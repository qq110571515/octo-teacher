import Foundation

/// iOS 成长包徽章能力卡预览的纯本地只读投影。
///
/// 这一层把成长包执行中心、证明准备、证据时间线、家庭成就、徽章、成长球星卡、
/// 荣誉墙和故事线整理成“完成后可能沉淀成什么”的预览。它只生成展示模型，
/// 不授徽章、不更新能力卡、不发布荣誉墙、不提交证明、不上传媒体、不写账本、
/// 不发成长积分、不发通知，也不控制设备或屏幕时间。
///
/// 孩子视角只看安全的徽章候选、能力维度成长提示、还需要继续努力的下一步和温和解释；
/// 家长视角只读查看徽章/能力卡候选、证据缺口、可见性/同意/撤回/回滚边界、
/// 能力维度跳变风险和荣誉墙发布前置条件。

/// 成就候选分类。rawValue 只是安全枚举，不携带真实 badge/card/proof/ref。
enum MobileGrowthPackAchievementCardPreviewCategory: String, CaseIterable, Equatable {
    case badge = "badge_candidate"
    case abilityCard = "ability_card_candidate"
    case honorWall = "honor_wall_candidate"
    case storyline = "storyline_candidate"
    case familyAchievement = "family_achievement_record"
    case relativeShare = "relative_share_candidate"
    case guardianBoundary = "guardian_boundary"

    var title: String {
        switch self {
        case .badge: return "徽章候选"
        case .abilityCard: return "成长球星卡能力卡候选"
        case .honorWall: return "荣誉墙展示候选"
        case .storyline: return "成长故事线候选"
        case .familyAchievement: return "家庭成就记录"
        case .relativeShare: return "亲友鼓励可见候选"
        case .guardianBoundary: return "可见性 / 撤回 / 回滚边界"
        }
    }
}

/// 成就候选状态。
enum MobileGrowthPackAchievementCardPreviewStatus: String, Equatable {
    case previewReady = "preview_ready"
    case needsMoreEvidence = "needs_more_evidence"
    case waitingConsent = "waiting_consent"
    case waitingReview = "waiting_review"
    case blocked

    var label: String {
        switch self {
        case .previewReady: return "可能沉淀"
        case .needsMoreEvidence: return "还要补证据"
        case .waitingConsent: return "等同意"
        case .waitingReview: return "等审核"
        case .blocked: return "先暂停"
        }
    }
}

/// 能力维度。只用安全枚举，不暴露内部能力评分算法或权重。
enum MobileGrowthPackAchievementCardPreviewAbilityDimension: String, CaseIterable, Equatable {
    case learning = "learning"
    case expression = "expression"
    case persistence = "persistence"
    case creativity = "creativity"
    case collaboration = "collaboration"
    case physical = "physical"

    var title: String {
        switch self {
        case .learning: return "学习力"
        case .expression: return "表达力"
        case .persistence: return "坚持力"
        case .creativity: return "创造力"
        case .collaboration: return "协作力"
        case .physical: return "运动力"
        }
    }

    var sortOrder: Int {
        switch self {
        case .learning: return 10
        case .expression: return 20
        case .persistence: return 30
        case .creativity: return 40
        case .collaboration: return 50
        case .physical: return 60
        }
    }
}

enum MobileGrowthPackAchievementCardPreviewFindingCode: String, Equatable {
    case readOnlyPreview = "READ_ONLY_PREVIEW"
    case verificationRequired = "VERIFICATION_REQUIRED"
    case achievementFrozen = "ACHIEVEMENT_FROZEN"
    case appealPending = "APPEAL_PENDING"
    case accessRevoked = "ACCESS_REVOKED"
    case consentRequired = "CONSENT_REQUIRED"
    case moderationRequired = "MODERATION_REQUIRED"
    case abilityJumpRisk = "ABILITY_JUMP_RISK"
    case honorWallPrecondition = "HONOR_WALL_PRECONDITION"
    case previewOnHold = "PREVIEW_ON_HOLD"
    case unsafePayloadBlocked = "UNSAFE_PAYLOAD_BLOCKED"
}

