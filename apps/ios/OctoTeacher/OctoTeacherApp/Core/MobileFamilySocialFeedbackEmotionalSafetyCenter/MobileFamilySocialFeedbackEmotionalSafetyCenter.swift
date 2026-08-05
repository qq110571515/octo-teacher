import Foundation

/// iOS 家庭社交反馈情绪安全中心的纯本地只读投影。
///
/// 这一层把家庭社交反馈情绪安全、亲友鼓励留言审核、亲友荣誉墙故事线批准、
/// 成长日记 / VLOG 连续性审核、专家 / 家长主题讨论治理等语义闭环到 iOS：
/// 亲友鼓励、荣誉墙故事线反馈、成长动态反馈、成长日记 / VLOG 连续性、专家 / 家长
/// 主题讨论、通知预览在进入孩子可见区或亲友 / 专家可见区前，是否具备家长审核、
/// 家长同意、孩子 assent，是否含羞辱 / 攀比 / 压力语言、奖励承诺、成长积分数额泄露、
/// 跨孩子内容、专家讨论泄露、连续性缺口、通知情绪安全风险、亲友越权或最小披露风险。
///
/// 它只生成展示模型，绝不真实发布评论、审核内容、通知亲友或孩子、发成长积分 / 扣成长积分、
/// 授徽章、发布荣誉墙、上传媒体、写账本、兑换奖励，也不控制设备或屏幕时间。
///
/// 孩子视角只看温和支持、等待家长审核、休息 / 继续努力下一步，不显示原始评论、
/// 羞辱 / 攀比 / 压力语言、奖励承诺、成长积分数额、审核原因、专家讨论、设备 / 通知命令
/// 或跨孩子内容；家长视角只读查看亲友评论、荣誉墙反馈、成长动态、日记 / VLOG 摘要、
/// 专家 / 家长讨论、通知预览的情绪安全、审核状态、撤回 / 删除、亲友撤权、压力语言和
/// 最小披露风险；亲友视角只看支持性表达指引和待审核 / 已通过鼓励；专家视角只看通用
/// 主题建议边界，不看孩子私密内容或家庭规则。

/// 查看视角。rawValue 只是安全枚举，不携带真实 child/family/guardian/relative/expert 身份。
enum MobileFamilySocialFeedbackEmotionalSafetyCenterRole: String, CaseIterable, Equatable {
    case child
    case guardian
    case relative
    case expert

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        case .relative: return "亲友"
        case .expert: return "专家"
        }
    }
}

/// 反馈渠道。映射社交反馈来源，rawValue 不携带真实 comment/story/diary/vlog/discussion。
enum MobileFamilySocialFeedbackEmotionalSafetyCenterChannel: String, CaseIterable, Equatable {
    case relativeEncouragement = "relative_encouragement_feedback"
    case honorWallStoryline = "honor_wall_storyline_feedback"
    case growthMoment = "growth_moment_feedback"
    case diaryVlogContinuity = "diary_vlog_continuity_review"
    case expertTopicDiscussion = "expert_topic_discussion"
    case parentTopicDiscussion = "parent_topic_discussion"
    case notificationPreview = "notification_emotional_safety_preview"

    var title: String {
        switch self {
        case .relativeEncouragement: return "亲友鼓励留言"
        case .honorWallStoryline: return "荣誉墙故事线反馈"
        case .growthMoment: return "成长动态反馈"
        case .diaryVlogContinuity: return "成长日记 / VLOG 连续性"
        case .expertTopicDiscussion: return "专家主题讨论"
        case .parentTopicDiscussion: return "家长主题讨论"
        case .notificationPreview: return "通知情绪安全预览"
        }
    }
}

/// 反馈状态。孩子看到的都是温和措辞。
enum MobileFamilySocialFeedbackEmotionalSafetyCenterStatus: String, Equatable {
    case gentleSupport = "gentle_support"
    case waitingReview = "waiting_review"
    case needsModeration = "needs_moderation"
    case revoked
    case removed
    case relativeVisible = "relative_visible"
    case expertBoundary = "expert_boundary"
    case onHold = "on_hold"

    var label: String {
        switch self {
        case .gentleSupport: return "温和支持"
        case .waitingReview: return "等家长看"
        case .needsModeration: return "需审核"
        case .revoked: return "已撤回"
        case .removed: return "已删除"
        case .relativeVisible: return "已通过鼓励"
        case .expertBoundary: return "主题边界"
        case .onHold: return "先暂停"
        }
    }

    func label(for role: MobileFamilySocialFeedbackEmotionalSafetyCenterRole) -> String {
        guard role == .child else { return label }

        switch self {
        case .gentleSupport, .relativeVisible: return "温和支持"
        case .waitingReview, .needsModeration: return "等家长看"
        case .revoked, .removed, .onHold: return "先收起来"
        case .expertBoundary: return "主题边界"
        }
    }
}

/// 安全 finding 码。仅供 iOS 展示，不回显原始字段。
enum MobileFamilySocialFeedbackEmotionalSafetyCenterFindingCode: String, Equatable {
    case readOnlyPreview = "READ_ONLY_PREVIEW"
    case gentleSupportOnly = "GENTLE_SUPPORT_ONLY"
    case waitingGuardianReview = "WAITING_GUARDIAN_REVIEW"
    case restOrKeepGoing = "REST_OR_KEEP_GOING"
    case contentUnderReview = "CONTENT_UNDER_REVIEW"
    case contentRevoked = "CONTENT_REVOKED"
    case contentRemoved = "CONTENT_REMOVED"
    case feedbackOnHold = "FEEDBACK_ON_HOLD"
    case relativeScopeApplied = "RELATIVE_SCOPE_APPLIED"
    case relativeExpressionGuidance = "RELATIVE_EXPRESSION_GUIDANCE"
    case expertTopicBoundaryApplied = "EXPERT_TOPIC_BOUNDARY_APPLIED"
    // 家长专属内部判断，不向孩子 / 亲友 / 专家泄露。
    case guardianConsentMissing = "GUARDIAN_CONSENT_MISSING"
    case childAssentMissing = "CHILD_ASSENT_MISSING"
    case moderationRequired = "MODERATION_REQUIRED"
    case pressureLanguageRisk = "PRESSURE_OR_SHAMING_LANGUAGE_RISK"
    case rewardPromiseRisk = "REWARD_PROMISE_RISK"
    case creditAmountLeakRisk = "CREDIT_VALUE_LEAK_RISK"
    case expertDiscussionLeakRisk = "EXPERT_DISCUSSION_LEAK_RISK"
    case crossChildLeakRisk = "CROSS_CHILD_CONTENT_LEAK_RISK"
    case relativeOverscope = "RELATIVE_OVERSCOPE_VISIBLE"
    case diaryVlogContinuityGap = "DIARY_VLOG_CONTINUITY_GAP"
    case notificationEmotionalSafetyRisk = "NOTIFICATION_EMOTIONAL_SAFETY_RISK"
    case minimalDisclosureRisk = "MINIMAL_DISCLOSURE_RISK"
    case publicSummaryLeak = "PUBLIC_SUMMARY_SENSITIVE_LEAK"
    case unsafePayloadBlocked = "UNSAFE_PAYLOAD_BLOCKED"

