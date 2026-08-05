import Foundation
import Observation

protocol ScreenTimeControlling {
    var shieldState: ShieldState { get }
    var unlockEndsAt: Date? { get }

    func requestAuthorization() async throws
    func selectAppsToShield() async throws
    func shieldSelectedApps()
    func unshield(for minutes: Int)
    func reshieldNow()
}

/// 解锁会话相关错误，用于让上层用例感知失败并回滚成长积分。
enum UnlockError: Error, Equatable {
    /// 已有进行中会话，拒绝重复解锁（重复解锁不得叠加时间）。
    case alreadyActive
    /// 请求分钟数为非正数。
    case nonPositiveMinutes
    /// 模拟设备命令下发失败（仅本壳注入，用于验证失败回滚）。
    case deviceCommandFailed
}

/// One independently timed app exception created by the real Screen Time layer.
struct ScreenTimeExternalSession: Equatable {
    var id: UUID
    var endsAt: Date
}

enum ScreenTimeGrantAuthority: String, Codable, Equatable {
    case growthPoints = "growth_points"
    case parentPIN = "parent_pin"
    case guardianRemote = "guardian_remote"
    case schoolEmergency = "school_emergency"

    var countsTowardGrowthPointDailyLimit: Bool { self == .growthPoints }
}

/// Local accounting for one active app exception. The opaque UUID is shared with the
/// persisted Screen Time reward window, so ending one app never ends another app.
struct ScreenTimeActiveGrantSnapshot: Identifiable, Codable, Equatable {
    var id: UUID
    var startedAt: Date
    var endsAt: Date
    var minutes: Int
    /// Privacy-safe app alias used only for family activity reporting.
    var appUsageRef: String? = nil
    /// Optional so snapshots written before authority tracking remain decodable.
    var authority: ScreenTimeGrantAuthority? = nil

    var resolvedAuthority: ScreenTimeGrantAuthority { authority ?? .growthPoints }
}

/// 屏幕时间会话的可持久化快照，随家庭数据一起只存本机。
struct ScreenTimeSessionSnapshot: Codable, Equatable {
    var sessionStatus: RewardSessionStatus
    var unlockStartedAt: Date?
    var unlockEndsAt: Date?
    var activeMinutes: Int
    var receipts: [RewardSessionReceipt]
    var deviceCommandReceipts: [ScreenTimeDeviceCommandReceipt]?
    /// Optional for backward-compatible decoding of the former single-session snapshot.
    var activeGrants: [ScreenTimeActiveGrantSnapshot]? = nil
    /// Optional so snapshots written before completion-based activity reporting remain decodable.
    var activityReportedReceiptIDs: [UUID]? = nil
    /// Last cloud control command reconciled into the local authorization ledger.
    var appliedGuardianControlCommandID: String? = nil
}

enum ScreenTimeDeviceCommandKind: String, Codable, Equatable {
    case startUnlock
    case automaticRelock
    case parentRelock
}

enum ScreenTimeDeviceCommandStatus: String, Codable, Equatable {
    case succeeded
    case failed
}

enum ScreenTimeDeviceCommandFailureReason: String, Codable, Equatable {
    case alreadyActive
    case nonPositiveMinutes
    case deviceCommandFailed
}

/// 设备命令回执：记录一次「打开/重锁」命令是否落地。
/// 仅含本地分钟数与时间戳，不保存真实 bundle id、设备标识或孩子隐私。
struct ScreenTimeDeviceCommandReceipt: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: ScreenTimeDeviceCommandKind
    var status: ScreenTimeDeviceCommandStatus
    var requestedMinutes: Int?
    var createdAt: Date
    var plannedEndsAt: Date?
    var failureReason: ScreenTimeDeviceCommandFailureReason?

    var didUnlockDevice: Bool {
        kind == .startUnlock && status == .succeeded
    }
}