/// 单条成就候选。所有副作用标记恒为 false。
struct MobileGrowthPackAchievementCardPreviewCandidate: Identifiable, Equatable {
    var publicPreviewRef: String
    var category: MobileGrowthPackAchievementCardPreviewCategory
    var status: MobileGrowthPackAchievementCardPreviewStatus
    var title: String
    var summary: String
    var gapReason: String
    var nextStep: String
    var safetyNote: String
    var visibleToChild: Bool
    var visibleToGuardian: Bool
    var requiresVerification: Bool
    var isFrozen: Bool
    var underAppeal: Bool
    var accessRevoked: Bool
    var requiresConsent: Bool
    var requiresModeration: Bool
    var requiresGuardianReview: Bool
    var abilityJumpRisk: Bool
    var sortOrder: Int

    let callsNetwork = false
    let callsAiProvider = false
    let callsLocalModel = false
    let callsLms = false
    let writesSchoolSystem = false
    let opensExternalLink = false
    let opensCamera = false
    let opensPhotoLibrary = false
    let opensFilePicker = false
    let uploadsMedia = false
    let writesLedger = false
    let grantsCredit = false
    let spendsCredit = false
    let fulfillsReward = false
    let grantsBadge = false
    let updatesAbilityCard = false
    let publishesHonorWall = false
    let publishesContent = false
    let unlocksDevice = false
    let controlsScreenTime = false
    let sendsNotification = false
    let submitsProof = false

    var id: String { publicPreviewRef }

    var isBlocked: Bool {
        status == .blocked || isFrozen || underAppeal || accessRevoked
    }

    var displayValues: [String] {
        [
            publicPreviewRef,
            category.rawValue,
            category.title,
            status.rawValue,
            status.label,
            title,
            summary,
            gapReason,
            nextStep,
            safetyNote
        ]
    }

    var hasTriggeredSideEffect: Bool {
        callsNetwork || callsAiProvider || callsLocalModel || callsLms || writesSchoolSystem
            || opensExternalLink || opensCamera || opensPhotoLibrary || opensFilePicker || uploadsMedia
            || writesLedger || grantsCredit || spendsCredit || fulfillsReward || grantsBadge
            || updatesAbilityCard || publishesHonorWall || publishesContent || unlocksDevice
            || controlsScreenTime || sendsNotification || submitsProof
    }
}

/// 能力维度成长提示。孩子和家长都只读，不显示内部能力评分。
struct MobileGrowthPackAchievementCardPreviewAbilityHint: Identifiable, Equatable {
    var publicPreviewRef: String
    var dimension: MobileGrowthPackAchievementCardPreviewAbilityDimension
    var growthNote: String
    var nextStep: String
    var jumpRisk: Bool
    var visibleToChild: Bool
    var visibleToGuardian: Bool

    let updatesAbilityCard = false
    let writesLedger = false
    let grantsCredit = false

    var id: String { publicPreviewRef }
    var sortOrder: Int { dimension.sortOrder }

    var displayValues: [String] {
        [publicPreviewRef, dimension.rawValue, dimension.title, growthNote, nextStep]
    }

    var hasTriggeredSideEffect: Bool {
        updatesAbilityCard || writesLedger || grantsCredit
    }
}

struct MobileGrowthPackAchievementCardPreviewFinding: Identifiable, Equatable {
    var code: MobileGrowthPackAchievementCardPreviewFindingCode
    var message: String
    var actionRequired: Bool
    var visibleToChild: Bool

    var id: String { code.rawValue }
    var displayValues: [String] { [code.rawValue, message] }
}

struct MobileGrowthPackAchievementCardPreviewPublicSummary: Equatable {
    var role: MobileGrowthPackExecutionHubRole
    var candidateCount: Int
    var visibleCandidateCount: Int
    var previewReadyCount: Int
    var blockedCount: Int
    var verificationRequiredCount: Int
    var consentRequiredCount: Int
    var moderationRequiredCount: Int
    var abilityJumpRiskCount: Int
    var abilityHintCount: Int
    var findingCodes: [MobileGrowthPackAchievementCardPreviewFindingCode]

