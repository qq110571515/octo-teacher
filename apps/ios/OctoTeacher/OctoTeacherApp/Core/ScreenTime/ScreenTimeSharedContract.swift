import Foundation
import Darwin
import CryptoKit

enum ScreenTimeSharedContract {
    enum ApplicationShieldStrategy: Equatable {
        case none
        case preciseApplications
        case applicationsAndCategories
        case categories
        case unsupportedTooManyApplications

        var isSupported: Bool {
            self == .preciseApplications || self == .applicationsAndCategories || self == .categories
        }
    }

    enum StaleEnforcementResetAction: Equatable {
        case skip
        case adoptStandardMarker
        case clearExecutionStatePreservingSelection
    }

    static let appGroupIdentifier = "group.com.octoteacher.app"
    static let selectionKey = "octoteacher.screentime.familyActivitySelection"
    static let selectionGenerationKey = "octoteacher.screentime.selectionGeneration.v1"
    static let activeRewardWindowKey = "octoteacher.screentime.activeRewardWindow"
    static let activeRewardWindowsKey = "octoteacher.screentime.activeRewardWindows.v2"
    static let rewardStoreName = "rewardUnlock"
    static let applicationShieldShardCountKey = "octoteacher.screentime.applicationShieldShardCount"
    static let maximumApplicationTokensPerShieldStore = 50
    static let maximumApplicationShieldStoreCount = 40
    static let maximumApplicationTokenCapacity =
        maximumApplicationTokensPerShieldStore * maximumApplicationShieldStoreCount
    static let webSafetyStoreName = "webSafety"
    static let schoolStoreName = "schoolMode"
    static let rewardActivityName = "octoteacher.reward-window"
    static let rewardActivityPrefix = "octoteacher.reward-window."
    static let schoolActivityPrefix = "octoteacher.school-mode."
    static let schoolRuntimeKey = "octoteacher.screentime.schoolModeRuntime"
    static let schoolModeActiveKey = "octoteacher.screentime.schoolModeActive"
    static let pendingShieldActionKey = "octoteacher.screentime.pendingShieldAction"
    static let pendingRewardCompensationsKey = "octoteacher.screentime.pendingRewardCompensations.v1"
    static let activeEmergencyWindowKey = "octoteacher.screentime.activeEmergencyWindow"
    static let childInterfaceLanguageKey = "octoteacher.screentime.childInterfaceLanguage"
    static let childInterfaceLanguageSnapshotKey = "octoteacher.screentime.childInterfaceLanguage.v2"
    static let authorizationPurposeKey = "octoteacher.screentime.authorizationPurpose"
    static let appliedPolicyRevisionKey = "octoteacher.screentime.appliedPolicyRevision"
    static let appliedPolicySelectionHashKey = "octoteacher.screentime.appliedPolicySelectionHash.v3"
    static let appliedControlCommandIDKey = "octoteacher.screentime.appliedControlCommandID.v1"
    static let appliedControlModeKey = "octoteacher.screentime.appliedControlMode.v1"
    static let appliedControlUnlockUntilKey = "octoteacher.screentime.appliedControlUnlockUntil.v1"
    static let syncedGuardianPolicyKey = "octoteacher.screentime.syncedGuardianPolicy.v3"
    static let localChildSelectionCompletedKey = "octoteacher.screentime.localChildSelection.v1.completed"
    static let selectionRequiresExplicitAppReselectionKey =
        "octoteacher.screentime.selectionRequiresExplicitAppReselection.v1"
    static let shieldDiagnosticKey = "octoteacher.screentime.shieldDiagnostic.v1"
    static let rewardRelockDiagnosticKey = "octoteacher.screentime.rewardRelockDiagnostic.v1"
    static let operationAuditKey = "octoteacher.screentime.operationAudit.v1"
    static let legacyMigrationCompletedKey = "octoteacher.screentime.legacyMigration.v3.completed"
    static let staleEnforcementResetCompletedKey = "octoteacher.screentime.staleEnforcementReset.v8.completed"

    private struct ChildInterfaceLanguageSnapshot: Codable {
        var languageRawValue: String
        var updatedAt: Date
        var schemaVersion: Int
    }

