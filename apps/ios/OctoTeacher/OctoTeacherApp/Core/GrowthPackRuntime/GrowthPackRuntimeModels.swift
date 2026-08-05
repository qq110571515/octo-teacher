import Foundation

/// iOS 本地「成长包运行详情与结算预览」模型层。
///
/// 承接平台共享契约 B29（growth-pack-runtime-settlement-contract / 成长包运行结算契约）的
/// view 语义，把一份成长包运行计划里的每个步骤（基础习惯、学校作业、测验、媒体学习、
/// 运动外部证明、创作上传、综合成长包）的 `planned/submitted/verified/credited/appealed/voided`
/// 状态、证明要求、下一步与**脱敏结算预览**，投影成只读、账本中立（ledger-neutral）的
/// 「运行详情 + 结算建议」，供孩子端看进度、家长端看待审核/可建议/已阻断/申诉中摘要。
///
/// 关键安全边界（与 CLAUDE.md、B29 一致）：
///
/// - **绝不真实发成长积分 / 授徽章 / 改能力卡 / 发布荣誉墙 / 改任务终态 / 写作业终态 / 解锁设备 / 发通知**。
///   每条投影与结算预览都携带恒为 `false` 的护栏标记，从结构上保证它只是「可审核的建议」。
/// - **`credit_suggested`（可建议）不是发成长积分**：只表示这条步骤在脱敏、证明齐备、幂等、账户匹配、
///   通过验证后可交家长流程审核；最终是否落定由真实账本决定。
/// - **未审核证明 / 失败测验 / 老师退回 / 申诉中 / 年龄不适配 / 内容被拒 / 离线回滚 / 重复幂等**
///   一律不得展示为已完成可用成长积分：分别投影为 `review_required` / `blocked` / `voided`，绝不 `credit_suggested`。
/// - **只读脱敏**：输出只含哈希引用（`prefix:token`）、类型/状态标签与脱敏文案，绝不暴露真实
///   child/family/pack/content/homework/proof/ledger/media/device/ref、token、路径、局域网地址、
///   taskId、claimId 或完整内部 ID。

// MARK: - 运行阶段 / 活动类型

/// 成长包运行步骤的状态机阶段（与 B29 `GrowthRuntimeSettlementStage` 对齐）。
enum GrowthRuntimeStage: String, Codable, Equatable, CaseIterable {
    /// 已排期：尚未提交，不能结算。
    case planned
    /// 已提交：等待验证。
    case submitted
    /// 已验证：证明通过，可进入结算建议。
    case verified
    /// 已结算：成长积分建议已在过去落定，不再重复建议。
    case credited
    /// 申诉中：结论被申诉，必须停留复核，不能结算。
    case appealed
    /// 已作废：终态，不能产生结算。
    case voided

    var label: String {
        switch self {
        case .planned: return "已排期"
        case .submitted: return "已提交待验证"
        case .verified: return "已验证"
        case .credited: return "已结算"
        case .appealed: return "申诉中"
        case .voided: return "已作废"
        }
    }
}

/// 成长包步骤的活动类型（与 B29 `GrowthRuntimeActivityKind` 对齐）。
enum GrowthRuntimeActivityKind: String, Codable, Equatable, CaseIterable {
    case basicHabit = "basic_habit"
    case schoolHomework = "school_homework"
    case quiz
    case mediaLearning = "media_learning"
    case exerciseExternalProof = "exercise_external_proof"
    case creativeUpload = "creative_upload"
    case compositeGrowthPack = "composite_growth_pack"

    var label: String {
        switch self {
        case .basicHabit: return "基础习惯"
        case .schoolHomework: return "学校作业"
        case .quiz: return "测验"
        case .mediaLearning: return "媒体学习"
        case .exerciseExternalProof: return "运动外部证明"
        case .creativeUpload: return "创作上传"
        case .compositeGrowthPack: return "综合成长包"
        }
    }

    var systemImage: String {
        switch self {
        case .basicHabit: return "checklist"
        case .schoolHomework: return "book.closed"
        case .quiz: return "questionmark.circle"
        case .mediaLearning: return "play.rectangle"
        case .exerciseExternalProof: return "figure.run"
        case .creativeUpload: return "paintbrush.pointed"
        case .compositeGrowthPack: return "shippingbox"
        }
    }
}