    let callsNetwork = false
    let callsAiProvider = false
    let callsLocalModel = false
    let callsLms = false
    let writesSchoolSystem = false
    let opensExternalLink = false
    let opensCamera = false
    let opensPhotoLibrary = false
    let opensFilePicker = false
    let uploadsMedia = false
    let writesLedger = false
    let grantsCredit = false
    let spendsCredit = false
    let fulfillsReward = false
    let grantsBadge = false
    let updatesAbilityCard = false
    let publishesHonorWall = false
    let publishesContent = false
    let unlocksDevice = false
    let controlsScreenTime = false
    let sendsNotification = false
    let submitsProof = false

    var hasTriggeredSideEffect: Bool {
        callsNetwork || callsAiProvider || callsLocalModel || callsLms || writesSchoolSystem
            || opensExternalLink || opensCamera || opensPhotoLibrary || opensFilePicker || uploadsMedia
            || writesLedger || grantsCredit || spendsCredit || fulfillsReward || grantsBadge
            || updatesAbilityCard || publishesHonorWall || publishesContent || unlocksDevice
            || controlsScreenTime || sendsNotification || submitsProof
    }
}

struct MobileGrowthPackAchievementCardPreview: Equatable {
    var role: MobileGrowthPackExecutionHubRole
    var title: String
    var subtitle: String
    var audienceNote: String
    var candidates: [MobileGrowthPackAchievementCardPreviewCandidate]
    var abilityHints: [MobileGrowthPackAchievementCardPreviewAbilityHint]
    var findings: [MobileGrowthPackAchievementCardPreviewFinding]
    var publicSummary: MobileGrowthPackAchievementCardPreviewPublicSummary

    var displayValues: [String] {
        [role.rawValue, title, subtitle, audienceNote]
            + candidates.flatMap(\.displayValues)
            + abilityHints.flatMap(\.displayValues)
            + findings.flatMap(\.displayValues)
    }

    var hasUnsafeDisplayPayload: Bool {
        MobileGrowthPackAchievementCardPreviewBuilder.hasUnsafeDisplayPayload(displayValues)
    }
}

struct MobileGrowthPackAchievementCardPreviewInput: Equatable {
    var generatedAt: String
    var unsafePayload: String?

    static let mock = MobileGrowthPackAchievementCardPreviewInput(
        generatedAt: "2026-06-25T02:00:00.000Z",
        unsafePayload: nil
    )
}

struct MobileGrowthPackAchievementCardPreviewBuilder {
    private static let redactionSalt = "mobile-growth-pack-achievement-card-preview-v1"
    private static let sensitiveMarkers = [
        "child:", "family:", "school:", "teacher:", "guardian:", "relative:", "creator:",
        "proof:", "media:", "photo:", "screenshot:", "transcript", "answer key", "answerkey",
        "答案键", "provider:", "model:", "resource:", "link:", "url:", "homework:", "quiz:",
        "badge:", "card:", "ability:", "pack:", "reward:", "order:", "inventory:", "ledger:",
        "device:", "entitlement:", "publicref", "adultreason", "adult reason", "internalref",
        "internal ref", "ref:", "task:", "taskid", "claim:", "claimid", "token", "api_key",
        "apikey", "secret", "credit amount", "成长积分金额", "账本明细", "设备命令", "复核策略",
        "能力评分", "评分算法", "http://", "https://", "file://", "/users/", "/volumes/",
        "child_real", "family_real", "proof_real", "badge_real", "card_real", "192.168.", ".local"
    ]

