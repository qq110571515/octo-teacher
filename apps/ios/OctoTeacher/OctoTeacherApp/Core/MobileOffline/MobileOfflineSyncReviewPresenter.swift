import Foundation

/// 离线同步本地复核台的**纯逻辑**展示映射。
///
/// 把 `MobileOfflineOutboxStore.publicStatus` / `conflictHints` 与
/// `MobileOfflineReplayStore.report` 三个本地只读输入，按视角脱敏地编排成复核台可消费的
/// 行模型。设计约束（与 CLAUDE.md 一致，且复用 outbox/replay 既有的脱敏边界）：
///
/// - **完全本地只读**：不接真实网络、云 API、数据库、队列、登录、支付、AI、LMS、学校系统、
///   通知、账本、FamilyControls、HealthKit 或真实设备控制；这里只读三个 mock store 的派生值。
/// - **不落定**：本地重放的 `confirmed` 只代表「mock 已收到」，复核台从不把它当成业务完成，
///   不写账本、不发成长积分、不扣成长积分、不解锁设备、不改 entitlement、不应用回滚。
/// - **角色裁剪**：孩子只看安全状态与下一步（`confirmed` / `needsGuardianReview`），看不到
///   冲突原因明细与回滚摘要；家长才看冲突提示与回滚摘要。
/// - **脱敏**：所有文案来自 outbox/replay 已脱敏的字段（计数、状态标签、人类可读提示），
///   绝不暴露真实 child/family/school/pack/order/entitlement/homework/session/device/ledger/ref、
///   token、路径、局域网地址、taskId、claimId 或完整内部 ID。
struct MobileOfflineSyncReviewPresenter: Equatable {
    let perspective: MobileHomePerspective
    let status: MobileOfflinePublicStatus
    let conflictHints: [MobileOfflineConflictHint]
    let report: MobileOfflineReplayReport

    init(
        perspective: MobileHomePerspective,
        status: MobileOfflinePublicStatus,
        conflictHints: [MobileOfflineConflictHint],
        report: MobileOfflineReplayReport
    ) {
        self.perspective = perspective
        self.status = status
        self.conflictHints = conflictHints
        self.report = report
    }

    /// 顶部一句话总览（脱敏）。
    var headline: String {
        if perspective == .child {
            // 孩子端不暴露冲突/回滚计数，只给安全的进度感受。
            return status.isClean ? "同步都完成啦" : "还有一些动作在等同步或家长处理"
        }
        return status.headline
    }

    /// 复核台说明：明确只读、不落定边界。
    var footnote: String {
        switch perspective {
        case .child:
            return "这里只看安全的同步状态和下一步，不会发积分、不会解锁设备。"
        case .parent:
            return "本地只读复核：可手动重放看结果，但不写账本、不发成长积分、不扣成长积分、不解锁设备，回滚需到专属流程处理。"
        }
    }

    /// 是否向当前视角展示冲突/回滚明细（仅家长）。
    var showsConflictDetails: Bool { perspective == .parent }

    /// 对当前视角可见的冲突/回滚提示：孩子端恒为空。
    var visibleConflictHints: [MobileOfflineConflictHint] {
        showsConflictDetails ? conflictHints : []
    }

    /// 对当前视角可见的重放结果。
    ///
    /// - 孩子：只看 `confirmed` / `needsGuardianReview` 两种安全态，隐藏冲突/回滚明细。
    /// - 家长：看全部结果（含冲突/回滚）。
    var visibleResults: [MobileOfflineReplayResult] {
        switch perspective {
        case .child:
            return report.results.filter { $0.status == .confirmed || $0.status == .needsGuardianReview }
        case .parent:
            return report.results
        }
    }

    /// 状态计数行（脱敏）。孩子端只展示「待同步」一项，避免暴露冲突/回滚数量。
    var statusCounts: [Count] {
        switch perspective {
        case .child:
            return [Count(label: "待同步", value: status.pendingCount)]
        case .parent:
            return [
                Count(label: "待同步", value: status.pendingCount),
                Count(label: "冲突", value: status.conflictCount),
                Count(label: "已回滚", value: status.rolledBackCount)
            ]
        }
    }

    /// 是否需要提醒关注（孩子端不据此暴露冲突细节，只用于图标语气）。
    var hasAttention: Bool {
        perspective == .parent ? status.hasAttention : false
    }

    /// 一行脱敏计数。
    struct Count: Identifiable, Equatable {
        var label: String
        var value: Int
        var id: String { label }
    }
}