    static func publishChildInterfaceLanguage(
        _ rawValue: String,
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupIdentifier),
        now: Date = Date()
    ) {
        guard rawValue == "english" || rawValue == "chinese" else { return }
        defaults?.set(rawValue, forKey: childInterfaceLanguageKey)
        let snapshot = ChildInterfaceLanguageSnapshot(
            languageRawValue: rawValue,
            updatedAt: now,
            schemaVersion: 1
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults?.set(data, forKey: childInterfaceLanguageSnapshotKey)
        }
    }

    static func resolvedChildInterfaceLanguageRawValue(
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupIdentifier),
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        if let data = defaults?.data(forKey: childInterfaceLanguageSnapshotKey),
           let snapshot = try? JSONDecoder().decode(ChildInterfaceLanguageSnapshot.self, from: data),
           snapshot.languageRawValue == "english" || snapshot.languageRawValue == "chinese" {
            return snapshot.languageRawValue
        }
        if let legacy = defaults?.string(forKey: childInterfaceLanguageKey),
           legacy == "english" || legacy == "chinese" {
            return legacy
        }
        return preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? "chinese" : "english"
    }

    static func shieldInterfaceLanguageRawValue(
        request: PersistedShieldActionRequest?,
        fallback: String
    ) -> String {
        request?.validatedInterfaceLanguageRawValue ?? fallback
    }

    /// The host app has the latest synced child profile, so it owns the language once it opens.
    /// The shield request is only a fallback for legacy or incomplete local profiles; otherwise a
    /// stale request can reopen an English child's redemption UI in Chinese.
    static func hostInterfaceLanguageRawValue(
        currentChildLanguage: String?,
        request: PersistedShieldActionRequest?,
        fallback: String
    ) -> String {
        if currentChildLanguage == "english" || currentChildLanguage == "chinese" {
            return currentChildLanguage ?? fallback
        }
        if let requestLanguage = request?.validatedInterfaceLanguageRawValue {
            return requestLanguage
        }
        return fallback
    }

    static func currentSelectionGeneration(
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupIdentifier)
    ) -> Int {
        max(0, defaults?.integer(forKey: selectionGenerationKey) ?? 0)
    }

    @discardableResult
    static func advanceSelectionGeneration(
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupIdentifier)
    ) -> Int {
        let current = currentSelectionGeneration(defaults: defaults)
        let next = current == Int.max ? 1 : current + 1
        defaults?.set(next, forKey: selectionGenerationKey)
        return next
    }

    /// Every named store used before the v2 reward ledger shipped. Keep this registry
    /// explicit: store discovery is unavailable on older iOS releases and is not a migration.
    static let legacyManagedSettingsStoreNames = [
        rewardStoreName,
        webSafetyStoreName,
        schoolStoreName,
    ]

    static func applicationShieldStoreName(at index: Int) -> String {
        index == 0 ? rewardStoreName : "\(rewardStoreName).\(index)"
    }

    static func rewardActivityName(for id: UUID) -> String {
        "\(rewardActivityPrefix)\(id.uuidString.lowercased())"
    }

    static func rewardWindowID(forActivityName activityName: String) -> UUID? {
        guard activityName.hasPrefix(rewardActivityPrefix) else { return nil }
        return UUID(uuidString: String(activityName.dropFirst(rewardActivityPrefix.count)))
    }

    static func schoolPINSessionRef(id: UUID = UUID()) -> String {
        "school-pin:\(id.uuidString.lowercased())"
    }

    static func schoolModeBlocksRewardUnlock(inMemoryIsActive: Bool, persistedIsActive: Bool) -> Bool {
        inMemoryIsActive || persistedIsActive
    }

    static func emergencyDefersShieldRestoration(
        _ emergencyWindow: PersistedScreenTimeEmergencyWindow?,
        at date: Date
    ) -> Bool {
        (emergencyWindow?.endsAt ?? .distantPast) > date
    }

    static func paidUnlockCanCommit(
        schoolModeIsActive: Bool,
        schoolStoreIsClear: Bool?
    ) -> Bool {
        !schoolModeIsActive && schoolStoreIsClear == true
    }

    static func managedSettingsCleanupWasVerified(
        namedStoresAreClear: Bool,
        defaultStoreIsClear: Bool?
    ) -> Bool {
        namedStoresAreClear && defaultStoreIsClear == true
    }

    /// The reset marker lives in the App Group so reinstalling the host app cannot replay a
    /// destructive migration against a child-device selection that intentionally survives there.
    static func staleEnforcementResetAction(
        sharedMarkerIsSet: Bool,
        standardMarkerIsSet: Bool
    ) -> StaleEnforcementResetAction {
        if sharedMarkerIsSet {
            return .skip
        }
        if standardMarkerIsSet {
            return .adoptStandardMarker
        }
        return .clearExecutionStatePreservingSelection
    }

    static func expectedShieldApplications<Token: Hashable>(
        guardianApplications: Set<Token>,
        activeRewardApplications: Set<Token>
    ) -> Set<Token> {
        guardianApplications.subtracting(activeRewardApplications)
    }

    static func expectedShieldCategories<Token: Hashable>(
        guardianCategories: Set<Token>,
        activeRewardCategories: Set<Token>
    ) -> Set<Token> {
        guardianCategories.subtracting(activeRewardCategories)
    }

    /// Explicit apps must be shielded only by their application rules. Excluding them from an
    /// overlapping category rule makes Apple's ShieldAction callback identify the exact app.
    static func categoryShieldExceptions<Token: Hashable>(
        guardianApplications: Set<Token>,
        activeRewardApplications: Set<Token>
    ) -> Set<Token> {
        guardianApplications.union(activeRewardApplications)
    }

    static func rewardShieldApplicationsMatch<Token: Hashable>(
        guardianApplications: Set<Token>,
        activeRewardApplications: Set<Token>,
        appliedApplications: Set<Token>
    ) -> Bool {
        activeRewardApplications.isSubset(of: guardianApplications) &&
            appliedApplications == expectedShieldApplications(
                guardianApplications: guardianApplications,
                activeRewardApplications: activeRewardApplications
            )
    }

    /// Direct-only policies may open only an app selected by the guardian. A category policy can
    /// exempt an exact app token only when that token came from an explicit child-device app
    /// selection or an application Shield Action callback. A category callback never identifies
    /// the individual app that the child tapped.
    static func activeRewardApplicationsAreValid<Token: Hashable>(
        _ activeRewardApplications: Set<Token>,
        guardianApplications: Set<Token>,
        hasGuardianCategories: Bool
    ) -> Bool {
        activeRewardApplications.count <= maximumApplicationTokenCapacity &&
            (hasGuardianCategories || activeRewardApplications.isSubset(of: guardianApplications))
    }

    /// Categories and explicitly selected apps are independent parts of one policy. Keeping
    /// both is what makes "Games + TikTok + ChatGPT" enforceable without expanding a category
    /// into an unstable list of app tokens. Direct apps are split across named stores because
    /// ManagedSettings accepts at most 50 application tokens in each store.
    static func applicationShieldStrategy(
        applicationCount: Int,
        categoryCount: Int
    ) -> ApplicationShieldStrategy {
        guard applicationCount <= maximumApplicationTokenCapacity else {
            return .unsupportedTooManyApplications
        }
        if applicationCount > 0, categoryCount > 0 { return .applicationsAndCategories }
        if applicationCount > 0 { return .preciseApplications }
        return categoryCount > 0 ? .categories : .none
    }

    static func singleApplicationUnlockSelectionIsReady(applicationCount: Int) -> Bool {
        applicationCount > 0 && applicationCount <= maximumApplicationTokenCapacity
    }

    static func applicationShieldShardCount(applicationCount: Int) -> Int? {
        guard applicationCount >= 0,
              applicationCount <= maximumApplicationTokenCapacity else {
            return nil
        }
        guard applicationCount > 0 else { return 0 }
        return (applicationCount + maximumApplicationTokensPerShieldStore - 1) /
            maximumApplicationTokensPerShieldStore
    }

    static func applicationShieldShards<Token: Hashable>(
        _ applicationTokens: Set<Token>
    ) -> [Set<Token>]? {
        guard applicationTokens.count <= maximumApplicationTokenCapacity else {
            return nil
        }

        var iterator = applicationTokens.makeIterator()
        var shards: [Set<Token>] = []
        while true {
            var shard = Set<Token>()
            while shard.count < maximumApplicationTokensPerShieldStore,
                  let token = iterator.next() {
                shard.insert(token)
            }
            guard !shard.isEmpty else { break }
            shards.append(shard)
        }
        return shards
    }

    /// Legacy callers without a tapped-app token may proceed only when the selection has one app.
    /// Otherwise choosing `first` would make the unlocked app depend on opaque Set iteration order.
    static func implicitSingleApplicationUnlockSelectionIsUnambiguous(
        applicationCount: Int
    ) -> Bool {
        applicationCount == 1
    }

    /// ManagedSettings only affects the phone running this process. Guardian previews may
    /// inspect a child's rewards, but must never execute a lock or unlock on the guardian phone.
    static func mayExecuteDeviceControl(isChildDevice: Bool, isUITestMode: Bool = false) -> Bool {
        isChildDevice || isUITestMode
    }
}

