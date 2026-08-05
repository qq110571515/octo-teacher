import Foundation

/// iOS 端「成长积分账本复核台」只读模型层。
///
/// 复核台消费 `MobileCreditSettlementReport`（B28 移动成长积分结算账本桥接的本地投影）
/// 与一份**本地成长积分余额快照**，把结算建议按「可建议 / 待审核 / 冻结 / 冲突 / 退款回滚」
/// 分组呈现给家长复核，并对孩子等非家长角色只暴露安全状态文案。
///
/// 关键安全边界（与 CLAUDE.md、B28 一致）：
///
/// - **绝不真实写账本 / 发成长积分 / 扣成长积分 / 退款 / 释放冻结 / 解锁设备 / 发通知**。复核台只读：
///   余额快照是脱敏 mock，不是真实账本；结算项是「可审核的建议」，落定仍由家长流程与真实账本决定。
/// - **角色门控**：只有家长能看到复核原因、建议金额、幂等/离线/设备/学校来源标签与余额；
///   孩子、亲友、老师只看到安全状态文案，看不到金额、原因、幂等键、离线冲突详情、退款/回滚原因。
/// - **不暴露真实标识**：输出只含哈希引用（`prefix-token`）、类型/状态/来源标签与脱敏文案，绝不暴露
///   child/family/school/teacher/relative/device/ledger/ref、token、路径、局域网地址、taskId、claimId
///   或完整内部 ID；幂等键只展示「已校验」事实，绝不展示键值本身。

// MARK: - 查看角色

/// 复核台查看角色。只有家长可见完整复核内容。
enum CreditLedgerReviewViewerRole: String, Equatable, CaseIterable {
    case guardian
    case child
    case relative
    case teacher

    var label: String {
        switch self {
        case .guardian: return "家长"
        case .child: return "孩子"
        case .relative: return "亲友"
        case .teacher: return "老师"
        }
    }

    /// 是否拥有家长级复核可见性（原因、金额、幂等/来源、余额）。
    var canReviewInternals: Bool { self == .guardian }
}

// MARK: - 复核台状态

/// 复核台整体状态。
enum CreditLedgerReviewStatus: String, Equatable {
    case ready
    case empty
    case reviewRequired = "review_required"
    case conflict
    case blocked

    var label: String {
        switch self {
        case .ready: return "可复核"
        case .empty: return "暂无建议"
        case .reviewRequired: return "需复核"
        case .conflict: return "有冲突"
        case .blocked: return "已阻断"
        }
    }
}

// MARK: - 展示分组

/// 复核台展示分组：把结算建议（状态 + 类型）归并成家长复核要看的分组。
///
/// 任务要求的五个主分组：可建议 / 待审核 / 冻结 / 冲突 / 退款回滚。
/// 额外保留 `blockedOrIgnored`（已阻断/忽略），以免把阻断、重复、过期等安全态从家长视图里藏起来。
enum CreditLedgerReviewSection: String, Equatable, CaseIterable {
    /// 可建议：可建议的 earn / spend。
    case proposable
    /// 待审核：review_required（亲友鼓励、设备失败退款等）。
    case reviewRequired
    /// 冻结：可建议的 hold。
    case frozen
    /// 冲突：老师/家长结论冲突或离线冲突。
    case conflict
    /// 退款/回滚：可建议的 release / refund / reverse。
    case refundOrRollback
    /// 已阻断/忽略：blocked / duplicate / expired（安全态，不对孩子展开原因）。
    case blockedOrIgnored

    var label: String {
        switch self {
        case .proposable: return "可建议"
        case .reviewRequired: return "待审核"
        case .frozen: return "冻结"
        case .conflict: return "冲突"
        case .refundOrRollback: return "退款/回滚"
        case .blockedOrIgnored: return "已阻断/忽略"
        }
    }

    var systemImage: String {
        switch self {
        case .proposable: return "lightbulb"
        case .reviewRequired: return "person.crop.circle.badge.clock"
        case .frozen: return "lock.circle"
        case .conflict: return "exclamationmark.triangle"
        case .refundOrRollback: return "arrow.uturn.backward.circle"
        case .blockedOrIgnored: return "nosign"
        }
    }

    /// 家长复核台分组顺序。
    static let displayOrder: [CreditLedgerReviewSection] = [
        .proposable, .reviewRequired, .frozen, .conflict, .refundOrRollback, .blockedOrIgnored
    ]

