import Foundation

/// iOS 本地「成长证据链申诉时间线」模型层。
///
/// 承接平台共享契约 B30（growth-evidence-appeal-timeline-contract / 成长证据链申诉时间线契约）的
/// view 语义，把孩子提交、老师验证、家长确认、亲友鼓励、成长积分建议、申诉、撤销和公开成长时间线的
/// 事件，串成一条带 `hash/prevHash` 链校验的**只读、账本中立**证据时间线投影：每个节点带脱敏
/// publicRef、链状态、成长积分冻结/释放/阻断提示、公开可见性与下一步；孩子端看自己的证明链，家长端
/// 看冲突 / 申诉 / 撤销 / 亲友待审核摘要。
///
/// 关键安全边界（与 CLAUDE.md、B30 一致）：
///
/// - **绝不真实写账本 / 改作业终态 / 发布时间线 / 通知亲友 / 保存原始媒体 / 解锁设备 / 发通知**。
///   每条节点、成长积分控制与公开摘要都携带恒为 `false` 的护栏标记，从结构上保证只是「可审核的投影」。
/// - **申诉不绕过家长 / 老师边界**：角色越权（如亲友审批作业、孩子代家长确认）一律 `blocked`；
///   亲友鼓励在家长复核通过前停留 `review_required`，不进孩子或公开可见。
/// - **`credit_suggested` 不是发成长积分**：老师 / 家长结论一致才 `released`（仍只是建议），
///   否则 `frozen`；申诉中冻结，申诉驳回保持 `blocked`，撤销阻断下游成长积分。
/// - **链校验**：缺 hash、prevHash 不匹配、重复证明、跨孩子复用证明、重复幂等键都阻断或视为重放，
///   绝不进入公开时间线或可信成长积分裁决。
/// - **只读脱敏**：输出只含哈希引用（`prefix:token`）、类型 / 状态标签与脱敏文案，绝不暴露真实
///   child/family/school/teacher/relative/guardian/homework/proof/media/ledger/ref、token、路径、
///   局域网地址、taskId、claimId 或完整内部 ID。

// MARK: - 角色 / 事件类型 / 决议 / 可见性

/// 证据时间线参与者角色（与 B30 `GrowthEvidenceAppealTimelineActorRole` 对齐）。
enum GrowthEvidenceTimelineActorRole: String, Codable, Equatable, CaseIterable {
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

/// 证据时间线事件类型（与 B30 `GrowthEvidenceAppealTimelineEventKind` 对齐）。
enum GrowthEvidenceTimelineEventKind: String, Codable, Equatable, CaseIterable {
    case childSubmitted = "child_submitted"
    case teacherVerified = "teacher_verified"
    case guardianConfirmed = "guardian_confirmed"
    case relativeEncouraged = "relative_encouraged"
    case creditSuggested = "credit_suggested"
    case appealOpened = "appeal_opened"
    case appealResolved = "appeal_resolved"
    case revoked
    case timelinePublished = "timeline_published"

    var label: String {
        switch self {
        case .childSubmitted: return "孩子提交"
        case .teacherVerified: return "老师验证"
        case .guardianConfirmed: return "家长确认"
        case .relativeEncouraged: return "亲友鼓励"
        case .creditSuggested: return "成长积分建议"
        case .appealOpened: return "发起申诉"
        case .appealResolved: return "申诉裁决"
        case .revoked: return "撤销证据"
        case .timelinePublished: return "成长时间线展示"
        }
    }

    var systemImage: String {
        switch self {
        case .childSubmitted: return "paperplane"
        case .teacherVerified: return "checkmark.seal"
        case .guardianConfirmed: return "person.badge.shield.checkmark"
        case .relativeEncouraged: return "hands.clap"
        case .creditSuggested: return "lightbulb"
        case .appealOpened: return "exclamationmark.bubble"
        case .appealResolved: return "gavel"
        case .revoked: return "arrow.uturn.backward.circle"
        case .timelinePublished: return "rectangle.stack"
        }
    }
}

/// 验证 / 申诉决议（与 B30 `GrowthEvidenceAppealTimelineDecision` 对齐）。
enum GrowthEvidenceTimelineDecision: String, Codable, Equatable {
    case approved
    case returned
    case rejected
    case restored
    case voided
}

/// 公开可见性（与 B30 `GrowthEvidenceAppealTimelineVisibility` 对齐）。
enum GrowthEvidenceTimelineVisibility: String, Codable, Equatable {
    case `private`
    case guardian
    case family
    case selectedRelatives = "selected_relatives"
    case `public`