    var label: String {
        switch self {
        case .readOnlyPreview: return "只读预览"
        case .gentleSupportOnly: return "温和支持"
        case .waitingGuardianReview: return "等家长看"
        case .restOrKeepGoing: return "休息或继续"
        case .contentUnderReview: return "安全检查中"
        case .contentRevoked, .contentRemoved: return "先收起来"
        case .feedbackOnHold: return "先暂停"
        case .relativeScopeApplied: return "可见范围"
        case .relativeExpressionGuidance: return "表达指引"
        case .expertTopicBoundaryApplied: return "主题边界"
        case .guardianConsentMissing: return "缺家长同意"
        case .childAssentMissing: return "缺孩子同意"
        case .moderationRequired: return "需审核"
        case .pressureLanguageRisk: return "压力语言"
        case .rewardPromiseRisk: return "奖励承诺"
        case .creditAmountLeakRisk: return "成长积分数值"
        case .expertDiscussionLeakRisk: return "专家可见边界"
        case .crossChildLeakRisk: return "跨孩子内容"
        case .relativeOverscope: return "亲友越权"
        case .diaryVlogContinuityGap: return "连续性风险"
        case .notificationEmotionalSafetyRisk: return "通知情绪风险"
        case .minimalDisclosureRisk: return "最小披露"
        case .publicSummaryLeak: return "公开摘要风险"
        case .unsafePayloadBlocked: return "已安全隐藏"
        }
    }
}

/// 单条反馈条目。所有副作用标记恒为 false。
struct MobileFamilySocialFeedbackEmotionalSafetyCenterItem: Identifiable, Equatable {
    var publicPreviewRef: String
    var channel: MobileFamilySocialFeedbackEmotionalSafetyCenterChannel
    var status: MobileFamilySocialFeedbackEmotionalSafetyCenterStatus
    var statusDisplayLabel: String
    var title: String
    var summary: String
    var gapReason: String
    var nextStep: String
    var safetyNote: String
    var visibleToChild: Bool
    var visibleToGuardian: Bool
    var visibleToRelative: Bool
    var visibleToExpert: Bool
    // 情绪安全 / 审核内部判断（家长可见，不向孩子 / 亲友 / 专家泄露原因）。
    var guardianConsentMissing: Bool
    var childAssentMissing: Bool
    var moderationRequired: Bool
    var pressureLanguageRisk: Bool
    var rewardPromiseRisk: Bool
    var creditAmountLeakRisk: Bool
    var expertDiscussionLeakRisk: Bool
    var crossChildLeakRisk: Bool
    var diaryVlogContinuityGap: Bool
    var notificationEmotionalSafetyRisk: Bool
    var minimalDisclosureRisk: Bool
    var publicSummaryLeakRisk: Bool
    var relativeOverscope: Bool
    var isRevoked: Bool
    var isRemoved: Bool
    var needsRollback: Bool
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
    let publishesHonorWall = false
    let publishesContent = false
    let postsComment = false
    let moderatesContent = false
    let approvesStoryline = false
    let governsDiscussion = false
    let reviewsCreativeWork = false
    let notifiesRelatives = false
    let notifiesChild = false
    let unlocksDevice = false
    let controlsScreenTime = false
    let sendsNotification = false
    let submitsProof = false

    var id: String { publicPreviewRef }

    var isBlocked: Bool {
        status == .onHold || isRevoked || isRemoved || needsRollback || relativeOverscope
    }

    var displayValues: [String] {
        [
            publicPreviewRef,
            channel.title,
            statusDisplayLabel,
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
            || publishesHonorWall || publishesContent || postsComment || moderatesContent
            || approvesStoryline || governsDiscussion || reviewsCreativeWork || notifiesRelatives
            || notifiesChild || unlocksDevice || controlsScreenTime || sendsNotification || submitsProof
    }
}

struct MobileFamilySocialFeedbackEmotionalSafetyCenterFinding: Identifiable, Equatable {
    var code: MobileFamilySocialFeedbackEmotionalSafetyCenterFindingCode
    var message: String
    var actionRequired: Bool
    var visibleToChild: Bool
    var visibleToRelative: Bool
    var visibleToExpert: Bool

