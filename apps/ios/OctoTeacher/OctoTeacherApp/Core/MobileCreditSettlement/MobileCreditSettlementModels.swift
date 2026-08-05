import Foundation

/// iOS 本地「成长积分结算建议」模型层。
///
/// 承接平台共享契约 B28（mobile-credit-settlement-ledger-bridge / 移动成长积分结算账本桥接）的
/// view 语义，把「离线重放结果、设备奖励会话、学校作业流、亲友鼓励、成长积分兑换请求」等本地 mock
/// 信号，投影成 **ledger-neutral（账本中立）** 的结算「建议 / 状态」，供首页、奖励、家长端只读展示。
///
/// 关键安全边界（与 CLAUDE.md、B28 一致）：
///
/// - **绝不真实发成长积分 / 扣成长积分 / 退款 / 释放 hold / 解锁设备 / 写学校作业终态 / 发动态 / 发通知**。
///   每条建议都携带四个恒为 `false` 的护栏标记（`writesLedger` / `unlocksDevice` /
///   `modifiesSchoolHomework` / `sendsNotification`），从结构上保证它只是「可审核的建议」。
/// - **`proposed`（可建议）不是发成长积分**：它只表示这条结算在脱敏、幂等、账户匹配后可被家长流程审核，
///   将来由真实账本决定是否落定。`hold`（冻结）只代表「积分将被预留待家长开启」，不真正锁定余额。
/// - **老师/家长冲突、亲友鼓励、设备失败、离线回滚、撤权会话、孩子自提奖励** 一律不得结算为可用成长积分：
///   分别投影为 `conflict` / `review_required` / `blocked`，绝不 `proposed`。
/// - **只读脱敏**：输出只含哈希引用（`prefix:token`）、类型/状态标签与脱敏文案，绝不暴露真实
///   child/family/school/teacher/relative/device/ledger/ref、token、路径、局域网地址、taskId、claimId
///   或完整内部 ID。

// MARK: - 结算类型

/// 一条成长积分结算建议的类型（与 B28 `MobileCreditSettlementKind` 对齐）。
enum MobileCreditSettlementKind: String, Codable, Equatable, CaseIterable {
    /// 赚取：完成任务/作业后建议将来发放的成长积分。
    case earn
    /// 冻结：为奖励会话预留成长积分（不真正锁定余额）。
    case hold
    /// 消费：建议从已冻结成长积分中扣减（需先有对应 hold）。
    case spend
    /// 释放：把未用完的冻结成长积分建议退回余额。
    case release
    /// 退款：失败/回滚后建议退回成长积分。
    case refund
    /// 冲销：对一笔已有交易建议反向冲销。
    case reverse

    var label: String {
        switch self {
        case .earn: return "赚取建议"
        case .hold: return "冻结建议"
        case .spend: return "消费建议"
        case .release: return "释放建议"
        case .refund: return "退款建议"
        case .reverse: return "冲销建议"
        }
    }
}

// MARK: - 结算来源

/// 结算建议的本地来源（与 B28 `MobileCreditSettlementSource` 对齐，按 iOS 本地数据源裁剪）。
enum MobileCreditSettlementSource: String, Codable, Equatable, CaseIterable {
    /// 离线动作（来自离线重放结果）。
    case offlineAction = "offline_action"
    /// 设备奖励会话生命周期（来自 MockScreenTimeController）。
    case deviceRewardLifecycle = "device_reward_lifecycle"
    /// 学校作业移动流（来自 SchoolFamilyStore）。
    case schoolHomeworkMobileFlow = "school_homework_mobile_flow"
    /// 亲友鼓励（只能成为待审核建议，绝不直接发成长积分）。
    case relativeEncouragement = "relative_encouragement"
    /// 成长积分兑换请求（孩子发起，需家长开启）。
    case rewardRequest = "reward_request"
    /// 家长审批闭环。
    case familyApproval = "family_approval"

    var label: String {
        switch self {
        case .offlineAction: return "离线动作"
        case .deviceRewardLifecycle: return "设备奖励会话"
        case .schoolHomeworkMobileFlow: return "学校作业"
        case .relativeEncouragement: return "亲友鼓励"
        case .rewardRequest: return "成长积分兑换请求"
        case .familyApproval: return "家长审批"
        }
    }
}

// MARK: - 会话状态 / 结论 / 角色

/// 发起结算时所在移动会话的状态。撤权会话不得产生可用结算。
enum MobileCreditSettlementSessionState: String, Codable, Equatable {
    case active
    case revoked
    case expired
}