enum ScreenTimeUsageWindowSchedule {
    static let minimumDeviceActivityDuration: TimeInterval = 15 * 60
    static let minimumMinutes = Int(minimumDeviceActivityDuration / 60)

    enum Error: Swift.Error, Equatable {
        case intervalTooShort
    }

    static func validatedInterval(startedAt: Date, endsAt: Date) throws -> DateInterval {
        guard endsAt.timeIntervalSince(startedAt) >= minimumDeviceActivityDuration else {
            throw Error.intervalTooShort
        }
        return DateInterval(start: startedAt, end: endsAt)
    }

    static func supports(minutes: Int) -> Bool {
        minutes >= minimumMinutes
    }
}

struct PersistedScreenTimeShieldDiagnostic: Codable, Equatable {
    var operation: String
    var selectedApplicationCount: Int
    var selectedCategoryCount: Int
    var selectedWebDomainCount: Int
    var appliedApplicationCount: Int
    var appliedCategoryPolicy: Bool
    var appliedWebDomainCount: Int
    var matchesGuardianSelection: Bool
    var updatedAt: Date
}

enum ScreenTimeRewardActivityCallbackPhase: String, Codable, Equatable {
    case intervalStarted
    case intervalEnded
}

enum PersistedScreenTimeRewardRelockOutcome: String, Codable, Equatable {
    case reconciled
    case ignoredStaleCallback
    case deferredByEmergencyAccess
    case lockUnavailable
    case persistenceFailed
    case shieldVerificationFailed
}