    var id: String { code.rawValue }
    var displayValues: [String] { [code.label, message] }
}

struct MobileFamilySocialFeedbackEmotionalSafetyCenterPublicSummary: Equatable {
    var role: MobileFamilySocialFeedbackEmotionalSafetyCenterRole
    var itemCount: Int
    var visibleItemCount: Int
    var gentleSupportCount: Int
    var waitingReviewCount: Int
    var moderationRequiredCount: Int
    var revokedCount: Int
    var removedCount: Int
    var relativeVisibleCount: Int
    var blockedCount: Int
    var guardianConsentMissingCount: Int
    var childAssentMissingCount: Int
    var pressureLanguageRiskCount: Int
    var rewardPromiseRiskCount: Int
    var creditAmountLeakRiskCount: Int
    var expertDiscussionLeakRiskCount: Int
    var crossChildLeakRiskCount: Int
    var continuityGapCount: Int
    var notificationRiskCount: Int
    var minimalDisclosureRiskCount: Int
    var relativeOverscopeCount: Int
    var findingCodes: [MobileFamilySocialFeedbackEmotionalSafetyCenterFindingCode]

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
    let publishesHonorWall = false
    let publishesContent = false
    let postsComment = false
    let moderatesContent = false
    let approvesStoryline = false
    let governsDiscussion = false
    let reviewsCreativeWork = false
    let notifiesRelatives = false
    let notifiesChild = false
    let unlocksDevice = false
    let controlsScreenTime = false
    let sendsNotification = false
    let submitsProof = false

    var hasTriggeredSideEffect: Bool {
        callsNetwork || callsAiProvider || callsLocalModel || callsLms || writesSchoolSystem
            || opensExternalLink || opensCamera || opensPhotoLibrary || opensFilePicker || uploadsMedia
            || writesLedger || grantsCredit || spendsCredit || fulfillsReward || grantsBadge
            || publishesHonorWall || publishesContent || postsComment || moderatesContent
            || approvesStoryline || governsDiscussion || reviewsCreativeWork || notifiesRelatives
            || notifiesChild || unlocksDevice || controlsScreenTime || sendsNotification || submitsProof
    }
}

struct MobileFamilySocialFeedbackEmotionalSafetyCenter: Equatable {
    var role: MobileFamilySocialFeedbackEmotionalSafetyCenterRole
    var title: String
    var subtitle: String
    var audienceNote: String
    var items: [MobileFamilySocialFeedbackEmotionalSafetyCenterItem]
    var findings: [MobileFamilySocialFeedbackEmotionalSafetyCenterFinding]
    var publicSummary: MobileFamilySocialFeedbackEmotionalSafetyCenterPublicSummary

    var displayValues: [String] {
        [role.rawValue, title, subtitle, audienceNote]
            + items.flatMap(\.displayValues)
            + findings.flatMap(\.displayValues)
    }

    var hasUnsafeDisplayPayload: Bool {
        MobileFamilySocialFeedbackEmotionalSafetyCenterBuilder.hasUnsafeDisplayPayload(displayValues)
    }
}

struct MobileFamilySocialFeedbackEmotionalSafetyCenterInput: Equatable {
    var generatedAt: String
    var unsafePayload: String?

    static let mock = MobileFamilySocialFeedbackEmotionalSafetyCenterInput(
        generatedAt: "2026-06-25T02:00:00.000Z",
        unsafePayload: nil
    )
}

struct MobileFamilySocialFeedbackEmotionalSafetyCenterBuilder {
    private static let redactionSalt = "mobile-family-social-feedback-emotional-safety-center-v1"
    private static let sensitiveMarkers = [
        "child:", "family:", "school:", "teacher:", "guardian:", "relative:", "expert:", "creator:",
        "proof:", "media:", "photo:", "screenshot:", "transcript", "answer key", "answerkey",
        "答案键", "provider:", "model:", "resource:", "link:", "url:", "homework:", "quiz:",
        "badge:", "card:", "ability:", "story:", "storyline:", "honor:", "pack:", "reward:",
        "comment:", "vlog:", "diary:", "discussion:", "topic:", "notify:", "notification:",
        "order:", "inventory:", "ledger:", "device:", "entitlement:", "publicref", "adultreason",
        "adult reason", "internalref", "internal ref", "ref:", "task:", "taskid", "claim:", "claimid",
        "token", "api_key", "apikey", "secret", "credit amount", "成长积分金额", "账本明细", "设备命令",
        "家长预算", "复核策略", "审核策略", "http://", "https://", "file://", "/users/", "/volumes/",
        "child_real", "family_real", "proof_real", "comment_real", "vlog_real", "diary_real", "192.168.", ".local"
    ]

    func build(
        role: MobileFamilySocialFeedbackEmotionalSafetyCenterRole,
        input: MobileFamilySocialFeedbackEmotionalSafetyCenterInput = .mock
    ) -> MobileFamilySocialFeedbackEmotionalSafetyCenter {
        if let unsafePayload = input.unsafePayload, Self.hasUnsafeDisplayPayload([unsafePayload]) {
            return blockedPreview(role: role)
        }

        let allItems = makeItems(for: role)
        let visibleItems = allItems
            .filter { isVisible($0, to: role) }
            .sorted { left, right in
                if left.sortOrder == right.sortOrder {
                    return left.publicPreviewRef < right.publicPreviewRef
                }
                return left.sortOrder < right.sortOrder
            }

        let findings = makeFindings(role: role, items: visibleItems)

        return MobileFamilySocialFeedbackEmotionalSafetyCenter(
            role: role,
            title: title(for: role),
            subtitle: subtitle(for: role),
            audienceNote: audienceNote(for: role),
            items: visibleItems,
            findings: findings,
            publicSummary: summary(
                role: role,
                allItems: allItems,
                visibleItems: visibleItems,
                findings: findings
            )
        )
    }

    static func hasUnsafeDisplayPayload(_ values: [String]) -> Bool {
        let joined = values.joined(separator: " ").lowercased()
        return sensitiveMarkers.contains { joined.contains($0) }
    }

    private func isVisible(
        _ item: MobileFamilySocialFeedbackEmotionalSafetyCenterItem,
        to role: MobileFamilySocialFeedbackEmotionalSafetyCenterRole
    ) -> Bool {
        switch role {
        case .child: return item.visibleToChild
        case .guardian: return item.visibleToGuardian
        case .relative: return item.visibleToRelative
        case .expert: return item.visibleToExpert
        }
    }

    private func title(for role: MobileFamilySocialFeedbackEmotionalSafetyCenterRole) -> String {
        switch role {
        case .child: return "家人和老师的支持现在到哪一步了"
        case .guardian: return "家庭社交反馈情绪安全复核"
        case .relative: return "可以看到的鼓励与表达指引"
        case .expert: return "通用主题建议边界"
        }
    }