    var label: String {
        switch self {
        case .private: return "仅本人"
        case .guardian: return "家长可见"
        case .family: return "家庭可见"
        case .selectedRelatives: return "指定亲友可见"
        case .public: return "公开可见"
        }
    }
}

/// 亲友鼓励的家长复核状态（与 B30 `GrowthEvidenceAppealTimelineGuardianReview` 对齐）。
enum GrowthEvidenceTimelineGuardianReview: String, Codable, Equatable {
    case pending
    case approved
    case rejected
}

// MARK: - 节点状态 / 发现项

/// 单个证据节点经引擎裁决后的链状态（与 B30 `GrowthEvidenceAppealTimelineNodeStatus` 对齐）。
enum GrowthEvidenceTimelineNodeStatus: String, Codable, Equatable, CaseIterable {
    /// 已接受：只读审计投影，链校验通过。
    case accepted
    /// 待复核：亲友鼓励待家长复核等，需成人关注。
    case reviewRequired = "review_required"
    /// 已阻断：缺 hash / 不安全负载 / 角色越权 / prevHash 不匹配 / 跨孩子 / 重复证明等。
    case blocked
    /// 冲突：老师与家长结论不一致，停留成人复核。
    case conflict
    /// 已冻结：成长积分建议或申诉发起期间冻结。
    case frozen
    /// 已释放：老师 / 家长结论一致，可作为后续账本中立结算建议。
    case released
    /// 已恢复：申诉恢复。
    case restored
    /// 已驳回：申诉驳回，成长积分保持阻断。
    case rejected
    /// 已撤销：撤销投影，下游全部收回。
    case revoked
    /// 重复：相同幂等键，按重放处理。
    case duplicate

    var label: String {
        switch self {
        case .accepted: return "已记录"
        case .reviewRequired: return "待复核"
        case .blocked: return "已阻断"
        case .conflict: return "冲突待裁"
        case .frozen: return "已冻结"
        case .released: return "可释放"
        case .restored: return "已恢复"
        case .rejected: return "已驳回"
        case .revoked: return "已撤销"
        case .duplicate: return "重复忽略"
        }
    }
}

/// 发现项编码（与 B30 `GrowthEvidenceAppealTimelineFindingCode` 对齐）。
enum GrowthEvidenceTimelineFindingCode: String, Codable, Equatable {
    case chainOk = "CHAIN_OK"
    case missingHash = "MISSING_HASH"
    case prevHashMismatch = "PREV_HASH_MISMATCH"
    case duplicateProof = "DUPLICATE_PROOF"
    case crossChildProofReuse = "CROSS_CHILD_PROOF_REUSE"
    case teacherGuardianConflict = "TEACHER_GUARDIAN_CONFLICT"
    case relativeReviewRequired = "RELATIVE_REVIEW_REQUIRED"
    case relativePermissionBlocked = "RELATIVE_PERMISSION_BLOCKED"
    case roleBoundaryViolation = "ROLE_BOUNDARY_VIOLATION"
    case creditFreezeRequired = "CREDIT_FREEZE_REQUIRED"
    case creditReleaseAllowed = "CREDIT_RELEASE_ALLOWED"
    case appealRestored = "APPEAL_RESTORED"
    case appealRejected = "APPEAL_REJECTED"
    case revocationNotPropagated = "REVOCATION_NOT_PROPAGATED"
    case unsafePayload = "UNSAFE_PAYLOAD"
    case duplicateIdempotency = "DUPLICATE_IDEMPOTENCY"
    case publicSummaryLeak = "PUBLIC_SUMMARY_LEAK"