    /// 由结算状态 + 类型归并到复核分组。
    static func from(status: MobileCreditSettlementStatus, kind: MobileCreditSettlementKind) -> CreditLedgerReviewSection {
        switch status {
        case .conflict:
            return .conflict
        case .reviewRequired:
            return .reviewRequired
        case .blocked, .duplicate, .expired:
            return .blockedOrIgnored
        case .proposed:
            switch kind {
            case .hold:
                return .frozen
            case .release, .refund, .reverse:
                return .refundOrRollback
            case .earn, .spend:
                return .proposable
            }
        }
    }

    /// 孩子等非家长角色看到的安全状态文案（不含金额、原因、来源）。
    var childSafeStatus: String {
        switch self {
        case .proposable: return "有新的成长奖励正在等家长确认。"
        case .reviewRequired: return "有内容正在等家长复核。"
        case .frozen: return "一份成长积分正在等家长开启。"
        case .conflict: return "有内容需要家长再确认一次。"
        case .refundOrRollback: return "有成长积分正在退回处理中。"
        case .blockedOrIgnored: return "有内容暂时不能发放，已交给家长处理。"
        }
    }
}

// MARK: - 本地成长积分余额快照（只读 mock 输入）

/// 一份脱敏的本地成长积分余额快照。**只读**：不是真实账本，复核台不据此发放或扣减任何成长积分。
///
/// 底层字段名沿用早期分钟口径以兼容旧快照；所有对外展示必须使用成长积分文案。
struct CreditLedgerBalanceSnapshot: Equatable {
    /// 可用成长积分（可建议消费的余量，展示用）。
    var availableMinutes: Int
    /// 冻结中的成长积分（hold 预留，未真正锁定）。
    var frozenMinutes: Int
    /// 待审核成长积分（等家长复核的建议合计）。
    var pendingMinutes: Int
    /// 累计获得成长积分（历史，展示用）。
    var lifetimeEarnedMinutes: Int
    /// 快照时间（脱敏）。
    var asOf: String

    // 护栏：这是只读快照，不是实时账本，写入恒为 false。
    let isLiveLedger = false
    let writesLedger = false

    var availableLabel: String { "\(availableMinutes) 积分" }
    var frozenLabel: String { "\(frozenMinutes) 积分" }
    var pendingLabel: String { "\(pendingMinutes) 积分" }
    var lifetimeEarnedLabel: String { "\(lifetimeEarnedMinutes) 积分" }

    static let empty = CreditLedgerBalanceSnapshot(
        availableMinutes: 0,
        frozenMinutes: 0,
        pendingMinutes: 0,
        lifetimeEarnedMinutes: 0,
        asOf: ""
    )
}

// MARK: - 复核项（脱敏、角色门控输出）

/// 一条复核项。家长看到完整复核内容；非家长只看到 `childSafeStatus`，金额/原因/来源全部为空。
struct CreditLedgerReviewItem: Identifiable, Equatable {
    var publicReviewRef: String
    var section: CreditLedgerReviewSection
    var kindLabel: String
    var statusLabel: String
    /// 安全状态文案（任何角色可见）。
    var childSafeStatus: String
    /// 复核原因（仅家长）。非家长为 nil。
    var reason: String?
    /// 建议金额（旧字段名沿用分钟口径，仅家长）。非家长为 nil；对外展示必须使用成长积分文案。
    var amountMinutes: Int?
    /// 来源标签（仅家长），如「离线动作」「设备奖励会话」「学校作业」。
    var sourceLabel: String?
    /// 只读来源标签（仅家长）：幂等已校验、离线、设备、学校等事实标签，不含键值或路径。
    var originTags: [String]
    var actionRequired: Bool

    // 护栏：复核项账本中立。
    let writesLedger = false
    let issuesCredit = false
    let unlocksDevice = false
    let sendsNotification = false

    var id: String { publicReviewRef }
    var amountLabel: String? { amountMinutes.map { "\($0) 成长积分" } }
}

/// 一个分组下的复核项集合。
struct CreditLedgerReviewSectionGroup: Identifiable, Equatable {
    var section: CreditLedgerReviewSection
    var items: [CreditLedgerReviewItem]

    var id: String { section.rawValue }
    var label: String { section.label }
    var systemImage: String { section.systemImage }
    var count: Int { items.count }
}

// MARK: - 可见性