    private func subtitle(for role: MobileFamilySocialFeedbackEmotionalSafetyCenterRole) -> String {
        switch role {
        case .child:
            return "把家人和老师想给你的支持放在一起看；这里只读，看到的都是温和的话，需要等家长看过才会真的告诉你。"
        case .guardian:
            return "只读复核亲友评论、荣誉墙反馈、成长动态、日记 / VLOG 摘要、专家 / 家长讨论和通知预览的情绪安全、审核状态、撤回 / 删除、亲友撤权、压力语言和最小披露风险。"
        case .relative:
            return "只看支持性表达指引，以及你给孩子的鼓励是待家长审核还是已通过；不能直接发评论、给奖励或通知孩子。"
        case .expert:
            return "只看通用主题建议的安全边界；看不到任何孩子私密内容、家庭规则、原始作业或可识别家庭信息。"
        }
    }

    private func audienceNote(for role: MobileFamilySocialFeedbackEmotionalSafetyCenterRole) -> String {
        switch role {
        case .child:
            return "这里只看支持和下一步；累了可以先休息，想继续就继续努力，家人怎么说要等家长看过再告诉你。"
        case .guardian:
            return "这里只读整理情绪安全与审核状态；真正放行评论、批准荣誉墙、治理讨论和发通知仍走正式流程。"
        case .relative:
            return "你只读看到表达指引和审核状态；不能看到孩子私密日记、情绪细节、学校 / 家庭规则或审核原因。"
        case .expert:
            return "你只读看到通用主题建议边界；不能看到孩子私密内容、家庭规则、成长积分 / 设备信息或亲友身份。"
        }
    }

    private func blockedPreview(
        role: MobileFamilySocialFeedbackEmotionalSafetyCenterRole
    ) -> MobileFamilySocialFeedbackEmotionalSafetyCenter {
        let finding = MobileFamilySocialFeedbackEmotionalSafetyCenterFinding(
            code: .unsafePayloadBlocked,
            message: "预览发现不安全字段，已隐藏全部反馈，等待家长在正式流程复核。",
            actionRequired: true,
            visibleToChild: true,
            visibleToRelative: true,
            visibleToExpert: true
        )
        return MobileFamilySocialFeedbackEmotionalSafetyCenter(
            role: role,
            title: title(for: role),
            subtitle: "内容已安全隐藏；本地页面不会继续展示原始字段。",
            audienceNote: role == .child
                ? "先不用着急，累了可以休息，等家长看过再继续。"
                : "请回正式复核流程查看原因；本页不显示原始字段。",
            items: [],
            findings: [finding],
            publicSummary: MobileFamilySocialFeedbackEmotionalSafetyCenterPublicSummary(
                role: role,
                itemCount: 0,
                visibleItemCount: 0,
                gentleSupportCount: 0,
                waitingReviewCount: 0,
                moderationRequiredCount: 0,
                revokedCount: 0,
                removedCount: 0,
                relativeVisibleCount: 0,
                blockedCount: 1,
                guardianConsentMissingCount: 0,
                childAssentMissingCount: 0,
                pressureLanguageRiskCount: 0,
                rewardPromiseRiskCount: 0,
                creditAmountLeakRiskCount: 0,
                expertDiscussionLeakRiskCount: 0,
                crossChildLeakRiskCount: 0,
                continuityGapCount: 0,
                notificationRiskCount: 0,
                minimalDisclosureRiskCount: 0,
                relativeOverscopeCount: 0,
                findingCodes: [.unsafePayloadBlocked]
            )
        )
    }