    var severity: GrowthEvidenceTimelineSeverity {
        switch self {
        case .chainOk, .creditReleaseAllowed, .appealRestored:
            return .info
        case .relativeReviewRequired, .creditFreezeRequired, .appealRejected, .duplicateIdempotency:
            return .warning
        default:
            return .blocker
        }
    }

    var label: String {
        switch self {
        case .chainOk: return "链一致"
        case .missingHash: return "缺哈希"
        case .prevHashMismatch: return "prevHash 不匹配"
        case .duplicateProof: return "重复证明"
        case .crossChildProofReuse: return "跨孩子复用证明"
        case .teacherGuardianConflict: return "老师家长结论冲突"
        case .relativeReviewRequired: return "亲友待家长复核"
        case .relativePermissionBlocked: return "亲友越权阻断"
        case .roleBoundaryViolation: return "角色越权阻断"
        case .creditFreezeRequired: return "成长积分需冻结"
        case .creditReleaseAllowed: return "成长积分可释放"
        case .appealRestored: return "申诉已恢复"
        case .appealRejected: return "申诉已驳回"
        case .revocationNotPropagated: return "撤销未传播"
        case .unsafePayload: return "不安全负载"
        case .duplicateIdempotency: return "重复幂等键"
        case .publicSummaryLeak: return "公开摘要泄露"
        }
    }
}

enum GrowthEvidenceTimelineSeverity: String, Codable, Equatable {
    case info
    case warning
    case blocker
}

/// 一条脱敏发现项。
struct GrowthEvidenceTimelineFinding: Identifiable, Equatable {
    var code: GrowthEvidenceTimelineFindingCode
    var severity: GrowthEvidenceTimelineSeverity
    var message: String
    var publicRef: String

    var id: String { "\(code.rawValue):\(publicRef)" }
}

// MARK: - 撤销传播（B30 GrowthEvidenceAppealTimelineRevocation）

/// 撤销时必须传播到的全部下游面：缺任意一面即视为「撤销未传播」并要求行动。
struct GrowthEvidenceTimelineRevocation: Equatable {
    var timelineHidden: Bool
    var creditBlocked: Bool
    var feedWithdrawn: Bool
    var homeworkMarkedRevoked: Bool
    var relativeVisibilityRevoked: Bool

    /// 全部下游面都已收回才算传播完成。
    var isFullyPropagated: Bool {
        timelineHidden && creditBlocked && feedWithdrawn && homeworkMarkedRevoked && relativeVisibilityRevoked
    }
}

// MARK: - 事件输入（脱敏草稿）

/// 一条证据时间线事件的脱敏输入。所有 `*Seed` 都是脱敏引用或本地哈希源，绝不是真实内部 ID，
/// 且永不原样出现在输出里（输出再哈希一次）。
struct GrowthEvidenceTimelineEventInput: Equatable {
    var eventSeed: String
    var kind: GrowthEvidenceTimelineEventKind
    var occurredAt: String
    var familySeed: String
    var childSeed: String
    var actorRole: GrowthEvidenceTimelineActorRole
    var actorSeed: String
    var proofSeed: String?
    var appealSeed: String?
    var creditSuggestionSeed: String?
    var hash: String?
    var prevHash: String?
    var decision: GrowthEvidenceTimelineDecision?
    var teacherConclusion: GrowthEvidenceTimelineDecision?
    var guardianConclusion: GrowthEvidenceTimelineDecision?
    var guardianReview: GrowthEvidenceTimelineGuardianReview?
    var visibility: GrowthEvidenceTimelineVisibility?
    var creditAmount: Int
    var idempotencyKey: String?
    var revocation: GrowthEvidenceTimelineRevocation?
    /// 脱敏展示标题（不含真实身份）。
    var title: String
    /// 脱敏自检探针：会被脱敏守卫扫描，命中即阻断。
    var redactionProbe: [String]