struct PersistedScreenTimeRewardRelockDiagnostic: Codable, Equatable {
    var activityName: String
    var phase: ScreenTimeRewardActivityCallbackPhase
    var outcome: PersistedScreenTimeRewardRelockOutcome
    var targetWindowID: UUID?
    var storedWindowCount: Int
    var activeWindowCount: Int
    var updatedAt: Date
}

enum PersistedShieldActionIntent: String, Codable, Equatable {
    case redeemGrowthPoints
    case parentPIN
    case requestSchoolEmergency
}

enum PersistedShieldTargetKind: String, Codable, Equatable {
    case application
    case category
    case webDomain
}

struct PersistedShieldActionRequest: Codable, Equatable, Identifiable {
    static let lifetime: TimeInterval = 5 * 60

    var id: UUID
    var intent: PersistedShieldActionIntent
    var targetKind: PersistedShieldTargetKind
    var tokenData: Data
    var createdAt: Date
    var interfaceLanguageRawValue: String?
    var selectionGeneration: Int?

    init(
        id: UUID,
        intent: PersistedShieldActionIntent,
        targetKind: PersistedShieldTargetKind,
        tokenData: Data,
        createdAt: Date,
        interfaceLanguageRawValue: String? = nil,
        selectionGeneration: Int? = nil
    ) {
        self.id = id
        self.intent = intent
        self.targetKind = targetKind
        self.tokenData = tokenData
        self.createdAt = createdAt
        self.interfaceLanguageRawValue = interfaceLanguageRawValue
        self.selectionGeneration = selectionGeneration
    }

    var expiresAt: Date { createdAt.addingTimeInterval(Self.lifetime) }

    var validatedInterfaceLanguageRawValue: String? {
        guard interfaceLanguageRawValue == "english" || interfaceLanguageRawValue == "chinese" else {
            return nil
        }
        return interfaceLanguageRawValue
    }

    func isValid(at date: Date = Date()) -> Bool {
        date < expiresAt && !tokenData.isEmpty
    }

    func belongsToSelectionGeneration(_ expected: Int?) -> Bool {
        guard let expected else { return true }
        return expected > 0 && selectionGeneration == expected
    }

    func identifiesExactApplication(
        at date: Date = Date(),
        selectionGeneration expected: Int? = nil
    ) -> Bool {
        targetKind == .application &&
            isValid(at: date) &&
            belongsToSelectionGeneration(expected)
    }

    func authorizesApplication(
        requestID: UUID,
        tokenData candidateTokenData: Data,
        at date: Date = Date(),
        selectionGeneration expected: Int? = nil
    ) -> Bool {
        id == requestID &&
            targetKind == .application &&
            tokenData == candidateTokenData &&
            isValid(at: date) &&
            belongsToSelectionGeneration(expected)
    }