    private func makeItems(
        for role: MobileFamilySocialFeedbackEmotionalSafetyCenterRole
    ) -> [MobileFamilySocialFeedbackEmotionalSafetyCenterItem] {
        [
            // 亲友鼓励（含轻微攀比语气，待审核）：孩子只看温和等待，亲友只看待审核。
            item(
                channel: .relativeEncouragement,
                role: role,
                status: .waitingReview,
                childSummary: "有家人想给你加油，家长看过后会用温和的话告诉你。",
                guardianSummary: "亲友鼓励留言含轻微攀比语气，需审核脱压后再决定是否转达给孩子。",
                relativeSummary: "你的鼓励正在等家长看一下，通过后才会温和地转达给孩子。",
                gapReason: role == .guardian ? "含压力 / 攀比措辞，需审核改写。" : "",
                childNextStep: "先做你自己的事，家人加油的话等家长看过再说。",
                guardianNextStep: "确认留言已脱压、保持鼓励语气后再转达。",
                relativeNextStep: "用具体、正向、不攀比的话表达支持，效果最好。",
                safetyNote: "不发布评论、不通知孩子、不发成长积分。",
                sortOrder: 10,
                visibleToChild: true, visibleToGuardian: true, visibleToRelative: true, visibleToExpert: false,
                moderationRequired: true,
                pressureLanguageRisk: true
            ),
            // 亲友鼓励（干净、已通过）：唯一对亲友确认可见的正向鼓励。
            item(
                channel: .relativeEncouragement,
                role: role,
                status: .relativeVisible,
                childSummary: "家人为你的努力感到骄傲，给你温和的鼓励。",
                guardianSummary: "亲友鼓励留言语气正向、已通过审核，可温和转达给孩子。",
                relativeSummary: "你的这条鼓励已经通过，会温和地转达给孩子。",
                gapReason: "",
                childNextStep: "继续保持你的节奏就好。",
                guardianNextStep: "保持鼓励语气、最小披露即可。",
                relativeNextStep: "继续用这种具体而温暖的方式鼓励孩子。",
                safetyNote: "不通知孩子、不发成长积分、不公开对外。",
                sortOrder: 20,
                visibleToChild: true, visibleToGuardian: true, visibleToRelative: true, visibleToExpert: false
            ),
            // 荣誉墙故事线反馈：缺家长同意与孩子 assent，等审核。
            item(
                channel: .honorWallStoryline,
                role: role,
                status: .waitingReview,
                childSummary: "你的成长故事想分享给家人看，要先等家长同意。",
                guardianSummary: "荣誉墙故事线反馈缺少家长同意与孩子 assent，批准前不能对亲友可见。",
                relativeSummary: "",
                gapReason: role == .guardian ? "缺家长同意与孩子 assent。" : "",
                childNextStep: "先保存，等家长一起看再决定要不要分享。",
                guardianNextStep: "确认家长同意、孩子 assent 与最小披露后再批准。",
                relativeNextStep: "",
                safetyNote: "不批准荣誉墙、不通知亲友、不公开。",
                sortOrder: 30,
                visibleToChild: true, visibleToGuardian: true, visibleToRelative: false, visibleToExpert: false,
                guardianConsentMissing: true,
                childAssentMissing: true
            ),
            // 成长动态反馈（亲友承诺奖励 + 提到成长积分数额）：孩子不看奖励承诺与金额。
            item(
                channel: .growthMoment,
                role: role,
                status: .needsModeration,
                childSummary: "家人看到你的进步很开心，家长会先看一下再告诉你。",
                guardianSummary: "成长动态反馈含奖励承诺并提到成长积分数额，需移除奖励诱导与数值后再转达。",
                relativeSummary: "",
                gapReason: role == .guardian ? "含奖励承诺与成长积分数额，需移除。" : "",
                childNextStep: "继续做你正在做的事，不用为奖励着急。",
                guardianNextStep: "移除奖励承诺与具体数值，只保留正向鼓励。",
                relativeNextStep: "",
                safetyNote: "不承诺奖励、不发成长积分、不通知孩子。",
                sortOrder: 40,
                visibleToChild: true, visibleToGuardian: true, visibleToRelative: false, visibleToExpert: false,
                moderationRequired: true,
                rewardPromiseRisk: true,
                creditAmountLeakRisk: true
            ),
            // 成长日记 / VLOG 连续性审核：前后内容拼出学校位置风险，需审核脱敏。
            item(
                channel: .diaryVlogContinuity,
                role: role,
                status: .needsModeration,
                childSummary: "你的成长日记和小视频很棒，分享前要先做一次安全检查。",
                guardianSummary: "成长日记 / VLOG 连续片段可能拼出学校 / 位置信息，需审核与最小披露后再处理。",
                relativeSummary: "",
                gapReason: role == .guardian ? "连续片段拼接位置风险，需脱敏。" : "",
                childNextStep: "先把亮点记下来，等大人看过再分享。",
                guardianNextStep: "复核连续片段是否泄露学校 / 位置，确认最小披露。",
                relativeNextStep: "",
                safetyNote: "不公开日记 / VLOG、不上传媒体、不通知亲友。",
                sortOrder: 50,
                visibleToChild: true, visibleToGuardian: true, visibleToRelative: false, visibleToExpert: false,
                moderationRequired: true,
                diaryVlogContinuityGap: true,
                minimalDisclosureRisk: true
            ),
            // 成长日记连续性：已撤回但旧片段未回滚。
            item(
                channel: .diaryVlogContinuity,
                role: role,
                status: .revoked,
                childSummary: "这篇成长日记先收起来了，不会展示给别人。",
                guardianSummary: "成长日记同意已撤回，但旧连续片段尚未回滚；撤回后需立即下线并回滚传播。",
                relativeSummary: "",
                gapReason: role == .guardian ? "撤回未回滚旧片段。" : "",
                childNextStep: "不用担心，想分享时再和家长说。",
                guardianNextStep: "确认撤回已生效、旧片段与摘要已回滚后再处理。",
                relativeNextStep: "",
                safetyNote: "不恢复展示、不通知亲友、不公开。",
                sortOrder: 60,
                visibleToChild: true, visibleToGuardian: true, visibleToRelative: false, visibleToExpert: false,
                isRevoked: true,
                needsRollback: true
            ),
            // 荣誉墙故事线：已删除但展示未回滚。
            item(
                channel: .honorWallStoryline,
                role: role,
                status: .removed,
                childSummary: "这个分享已经删掉了，先不会出现在家人那边。",
                guardianSummary: "荣誉墙故事线反馈已删除，但旧展示尚未回滚；需回滚后再确认。",
                relativeSummary: "",
                gapReason: role == .guardian ? "删除未回滚旧展示。" : "",
                childNextStep: "先做下一件事，想分享时再和家长商量。",
                guardianNextStep: "确认删除已回滚荣誉墙与亲友可见展示后再放行。",
                relativeNextStep: "",
                safetyNote: "不恢复展示、不通知亲友、不公开。",
                sortOrder: 70,
                visibleToChild: true, visibleToGuardian: true, visibleToRelative: false, visibleToExpert: false,
                isRemoved: true,
                needsRollback: true
            ),
            // 专家主题讨论：仅通用主题建议边界，专家可读，孩子不可见。
            item(
                channel: .expertTopicDiscussion,
                role: role,
                status: .expertBoundary,
                childSummary: "",
                guardianSummary: "专家主题讨论保持通用、不指向具体孩子；专家只看通用建议边界，看不到家庭私密内容。",
                relativeSummary: "",
                gapReason: "",
                childNextStep: "",
                guardianNextStep: "确认讨论保持通用、未引入可识别家庭信息即可。",
                relativeNextStep: "",
                expertSummary: "通用主题建议边界：只讨论一般性成长方法，不针对具体孩子、不读家庭规则或私密内容。",
                expertNextStep: "把建议保持在通用层面；如需个性化，请走家长在场的正式流程。",
                safetyNote: "不私聊孩子、不读私密内容、不绕过家长。",
                sortOrder: 80,
                visibleToChild: false, visibleToGuardian: true, visibleToRelative: false, visibleToExpert: true
            ),
            // 家长主题讨论：含跨孩子内容与专家泄露风险，需治理，专家不可见。
            item(
                channel: .parentTopicDiscussion,
                role: role,
                status: .needsModeration,
                childSummary: "",
                guardianSummary: "家长主题讨论引用了其他孩子内容，且可能泄露给专家或公开摘要，需治理与最小披露。",
                relativeSummary: "",
                gapReason: role == .guardian ? "跨孩子内容 + 专家 / 摘要泄露风险。" : "",
                childNextStep: "",
                guardianNextStep: "移除跨孩子内容，确认专家视图与公开摘要已脱敏。",
                relativeNextStep: "",
                safetyNote: "不公开讨论、不暴露其他孩子、不发给专家。",
                sortOrder: 90,
                visibleToChild: false, visibleToGuardian: true, visibleToRelative: false, visibleToExpert: false,
                moderationRequired: true,
                expertDiscussionLeakRisk: true,
                crossChildLeakRisk: true,
                publicSummaryLeakRisk: true
            ),
            // 通知预览情绪安全：通知含压力措辞，需脱压后再发，孩子只看温和等待。
            item(
                channel: .notificationPreview,
                role: role,
                status: .needsModeration,
                childSummary: "有一条提醒在等家长看过后才会用温和的话发给你。",
                guardianSummary: "通知预览含压力 / 催促措辞，发送前需脱压改写，避免给孩子造成情绪压力。",
                relativeSummary: "",
                gapReason: role == .guardian ? "通知含压力 / 催促措辞。" : "",
                childNextStep: "累了可以先休息，提醒会用温和的方式告诉你。",
                guardianNextStep: "把通知改成温和、可选择的措辞后再决定是否发送。",
                relativeNextStep: "",
                safetyNote: "不发送通知、不催促、不通知孩子。",
                sortOrder: 100,
                visibleToChild: true, visibleToGuardian: true, visibleToRelative: false, visibleToExpert: false,
                moderationRequired: true,
                pressureLanguageRisk: true,
                notificationEmotionalSafetyRisk: true
            ),
            // 亲友鼓励（越权）：亲友权限已撤回但仍可见，需重新限定，亲友 / 孩子不可见。
            item(
                channel: .relativeEncouragement,
                role: role,
                status: .onHold,
                childSummary: "",
                guardianSummary: "一条亲友鼓励来自已撤回权限的亲友，越权可见已暂停，需重新限定授权范围。",
                relativeSummary: "",
                gapReason: role == .guardian ? "亲友权限已撤回，越权可见。" : "",
                childNextStep: "",
                guardianNextStep: "确认亲友授权范围、撤回越权可见后再恢复。",
                relativeNextStep: "",
                safetyNote: "不恢复可见、不通知孩子、不扩大授权。",
                sortOrder: 110,
                visibleToChild: false, visibleToGuardian: true, visibleToRelative: false, visibleToExpert: false,
                relativeOverscope: true
            )
        ]
    }