/// 老师 / 家长对一条提交的结论。两者不一致即冲突，需成人复核。
enum MobileCreditSettlementConclusion: String, Codable, Equatable {
    case approved
    case returned
    case rejected
}

/// 发起结算建议的角色。
enum MobileCreditSettlementActorRole: String, Codable, Equatable {
    case child
    case guardian
    case teacher
    case relative
    case system

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        case .teacher: return "老师"
        case .relative: return "亲友"
        case .system: return "系统"
        }
    }
}

// MARK: - 结算状态

/// 一条结算建议经引擎裁决后的状态（与 B28 `MobileCreditSettlementStatus` 对齐）。
enum MobileCreditSettlementStatus: String, Codable, Equatable, CaseIterable {
    /// 可建议：脱敏、幂等、账户匹配通过，可交家长流程审核（账本中立，未发成长积分）。
    case proposed
    /// 重复：相同幂等键 / 离线重放，按重放处理，不再生成新结算。
    case duplicate
    /// 过期：冻结已过期，只投影为复核项，不激活。
    case expired
    /// 冲突：老师/家长结论冲突或离线冲突，需成人复核。
    case conflict
    /// 待审核：亲友鼓励、设备失败退款等只能成为待审核建议。
    case reviewRequired = "review_required"
    /// 已阻断：账户不匹配、金额非法、不安全负载、撤权会话、离线回滚、缺关联 hold。
    case blocked

    var label: String {
        switch self {
        case .proposed: return "可建议"
        case .duplicate: return "重复忽略"
        case .expired: return "已过期"
        case .conflict: return "有冲突"
        case .reviewRequired: return "待审核"
        case .blocked: return "已阻断"
        }
    }
}

// MARK: - 展示分组（供 UI 归类）

/// UI 展示分组：把（状态 + 类型）归并成首页/奖励/家长端要展示的五类。
///
/// 这是**纯展示归类**，不改变结算状态语义。
enum MobileCreditSettlementDisplayGroup: String, Equatable, CaseIterable {
    /// 待审核：冲突 / 待审核。
    case reviewRequired
    /// 冻结：可建议的 hold。
    case frozen
    /// 可建议：可建议的 earn / spend。
    case proposable
    /// 退款/回滚建议：可建议的 release / refund / reverse。
    case refundSuggestion
    /// 已阻断：阻断 / 重复 / 过期。
    case blocked

    var label: String {
        switch self {
        case .reviewRequired: return "待审核"
        case .frozen: return "冻结"
        case .proposable: return "可建议"
        case .refundSuggestion: return "退款/回滚建议"
        case .blocked: return "已阻断"
        }
    }

    var systemImage: String {
        switch self {
        case .reviewRequired: return "person.crop.circle.badge.clock"
        case .frozen: return "lock.circle"
        case .proposable: return "lightbulb"
        case .refundSuggestion: return "arrow.uturn.backward.circle"
        case .blocked: return "nosign"
        }
    }

    static func from(status: MobileCreditSettlementStatus, kind: MobileCreditSettlementKind) -> MobileCreditSettlementDisplayGroup {
        switch status {
        case .blocked, .duplicate, .expired:
            return .blocked
        case .conflict, .reviewRequired:
            return .reviewRequired
        case .proposed:
            switch kind {
            case .hold:
                return .frozen
            case .release, .refund, .reverse:
                return .refundSuggestion
            case .earn, .spend:
                return .proposable
            }
        }
    }
}

// MARK: - 发现项编码

/// 结算发现项编码（B28 编码 + iOS 本地补充项）。
enum MobileCreditSettlementFindingCode: String, Codable, Equatable {
    // 与 B28 对齐
    case duplicateIdempotency = "duplicate_idempotency"
    case expiredHold = "expired_hold"
    case teacherGuardianConflict = "teacher_guardian_conflict"
    case deviceFailureRefundReview = "device_failure_refund_review"
    case revokedActionBlocked = "revoked_action_blocked"
    case crossChildFamilyMismatch = "cross_child_family_mismatch"
    case relativeEncouragementReviewRequired = "relative_encouragement_review_required"
    case offlineReplayBlocked = "offline_replay_blocked"
    case rollbackRequired = "rollback_required"
    case unsafePayload = "unsafe_payload"
    case invalidAmount = "invalid_amount"
    case missingRelatedHold = "missing_related_hold"
    case publicSummaryLeak = "public_summary_leak"
    // iOS 本地补充：离线（非回滚）冲突需复核
    case offlineConflictReview = "offline_conflict_review"