    init(
        eventSeed: String,
        kind: GrowthEvidenceTimelineEventKind,
        occurredAt: String,
        familySeed: String,
        childSeed: String,
        actorRole: GrowthEvidenceTimelineActorRole,
        actorSeed: String,
        title: String,
        proofSeed: String? = nil,
        appealSeed: String? = nil,
        creditSuggestionSeed: String? = nil,
        hash: String? = "h",
        prevHash: String? = nil,
        decision: GrowthEvidenceTimelineDecision? = nil,
        teacherConclusion: GrowthEvidenceTimelineDecision? = nil,
        guardianConclusion: GrowthEvidenceTimelineDecision? = nil,
        guardianReview: GrowthEvidenceTimelineGuardianReview? = nil,
        visibility: GrowthEvidenceTimelineVisibility? = nil,
        creditAmount: Int = 0,
        idempotencyKey: String? = nil,
        revocation: GrowthEvidenceTimelineRevocation? = nil,
        redactionProbe: [String] = []
    ) {
        self.eventSeed = eventSeed
        self.kind = kind
        self.occurredAt = occurredAt
        self.familySeed = familySeed
        self.childSeed = childSeed
        self.actorRole = actorRole
        self.actorSeed = actorSeed
        self.title = title
        self.proofSeed = proofSeed
        self.appealSeed = appealSeed
        self.creditSuggestionSeed = creditSuggestionSeed
        self.hash = hash
        self.prevHash = prevHash
        self.decision = decision
        self.teacherConclusion = teacherConclusion
        self.guardianConclusion = guardianConclusion
        self.guardianReview = guardianReview
        self.visibility = visibility
        self.creditAmount = creditAmount
        self.idempotencyKey = idempotencyKey
        self.revocation = revocation
        self.redactionProbe = redactionProbe
    }
}

/// 一个证据案件的脱敏输入：单个孩子的一条证据链。
struct GrowthEvidenceTimelineCaseInput: Equatable {
    var familySeed: String
    var childSeed: String
    var caseSeed: String
    /// 历史证明引用（用于检测重复 / 跨孩子复用）。
    var existingProofSeeds: [String]
    /// 历史幂等键（用于检测重放）。
    var existingIdempotencyKeys: [String]
    var events: [GrowthEvidenceTimelineEventInput]

    init(
        familySeed: String,
        childSeed: String,
        caseSeed: String,
        existingProofSeeds: [String] = [],
        existingIdempotencyKeys: [String] = [],
        events: [GrowthEvidenceTimelineEventInput]
    ) {
        self.familySeed = familySeed
        self.childSeed = childSeed
        self.caseSeed = caseSeed
        self.existingProofSeeds = existingProofSeeds
        self.existingIdempotencyKeys = existingIdempotencyKeys
        self.events = events
    }
}

// MARK: - 节点投影（脱敏输出）

/// 一个证据时间线节点的脱敏投影，专供 UI 展示。账本中立——护栏标记恒为 false。
struct GrowthEvidenceTimelineNode: Identifiable, Equatable {
    var publicEventRef: String
    var prevPublicEventRef: String?
    var sequence: Int
    var kind: GrowthEvidenceTimelineEventKind
    var actorRole: GrowthEvidenceTimelineActorRole
    var occurredAt: String
    var status: GrowthEvidenceTimelineNodeStatus
    var childPublicRef: String
    var proofPublicRef: String?
    var appealPublicRef: String?
    var title: String
    var hashPresent: Bool
    var actionRequired: Bool
    var hiddenFromPublic: Bool
    var reason: String
    var nextStep: String

    // 护栏：恒为 false，编译期表明这是只读投影而非真实写入。
    let writesLedger = false
    let modifiesHomework = false
    let publishesTimeline = false
    let notifiesRelatives = false
    let storesRawMedia = false
    let unlocksDevice = false

    var id: String { publicEventRef }

    var kindLabel: String { kind.label }
    var actorLabel: String { actorRole.label }
    var statusLabel: String { status.label }
    var systemImage: String { kind.systemImage }