    func authorizesCategory(
        requestID: UUID,
        tokenData candidateTokenData: Data,
        at date: Date = Date(),
        selectionGeneration expected: Int? = nil
    ) -> Bool {
        id == requestID &&
            targetKind == .category &&
            tokenData == candidateTokenData &&
            isValid(at: date) &&
            belongsToSelectionGeneration(expected)
    }
}

enum PersistedScreenTimeOperationOutcome: String, Codable, Equatable {
    case started
    case rejected
    case rolledBack
}

/// Privacy-safe breadcrumbs for diagnosing a failed Screen Time transaction. App names,
/// bundle identifiers and FamilyControls tokens must never be written to this ledger.
struct PersistedScreenTimeOperationAuditEntry: Codable, Equatable, Identifiable {
    var id: UUID
    var requestID: UUID?
    var stage: String
    var outcome: PersistedScreenTimeOperationOutcome
    var authorityRawValue: String?
    var targetKind: PersistedShieldTargetKind?
    var interfaceLanguageRawValue: String?
    var durationMinutes: Int?
    var errorCode: String?
    var timestamp: Date
}

enum ScreenTimeOperationAuditLedger {
    static let maximumEntryCount = 32

    static func load(
        defaults: UserDefaults? = UserDefaults(suiteName: ScreenTimeSharedContract.appGroupIdentifier)
    ) -> [PersistedScreenTimeOperationAuditEntry] {
        guard let data = defaults?.data(forKey: ScreenTimeSharedContract.operationAuditKey),
              let entries = try? JSONDecoder().decode([PersistedScreenTimeOperationAuditEntry].self, from: data)
        else { return [] }
        return entries
    }

    static func append(
        _ entry: PersistedScreenTimeOperationAuditEntry,
        defaults: UserDefaults? = UserDefaults(suiteName: ScreenTimeSharedContract.appGroupIdentifier)
    ) {
        guard let defaults else { return }
        let entries = Array((load(defaults: defaults) + [entry]).suffix(maximumEntryCount))
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: ScreenTimeSharedContract.operationAuditKey)
    }

    static func latest(
        requestID: UUID?,
        defaults: UserDefaults? = UserDefaults(suiteName: ScreenTimeSharedContract.appGroupIdentifier)
    ) -> PersistedScreenTimeOperationAuditEntry? {
        let entries = load(defaults: defaults)
        guard let requestID else { return entries.last }
        return entries.last(where: { $0.requestID == requestID })
    }

    static func clear(
        defaults: UserDefaults? = UserDefaults(suiteName: ScreenTimeSharedContract.appGroupIdentifier)
    ) {
        defaults?.removeObject(forKey: ScreenTimeSharedContract.operationAuditKey)
    }
}

struct PersistedScreenTimeEmergencyWindow: Codable, Equatable {
    var startedAt: Date
    var endsAt: Date
    var sourceLabel: String
}

struct PersistedScreenTimeRewardWindow: Codable, Equatable {
    var id: UUID?
    var applicationTokenData: Data
    var targetKind: PersistedShieldTargetKind?
    var startedAt: Date
    var endsAt: Date
    var sourceLabel: String
    var selectionGeneration: Int?
    /// Uptime is immune to wall-clock edits. A value lower than this after decoding means
    /// the device rebooted, so temporary access must fail closed until the host reconciles.
    var startedAtSystemUptime: TimeInterval?

    init(
        id: UUID = UUID(),
        applicationTokenData: Data,
        targetKind: PersistedShieldTargetKind = .application,
        startedAt: Date,
        endsAt: Date,
        sourceLabel: String,
        selectionGeneration: Int? = nil,
        startedAtSystemUptime: TimeInterval? = nil
    ) {
        self.id = id
        self.applicationTokenData = applicationTokenData
        self.targetKind = targetKind
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.sourceLabel = sourceLabel
        self.selectionGeneration = selectionGeneration
        self.startedAtSystemUptime = startedAtSystemUptime
    }

    var resolvedID: UUID { id ?? Self.legacyID(for: self) }
    var resolvedTargetKind: PersistedShieldTargetKind { targetKind ?? .application }