    func build(
        role: MobileGrowthPackExecutionHubRole,
        input: MobileGrowthPackAchievementCardPreviewInput = .mock
    ) -> MobileGrowthPackAchievementCardPreview {
        if let unsafePayload = input.unsafePayload, Self.hasUnsafeDisplayPayload([unsafePayload]) {
            return blockedPreview(role: role)
        }

        let allCandidates = makeCandidates(for: role)
        let visibleCandidates = allCandidates
            .filter { role == .child ? $0.visibleToChild : $0.visibleToGuardian }
            .sorted { left, right in
                if left.sortOrder == right.sortOrder {
                    return left.publicPreviewRef < right.publicPreviewRef
                }
                return left.sortOrder < right.sortOrder
            }

        let allHints = makeAbilityHints(for: role)
        let visibleHints = allHints
            .filter { role == .child ? $0.visibleToChild : $0.visibleToGuardian }
            .sorted { left, right in
                if left.sortOrder == right.sortOrder {
                    return left.publicPreviewRef < right.publicPreviewRef
                }
                return left.sortOrder < right.sortOrder
            }

        let findings = makeFindings(role: role, candidates: visibleCandidates)

        return MobileGrowthPackAchievementCardPreview(
            role: role,
            title: role == .child ? "完成后可能沉淀成什么" : "徽章能力卡预览复核",
            subtitle: role == .child
                ? "把今天的努力会变成哪些徽章、能力和记录放在一起看；这里只读，不会真的发徽章或更新能力卡。"
                : "只读复核徽章/能力卡候选、证据缺口、可见性/同意/撤回/回滚边界、能力维度跳变风险和荣誉墙发布前置条件。",
            audienceNote: role == .child
                ? "这里只看安全的徽章候选、能力成长方向和下一步；真正授徽章、更新能力卡和公开都要等家长或老师确认。"
                : "这里只读整理“完成后可能沉淀成什么”；真正授徽章、更新能力卡、发布荣誉墙和发成长积分仍走正式流程。",
            candidates: visibleCandidates,
            abilityHints: visibleHints,
            findings: findings,
            publicSummary: summary(
                role: role,
                allCandidates: allCandidates,
                visibleCandidates: visibleCandidates,
                visibleHints: visibleHints,
                findings: findings
            )
        )
    }

    static func hasUnsafeDisplayPayload(_ values: [String]) -> Bool {
        let joined = values.joined(separator: " ").lowercased()
        return sensitiveMarkers.contains { joined.contains($0) }
    }

    private func blockedPreview(role: MobileGrowthPackExecutionHubRole) -> MobileGrowthPackAchievementCardPreview {
        let finding = MobileGrowthPackAchievementCardPreviewFinding(
            code: .unsafePayloadBlocked,
            message: "预览发现不安全字段，已隐藏徽章和能力卡候选，等待家长在正式流程复核。",
            actionRequired: true,
            visibleToChild: true
        )
        return MobileGrowthPackAchievementCardPreview(
            role: role,
            title: role == .child ? "完成后可能沉淀成什么" : "徽章能力卡预览复核",
            subtitle: "内容已安全隐藏；本地页面不会继续展示原始字段。",
            audienceNote: role == .child
                ? "先不用着急，等家长确认后再继续。"
                : "请回正式复核流程查看原因；本页不显示原始字段。",
            candidates: [],
            abilityHints: [],
            findings: [finding],
            publicSummary: MobileGrowthPackAchievementCardPreviewPublicSummary(
                role: role,
                candidateCount: 0,
                visibleCandidateCount: 0,
                previewReadyCount: 0,
                blockedCount: 1,
                verificationRequiredCount: 0,
                consentRequiredCount: 0,
                moderationRequiredCount: 0,
                abilityJumpRiskCount: 0,
                abilityHintCount: 0,
                findingCodes: [.unsafePayloadBlocked]
            )
        )
    }