/// 验证结论（与 B29 `GrowthRuntimeVerificationOutcome` 对齐）。
enum GrowthRuntimeVerificationOutcome: String, Codable, Equatable {
    case pending
    case approved
    case rejected
    case returned
    case appealed
}

/// 证明状态（与 B29 `GrowthRuntimeProofStatus` 对齐）。
enum GrowthRuntimeProofStatus: String, Codable, Equatable {
    case missing
    case submitted
    case pendingReview = "pending_review"
    case approved
    case rejected

    var label: String {
        switch self {
        case .missing: return "缺证明"
        case .submitted: return "已交证明"
        case .pendingReview: return "证明待复核"
        case .approved: return "证明已通过"
        case .rejected: return "证明被拒"
        }
    }
}

/// 内容审核状态（与 B29 `GrowthRuntimeContentReviewStatus` 对齐）。
enum GrowthRuntimeContentReviewStatus: String, Codable, Equatable {
    case notRequired = "not_required"
    case pending
    case approved
    case rejected
}

// MARK: - 投影状态 / 发现项

/// 一个步骤经引擎裁决后的结算投影状态（与 B29 `GrowthRuntimeSettlementProjectionStatus` 对齐）。
enum GrowthRuntimeProjectionStatus: String, Codable, Equatable, CaseIterable {
    /// 已排期：未提交，不结算。
    case planned
    /// 待复核：已提交/待验证/内容待审/申诉中，需成人复核，绝不发成长积分。
    case reviewRequired = "review_required"
    /// 可建议：通过验证、证明齐备、幂等，可交家长审核后再决定是否发放成长积分。
    case creditSuggested = "credit_suggested"
    /// 重复：相同幂等键，按重放处理，不再生成新结算。
    case duplicate
    /// 已结算：过去已发放，不重复建议。
    case alreadyCredited = "already_credited"
    /// 已作废：终态。
    case voided
    /// 已阻断：缺证明/证明被拒/失败测验/老师退回/年龄不适配/内容被拒/账户不匹配/不安全负载。
    case blocked

    var label: String {
        switch self {
        case .planned: return "待开始"
        case .reviewRequired: return "待复核"
        case .creditSuggested: return "可建议结算"
        case .duplicate: return "重复忽略"
        case .alreadyCredited: return "已结算"
        case .voided: return "已作废"
        case .blocked: return "已阻断"
        }
    }
}

/// 结算发现项编码（与 B29 `GrowthRuntimeSettlementFindingCode` 对齐，按 iOS 本地裁剪）。
enum GrowthRuntimeFindingCode: String, Codable, Equatable {
    case unknownRuntimeTask = "unknown_runtime_task"
    case crossChildFamilyMismatch = "cross_child_family_mismatch"
    case unsafePayload = "unsafe_payload"
    case missingProof = "missing_proof"
    case proofRejected = "proof_rejected"
    case verificationPending = "verification_pending"
    case verificationRejected = "verification_rejected"
    case teacherReturned = "teacher_returned"
    case appealOpen = "appeal_open"
    case duplicateIdempotency = "duplicate_idempotency"
    case failedQuiz = "failed_quiz"
    case ageInappropriate = "age_inappropriate"
    case contentReviewRequired = "content_review_required"
    case contentRejected = "content_rejected"
    case alreadyCredited = "already_credited"
    case voidedTask = "voided_task"
    case publicSummaryLeak = "public_summary_leak"

    var severity: GrowthRuntimeSeverity {
        switch self {
        case .verificationPending, .appealOpen, .duplicateIdempotency, .contentReviewRequired:
            return .warning
        case .alreadyCredited, .voidedTask:
            return .info
        default:
            return .blocker
        }
    }
}

enum GrowthRuntimeSeverity: String, Codable, Equatable {
    case info
    case warning
    case blocker
}

/// 一条脱敏发现项。
struct GrowthRuntimeFinding: Identifiable, Equatable {
    var code: GrowthRuntimeFindingCode
    var severity: GrowthRuntimeSeverity
    var message: String
    var publicRef: String

    var id: String { "\(code.rawValue):\(publicRef)" }
}

// MARK: - 步骤输入（来自运行计划的脱敏草稿）