    func normalized() -> PersistedScreenTimeRewardWindow {
        guard id == nil else { return self }
        return PersistedScreenTimeRewardWindow(
            id: resolvedID,
            applicationTokenData: applicationTokenData,
            targetKind: resolvedTargetKind,
            startedAt: startedAt,
            endsAt: endsAt,
            sourceLabel: sourceLabel,
            selectionGeneration: selectionGeneration,
            startedAtSystemUptime: startedAtSystemUptime
        )
    }

    func belongsToSelectionGeneration(_ generation: Int) -> Bool {
        generation > 0 && selectionGeneration == generation
    }

    func isActive(at date: Date, systemUptime: TimeInterval?) -> Bool {
        guard !applicationTokenData.isEmpty, endsAt > date else { return false }
        guard let startedAtSystemUptime, let systemUptime else { return true }
        let duration = endsAt.timeIntervalSince(startedAt)
        guard duration > 0, systemUptime >= startedAtSystemUptime else { return false }
        return systemUptime < startedAtSystemUptime + duration
    }

    private static func legacyID(for window: PersistedScreenTimeRewardWindow) -> UUID {
        var payload = window.applicationTokenData
        payload.append(contentsOf: withUnsafeBytes(of: window.startedAt.timeIntervalSince1970.bitPattern.bigEndian, Array.init))
        payload.append(contentsOf: withUnsafeBytes(of: window.endsAt.timeIntervalSince1970.bitPattern.bigEndian, Array.init))
        payload.append(contentsOf: window.sourceLabel.utf8)

        let first = fnv1a64(payload, seed: 0xcbf29ce484222325)
        let second = fnv1a64(payload, seed: 0x84222325cbf29ce4)
        var bytes = withUnsafeBytes(of: first.bigEndian, Array.init)
        bytes.append(contentsOf: withUnsafeBytes(of: second.bigEndian, Array.init))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func fnv1a64(_ data: Data, seed: UInt64) -> UInt64 {
        data.reduce(seed) { hash, byte in
            (hash ^ UInt64(byte)) &* 0x00000100000001b3
        }
    }
}

enum ScreenTimeOpaqueTokenRefreshMigration {
    enum Error: Swift.Error, Equatable {
        case mismatchedTokenCount
        case duplicateSourceToken
        case duplicateRefreshedToken
        case missingTokenMapping
    }

    struct Result: Equatable {
        var rewardWindows: [PersistedScreenTimeRewardWindow]
        var shieldActionRequest: PersistedShieldActionRequest?
    }

    static func makeTokenMap(
        oldTokenData: [Data],
        refreshedTokenData: [Data]
    ) throws -> [Data: Data] {
        guard oldTokenData.count == refreshedTokenData.count else {
            throw Error.mismatchedTokenCount
        }
        guard Set(oldTokenData).count == oldTokenData.count else {
            throw Error.duplicateSourceToken
        }
        guard Set(refreshedTokenData).count == refreshedTokenData.count else {
            throw Error.duplicateRefreshedToken
        }
        return Dictionary(uniqueKeysWithValues: zip(oldTokenData, refreshedTokenData))
    }

    static func migrate(
        tokenMap: [Data: Data],
        rewardWindows: [PersistedScreenTimeRewardWindow],
        shieldActionRequest: PersistedShieldActionRequest?
    ) throws -> Result {
        let migratedWindows = try rewardWindows.map { window in
            guard window.resolvedTargetKind == .application else { return window }
            guard let refreshedTokenData = tokenMap[window.applicationTokenData] else {
                throw Error.missingTokenMapping
            }
            var migrated = window
            migrated.applicationTokenData = refreshedTokenData
            return migrated
        }

        let migratedRequest: PersistedShieldActionRequest?
        if var request = shieldActionRequest, request.targetKind == .application {
            guard let refreshedTokenData = tokenMap[request.tokenData] else {
                throw Error.missingTokenMapping
            }
            request.tokenData = refreshedTokenData
            migratedRequest = request
        } else {
            migratedRequest = shieldActionRequest
        }

        return Result(
            rewardWindows: migratedWindows,
            shieldActionRequest: migratedRequest
        )
    }
}

struct PersistedScreenTimeRewardCompensation: Codable, Equatable, Identifiable {
    var id: UUID
    var requestedAt: Date
}

enum ScreenTimeRewardCompensationLedger {
    static func adding(
        id: UUID,
        at date: Date,
        to compensations: [PersistedScreenTimeRewardCompensation]
    ) -> [PersistedScreenTimeRewardCompensation] {
        guard !compensations.contains(where: { $0.id == id }) else { return compensations }
        return compensations + [.init(id: id, requestedAt: date)]
    }