/// 本壳唯一的屏幕时间执行面，全部为 mock：不接 FamilyControls / ManagedSettings / DeviceActivity。
/// 会话生命周期在此确定性地推进，时间通过 `now` 注入，便于单元测试。
/// 真实接入边界见同目录 `README.md`。
@Observable
final class MockScreenTimeController: ScreenTimeControlling {
    private(set) var sessionStatus: RewardSessionStatus = .locked
    private(set) var unlockEndsAt: Date?
    private(set) var unlockStartedAt: Date?
    /// 当前进行中会话的发放分钟；非 active 时为 0。
    private(set) var activeMinutes: Int = 0
    /// Multiple apps may be open at once; each grant keeps its own expiry and receipt.
    private(set) var activeGrants: [ScreenTimeActiveGrantSnapshot] = []
    /// 历史会话收据，最新在前。
    private(set) var receipts: [RewardSessionReceipt] = []
    /// 设备命令回执，最新在前；成功开启会话时立即生成，结束回执稍后由 tick/家长结束生成。
    private(set) var deviceCommandReceipts: [ScreenTimeDeviceCommandReceipt] = []
    /// Completion receipts already accepted into the durable family-cloud outbox.
    private(set) var activityReportedReceiptIDs: Set<UUID> = []
    private(set) var appliedGuardianControlCommandID: String?

    /// 会话持久化的 UserDefaults key；nil 时纯内存运行（单元测试与 UI 测试模式）。
    @ObservationIgnored
    private let persistenceKey: String?
    @ObservationIgnored
    private let defaults: UserDefaults

    /// - Parameter persistenceKey: 传入后，进行中的解锁会话与历史收据跨 App 重启保留；
    ///   恢复后由下一次 `tick()` 判断是否已到期并重锁。
    init(persistenceKey: String? = nil, defaults: UserDefaults = .standard) {
        self.persistenceKey = persistenceKey
        self.defaults = defaults
        restoreSession()
    }

    // MARK: - 会话持久化