/// 一个成长包运行步骤的脱敏输入草稿。调用方（assembler）只填脱敏 seed 与摘要；
/// 引擎据此裁决投影状态并分配脱敏 publicRef。所有 `*Seed` 都是脱敏引用或本地哈希源，
/// 绝不是真实内部 ID，且永不原样出现在输出里（输出再哈希一次）。
struct GrowthRuntimeStepInput: Equatable {
    var stepSeed: String
    var packSeed: String
    var childSeed: String
    var familySeed: String
    var title: String
    var order: Int
    var kind: GrowthRuntimeActivityKind
    var stage: GrowthRuntimeStage
    /// 该步骤要求的证明份数（0 表示无内在证明记录，引擎按缺证明阻断已验证步骤）。
    var requiredProofCount: Int
    /// 已交的脱敏证明引用数量。
    var submittedProofCount: Int
    var proofStatus: GrowthRuntimeProofStatus
    var verificationOutcome: GrowthRuntimeVerificationOutcome
    /// 建议结算的脱敏「建议积分」（仅展示，恒为正才可建议）。
    var suggestedCredit: Int
    /// 使用范围脱敏标签。
    var scopeLabel: String
    var idempotencyKey: String
    // 各类阻断/复核信号（默认安全：不触发任何阻断）。
    var quizPassed: Bool?
    var teacherReview: GrowthRuntimeVerificationOutcome?
    var moderationStatus: GrowthRuntimeContentReviewStatus
    var ageAppropriate: Bool
    var appealOpen: Bool
    var duplicate: Bool
    /// 该步骤是否属于已接受的运行计划（不属于则阻断）。
    var partOfAcceptedPlan: Bool
    /// 脱敏自检探针：会被脱敏守卫扫描，命中即阻断。
    var redactionProbe: [String]

    init(
        stepSeed: String,
        packSeed: String,
        childSeed: String,
        familySeed: String,
        title: String,
        order: Int,
        kind: GrowthRuntimeActivityKind,
        stage: GrowthRuntimeStage,
        requiredProofCount: Int = 1,
        submittedProofCount: Int = 1,
        proofStatus: GrowthRuntimeProofStatus = .approved,
        verificationOutcome: GrowthRuntimeVerificationOutcome = .approved,
        suggestedCredit: Int = 10,
        scopeLabel: String = "需家长批准",
        idempotencyKey: String,
        quizPassed: Bool? = nil,
        teacherReview: GrowthRuntimeVerificationOutcome? = nil,
        moderationStatus: GrowthRuntimeContentReviewStatus = .notRequired,
        ageAppropriate: Bool = true,
        appealOpen: Bool = false,
        duplicate: Bool = false,
        partOfAcceptedPlan: Bool = true,
        redactionProbe: [String] = []
    ) {
        self.stepSeed = stepSeed
        self.packSeed = packSeed
        self.childSeed = childSeed
        self.familySeed = familySeed
        self.title = title
        self.order = order
        self.kind = kind
        self.stage = stage
        self.requiredProofCount = requiredProofCount
        self.submittedProofCount = submittedProofCount
        self.proofStatus = proofStatus
        self.verificationOutcome = verificationOutcome
        self.suggestedCredit = suggestedCredit
        self.scopeLabel = scopeLabel
        self.idempotencyKey = idempotencyKey
        self.quizPassed = quizPassed
        self.teacherReview = teacherReview
        self.moderationStatus = moderationStatus
        self.ageAppropriate = ageAppropriate
        self.appealOpen = appealOpen
        self.duplicate = duplicate
        self.partOfAcceptedPlan = partOfAcceptedPlan
        self.redactionProbe = redactionProbe
    }
}

/// 账户上下文：每个步骤必须匹配的孩子/家庭脱敏 seed。不匹配即阻断。
struct GrowthRuntimeAccount: Equatable {
    var childSeed: String
    var familySeed: String
}

// MARK: - 结算预览（脱敏输出）

/// 一个步骤的脱敏结算预览。账本中立——护栏标记恒为 false。
struct GrowthRuntimeSettlementPreview: Equatable {
    /// 仅在 `credit_suggested` 时为正；其他状态恒为 0。
    var suggestedCredit: Int
    var scopeLabel: String
    /// 脱敏徽章建议数（不授徽章）。
    var badgeSuggestionCount: Int
    /// 脱敏能力贡献建议数（不改能力卡）。
    var abilitySuggestionCount: Int