    static func removing(
        ids: Set<UUID>,
        from compensations: [PersistedScreenTimeRewardCompensation]
    ) -> [PersistedScreenTimeRewardCompensation] {
        compensations.filter { !ids.contains($0.id) }
    }

    static func applying(
        _ compensations: [PersistedScreenTimeRewardCompensation],
        to windows: [PersistedScreenTimeRewardWindow]
    ) -> (remaining: [PersistedScreenTimeRewardWindow], removed: [PersistedScreenTimeRewardWindow]) {
        let ids = Set(compensations.map(\.id))
        return (
            windows.filter { !ids.contains($0.resolvedID) },
            windows.filter { ids.contains($0.resolvedID) }
        )
    }
}

enum ScreenTimeRewardWindowLedger {
    enum Error: Swift.Error, Equatable {
        case alreadyActive
    }

    static func active(
        _ windows: [PersistedScreenTimeRewardWindow],
        at date: Date,
        systemUptime: TimeInterval? = nil
    ) -> [PersistedScreenTimeRewardWindow] {
        windows
            .filter { $0.isActive(at: date, systemUptime: systemUptime) }
            .map { $0.normalized() }
            .sorted { $0.endsAt < $1.endsAt }
    }

    static func adding(
        _ window: PersistedScreenTimeRewardWindow,
        to windows: [PersistedScreenTimeRewardWindow],
        at date: Date,
        systemUptime: TimeInterval? = nil
    ) throws -> [PersistedScreenTimeRewardWindow] {
        var current = active(windows, at: date, systemUptime: systemUptime)
        guard !current.contains(where: {
            $0.resolvedTargetKind == window.resolvedTargetKind &&
                $0.applicationTokenData == window.applicationTokenData
        }) else {
            throw Error.alreadyActive
        }
        current.append(window.normalized())
        return current.sorted { $0.endsAt < $1.endsAt }
    }

    static func removing(
        applicationTokenData: Data,
        from windows: [PersistedScreenTimeRewardWindow],
        at date: Date,
        systemUptime: TimeInterval? = nil
    ) -> (remaining: [PersistedScreenTimeRewardWindow], removed: PersistedScreenTimeRewardWindow?) {
        let current = active(windows, at: date, systemUptime: systemUptime)
        let removed = current.first {
            $0.resolvedTargetKind == .application &&
                $0.applicationTokenData == applicationTokenData
        }
        return (
            current.filter {
                $0.resolvedTargetKind != .application ||
                    $0.applicationTokenData != applicationTokenData
            },
            removed
        )
    }

    /// A DeviceActivity callback is authoritative only while its exact window remains
    /// in the ledger. Delayed callbacks from cancelled or migrated schedules are ignored.
    static func activeWindowsForCallback(
        activityName: String,
        phase: ScreenTimeRewardActivityCallbackPhase = .intervalEnded,
        storedWindows: [PersistedScreenTimeRewardWindow],
        at date: Date,
        acceptsLegacyActivity: Bool = false,
        systemUptime: TimeInterval? = nil
    ) -> [PersistedScreenTimeRewardWindow]? {
        let candidateWindows: [PersistedScreenTimeRewardWindow]
        if activityName == ScreenTimeSharedContract.rewardActivityName {
            guard acceptsLegacyActivity else { return nil }
            candidateWindows = storedWindows
        } else {
            guard let callbackID = ScreenTimeSharedContract.rewardWindowID(forActivityName: activityName),
                  storedWindows.contains(where: { $0.resolvedID == callbackID }) else { return nil }
            candidateWindows = phase == .intervalEnded
                ? storedWindows.filter { $0.resolvedID != callbackID }
                : storedWindows
        }
        return active(candidateWindows, at: date, systemUptime: systemUptime)
    }
}

enum ScreenTimeRewardWindowTransaction {
    static func commitStart(
        schedule: () throws -> Void,
        persist: () throws -> Void,
        rollbackPersistence: () -> Void = {},
        rollbackSchedule: () -> Void
    ) throws {
        do {
            try schedule()
        } catch {
            rollbackSchedule()
            throw error
        }
        do {
            try persist()
        } catch {
            rollbackPersistence()
            rollbackSchedule()
            throw error
        }
    }

    static func commitMutation(
        persist: () throws -> Void,
        apply: () throws -> Void,
        cancelObsoleteSchedules: () -> Void
    ) throws {
        try persist()
        try apply()
        cancelObsoleteSchedules()
    }