    private func restoreSession() {
        guard let persistenceKey,
              let data = defaults.data(forKey: persistenceKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(ScreenTimeSessionSnapshot.self, from: data) else { return }
        sessionStatus = snapshot.sessionStatus
        unlockStartedAt = snapshot.unlockStartedAt
        unlockEndsAt = snapshot.unlockEndsAt
        activeMinutes = snapshot.activeMinutes
        receipts = snapshot.receipts
        deviceCommandReceipts = snapshot.deviceCommandReceipts ?? []
        if let restoredIDs = snapshot.activityReportedReceiptIDs {
            activityReportedReceiptIDs = Set(restoredIDs)
        } else {
            // Legacy snapshots may contain years of receipts that were already reported at start.
            activityReportedReceiptIDs = Set(snapshot.receipts.map(\.id))
        }
        if let restoredGrants = snapshot.activeGrants {
            activeGrants = restoredGrants
        } else if snapshot.sessionStatus == .active,
                  let startedAt = snapshot.unlockStartedAt,
                  let endsAt = snapshot.unlockEndsAt,
                  snapshot.activeMinutes > 0 {
            activeGrants = [ScreenTimeActiveGrantSnapshot(
                id: UUID(),
                startedAt: startedAt,
                endsAt: endsAt,
                minutes: snapshot.activeMinutes
            )]
        }
        appliedGuardianControlCommandID = snapshot.appliedGuardianControlCommandID
        refreshAggregateActiveFields()
    }

    private func persistSession() {
        guard let persistenceKey else { return }
        let snapshot = ScreenTimeSessionSnapshot(
            sessionStatus: sessionStatus,
            unlockStartedAt: unlockStartedAt,
            unlockEndsAt: unlockEndsAt,
            activeMinutes: activeMinutes,
            receipts: receipts,
            deviceCommandReceipts: deviceCommandReceipts,
            activeGrants: activeGrants,
            activityReportedReceiptIDs: Array(activityReportedReceiptIDs),
            appliedGuardianControlCommandID: appliedGuardianControlCommandID
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: persistenceKey)
    }

    /// 仅供测试注入的设备故障开关：为 true 时下一次 `startSession` 抛出 `deviceCommandFailed`，
    /// 用来验证「失败会话必须回滚成长积分」。生产代码不应改写它。
    var simulateDeviceFailure = false

    /// 对外仍暴露二态 shield：只有 active 会话才解锁，locked/expired 一律遮挡。
    var shieldState: ShieldState { sessionStatus == .active ? .unlocked : .locked }

    /// 最近一条会话收据，供 UI 展示。
    var latestReceipt: RewardSessionReceipt? { receipts.first }

    /// 最近一条设备命令回执，供兑换 UI 展示「命令是否落地」。
    var latestDeviceCommandReceipt: ScreenTimeDeviceCommandReceipt? { deviceCommandReceipts.first }

    var pendingActivityReceipts: [RewardSessionReceipt] {
        receipts.filter { !activityReportedReceiptIDs.contains($0.id) }
    }

    func markActivityReceiptQueued(_ receiptID: UUID) {
        activityReportedReceiptIDs.insert(receiptID)
        persistSession()
    }

    /// 当天已经发放的屏幕时间。并行 App 窗口按时间轴并集计入上限，
    /// 避免同一分钟因同时开放多个 App 被重复计算；提前结束仍不返还额度。
    func grantedMinutes(on date: Date, calendar: Calendar = .current) -> Int {
        guard let day = calendar.dateInterval(of: .day, for: date) else { return 0 }
        return roundedMinutes(for: growthPointIntervals(overlapping: day))
    }

    /// 新开一个 App 窗口会给当天授权时间轴增加多少分钟。
    /// 完全重叠的并行窗口增加 0 分钟，但仍可独立扣积分并独立到期。
    func additionalGrantedMinutes(
        for minutes: Int,
        startingAt start: Date,
        calendar: Calendar = .current
    ) -> Int {
        guard minutes > 0,
              let day = calendar.dateInterval(of: .day, for: start) else { return 0 }
        let existing = growthPointIntervals(overlapping: day)
        let proposedEnd = start.addingTimeInterval(TimeInterval(minutes * 60))
        guard let proposed = clippedInterval(start: start, end: proposedEnd, to: day) else {
            return 0
        }
        return max(
            0,
            roundedMinutes(for: existing + [proposed]) - roundedMinutes(for: existing)
        )
    }

    private func growthPointIntervals(overlapping day: DateInterval) -> [DateInterval] {
        let completed = receipts.compactMap { receipt -> DateInterval? in
            guard receipt.resolvedAuthority.countsTowardGrowthPointDailyLimit else { return nil }
            return clippedInterval(start: receipt.startedAt, end: receipt.plannedEndsAt, to: day)
        }
        let active = activeGrants.compactMap { grant -> DateInterval? in
            guard grant.resolvedAuthority.countsTowardGrowthPointDailyLimit else { return nil }
            return clippedInterval(start: grant.startedAt, end: grant.endsAt, to: day)
        }
        return completed + active
    }

    private func clippedInterval(start: Date, end: Date, to bounds: DateInterval) -> DateInterval? {
        let clippedStart = start > bounds.start ? start : bounds.start
        let clippedEnd = end < bounds.end ? end : bounds.end
        guard clippedEnd > clippedStart else { return nil }
        return DateInterval(start: clippedStart, end: clippedEnd)
    }

    private func roundedMinutes(for intervals: [DateInterval]) -> Int {
        let sorted = intervals.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return 0 }
        var seconds: TimeInterval = 0

        for interval in sorted.dropFirst() {
            if interval.start <= current.end {
                if interval.end > current.end {
                    current = DateInterval(start: current.start, end: interval.end)
                }
            } else {
                seconds += current.duration
                current = interval
            }
        }
        seconds += current.duration
        return Int(ceil(seconds / 60))
    }

    // MARK: - 真实端口占位（mock 不执行任何系统调用）

    func requestAuthorization() async throws {}

    func selectAppsToShield() async throws {}

    /// 初始/硬重锁：直接遮挡，不生成会话收据。用于 App 启动或重置。
    func shieldSelectedApps() {
        hardLock()
    }

    // MARK: - 会话生命周期