    private func makeCandidates(
        for role: MobileGrowthPackExecutionHubRole
    ) -> [MobileGrowthPackAchievementCardPreviewCandidate] {
        [
            candidate(
                category: .badge,
                role: role,
                status: .needsMoreEvidence,
                childSummary: "坚持完成成长包可能换来一枚徽章候选，现在还差最后的确认。",
                guardianSummary: "徽章候选需要证据验证；未验证前不能授徽章，也不能让能力卡借此跳变。",
                gapReason: role == .child ? "还要等大人确认你真的完成了。" : "证据未验证，缺少完成确认。",
                childNextStep: "把今天做的事说清楚，等老师或家长确认。",
                guardianNextStep: "确认证据真实、未退回，再考虑是否进入授徽章流程。",
                safetyNote: "不授徽章、不写账本、不发成长积分。",
                sortOrder: 10,
                requiresVerification: true,
                isFrozen: false,
                underAppeal: false,
                accessRevoked: false,
                requiresConsent: false,
                requiresModeration: false,
                requiresGuardianReview: true,
                abilityJumpRisk: false,
                visibleToChild: true,
                visibleToGuardian: true
            ),
            candidate(
                category: .abilityCard,
                role: role,
                status: .blocked,
                childSummary: "你的成长球星卡先暂停更新，等大人看过后再继续。",
                guardianSummary: "能力卡候选已冻结：存在能力维度跳变风险，确认前不更新成长球星卡。",
                gapReason: role == .child ? "这张卡先停一下，不是你的错。" : "能力卡冻结中，跳变风险待人工复核。",
                childNextStep: "先做下一步，能力卡晚点会自己更新。",
                guardianNextStep: "复核跳变幅度、证据来源和跨孩子对比，再决定是否解冻。",
                safetyNote: "不更新能力卡、不改能力维度、不发成长积分。",
                sortOrder: 20,
                requiresVerification: false,
                isFrozen: true,
                underAppeal: false,
                accessRevoked: false,
                requiresConsent: false,
                requiresModeration: false,
                requiresGuardianReview: true,
                abilityJumpRisk: true,
                visibleToChild: true,
                visibleToGuardian: true
            ),
            candidate(
                category: .honorWall,
                role: role,
                status: .waitingConsent,
                childSummary: "做得好的作品可能上荣誉墙，公开前要等你和家长都同意。",
                guardianSummary: "荣誉墙展示候选需要孩子 assent、家长同意和内容审核；未同意/未审核前不发布。",
                gapReason: role == .child ? "还要等你和家长一起同意。" : "缺少同意与内容审核，未达发布前置条件。",
                childNextStep: "先保存想法，等家长一起看再决定要不要公开。",
                guardianNextStep: "确认同意、可见范围、最小披露和审核都通过，再谈发布。",
                safetyNote: "不发布荣誉墙、不上传媒体、不通知亲友。",
                sortOrder: 30,
                requiresVerification: false,
                isFrozen: false,
                underAppeal: false,
                accessRevoked: false,
                requiresConsent: true,
                requiresModeration: true,
                requiresGuardianReview: true,
                abilityJumpRisk: false,
                visibleToChild: true,
                visibleToGuardian: true
            ),
            candidate(
                category: .storyline,
                role: role,
                status: .waitingReview,
                childSummary: "你的成长故事线会把努力串起来，发布前要先做安全检查。",
                guardianSummary: "成长故事线候选需内容审核，避免拼出学校/家庭敏感信息或跨孩子内容。",
                gapReason: role == .child ? "故事还要做一次安全检查。" : "故事线未审核，存在敏感信息拼合风险。",
                childNextStep: "先把亮点记下来，等大人看过再分享。",
                guardianNextStep: "复核故事线是否泄露学校/家庭信息、是否最小披露。",
                safetyNote: "不发布故事线、不拼接敏感信息、不公开位置。",
                sortOrder: 40,
                requiresVerification: false,
                isFrozen: false,
                underAppeal: false,
                accessRevoked: false,
                requiresConsent: false,
                requiresModeration: true,
                requiresGuardianReview: true,
                abilityJumpRisk: false,
                visibleToChild: true,
                visibleToGuardian: true
            ),
            candidate(
                category: .familyAchievement,
                role: role,
                status: .previewReady,
                childSummary: "有些成长亮点已经能安全地记在家庭成就里，先保持家庭私密。",
                guardianSummary: "家庭成就记录保持家庭私密、最小披露，可作为安全沉淀记录，不对外公开。",
                gapReason: "",
                childNextStep: "继续记录你的成长亮点，先留在家里。",
                guardianNextStep: "确认家庭成就保持私密、未误触公开或亲友可见。",
                safetyNote: "不公开、不发通知、不授徽章。",
                sortOrder: 50,
                requiresVerification: false,
                isFrozen: false,
                underAppeal: false,
                accessRevoked: false,
                requiresConsent: false,
                requiresModeration: false,
                requiresGuardianReview: false,
                abilityJumpRisk: false,
                visibleToChild: true,
                visibleToGuardian: true
            ),
            candidate(
                category: .relativeShare,
                role: role,
                status: .blocked,
                childSummary: "分享给亲友的鼓励内容先收起来，等家长重新确认可见范围。",
                guardianSummary: "亲友可见候选的访问权限已撤回，需要家长重新同意才能恢复传播。",
                gapReason: role == .child ? "这个分享先暂停一下。" : "亲友访问权限已撤回，需重新同意并回滚旧传播。",
                childNextStep: "先不用担心，等家长确认谁能看。",
                guardianNextStep: "确认撤回已生效、旧链路已回滚、重新同意后再恢复可见。",
                safetyNote: "不恢复可见、不通知亲友、不公开内容。",
                sortOrder: 60,
                requiresVerification: false,
                isFrozen: false,
                underAppeal: false,
                accessRevoked: true,
                requiresConsent: true,
                requiresModeration: false,
                requiresGuardianReview: true,
                abilityJumpRisk: false,
                visibleToChild: true,
                visibleToGuardian: true
            ),
            candidate(
                category: .guardianBoundary,
                role: role,
                status: .waitingReview,
                childSummary: "",
                guardianSummary: "可见性/撤回/回滚边界：有成就正在申诉，撤回后必须回滚徽章、能力卡和荣誉墙展示。",
                gapReason: "",
                childNextStep: "",
                guardianNextStep: "在正式复核流程确认申诉结果、撤回回滚和可见性边界后再放行。",
                safetyNote: "不授徽章、不更新能力卡、不发布、不写账本。",
                sortOrder: 70,
                requiresVerification: false,
                isFrozen: false,
                underAppeal: true,
                accessRevoked: false,
                requiresConsent: false,
                requiresModeration: false,
                requiresGuardianReview: true,
                abilityJumpRisk: false,
                visibleToChild: false,
                visibleToGuardian: true
            )
        ]
    }