    var severity: MobileCreditSettlementSeverity {
        switch self {
        case .crossChildFamilyMismatch, .invalidAmount, .unsafePayload,
             .revokedActionBlocked, .rollbackRequired, .missingRelatedHold,
             .publicSummaryLeak, .teacherGuardianConflict:
            return .blocker
        default:
            return .warning
        }
    }
}

enum MobileCreditSettlementSeverity: String, Codable, Equatable {
    case info
    case warning
    case blocker
}

/// 一条脱敏发现项。
struct MobileCreditSettlementFinding: Identifiable, Equatable {
    var code: MobileCreditSettlementFindingCode
    var severity: MobileCreditSettlementSeverity
    var message: String
    var publicRef: String

    var id: String { "\(code.rawValue):\(publicRef)" }
}

// MARK: - 结算建议输入（来自本地数据源的脱敏草稿）

/// 一条结算建议输入草稿。调用方（assembler）只填脱敏 seed 与摘要；
/// 引擎据此裁决状态并分配脱敏 publicRef。所有 `*Seed` 都是脱敏引用或本地哈希源，
/// 绝不是真实内部 ID，且永不原样出现在输出里（输出再哈希一次）。
struct MobileCreditSettlementProposalInput: Equatable {
    var proposalSeed: String
    var kind: MobileCreditSettlementKind
    var source: MobileCreditSettlementSource
    var childSeed: String
    var familySeed: String
    /// 建议结算的成长积分数。来源无内在金额时使用脱敏「建议」值，恒为正。
    var amount: Int
    /// 使用范围脱敏标签（如「需家长批准」）。
    var scopeLabel: String
    var requestedAt: String
    var idempotencyKey: String
    var actorRole: MobileCreditSettlementActorRole
    var sessionState: MobileCreditSettlementSessionState
    var holdExpired: Bool
    var teacherConclusion: MobileCreditSettlementConclusion?
    var guardianConclusion: MobileCreditSettlementConclusion?
    /// spend / release / refund 是否有对应的已冻结成长积分。
    var relatedHoldPresent: Bool
    /// 离线重放 / 重复（投影为 duplicate）。
    var offlineReplayed: Bool
    /// 离线（非回滚）冲突（投影为 conflict / 待审核）。
    var offlineConflict: Bool
    /// 离线回滚 / 需回滚（投影为 blocked，绝不结算为可用成长积分）。
    var offlineRolledBack: Bool
    /// 设备命令失败（投影为退款待审核）。
    var deviceFailed: Bool
    /// 脱敏自检探针：会被脱敏守卫扫描，命中即 blocked。
    var redactionProbe: [String]

    init(
        proposalSeed: String,
        kind: MobileCreditSettlementKind,
        source: MobileCreditSettlementSource,
        childSeed: String,
        familySeed: String,
        amount: Int,
        scopeLabel: String = "需家长批准",
        requestedAt: String = "2026-06-23T22:00:00Z",
        idempotencyKey: String,
        actorRole: MobileCreditSettlementActorRole,
        sessionState: MobileCreditSettlementSessionState = .active,
        holdExpired: Bool = false,
        teacherConclusion: MobileCreditSettlementConclusion? = nil,
        guardianConclusion: MobileCreditSettlementConclusion? = nil,
        relatedHoldPresent: Bool = true,
        offlineReplayed: Bool = false,
        offlineConflict: Bool = false,
        offlineRolledBack: Bool = false,
        deviceFailed: Bool = false,
        redactionProbe: [String] = []
    ) {
        self.proposalSeed = proposalSeed
        self.kind = kind
        self.source = source
        self.childSeed = childSeed
        self.familySeed = familySeed
        self.amount = amount
        self.scopeLabel = scopeLabel
        self.requestedAt = requestedAt
        self.idempotencyKey = idempotencyKey
        self.actorRole = actorRole
        self.sessionState = sessionState
        self.holdExpired = holdExpired
        self.teacherConclusion = teacherConclusion
        self.guardianConclusion = guardianConclusion
        self.relatedHoldPresent = relatedHoldPresent
        self.offlineReplayed = offlineReplayed
        self.offlineConflict = offlineConflict
        self.offlineRolledBack = offlineRolledBack
        self.deviceFailed = deviceFailed
        self.redactionProbe = redactionProbe
    }
}

/// 账户上下文：结算建议必须匹配的孩子/家庭脱敏 seed。不匹配即 blocked。
struct MobileCreditSettlementAccount: Equatable {
    var childSeed: String
    var familySeed: String
}

// MARK: - 结算建议（脱敏输出）

