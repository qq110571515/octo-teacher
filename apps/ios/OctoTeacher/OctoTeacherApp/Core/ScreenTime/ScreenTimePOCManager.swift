import Foundation
import Observation

#if canImport(FamilyControls) && canImport(ManagedSettings)
import DeviceActivity
import FamilyControls
import ManagedSettings

protocol ScreenTimeUsageWindowScheduling {
    func noteUsageWindow(
        named activityName: String,
        from startDate: Date,
        until endDate: Date,
        selection: FamilyActivitySelection
    ) throws
    func cancelUsageWindows(named activityNames: [String])
}

struct NoopScreenTimeUsageWindowScheduler: ScreenTimeUsageWindowScheduling {
    func noteUsageWindow(
        named activityName: String,
        from startDate: Date,
        until endDate: Date,
        selection: FamilyActivitySelection
    ) throws {
        _ = activityName
        _ = startDate
        _ = endDate
        _ = selection
    }

    func cancelUsageWindows(named activityNames: [String]) { _ = activityNames }
}

struct DeviceActivityScreenTimeUsageWindowScheduler: ScreenTimeUsageWindowScheduling {
    func noteUsageWindow(
        named activityName: String,
        from startDate: Date,
        until endDate: Date,
        selection: FamilyActivitySelection
    ) throws {
        _ = selection
        let interval = try ScreenTimeUsageWindowSchedule.validatedInterval(
            startedAt: startDate,
            endsAt: endDate
        )
        let center = DeviceActivityCenter()
        let name = DeviceActivityName(activityName)
        let calendar = Calendar.current
        let components: Set<Calendar.Component> = [
            .era, .year, .month, .day, .hour, .minute, .second,
        ]
        var startComponents = calendar.dateComponents(components, from: interval.start)
        startComponents.calendar = calendar
        startComponents.timeZone = calendar.timeZone
        var endComponents = calendar.dateComponents(components, from: interval.end)
        endComponents.calendar = calendar
        endComponents.timeZone = calendar.timeZone
        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false
        )
        center.stopMonitoring([name])
        try center.startMonitoring(name, during: schedule)
    }

    func cancelUsageWindows(named activityNames: [String]) {
        let names = Set(activityNames).map { DeviceActivityName($0) }
        guard !names.isEmpty else { return }
        DeviceActivityCenter().stopMonitoring(names)
    }
}

protocol SchoolModeDeviceScheduling {
    func replaceSchedules(previousActivityNames: [String], with runtime: PersistedSchoolModeRuntime) throws
    func cancel(activityNames: [String])
}

struct DeviceActivitySchoolModeScheduler: SchoolModeDeviceScheduling {
    func replaceSchedules(previousActivityNames: [String], with runtime: PersistedSchoolModeRuntime) throws {
        let center = DeviceActivityCenter()
        center.stopMonitoring(previousActivityNames.map { DeviceActivityName($0) })
        guard runtime.isEnabled else { return }

        for rule in runtime.rules {
            let name = DeviceActivityName("\(ScreenTimeSharedContract.schoolActivityPrefix)weekly.\(rule.weekday)")
            var start = DateComponents()
            start.calendar = .current
            start.weekday = rule.weekday
            start.hour = rule.startMinutes / 60
            start.minute = rule.startMinutes % 60
            var end = DateComponents()
            end.calendar = .current
            end.weekday = rule.weekday
            end.hour = rule.endMinutes / 60
            end.minute = rule.endMinutes % 60
            let schedule = DeviceActivitySchedule(
                intervalStart: start,
                intervalEnd: end,
                repeats: true
            )
            try center.startMonitoring(name, during: schedule)
        }

        for exception in runtime.exceptions where !exception.isHoliday {
            let startMinutes = exception.startMinutes ?? runtime.defaultStartMinutes
            let endMinutes = exception.endMinutes ?? runtime.defaultEndMinutes
            guard let day = Self.dayComponents(from: exception.dateKey) else { continue }
            let name = DeviceActivityName("\(ScreenTimeSharedContract.schoolActivityPrefix)override.\(exception.dateKey)")
            let start = DateComponents(
                calendar: .current,
                year: day.year,
                month: day.month,
                day: day.day,
                hour: startMinutes / 60,
                minute: startMinutes % 60
            )
            let end = DateComponents(
                calendar: .current,
                year: day.year,
                month: day.month,
                day: day.day,
                hour: endMinutes / 60,
                minute: endMinutes % 60
            )
            try center.startMonitoring(name, during: DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: false))
        }
    }

    func cancel(activityNames: [String]) {
        DeviceActivityCenter().stopMonitoring(activityNames.map { DeviceActivityName($0) })
    }

    private static func dayComponents(from dateKey: String) -> DateComponents? {
        let parts = dateKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }
}

enum ScreenTimePOCAuthorizationState: String {
    case unavailable
    case notDetermined
    case denied
    case approved
    case unknown

    var label: String {
        switch self {
        case .unavailable: return "不可用"
        case .notDetermined: return "未请求"
        case .denied: return "已拒绝"
        case .approved: return "已授权"
        case .unknown: return "未知"
        }
    }
}

struct ScreenTimeSelectionCounts: Equatable {
    var applications: Int
    var categories: Int
    var webDomains: Int

    static let empty = ScreenTimeSelectionCounts(applications: 0, categories: 0, webDomains: 0)

    var hasSelection: Bool {
        applications > 0 || categories > 0 || webDomains > 0
    }
}

struct ScreenTimeSelectionStore {
    private let fallbackDefaults = UserDefaults.standard

    var storageLabel: String {
        appGroupDefaults == nil ? "Standard UserDefaults" : "App Group UserDefaults"
    }

    var usesSharedAppGroup: Bool { appGroupDefaults != nil }

    func load() -> FamilyActivitySelection {
        guard let data = defaults.data(forKey: ScreenTimeSharedContract.selectionKey),
              let selection = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
        else {
            return Self.emptyExpandedSelection()
        }
        return selection
    }

    static func emptyExpandedSelection() -> FamilyActivitySelection {
        FamilyActivitySelection(includeEntireCategory: false)
    }

    /// Category-expanding pickers return the currently installed apps inside each selected
    /// category. Preserve those tokens as precise apps while retaining the category policy for
    /// future installs. The aggregate capacity check rejects an unsafe oversized expansion.
    static func normalizedForExplicitCategorySelection(
        _ selection: FamilyActivitySelection
    ) -> (selection: FamilyActivitySelection, changed: Bool, droppedExpandedApplications: Bool) {
        guard selection.includeEntireCategory else {
            return (selection, false, false)
        }

        var normalized = FamilyActivitySelection(includeEntireCategory: false)
        normalized.applicationTokens = selection.applicationTokens
        normalized.categoryTokens = selection.categoryTokens
        normalized.webDomainTokens = selection.webDomainTokens
        return (
            normalized,
            true,
            false
        )
    }

    static func categoryExpandingPickerSelection(
        from selection: FamilyActivitySelection
    ) -> FamilyActivitySelection {
        var expanded = FamilyActivitySelection(includeEntireCategory: true)
        expanded.applicationTokens = selection.applicationTokens
        expanded.categoryTokens = selection.categoryTokens
        expanded.webDomainTokens = selection.webDomainTokens
        return expanded
    }

    func save(_ selection: FamilyActivitySelection) throws {
        let key = ScreenTimeSharedContract.selectionKey
        let previous = defaults.object(forKey: key)
        let data = try PropertyListEncoder().encode(selection)
        defaults.set(data, forKey: key)
        guard defaults.data(forKey: key) == data, load() == selection else {
            restore(previous, forKey: key)
            throw ScreenTimeRewardWindowPersistenceError.writeVerificationFailed
        }
    }

    func clear() {
        defaults.removeObject(forKey: ScreenTimeSharedContract.selectionKey)
    }

    private var defaults: UserDefaults {
        appGroupDefaults ?? fallbackDefaults
    }

    private var appGroupDefaults: UserDefaults? {
        UserDefaults(suiteName: AppGroupKeys.groupIdentifier)
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

enum ScreenTimeSingleAppUnlockAuthority: Equatable {
    case growthPoints
    case parentPIN

    var maximumMinutes: Int {
        switch self {
        case .growthPoints: return 60
        case .parentPIN: return 24 * 60
        }
    }
}

enum ScreenTimeAuthorizationPurpose: String, Equatable {
    case childFamily
}

struct ScreenTimeAuthorizationPurposeStore {
    private let defaults: UserDefaults
    private let legacyDefaults: UserDefaults?

    init() {
        let shared = UserDefaults(suiteName: AppGroupKeys.groupIdentifier)
        defaults = shared ?? .standard
        legacyDefaults = shared == nil ? nil : .standard
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        legacyDefaults = nil
    }

    var purpose: ScreenTimeAuthorizationPurpose? {
        let key = ScreenTimeSharedContract.authorizationPurposeKey
        if let rawValue = defaults.string(forKey: key) {
            return ScreenTimeAuthorizationPurpose(rawValue: rawValue)
        }
        guard let rawValue = legacyDefaults?.string(forKey: key),
              let purpose = ScreenTimeAuthorizationPurpose(rawValue: rawValue) else { return nil }
        defaults.set(rawValue, forKey: key)
        return purpose
    }

    func save(_ purpose: ScreenTimeAuthorizationPurpose) {
        defaults.set(purpose.rawValue, forKey: ScreenTimeSharedContract.authorizationPurposeKey)
        legacyDefaults?.set(purpose.rawValue, forKey: ScreenTimeSharedContract.authorizationPurposeKey)
    }

    func clear() {
        defaults.removeObject(forKey: ScreenTimeSharedContract.authorizationPurposeKey)
        legacyDefaults?.removeObject(forKey: ScreenTimeSharedContract.authorizationPurposeKey)
    }
}

protocol ScreenTimeRewardWindowPersisting {
    var containsLegacyWindow: Bool { get }
    func loadAll() -> [PersistedScreenTimeRewardWindow]
    func saveAll(_ windows: [PersistedScreenTimeRewardWindow]) throws
    func clear() throws
}

extension ScreenTimeRewardWindowPersisting {
    var containsLegacyWindow: Bool { false }
}

enum ScreenTimeRewardWindowPersistenceError: Error {
    case sharedAppGroupUnavailable
    case writeVerificationFailed
    case unreadableCompensation
}

private enum ScreenTimeSharedAppGroupStorage {
    static func verifiedDefaults() -> UserDefaults? {
        guard FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroupKeys.groupIdentifier
        ) != nil else { return nil }
        return UserDefaults(suiteName: AppGroupKeys.groupIdentifier)
    }
}

enum SchoolModeSynchronizationTransaction {
    static func commit(
        previous: PersistedSchoolModeRuntime?,
        desired: PersistedSchoolModeRuntime,
        replaceSchedules: () throws -> Void,
        persistRuntime: () throws -> Void,
        applyCurrentState: () throws -> Void,
        rollback: () -> Void
    ) throws {
        do {
            if previous != desired {
                try replaceSchedules()
                try persistRuntime()
            }
            try applyCurrentState()
        } catch {
            rollback()
            throw error
        }
    }
}

struct ScreenTimeRewardWindowStore: ScreenTimeRewardWindowPersisting {
    private let explicitDefaults: UserDefaults?

    init(defaults: UserDefaults? = nil) {
        explicitDefaults = defaults
    }

    var containsLegacyWindow: Bool {
        defaults.data(forKey: ScreenTimeSharedContract.activeRewardWindowKey) != nil
    }

    func loadAll() -> [PersistedScreenTimeRewardWindow] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = defaults.data(forKey: ScreenTimeSharedContract.activeRewardWindowsKey),
           let windows = try? decoder.decode([PersistedScreenTimeRewardWindow].self, from: data) {
            return windows.map { $0.normalized() }
        }
        guard let legacyData = defaults.data(forKey: ScreenTimeSharedContract.activeRewardWindowKey),
              let legacy = try? decoder.decode(PersistedScreenTimeRewardWindow.self, from: legacyData)
        else { return [] }
        return [legacy.normalized()]
    }

    func saveAll(_ windows: [PersistedScreenTimeRewardWindow]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard !windows.isEmpty else {
            try clear()
            return
        }
        let data = try encoder.encode(windows.map { $0.normalized() })
        let previousWindows = defaults.object(forKey: ScreenTimeSharedContract.activeRewardWindowsKey)
        let previousLegacy = defaults.object(forKey: ScreenTimeSharedContract.activeRewardWindowKey)
        defaults.set(data, forKey: ScreenTimeSharedContract.activeRewardWindowsKey)
        defaults.removeObject(forKey: ScreenTimeSharedContract.activeRewardWindowKey)
        guard defaults.data(forKey: ScreenTimeSharedContract.activeRewardWindowsKey) == data,
              defaults.object(forKey: ScreenTimeSharedContract.activeRewardWindowKey) == nil else {
            restore(previousWindows, forKey: ScreenTimeSharedContract.activeRewardWindowsKey)
            restore(previousLegacy, forKey: ScreenTimeSharedContract.activeRewardWindowKey)
            throw ScreenTimeRewardWindowPersistenceError.writeVerificationFailed
        }
    }

    func clear() throws {
        let previousWindows = defaults.object(forKey: ScreenTimeSharedContract.activeRewardWindowsKey)
        let previousLegacy = defaults.object(forKey: ScreenTimeSharedContract.activeRewardWindowKey)
        defaults.removeObject(forKey: ScreenTimeSharedContract.activeRewardWindowsKey)
        defaults.removeObject(forKey: ScreenTimeSharedContract.activeRewardWindowKey)
        guard defaults.object(forKey: ScreenTimeSharedContract.activeRewardWindowsKey) == nil,
              defaults.object(forKey: ScreenTimeSharedContract.activeRewardWindowKey) == nil else {
            restore(previousWindows, forKey: ScreenTimeSharedContract.activeRewardWindowsKey)
            restore(previousLegacy, forKey: ScreenTimeSharedContract.activeRewardWindowKey)
            throw ScreenTimeRewardWindowPersistenceError.writeVerificationFailed
        }
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private var defaults: UserDefaults {
        explicitDefaults ?? UserDefaults(suiteName: AppGroupKeys.groupIdentifier) ?? .standard
    }
}

struct ScreenTimeRewardCompensationStore {
    private let explicitDefaults: UserDefaults?

    init(defaults: UserDefaults? = nil) {
        explicitDefaults = defaults
    }

    func load() -> [PersistedScreenTimeRewardCompensation] {
        (try? loadVerified()) ?? []
    }

    var isReadable: Bool {
        (try? loadVerified()) != nil
    }

    func add(id: UUID, requestedAt: Date) throws {
        try add(ids: [id], requestedAt: requestedAt)
    }

    func add(ids: [UUID], requestedAt: Date) throws {
        let updated = try ids.reduce(loadVerified()) { compensations, id in
            ScreenTimeRewardCompensationLedger.adding(
                id: id,
                at: requestedAt,
                to: compensations
            )
        }
        try save(updated)
    }

    func remove(ids: Set<UUID>) throws {
        try save(ScreenTimeRewardCompensationLedger.removing(ids: ids, from: loadVerified()))
    }

    func clear() throws {
        try save([])
    }

    private func save(_ compensations: [PersistedScreenTimeRewardCompensation]) throws {
        let key = ScreenTimeSharedContract.pendingRewardCompensationsKey
        let previous = defaults.object(forKey: key)
        if compensations.isEmpty {
            defaults.removeObject(forKey: key)
            guard defaults.object(forKey: key) == nil else {
                restore(previous, forKey: key)
                throw ScreenTimeRewardWindowPersistenceError.writeVerificationFailed
            }
            return
        }

        let data = try JSONEncoder().encode(compensations)
        defaults.set(data, forKey: key)
        guard defaults.data(forKey: key) == data else {
            restore(previous, forKey: key)
            throw ScreenTimeRewardWindowPersistenceError.writeVerificationFailed
        }
    }

    private func loadVerified() throws -> [PersistedScreenTimeRewardCompensation] {
        let key = ScreenTimeSharedContract.pendingRewardCompensationsKey
        guard let data = defaults.data(forKey: key) else { return [] }
        guard let compensations = try? JSONDecoder().decode(
            [PersistedScreenTimeRewardCompensation].self,
            from: data
        ) else {
            throw ScreenTimeRewardWindowPersistenceError.unreadableCompensation
        }
        return compensations
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private var defaults: UserDefaults {
        explicitDefaults ?? UserDefaults(suiteName: AppGroupKeys.groupIdentifier) ?? .standard
    }
}

struct SchoolModeRuntimeStore {
    private let explicitDefaults: UserDefaults?
    let usesSharedAppGroup: Bool

    init() {
        let defaults = ScreenTimeSharedAppGroupStorage.verifiedDefaults()
        explicitDefaults = defaults
        usesSharedAppGroup = defaults != nil
    }

    init(defaults: UserDefaults?, usesSharedAppGroup: Bool) {
        explicitDefaults = defaults
        self.usesSharedAppGroup = usesSharedAppGroup && defaults != nil
    }

    func load() -> PersistedSchoolModeRuntime? {
        guard let defaults,
              let data = defaults.data(forKey: ScreenTimeSharedContract.schoolRuntimeKey) else { return nil }
        return try? JSONDecoder().decode(PersistedSchoolModeRuntime.self, from: data)
    }