    static func == (lhs: GrowthEvidenceTimelineNode, rhs: GrowthEvidenceTimelineNode) -> Bool {
        lhs.publicEventRef == rhs.publicEventRef
            && lhs.prevPublicEventRef == rhs.prevPublicEventRef
            && lhs.sequence == rhs.sequence
            && lhs.kind == rhs.kind
            && lhs.actorRole == rhs.actorRole
            && lhs.occurredAt == rhs.occurredAt
            && lhs.status == rhs.status
            && lhs.childPublicRef == rhs.childPublicRef
            && lhs.proofPublicRef == rhs.proofPublicRef
            && lhs.appealPublicRef == rhs.appealPublicRef
            && lhs.title == rhs.title
            && lhs.hashPresent == rhs.hashPresent
            && lhs.actionRequired == rhs.actionRequired
            && lhs.hiddenFromPublic == rhs.hiddenFromPublic
            && lhs.reason == rhs.reason
            && lhs.nextStep == rhs.nextStep
    }
}

/// 公开成长时间线条目（脱敏、带可见性）。
struct GrowthEvidenceTimelinePublicItem: Identifiable, Equatable {
    var publicItemRef: String
    var sourceEventPublicRef: String
    var sequence: Int
    var kind: GrowthEvidenceTimelineEventKind
    var occurredAt: String
    var status: GrowthEvidenceTimelineNodeStatus
    var summary: String
    var visibility: GrowthEvidenceTimelineVisibility

    var id: String { publicItemRef }
    var kindLabel: String { kind.label }
    var visibilityLabel: String { visibility.label }
}

/// 成长积分控制投影（冻结 / 释放 / 阻断）。账本中立。
struct GrowthEvidenceTimelineCreditControl: Identifiable, Equatable {
    enum State: String, Equatable {
        case frozen
        case released
        case blocked

        var label: String {
            switch self {
            case .frozen: return "已冻结"
            case .released: return "可释放"
            case .blocked: return "已阻断"
            }
        }
    }

    var publicCreditRef: String
    var sourceEventPublicRef: String
    var state: State
    var amount: Int
    var reason: String

    let writesLedger = false
    let unlocksDevice = false

    var id: String { publicCreditRef }
    var stateLabel: String { state.label }
}

/// 申诉裁决投影（open / restored / rejected）。
struct GrowthEvidenceTimelineAppealDecision: Identifiable, Equatable {
    enum State: String, Equatable {
        case open
        case restored
        case rejected

        var label: String {
            switch self {
            case .open: return "申诉中"
            case .restored: return "已恢复"
            case .rejected: return "已驳回"
            }
        }
    }

    var publicAppealRef: String
    var sourceEventPublicRef: String
    var state: State
    var creditState: GrowthEvidenceTimelineCreditControl.State
    var actionRequired: Bool

    let modifiesHomework = false
    let writesLedger = false

    var id: String { publicAppealRef }
    var stateLabel: String { state.label }
}

// MARK: - 公开摘要（脱敏聚合）

/// 证据时间线报告的脱敏公开摘要：只暴露计数与发现项编码。
struct GrowthEvidenceTimelinePublicSummary: Equatable {
    var generatedAt: String
    var publicCaseRef: String
    var childPublicRef: String
    var eventCount: Int
    var publicTimelineCount: Int
    var appealCount: Int
    var creditFrozenCount: Int
    var creditReleasedCount: Int
    var creditBlockedCount: Int
    var findingCodes: [GrowthEvidenceTimelineFindingCode]

    let writesLedger = false
    let modifiesHomework = false
    let publishesTimeline = false
    let notifiesRelatives = false
    let storesRawMedia = false
    let unlocksDevice = false
}

// MARK: - 证据时间线报告

/// 一次证据链申诉时间线投影的聚合报告。
struct GrowthEvidenceTimelineReport: Equatable {
    var generatedAt: String
    var caseTitle: String
    var caseSummary: String
    var nodes: [GrowthEvidenceTimelineNode]
    var publicTimeline: [GrowthEvidenceTimelinePublicItem]
    var creditControls: [GrowthEvidenceTimelineCreditControl]
    var appealDecisions: [GrowthEvidenceTimelineAppealDecision]
    var findings: [GrowthEvidenceTimelineFinding]
    var publicSummary: GrowthEvidenceTimelinePublicSummary

    var isEmpty: Bool { nodes.isEmpty }