/// 一条结算建议输出，专供 UI 展示。账本中立，四个护栏标记恒为 false。
struct MobileCreditSettlementProposal: Identifiable, Equatable {
    var publicProposalRef: String
    var kind: MobileCreditSettlementKind
    var status: MobileCreditSettlementStatus
    var source: MobileCreditSettlementSource
    var childPublicRef: String
    var accountPublicRef: String
    var amount: Int
    var scopeLabel: String
    var requestedAt: String
    var reason: String
    var actionRequired: Bool
    var retryable: Bool

    // 护栏：恒为 false，编译期表明这是建议而非落定。
    let writesLedger = false
    let unlocksDevice = false
    let modifiesSchoolHomework = false
    let sendsNotification = false

    var id: String { publicProposalRef }

    var displayGroup: MobileCreditSettlementDisplayGroup {
        MobileCreditSettlementDisplayGroup.from(status: status, kind: kind)
    }

    var kindLabel: String { kind.label }
    var statusLabel: String { status.label }
    var sourceLabel: String { source.label }
    var groupLabel: String { displayGroup.label }
    var amountLabel: String { "\(amount) 成长积分" }
    var systemImage: String { displayGroup.systemImage }

    static func == (lhs: MobileCreditSettlementProposal, rhs: MobileCreditSettlementProposal) -> Bool {
        lhs.publicProposalRef == rhs.publicProposalRef
            && lhs.kind == rhs.kind
            && lhs.status == rhs.status
            && lhs.source == rhs.source
            && lhs.childPublicRef == rhs.childPublicRef
            && lhs.accountPublicRef == rhs.accountPublicRef
            && lhs.amount == rhs.amount
            && lhs.scopeLabel == rhs.scopeLabel
            && lhs.requestedAt == rhs.requestedAt
            && lhs.reason == rhs.reason
            && lhs.actionRequired == rhs.actionRequired
            && lhs.retryable == rhs.retryable
    }
}

// MARK: - 公开摘要（脱敏聚合）

/// 结算报告的脱敏公开摘要：只暴露计数与发现项编码。
struct MobileCreditSettlementPublicSummary: Equatable {
    var generatedAt: String
    var accountPublicRef: String
    var childPublicRef: String
    var proposalCount: Int
    var proposedCount: Int
    var blockedCount: Int
    var reviewRequiredCount: Int
    var duplicateCount: Int
    var expiredCount: Int
    var conflictCount: Int
    var totalProposedAmount: Int
    var findingCodes: [MobileCreditSettlementFindingCode]

    let writesLedger = false
    let unlocksDevice = false
    let modifiesSchoolHomework = false
    let sendsNotification = false
}

// MARK: - 结算报告

/// 一次结算投影的聚合报告。
struct MobileCreditSettlementReport: Equatable {
    var generatedAt: String
    var proposals: [MobileCreditSettlementProposal]
    var findings: [MobileCreditSettlementFinding]
    var publicSummary: MobileCreditSettlementPublicSummary

    var isEmpty: Bool { proposals.isEmpty }

    /// 是否有需要成人关注的建议（待审核 / 冲突 / 阻断）。
    var hasAttention: Bool {
        proposals.contains {
            $0.status == .reviewRequired || $0.status == .conflict || $0.status == .blocked
        }
    }

    /// 按展示分组取建议。
    func proposals(in group: MobileCreditSettlementDisplayGroup) -> [MobileCreditSettlementProposal] {
        proposals.filter { $0.displayGroup == group }
    }

    /// 一句话总览（脱敏）。
    var headline: String {
        if proposals.isEmpty { return "暂无结算建议" }
        var parts: [String] = []
        let proposable = proposals(in: .proposable).count + proposals(in: .frozen).count + proposals(in: .refundSuggestion).count
        if proposable > 0 { parts.append("\(proposable) 条可建议") }
        let review = proposals(in: .reviewRequired).count
        if review > 0 { parts.append("\(review) 条待审核") }
        let blocked = proposals(in: .blocked).count
        if blocked > 0 { parts.append("\(blocked) 条已阻断") }
        return parts.isEmpty ? "暂无结算建议" : parts.joined(separator: " · ")
    }

    static let empty = MobileCreditSettlementReport(
        generatedAt: "",
        proposals: [],
        findings: [],
        publicSummary: MobileCreditSettlementPublicSummary(
            generatedAt: "",
            accountPublicRef: "",
            childPublicRef: "",
            proposalCount: 0,
            proposedCount: 0,
            blockedCount: 0,
            reviewRequiredCount: 0,
            duplicateCount: 0,
            expiredCount: 0,
            conflictCount: 0,
            totalProposedAmount: 0,
            findingCodes: []
        )
    )
}