    /// 开启一个解锁会话；失败时抛错，由上层决定回滚。
    /// - 重复解锁：已有 active 会话时抛 `alreadyActive`，绝不叠加时间。
    /// - 设备故障：`simulateDeviceFailure` 为 true 时抛 `deviceCommandFailed`。
    @discardableResult
    func startSession(
        sessionID: UUID = UUID(),
        minutes: Int,
        now: Date = Date(),
        authority: ScreenTimeGrantAuthority = .growthPoints,
        appUsageRef: String? = nil
    ) throws -> Date {
        guard minutes > 0 else {
            recordDeviceCommand(
                kind: .startUnlock,
                status: .failed,
                requestedMinutes: minutes,
                createdAt: now,
                failureReason: .nonPositiveMinutes
            )
            throw UnlockError.nonPositiveMinutes
        }
        guard sessionStatus != .active else {
            recordDeviceCommand(
                kind: .startUnlock,
                status: .failed,
                requestedMinutes: minutes,
                createdAt: now,
                failureReason: .alreadyActive
            )
            throw UnlockError.alreadyActive
        }
        if simulateDeviceFailure {
            recordDeviceCommand(
                kind: .startUnlock,
                status: .failed,
                requestedMinutes: minutes,
                createdAt: now,
                failureReason: .deviceCommandFailed
            )
            throw UnlockError.deviceCommandFailed
        }

        let endsAt = now.addingTimeInterval(TimeInterval(minutes * 60))
        activeGrants = [ScreenTimeActiveGrantSnapshot(
            id: sessionID,
            startedAt: now,
            endsAt: endsAt,
            minutes: minutes,
            appUsageRef: appUsageRef,
            authority: authority
        )]
        refreshAggregateActiveFields()
        recordDeviceCommand(
            kind: .startUnlock,
            status: .succeeded,
            requestedMinutes: minutes,
            createdAt: now,
            plannedEndsAt: endsAt
        )
        persistSession()
        return endsAt
    }

    /// 真实 Screen Time 执行面已成功打开窗口后，把本地会话账本推进到 active。
    /// 这让主奖励链路可以先调用 FamilyControls / ManagedSettings，再用同一套 UI 和收据展示状态。
    @discardableResult
    func adoptExternalUnlock(
        sessionID: UUID = UUID(),
        minutes: Int,
        now: Date = Date(),
        endsAt: Date,
        authority: ScreenTimeGrantAuthority = .growthPoints,
        appUsageRef: String? = nil
    ) throws -> Date {
        guard minutes > 0 else {
            recordDeviceCommandFailure(minutes: minutes, now: now, reason: .nonPositiveMinutes)
            throw UnlockError.nonPositiveMinutes
        }
        guard sessionStatus != .active else {
            recordDeviceCommandFailure(minutes: minutes, now: now, reason: .alreadyActive)
            throw UnlockError.alreadyActive
        }

        activeGrants = [ScreenTimeActiveGrantSnapshot(
            id: sessionID,
            startedAt: now,
            endsAt: endsAt,
            minutes: minutes,
            appUsageRef: appUsageRef,
            authority: authority
        )]
        refreshAggregateActiveFields()
        recordDeviceCommand(
            kind: .startUnlock,
            status: .succeeded,
            requestedMinutes: minutes,
            createdAt: now,
            plannedEndsAt: endsAt
        )
        persistSession()
        return endsAt
    }

    /// Adopts one real app exception without blocking other active app exceptions.
    /// A duplicate UUID is rejected so a retried callback cannot double-count minutes.
    @discardableResult
    func adoptConcurrentExternalUnlock(
        sessionID: UUID,
        minutes: Int,
        now: Date = Date(),
        endsAt: Date,
        authority: ScreenTimeGrantAuthority = .growthPoints,
        appUsageRef: String? = nil
    ) throws -> Date {
        guard minutes > 0 else {
            recordDeviceCommandFailure(minutes: minutes, now: now, reason: .nonPositiveMinutes)
            throw UnlockError.nonPositiveMinutes
        }
        guard !activeGrants.contains(where: { $0.id == sessionID }) else {
            recordDeviceCommandFailure(minutes: minutes, now: now, reason: .alreadyActive)
            throw UnlockError.alreadyActive
        }

        activeGrants.append(ScreenTimeActiveGrantSnapshot(
            id: sessionID,
            startedAt: now,
            endsAt: endsAt,
            minutes: minutes,
            appUsageRef: appUsageRef,
            authority: authority
        ))
        refreshAggregateActiveFields()
        recordDeviceCommand(
            kind: .startUnlock,
            status: .succeeded,
            requestedMinutes: minutes,
            createdAt: now,
            plannedEndsAt: endsAt
        )
        persistSession()
        return endsAt
    }