    static func commitCompensatedMutation(
        persistCompensation: () throws -> Void,
        persistAndApply: () throws -> Void,
        cancelObsoleteSchedules: () -> Void,
        clearCompensation: () throws -> Void
    ) throws {
        try persistCompensation()
        try persistAndApply()
        cancelObsoleteSchedules()
        try clearCompensation()
    }

    static func commitLegacyMigration(
        activityNames: [String],
        register: (String) throws -> Void,
        persistV2: () throws -> Void,
        cancelRegistered: ([String]) -> Void,
        cancelLegacy: () -> Void
    ) throws {
        var registered: [String] = []
        do {
            for activityName in activityNames {
                try register(activityName)
                registered.append(activityName)
            }
            try persistV2()
        } catch {
            cancelRegistered(registered)
            throw error
        }
        cancelLegacy()
    }
}

enum ScreenTimeApplicationUsageAliasStore {
    static let mappingKey = "octoteacher.screentime.appUsageAliases.v1"

    static func appUsageRef(
        for tokenData: Data,
        defaults: UserDefaults? = UserDefaults(
            suiteName: ScreenTimeSharedContract.appGroupIdentifier
        )
    ) -> String? {
        guard let defaults else { return nil }
        let fingerprint = SHA256.hash(data: tokenData)
            .map { String(format: "%02x", $0) }
            .joined()
        var mapping = defaults.dictionary(forKey: mappingKey) as? [String: String] ?? [:]
        if let existing = mapping[fingerprint], isValidAlias(existing) {
            return "app:\(existing)"
        }
        let alias = UUID().uuidString
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
        mapping[fingerprint] = alias
        defaults.set(mapping, forKey: mappingKey)
        return "app:\(alias)"
    }

    private static func isValidAlias(_ value: String) -> Bool {
        value.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil
    }
}

enum ScreenTimeRewardWindowLock {
    static func retryInterruptedSystemCall(
        _ operation: () -> Int32,
        errorCode: () -> Int32 = { errno }
    ) -> Int32 {
        while true {
            let result = operation()
            guard result == -1, errorCode() == EINTR else {
                return result
            }
        }
    }

    /// Returns nil instead of executing without the cross-process lock. Reward and school
    /// mutations must fail closed when the App Group container or lock file is unavailable.
    static func withLock<Result>(_ operation: () throws -> Result) rethrows -> Result? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ScreenTimeSharedContract.appGroupIdentifier
        ) else {
            return nil
        }
        let path = container.appendingPathComponent("octoteacher-reward-windows.lock").path
        let descriptor = retryInterruptedSystemCall {
            open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else { return nil }
        guard retryInterruptedSystemCall({
            flock(descriptor, LOCK_EX)
        }) == 0 else {
            close(descriptor)
            return nil
        }
        defer {
            _ = retryInterruptedSystemCall {
                flock(descriptor, LOCK_UN)
            }
            close(descriptor)
        }
        return try operation()
    }
}

struct PersistedSchoolModeRule: Codable, Equatable {
    var weekday: Int
    var startMinutes: Int
    var endMinutes: Int
}

struct PersistedSchoolModeException: Codable, Equatable {
    var dateKey: String
    var isHoliday: Bool
    var startMinutes: Int?
    var endMinutes: Int?
}

struct PersistedSchoolModeRuntime: Codable, Equatable {
    var childID: UUID
    var isEnabled: Bool
    var defaultStartMinutes: Int
    var defaultEndMinutes: Int
    var rules: [PersistedSchoolModeRule]
    var exceptions: [PersistedSchoolModeException]
    var activityNames: [String]

    func shouldApplyShield(at date: Date, activityName: String, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard isEnabled else { return false }
        let key = Self.dateKey(for: date, calendar: calendar)
        if let exception = exceptions.first(where: { $0.dateKey == key }) {
            guard !exception.isHoliday else { return false }
            return activityName.contains(".override.")
        }
        return !activityName.contains(".override.")
    }

    func shouldClearShield(at date: Date, activityName: String, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        let key = Self.dateKey(for: date, calendar: calendar)
        if exceptions.contains(where: { $0.dateKey == key }) {
            return activityName.contains(".override.")
        }
        return !activityName.contains(".override.")
    }

    static func dateKey(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let values = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", values.year ?? 0, values.month ?? 0, values.day ?? 0)
    }
}