    private func item(
        channel: MobileFamilySocialFeedbackEmotionalSafetyCenterChannel,
        role: MobileFamilySocialFeedbackEmotionalSafetyCenterRole,
        status: MobileFamilySocialFeedbackEmotionalSafetyCenterStatus,
        childSummary: String,
        guardianSummary: String,
        relativeSummary: String,
        gapReason: String,
        childNextStep: String,
        guardianNextStep: String,
        relativeNextStep: String,
        expertSummary: String = "",
        expertNextStep: String = "",
        safetyNote: String,
        sortOrder: Int,
        visibleToChild: Bool,
        visibleToGuardian: Bool,
        visibleToRelative: Bool,
        visibleToExpert: Bool,
        guardianConsentMissing: Bool = false,
        childAssentMissing: Bool = false,
        moderationRequired: Bool = false,
        pressureLanguageRisk: Bool = false,
        rewardPromiseRisk: Bool = false,
        creditAmountLeakRisk: Bool = false,
        expertDiscussionLeakRisk: Bool = false,
        crossChildLeakRisk: Bool = false,
        diaryVlogContinuityGap: Bool = false,
        notificationEmotionalSafetyRisk: Bool = false,
        minimalDisclosureRisk: Bool = false,
        publicSummaryLeakRisk: Bool = false,
        relativeOverscope: Bool = false,
        isRevoked: Bool = false,
        isRemoved: Bool = false,
        needsRollback: Bool = false
    ) -> MobileFamilySocialFeedbackEmotionalSafetyCenterItem {
        let summary: String
        let nextStep: String
        switch role {
        case .child:
            summary = childSummary
            nextStep = childNextStep
        case .guardian:
            summary = guardianSummary
            nextStep = guardianNextStep
        case .relative:
            summary = relativeSummary
            nextStep = relativeNextStep
        case .expert:
            summary = expertSummary
            nextStep = expertNextStep
        }
        return MobileFamilySocialFeedbackEmotionalSafetyCenterItem(
            publicPreviewRef: publicRef("item:\(channel.rawValue):\(role.rawValue):\(sortOrder)"),
            channel: channel,
            status: status,
            statusDisplayLabel: status.label(for: role),
            title: channel.title,
            summary: summary,
            gapReason: gapReason,
            nextStep: nextStep,
            safetyNote: safetyNote,
            visibleToChild: visibleToChild,
            visibleToGuardian: visibleToGuardian,
            visibleToRelative: visibleToRelative,
            visibleToExpert: visibleToExpert,
            guardianConsentMissing: guardianConsentMissing,
            childAssentMissing: childAssentMissing,
            moderationRequired: moderationRequired,
            pressureLanguageRisk: pressureLanguageRisk,
            rewardPromiseRisk: rewardPromiseRisk,
            creditAmountLeakRisk: creditAmountLeakRisk,
            expertDiscussionLeakRisk: expertDiscussionLeakRisk,
            crossChildLeakRisk: crossChildLeakRisk,
            diaryVlogContinuityGap: diaryVlogContinuityGap,
            notificationEmotionalSafetyRisk: notificationEmotionalSafetyRisk,
            minimalDisclosureRisk: minimalDisclosureRisk,
            publicSummaryLeakRisk: publicSummaryLeakRisk,
            relativeOverscope: relativeOverscope,
            isRevoked: isRevoked,
            isRemoved: isRemoved,
            needsRollback: needsRollback,
            sortOrder: sortOrder
        )
    }