    private func candidate(
        category: MobileGrowthPackAchievementCardPreviewCategory,
        role: MobileGrowthPackExecutionHubRole,
        status: MobileGrowthPackAchievementCardPreviewStatus,
        childSummary: String,
        guardianSummary: String,
        gapReason: String,
        childNextStep: String,
        guardianNextStep: String,
        safetyNote: String,
        sortOrder: Int,
        requiresVerification: Bool,
        isFrozen: Bool,
        underAppeal: Bool,
        accessRevoked: Bool,
        requiresConsent: Bool,
        requiresModeration: Bool,
        requiresGuardianReview: Bool,
        abilityJumpRisk: Bool,
        visibleToChild: Bool,
        visibleToGuardian: Bool
    ) -> MobileGrowthPackAchievementCardPreviewCandidate {
        MobileGrowthPackAchievementCardPreviewCandidate(
            publicPreviewRef: publicRef("candidate:\(category.rawValue):\(role.rawValue):\(sortOrder)"),
            category: category,
            status: status,
            title: category.title,
            summary: role == .child ? childSummary : guardianSummary,
            gapReason: gapReason,
            nextStep: role == .child ? childNextStep : guardianNextStep,
            safetyNote: safetyNote,
            visibleToChild: visibleToChild,
            visibleToGuardian: visibleToGuardian,
            requiresVerification: requiresVerification,
            isFrozen: isFrozen,
            underAppeal: underAppeal,
            accessRevoked: accessRevoked,
            requiresConsent: requiresConsent,
            requiresModeration: requiresModeration,
            requiresGuardianReview: requiresGuardianReview,
            abilityJumpRisk: abilityJumpRisk,
            sortOrder: sortOrder
        )
    }