    let writesLedger = false
    let grantsBadge = false
    let updatesAbilityCard = false
    let publishesHonorWall = false

    var suggestedCreditLabel: String { "\(suggestedCredit) 成长积分" }

    static let none = GrowthRuntimeSettlementPreview(
        suggestedCredit: 0,
        scopeLabel: "暂无可建议结算",
        badgeSuggestionCount: 0,
        abilitySuggestionCount: 0
    )
}

// MARK: - 步骤投影（脱敏输出）

/// 一个成长包运行步骤的脱敏投影，专供 UI 展示。
struct GrowthRuntimeStepProjection: Identifiable, Equatable {
    var publicStepRef: String
    var publicPackRef: String
    var childPublicRef: String
    var title: String
    var order: Int
    var kind: GrowthRuntimeActivityKind
    var fromStage: GrowthRuntimeStage
    var suggestedNextStage: GrowthRuntimeStage
    var status: GrowthRuntimeProjectionStatus
    var proofStatus: GrowthRuntimeProofStatus
    var proofRequirementLabel: String
    var reason: String
    var nextStep: String
    var actionRequired: Bool
    var retryable: Bool
    /// 是否处于申诉态（供家长端「申诉中」分组）。
    var isAppealing: Bool
    var settlement: GrowthRuntimeSettlementPreview

    // 护栏：恒为 false，编译期表明这是建议而非落定。
    let writesLedger = false
    let grantsBadge = false
    let updatesAbilityCard = false
    let modifiesTaskState = false
    let publishesHonorWall = false

    var id: String { publicStepRef }

    var kindLabel: String { kind.label }
    var stageLabel: String { fromStage.label }
    var statusLabel: String { status.label }
    var systemImage: String { kind.systemImage }

    var parentGroup: GrowthRuntimeParentGroup? {
        GrowthRuntimeParentGroup.from(status: status, isAppealing: isAppealing)
    }

    static func == (lhs: GrowthRuntimeStepProjection, rhs: GrowthRuntimeStepProjection) -> Bool {
        lhs.publicStepRef == rhs.publicStepRef
            && lhs.publicPackRef == rhs.publicPackRef
            && lhs.childPublicRef == rhs.childPublicRef
            && lhs.title == rhs.title
            && lhs.order == rhs.order
            && lhs.kind == rhs.kind
            && lhs.fromStage == rhs.fromStage
            && lhs.suggestedNextStage == rhs.suggestedNextStage
            && lhs.status == rhs.status
            && lhs.proofStatus == rhs.proofStatus
            && lhs.proofRequirementLabel == rhs.proofRequirementLabel
            && lhs.reason == rhs.reason
            && lhs.nextStep == rhs.nextStep
            && lhs.actionRequired == rhs.actionRequired
            && lhs.retryable == rhs.retryable
            && lhs.isAppealing == rhs.isAppealing
            && lhs.settlement == rhs.settlement
    }
}

// MARK: - 家长端展示分组

/// 家长端摘要分组：把投影状态归并成「待审核 / 可建议 / 已阻断 / 申诉中」四类。
/// 纯展示归类，不改变投影语义。
enum GrowthRuntimeParentGroup: String, Equatable, CaseIterable {
    case reviewRequired
    case proposable
    case blocked
    case appealing

    var label: String {
        switch self {
        case .reviewRequired: return "待审核"
        case .proposable: return "可建议"
        case .blocked: return "已阻断"
        case .appealing: return "申诉中"
        }
    }

    var systemImage: String {
        switch self {
        case .reviewRequired: return "person.crop.circle.badge.clock"
        case .proposable: return "lightbulb"
        case .blocked: return "nosign"
        case .appealing: return "exclamationmark.bubble"
        }
    }

    /// 仅这四类计入家长摘要；其余（待开始/重复/已结算/已作废）返回 nil。
    static func from(status: GrowthRuntimeProjectionStatus, isAppealing: Bool) -> GrowthRuntimeParentGroup? {
        if isAppealing { return .appealing }
        switch status {
        case .reviewRequired: return .reviewRequired
        case .creditSuggested: return .proposable
        case .blocked: return .blocked
        case .planned, .duplicate, .alreadyCredited, .voided: return nil
        }
    }
}