    private func makeFindings(
        role: MobileFamilySocialFeedbackEmotionalSafetyCenterRole,
        items: [MobileFamilySocialFeedbackEmotionalSafetyCenterItem]
    ) -> [MobileFamilySocialFeedbackEmotionalSafetyCenterFinding] {
        var findings = [
            MobileFamilySocialFeedbackEmotionalSafetyCenterFinding(
                code: .readOnlyPreview,
                message: "预览只读整理情绪安全与审核状态，不会发布评论、审核内容、批准荣誉墙、治理讨论、通知亲友 / 孩子或发成长积分。",
                actionRequired: false,
                visibleToChild: true,
                visibleToRelative: true,
                visibleToExpert: true
            )
        ]

        if role == .expert {
            findings.append(MobileFamilySocialFeedbackEmotionalSafetyCenterFinding(
                code: .expertTopicBoundaryApplied,
                message: "你只看到通用主题建议边界；看不到孩子私密内容、家庭规则、原始作业、健康 / 设备 / 成长积分信息或亲友身份。",
                actionRequired: false,
                visibleToChild: false,
                visibleToRelative: false,
                visibleToExpert: true
            ))
            return findings.filter(\.visibleToExpert)
        }

        if role == .relative {
            findings.append(MobileFamilySocialFeedbackEmotionalSafetyCenterFinding(
                code: .relativeExpressionGuidance,
                message: "用具体、正向、不攀比、不催促的话表达支持；不要承诺奖励、不要提分数或名次。",
                actionRequired: false,
                visibleToChild: false,
                visibleToRelative: true,
                visibleToExpert: false
            ))
            findings.append(MobileFamilySocialFeedbackEmotionalSafetyCenterFinding(
                code: .relativeScopeApplied,
                message: "你只看到自己鼓励的审核状态；看不到孩子私密日记、情绪细节、学校 / 家庭规则或审核原因。",
                actionRequired: false,
                visibleToChild: false,
                visibleToRelative: true,
                visibleToExpert: false
            ))
            return findings.filter(\.visibleToRelative)
        }

        // 孩子 / 家长共享的温和状态提示。
        findings.append(MobileFamilySocialFeedbackEmotionalSafetyCenterFinding(
            code: .gentleSupportOnly,
            message: role == .guardian
                ? "孩子端只显示温和支持与等待提示，不显示原始评论、压力语言、奖励承诺、成长积分数值或审核原因。"
                : "你看到的都是温和的支持；具体的话要等家长看过再温和地告诉你。",
            actionRequired: false,
            visibleToChild: true,
            visibleToRelative: false,
            visibleToExpert: false
        ))
        if items.contains(where: { $0.guardianConsentMissing || $0.childAssentMissing }) {
            findings.append(finding(.waitingGuardianReview,
                child: "有内容要等家长同意后才能分享给家人。",
                guardian: "存在缺少家长同意 / 孩子 assent 的反馈，批准前不能对亲友可见。",
                actionRequired: true, role: role))
        }
        if items.contains(where: \.moderationRequired) {
            findings.append(finding(.contentUnderReview,
                child: "有内容正在做安全检查，检查通过后家长会温和地告诉你。",
                guardian: "存在需审核的反馈，审核前不能转达孩子或对亲友可见。",
                actionRequired: true, role: role))
        }
        if items.contains(where: \.isRevoked) {
            findings.append(finding(.contentRevoked,
                child: "有内容已经收起来了，先不会展示给别人。",
                guardian: "存在已撤回的反馈，需确认撤回已生效并回滚旧展示。",
                actionRequired: true, role: role))
        }
        if items.contains(where: \.isRemoved) {
            findings.append(finding(.contentRemoved,
                child: "有内容已经删掉了，先不会出现在家人那边。",
                guardian: "存在已删除的反馈，需确认展示已回滚。",
                actionRequired: true, role: role))
        }
        if items.contains(where: \.isBlocked) {
            findings.append(finding(.feedbackOnHold,
                child: "有些内容先暂停，等大人确认后再继续，你可以先做下一步。",
                guardian: "有反馈处于暂停状态，需正式复核后再放行。",
                actionRequired: true, role: role))
        }
        // 孩子永远看到「休息 / 继续努力」的下一步提示。
        findings.append(MobileFamilySocialFeedbackEmotionalSafetyCenterFinding(
            code: .restOrKeepGoing,
            message: role == .guardian
                ? "孩子端下一步只提供休息或继续努力，不施加奖励诱导或名次压力。"
                : "累了就先休息，想继续就继续努力，按你自己的节奏来。",
            actionRequired: false,
            visibleToChild: true,
            visibleToRelative: false,
            visibleToExpert: false
        ))

        guard role == .guardian else {
            return findings.filter(\.visibleToChild)
        }

        // 家长专属的情绪安全 / 审核风险 findings。
        if items.contains(where: \.guardianConsentMissing) {
            findings.append(guardianFinding(.guardianConsentMissing,
                "缺少家长同意，未达对亲友可见的前置条件。"))
        }
        if items.contains(where: \.childAssentMissing) {
            findings.append(guardianFinding(.childAssentMissing,
                "缺少孩子 assent，孩子未自愿同意前不能分享。"))
        }
        if items.contains(where: \.moderationRequired) {
            findings.append(guardianFinding(.moderationRequired,
                "亲友评论、成长动态、日记 / VLOG、讨论与通知审核通过前不能转达或公开。"))
        }
        if items.contains(where: \.pressureLanguageRisk) {
            findings.append(guardianFinding(.pressureLanguageRisk,
                "存在羞辱 / 攀比 / 压力 / 催促措辞，需脱压改写后再转达，孩子端不显示原文。"))
        }
        if items.contains(where: \.rewardPromiseRisk) {
            findings.append(guardianFinding(.rewardPromiseRisk,
                "存在奖励承诺诱导，需移除，孩子端不显示奖励承诺。"))
        }
        if items.contains(where: \.creditAmountLeakRisk) {
            findings.append(guardianFinding(.creditAmountLeakRisk,
                "反馈提及成长积分数额，需移除具体数值，孩子端不显示成长积分数值。"))
        }
        if items.contains(where: \.diaryVlogContinuityGap) {
            findings.append(guardianFinding(.diaryVlogContinuityGap,
                "成长日记 / VLOG 连续片段可能拼出学校 / 位置，需审核与脱敏。"))
        }
        if items.contains(where: \.notificationEmotionalSafetyRisk) {
            findings.append(guardianFinding(.notificationEmotionalSafetyRisk,
                "通知预览含压力 / 催促措辞，发送前需脱压改写。"))
        }
        if items.contains(where: \.expertDiscussionLeakRisk) {
            findings.append(guardianFinding(.expertDiscussionLeakRisk,
                "家长 / 家庭讨论不得泄露给专家视图，专家只看通用主题边界。"))
        }
        if items.contains(where: \.crossChildLeakRisk) {
            findings.append(guardianFinding(.crossChildLeakRisk,
                "存在跨孩子内容，需移除其他孩子的可识别信息。"))
        }
        if items.contains(where: \.relativeOverscope) {
            findings.append(guardianFinding(.relativeOverscope,
                "存在超出已授权亲友范围的可见反馈，需重新限定授权范围后再恢复。"))
        }
        if items.contains(where: \.minimalDisclosureRisk) {
            findings.append(guardianFinding(.minimalDisclosureRisk,
                "存在可进一步最小披露的内容，需收敛到必要范围。"))
        }
        if items.contains(where: \.publicSummaryLeakRisk) {
            findings.append(guardianFinding(.publicSummaryLeak,
                "公开摘要可能泄露内部编号、凭证、路径、来源标识或讨论记录，需最小披露。"))
        }
        return findings
    }