/// 角色可见性矩阵：家长可见全部内部复核信息，其余角色只看安全状态。
struct CreditLedgerReviewVisibility: Equatable {
    var viewerRole: CreditLedgerReviewViewerRole
    var canSeeAmounts: Bool
    var canSeeReasons: Bool
    var canSeeIdempotency: Bool
    var canSeeOrigin: Bool
    var canSeeBalance: Bool

    static func forRole(_ role: CreditLedgerReviewViewerRole) -> CreditLedgerReviewVisibility {
        let guardian = role.canReviewInternals
        return CreditLedgerReviewVisibility(
            viewerRole: role,
            canSeeAmounts: guardian,
            canSeeReasons: guardian,
            canSeeIdempotency: guardian,
            canSeeOrigin: guardian,
            canSeeBalance: guardian
        )
    }
}

// MARK: - 发现项

enum CreditLedgerReviewFindingCode: String, Equatable {
    case consoleOK = "CREDIT_LEDGER_REVIEW_OK"
    case roleVisibilityApplied = "ROLE_VISIBILITY_APPLIED"
    case nonGuardianDetailHidden = "NON_GUARDIAN_DETAIL_HIDDEN"
    case conflictReviewRequired = "CONFLICT_REVIEW_REQUIRED"
    case reviewRequiredPresent = "REVIEW_REQUIRED_PRESENT"
    case blockedPresent = "BLOCKED_PRESENT"
    case upstreamLeak = "UPSTREAM_LEAK"
    case publicSummaryLeak = "PUBLIC_SUMMARY_LEAK"
}

enum CreditLedgerReviewSeverity: String, Equatable {
    case ok
    case info
    case warning
    case blocker
}

struct CreditLedgerReviewFinding: Identifiable, Equatable {
    var code: CreditLedgerReviewFindingCode
    var severity: CreditLedgerReviewSeverity
    var message: String
    var publicRef: String

    var id: String { "\(code.rawValue):\(publicRef)" }
}

// MARK: - 公开摘要

/// 复核台脱敏公开摘要：只暴露计数与发现项编码；金额仅家长可见时非零。
struct CreditLedgerReviewSummary: Equatable {
    var generatedAt: String
    var viewerRole: CreditLedgerReviewViewerRole
    var status: CreditLedgerReviewStatus
    var visibleItemCount: Int
    var proposableCount: Int
    var reviewRequiredCount: Int
    var frozenCount: Int
    var conflictCount: Int
    var refundOrRollbackCount: Int
    var blockedOrIgnoredCount: Int
    /// 可建议合计分钟（仅家长非零）。
    var totalProposableMinutes: Int
    var findingCodes: [CreditLedgerReviewFindingCode]

    // 护栏：复核台只读、账本中立、无副作用。
    let readOnly = true
    let writesLedger = false
    let issuesCredit = false
    let revokesCredit = false
    let unlocksDevice = false
    let sendsNotification = false
    let callsLedgerApi = false
}

// MARK: - 复核台

/// 一次复核台投影。账户中立、脱敏、角色门控、无副作用。
struct CreditLedgerReviewConsole: Equatable {
    var generatedAt: String
    var viewerRole: CreditLedgerReviewViewerRole
    var status: CreditLedgerReviewStatus
    var visibility: CreditLedgerReviewVisibility
    /// 余额快照仅家长可见；非家长为 nil。
    var balance: CreditLedgerBalanceSnapshot?
    var sections: [CreditLedgerReviewSectionGroup]
    var findings: [CreditLedgerReviewFinding]
    var summary: CreditLedgerReviewSummary

    var isEmpty: Bool { sections.allSatisfy { $0.items.isEmpty } }

    /// 一句话总览（脱敏，按角色裁剪）。
    var headline: String {
        if isEmpty { return "暂无成长积分复核项" }
        if !viewerRole.canReviewInternals { return "有内容正在等家长复核" }
        var parts: [String] = []
        if summary.proposableCount > 0 { parts.append("\(summary.proposableCount) 条可建议") }
        if summary.reviewRequiredCount > 0 { parts.append("\(summary.reviewRequiredCount) 条待审核") }
        if summary.conflictCount > 0 { parts.append("\(summary.conflictCount) 条冲突") }
        if summary.blockedOrIgnoredCount > 0 { parts.append("\(summary.blockedOrIgnoredCount) 条已阻断") }
        return parts.isEmpty ? "暂无成长积分复核项" : parts.joined(separator: " · ")
    }

    /// 取某分组（保持声明顺序）。
    func group(_ section: CreditLedgerReviewSection) -> CreditLedgerReviewSectionGroup? {
        sections.first { $0.section == section }
    }
}