// MARK: - 公开摘要（脱敏聚合）

/// 运行结算报告的脱敏公开摘要：只暴露计数与发现项编码。
struct GrowthRuntimePublicSummary: Equatable {
    var generatedAt: String
    var packPublicRef: String
    var childPublicRef: String
    var stepCount: Int
    var plannedCount: Int
    var reviewRequiredCount: Int
    var creditSuggestedCount: Int
    var appealingCount: Int
    var blockedCount: Int
    var duplicateCount: Int
    var alreadyCreditedCount: Int
    var voidedCount: Int
    var totalSuggestedCredit: Int
    var badgeSuggestionCount: Int
    var abilitySuggestionCount: Int
    var findingCodes: [GrowthRuntimeFindingCode]

    let writesLedger = false
    let grantsBadge = false
    let updatesAbilityCard = false
    let modifiesTaskState = false
    let publishesHonorWall = false
}

// MARK: - 运行结算报告

/// 一次成长包运行结算投影的聚合报告。
struct GrowthRuntimeSettlementReport: Equatable {
    var generatedAt: String
    var packTitle: String
    var packSummary: String
    var steps: [GrowthRuntimeStepProjection]
    var findings: [GrowthRuntimeFinding]
    var publicSummary: GrowthRuntimePublicSummary

    var isEmpty: Bool { steps.isEmpty }

    /// 是否有需要成人关注的步骤（待复核 / 申诉中 / 阻断）。
    var hasAttention: Bool {
        steps.contains {
            $0.status == .reviewRequired || $0.status == .blocked || $0.isAppealing
        }
    }

    /// 按家长展示分组取步骤。
    func steps(in group: GrowthRuntimeParentGroup) -> [GrowthRuntimeStepProjection] {
        steps.filter { $0.parentGroup == group }
    }

    /// 孩子端一句话总览（脱敏）。
    var childHeadline: String {
        if steps.isEmpty { return "暂无成长包步骤" }
        var parts: [String] = []
        let credited = steps.filter { $0.status == .alreadyCredited }.count
        if credited > 0 { parts.append("\(credited) 步已结算") }
        let suggested = steps.filter { $0.status == .creditSuggested }.count
        if suggested > 0 { parts.append("\(suggested) 步可建议结算") }
        let review = steps.filter { $0.status == .reviewRequired }.count
        if review > 0 { parts.append("\(review) 步待复核") }
        let planned = steps.filter { $0.status == .planned }.count
        if planned > 0 { parts.append("\(planned) 步待开始") }
        return parts.isEmpty ? "成长包进行中" : parts.joined(separator: " · ")
    }

    /// 家长端一句话总览（脱敏）。
    var parentHeadline: String {
        if steps.isEmpty { return "暂无成长包步骤" }
        var parts: [String] = []
        let proposable = steps(in: .proposable).count
        if proposable > 0 { parts.append("\(proposable) 条可建议") }
        let review = steps(in: .reviewRequired).count
        if review > 0 { parts.append("\(review) 条待审核") }
        let appealing = steps(in: .appealing).count
        if appealing > 0 { parts.append("\(appealing) 条申诉中") }
        let blocked = steps(in: .blocked).count
        if blocked > 0 { parts.append("\(blocked) 条已阻断") }
        return parts.isEmpty ? "暂无待处理项" : parts.joined(separator: " · ")
    }

    static let empty = GrowthRuntimeSettlementReport(
        generatedAt: "",
        packTitle: "",
        packSummary: "",
        steps: [],
        findings: [],
        publicSummary: GrowthRuntimePublicSummary(
            generatedAt: "",
            packPublicRef: "",
            childPublicRef: "",
            stepCount: 0,
            plannedCount: 0,
            reviewRequiredCount: 0,
            creditSuggestedCount: 0,
            appealingCount: 0,
            blockedCount: 0,
            duplicateCount: 0,
            alreadyCreditedCount: 0,
            voidedCount: 0,
            totalSuggestedCredit: 0,
            badgeSuggestionCount: 0,
            abilitySuggestionCount: 0,
            findingCodes: []
        )
    )
}