    private func makeAbilityHints(
        for role: MobileGrowthPackExecutionHubRole
    ) -> [MobileGrowthPackAchievementCardPreviewAbilityHint] {
        [
            abilityHint(
                dimension: .learning,
                role: role,
                childGrowthNote: "认真完成作业自检会让学习力慢慢变强。",
                guardianGrowthNote: "学习力主要来自作业与测验自检证据，确认后才反映到能力卡。",
                childNextStep: "把不懂的地方记下来，下次先自己想一遍。",
                guardianNextStep: "确认证据真实，避免单次成绩造成跳变。",
                jumpRisk: false
            ),
            abilityHint(
                dimension: .expression,
                role: role,
                childGrowthNote: "把想法讲清楚、写明白会让表达力成长。",
                guardianGrowthNote: "表达力来自创作说明与复盘，公开内容需先审核。",
                childNextStep: "试着用自己的话讲一遍今天学到的东西。",
                guardianNextStep: "确认表达类作品已审核、未泄露敏感信息。",
                jumpRisk: false
            ),
            abilityHint(
                dimension: .persistence,
                role: role,
                childGrowthNote: "每天坚持一点点会让坚持力越来越稳。",
                guardianGrowthNote: "坚持力看连续完成趋势，单次冲刺不应造成跳变。",
                childNextStep: "继续保持每天的小目标。",
                guardianNextStep: "关注是否因奖励压力出现异常冲刺。",
                jumpRisk: true
            ),
            abilityHint(
                dimension: .creativity,
                role: role,
                childGrowthNote: "多尝试新点子会让创造力成长。",
                guardianGrowthNote: "创造力来自创作展示，需配合内容审核与同意。",
                childNextStep: "记录一个你自己想出来的小创意。",
                guardianNextStep: "确认创作已审核、同意范围清楚。",
                jumpRisk: false
            ),
            abilityHint(
                dimension: .collaboration,
                role: role,
                childGrowthNote: "和同学家人一起完成任务会让协作力变强。",
                guardianGrowthNote: "协作力看共同任务参与，不涉及跨孩子内容。",
                childNextStep: "下次试着和别人一起完成一个小任务。",
                guardianNextStep: "确认协作记录不混入其他孩子的隐私。",
                jumpRisk: false
            ),
            abilityHint(
                dimension: .physical,
                role: role,
                childGrowthNote: "坚持运动会让运动力慢慢提升。",
                guardianGrowthNote: "运动力依赖运动证明，异常数据确认前不应造成跳变。",
                childNextStep: "继续记录你喜欢的运动。",
                guardianNextStep: "复核运动证明异常，避免设备数据造成跳变。",
                jumpRisk: true
            )
        ]
    }

    private func abilityHint(
        dimension: MobileGrowthPackAchievementCardPreviewAbilityDimension,
        role: MobileGrowthPackExecutionHubRole,
        childGrowthNote: String,
        guardianGrowthNote: String,
        childNextStep: String,
        guardianNextStep: String,
        jumpRisk: Bool
    ) -> MobileGrowthPackAchievementCardPreviewAbilityHint {
        MobileGrowthPackAchievementCardPreviewAbilityHint(
            publicPreviewRef: publicRef("ability:\(dimension.rawValue):\(role.rawValue)"),
            dimension: dimension,
            growthNote: role == .child ? childGrowthNote : guardianGrowthNote,
            nextStep: role == .child ? childNextStep : guardianNextStep,
            jumpRisk: jumpRisk,
            visibleToChild: true,
            visibleToGuardian: true
        )
    }