    /// 是否有需要成人关注的节点（待复核 / 冲突 / 阻断 / 撤销未传播 / 申诉中）。
    var hasAttention: Bool {
        nodes.contains { node in
            node.status == .reviewRequired || node.status == .conflict
                || node.status == .blocked || node.actionRequired
        }
    }

    // MARK: 孩子端

    /// 孩子端：自己的证明链节点（链上全部事件，按序）。孩子只看脱敏链状态与下一步，不看裁决细节。
    var childChainNodes: [GrowthEvidenceTimelineNode] {
        nodes.sorted { $0.sequence < $1.sequence }
    }

    /// 孩子端一句话总览（脱敏）。
    var childHeadline: String {
        if nodes.isEmpty { return "暂无成长证据节点" }
        var parts: [String] = []
        let accepted = nodes.filter { $0.status == .accepted || $0.status == .released || $0.status == .restored }.count
        if accepted > 0 { parts.append("\(accepted) 条已记录") }
        let pending = nodes.filter { $0.status == .reviewRequired }.count
        if pending > 0 { parts.append("\(pending) 条待复核") }
        let frozen = nodes.filter { $0.status == .frozen }.count
        if frozen > 0 { parts.append("\(frozen) 条成长积分冻结中") }
        let blocked = nodes.filter { $0.status == .blocked || $0.status == .conflict }.count
        if blocked > 0 { parts.append("\(blocked) 条待处理") }
        return parts.isEmpty ? "成长证据链进行中" : parts.joined(separator: " · ")
    }

    // MARK: 家长端分组

    /// 老师 / 家长结论冲突节点。
    var conflictNodes: [GrowthEvidenceTimelineNode] {
        nodes.filter { $0.status == .conflict }
    }

    /// 申诉相关节点（发起 / 裁决）。
    var appealNodes: [GrowthEvidenceTimelineNode] {
        nodes.filter { $0.kind == .appealOpened || $0.kind == .appealResolved }
    }

    /// 撤销节点（含撤销未传播待处理）。
    var revocationNodes: [GrowthEvidenceTimelineNode] {
        nodes.filter { $0.kind == .revoked }
    }

    /// 亲友鼓励待家长复核节点。
    var relativePendingNodes: [GrowthEvidenceTimelineNode] {
        nodes.filter { $0.kind == .relativeEncouraged && $0.status == .reviewRequired }
    }

    /// 角色越权 / 阻断（含亲友越权）节点。
    var blockedNodes: [GrowthEvidenceTimelineNode] {
        nodes.filter { $0.status == .blocked }
    }

    /// 家长端一句话总览（脱敏）。
    var parentHeadline: String {
        if nodes.isEmpty { return "暂无成长证据节点" }
        var parts: [String] = []
        let conflicts = conflictNodes.count
        if conflicts > 0 { parts.append("\(conflicts) 条冲突待裁") }
        let openAppeals = appealDecisions.filter { $0.state == .open }.count
        if openAppeals > 0 { parts.append("\(openAppeals) 条申诉中") }
        let revokeAttention = revocationNodes.filter { $0.actionRequired }.count
        if revokeAttention > 0 { parts.append("\(revokeAttention) 条撤销待传播") }
        let relativePending = relativePendingNodes.count
        if relativePending > 0 { parts.append("\(relativePending) 条亲友待复核") }
        let blocked = blockedNodes.count
        if blocked > 0 { parts.append("\(blocked) 条已阻断") }
        return parts.isEmpty ? "暂无待处理项" : parts.joined(separator: " · ")
    }

    static let empty = GrowthEvidenceTimelineReport(
        generatedAt: "",
        caseTitle: "",
        caseSummary: "",
        nodes: [],
        publicTimeline: [],
        creditControls: [],
        appealDecisions: [],
        findings: [],
        publicSummary: GrowthEvidenceTimelinePublicSummary(
            generatedAt: "",
            publicCaseRef: "",
            childPublicRef: "",
            eventCount: 0,
            publicTimelineCount: 0,
            appealCount: 0,
            creditFrozenCount: 0,
            creditReleasedCount: 0,
            creditBlockedCount: 0,
            findingCodes: []
        )
    )
}