    private func finding(
        _ code: MobileFamilySocialFeedbackEmotionalSafetyCenterFindingCode,
        child: String,
        guardian: String,
        actionRequired: Bool,
        role: MobileFamilySocialFeedbackEmotionalSafetyCenterRole
    ) -> MobileFamilySocialFeedbackEmotionalSafetyCenterFinding {
        MobileFamilySocialFeedbackEmotionalSafetyCenterFinding(
            code: code,
            message: role == .guardian ? guardian : child,
            actionRequired: actionRequired,
            visibleToChild: true,
            visibleToRelative: false,
            visibleToExpert: false
        )
    }

    private func guardianFinding(
        _ code: MobileFamilySocialFeedbackEmotionalSafetyCenterFindingCode,
        _ message: String
    ) -> MobileFamilySocialFeedbackEmotionalSafetyCenterFinding {
        MobileFamilySocialFeedbackEmotionalSafetyCenterFinding(
            code: code,
            message: message,
            actionRequired: true,
            visibleToChild: false,
            visibleToRelative: false,
            visibleToExpert: false
        )
    }

    private func summary(
        role: MobileFamilySocialFeedbackEmotionalSafetyCenterRole,
        allItems: [MobileFamilySocialFeedbackEmotionalSafetyCenterItem],
        visibleItems: [MobileFamilySocialFeedbackEmotionalSafetyCenterItem],
        findings: [MobileFamilySocialFeedbackEmotionalSafetyCenterFinding]
    ) -> MobileFamilySocialFeedbackEmotionalSafetyCenterPublicSummary {
        let exposesGuardianReviewCounts = role == .guardian

        return MobileFamilySocialFeedbackEmotionalSafetyCenterPublicSummary(
            role: role,
            itemCount: exposesGuardianReviewCounts ? allItems.count : visibleItems.count,
            visibleItemCount: visibleItems.count,
            gentleSupportCount: visibleItems.filter { $0.status == .gentleSupport || $0.status == .relativeVisible }.count,
            waitingReviewCount: visibleItems.filter { $0.status == .waitingReview }.count,
            moderationRequiredCount: exposesGuardianReviewCounts ? visibleItems.filter(\.moderationRequired).count : 0,
            revokedCount: exposesGuardianReviewCounts ? visibleItems.filter(\.isRevoked).count : 0,
            removedCount: exposesGuardianReviewCounts ? visibleItems.filter(\.isRemoved).count : 0,
            relativeVisibleCount: visibleItems.filter { $0.status == .relativeVisible }.count,
            blockedCount: exposesGuardianReviewCounts ? visibleItems.filter(\.isBlocked).count : 0,
            guardianConsentMissingCount: exposesGuardianReviewCounts ? visibleItems.filter(\.guardianConsentMissing).count : 0,
            childAssentMissingCount: exposesGuardianReviewCounts ? visibleItems.filter(\.childAssentMissing).count : 0,
            pressureLanguageRiskCount: exposesGuardianReviewCounts ? visibleItems.filter(\.pressureLanguageRisk).count : 0,
            rewardPromiseRiskCount: exposesGuardianReviewCounts ? visibleItems.filter(\.rewardPromiseRisk).count : 0,
            creditAmountLeakRiskCount: exposesGuardianReviewCounts ? visibleItems.filter(\.creditAmountLeakRisk).count : 0,
            expertDiscussionLeakRiskCount: exposesGuardianReviewCounts ? visibleItems.filter(\.expertDiscussionLeakRisk).count : 0,
            crossChildLeakRiskCount: exposesGuardianReviewCounts ? visibleItems.filter(\.crossChildLeakRisk).count : 0,
            continuityGapCount: exposesGuardianReviewCounts ? visibleItems.filter(\.diaryVlogContinuityGap).count : 0,
            notificationRiskCount: exposesGuardianReviewCounts ? visibleItems.filter(\.notificationEmotionalSafetyRisk).count : 0,
            minimalDisclosureRiskCount: exposesGuardianReviewCounts ? visibleItems.filter(\.minimalDisclosureRisk).count : 0,
            relativeOverscopeCount: exposesGuardianReviewCounts ? visibleItems.filter(\.relativeOverscope).count : 0,
            findingCodes: exposesGuardianReviewCounts ? findings.map(\.code) : []
        )
    }

    private func publicRef(_ seed: String) -> String {
        "fse-\(Self.stableHash("\(Self.redactionSalt):\(seed)"))"
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