    private func makeFindings(
        role: MobileGrowthPackExecutionHubRole,
        candidates: [MobileGrowthPackAchievementCardPreviewCandidate]
    ) -> [MobileGrowthPackAchievementCardPreviewFinding] {
        var findings = [
            MobileGrowthPackAchievementCardPreviewFinding(
                code: .readOnlyPreview,
                message: "预览只读整理“完成后可能沉淀成什么”，不会授徽章、更新能力卡、发布荣誉墙或发成长积分。",
                actionRequired: false,
                visibleToChild: true
            )
        ]
        if candidates.contains(where: \.requiresVerification) {
            findings.append(
                MobileGrowthPackAchievementCardPreviewFinding(
                    code: .verificationRequired,
                    message: role == .child ? "有徽章要等大人确认你真的完成了。" : "存在未验证证据，验证前不能授徽章。",
                    actionRequired: true,
                    visibleToChild: true
                )
            )
        }
        if candidates.contains(where: \.requiresConsent) {
            findings.append(
                MobileGrowthPackAchievementCardPreviewFinding(
                    code: .consentRequired,
                    message: role == .child ? "公开内容要等你和家长都同意。" : "缺少同意，未达公开/亲友可见前置条件。",
                    actionRequired: true,
                    visibleToChild: true
                )
            )
        }
        if candidates.contains(where: \.isBlocked) {
            findings.append(
                MobileGrowthPackAchievementCardPreviewFinding(
                    code: .previewOnHold,
                    message: role == .child ? "有些成就先暂停沉淀，等大人确认后再继续，你可以先做下一步。" : "有候选处于暂停状态，需正式复核后再放行。",
                    actionRequired: true,
                    visibleToChild: true
                )
            )
        }
        guard role == .guardian else {
            return findings.filter(\.visibleToChild)
        }
        if candidates.contains(where: \.isFrozen) {
            findings.append(
                MobileGrowthPackAchievementCardPreviewFinding(
                    code: .achievementFrozen,
                    message: "能力卡冻结中，解冻前不更新成长球星卡。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        if candidates.contains(where: \.underAppeal) {
            findings.append(
                MobileGrowthPackAchievementCardPreviewFinding(
                    code: .appealPending,
                    message: "有成就正在申诉，结果确认前不授徽章、不更新能力卡、不发布。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        if candidates.contains(where: \.accessRevoked) {
            findings.append(
                MobileGrowthPackAchievementCardPreviewFinding(
                    code: .accessRevoked,
                    message: "亲友访问已撤回，需回滚旧传播并重新同意后再恢复可见。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        if candidates.contains(where: \.requiresModeration) {
            findings.append(
                MobileGrowthPackAchievementCardPreviewFinding(
                    code: .moderationRequired,
                    message: "创作与故事线通过内容审核前不能进入荣誉墙或亲友可见。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        if candidates.contains(where: \.abilityJumpRisk) {
            findings.append(
                MobileGrowthPackAchievementCardPreviewFinding(
                    code: .abilityJumpRisk,
                    message: "存在能力维度跳变风险，确认前不更新能力卡运动/坚持等维度。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        if candidates.contains(where: { $0.category == .honorWall }) {
            findings.append(
                MobileGrowthPackAchievementCardPreviewFinding(
                    code: .honorWallPrecondition,
                    message: "荣誉墙发布前置：需同意、assent、审核、可见范围与最小披露全部满足。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        return findings
    }

    private func summary(
        role: MobileGrowthPackExecutionHubRole,
        allCandidates: [MobileGrowthPackAchievementCardPreviewCandidate],
        visibleCandidates: [MobileGrowthPackAchievementCardPreviewCandidate],
        visibleHints: [MobileGrowthPackAchievementCardPreviewAbilityHint],
        findings: [MobileGrowthPackAchievementCardPreviewFinding]
    ) -> MobileGrowthPackAchievementCardPreviewPublicSummary {
        MobileGrowthPackAchievementCardPreviewPublicSummary(
            role: role,
            candidateCount: allCandidates.count,
            visibleCandidateCount: visibleCandidates.count,
            previewReadyCount: visibleCandidates.filter { $0.status == .previewReady }.count,
            blockedCount: visibleCandidates.filter(\.isBlocked).count,
            verificationRequiredCount: visibleCandidates.filter(\.requiresVerification).count,
            consentRequiredCount: visibleCandidates.filter(\.requiresConsent).count,
            moderationRequiredCount: visibleCandidates.filter(\.requiresModeration).count,
            abilityJumpRiskCount: visibleCandidates.filter(\.abilityJumpRisk).count,
            abilityHintCount: visibleHints.count,
            findingCodes: findings.map(\.code)
        )
    }

    private func publicRef(_ seed: String) -> String {
        "gpa-\(Self.stableHash("\(Self.redactionSalt):\(seed)"))"
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