    /// 外部真实执行面失败时，记录一条可见设备命令失败回执，但不改变会话状态。
    func recordDeviceCommandFailure(
        minutes: Int,
        now: Date = Date(),
        reason: ScreenTimeDeviceCommandFailureReason = .deviceCommandFailed
    ) {
        recordDeviceCommand(
            kind: .startUnlock,
            status: .failed,
            requestedMinutes: minutes,
            createdAt: now,
            failureReason: reason
        )
    }

    /// 协议要求的简化解锁入口：忽略错误。仅用于旧调用点与亲友护栏（亲友永远到不了这里）。
    func unshield(for minutes: Int) {
        _ = try? startSession(minutes: minutes)
    }

    /// 协议要求的立即重锁入口：等价于家长提前结束当前会话。
    func reshieldNow() {
        _ = endSessionByParent()
    }

    /// Mirrors a successfully acknowledged cloud command into the local receipt ledger.
    /// The command ID makes lock commands edge-triggered: a later Growth Points window is not
    /// repeatedly cancelled by the same already-applied cloud command.
    @discardableResult
    func reconcileGuardianControl(
        _ control: FamilyScreenTimeControl,
        now: Date = Date()
    ) -> Bool {
        _ = tick(now: now)
        guard control.schemaVersion == 1,
              !control.commandId.isEmpty,
              appliedGuardianControlCommandID != control.commandId else {
            return false
        }

        let receipt = control.effectiveReceipt(referenceDate: now)
        if receipt.mode == .locked {
            _ = endSessionByParent(now: now)
            appliedGuardianControlCommandID = control.commandId
            persistSession()
            return true
        }

        guard let endsAt = control.unlockEndDate else { return false }
        _ = endSessionByParent(now: now)
        let minutes = max(1, Int(ceil(endsAt.timeIntervalSince(now) / 60)))
        do {
            _ = try adoptExternalUnlock(
                sessionID: control.accountingSessionID,
                minutes: minutes,
                now: now,
                endsAt: endsAt,
                authority: .guardianRemote
            )
            appliedGuardianControlCommandID = control.commandId
            persistSession()
            return true
        } catch {
            return false
        }
    }

    /// Clears an obsolete persisted countdown without issuing a new lock command or receipt.
    /// Used only by a versioned migration after the real ManagedSettings stores are cleared.
    func resetPersistedSessionWithoutRelock() {
        sessionStatus = .locked
        clearActiveSession()
        persistSession()
    }

    /// 时间推进：active 会话到期则生成「到期」收据并进入 expired 状态。
    /// 返回新生成的收据（若有），便于 UI 提示。
    @discardableResult
    func tick(now: Date = Date()) -> RewardSessionReceipt? {
        let expired = activeGrants.filter { now >= $0.endsAt }
        guard !expired.isEmpty else { return nil }

        var newestReceipt: RewardSessionReceipt?
        for grant in expired.sorted(by: { $0.endsAt < $1.endsAt }) {
            newestReceipt = finalizeReceipt(
                startedAt: grant.startedAt,
                plannedEndsAt: grant.endsAt,
                endedAt: grant.endsAt,
                grantedMinutes: grant.minutes,
                authority: grant.resolvedAuthority,
                sessionID: grant.id,
                appUsageRef: grant.appUsageRef,
                reason: .expired
            )
            recordDeviceCommand(kind: .automaticRelock, status: .succeeded, createdAt: grant.endsAt)
        }
        let expiredIDs = Set(expired.map(\.id))
        activeGrants.removeAll { expiredIDs.contains($0.id) }
        if activeGrants.isEmpty {
            sessionStatus = .expired
            clearActiveSession()
        } else {
            refreshAggregateActiveFields()
        }
        persistSession()
        return newestReceipt
    }