    func save(_ runtime: PersistedSchoolModeRuntime) throws {
        guard usesSharedAppGroup, let defaults = explicitDefaults else {
            throw ScreenTimeRewardWindowPersistenceError.sharedAppGroupUnavailable
        }
        let key = ScreenTimeSharedContract.schoolRuntimeKey
        let previous = defaults.object(forKey: key)
        let data = try JSONEncoder().encode(runtime)
        defaults.set(data, forKey: key)
        guard defaults.data(forKey: key) == data, load() == runtime else {
            restore(previous, forKey: key, defaults: defaults)
            throw ScreenTimeRewardWindowPersistenceError.writeVerificationFailed
        }
    }

    func clear() {
        explicitDefaults?.removeObject(forKey: ScreenTimeSharedContract.schoolRuntimeKey)
    }

    private var defaults: UserDefaults? { explicitDefaults }

    private func restore(_ value: Any?, forKey key: String, defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

struct ScreenTimeShieldActionStore {
    private let fallbackDefaults = UserDefaults.standard

    func load(at date: Date = Date()) -> PersistedShieldActionRequest? {
        guard let request = loadPersisted(), request.isValid(at: date) else {
            clear()
            return nil
        }
        return request
    }

    func loadPersisted() -> PersistedShieldActionRequest? {
        guard let data = defaults.data(forKey: ScreenTimeSharedContract.pendingShieldActionKey) else {
            return nil
        }
        return try? JSONDecoder().decode(PersistedShieldActionRequest.self, from: data)
    }

    func replace(_ request: PersistedShieldActionRequest?) throws {
        let key = ScreenTimeSharedContract.pendingShieldActionKey
        let previous = defaults.object(forKey: key)
        if let request {
            defaults.set(try JSONEncoder().encode(request), forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        guard loadPersisted() == request else {
            restore(previous, forKey: key)
            throw ScreenTimeRewardWindowPersistenceError.writeVerificationFailed
        }
    }

    func clear() {
        defaults.removeObject(forKey: ScreenTimeSharedContract.pendingShieldActionKey)
    }

    private var defaults: UserDefaults {
        UserDefaults(suiteName: AppGroupKeys.groupIdentifier) ?? fallbackDefaults
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

struct ScreenTimeEmergencyWindowStore {
    private let explicitDefaults: UserDefaults?
    let usesSharedAppGroup: Bool

    init() {
        let defaults = ScreenTimeSharedAppGroupStorage.verifiedDefaults()
        explicitDefaults = defaults
        usesSharedAppGroup = defaults != nil
    }

    init(defaults: UserDefaults?, usesSharedAppGroup: Bool) {
        explicitDefaults = defaults
        self.usesSharedAppGroup = usesSharedAppGroup && defaults != nil
    }

    func load() -> PersistedScreenTimeEmergencyWindow? {
        guard let defaults,
              let data = defaults.data(forKey: ScreenTimeSharedContract.activeEmergencyWindowKey) else { return nil }
        return try? JSONDecoder().decode(PersistedScreenTimeEmergencyWindow.self, from: data)
    }

    func save(_ window: PersistedScreenTimeEmergencyWindow) throws {
        guard usesSharedAppGroup, let defaults = explicitDefaults else {
            throw ScreenTimeRewardWindowPersistenceError.sharedAppGroupUnavailable
        }
        let key = ScreenTimeSharedContract.activeEmergencyWindowKey
        let previous = defaults.object(forKey: key)
        let data = try JSONEncoder().encode(window)
        defaults.set(data, forKey: key)
        guard defaults.data(forKey: key) == data, load() == window else {
            restore(previous, forKey: key, defaults: defaults)
            throw ScreenTimeRewardWindowPersistenceError.writeVerificationFailed
        }
    }

    func clear() {
        explicitDefaults?.removeObject(forKey: ScreenTimeSharedContract.activeEmergencyWindowKey)
    }

    private var defaults: UserDefaults? { explicitDefaults }

    private func restore(_ value: Any?, forKey key: String, defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

@MainActor
@Observable
final class ScreenTimePOCManager {
    var authorizationState: ScreenTimePOCAuthorizationState = .unknown
    var selection: FamilyActivitySelection
    var guardianCatalogSelection: FamilyActivitySelection
    var selectionCounts: ScreenTimeSelectionCounts = .empty
    var isShielded = false
    var unlockEndsAt: Date?
    var websiteSafetyIsApplied = false
    var websiteSafetyDomainCount = 0
    var schoolModeIsActive = false
    var schoolModeEndsAt: Date?
    var schoolModeLastError: String?
    var logs: [String] = []
    /// 最近一次授权请求的失败原因；请求立刻失败且无系统弹窗时，通常是签名缺少
    /// com.apple.developer.family-controls entitlement。
    var lastAuthorizationError: String?
    /// The most recent ManagedSettings/token failure. A saved picker selection is not
    /// considered proof that SpringBoard is enforcing the shield.
    var lastShieldError: String?
    private(set) var authorizationPurpose: ScreenTimeAuthorizationPurpose?
    private(set) var appliedPolicyRevision: Int?
    private(set) var guardianCatalog: FamilyScreenTimeCatalog?
    private(set) var guardianCatalogBinding: FamilyScreenTimeCatalogBinding?

    @ObservationIgnored
    private let selectionStore: ScreenTimeSelectionStore
    @ObservationIgnored
    private let shieldStore: ManagedSettingsStore
    @ObservationIgnored
    private let webSafetyStore: ManagedSettingsStore
    @ObservationIgnored
    private let schoolStore: ManagedSettingsStore
    @ObservationIgnored
    private let usageWindowScheduler: ScreenTimeUsageWindowScheduling
    @ObservationIgnored
    private let rewardWindowStore: any ScreenTimeRewardWindowPersisting
    @ObservationIgnored
    private let rewardCompensationStore: ScreenTimeRewardCompensationStore
    @ObservationIgnored
    private let schoolModeScheduler: any SchoolModeDeviceScheduling
    @ObservationIgnored
    private let schoolModeRuntimeStore: SchoolModeRuntimeStore
    @ObservationIgnored
    private let authorizationPurposeStore: ScreenTimeAuthorizationPurposeStore
    @ObservationIgnored
    private let shieldActionStore: ScreenTimeShieldActionStore
    @ObservationIgnored
    private let emergencyWindowStore: ScreenTimeEmergencyWindowStore
    @ObservationIgnored
    private var relockTask: Task<Void, Never>?

    init(
        selectionStore: ScreenTimeSelectionStore = ScreenTimeSelectionStore(),
        shieldStore: ManagedSettingsStore = ManagedSettingsStore(
            named: ManagedSettingsStore.Name(ScreenTimeSharedContract.rewardStoreName)
        ),
        webSafetyStore: ManagedSettingsStore = ManagedSettingsStore(
            named: ManagedSettingsStore.Name(ScreenTimeSharedContract.webSafetyStoreName)
        ),
        schoolStore: ManagedSettingsStore = ManagedSettingsStore(
            named: ManagedSettingsStore.Name(ScreenTimeSharedContract.schoolStoreName)
        ),
        usageWindowScheduler: ScreenTimeUsageWindowScheduling = DeviceActivityScreenTimeUsageWindowScheduler(),
        rewardWindowStore: any ScreenTimeRewardWindowPersisting = ScreenTimeRewardWindowStore(),
        rewardCompensationStore: ScreenTimeRewardCompensationStore = ScreenTimeRewardCompensationStore(),
        schoolModeScheduler: any SchoolModeDeviceScheduling = DeviceActivitySchoolModeScheduler(),
        schoolModeRuntimeStore: SchoolModeRuntimeStore = SchoolModeRuntimeStore(),
        authorizationPurposeStore: ScreenTimeAuthorizationPurposeStore = ScreenTimeAuthorizationPurposeStore(),
        shieldActionStore: ScreenTimeShieldActionStore = ScreenTimeShieldActionStore(),
        emergencyWindowStore: ScreenTimeEmergencyWindowStore = ScreenTimeEmergencyWindowStore()
    ) {
        self.selectionStore = selectionStore
        self.shieldStore = shieldStore
        self.webSafetyStore = webSafetyStore
        self.schoolStore = schoolStore
        self.usageWindowScheduler = usageWindowScheduler
        self.rewardWindowStore = rewardWindowStore
        self.rewardCompensationStore = rewardCompensationStore
        self.schoolModeScheduler = schoolModeScheduler
        self.schoolModeRuntimeStore = schoolModeRuntimeStore
        self.authorizationPurposeStore = authorizationPurposeStore
        self.shieldActionStore = shieldActionStore
        self.emergencyWindowStore = emergencyWindowStore
        self.authorizationPurpose = authorizationPurposeStore.purpose
        let storedRevision = UserDefaults(suiteName: AppGroupKeys.groupIdentifier)?
            .object(forKey: ScreenTimeSharedContract.appliedPolicyRevisionKey) as? Int
        self.appliedPolicyRevision = storedRevision
        self.schoolModeIsActive = UserDefaults(suiteName: AppGroupKeys.groupIdentifier)?
            .bool(forKey: ScreenTimeSharedContract.schoolModeActiveKey) ?? false
        let restored = selectionStore.load()
        let normalized = ScreenTimeSelectionStore.normalizedForExplicitCategorySelection(restored)
        self.selection = normalized.selection
        self.guardianCatalogSelection = ScreenTimeSelectionStore.emptyExpandedSelection()
        self.selectionCounts = Self.counts(for: normalized.selection)
        if normalized.changed {
            try? selectionStore.save(normalized.selection)
            ScreenTimeSharedContract.advanceSelectionGeneration(
                defaults: UserDefaults(suiteName: AppGroupKeys.groupIdentifier)
            )
            UserDefaults(suiteName: AppGroupKeys.groupIdentifier)?
                .removeObject(forKey: ScreenTimeSharedContract.pendingShieldActionKey)
        } else if self.selectionCounts.hasSelection,
                  ScreenTimeSharedContract.currentSelectionGeneration(
                    defaults: UserDefaults(suiteName: AppGroupKeys.groupIdentifier)
                  ) == 0 {
            ScreenTimeSharedContract.advanceSelectionGeneration(
                defaults: UserDefaults(suiteName: AppGroupKeys.groupIdentifier)
            )
        }
        if normalized.droppedExpandedApplications {
            UserDefaults(suiteName: AppGroupKeys.groupIdentifier)?.set(
                true,
                forKey: ScreenTimeSharedContract.selectionRequiresExplicitAppReselectionKey
            )
        }
        refreshAuthorizationStatus()
        appendLog("Loaded selection from \(selectionStore.storageLabel).")
        restoreRewardWindowIfNeeded()
        restoreEmergencyWindowIfNeeded()
        syncShieldStateFromStore(operation: "manager_init")
    }

    deinit {
        relockTask?.cancel()
    }

    var canControlSelectedApps: Bool {
        isChildFamilyAuthorizationReady && applicationShieldStrategy.isSupported
    }

    var applicationShieldStrategy: ScreenTimeSharedContract.ApplicationShieldStrategy {
        ScreenTimeSharedContract.applicationShieldStrategy(
            applicationCount: selection.applicationTokens.count,
            categoryCount: selection.categoryTokens.count
        )
    }

    var usesCombinedApplicationAndCategoryShield: Bool {
        applicationShieldStrategy == .applicationsAndCategories
    }

    var requiresExplicitAppReselection: Bool {
        sharedDefaults.bool(forKey: ScreenTimeSharedContract.selectionRequiresExplicitAppReselectionKey)
    }

    var isChildFamilyAuthorizationReady: Bool {
        authorizationState == .approved && authorizationPurpose == .childFamily
    }

    var hasLocalChildSelection: Bool {
        sharedDefaults.bool(forKey: ScreenTimeSharedContract.localChildSelectionCompletedKey) &&
            selectionCounts.hasSelection
    }

    var localChildSetupIsComplete: Bool {
        isChildFamilyAuthorizationReady &&
            (hasLocalChildSelection || hasSyncedGuardianPolicy) &&
            applicationShieldStrategy.isSupported
    }

    var hasSyncedGuardianPolicy: Bool {
        appliedPolicyRevision != nil ||
            sharedDefaults.bool(forKey: ScreenTimeSharedContract.syncedGuardianPolicyKey)
    }

    var guardianCatalogBindingIsCurrent: Bool {
        guard let guardianCatalogBinding else { return true }
        return guardianCatalog?.binding == guardianCatalogBinding
    }

    /// Broad category shields can lock apps, but only explicitly selected application tokens
    /// support reliable single-app Growth Point or parent PIN unlocks.
    var preciseSingleAppUnlockIsReady: Bool {
        isChildFamilyAuthorizationReady &&
            selectionStore.usesSharedAppGroup &&
            ScreenTimeSharedContract.singleApplicationUnlockSelectionIsReady(
                applicationCount: selection.applicationTokens.count
            )
    }

    /// 主奖励链路是否可以把已批准的屏幕时间兑换交给真实 Screen Time 执行面。
    var canStartRewardWindow: Bool { canControlSelectedApps && !schoolModeBlocksRewardUnlock }

    /// A single-app reward window requires an explicit app token. Category callbacks use a
    /// separate category-scoped window because Apple intentionally withholds the tapped app.
    var canStartSingleAppRewardWindow: Bool {
        isChildFamilyAuthorizationReady &&
            selectionStore.usesSharedAppGroup &&
            ScreenTimeSharedContract.singleApplicationUnlockSelectionIsReady(
                applicationCount: selection.applicationTokens.count
            ) &&
            !schoolModeBlocksRewardUnlock
    }

    func canStartSingleAppRewardWindow(
        applicationToken: ApplicationToken?,
        shieldRequestID: UUID?,
        at date: Date = Date()
    ) -> Bool {
        guard isChildFamilyAuthorizationReady,
              selectionStore.usesSharedAppGroup,
              !schoolModeBlocksRewardUnlock,
              let applicationToken
        else {
            return false
        }

        if selection.applicationTokens.contains(applicationToken) {
            return true
        }

        guard let shieldRequestID else {
            return false
        }

        return isValidShieldApplicationRequest(
            id: shieldRequestID,
            token: applicationToken,
            at: date
        )
    }

    func canStartCategoryRewardWindow(
        categoryToken: ActivityCategoryToken?,
        shieldRequestID: UUID?,
        at date: Date = Date()
    ) -> Bool {
        guard isChildFamilyAuthorizationReady,
              selectionStore.usesSharedAppGroup,
              !schoolModeBlocksRewardUnlock,
              let categoryToken,
              selection.categoryTokens.contains(categoryToken),
              let shieldRequestID
        else {
            return false
        }
        return isValidShieldCategoryRequest(
            id: shieldRequestID,
            token: categoryToken,
            at: date
        )
    }

    /// All-app emergency access must survive app relaunches and cloud refreshes until expiry.
    var emergencyUnlockIsActive: Bool {
        guard let window = emergencyWindowStore.load() else { return false }
        return window.endsAt > Date()
    }

    var temporaryUnlockIsActive: Bool {
        !activeRewardWindows(at: Date()).isEmpty
    }

    var activeRewardWindowCount: Int {
        activeRewardWindows(at: Date()).count
    }

    func rewardWindowEnd(for applicationToken: ApplicationToken, at date: Date = Date()) -> Date? {
        guard let tokenData = try? PropertyListEncoder().encode(applicationToken) else { return nil }
        return activeRewardWindows(at: date)
            .first {
                $0.resolvedTargetKind == .application &&
                    $0.applicationTokenData == tokenData
            }?
            .endsAt
    }

    func rewardWindowEnd(for categoryToken: ActivityCategoryToken, at date: Date = Date()) -> Date? {
        guard let tokenData = try? PropertyListEncoder().encode(categoryToken) else { return nil }
        return activeRewardWindows(at: date)
            .first {
                $0.resolvedTargetKind == .category &&
                    $0.applicationTokenData == tokenData
            }?
            .endsAt
    }

    func rewardWindowIsActive(for applicationToken: ApplicationToken, at date: Date = Date()) -> Bool {
        rewardWindowEnd(for: applicationToken, at: date) != nil
    }

    var rewardWindowReadinessLabel: String {
        rewardWindowReadinessLabel(for: .chinese)
    }

    /// 兑换执行面就绪状态（孩子可见，跟随孩子界面语言）。
    func rewardWindowReadinessLabel(for language: AppInterfaceLanguage) -> String {
        if schoolModeBlocksRewardUnlock {
            return language.pick(
                "现在是学校时段，成长积分不会被扣除；放学后再兑换屏幕时间。",
                "School hours are active. No Growth Points will be charged; trade for screen time after school."
            )
        }
        if !isChildFamilyAuthorizationReady {
            if selectionCounts.hasSelection {
                return language.pick(
                    "这台手机已选的 App 还在；请重新连接 Apple 家庭控制授权。",
                    "The apps selected on this phone are still saved. Reconnect Apple Family Controls."
                )
            }
            return language.pick(
                "请让家长在这台孩子手机完成一次 Apple 家庭控制授权；App 清单由家长手机发布。",
                "Ask a parent to authorize Apple Family Controls once on this child phone. The guardian phone publishes the app list."
            )
        }
        if selection.applicationTokens.isEmpty, selection.categoryTokens.isEmpty {
            return language.pick(
                "正在等待家长手机发布要管理的 App 或分类。",
                "Waiting for the guardian phone to publish managed apps or categories."
            )
        }
        if !selectionStore.usesSharedAppGroup {
            return language.pick(
                "App Group 尚未生效；为确保后台到期重锁，当前禁止兑换。",
                "App Group isn't active. Exchanges stay disabled so background relocking remains reliable."
            )
        }
        return language.pick(
            "真实 Screen Time 已准备好；孩子每次最多只打开所点的一个 App 60 分钟。",
            "Real Screen Time is ready. Each trade opens only the tapped app for at most 60 minutes."
        )
    }

    func refreshAuthorizationStatus() {
        authorizationState = Self.mapAuthorizationStatus(AuthorizationCenter.shared.authorizationStatus)
    }

    func requestChildFamilyAuthorization() async {
        lastAuthorizationError = nil
        do {
            if authorizationState == .approved, authorizationPurpose != .childFamily {
                try await revokeCurrentAuthorization()
                refreshAuthorizationStatus()
            }
            clearAllDeviceEnforcement(clearSelection: false)
            try await AuthorizationCenter.shared.requestAuthorization(for: .child)
            refreshAuthorizationStatus()
            guard authorizationState == .approved else {
                throw ScreenTimeRoleError.childAuthorizationNotApproved
            }
            authorizationPurposeStore.save(.childFamily)
            authorizationPurpose = .childFamily
            if selectionCounts.hasSelection {
                if !hasSyncedGuardianPolicy {
                    sharedDefaults.set(
                        true,
                        forKey: ScreenTimeSharedContract.localChildSelectionCompletedKey
                    )
                }
                shieldSelection()
                appendLog("Restored the saved Screen Time policy after authorization.")
            }
            lastAuthorizationError = nil
            appendLog("FamilyControls child-family authorization: \(authorizationState.label).")
        } catch {
            refreshAuthorizationStatus()
            lastAuthorizationError = error.localizedDescription
            appendLog("Child-family authorization request failed: \(error.localizedDescription)")
        }
    }

    func childAuthorizationGuidance(for language: AppInterfaceLanguage) -> String {
        if !isChildFamilyAuthorizationReady {
            return language.pick(
                "请让家长在这台孩子手机批准一次 Apple 家庭控制。以后 App 清单全部由家长手机发布。",
                "Ask a parent to approve Apple Family Controls once on this child phone. The guardian phone publishes all app policies afterward."
            )
        }
        if hasSyncedGuardianPolicy {
            return language.pick(
                "家长发布的 App 规则已在这台手机生效。",
                "The app policy published by the guardian is active on this phone."
            )
        }
        return language.pick(
            "设备授权已完成，正在等待家长手机发布 App 规则。",
            "Device authorization is complete. Waiting for the guardian phone to publish an app policy."
        )
    }

    func childAuthorizationFailureGuidance(for language: AppInterfaceLanguage) -> String {
        language.pick(
            "Apple 没有批准这台孩子手机。请在 iPhone“设置 > 家庭”中确认孩子使用自己的儿童 Apple 账户并已加入家庭共享，然后重新连接。App 清单仍由家长手机管理。",
            "Apple did not approve this child phone. In iPhone Settings > Family, confirm the child uses a child Apple Account in Family Sharing, then reconnect. The guardian phone still owns the app list."
        )
    }

    @available(*, deprecated, message: "Use requestChildFamilyAuthorization() so this app never controls the guardian's own device.")
    func requestAuthorization() async {
        await requestChildFamilyAuthorization()
    }

    /// Build 53 and earlier requested `.individual`, which applies shields to the guardian's
    /// own phone. Until a child-family authorization is recorded, clear every local store and
    /// discard those device-scoped tokens before allowing another Screen Time action.
    func migrateLegacyIndividualAuthorizationIfNeeded(isChildDevice: Bool) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: ScreenTimeSharedContract.legacyMigrationCompletedKey) else { return }
        refreshAuthorizationStatus()
        let cleanupVerified: Bool
        if authorizationPurpose == .childFamily {
            cleanupVerified = sharedDefaults.bool(
                forKey: ScreenTimeSharedContract.staleEnforcementResetCompletedKey
            ) || defaults.bool(forKey: ScreenTimeSharedContract.staleEnforcementResetCompletedKey)
        } else {
            // A device-scoped selection is inert after its ManagedSettings stores are cleared.
            // Preserve it so a reinstall or a transient authorization read never forces the
            // parent to rebuild the child's app catalog.
            cleanupVerified = clearAllDeviceEnforcement(clearSelection: false)
        }
        guard cleanupVerified else {
            appendLog("Legacy Screen Time cleanup was not verified; migration remains pending.")
            return
        }
        defaults.set(true, forKey: ScreenTimeSharedContract.legacyMigrationCompletedKey)
        guard defaults.bool(forKey: ScreenTimeSharedContract.legacyMigrationCompletedKey) else {
            appendLog("Legacy Screen Time migration marker could not be verified.")
            return
        }
        if authorizationPurpose != .childFamily {
            appendLog(isChildDevice
                ? "Child device waits for guardian-approved child authorization."
                : "Cleared legacy individual controls from guardian device.")
        }
    }

    /// Build 56 could leave named ManagedSettings stores active after its UI state or saved
    /// selection had drifted away. Clear only Screen Time execution state once on every phone.
    /// Family, task, reward, book, and account data are intentionally untouched.
    @discardableResult
    func resetStaleDeviceEnforcementIfNeeded() -> Bool {
        let defaults = UserDefaults.standard
        let action = ScreenTimeSharedContract.staleEnforcementResetAction(
            sharedMarkerIsSet: sharedDefaults.bool(
                forKey: ScreenTimeSharedContract.staleEnforcementResetCompletedKey
            ),
            standardMarkerIsSet: defaults.bool(
                forKey: ScreenTimeSharedContract.staleEnforcementResetCompletedKey
            )
        )
        switch action {
        case .skip:
            defaults.set(true, forKey: ScreenTimeSharedContract.staleEnforcementResetCompletedKey)
            return false
        case .adoptStandardMarker:
            sharedDefaults.set(true, forKey: ScreenTimeSharedContract.staleEnforcementResetCompletedKey)
            appendLog("Copied the completed Screen Time reset marker into shared storage.")
            return false
        case .clearExecutionStatePreservingSelection:
            break
        }

        let previousRevision = appliedPolicyRevision
        let previousHash = appliedPolicySelectionHash
        let previousControlCommandID = appliedControlCommandID
        let previousControlMode = appliedControlMode
        let previousControlUnlockUntil = appliedControlUnlockUntil
        let previousWasSynced = hasSyncedGuardianPolicy
        guard clearAllDeviceEnforcement(clearSelection: false) else {
            appendLog("Stale Screen Time cleanup was not verified; reset remains pending.")
            return false
        }
        restoreAppliedGuardianPolicy(
            revision: previousRevision,
            selectionHash: previousHash,
            controlCommandID: previousControlCommandID,
            controlMode: previousControlMode,
            controlUnlockUntil: previousControlUnlockUntil,
            wasSynced: previousWasSynced
        )
        sharedDefaults.set(true, forKey: ScreenTimeSharedContract.staleEnforcementResetCompletedKey)
        defaults.set(true, forKey: ScreenTimeSharedContract.staleEnforcementResetCompletedKey)
        guard sharedDefaults.bool(forKey: ScreenTimeSharedContract.staleEnforcementResetCompletedKey),
              defaults.bool(forKey: ScreenTimeSharedContract.staleEnforcementResetCompletedKey) else {
            appendLog("Stale Screen Time reset marker could not be verified.")
            return false
        }
        if (hasLocalChildSelection || previousWasSynced), isChildFamilyAuthorizationReady {
            _ = shieldSelection()
            if previousControlMode == .unlocked,
               let previousControlCommandID,
               let previousControlUnlockUntil {
                _ = reconcileGuardianControl(
                    FamilyScreenTimeControl(
                        schemaVersion: 1,
                        commandId: previousControlCommandID,
                        mode: .unlocked,
                        issuedAt: "",
                        unlockUntil: previousControlUnlockUntil
                    )
                )
            }
        }
        appendLog("Cleared stale Screen Time execution state while preserving the child-device app selection.")
        return true
    }

    func makeGuardianPolicy(revision: Int, updatedAt: String) throws -> FamilyScreenTimePolicy {
        let normalized = ScreenTimeSelectionStore.normalizedForExplicitCategorySelection(selection).selection
        let counts = Self.counts(for: normalized)
        let data = try PropertyListEncoder().encode(normalized)
        let selectionData = data.base64EncodedString()
        return FamilyScreenTimePolicy(
            revision: revision,
            selectionData: selectionData,
            selectionHash: FamilyScreenTimePolicy.hash(selectionData: selectionData),
            applicationCount: counts.applications,
            categoryCount: counts.categories,
            webDomainCount: counts.webDomains,
            catalogBinding: guardianCatalogBinding,
            updatedAt: updatedAt
        )
    }

    func makeChildCatalogUpload(
        from sourceSelection: FamilyActivitySelection,
        capturedAt: String
    ) throws -> FamilyScreenTimeCatalogUpload {
        let normalized = ScreenTimeSelectionStore
            .normalizedForExplicitCategorySelection(sourceSelection).selection
        let counts = Self.counts(for: normalized)
        let selectionData = try PropertyListEncoder().encode(normalized).base64EncodedString()
        return FamilyScreenTimeCatalogUpload(
            selectionData: selectionData,
            selectionHash: FamilyScreenTimePolicy.hash(selectionData: selectionData),
            applicationCount: counts.applications,
            categoryCount: counts.categories,
            webDomainCount: counts.webDomains,
            capturedAt: capturedAt
        )
    }

    func loadGuardianCatalog(_ catalog: FamilyScreenTimeCatalog?) {
        guardianCatalog = catalog
        guard let catalog,
              catalog.schemaVersion == FamilyScreenTimeCatalog.currentSchemaVersion,
              catalog.hasValidSelectionHash,
              let data = Data(base64Encoded: catalog.selectionData),
              let decoded = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
        else {
            guardianCatalogSelection = ScreenTimeSelectionStore.emptyExpandedSelection()
            guardianCatalogBinding = nil
            return
        }
        guardianCatalogSelection = ScreenTimeSelectionStore
            .normalizedForExplicitCategorySelection(decoded).selection
        if guardianCatalogBinding?.revision != catalog.revision ||
            guardianCatalogBinding?.selectionHash != catalog.selectionHash {
            guardianCatalogBinding = nil
        }
    }

    func useCompleteGuardianCatalog() {
        guard let catalog = guardianCatalog, catalog.hasValidSelectionHash else { return }
        selection = guardianCatalogSelection
        selectionCounts = Self.counts(for: selection)
        guardianCatalogBinding = catalog.binding
    }

    func clearGuardianCatalogApplications() {
        selection.applicationTokens = []
        selectionCounts = Self.counts(for: selection)
        guardianCatalogBinding = guardianCatalog?.binding
    }

    func toggleGuardianCatalogApplication(_ token: ApplicationToken) {
        if selection.applicationTokens.contains(token) {
            selection.applicationTokens.remove(token)
        } else {
            selection.applicationTokens.insert(token)
        }
        selectionCounts = Self.counts(for: selection)
        guardianCatalogBinding = guardianCatalog?.binding
    }

    func clearGuardianCatalogBinding() {
        guardianCatalogBinding = nil
    }

    func prepareGuardianSelectionForPicker() {
        selection = ScreenTimeSelectionStore.normalizedForExplicitCategorySelection(selection).selection
        selectionCounts = Self.counts(for: selection)
        guardianCatalogBinding = nil
    }

    func refreshGuardianDraftCounts() {
        let normalized = ScreenTimeSelectionStore.normalizedForExplicitCategorySelection(selection).selection
        selectionCounts = Self.counts(for: normalized)
    }

    /// Loads a guardian-side draft without touching ManagedSettings on this device.
    /// Guardian phones may author a policy, but only a linked child phone may enforce it.
    func loadGuardianDraft(_ policy: FamilyScreenTimePolicy?) {
        guard let policy,
              policy.schemaVersion == FamilyScreenTimePolicy.currentSchemaVersion,
              policy.hasValidSelectionHash,
              let data = Data(base64Encoded: policy.selectionData),
              let decoded = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
        else {
            selection = ScreenTimeSelectionStore.categoryExpandingPickerSelection(
                from: ScreenTimeSelectionStore.emptyExpandedSelection()
            )
            selectionCounts = .empty
            guardianCatalogBinding = nil
            return
        }
        selection = ScreenTimeSelectionStore.normalizedForExplicitCategorySelection(decoded).selection
        selectionCounts = Self.counts(for: decoded)
        guardianCatalogBinding = policy.catalogBinding
    }

    @discardableResult
    func applySyncedPolicy(_ policy: FamilyScreenTimePolicy?) -> FamilyScreenTimeDeviceStatus {
        refreshAuthorizationStatus()
        guard isChildFamilyAuthorizationReady else {
            return currentDeviceStatus(enforcement: .waitingForAuthorization)
        }

        guard let policy else {
            guard clearAllDeviceEnforcement(clearSelection: true) else {
                return currentDeviceStatus(
                    enforcement: .error,
                    errorCode: "policy_reset_failed"
                )
            }
            clearAppliedGuardianPolicy()
            appendLog("Cleared device-local Screen Time state while waiting for a guardian policy.")
            return currentDeviceStatus(enforcement: .waitingForPolicy)
        }

        guard policy.schemaVersion == FamilyScreenTimePolicy.currentSchemaVersion else {
            return currentDeviceStatus(
                enforcement: .error,
                errorCode: "unsupported_policy_schema"
            )
        }
        guard let policyHash = policy.selectionHash,
              policy.hasValidSelectionHash,
              let data = Data(base64Encoded: policy.selectionData),
              let decoded = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
        else {
            return currentDeviceStatus(
                enforcement: .error,
                errorCode: "policy_integrity_failed"
            )
        }
        let normalized = ScreenTimeSelectionStore.normalizedForExplicitCategorySelection(decoded).selection
        let decodedCounts = Self.counts(for: normalized)
        guard decodedCounts.applications == policy.applicationCount,
              decodedCounts.categories == policy.categoryCount,
              decodedCounts.webDomains == policy.webDomainCount
        else {
            return currentDeviceStatus(
                enforcement: .error,
                errorCode: "policy_selection_mismatch"
            )
        }
        guard ScreenTimeSharedContract.applicationShieldStrategy(
            applicationCount: decodedCounts.applications,
            categoryCount: decodedCounts.categories
        ) != .unsupportedTooManyApplications else {
            return currentDeviceStatus(
                enforcement: .error,
                errorCode: "application_selection_exceeds_apple_limit"
            )
        }

        if appliedPolicyRevision == policy.revision,
           appliedPolicySelectionHash == policyHash,
           appliedControlCommandID == policy.control?.commandId {
            if Self.shouldReconcileAcknowledgedControl(
                policy.control,
                appliedMode: appliedControlMode
            ) {
                let referenceDate = Date()
                if let controlError = reconcileGuardianControl(
                    policy.control,
                    referenceDate: referenceDate
                ) {
                    return currentDeviceStatus(enforcement: .error, errorCode: controlError)
                }
                persistAppliedControlReceipt(
                    policy.control,
                    referenceDate: referenceDate
                )
            }
            if temporaryUnlockIsActive || emergencyUnlockIsActive || schoolModeIsActive {
                return currentDeviceStatus(enforcement: .applied)
            }
            if !guardianShieldMatchesSelection() {
                shieldSelection()
            } else {
                syncShieldStateFromStore(operation: "cloud_sync_verified")
            }
            let applied = guardianShieldMatchesSelection()
            return currentDeviceStatus(
                enforcement: applied ? .applied : .error,
                errorCode: applied ? nil : "managed_settings_write_failed"
            )
        }

        let previousSelection = selection
        let previousCounts = selectionCounts
        let previousRevision = appliedPolicyRevision
        let previousHash = appliedPolicySelectionHash
        let previousControlCommandID = appliedControlCommandID
        let previousControlMode = appliedControlMode
        let previousControlUnlockUntil = appliedControlUnlockUntil
        let previousWasSynced = hasSyncedGuardianPolicy

        do {
            try selectionStore.save(normalized)
            selection = normalized
            selectionCounts = decodedCounts
            if !selectionsMatch(previousSelection, normalized) {
                invalidateSelectionScopedRuntime()
            } else {
                _ = ensureSelectionGeneration()
            }
            sharedDefaults.removeObject(
                forKey: ScreenTimeSharedContract.localChildSelectionCompletedKey
            )
            guard shieldSelection() else {
                throw ScreenTimeRewardMutationError.shieldVerificationFailed
            }
            if let controlError = reconcileGuardianControl(policy.control) {
                throw ScreenTimeRewardMutationError.controlCommandFailed(controlError)
            }
            persistAppliedGuardianPolicy(
                revision: policy.revision,
                selectionHash: policyHash,
                control: policy.control
            )
            lastAuthorizationError = nil
            appendLog("Applied guardian Screen Time policy revision \(policy.revision).")
            return currentDeviceStatus(enforcement: .applied)
        } catch {
            try? selectionStore.save(previousSelection)
            selection = previousSelection
            selectionCounts = previousCounts
            restoreAppliedGuardianPolicy(
                revision: previousRevision,
                selectionHash: previousHash,
                controlCommandID: previousControlCommandID,
                controlMode: previousControlMode,
                controlUnlockUntil: previousControlUnlockUntil,
                wasSynced: previousWasSynced
            )
            if previousCounts.hasSelection {
                _ = shieldSelection()
                if previousControlMode == .unlocked,
                   let previousControlCommandID,
                   let previousControlUnlockUntil {
                    _ = reconcileGuardianControl(
                        FamilyScreenTimeControl(
                            schemaVersion: 1,
                            commandId: previousControlCommandID,
                            mode: .unlocked,
                            issuedAt: "",
                            unlockUntil: previousControlUnlockUntil
                        )
                    )
                }
            }
            appendLog("Guardian policy apply failed and previous policy was restored: \(error.localizedDescription)")
            let errorCode: String
            if case ScreenTimeRewardMutationError.controlCommandFailed(let controlError) = error {
                errorCode = controlError
            } else if let lastShieldError {
                errorCode = lastShieldError
            } else {
                errorCode = "policy_apply_failed"
            }
            return currentDeviceStatus(
                enforcement: .error,
                errorCode: errorCode
            )
        }
    }

    func currentDeviceStatus(
        enforcement: FamilyScreenTimeEnforcementState? = nil,
        errorCode: String? = nil
    ) -> FamilyScreenTimeDeviceStatus {
        refreshAuthorizationStatus()
        let authorization: FamilyScreenTimeAuthorizationState
        switch authorizationState {
        case .approved: authorization = .approved
        case .denied: authorization = .denied
        case .unavailable: authorization = .unavailable
        case .notDetermined, .unknown: authorization = .notRequested
        }
        let selectionError = authorization == .approved && requiresExplicitAppReselection
            ? "family_controls_selection_requires_reselection"
            : nil
        let resolvedEnforcement = enforcement ?? {
            if authorization != .approved { return .waitingForAuthorization }
            if selectionError != nil { return .error }
            if !selectionCounts.hasSelection { return .waitingForPolicy }
            let hasCompleteReceipt = appliedPolicyRevision != nil &&
                appliedPolicySelectionHash != nil &&
                appliedControlCommandID != nil &&
                appliedControlMode != nil
            if (isShielded || emergencyUnlockIsActive), hasCompleteReceipt { return .applied }
            return .ready
        }()
        return FamilyScreenTimeDeviceStatus(
            authorization: authorization,
            enforcement: resolvedEnforcement,
            appliedPolicyRevision: appliedPolicyRevision,
            appliedSelectionHash: appliedPolicySelectionHash,
            appliedControlCommandId: appliedControlCommandID,
            controlMode: appliedControlMode,
            unlockedUntil: appliedControlUnlockUntil,
            lastErrorCode: errorCode ?? selectionError ??
                (lastAuthorizationError == nil ? nil : "authorization_failed"),
            applicationCount: selectionCounts.applications,
            categoryCount: selectionCounts.categories,
            webDomainCount: selectionCounts.webDomains,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    nonisolated static func shouldPreserveLocalChildSelection(
        localSelectionCompleted: Bool,
        localCounts: ScreenTimeSelectionCounts
    ) -> Bool {
        _ = localSelectionCompleted
        _ = localCounts
        return false
    }

    func resetChildDeviceControls() async {
        clearAllDeviceEnforcement(clearSelection: true)
        clearAppliedGuardianPolicy()
        sharedDefaults.removeObject(forKey: ScreenTimeSharedContract.localChildSelectionCompletedKey)
        do {
            try await revokeCurrentAuthorization()
            refreshAuthorizationStatus()
            lastAuthorizationError = nil
        } catch {
            lastAuthorizationError = error.localizedDescription
        }
    }

    func persistSelection() {
        do {
            let previousSelection = selectionStore.load()
            selection = ScreenTimeSelectionStore.normalizedForExplicitCategorySelection(selection).selection
            try selectionStore.save(selection)
            selectionCounts = Self.counts(for: selection)
            if !selectionsMatch(previousSelection, selection) {
                invalidateSelectionScopedRuntime()
            } else if selectionCounts.hasSelection {
                ensureSelectionGeneration()
            }
            appendLog("Saved selection: apps \(selectionCounts.applications), categories \(selectionCounts.categories), web domains \(selectionCounts.webDomains).")
        } catch {
            appendLog("Failed to save selection: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func shieldSelection() -> Bool {
        guard let applied = ScreenTimeRewardWindowLock.withLock({ shieldSelectionWhileLocked() }) else {
            lastShieldError = "reward_window_lock_unavailable"
            appendLog("Cannot apply the shield without the shared Screen Time lock.")
            return false
        }
        return applied
    }

    private func shieldSelectionWhileLocked() -> Bool {
        refreshAuthorizationStatus()
        guard isChildFamilyAuthorizationReady else {
            lastShieldError = "family_controls_not_authorized"
            appendLog("Cannot shield before FamilyControls authorization is approved.")
            syncShieldStateFromStore(operation: "guardian_shield_rejected_authorization")
            return false
        }
        guard selectionCounts.hasSelection else {
            lastShieldError = "managed_app_selection_empty"
            appendLog("Cannot shield: no apps or categories selected.")
            syncShieldStateFromStore(operation: "guardian_shield_rejected_empty_selection")
            return false
        }
        guard refreshSelectionTokensIfNeeded() else {
            syncShieldStateFromStore(operation: "guardian_shield_rejected_expired_tokens")
            return false
        }
        guard applicationShieldStrategy.isSupported else {
            lastShieldError = applicationShieldStrategy == .unsupportedTooManyApplications
                ? "application_selection_exceeds_apple_limit"
                : "managed_app_selection_empty"
            appendLog("Cannot shield an unsupported application selection; the existing effective policy was preserved.")
            return false
        }

        let previousRewardWindows = rewardWindowStore.loadAll()
        do {
            try rewardWindowStore.clear()
        } catch {
            lastShieldError = "reward_window_persistence_failed"
            appendLog("Cannot replace reward windows with the guardian shield: \(error.localizedDescription)")
            return false
        }
        cancelUsageWindows(previousRewardWindows)

        let applied = applyGuardianShields(
            activeRewardTokens: [],
            operation: "guardian_shield_apply"
        )
        if applied {
            lastShieldError = nil
        } else if #available(iOS 26.5, *) {
            sharedDefaults.set(
                true,
                forKey: ScreenTimeSharedContract.selectionRequiresExplicitAppReselectionKey
            )
            lastShieldError = "family_controls_selection_requires_reselection"
        } else {
            lastShieldError = "managed_settings_write_mismatch"
        }
        unlockEndsAt = nil
        emergencyWindowStore.clear()
        relockTask?.cancel()
        appendLog(applied
            ? "Shield applied and verified for the selected apps/categories."
            : "Shield write did not match the selected apps/categories; it will be retried.")
        return applied
    }

    /// Replays a saved parent-approved policy whenever the child app becomes active.
    /// This is important on iOS 26.5+, where opaque FamilyControls tokens can expire
    /// even though the old picker payload can still be decoded from App Group storage.
    func reapplyConfiguredShieldIfNeeded(referenceDate: Date = Date()) {
        guard !requiresExplicitAppReselection else {
            lastShieldError = "family_controls_selection_requires_reselection"
            appendLog("Skipped Screen Time retry until the app selection is confirmed again.")
            return
        }
        guard ScreenTimeRewardWindowLock.withLock({
            guard localChildSetupIsComplete else { return }
            if ScreenTimeSharedContract.emergencyDefersShieldRestoration(
                emergencyWindowStore.load(),
                at: referenceDate
            ) {
                restoreEmergencyWindowWhileLocked(referenceDate: referenceDate)
                return
            }
            guard retryPendingRewardCompensationsWhileLocked(referenceDate: referenceDate) else { return }
            let windows = activeRewardWindows(at: referenceDate)
            if windows.isEmpty {
                _ = shieldSelectionWhileLocked()
            } else {
                _ = applyRewardWindows(windows)
                updateRewardWindowRuntime(windows, referenceDate: referenceDate)
            }
        }) != nil else {
            appendLog("Could not reapply Screen Time state because the shared lock is unavailable.")
            return
        }
    }

    @discardableResult
    func applyConfiguredShieldNow() -> Bool {
        shieldSelection()
    }

    func unshieldAll() {
        guard ScreenTimeRewardWindowLock.withLock({ unshieldAllWhileLocked() }) != nil else {
            appendLog("Cannot clear the shield without the shared Screen Time lock.")
            return
        }
    }

    private func unshieldAllWhileLocked() {
        let previousRewardWindows = rewardWindowStore.loadAll()
        do {
            try rewardWindowStore.clear()
        } catch {
            appendLog("Cannot clear the shield while reward-window state is not durable: \(error.localizedDescription)")
            return
        }
        cancelUsageWindows(previousRewardWindows)
        clearApplicationShieldStores()
        isShielded = false
        unlockEndsAt = nil
        relockTask?.cancel()
        lastShieldError = nil
        appendLog("Shield cleared.")
    }

    @discardableResult
    func clearAllDeviceEnforcement(clearSelection: Bool) -> Bool {
        guard let cleared = ScreenTimeRewardWindowLock.withLock({
            clearAllDeviceEnforcementWhileLocked(clearSelection: clearSelection)
        }) else {
            appendLog("Cannot clear Screen Time enforcement without the shared lock.")
            return false
        }
        return cleared
    }

    private func clearAllDeviceEnforcementWhileLocked(clearSelection: Bool) -> Bool {
        let previousSchoolRuntime = schoolModeRuntimeStore.load()
        let previousRewardWindows = rewardWindowStore.loadAll()
        // Runtime files can drift or disappear while DeviceActivity and named
        // ManagedSettings stores remain registered with iOS. Stop every monitor
        // owned by this app and scrub every configured store before clearing the
        // current in-memory state.
        DeviceActivityCenter().stopMonitoring()
        schoolModeScheduler.cancel(activityNames: previousSchoolRuntime?.activityNames ?? [])
        unlockEndsAt = nil
        relockTask?.cancel()
        relockTask = nil
        let namedStoresCleared = clearConfiguredManagedSettingsStores()
        clearApplicationShieldStores()
        webSafetyStore.clearAllSettings()
        schoolStore.clearAllSettings()
        let defaultStoreIsClear = clearAndVerifyManagedSettingsStore(ManagedSettingsStore())
        schoolModeRuntimeStore.clear()
        do {
            try rewardWindowStore.clear()
            try rewardCompensationStore.clear()
        } catch {
            appendLog("Could not verify reward-state cleanup: \(error.localizedDescription)")
            return false
        }
        emergencyWindowStore.clear()
        shieldActionStore.clear()
        cancelUsageWindows(previousRewardWindows)
        isShielded = false
        websiteSafetyIsApplied = false
        websiteSafetyDomainCount = 0
        schoolModeIsActive = false
        schoolModeEndsAt = nil
        schoolModeLastError = nil
        sharedDefaults.set(false, forKey: ScreenTimeSharedContract.schoolModeActiveKey)
        if clearSelection {
            selectionStore.clear()
            selection = ScreenTimeSelectionStore.emptyExpandedSelection()
            selectionCounts = .empty
            invalidateSelectionScopedRuntime()
        }
        let stateCleared = rewardWindowStore.loadAll().isEmpty &&
            rewardCompensationStore.load().isEmpty &&
            emergencyWindowStore.load() == nil
        return ScreenTimeSharedContract.managedSettingsCleanupWasVerified(
            namedStoresAreClear: namedStoresCleared && stateCleared,
            defaultStoreIsClear: defaultStoreIsClear
        )
    }

    private func clearConfiguredManagedSettingsStores() -> Bool {
        let explicitNames = ScreenTimeSharedContract.legacyManagedSettingsStoreNames +
            (1..<ScreenTimeSharedContract.maximumApplicationShieldStoreCount).map {
                ScreenTimeSharedContract.applicationShieldStoreName(at: $0)
            }
        var configuredStoreNames = Set(explicitNames.map { ManagedSettingsStore.Name($0) })
        if #available(iOS 26.5, *) {
            configuredStoreNames.formUnion(ManagedSettingsStore.stores)
        }
        for name in configuredStoreNames {
            ManagedSettingsStore(named: name).clearAllSettings()
        }
        return configuredStoreNames.allSatisfy {
            managedSettingsStoreIsClear(ManagedSettingsStore(named: $0))
        }
    }

    private func clearAndVerifyManagedSettingsStore(_ store: ManagedSettingsStore) -> Bool? {
        store.clearAllSettings()
        // Nil also represents a failed ManagedSettings read; an empty set proves readback without shielding an app.
        store.shield.applications = []
        guard let probe = store.shield.applications, probe.isEmpty else {
            store.clearAllSettings()
            return nil
        }
        store.clearAllSettings()
        return managedSettingsStoreIsClear(store)
    }

    private func managedSettingsStoreIsClear(_ store: ManagedSettingsStore) -> Bool {
        store.shield.applications == nil &&
            store.shield.applicationCategories == nil &&
            store.shield.webDomains == nil &&
            store.webContent.blockedByFilter == nil
    }

    private var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: AppGroupKeys.groupIdentifier) ?? .standard
    }

    private var appliedPolicySelectionHash: String? {
        sharedDefaults.string(forKey: ScreenTimeSharedContract.appliedPolicySelectionHashKey)
    }

    private var appliedControlCommandID: String? {
        sharedDefaults.string(forKey: ScreenTimeSharedContract.appliedControlCommandIDKey)
    }

    private var appliedControlMode: FamilyScreenTimeControlMode? {
        sharedDefaults.string(forKey: ScreenTimeSharedContract.appliedControlModeKey)
            .flatMap(FamilyScreenTimeControlMode.init(rawValue:))
    }

    private var appliedControlUnlockUntil: String? {
        sharedDefaults.string(forKey: ScreenTimeSharedContract.appliedControlUnlockUntilKey)
    }

    nonisolated static func shouldReconcileAcknowledgedControl(
        _ control: FamilyScreenTimeControl?,
        appliedMode: FamilyScreenTimeControlMode?
    ) -> Bool {
        control?.mode == .unlocked && appliedMode == .unlocked
    }

    private func persistAppliedGuardianPolicy(
        revision: Int,
        selectionHash: String,
        control: FamilyScreenTimeControl?
    ) {
        appliedPolicyRevision = revision
        sharedDefaults.set(revision, forKey: ScreenTimeSharedContract.appliedPolicyRevisionKey)
        sharedDefaults.set(selectionHash, forKey: ScreenTimeSharedContract.appliedPolicySelectionHashKey)
        persistAppliedControlReceipt(control)
        sharedDefaults.set(true, forKey: ScreenTimeSharedContract.syncedGuardianPolicyKey)
    }

    private func persistAppliedControlReceipt(
        _ control: FamilyScreenTimeControl?,
        referenceDate: Date = Date()
    ) {
        if let commandID = control?.commandId {
            sharedDefaults.set(commandID, forKey: ScreenTimeSharedContract.appliedControlCommandIDKey)
        } else {
            sharedDefaults.removeObject(forKey: ScreenTimeSharedContract.appliedControlCommandIDKey)
        }
        let receipt = control?.effectiveReceipt(referenceDate: referenceDate)
            ?? FamilyScreenTimeControlReceipt(mode: .locked, unlockUntil: nil)
        sharedDefaults.set(
            receipt.mode.rawValue,
            forKey: ScreenTimeSharedContract.appliedControlModeKey
        )
        if let unlockUntil = receipt.unlockUntil {
            sharedDefaults.set(unlockUntil, forKey: ScreenTimeSharedContract.appliedControlUnlockUntilKey)
        } else {
            sharedDefaults.removeObject(forKey: ScreenTimeSharedContract.appliedControlUnlockUntilKey)
        }
    }

    private func clearAppliedGuardianPolicy() {
        appliedPolicyRevision = nil
        sharedDefaults.removeObject(forKey: ScreenTimeSharedContract.appliedPolicyRevisionKey)
        sharedDefaults.removeObject(forKey: ScreenTimeSharedContract.appliedPolicySelectionHashKey)
        sharedDefaults.removeObject(forKey: ScreenTimeSharedContract.appliedControlCommandIDKey)
        sharedDefaults.removeObject(forKey: ScreenTimeSharedContract.appliedControlModeKey)
        sharedDefaults.removeObject(forKey: ScreenTimeSharedContract.appliedControlUnlockUntilKey)
        sharedDefaults.removeObject(forKey: ScreenTimeSharedContract.syncedGuardianPolicyKey)
    }

    private func restoreAppliedGuardianPolicy(
        revision: Int?,
        selectionHash: String?,
        controlCommandID: String?,
        controlMode: FamilyScreenTimeControlMode?,
        controlUnlockUntil: String?,
        wasSynced: Bool
    ) {
        appliedPolicyRevision = revision
        if let revision {
            sharedDefaults.set(revision, forKey: ScreenTimeSharedContract.appliedPolicyRevisionKey)
        } else {
            sharedDefaults.removeObject(forKey: ScreenTimeSharedContract.appliedPolicyRevisionKey)
        }
        if let selectionHash {
            sharedDefaults.set(
                selectionHash,
                forKey: ScreenTimeSharedContract.appliedPolicySelectionHashKey
            )
        } else {
            sharedDefaults.removeObject(forKey: ScreenTimeSharedContract.appliedPolicySelectionHashKey)
        }
        if let controlCommandID {
            sharedDefaults.set(controlCommandID, forKey: ScreenTimeSharedContract.appliedControlCommandIDKey)
        } else {
            sharedDefaults.removeObject(forKey: ScreenTimeSharedContract.appliedControlCommandIDKey)
        }
        if let controlMode {
            sharedDefaults.set(controlMode.rawValue, forKey: ScreenTimeSharedContract.appliedControlModeKey)
        } else {
            sharedDefaults.removeObject(forKey: ScreenTimeSharedContract.appliedControlModeKey)
        }
        if let controlUnlockUntil {
            sharedDefaults.set(
                controlUnlockUntil,
                forKey: ScreenTimeSharedContract.appliedControlUnlockUntilKey
            )
        } else {
            sharedDefaults.removeObject(forKey: ScreenTimeSharedContract.appliedControlUnlockUntilKey)
        }
        sharedDefaults.set(wasSynced, forKey: ScreenTimeSharedContract.syncedGuardianPolicyKey)
    }

    private var currentSelectionGeneration: Int {
        ScreenTimeSharedContract.currentSelectionGeneration(defaults: sharedDefaults)
    }

    @discardableResult
    private func ensureSelectionGeneration() -> Int {
        let current = currentSelectionGeneration
        return current > 0
            ? current
            : ScreenTimeSharedContract.advanceSelectionGeneration(defaults: sharedDefaults)
    }

    private func selectionsMatch(
        _ lhs: FamilyActivitySelection,
        _ rhs: FamilyActivitySelection
    ) -> Bool {
        lhs.applicationTokens == rhs.applicationTokens &&
            lhs.categoryTokens == rhs.categoryTokens &&
            lhs.webDomainTokens == rhs.webDomainTokens
    }

    private func invalidateSelectionScopedRuntime() {
        ScreenTimeSharedContract.advanceSelectionGeneration(defaults: sharedDefaults)
        shieldActionStore.clear()
    }

    private var schoolModeBlocksRewardUnlock: Bool {
        ScreenTimeSharedContract.schoolModeBlocksRewardUnlock(
            inMemoryIsActive: schoolModeIsActive,
            persistedIsActive: sharedDefaults.bool(forKey: ScreenTimeSharedContract.schoolModeActiveKey)
        )
    }

    @discardableResult
    private func syncShieldStateFromStore(operation: String) -> Bool {
        let appliedApplicationCount = appliedApplicationTokens.count
        let appliedCategoryPolicy = shieldStore.shield.applicationCategories != nil
        let appliedWebDomainCount = shieldStore.shield.webDomains?.count ?? 0
        let hasAnyShield = appliedApplicationCount > 0 || appliedCategoryPolicy || appliedWebDomainCount > 0
        isShielded = hasAnyShield

        let matches = guardianShieldMatchesSelection()
        let diagnostic = PersistedScreenTimeShieldDiagnostic(
            operation: operation,
            selectedApplicationCount: selectionCounts.applications,
            selectedCategoryCount: selectionCounts.categories,
            selectedWebDomainCount: selectionCounts.webDomains,
            appliedApplicationCount: appliedApplicationCount,
            appliedCategoryPolicy: appliedCategoryPolicy,
            appliedWebDomainCount: appliedWebDomainCount,
            matchesGuardianSelection: matches,
            updatedAt: Date()
        )
        if let data = try? JSONEncoder().encode(diagnostic) {
            sharedDefaults.set(data, forKey: ScreenTimeSharedContract.shieldDiagnosticKey)
        }
        return matches
    }

    private func guardianShieldMatchesSelection() -> Bool {
        let appliedApplications = appliedApplicationTokens
        let appliedWebDomains = shieldStore.shield.webDomains ?? []
        let enforcementMatches: Bool
        switch applicationShieldStrategy {
        case .preciseApplications:
            enforcementMatches = appliedApplications == selection.applicationTokens &&
                shieldStore.shield.applicationCategories == nil
        case .applicationsAndCategories:
            enforcementMatches = appliedApplications == selection.applicationTokens &&
                shieldStore.shield.applicationCategories == .specific(
                    selection.categoryTokens,
                    except: selection.applicationTokens
                )
        case .categories:
            enforcementMatches = appliedApplications.isEmpty &&
                shieldStore.shield.applicationCategories == .specific(selection.categoryTokens)
        case .none, .unsupportedTooManyApplications:
            enforcementMatches = false
        }
        return enforcementMatches && appliedWebDomains == selection.webDomainTokens
    }

    /// Refreshes opaque FamilyControls tokens before every enforcement write.
    /// iOS 26.5 can invalidate persisted tokens while leaving their encoded values
    /// readable, which otherwise produces a false "configured" state with no shield.
    private func refreshSelectionTokensIfNeeded() -> Bool {
        guard #available(iOS 26.5, *) else { return true }

        do {
            let previousSelection = selection
            let previousWindows = rewardWindowStore.loadAll()
            let previousShieldRequest = shieldActionStore.loadPersisted()
            let encoder = PropertyListEncoder()
            let decoder = PropertyListDecoder()

            var applicationTokens: [ApplicationToken] = []
            var oldApplicationTokenData: [Data] = []
            var seenApplicationTokenData = Set<Data>()

            func appendApplicationToken(_ token: ApplicationToken, encoded data: Data? = nil) throws {
                let tokenData = try data ?? encoder.encode(token)
                guard seenApplicationTokenData.insert(tokenData).inserted else { return }
                applicationTokens.append(token)
                oldApplicationTokenData.append(tokenData)
            }

            for token in selection.applicationTokens {
                try appendApplicationToken(token)
            }
            let selectedApplicationCount = applicationTokens.count

            for window in previousWindows {
                guard window.resolvedTargetKind == .application else { continue }
                guard !seenApplicationTokenData.contains(window.applicationTokenData) else { continue }
                let token = try decoder.decode(ApplicationToken.self, from: window.applicationTokenData)
                try appendApplicationToken(token, encoded: window.applicationTokenData)
            }

            if let request = previousShieldRequest,
               request.targetKind == .application,
               !seenApplicationTokenData.contains(request.tokenData) {
                let token = try decoder.decode(ApplicationToken.self, from: request.tokenData)
                try appendApplicationToken(token, encoded: request.tokenData)
            }

            var categoryTokens = Array(selection.categoryTokens)
            var webDomainTokens = Array(selection.webDomainTokens)
            if !applicationTokens.isEmpty {
                try ManagedSettingsStore.refresh(&applicationTokens)
            }
            if !categoryTokens.isEmpty {
                try ManagedSettingsStore.refresh(&categoryTokens)
            }
            if !webDomainTokens.isEmpty {
                try ManagedSettingsStore.refresh(&webDomainTokens)
            }

            let refreshedApplicationTokenData = try applicationTokens.map { try encoder.encode($0) }
            let tokenMap = try ScreenTimeOpaqueTokenRefreshMigration.makeTokenMap(
                oldTokenData: oldApplicationTokenData,
                refreshedTokenData: refreshedApplicationTokenData
            )
            let migratedRuntime = try ScreenTimeOpaqueTokenRefreshMigration.migrate(
                tokenMap: tokenMap,
                rewardWindows: previousWindows,
                shieldActionRequest: previousShieldRequest
            )

            var refreshed = FamilyActivitySelection(includeEntireCategory: false)
            refreshed.applicationTokens = Set(applicationTokens.prefix(selectedApplicationCount))
            refreshed.categoryTokens = Set(categoryTokens)
            refreshed.webDomainTokens = Set(webDomainTokens)

            do {
                try selectionStore.save(refreshed)
                try rewardWindowStore.saveAll(migratedRuntime.rewardWindows)
                try shieldActionStore.replace(migratedRuntime.shieldActionRequest)
            } catch {
                try? selectionStore.save(previousSelection)
                try? rewardWindowStore.saveAll(previousWindows)
                try? shieldActionStore.replace(previousShieldRequest)
                throw error
            }

            selection = refreshed
            selectionCounts = Self.counts(for: refreshed)
            if selectionCounts.hasSelection {
                ensureSelectionGeneration()
            }
            lastShieldError = nil
            appendLog(
                "Refreshed FamilyControls tokens and migrated " +
                    "\(migratedRuntime.rewardWindows.count) active reward window(s)."
            )
            return true
        } catch {
            lastShieldError = "family_controls_tokens_expired"
            appendLog("FamilyControls tokens could not be refreshed: \(error.localizedDescription)")
            return false
        }
    }

    func unlockForTesting(minutes: Int = 2) {
        guard ScreenTimeSharedContract.implicitSingleApplicationUnlockSelectionIsUnambiguous(
            applicationCount: selection.applicationTokens.count
        ), let token = selection.applicationTokens.first else {
            appendLog("Cannot start POC test: select exactly one individual app.")
            return
        }
        _ = try? startSingleAppRewardWindow(
            applicationToken: token,
            minutes: minutes,
            now: Date(),
            sourceLabel: "POC test"
        )
    }

    /// 给主奖励链路调用的真实设备窗口入口。
    /// 成功时返回计划到期时间；失败时抛 `UnlockError`，由上游回滚成长积分。
    @discardableResult
    func startRewardWindow(minutes: Int, now: Date = Date(), sourceLabel: String = "reward redemption") throws -> Date {
        guard ScreenTimeSharedContract.implicitSingleApplicationUnlockSelectionIsUnambiguous(
            applicationCount: selection.applicationTokens.count
        ), let token = selection.applicationTokens.first else {
            appendLog("Cannot start \(sourceLabel): an exact app token or exactly one selected app is required.")
            throw UnlockError.deviceCommandFailed
        }
        return try startSingleAppRewardWindow(
            applicationToken: token,
            minutes: minutes,
            now: now,
            sourceLabel: sourceLabel
        )
    }

    /// 只打开一个由家长预先选入控制范围的 App，其他 App、分类和网站限制保持生效。
    @discardableResult
    func startSingleAppRewardWindow(
        applicationToken: ApplicationToken,
        minutes: Int,
        now: Date = Date(),
        sourceLabel: String = "reward redemption",
        shieldRequestID: UUID? = nil,
        allowDuringSchoolMode: Bool = false,
        authority: ScreenTimeSingleAppUnlockAuthority = .growthPoints,
        sessionID: UUID? = nil
    ) throws -> Date {
        try startSingleAppRewardSession(
            applicationToken: applicationToken,
            minutes: minutes,
            now: now,
            sourceLabel: sourceLabel,
            shieldRequestID: shieldRequestID,
            allowDuringSchoolMode: allowDuringSchoolMode,
            authority: authority,
            sessionID: sessionID
        ).endsAt
    }

    /// Same real-device operation as `startSingleAppRewardWindow`, with a stable ID used by
    /// the local points ledger to track multiple apps independently.
    @discardableResult
    func startSingleAppRewardSession(
        applicationToken: ApplicationToken,
        minutes: Int,
        now: Date = Date(),
        sourceLabel: String = "reward redemption",
        shieldRequestID: UUID? = nil,
        allowDuringSchoolMode: Bool = false,
        authority: ScreenTimeSingleAppUnlockAuthority = .growthPoints,
        sessionID: UUID? = nil
    ) throws -> ScreenTimeExternalSession {
        guard ScreenTimeUsageWindowSchedule.supports(minutes: minutes),
              minutes <= authority.maximumMinutes else {
            appendLog("Cannot start \(sourceLabel): duration must be at least 15 minutes and within the allowed window.")
            recordSingleAppOperation(
                requestID: shieldRequestID,
                authority: authority,
                minutes: minutes,
                outcome: .rejected,
                errorCode: "invalid_duration",
                timestamp: now
            )
            throw UnlockError.nonPositiveMinutes
        }
        let hasSchoolOverrideAuthority = allowDuringSchoolMode && authority == .parentPIN
        guard !schoolModeBlocksRewardUnlock || hasSchoolOverrideAuthority else {
            appendLog("Cannot start \(sourceLabel): school mode is active.")
            recordSingleAppOperation(
                requestID: shieldRequestID,
                authority: authority,
                minutes: minutes,
                outcome: .rejected,
                errorCode: "school_mode_active",
                timestamp: now
            )
            throw UnlockError.deviceCommandFailed
        }
        refreshAuthorizationStatus()
        guard authorizationState == .approved else {
            appendLog("Cannot start \(sourceLabel): FamilyControls authorization is \(authorizationState.label).")
            recordSingleAppOperation(
                requestID: shieldRequestID,
                authority: authority,
                minutes: minutes,
                outcome: .rejected,
                errorCode: "authorization_not_approved",
                timestamp: now
            )
            throw UnlockError.deviceCommandFailed
        }
        let hasDirectSelection = selection.applicationTokens.contains(applicationToken)
        let hasValidShieldOrigin = shieldRequestID.map {
            isValidShieldApplicationRequest(id: $0, token: applicationToken, at: now)
        } ?? false
        guard hasDirectSelection || hasValidShieldOrigin else {
            appendLog("Cannot start \(sourceLabel): selected app is outside the guardian-approved set.")
            recordSingleAppOperation(
                requestID: shieldRequestID,
                authority: authority,
                minutes: minutes,
                outcome: .rejected,
                errorCode: shieldRequestID == nil ? "invalid_target_receipt" : "request_expired",
                timestamp: now
            )
            throw UnlockError.deviceCommandFailed
        }

        guard let session = try ScreenTimeRewardWindowLock.withLock({
            guard !schoolModeBlocksRewardUnlock || hasSchoolOverrideAuthority else {
                appendLog("Cannot start \(sourceLabel): school mode became active before mutation.")
                recordSingleAppOperation(
                    requestID: shieldRequestID,
                    authority: authority,
                    minutes: minutes,
                    outcome: .rejected,
                    errorCode: "school_mode_changed",
                    timestamp: now
                )
                throw UnlockError.deviceCommandFailed
            }
            if authority == .growthPoints {
                guard ScreenTimeSharedContract.paidUnlockCanCommit(
                    schoolModeIsActive: schoolModeBlocksRewardUnlock,
                    schoolStoreIsClear: clearAndVerifyManagedSettingsStore(schoolStore)
                ) else {
                    appendLog("Cannot start \(sourceLabel): the school store could not be verified clear; no unlock was committed.")
                    recordSingleAppOperation(
                        requestID: shieldRequestID,
                        authority: authority,
                        minutes: minutes,
                        outcome: .rejected,
                        errorCode: "school_store_not_clear",
                        timestamp: now
                    )
                    throw UnlockError.deviceCommandFailed
                }
            }
            let tokenData = try PropertyListEncoder().encode(applicationToken)
            let endDate = now.addingTimeInterval(TimeInterval(minutes * 60))
            let window = PersistedScreenTimeRewardWindow(
                id: sessionID ?? UUID(),
                applicationTokenData: tokenData,
                startedAt: now,
                endsAt: endDate,
                sourceLabel: sourceLabel,
                selectionGeneration: ensureSelectionGeneration(),
                startedAtSystemUptime: ProcessInfo.processInfo.systemUptime
            )
            let previousWindows = rewardWindowStore.loadAll()
            let windows: [PersistedScreenTimeRewardWindow]
            do {
                windows = try ScreenTimeRewardWindowLedger.adding(
                    window,
                    to: previousWindows,
                    at: now,
                    systemUptime: ProcessInfo.processInfo.systemUptime
                )
            } catch ScreenTimeRewardWindowLedger.Error.alreadyActive {
                appendLog("Cannot start \(sourceLabel): this app already has an active reward window.")
                recordSingleAppOperation(
                    requestID: shieldRequestID,
                    authority: authority,
                    minutes: minutes,
                    outcome: .rejected,
                    errorCode: "already_active",
                    timestamp: now
                )
                throw UnlockError.alreadyActive
            }
            let activityName = ScreenTimeSharedContract.rewardActivityName(for: window.resolvedID)
            try ScreenTimeRewardWindowTransaction.commitStart(
                schedule: {
                    try usageWindowScheduler.noteUsageWindow(
                        named: activityName,
                        from: now,
                        until: endDate,
                        selection: selection
                    )
                },
                persist: { try rewardWindowStore.saveAll(windows) },
                rollbackPersistence: { try? rewardWindowStore.saveAll(previousWindows) },
                rollbackSchedule: { usageWindowScheduler.cancelUsageWindows(named: [activityName]) }
            )
            guard !schoolModeBlocksRewardUnlock || hasSchoolOverrideAuthority else {
                try rollbackStartedRewardWindow(
                    window: window,
                    previousWindows: previousWindows,
                    referenceDate: now
                )
                appendLog("Rolled back \(sourceLabel): school mode became active before commit.")
                recordSingleAppOperation(
                    requestID: shieldRequestID,
                    authority: authority,
                    minutes: minutes,
                    outcome: .rolledBack,
                    errorCode: "school_mode_changed",
                    timestamp: now
                )
                throw UnlockError.deviceCommandFailed
            }
            guard applyRewardWindows(windows) else {
                try rollbackStartedRewardWindow(
                    window: window,
                    previousWindows: previousWindows,
                    referenceDate: now
                )
                appendLog("Rolled back \(sourceLabel): the applied shield did not match the expected app set.")
                recordSingleAppOperation(
                    requestID: shieldRequestID,
                    authority: authority,
                    minutes: minutes,
                    outcome: .rolledBack,
                    errorCode: "shield_verification_failed",
                    timestamp: now
                )
                throw UnlockError.deviceCommandFailed
            }
            if authority == .growthPoints,
               !ScreenTimeSharedContract.paidUnlockCanCommit(
                    schoolModeIsActive: schoolModeBlocksRewardUnlock,
                    schoolStoreIsClear: clearAndVerifyManagedSettingsStore(schoolStore)
               ) {
                try rollbackStartedRewardWindow(
                    window: window,
                    previousWindows: previousWindows,
                    referenceDate: now
                )
                if schoolModeBlocksRewardUnlock {
                    _ = applySchoolShield()
                }
                appendLog("Rolled back \(sourceLabel): the school store was not clear at final verification.")
                recordSingleAppOperation(
                    requestID: shieldRequestID,
                    authority: authority,
                    minutes: minutes,
                    outcome: .rolledBack,
                    errorCode: "school_store_not_clear",
                    timestamp: now
                )
                throw UnlockError.deviceCommandFailed
            }
            recordSingleAppOperation(
                requestID: shieldRequestID,
                authority: authority,
                minutes: minutes,
                outcome: .started,
                errorCode: nil,
                timestamp: now
            )
            updateRewardWindowRuntime(windows, referenceDate: now)
            appendLog("Started \(sourceLabel) for one selected app for \(minutes) minutes; \(windows.count) app window(s) active.")
            return ScreenTimeExternalSession(id: window.resolvedID, endsAt: endDate)
        }) else {
            appendLog("Cannot start \(sourceLabel): the shared Screen Time lock is unavailable.")
            recordSingleAppOperation(
                requestID: shieldRequestID,
                authority: authority,
                minutes: minutes,
                outcome: .rejected,
                errorCode: "shared_lock_unavailable",
                timestamp: now
            )
            throw UnlockError.deviceCommandFailed
        }
        return session
    }

    /// Opens only the category identified by Apple's ShieldAction callback. Apple deliberately
    /// omits the individual app for category shields, so this is the narrowest verifiable scope.
    @discardableResult
    func startCategoryRewardSession(
        categoryToken: ActivityCategoryToken,
        minutes: Int,
        now: Date = Date(),
        sourceLabel: String = "category reward redemption",
        shieldRequestID: UUID,
        authority: ScreenTimeSingleAppUnlockAuthority = .growthPoints,
        sessionID: UUID? = nil
    ) throws -> ScreenTimeExternalSession {
        func record(
            _ outcome: PersistedScreenTimeOperationOutcome,
            errorCode: String?
        ) {
            recordSingleAppOperation(
                requestID: shieldRequestID,
                authority: authority,
                minutes: minutes,
                outcome: outcome,
                errorCode: errorCode,
                timestamp: now,
                targetKind: .category
            )
        }

        guard ScreenTimeUsageWindowSchedule.supports(minutes: minutes),
              minutes <= authority.maximumMinutes else {
            record(.rejected, errorCode: "invalid_duration")
            throw UnlockError.nonPositiveMinutes
        }
        guard !schoolModeBlocksRewardUnlock else {
            record(.rejected, errorCode: "school_mode_active")
            throw UnlockError.deviceCommandFailed
        }
        refreshAuthorizationStatus()
        guard authorizationState == .approved,
              selectionStore.usesSharedAppGroup else {
            record(.rejected, errorCode: "authorization_not_approved")
            throw UnlockError.deviceCommandFailed
        }
        guard selection.categoryTokens.contains(categoryToken),
              isValidShieldCategoryRequest(
                  id: shieldRequestID,
                  token: categoryToken,
                  at: now
              ) else {
            record(.rejected, errorCode: "invalid_target_receipt")
            throw UnlockError.deviceCommandFailed
        }

        guard let session = try ScreenTimeRewardWindowLock.withLock({
            guard !schoolModeBlocksRewardUnlock else {
                record(.rejected, errorCode: "school_mode_changed")
                throw UnlockError.deviceCommandFailed
            }
            if authority == .growthPoints {
                guard ScreenTimeSharedContract.paidUnlockCanCommit(
                    schoolModeIsActive: schoolModeBlocksRewardUnlock,
                    schoolStoreIsClear: clearAndVerifyManagedSettingsStore(schoolStore)
                ) else {
                    record(.rejected, errorCode: "school_store_not_clear")
                    throw UnlockError.deviceCommandFailed
                }
            }

            let tokenData = try PropertyListEncoder().encode(categoryToken)
            let endDate = now.addingTimeInterval(TimeInterval(minutes * 60))
            let window = PersistedScreenTimeRewardWindow(
                id: sessionID ?? UUID(),
                applicationTokenData: tokenData,
                targetKind: .category,
                startedAt: now,
                endsAt: endDate,
                sourceLabel: sourceLabel,
                selectionGeneration: ensureSelectionGeneration(),
                startedAtSystemUptime: ProcessInfo.processInfo.systemUptime
            )
            let previousWindows = rewardWindowStore.loadAll()
            let windows: [PersistedScreenTimeRewardWindow]
            do {
                windows = try ScreenTimeRewardWindowLedger.adding(
                    window,
                    to: previousWindows,
                    at: now,
                    systemUptime: ProcessInfo.processInfo.systemUptime
                )
            } catch ScreenTimeRewardWindowLedger.Error.alreadyActive {
                record(.rejected, errorCode: "already_active")
                throw UnlockError.alreadyActive
            }

            let activityName = ScreenTimeSharedContract.rewardActivityName(for: window.resolvedID)
            try ScreenTimeRewardWindowTransaction.commitStart(
                schedule: {
                    try usageWindowScheduler.noteUsageWindow(
                        named: activityName,
                        from: now,
                        until: endDate,
                        selection: selection
                    )
                },
                persist: { try rewardWindowStore.saveAll(windows) },
                rollbackPersistence: { try? rewardWindowStore.saveAll(previousWindows) },
                rollbackSchedule: { usageWindowScheduler.cancelUsageWindows(named: [activityName]) }
            )

            guard !schoolModeBlocksRewardUnlock else {
                try rollbackStartedRewardWindow(
                    window: window,
                    previousWindows: previousWindows,
                    referenceDate: now
                )
                record(.rolledBack, errorCode: "school_mode_changed")
                throw UnlockError.deviceCommandFailed
            }
            guard applyRewardWindows(windows) else {
                try rollbackStartedRewardWindow(
                    window: window,
                    previousWindows: previousWindows,
                    referenceDate: now
                )
                record(.rolledBack, errorCode: "shield_verification_failed")
                throw UnlockError.deviceCommandFailed
            }
            if authority == .growthPoints,
               !ScreenTimeSharedContract.paidUnlockCanCommit(
                   schoolModeIsActive: schoolModeBlocksRewardUnlock,
                   schoolStoreIsClear: clearAndVerifyManagedSettingsStore(schoolStore)
               ) {
                try rollbackStartedRewardWindow(
                    window: window,
                    previousWindows: previousWindows,
                    referenceDate: now
                )
                if schoolModeBlocksRewardUnlock {
                    _ = applySchoolShield()
                }
                record(.rolledBack, errorCode: "school_store_not_clear")
                throw UnlockError.deviceCommandFailed
            }

            record(.started, errorCode: nil)
            updateRewardWindowRuntime(windows, referenceDate: now)
            appendLog("Started (sourceLabel) for one category for (minutes) minutes.")
            return ScreenTimeExternalSession(id: window.resolvedID, endsAt: endDate)
        }) else {
            record(.rejected, errorCode: "shared_lock_unavailable")
            throw UnlockError.deviceCommandFailed
        }
        return session
    }

    func makeRedemptionReceipt(
        redemptionID: UUID,
        applicationToken: ApplicationToken,
        points: Int,
        minutes: Int,
        policy: FamilyScreenTimePolicy,
        now: Date = Date()
    ) throws -> FamilyScreenTimeRedemptionReceipt {
        try makeRedemptionReceipt(
            redemptionID: redemptionID,
            targetTokenData: PropertyListEncoder().encode(applicationToken),
            points: points,
            minutes: minutes,
            policy: policy,
            now: now
        )
    }

    func makeRedemptionReceipt(
        redemptionID: UUID,
        categoryToken: ActivityCategoryToken,
        points: Int,
        minutes: Int,
        policy: FamilyScreenTimePolicy,
        now: Date = Date()
    ) throws -> FamilyScreenTimeRedemptionReceipt {
        try makeRedemptionReceipt(
            redemptionID: redemptionID,
            targetTokenData: PropertyListEncoder().encode(categoryToken),
            points: points,
            minutes: minutes,
            policy: policy,
            now: now
        )
    }

    private func makeRedemptionReceipt(
        redemptionID: UUID,
        targetTokenData: Data,
        points: Int,
        minutes: Int,
        policy: FamilyScreenTimePolicy,
        now: Date
    ) throws -> FamilyScreenTimeRedemptionReceipt {
        let status = currentDeviceStatus()
        guard points > 0,
              ScreenTimeUsageWindowSchedule.supports(minutes: minutes),
              policy.hasValidSelectionHash,
              status.acknowledgesCurrentLockedPolicy(policy, referenceDate: now),
              let selectionHash = policy.selectionHash,
              let control = policy.control else {
            appendLog("Cannot reserve reward points: the child device has not acknowledged the current locked policy.")
            throw UnlockError.deviceCommandFailed
        }
        let targetTokenHash = FamilyScreenTimePolicy.hash(
            selectionData: targetTokenData.base64EncodedString()
        )
        return FamilyScreenTimeRedemptionReceipt(
            redemptionRef: redemptionID.uuidString.lowercased(),
            points: points,
            minutes: minutes,
            policyRevision: policy.revision,
            selectionHash: selectionHash,
            controlCommandId: control.commandId,
            targetTokenHash: targetTokenHash,
            unlockUntil: ISO8601DateFormatter().string(
                from: now.addingTimeInterval(TimeInterval(minutes * 60))
            )
        )
    }

    private func recordSingleAppOperation(
        requestID: UUID?,
        authority: ScreenTimeSingleAppUnlockAuthority,
        minutes: Int,
        outcome: PersistedScreenTimeOperationOutcome,
        errorCode: String?,
        timestamp: Date,
        targetKind: PersistedShieldTargetKind = .application
    ) {
        let matchingRequest = shieldActionStore.load(at: timestamp).flatMap { request in
            requestID == nil || request.id == requestID ? request : nil
        }
        ScreenTimeOperationAuditLedger.append(
            PersistedScreenTimeOperationAuditEntry(
                id: UUID(),
                requestID: requestID,
                stage: targetKind == .category ? "category_unlock" : "single_app_unlock",
                outcome: outcome,
                authorityRawValue: authority == .growthPoints ? "growth_points" : "parent_pin",
                targetKind: targetKind,
                interfaceLanguageRawValue: matchingRequest?.validatedInterfaceLanguageRawValue,
                durationMinutes: minutes,
                errorCode: errorCode,
                timestamp: timestamp
            )
        )
    }

    /// ShieldAction extension stores only an opaque, five-minute target receipt. Application
    /// callbacks identify one app; category callbacks identify only a category and are never
    /// decoded as application tokens.
    func pendingShieldAction(at date: Date = Date()) -> PersistedShieldActionRequest? {
        guard let request = shieldActionStore.load(at: date) else { return nil }
        guard request.belongsToSelectionGeneration(currentSelectionGeneration) else {
            shieldActionStore.clear()
            appendLog("Discarded a stale shield action after the guardian selection changed.")
            return nil
        }
        return request
    }

    func clearPendingShieldAction(id: UUID) {
        guard shieldActionStore.load()?.id == id else { return }
        shieldActionStore.clear()
    }

    func applicationToken(from request: PersistedShieldActionRequest) -> ApplicationToken? {
        guard request.identifiesExactApplication(
            selectionGeneration: currentSelectionGeneration
        ) else { return nil }
        return try? PropertyListDecoder().decode(ApplicationToken.self, from: request.tokenData)
    }

    func categoryToken(from request: PersistedShieldActionRequest) -> ActivityCategoryToken? {
        guard request.targetKind == .category,
              request.isValid(),
              request.belongsToSelectionGeneration(currentSelectionGeneration)
        else { return nil }
        return try? PropertyListDecoder().decode(ActivityCategoryToken.self, from: request.tokenData)
    }

    /// Reconciles a server-authored lock command after its policy selection has been verified.
    /// Nil means the command was applied; a stable string is returned for the cloud status.
    private func reconcileGuardianControl(
        _ control: FamilyScreenTimeControl?,
        referenceDate: Date = Date()
    ) -> String? {
        guard let control else { return nil }
        let activeUnlockEnd = emergencyWindowStore.load()?.endsAt
        switch control.decision(
            activeUnlockEnd: activeUnlockEnd,
            referenceDate: referenceDate,
            minimumStartDuration: ScreenTimeUsageWindowSchedule.minimumDeviceActivityDuration
        ) {
        case .noCommand:
            return nil
        case .lock:
            relockIfNeeded(referenceDate: referenceDate)
            if !guardianShieldMatchesSelection() {
                _ = shieldSelection()
            }
            return nil
        case .keepUnlock:
            restoreEmergencyWindowIfNeeded(referenceDate: referenceDate)
            return nil
        case .startUnlock(let endDate):
            do {
                _ = try startAllAppsEmergencyWindow(
                    until: endDate,
                    now: referenceDate,
                    sourceLabel: "guardian remote unlock"
                )
                return nil
            } catch {
                appendLog("Guardian remote unlock failed: \(error.localizedDescription)")
                return "remote_unlock_apply_failed"
            }
        case .reject(let errorCode):
            return errorCode
        }
    }

    /// Parent-approved or local-PIN school emergency access opens the whole device temporarily.
    /// It never changes the guardian policy and school/daily shields are restored at expiry.
    @discardableResult
    func startAllAppsEmergencyWindow(
        minutes: Int = 30,
        now: Date = Date(),
        sourceLabel: String = "school emergency unlock"
    ) throws -> Date {
        guard ScreenTimeUsageWindowSchedule.supports(minutes: minutes), minutes <= 60 else {
            throw UnlockError.nonPositiveMinutes
        }
        return try startAllAppsEmergencyWindow(
            until: now.addingTimeInterval(TimeInterval(minutes * 60)),
            now: now,
            sourceLabel: sourceLabel
        )
    }

    @discardableResult
    private func startAllAppsEmergencyWindow(
        until endDate: Date,
        now: Date,
        sourceLabel: String
    ) throws -> Date {
        let duration = endDate.timeIntervalSince(now)
        guard duration >= ScreenTimeUsageWindowSchedule.minimumDeviceActivityDuration,
              duration <= 120 * 60 else {
            throw UnlockError.nonPositiveMinutes
        }
        refreshAuthorizationStatus()
        guard isChildFamilyAuthorizationReady,
              emergencyWindowStore.usesSharedAppGroup else {
            appendLog("Cannot start emergency access: shared App Group storage is unavailable.")
            throw UnlockError.deviceCommandFailed
        }
        guard let committedEndDate = try ScreenTimeRewardWindowLock.withLock({
            let previousEmergencyWindow = emergencyWindowStore.load()
            try ScreenTimeRewardWindowTransaction.commitStart(
                schedule: {
                    try usageWindowScheduler.noteUsageWindow(
                        named: ScreenTimeSharedContract.rewardActivityName,
                        from: now,
                        until: endDate,
                        selection: selection
                    )
                },
                persist: {
                    try emergencyWindowStore.save(.init(startedAt: now, endsAt: endDate, sourceLabel: sourceLabel))
                },
                rollbackPersistence: {
                    if let previousEmergencyWindow {
                        try? emergencyWindowStore.save(previousEmergencyWindow)
                    } else {
                        emergencyWindowStore.clear()
                    }
                },
                rollbackSchedule: {
                    usageWindowScheduler.cancelUsageWindows(named: [ScreenTimeSharedContract.rewardActivityName])
                }
            )
            clearApplicationShieldStores()
            schoolStore.clearAllSettings()
            isShielded = false
            unlockEndsAt = endDate
            scheduleRelock(until: endDate)
            appendLog("Started all-app access until \(ISO8601DateFormatter().string(from: endDate)).")
            return endDate
        }) else {
            appendLog("Cannot start emergency access: the shared Screen Time lock is unavailable.")
            throw UnlockError.deviceCommandFailed
        }
        return committedEndDate
    }

    func encodedApplicationToken(_ token: ApplicationToken) throws -> Data {
        try PropertyListEncoder().encode(token)
    }

    /// 应用网站安全策略。它使用独立 store，奖励解锁和紧急解锁永远不会清除这里的限制。
    func applyWebsiteSafety(enabledDomains: [String], automaticAdultContentFilter: Bool) {
        refreshAuthorizationStatus()
        guard isChildFamilyAuthorizationReady else {
            webSafetyStore.clearAllSettings()
            websiteSafetyIsApplied = false
            appendLog("Website safety waits for child-family authorization.")
            return
        }
        let domains = Set(enabledDomains.prefix(WebsiteSafetyStore.maximumBlockedDomains).map { WebDomain(domain: $0) })
        if automaticAdultContentFilter {
            webSafetyStore.webContent.blockedByFilter = .auto(domains, except: [])
        } else if domains.isEmpty {
            webSafetyStore.webContent.blockedByFilter = nil
        } else {
            webSafetyStore.webContent.blockedByFilter = .specific(domains)
        }
        websiteSafetyDomainCount = domains.count
        websiteSafetyIsApplied = automaticAdultContentFilter || !domains.isEmpty
        appendLog("Website safety applied: automatic \(automaticAdultContentFilter), supplemental domains \(domains.count).")
    }

    /// 把当前设备绑定孩子的学校规则同步到独立 DeviceActivity/ManagedSettings store。
    /// 学校 store 与奖励、网站安全完全隔离，解除学校模式不会清除其他限制。
    func synchronizeSchoolMode(profile: ChildSchoolModeProfile, at date: Date = Date()) {
        guard ScreenTimeRewardWindowLock.withLock({
            synchronizeSchoolModeWhileLocked(profile: profile, at: date)
        }) != nil else {
            schoolModeLastError = "共享 Screen Time 锁不可用"
            appendLog("School mode synchronization failed because the shared lock is unavailable.")
            return
        }
    }

    private func synchronizeSchoolModeWhileLocked(profile: ChildSchoolModeProfile, at date: Date) {
        refreshAuthorizationStatus()
        let runtime = Self.schoolRuntime(from: profile, referenceDate: date)
        let previous = schoolModeRuntimeStore.load()

        guard profile.isEnabled else {
            schoolModeScheduler.cancel(activityNames: previous?.activityNames ?? [])
            schoolModeRuntimeStore.clear()
            schoolStore.clearAllSettings()
            schoolModeIsActive = false
            schoolModeEndsAt = nil
            schoolModeLastError = nil
            sharedDefaults.set(false, forKey: ScreenTimeSharedContract.schoolModeActiveKey)
            return
        }
        guard isChildFamilyAuthorizationReady else {
            schoolModeScheduler.cancel(activityNames: previous?.activityNames ?? [])
            schoolModeRuntimeStore.clear()
            schoolStore.clearAllSettings()
            schoolModeLastError = "儿童设备控制尚未授权"
            schoolModeIsActive = false
            schoolModeEndsAt = nil
            sharedDefaults.set(false, forKey: ScreenTimeSharedContract.schoolModeActiveKey)
            return
        }
        guard selectionStore.usesSharedAppGroup,
              schoolModeRuntimeStore.usesSharedAppGroup else {
            schoolModeScheduler.cancel(activityNames: previous?.activityNames ?? [])
            schoolModeRuntimeStore.clear()
            schoolStore.clearAllSettings()
            schoolModeLastError = "App Group 尚未生效，后台学校时段无法可靠执行"
            schoolModeIsActive = false
            schoolModeEndsAt = nil
            sharedDefaults.set(false, forKey: ScreenTimeSharedContract.schoolModeActiveKey)
            return
        }

        let evaluation = SchoolModeRuleEngine.evaluate(profile: profile, at: date)
        do {
            try SchoolModeSynchronizationTransaction.commit(
                previous: previous,
                desired: runtime,
                replaceSchedules: {
                    try schoolModeScheduler.replaceSchedules(
                        previousActivityNames: previous?.activityNames ?? [],
                        with: runtime
                    )
                },
                persistRuntime: {
                    try schoolModeRuntimeStore.save(runtime)
                },
                applyCurrentState: {
                    if evaluation.isActive && !emergencyUnlockIsActive {
                        guard applySchoolShield() else {
                            throw ScreenTimeRewardMutationError.shieldVerificationFailed
                        }
                    } else {
                        schoolStore.clearAllSettings()
                    }
                },
                rollback: {
                    schoolModeScheduler.cancel(activityNames: runtime.activityNames)
                    schoolModeRuntimeStore.clear()
                    schoolStore.clearAllSettings()
                    schoolModeIsActive = false
                    schoolModeEndsAt = nil
                    sharedDefaults.set(false, forKey: ScreenTimeSharedContract.schoolModeActiveKey)
                }
            )
            schoolModeIsActive = evaluation.isActive
            sharedDefaults.set(evaluation.isActive, forKey: ScreenTimeSharedContract.schoolModeActiveKey)
            schoolModeEndsAt = evaluation.isActive ? evaluation.endsAt : nil
            schoolModeLastError = nil
            appendLog("School mode synchronized; active \(evaluation.isActive), schedules \(runtime.activityNames.count).")
        } catch {
            schoolModeLastError = error.localizedDescription
            appendLog("School mode scheduling failed: \(error.localizedDescription)")
        }
    }

    func relockRewardWindow() {
        guard ScreenTimeRewardWindowLock.withLock({ relockAllRewardWindowsWhileLocked() }) != nil else {
            appendLog("Could not end reward windows because the shared lock is unavailable.")
            return
        }
    }

    private func relockAllRewardWindowsWhileLocked() {
        let windows = rewardWindowStore.loadAll()
        guard persistCompensationIntents(for: windows, requestedAt: Date()) else { return }
        do {
            try persistAndApplyRewardWindows([], referenceDate: Date())
            try rewardCompensationStore.remove(ids: Set(windows.map(\.resolvedID)))
            cancelUsageWindows(windows)
            appendLog("Ended all app reward windows.")
        } catch {
            scheduleRelock(until: Date().addingTimeInterval(5))
            appendLog("Could not end reward windows; durable compensation remains pending: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func relockRewardWindow(
        for applicationToken: ApplicationToken,
        referenceDate: Date = Date()
    ) -> PersistedScreenTimeRewardWindow? {
        guard let removed = ScreenTimeRewardWindowLock.withLock({ () -> PersistedScreenTimeRewardWindow? in
            guard let tokenData = try? PropertyListEncoder().encode(applicationToken) else { return nil }
            let stored = rewardWindowStore.loadAll()
            let result = ScreenTimeRewardWindowLedger.removing(
                applicationTokenData: tokenData,
                from: stored,
                at: referenceDate,
                systemUptime: ProcessInfo.processInfo.systemUptime
            )
            guard let removed = result.removed else { return nil }
            let remaining = activeRewardWindows(at: referenceDate, from: result.remaining)
            let remainingIDs = Set(remaining.map(\.resolvedID))
            let removedByMutation = stored.filter { !remainingIDs.contains($0.resolvedID) }
            guard persistCompensationIntents(
                for: removedByMutation,
                requestedAt: referenceDate
            ) else { return nil }
            do {
                try persistAndApplyRewardWindows(remaining, referenceDate: referenceDate)
                try rewardCompensationStore.remove(ids: Set(removedByMutation.map(\.resolvedID)))
            } catch {
                scheduleRelock(until: Date().addingTimeInterval(5))
                appendLog("Could not end one app reward window; durable compensation remains pending: \(error.localizedDescription)")
                return nil
            }
            cancelUsageWindows(removedByMutation)
            appendLog("Ended one app reward window; \(remaining.count) app window(s) remain active.")
            return removed
        }) else {
            appendLog("Could not end one app reward window because the shared lock is unavailable.")
            return nil
        }
        return removed
    }

    @discardableResult
    func relockRewardWindow(
        for categoryToken: ActivityCategoryToken,
        referenceDate: Date = Date()
    ) -> PersistedScreenTimeRewardWindow? {
        guard let tokenData = try? PropertyListEncoder().encode(categoryToken),
              let id = activeRewardWindows(at: referenceDate).first(where: {
                  $0.resolvedTargetKind == .category &&
                      $0.applicationTokenData == tokenData
              })?.resolvedID
        else { return nil }
        return relockRewardWindow(id: id, referenceDate: referenceDate)
    }

    @discardableResult
    func relockRewardWindow(id: UUID, referenceDate: Date = Date()) -> PersistedScreenTimeRewardWindow? {
        guard let removed = ScreenTimeRewardWindowLock.withLock({ () -> PersistedScreenTimeRewardWindow? in
            let stored = rewardWindowStore.loadAll()
            guard let removed = stored.first(where: { $0.resolvedID == id }) else { return nil }
            let remaining = activeRewardWindows(
                at: referenceDate,
                from: stored.filter { $0.resolvedID != id }
            )
            let remainingIDs = Set(remaining.map(\.resolvedID))
            let removedByMutation = stored.filter { !remainingIDs.contains($0.resolvedID) }
            guard persistCompensationIntents(
                for: removedByMutation,
                requestedAt: referenceDate
            ) else { return nil }
            do {
                try persistAndApplyRewardWindows(remaining, referenceDate: referenceDate)
                try rewardCompensationStore.remove(ids: Set(removedByMutation.map(\.resolvedID)))
            } catch {
                scheduleRelock(until: Date().addingTimeInterval(5))
                appendLog("Could not roll back one app reward window; durable compensation remains pending: \(error.localizedDescription)")
                return nil
            }
            cancelUsageWindows(removedByMutation)
            appendLog("Rolled back one app reward window; \(remaining.count) app window(s) remain active.")
            return removed
        }) else {
            appendLog("Could not roll back one app reward window because the shared lock is unavailable.")
            return nil
        }
        return removed
    }

    func relockIfNeeded(referenceDate: Date = Date()) {
        guard ScreenTimeRewardWindowLock.withLock({
            relockIfNeededWhileLocked(referenceDate: referenceDate)
        }) != nil else {
            scheduleRelock(until: Date().addingTimeInterval(5))
            appendLog("Relock retry deferred because the shared lock is unavailable.")
            return
        }
    }

    private func relockIfNeededWhileLocked(referenceDate: Date) {
        if let emergency = emergencyWindowStore.load(),
           ScreenTimeSharedContract.emergencyDefersShieldRestoration(emergency, at: referenceDate) {
            unlockEndsAt = emergency.endsAt
            scheduleRelock(until: emergency.endsAt)
            return
        }
        guard retryPendingRewardCompensationsWhileLocked(referenceDate: referenceDate) else { return }
        if let emergency = emergencyWindowStore.load(), referenceDate >= emergency.endsAt {
            if restoreGuardianEnforcement(referenceDate: referenceDate) {
                appendLog("Wall-clock emergency window ended; guardian shield reapplied.")
            }
            return
        }
        let stored = rewardWindowStore.loadAll()
        let active = activeRewardWindows(at: referenceDate, from: stored)
        guard active.count != stored.count else {
            updateRewardWindowRuntime(active, referenceDate: referenceDate)
            return
        }
        let activeIDs = Set(active.map(\.resolvedID))
        let expired = stored.filter { !activeIDs.contains($0.resolvedID) }
        guard persistCompensationIntents(for: expired, requestedAt: referenceDate) else { return }
        do {
            try persistAndApplyRewardWindows(active, referenceDate: referenceDate)
            try rewardCompensationStore.remove(ids: Set(expired.map(\.resolvedID)))
        } catch {
            scheduleRelock(until: referenceDate.addingTimeInterval(5))
            appendLog("Could not commit expired reward windows; previous state was retained and retry scheduled: \(error.localizedDescription)")
            return
        }
        cancelUsageWindows(expired)
        appendLog("Expired app reward window(s) relocked; \(active.count) app window(s) remain active.")
    }

    func completeLocalTestTaskAndUnlockForTwoMinutes() {
        appendLog("Local test task marked complete for POC.")
        unlockForTesting(minutes: 2)
    }

    func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        logs.insert("\(formatter.string(from: Date())) \(message)", at: 0)
        if logs.count > 40 {
            logs.removeLast(logs.count - 40)
        }
    }

    private static func counts(for selection: FamilyActivitySelection) -> ScreenTimeSelectionCounts {
        ScreenTimeSelectionCounts(
            applications: selection.applicationTokens.count,
            categories: selection.categoryTokens.count,
            webDomains: selection.webDomainTokens.count
        )
    }

    @discardableResult
    private func applySchoolShield() -> Bool {
        schoolStore.shield.applications = nil
        schoolStore.shield.applicationCategories = .all()
        schoolStore.shield.webDomains = nil
        return schoolStore.shield.applications == nil &&
            schoolStore.shield.applicationCategories != nil &&
            schoolStore.shield.webDomains == nil
    }

    private static func schoolRuntime(
        from profile: ChildSchoolModeProfile,
        referenceDate: Date
    ) -> PersistedSchoolModeRuntime {
        let rules = profile.weekdayRules
            .filter { $0.isEnabled && $0.hasValidWindow }
            .map {
                PersistedSchoolModeRule(
                    weekday: $0.weekday,
                    startMinutes: $0.startMinutes,
                    endMinutes: $0.endMinutes
                )
            }
        let todayKey = PersistedSchoolModeRuntime.dateKey(for: referenceDate)
        let exceptions = profile.exceptions
            .filter(\.guardianConfirmed)
            .filter { $0.dateKey >= todayKey }
            .prefix(60)
            .map {
                PersistedSchoolModeException(
                    dateKey: $0.dateKey,
                    isHoliday: $0.kind == .holiday,
                    startMinutes: $0.startMinutes,
                    endMinutes: $0.endMinutes
                )
            }
        let weeklyNames = rules.map { "\(ScreenTimeSharedContract.schoolActivityPrefix)weekly.\($0.weekday)" }
        let overrideNames = exceptions.filter { !$0.isHoliday }.map {
            "\(ScreenTimeSharedContract.schoolActivityPrefix)override.\($0.dateKey)"
        }
        return PersistedSchoolModeRuntime(
            childID: profile.childID,
            isEnabled: profile.isEnabled,
            defaultStartMinutes: profile.defaultStartMinutes,
            defaultEndMinutes: profile.defaultEndMinutes,
            rules: rules,
            exceptions: exceptions,
            activityNames: weeklyNames + overrideNames
        )
    }

    @discardableResult
    private func applyRewardWindows(_ windows: [PersistedScreenTimeRewardWindow]) -> Bool {
        let activeApplicationTokens: Set<ApplicationToken> = Set(windows.compactMap {
            guard $0.resolvedTargetKind == .application else { return nil }
            return try? PropertyListDecoder().decode(
                ApplicationToken.self,
                from: $0.applicationTokenData
            )
        })
        let activeCategoryTokens: Set<ActivityCategoryToken> = Set(windows.compactMap {
            guard $0.resolvedTargetKind == .category else { return nil }
            return try? PropertyListDecoder().decode(
                ActivityCategoryToken.self,
                from: $0.applicationTokenData
            )
        })
        return applyGuardianShields(
            activeRewardTokens: activeApplicationTokens,
            activeRewardCategoryTokens: activeCategoryTokens,
            operation: "multi_app_reward_windows"
        )
    }

    private func restoreRewardWindowIfNeeded(referenceDate: Date = Date()) {
        guard ScreenTimeRewardWindowLock.withLock({
            restoreRewardWindowWhileLocked(referenceDate: referenceDate)
        }) != nil else {
            appendLog("Reward-window restore deferred because the shared lock is unavailable.")
            return
        }
    }

    private func restoreRewardWindowWhileLocked(referenceDate: Date) {
        guard !ScreenTimeSharedContract.emergencyDefersShieldRestoration(
            emergencyWindowStore.load(),
            at: referenceDate
        ) else { return }
        guard retryPendingRewardCompensationsWhileLocked(referenceDate: referenceDate) else { return }
        let stored = rewardWindowStore.loadAll()
        guard !stored.isEmpty else { return }
        let windows = activeRewardWindows(at: referenceDate, from: stored)
        guard authorizationState == .approved else {
            unlockEndsAt = windows.map(\.endsAt).max()
            return
        }
        let needsLegacyMigration = rewardWindowStore.containsLegacyWindow
        guard convergeStoredRewardWindowsWhileLocked(
            stored: stored,
            active: windows,
            referenceDate: referenceDate,
            operation: "Startup reward-window convergence",
            preparePersistence: {
                if needsLegacyMigration {
                    try migrateLegacyRewardWindows(windows)
                }
            }
        ) else {
            if !windows.isEmpty {
                let applied = applyRewardWindows(windows)
                updateRewardWindowRuntime(windows, referenceDate: referenceDate)
                appendLog("Active reward windows remain usable while startup convergence retries; shield verified \(applied).")
            }
            return
        }
        appendLog(windows.isEmpty
            ? "Startup convergence relocked all expired reward windows."
            : "Restored \(windows.count) active app reward window(s).")
    }

    private func restoreEmergencyWindowIfNeeded(referenceDate: Date = Date()) {
        guard ScreenTimeRewardWindowLock.withLock({
            restoreEmergencyWindowWhileLocked(referenceDate: referenceDate)
        }) != nil else {
            appendLog("Emergency-window restore deferred because the shared lock is unavailable.")
            return
        }
    }

    private func restoreEmergencyWindowWhileLocked(referenceDate: Date) {
        guard let window = emergencyWindowStore.load() else { return }
        guard window.endsAt > referenceDate else {
            emergencyWindowStore.clear()
            usageWindowScheduler.cancelUsageWindows(named: [ScreenTimeSharedContract.rewardActivityName])
            _ = restoreGuardianEnforcement(referenceDate: referenceDate)
            return
        }
        clearApplicationShieldStores()
        schoolStore.clearAllSettings()
        isShielded = false
        unlockEndsAt = window.endsAt
        scheduleRelock(until: window.endsAt)
        appendLog("Restored active all-app emergency access after relaunch.")
    }

    private func scheduleRelock(until endDate: Date) {
        relockTask?.cancel()
        relockTask = Task { [weak self] in
            let seconds = max(0, endDate.timeIntervalSince(Date()))
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                try Task.checkCancellation()
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.relockIfNeeded(referenceDate: Date())
            }
        }
    }

    private func activeRewardWindows(at date: Date) -> [PersistedScreenTimeRewardWindow] {
        activeRewardWindows(at: date, from: rewardWindowStore.loadAll())
    }

    private func activeRewardWindows(
        at date: Date,
        from windows: [PersistedScreenTimeRewardWindow]
    ) -> [PersistedScreenTimeRewardWindow] {
        ScreenTimeRewardWindowLedger.active(
            windows,
            at: date,
            systemUptime: ProcessInfo.processInfo.systemUptime
        ).filter { window in
            guard window.belongsToSelectionGeneration(currentSelectionGeneration) else {
                return false
            }
            switch window.resolvedTargetKind {
            case .application:
                guard let token = try? PropertyListDecoder().decode(
                    ApplicationToken.self,
                    from: window.applicationTokenData
                ) else { return false }
                return !selection.categoryTokens.isEmpty || selection.applicationTokens.contains(token)
            case .category:
                guard let token = try? PropertyListDecoder().decode(
                    ActivityCategoryToken.self,
                    from: window.applicationTokenData
                ) else { return false }
                return selection.categoryTokens.contains(token)
            case .webDomain:
                return false
            }
        }
    }

    private func persistAndApplyRewardWindows(
        _ windows: [PersistedScreenTimeRewardWindow],
        referenceDate: Date
    ) throws {
        let committedWindows = activeRewardWindows(at: referenceDate, from: windows)
        try ScreenTimeRewardWindowTransaction.commitMutation(
            persist: { try rewardWindowStore.saveAll(committedWindows) },
            apply: { try applyPersistedRewardWindows(committedWindows, referenceDate: referenceDate) },
            cancelObsoleteSchedules: {}
        )
    }

    private func convergeStoredRewardWindowsWhileLocked(
        stored: [PersistedScreenTimeRewardWindow],
        active: [PersistedScreenTimeRewardWindow],
        referenceDate: Date,
        operation: String,
        preparePersistence: () throws -> Void = {}
    ) -> Bool {
        let activeIDs = Set(active.map(\.resolvedID))
        let removed = stored.filter { !activeIDs.contains($0.resolvedID) }
        let removedIDs = Set(removed.map(\.resolvedID))
        var writeAheadWasVerified = false

        do {
            if removed.isEmpty {
                try preparePersistence()
                try persistAndApplyRewardWindows(active, referenceDate: referenceDate)
            } else {
                try ScreenTimeRewardWindowTransaction.commitCompensatedMutation(
                    persistCompensation: {
                        try rewardCompensationStore.add(
                            ids: Array(removedIDs),
                            requestedAt: referenceDate
                        )
                        writeAheadWasVerified = true
                    },
                    persistAndApply: {
                        try preparePersistence()
                        try persistAndApplyRewardWindows(active, referenceDate: referenceDate)
                    },
                    cancelObsoleteSchedules: { cancelUsageWindows(removed) },
                    clearCompensation: { try rewardCompensationStore.remove(ids: removedIDs) }
                )
            }
            return true
        } catch {
            scheduleRelock(until: Date().addingTimeInterval(5))
            guard !removedIDs.isEmpty else {
                appendLog("\(operation) failed without removing a ledger entry; retry scheduled: \(error.localizedDescription)")
                return false
            }
            if writeAheadWasVerified {
                appendLog("\(operation) failed; durable compensation remains pending for retry: \(error.localizedDescription)")
            } else {
                appendLog("\(operation) stopped before its write-ahead intent was verified; the ledger mutation did not begin: \(error.localizedDescription)")
            }
            return false
        }
    }

    private func applyPersistedRewardWindows(
        _ windows: [PersistedScreenTimeRewardWindow],
        referenceDate: Date
    ) throws {
        if windows.isEmpty {
            unlockEndsAt = nil
            relockTask?.cancel()
            if selectionCounts.hasSelection {
                guard applyGuardianShields(
                    activeRewardTokens: [],
                    operation: "reward_windows_finished"
                ) else {
                    throw ScreenTimeRewardMutationError.shieldVerificationFailed
                }
            } else {
                clearApplicationShieldStores()
                isShielded = false
                guard appliedApplicationTokens.isEmpty else {
                    throw ScreenTimeRewardMutationError.shieldVerificationFailed
                }
            }
            return
        }
        guard applyRewardWindows(windows) else {
            throw ScreenTimeRewardMutationError.shieldVerificationFailed
        }
        updateRewardWindowRuntime(windows, referenceDate: referenceDate)
    }

    private func updateRewardWindowRuntime(
        _ windows: [PersistedScreenTimeRewardWindow],
        referenceDate: Date
    ) {
        let active = ScreenTimeRewardWindowLedger.active(
            windows,
            at: referenceDate,
            systemUptime: ProcessInfo.processInfo.systemUptime
        )
        unlockEndsAt = active.map(\.endsAt).max()
        guard let nextEnd = active.map(\.endsAt).min() else {
            relockTask?.cancel()
            return
        }
        scheduleRelock(until: nextEnd)
    }

    private func cancelUsageWindows(_ windows: [PersistedScreenTimeRewardWindow]) {
        let names = windows.map { ScreenTimeSharedContract.rewardActivityName(for: $0.resolvedID) }
        usageWindowScheduler.cancelUsageWindows(named: names)
    }

    private func migrateLegacyRewardWindows(_ windows: [PersistedScreenTimeRewardWindow]) throws {
        let windowsByActivityName = Dictionary(uniqueKeysWithValues: windows.map {
            (ScreenTimeSharedContract.rewardActivityName(for: $0.resolvedID), $0)
        })
        let activityNames = windows.map {
            ScreenTimeSharedContract.rewardActivityName(for: $0.resolvedID)
        }
        try ScreenTimeRewardWindowTransaction.commitLegacyMigration(
            activityNames: activityNames,
            register: { activityName in
                guard let window = windowsByActivityName[activityName] else {
                    throw ScreenTimeRewardMutationError.shieldVerificationFailed
                }
                try usageWindowScheduler.noteUsageWindow(
                    named: activityName,
                    from: window.startedAt,
                    until: window.endsAt,
                    selection: selection
                )
            },
            persistV2: { try rewardWindowStore.saveAll(windows) },
            cancelRegistered: { usageWindowScheduler.cancelUsageWindows(named: $0) },
            cancelLegacy: {
                usageWindowScheduler.cancelUsageWindows(
                    named: [ScreenTimeSharedContract.rewardActivityName]
                )
            }
        )
    }

    private func rollbackStartedRewardWindow(
        window: PersistedScreenTimeRewardWindow,
        previousWindows: [PersistedScreenTimeRewardWindow],
        referenceDate: Date
    ) throws {
        let id = window.resolvedID
        var compensationIsDurable = false
        do {
            try rewardCompensationStore.add(id: id, requestedAt: referenceDate)
            compensationIsDurable = true
        } catch {
            appendLog("Could not persist reward rollback intent: \(error.localizedDescription)")
        }

        usageWindowScheduler.cancelUsageWindows(
            named: [ScreenTimeSharedContract.rewardActivityName(for: id)]
        )
        let restoredWindows = activeRewardWindows(at: referenceDate, from: previousWindows)
        do {
            try rewardWindowStore.saveAll(restoredWindows)
            try applyPersistedRewardWindows(restoredWindows, referenceDate: referenceDate)
            if compensationIsDurable {
                try rewardCompensationStore.remove(ids: [id])
            }
        } catch {
            _ = applyRewardWindows(restoredWindows)
            scheduleRelock(until: Date().addingTimeInterval(5))
            appendLog("Reward rollback remains pending and will retry: \(error.localizedDescription)")
            throw error
        }
    }

    private func persistCompensationIntents(
        for windows: [PersistedScreenTimeRewardWindow],
        requestedAt: Date
    ) -> Bool {
        guard !windows.isEmpty else { return true }
        do {
            try rewardCompensationStore.add(
                ids: windows.map(\.resolvedID),
                requestedAt: requestedAt
            )
            return true
        } catch {
            scheduleRelock(until: Date().addingTimeInterval(5))
            appendLog("Could not persist reward compensation; relock did not proceed: \(error.localizedDescription)")
            return false
        }
    }

    private func retryPendingRewardCompensationsWhileLocked(referenceDate: Date) -> Bool {
        if !rewardCompensationStore.isReadable {
            let stored = rewardWindowStore.loadAll()
            do {
                try persistAndApplyRewardWindows([], referenceDate: referenceDate)
                try rewardCompensationStore.clear()
                cancelUsageWindows(stored)
                appendLog("Unreadable reward compensation failed closed by ending all reward windows.")
                return true
            } catch {
                scheduleRelock(until: Date().addingTimeInterval(5))
                appendLog("Unreadable reward compensation could not fail closed yet: \(error.localizedDescription)")
                return false
            }
        }
        let compensations = rewardCompensationStore.load()
        guard !compensations.isEmpty else { return true }
        let result = ScreenTimeRewardCompensationLedger.applying(
            compensations,
            to: rewardWindowStore.loadAll()
        )
        do {
            try persistAndApplyRewardWindows(result.remaining, referenceDate: referenceDate)
            try rewardCompensationStore.remove(ids: Set(compensations.map(\.id)))
            cancelUsageWindows(result.removed)
            appendLog("Completed \(compensations.count) pending reward compensation(s).")
            return true
        } catch {
            scheduleRelock(until: Date().addingTimeInterval(5))
            appendLog("Pending reward compensation retry failed: \(error.localizedDescription)")
            return false
        }
    }

    private func isValidShieldApplicationRequest(id: UUID, token: ApplicationToken, at date: Date) -> Bool {
        guard let request = shieldActionStore.load(at: date),
              let tokenData = try? PropertyListEncoder().encode(token)
        else {
            return false
        }

        return request.authorizesApplication(
            requestID: id,
            tokenData: tokenData,
            at: date,
            selectionGeneration: currentSelectionGeneration
        )
    }

    private func isValidShieldCategoryRequest(
        id: UUID,
        token: ActivityCategoryToken,
        at date: Date
    ) -> Bool {
        guard let request = shieldActionStore.load(at: date),
              let tokenData = try? PropertyListEncoder().encode(token)
        else { return false }
        return request.authorizesCategory(
            requestID: id,
            tokenData: tokenData,
            at: date,
            selectionGeneration: currentSelectionGeneration
        )
    }

    @discardableResult
    private func restoreGuardianEnforcement(referenceDate: Date = Date()) -> Bool {
        usageWindowScheduler.cancelUsageWindows(named: [ScreenTimeSharedContract.rewardActivityName])
        emergencyWindowStore.clear()
        guard retryPendingRewardCompensationsWhileLocked(referenceDate: referenceDate) else {
            appendLog("Emergency access ended, but guardian enforcement convergence remains pending.")
            return false
        }
        let stored = rewardWindowStore.loadAll()
        let active = activeRewardWindows(at: referenceDate, from: stored)
        guard convergeStoredRewardWindowsWhileLocked(
            stored: stored,
            active: active,
            referenceDate: referenceDate,
            operation: "Post-emergency guardian convergence"
        ) else { return false }
        if sharedDefaults.bool(forKey: ScreenTimeSharedContract.schoolModeActiveKey) {
            guard applySchoolShield() else {
                scheduleRelock(until: Date().addingTimeInterval(5))
                appendLog("Post-emergency school shield verification failed; retry scheduled.")
                return false
            }
            schoolModeIsActive = true
        }
        return true
    }

    private func rewardShieldMatches(
        activeRewardTokens: Set<ApplicationToken>,
        activeRewardCategoryTokens: Set<ActivityCategoryToken> = []
    ) -> Bool {
        guard ScreenTimeSharedContract.activeRewardApplicationsAreValid(
            activeRewardTokens,
            guardianApplications: selection.applicationTokens,
            hasGuardianCategories: !selection.categoryTokens.isEmpty
        ), activeRewardCategoryTokens.isSubset(of: selection.categoryTokens)
        else { return false }

        let categoryExceptions = ScreenTimeSharedContract.categoryShieldExceptions(
            guardianApplications: selection.applicationTokens,
            activeRewardApplications: activeRewardTokens
        )
        let expectedCategories = ScreenTimeSharedContract.expectedShieldCategories(
            guardianCategories: selection.categoryTokens,
            activeRewardCategories: activeRewardCategoryTokens
        )
        let expectedCategoryPolicy: ShieldSettings.ActivityCategoryPolicy<Application>? =
            expectedCategories.isEmpty
                ? nil
                : .specific(expectedCategories, except: categoryExceptions)
        let enforcementMatches: Bool
        switch applicationShieldStrategy {
        case .preciseApplications:
            enforcementMatches = ScreenTimeSharedContract.rewardShieldApplicationsMatch(
                guardianApplications: selection.applicationTokens,
                activeRewardApplications: activeRewardTokens,
                appliedApplications: appliedApplicationTokens
            ) && shieldStore.shield.applicationCategories == nil
        case .applicationsAndCategories:
            enforcementMatches = appliedApplicationTokens ==
                ScreenTimeSharedContract.expectedShieldApplications(
                    guardianApplications: selection.applicationTokens,
                    activeRewardApplications: activeRewardTokens
                ) && shieldStore.shield.applicationCategories == expectedCategoryPolicy
        case .categories:
            enforcementMatches = appliedApplicationTokens.isEmpty &&
                shieldStore.shield.applicationCategories == expectedCategoryPolicy
        case .none, .unsupportedTooManyApplications:
            enforcementMatches = false
        }
        return enforcementMatches &&
            (shieldStore.shield.webDomains ?? []) == selection.webDomainTokens
    }

    private func applicationShieldStore(at index: Int) -> ManagedSettingsStore {
        index == 0
            ? shieldStore
            : ManagedSettingsStore(
                named: ManagedSettingsStore.Name(
                    ScreenTimeSharedContract.applicationShieldStoreName(at: index)
                )
            )
    }

    private var appliedApplicationTokens: Set<ApplicationToken> {
        (0..<ScreenTimeSharedContract.maximumApplicationShieldStoreCount)
            .reduce(into: Set<ApplicationToken>()) { result, index in
                result.formUnion(
                    applicationShieldStore(at: index).shield.applications ?? []
                )
            }
    }

    @discardableResult
    private func applyGuardianShields(
        activeRewardTokens: Set<ApplicationToken>,
        activeRewardCategoryTokens: Set<ActivityCategoryToken> = [],
        operation: String
    ) -> Bool {
        guard applicationShieldStrategy.isSupported,
              ScreenTimeSharedContract.activeRewardApplicationsAreValid(
                  activeRewardTokens,
                  guardianApplications: selection.applicationTokens,
                  hasGuardianCategories: !selection.categoryTokens.isEmpty
              ), activeRewardCategoryTokens.isSubset(of: selection.categoryTokens)
        else {
            lastShieldError = applicationShieldStrategy == .unsupportedTooManyApplications
                ? "application_selection_exceeds_apple_limit"
                : "managed_settings_write_mismatch"
            return false
        }

        let expectedApplications = ScreenTimeSharedContract.expectedShieldApplications(
            guardianApplications: selection.applicationTokens,
            activeRewardApplications: activeRewardTokens
        )
        let categoryExceptions = ScreenTimeSharedContract.categoryShieldExceptions(
            guardianApplications: selection.applicationTokens,
            activeRewardApplications: activeRewardTokens
        )
        let expectedCategories = ScreenTimeSharedContract.expectedShieldCategories(
            guardianCategories: selection.categoryTokens,
            activeRewardCategories: activeRewardCategoryTokens
        )
        guard let applicationShards = ScreenTimeSharedContract.applicationShieldShards(
            expectedApplications
        ) else {
            lastShieldError = "application_selection_exceeds_apple_limit"
            return false
        }

        clearApplicationShieldStores()
        for (index, shard) in applicationShards.enumerated() {
            let store = applicationShieldStore(at: index)
            if #available(iOS 26.5, *) {
                store.isActive = true
            }
            store.shield.applications = shard
        }
        if #available(iOS 26.5, *),
           applicationShards.isEmpty,
           (!expectedCategories.isEmpty || !selection.webDomainTokens.isEmpty) {
            shieldStore.isActive = true
        }
        switch applicationShieldStrategy {
        case .preciseApplications:
            shieldStore.shield.applicationCategories = nil
        case .applicationsAndCategories:
            shieldStore.shield.applicationCategories = expectedCategories.isEmpty
                ? nil
                : .specific(expectedCategories, except: categoryExceptions)
        case .categories:
            shieldStore.shield.applicationCategories = expectedCategories.isEmpty
                ? nil
                : .specific(expectedCategories, except: categoryExceptions)
        case .none, .unsupportedTooManyApplications:
            return false
        }
        shieldStore.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        sharedDefaults.set(
            applicationShards.count,
            forKey: ScreenTimeSharedContract.applicationShieldShardCountKey
        )
        _ = syncShieldStateFromStore(operation: operation)
        return rewardShieldMatches(
            activeRewardTokens: activeRewardTokens,
            activeRewardCategoryTokens: activeRewardCategoryTokens
        )
    }

    private func clearApplicationShieldStores() {
        for index in 0..<ScreenTimeSharedContract.maximumApplicationShieldStoreCount {
            applicationShieldStore(at: index).clearAllSettings()
        }
        sharedDefaults.removeObject(forKey: ScreenTimeSharedContract.applicationShieldShardCountKey)
    }

    private static func mapAuthorizationStatus(_ status: AuthorizationStatus) -> ScreenTimePOCAuthorizationState {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .approved: return .approved
        default: return .unknown
        }
    }

    private func revokeCurrentAuthorization() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            AuthorizationCenter.shared.revokeAuthorization { result in
                continuation.resume(with: result)
            }
        }
        authorizationPurposeStore.clear()
        authorizationPurpose = nil
    }
}

private enum ScreenTimeRewardMutationError: Error {
    case shieldVerificationFailed
    case controlCommandFailed(String)
}

private enum ScreenTimeRoleError: LocalizedError {
    case childAuthorizationNotApproved

    var errorDescription: String? {
        "儿童设备控制授权未完成，请由家庭共享中的监护人在系统页面确认。"
    }
}
#endif
