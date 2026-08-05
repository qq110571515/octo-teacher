import Foundation

struct ApproveTaskUseCase {
    let store: LocalFamilyStore

    /// 批准任务并返回发放的奖励；若任务已批准则返回 nil（幂等保护）。
    @discardableResult
    func callAsFunction(_ assignment: TaskAssignment) -> RewardGrant? {
        store.approve(assignment)
    }
}

/// 开启奖励会话的结果。失败路径明确，便于 UI 提示且保证成长积分安全。
enum StartRewardSessionResult: Equatable {
    /// 会话已开启，返回计划到期时间。
    case started(endsAt: Date)
    /// 余额不足：未扣成长积分、未解锁。
    case insufficientBalance
    /// 已有进行中会话：拒绝重复解锁，已扣成长积分已回滚。
    case alreadyActive
    /// 分钟数非法（<= 0）：未扣成长积分。
    case invalidMinutes
    /// 本次兑换会超过家长设置的当天解锁上限。
    case dailyLimitExceeded(remainingMinutes: Int)
    /// 设备命令失败：已扣成长积分已回滚，孩子不损失奖励。
    case deviceFailureRolledBack
}

/// 兑换成长积分开启一次屏幕时间会话。先扣成长积分再下发解锁命令；
/// 任何下发失败都回滚成长积分，杜绝「失败会话扣成长积分且无法回滚」。
struct StartRewardSessionUseCase {
    let store: LocalFamilyStore
    let screenTimeController: MockScreenTimeController

    @discardableResult
    func callAsFunction(
        minutes: Int,
        now: Date = Date(),
        externalDeviceStart: ((Int, Date) throws -> Date)? = nil,
        externalDeviceRelock: (() -> Void)? = nil,
        concurrentExternalDeviceStart: ((Int, Date) throws -> ScreenTimeExternalSession)? = nil,
        concurrentExternalDeviceRelock: ((UUID) -> Void)? = nil,
        appUsageRef: String? = nil,
        pointMutationCommitted: ((_ mutationRef: String, _ delta: Int, _ sourceRef: String) -> Void)? = nil,
        transactionCommitted: (() -> Void)? = nil
    ) -> StartRewardSessionResult {
        guard minutes > 0 else { return .invalidMinutes }
        if concurrentExternalDeviceStart == nil,
           screenTimeController.sessionStatus == .active {
            return .alreadyActive
        }

        // 经济系统 P3：余额是成长积分，按家长设定的汇率折算解锁分钟。
        let childId = store.activeChildId
        guard let child = store.children.first(where: { $0.id == childId }) else {
            return .insufficientBalance
        }
        let grantedToday = screenTimeController.grantedMinutes(on: now)
        let remaining = max(0, child.dailyLimitMinutes - grantedToday)
        let additionalMinutes = screenTimeController.additionalGrantedMinutes(
            for: minutes,
            startingAt: now
        )
        guard additionalMinutes <= remaining else {
            return .dailyLimitExceeded(remainingMinutes: remaining)
        }
        let points = store.policy(for: childId).screenPointsRequired(forMinutes: minutes)
        guard child.rewardBalanceMinutes >= points,
              store.spendRewardMinutes(points, for: childId)
        else { return .insufficientBalance }

        if let concurrentExternalDeviceStart {
            let externalSession: ScreenTimeExternalSession
            do {
                externalSession = try concurrentExternalDeviceStart(minutes, now)
            } catch UnlockError.alreadyActive {
                store.refundRewardMinutes(points, for: childId)
                screenTimeController.recordDeviceCommandFailure(minutes: minutes, now: now, reason: .alreadyActive)
                return .alreadyActive
            } catch UnlockError.nonPositiveMinutes {
                store.refundRewardMinutes(points, for: childId)
                screenTimeController.recordDeviceCommandFailure(minutes: minutes, now: now, reason: .nonPositiveMinutes)
                return .invalidMinutes
            } catch {
                store.refundRewardMinutes(points, for: childId)
                screenTimeController.recordDeviceCommandFailure(minutes: minutes, now: now, reason: .deviceCommandFailed)
                return .deviceFailureRolledBack
            }

            do {
                _ = try screenTimeController.adoptConcurrentExternalUnlock(
                    sessionID: externalSession.id,
                    minutes: minutes,
                    now: now,
                    endsAt: externalSession.endsAt,
                    appUsageRef: appUsageRef
                )
                let sourceRef = "screen-time-session:\(externalSession.id.uuidString.lowercased())"
                pointMutationCommitted?("spend:\(sourceRef)", -points, sourceRef)
                transactionCommitted?()
                return .started(endsAt: externalSession.endsAt)
            } catch UnlockError.alreadyActive {
                store.refundRewardMinutes(points, for: childId)
                concurrentExternalDeviceRelock?(externalSession.id)
                return .alreadyActive
            } catch UnlockError.nonPositiveMinutes {
                store.refundRewardMinutes(points, for: childId)
                concurrentExternalDeviceRelock?(externalSession.id)
                return .invalidMinutes
            } catch {
                store.refundRewardMinutes(points, for: childId)
                concurrentExternalDeviceRelock?(externalSession.id)
                screenTimeController.recordDeviceCommandFailure(minutes: minutes, now: now, reason: .deviceCommandFailed)
                return .deviceFailureRolledBack
            }
        }

        do {
            let sessionID = UUID()
            let endsAt: Date
            if let externalDeviceStart {
                endsAt = try externalDeviceStart(minutes, now)
                _ = try screenTimeController.adoptExternalUnlock(
                    sessionID: sessionID,
                    minutes: minutes,
                    now: now,
                    endsAt: endsAt,
                    appUsageRef: appUsageRef
                )
            } else {
                endsAt = try screenTimeController.startSession(
                    sessionID: sessionID,
                    minutes: minutes,
                    now: now,
                    appUsageRef: appUsageRef
                )
            }
            let sourceRef = "screen-time-session:\(sessionID.uuidString.lowercased())"
            pointMutationCommitted?("spend:\(sourceRef)", -points, sourceRef)
            transactionCommitted?()
            return .started(endsAt: endsAt)
        } catch UnlockError.alreadyActive {
            store.refundRewardMinutes(points, for: childId)
            screenTimeController.recordDeviceCommandFailure(minutes: minutes, now: now, reason: .alreadyActive)
            return .alreadyActive
        } catch UnlockError.nonPositiveMinutes {
            store.refundRewardMinutes(points, for: childId)
            screenTimeController.recordDeviceCommandFailure(minutes: minutes, now: now, reason: .nonPositiveMinutes)
            return .invalidMinutes
        } catch {
            // 设备命令失败（或其他下发错误）：回滚成长积分，孩子不损失奖励。
            store.refundRewardMinutes(points, for: childId)
            externalDeviceRelock?()
            screenTimeController.recordDeviceCommandFailure(minutes: minutes, now: now, reason: .deviceCommandFailed)
            return .deviceFailureRolledBack
        }
    }
}