    /// 家长提前结束当前会话：生成「家长结束」收据并重锁。
    /// 没有进行中会话时仅确保处于锁定态，返回 nil。
    @discardableResult
    func endSessionByParent(now: Date = Date()) -> RewardSessionReceipt? {
        guard !activeGrants.isEmpty else {
            hardLock()
            return nil
        }
        let commandDate = activeGrants.map { min(now, $0.endsAt) }.max() ?? now
        var newestReceipt: RewardSessionReceipt?
        for grant in activeGrants {
            newestReceipt = finalizeReceipt(
                startedAt: grant.startedAt,
                plannedEndsAt: grant.endsAt,
                endedAt: min(now, grant.endsAt),
                grantedMinutes: grant.minutes,
                authority: grant.resolvedAuthority,
                sessionID: grant.id,
                appUsageRef: grant.appUsageRef,
                reason: .parentEnded
            )
        }
        sessionStatus = .locked
        clearActiveSession()
        recordDeviceCommand(kind: .parentRelock, status: .succeeded, createdAt: commandDate)
        persistSession()
        return newestReceipt
    }

    /// Ends only the selected app's local grant; all other app sessions continue.
    @discardableResult
    func endConcurrentExternalUnlock(sessionID: UUID, now: Date = Date()) -> RewardSessionReceipt? {
        guard let grant = activeGrants.first(where: { $0.id == sessionID }) else { return nil }
        let receipt = finalizeReceipt(
            startedAt: grant.startedAt,
            plannedEndsAt: grant.endsAt,
            endedAt: min(now, grant.endsAt),
            grantedMinutes: grant.minutes,
            authority: grant.resolvedAuthority,
            sessionID: grant.id,
            appUsageRef: grant.appUsageRef,
            reason: .parentEnded
        )
        activeGrants.removeAll { $0.id == sessionID }
        if activeGrants.isEmpty {
            sessionStatus = .locked
            clearActiveSession()
        } else {
            refreshAggregateActiveFields()
        }
        recordDeviceCommand(kind: .parentRelock, status: .succeeded, createdAt: min(now, grant.endsAt))
        persistSession()
        return receipt
    }

    // MARK: - 私有

    private func finalizeReceipt(
        startedAt: Date,
        plannedEndsAt: Date,
        endedAt: Date,
        grantedMinutes: Int,
        authority: ScreenTimeGrantAuthority,
        sessionID: UUID,
        appUsageRef: String?,
        reason: SessionEndReason
    ) -> RewardSessionReceipt {
        let granted = grantedMinutes
        let elapsedSeconds = max(0, endedAt.timeIntervalSince(startedAt))
        let consumed = min(granted, Int(ceil(elapsedSeconds / 60)))
        let unused = max(0, granted - consumed)

        let receipt = RewardSessionReceipt(
            id: UUID(),
            sessionID: sessionID,
            appUsageRef: appUsageRef,
            grantedMinutes: granted,
            startedAt: startedAt,
            plannedEndsAt: plannedEndsAt,
            endedAt: endedAt,
            endReason: reason,
            consumedMinutes: consumed,
            unusedMinutes: unused,
            authority: authority
        )
        receipts.insert(receipt, at: 0)
        return receipt
    }

    /// 清空进行中会话字段，但保留 sessionStatus（由调用方设为 .locked / .expired）。
    private func clearActiveSession() {
        activeGrants = []
        unlockEndsAt = nil
        unlockStartedAt = nil
        activeMinutes = 0
    }

    private func refreshAggregateActiveFields() {
        guard !activeGrants.isEmpty else {
            clearActiveSession()
            return
        }
        sessionStatus = .active
        unlockStartedAt = activeGrants.map(\.startedAt).min()
        unlockEndsAt = activeGrants.map(\.endsAt).max()
        activeMinutes = activeGrants.reduce(0) { $0 + $1.minutes }
    }

    private func recordDeviceCommand(
        kind: ScreenTimeDeviceCommandKind,
        status: ScreenTimeDeviceCommandStatus,
        requestedMinutes: Int? = nil,
        createdAt: Date = Date(),
        plannedEndsAt: Date? = nil,
        failureReason: ScreenTimeDeviceCommandFailureReason? = nil
    ) {
        let receipt = ScreenTimeDeviceCommandReceipt(
            id: UUID(),
            kind: kind,
            status: status,
            requestedMinutes: requestedMinutes,
            createdAt: createdAt,
            plannedEndsAt: plannedEndsAt,
            failureReason: failureReason
        )
        deviceCommandReceipts.insert(receipt, at: 0)
        persistSession()
    }

    private func hardLock() {
        sessionStatus = .locked
        clearActiveSession()
        persistSession()
    }
}
