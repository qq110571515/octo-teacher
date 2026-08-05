import Foundation

/// iOS 荣誉墙徽章故事线发布预览的纯本地只读投影。
///
/// 这一层把 B84「荣誉墙徽章故事线发布同意审计」的领域语义投影到 iOS：徽章、能力卡、
/// 创作作品、成长日记、VLOG、励志故事线和亲友鼓励在进入荣誉墙 / 亲友可见区前，
/// 是否具备家长同意（guardian consent）、孩子 assent、内容审核，以及撤回 / 删除 / 下架
/// 是否已回滚、亲友授权范围是否越界、故事线是否拼出敏感信息、公开摘要是否泄露内部字段。
///
/// 它只生成展示模型，绝不真实发布荣誉墙、授徽章、更新能力卡、上传媒体、通知亲友、
/// 写账本、发成长积分 / 扣成长积分、兑换奖励，也不控制设备或屏幕时间。
///
/// 孩子视角只看温和的发布候选状态、等待家长 / 老师确认、需审核 / 已撤回 / 已下架提示和下一步；
/// 家长视角只读查看证据缺口、guardian consent、child assent、内容审核、撤回 / 删除 / 下架回滚、
/// 亲友授权范围、敏感故事线和公开摘要泄露风险；亲友视角只看已同意且授权范围内的鼓励预览。

/// 预览视角。rawValue 只是安全枚举，不携带真实 child/family/guardian/relative 身份。
enum MobileHonorWallBadgeStorylinePublicationPreviewRole: String, CaseIterable, Equatable {
    case child
    case guardian
    case relative

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        case .relative: return "亲友"
        }
    }
}

/// 发布候选来源。映射 B84 的 sourceKind，rawValue 不携带真实 badge/card/story/media。
enum MobileHonorWallBadgeStorylinePublicationPreviewSourceKind: String, CaseIterable, Equatable {
    case badge = "badge_candidate"
    case abilityCard = "ability_card_candidate"
    case creativeWork = "creative_work_candidate"
    case growthDiary = "growth_diary_candidate"
    case vlog = "vlog_candidate"
    case storyline = "storyline_candidate"
    case relativeEncouragement = "relative_encouragement_candidate"

    var title: String {
        switch self {
        case .badge: return "徽章发布候选"
        case .abilityCard: return "能力卡发布候选"
        case .creativeWork: return "创作作品发布候选"
        case .growthDiary: return "成长日记发布候选"
        case .vlog: return "成长 VLOG 发布候选"
        case .storyline: return "励志故事线发布候选"
        case .relativeEncouragement: return "亲友鼓励可见候选"
        }
    }
}

/// 发布候选状态。孩子看到的都是温和措辞。
enum MobileHonorWallBadgeStorylinePublicationPreviewStatus: String, Equatable {
    case publicationCandidate = "publication_candidate"
    case waitingConsent = "waiting_consent"
    case needsModeration = "needs_moderation"
    case revoked
    case takenDown = "taken_down"
    case relativeVisible = "relative_visible"
    case onHold = "on_hold"

    var label: String {
        switch self {
        case .publicationCandidate: return "发布候选"
        case .waitingConsent: return "等确认"
        case .needsModeration: return "需审核"
        case .revoked: return "已撤回"
        case .takenDown: return "已下架"
        case .relativeVisible: return "亲友可见"
        case .onHold: return "先暂停"
        }
    }
}

/// 安全 finding 码。前缀语义与 B84 的发布审计码一一对应，但仅供 iOS 展示，不回显原始字段。
enum MobileHonorWallBadgeStorylinePublicationPreviewFindingCode: String, Equatable {
    case readOnlyPreview = "READ_ONLY_PREVIEW"
    case waitingConfirmation = "WAITING_CONFIRMATION"
    case contentUnderReview = "CONTENT_UNDER_REVIEW"
    case contentRevoked = "CONTENT_REVOKED"
    case contentTakenDown = "CONTENT_TAKEN_DOWN"
    case publicationOnHold = "PUBLICATION_ON_HOLD"
    case relativeScopeApplied = "RELATIVE_SCOPE_APPLIED"
    case guardianConsentMissing = "GUARDIAN_CONSENT_MISSING"
    case childAssentMissing = "CHILD_ASSENT_MISSING"
    case moderationRequired = "MODERATION_REQUIRED"
    case revokedStillVisible = "REVOKED_CONTENT_STILL_VISIBLE"
    case deletedNotRolledBack = "DELETED_OR_TAKEDOWN_NOT_ROLLED_BACK"
    case relativeOverscope = "RELATIVE_OVERSCOPE_VISIBLE"
    case storylineSensitiveLeak = "STORYLINE_SENSITIVE_CONTEXT_LEAK"
    case publicSummaryLeak = "PUBLIC_SUMMARY_SENSITIVE_LEAK"
    case duplicateNotCollapsed = "DUPLICATE_PUBLICATION_NOT_COLLAPSED"
    case sideEffectBlocked = "REAL_SIDE_EFFECT_BLOCKED"
    case unsafePayloadBlocked = "UNSAFE_PAYLOAD_BLOCKED"
}

/// 单条发布候选。所有副作用标记恒为 false。
struct MobileHonorWallBadgeStorylinePublicationPreviewCandidate: Identifiable, Equatable {
    var publicPreviewRef: String
    var sourceKind: MobileHonorWallBadgeStorylinePublicationPreviewSourceKind
    var status: MobileHonorWallBadgeStorylinePublicationPreviewStatus
    var title: String
    var summary: String
    var gapReason: String
    var nextStep: String
    var safetyNote: String
    var visibleToChild: Bool
    var visibleToGuardian: Bool
    var visibleToRelative: Bool
    // 发布前置条件缺口（家长可见的内部判断，不向孩子/亲友泄露原因）。
    var guardianConsentMissing: Bool
    var childAssentMissing: Bool
    var moderationRequired: Bool
    var isRevoked: Bool
    var isTakenDown: Bool
    var needsRollback: Bool
    var relativeOverscope: Bool
    var storylineSensitiveLeakRisk: Bool
    var publicSummaryLeakRisk: Bool
    var duplicateNotCollapsed: Bool
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
    let reviewsCreativeWork = false
    let notifiesRelatives = false
    let unlocksDevice = false
    let controlsScreenTime = false
    let sendsNotification = false
    let submitsProof = false

    var id: String { publicPreviewRef }

    var isBlocked: Bool {
        status == .onHold || isRevoked || isTakenDown || needsRollback || relativeOverscope
    }

    var displayValues: [String] {
        [
            publicPreviewRef,
            sourceKind.rawValue,
            sourceKind.title,
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
            || updatesAbilityCard || publishesHonorWall || publishesContent || reviewsCreativeWork
            || notifiesRelatives || unlocksDevice || controlsScreenTime || sendsNotification || submitsProof
    }
}

struct MobileHonorWallBadgeStorylinePublicationPreviewFinding: Identifiable, Equatable {
    var code: MobileHonorWallBadgeStorylinePublicationPreviewFindingCode
    var message: String
    var actionRequired: Bool
    var visibleToChild: Bool
    var visibleToRelative: Bool

    var id: String { code.rawValue }
    var displayValues: [String] { [code.rawValue, message] }
}

struct MobileHonorWallBadgeStorylinePublicationPreviewPublicSummary: Equatable {
    var role: MobileHonorWallBadgeStorylinePublicationPreviewRole
    var candidateCount: Int
    var visibleCandidateCount: Int
    var publicationCandidateCount: Int
    var waitingConsentCount: Int
    var moderationRequiredCount: Int
    var revokedCount: Int
    var takenDownCount: Int
    var relativeVisibleCount: Int
    var blockedCount: Int
    var guardianConsentMissingCount: Int
    var childAssentMissingCount: Int
    var relativeOverscopeCount: Int
    var storylineLeakRiskCount: Int
    var publicSummaryLeakRiskCount: Int
    var duplicateCount: Int
    var findingCodes: [MobileHonorWallBadgeStorylinePublicationPreviewFindingCode]

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
    let reviewsCreativeWork = false
    let notifiesRelatives = false
    let unlocksDevice = false
    let controlsScreenTime = false
    let sendsNotification = false
    let submitsProof = false

    var hasTriggeredSideEffect: Bool {
        callsNetwork || callsAiProvider || callsLocalModel || callsLms || writesSchoolSystem
            || opensExternalLink || opensCamera || opensPhotoLibrary || opensFilePicker || uploadsMedia
            || writesLedger || grantsCredit || spendsCredit || fulfillsReward || grantsBadge
            || updatesAbilityCard || publishesHonorWall || publishesContent || reviewsCreativeWork
            || notifiesRelatives || unlocksDevice || controlsScreenTime || sendsNotification || submitsProof
    }
}

struct MobileHonorWallBadgeStorylinePublicationPreview: Equatable {
    var role: MobileHonorWallBadgeStorylinePublicationPreviewRole
    var title: String
    var subtitle: String
    var audienceNote: String
    var candidates: [MobileHonorWallBadgeStorylinePublicationPreviewCandidate]
    var findings: [MobileHonorWallBadgeStorylinePublicationPreviewFinding]
    var publicSummary: MobileHonorWallBadgeStorylinePublicationPreviewPublicSummary

    var displayValues: [String] {
        [role.rawValue, title, subtitle, audienceNote]
            + candidates.flatMap(\.displayValues)
            + findings.flatMap(\.displayValues)
    }

    var hasUnsafeDisplayPayload: Bool {
        MobileHonorWallBadgeStorylinePublicationPreviewBuilder.hasUnsafeDisplayPayload(displayValues)
    }
}

struct MobileHonorWallBadgeStorylinePublicationPreviewInput: Equatable {
    var generatedAt: String
    var unsafePayload: String?

    static let mock = MobileHonorWallBadgeStorylinePublicationPreviewInput(
        generatedAt: "2026-06-25T02:00:00.000Z",
        unsafePayload: nil
    )
}

struct MobileHonorWallBadgeStorylinePublicationPreviewBuilder {
    private static let redactionSalt = "mobile-honor-wall-badge-storyline-publication-preview-v1"
    private static let sensitiveMarkers = [
        "child:", "family:", "school:", "teacher:", "guardian:", "relative:", "creator:",
        "proof:", "media:", "photo:", "screenshot:", "transcript", "answer key", "answerkey",
        "答案键", "provider:", "model:", "resource:", "link:", "url:", "homework:", "quiz:",
        "badge:", "card:", "ability:", "story:", "storyline:", "honor:", "pack:", "reward:",
        "order:", "inventory:", "ledger:", "device:", "entitlement:", "publicref", "adultreason",
        "adult reason", "internalref", "internal ref", "ref:", "task:", "taskid", "claim:", "claimid",
        "token", "api_key", "apikey", "secret", "credit amount", "成长积分金额", "账本明细", "设备命令",
        "家长预算", "复核策略", "发布策略", "http://", "https://", "file://", "/users/", "/volumes/",
        "child_real", "family_real", "proof_real", "badge_real", "card_real", "story_real", "192.168.", ".local"
    ]

    func build(
        role: MobileHonorWallBadgeStorylinePublicationPreviewRole,
        input: MobileHonorWallBadgeStorylinePublicationPreviewInput = .mock
    ) -> MobileHonorWallBadgeStorylinePublicationPreview {
        if let unsafePayload = input.unsafePayload, Self.hasUnsafeDisplayPayload([unsafePayload]) {
            return blockedPreview(role: role)
        }

        let allCandidates = makeCandidates(for: role)
        let visibleCandidates = allCandidates
            .filter { isVisible($0, to: role) }
            .sorted { left, right in
                if left.sortOrder == right.sortOrder {
                    return left.publicPreviewRef < right.publicPreviewRef
                }
                return left.sortOrder < right.sortOrder
            }

        let findings = makeFindings(role: role, candidates: visibleCandidates)

        return MobileHonorWallBadgeStorylinePublicationPreview(
            role: role,
            title: title(for: role),
            subtitle: subtitle(for: role),
            audienceNote: audienceNote(for: role),
            candidates: visibleCandidates,
            findings: findings,
            publicSummary: summary(
                role: role,
                allCandidates: allCandidates,
                visibleCandidates: visibleCandidates,
                findings: findings
            )
        )
    }

    static func hasUnsafeDisplayPayload(_ values: [String]) -> Bool {
        let joined = values.joined(separator: " ").lowercased()
        return sensitiveMarkers.contains { joined.contains($0) }
    }

    private func isVisible(
        _ candidate: MobileHonorWallBadgeStorylinePublicationPreviewCandidate,
        to role: MobileHonorWallBadgeStorylinePublicationPreviewRole
    ) -> Bool {
        switch role {
        case .child: return candidate.visibleToChild
        case .guardian: return candidate.visibleToGuardian
        case .relative: return candidate.visibleToRelative
        }
    }

    private func title(for role: MobileHonorWallBadgeStorylinePublicationPreviewRole) -> String {
        switch role {
        case .child: return "想公开的内容现在到哪一步了"
        case .guardian: return "荣誉墙发布同意预览复核"
        case .relative: return "可以看到的鼓励内容"
        }
    }

    private func subtitle(for role: MobileHonorWallBadgeStorylinePublicationPreviewRole) -> String {
        switch role {
        case .child:
            return "把想放到荣誉墙或分享给亲友的内容放在一起看；这里只读，不会真的公开、发徽章或通知亲友。"
        case .guardian:
            return "只读复核证据缺口、家长同意、孩子 assent、内容审核、撤回 / 删除 / 下架回滚、亲友授权范围、敏感故事线和公开摘要泄露风险。"
        case .relative:
            return "只看孩子和家长都已同意、且授权给你的鼓励内容；看不到未公开、审核中或被撤回的内容。"
        }
    }

    private func audienceNote(for role: MobileHonorWallBadgeStorylinePublicationPreviewRole) -> String {
        switch role {
        case .child:
            return "这里只看发布候选状态和下一步；真正公开、授徽章和通知亲友都要等家长或老师确认。"
        case .guardian:
            return "这里只读整理发布前置条件；真正发布荣誉墙、授徽章、更新能力卡和通知亲友仍走正式流程。"
        case .relative:
            return "你只读看到被授权的鼓励内容；不能看到内部原因、原始媒体或其他孩子的内容。"
        }
    }

    private func blockedPreview(
        role: MobileHonorWallBadgeStorylinePublicationPreviewRole
    ) -> MobileHonorWallBadgeStorylinePublicationPreview {
        let finding = MobileHonorWallBadgeStorylinePublicationPreviewFinding(
            code: .unsafePayloadBlocked,
            message: "预览发现不安全字段，已隐藏全部发布候选，等待家长在正式流程复核。",
            actionRequired: true,
            visibleToChild: true,
            visibleToRelative: true
        )
        return MobileHonorWallBadgeStorylinePublicationPreview(
            role: role,
            title: title(for: role),
            subtitle: "内容已安全隐藏；本地页面不会继续展示原始字段。",
            audienceNote: role == .child
                ? "先不用着急，等家长确认后再继续。"
                : "请回正式复核流程查看原因；本页不显示原始字段。",
            candidates: [],
            findings: [finding],
            publicSummary: MobileHonorWallBadgeStorylinePublicationPreviewPublicSummary(
                role: role,
                candidateCount: 0,
                visibleCandidateCount: 0,
                publicationCandidateCount: 0,
                waitingConsentCount: 0,
                moderationRequiredCount: 0,
                revokedCount: 0,
                takenDownCount: 0,
                relativeVisibleCount: 0,
                blockedCount: 1,
                guardianConsentMissingCount: 0,
                childAssentMissingCount: 0,
                relativeOverscopeCount: 0,
                storylineLeakRiskCount: 0,
                publicSummaryLeakRiskCount: 0,
                duplicateCount: 0,
                findingCodes: [.unsafePayloadBlocked]
            )
        )
    }

    private func makeCandidates(
        for role: MobileHonorWallBadgeStorylinePublicationPreviewRole
    ) -> [MobileHonorWallBadgeStorylinePublicationPreviewCandidate] {
        [
            // 徽章：缺家长同意，等确认。孩子、家长可见；亲友不可见。
            candidate(
                sourceKind: .badge,
                role: role,
                status: .waitingConsent,
                childSummary: "你的徽章想放到荣誉墙，公开前要先等家长同意。",
                guardianSummary: "徽章发布候选缺少家长同意（guardian consent）；未同意前不能发布或授徽章。",
                gapReason: role == .child ? "还要等家长点头同意。" : "缺少家长同意，未达发布前置条件。",
                childNextStep: "先保存，等家长一起看再决定要不要公开。",
                guardianNextStep: "确认家长同意、可见范围与最小披露后，再进入正式发布流程。",
                safetyNote: "不发布荣誉墙、不授徽章、不通知亲友。",
                sortOrder: 10,
                visibleToChild: true, visibleToGuardian: true, visibleToRelative: false,
                guardianConsentMissing: true
            ),
            // 能力卡：缺孩子 assent，等确认。
            candidate(
                sourceKind: .abilityCard,
                role: role,
                status: .waitingConsent,
                childSummary: "能力卡想展示出来，要先问你自己同不同意。",
                guardianSummary: "能力卡发布候选缺少孩子 assent；孩子未同意前不能公开或更新能力卡。",
                gapReason: role == .child ? "想听听你自己愿不愿意公开。" : "缺少孩子 assent，未达公开前置条件。",
                childNextStep: "想清楚愿不愿意展示，再和家长说。",
                guardianNextStep: "确认孩子 assent 真实自愿，再考虑是否公开。",
                safetyNote: "不更新能力卡、不发布、不通知亲友。",
                sortOrder: 20,
                visibleToChild: true, visibleToGuardian: true, visibleToRelative: false,
                childAssentMissing: true
            ),
            // 创作作品：缺内容审核，需审核。
            candidate(
                sourceKind: .creativeWork,
                role: role,
                status: .needsModeration,
                childSummary: "你的作品要先做一次安全检查，才能放到荣誉墙。",
                guardianSummary: "创作作品发布候选未通过内容审核；审核通过前不能进入荣誉墙或亲友可见。",
                gapReason: role == .child ? "作品还要做一次安全检查。" : "内容审核未通过，存在未审核创作。",
                childNextStep: "先把作品保存好，等大人看过再分享。",
                guardianNextStep: "确认创作已通过内容审核、未含敏感信息后再放行。",
                safetyNote: "不发布、不公开作品、不通知亲友。",
                sortOrder: 30,
                visibleToChild: true, visibleToGuardian: true, visibleToRelative: false,
                moderationRequired: true
            ),
            // 成长日记：已撤回但仍可能展示，需回滚。
            candidate(
                sourceKind: .growthDiary,
                role: role,
                status: .revoked,
                childSummary: "这篇成长日记已经收回了，先不会展示给别人。",
                guardianSummary: "成长日记同意已撤回，但旧展示尚未回滚；撤回后必须立即下线并回滚传播。",
                gapReason: role == .child ? "这篇先收起来了。" : "同意已撤回，撤回内容仍可能可见，需回滚。",
                childNextStep: "不用担心，想公开时可以重新和家长说。",
                guardianNextStep: "确认撤回已生效、旧链路与公开摘要已回滚后再处理。",
                safetyNote: "不恢复展示、不通知亲友、不公开。",
                sortOrder: 40,
                visibleToChild: true, visibleToGuardian: true, visibleToRelative: false,
                isRevoked: true,
                needsRollback: true
            ),
            // VLOG：已删除/下架但未回滚徽章与展示。
            candidate(
                sourceKind: .vlog,
                role: role,
                status: .takenDown,
                childSummary: "这个成长 VLOG 已经下架了，先不会出现在荣誉墙。",
                guardianSummary: "成长 VLOG 已删除 / 下架，但徽章与荣誉墙展示尚未回滚；需回滚后再确认。",
                gapReason: role == .child ? "这个视频先下架了。" : "删除 / 下架未回滚徽章与荣誉墙展示。",
                childNextStep: "先做下一件事，想分享时再和家长商量。",
                guardianNextStep: "确认删除 / 下架已回滚徽章、能力卡和荣誉墙展示后再放行。",
                safetyNote: "不发布、不授徽章、不通知亲友。",
                sortOrder: 50,
                visibleToChild: true, visibleToGuardian: true, visibleToRelative: false,
                isTakenDown: true,
                needsRollback: true
            ),
            // 故事线：拼接敏感信息风险 + 公开摘要泄露风险，需审核。
            candidate(
                sourceKind: .storyline,
                role: role,
                status: .needsModeration,
                childSummary: "你的励志故事线很棒，公开前要先做一次安全检查。",
                guardianSummary: "励志故事线存在拼出学校 / 家庭敏感信息风险，且公开摘要可能泄露内部字段，需审核与脱敏。",
                gapReason: role == .child ? "故事还要做一次安全检查。" : "故事线敏感信息拼合风险 + 公开摘要泄露风险。",
                childNextStep: "先把亮点记下来，等大人看过再分享。",
                guardianNextStep: "复核故事线是否泄露学校 / 家庭信息，确认公开摘要已最小披露。",
                safetyNote: "不发布故事线、不拼接敏感信息、不公开位置。",
                sortOrder: 60,
                visibleToChild: true, visibleToGuardian: true, visibleToRelative: false,
                moderationRequired: true,
                storylineSensitiveLeakRisk: true,
                publicSummaryLeakRisk: true,
                duplicateNotCollapsed: true
            ),
            // 亲友鼓励（已同意、授权范围内）：唯一对亲友可见的候选。
            candidate(
                sourceKind: .relativeEncouragement,
                role: role,
                status: .relativeVisible,
                childSummary: "家人已经同意，亲友可以看到这条鼓励内容啦。",
                guardianSummary: "亲友鼓励候选已具备家长同意、孩子 assent 与内容审核，且在授权范围内，可对授权亲友可见。",
                gapReason: "",
                childNextStep: "继续记录你的成长亮点。",
                guardianNextStep: "确认授权范围未扩大、内容保持最小披露即可。",
                safetyNote: "不通知亲友、不公开对外、不授徽章。",
                sortOrder: 70,
                visibleToChild: true, visibleToGuardian: true, visibleToRelative: true
            ),
            // 亲友鼓励（越权）：家长可见的风险候选，亲友看不到。
            candidate(
                sourceKind: .relativeEncouragement,
                role: role,
                status: .onHold,
                childSummary: "",
                guardianSummary: "另一条亲友鼓励候选超出已授权亲友范围；越权可见已暂停，需重新限定授权范围。",
                gapReason: "",
                childNextStep: "",
                guardianNextStep: "确认亲友授权范围、撤回越权可见后再恢复。",
                safetyNote: "不恢复可见、不通知亲友、不扩大授权。",
                sortOrder: 80,
                visibleToChild: false, visibleToGuardian: true, visibleToRelative: false,
                relativeOverscope: true
            )
        ]
    }

    private func candidate(
        sourceKind: MobileHonorWallBadgeStorylinePublicationPreviewSourceKind,
        role: MobileHonorWallBadgeStorylinePublicationPreviewRole,
        status: MobileHonorWallBadgeStorylinePublicationPreviewStatus,
        childSummary: String,
        guardianSummary: String,
        gapReason: String,
        childNextStep: String,
        guardianNextStep: String,
        safetyNote: String,
        sortOrder: Int,
        visibleToChild: Bool,
        visibleToGuardian: Bool,
        visibleToRelative: Bool,
        guardianConsentMissing: Bool = false,
        childAssentMissing: Bool = false,
        moderationRequired: Bool = false,
        isRevoked: Bool = false,
        isTakenDown: Bool = false,
        needsRollback: Bool = false,
        relativeOverscope: Bool = false,
        storylineSensitiveLeakRisk: Bool = false,
        publicSummaryLeakRisk: Bool = false,
        duplicateNotCollapsed: Bool = false
    ) -> MobileHonorWallBadgeStorylinePublicationPreviewCandidate {
        let summary: String
        switch role {
        case .child: summary = childSummary
        case .guardian: summary = guardianSummary
        case .relative: summary = childSummary
        }
        let nextStep = role == .guardian ? guardianNextStep : childNextStep
        return MobileHonorWallBadgeStorylinePublicationPreviewCandidate(
            publicPreviewRef: publicRef("candidate:\(sourceKind.rawValue):\(role.rawValue):\(sortOrder)"),
            sourceKind: sourceKind,
            status: status,
            title: sourceKind.title,
            summary: summary,
            gapReason: gapReason,
            nextStep: nextStep,
            safetyNote: safetyNote,
            visibleToChild: visibleToChild,
            visibleToGuardian: visibleToGuardian,
            visibleToRelative: visibleToRelative,
            guardianConsentMissing: guardianConsentMissing,
            childAssentMissing: childAssentMissing,
            moderationRequired: moderationRequired,
            isRevoked: isRevoked,
            isTakenDown: isTakenDown,
            needsRollback: needsRollback,
            relativeOverscope: relativeOverscope,
            storylineSensitiveLeakRisk: storylineSensitiveLeakRisk,
            publicSummaryLeakRisk: publicSummaryLeakRisk,
            duplicateNotCollapsed: duplicateNotCollapsed,
            sortOrder: sortOrder
        )
    }

    private func makeFindings(
        role: MobileHonorWallBadgeStorylinePublicationPreviewRole,
        candidates: [MobileHonorWallBadgeStorylinePublicationPreviewCandidate]
    ) -> [MobileHonorWallBadgeStorylinePublicationPreviewFinding] {
        var findings = [
            MobileHonorWallBadgeStorylinePublicationPreviewFinding(
                code: .readOnlyPreview,
                message: "预览只读整理发布前置条件，不会发布荣誉墙、授徽章、更新能力卡、通知亲友或发成长积分。",
                actionRequired: false,
                visibleToChild: true,
                visibleToRelative: true
            )
        ]

        // 孩子 / 亲友也能看到的温和状态提示。
        if candidates.contains(where: { $0.guardianConsentMissing || $0.childAssentMissing }) {
            findings.append(finding(.waitingConfirmation,
                child: "有内容要等家长或你自己确认同意后才能公开。",
                guardian: "存在缺少同意 / assent 的候选，确认前不能公开。",
                actionRequired: true, role: role, visibleToChild: true, visibleToRelative: false))
        }
        if candidates.contains(where: \.moderationRequired) {
            findings.append(finding(.contentUnderReview,
                child: "有内容正在做安全检查，检查通过后才能分享。",
                guardian: "存在未通过内容审核的候选，审核前不能进入荣誉墙或亲友可见。",
                actionRequired: true, role: role, visibleToChild: true, visibleToRelative: false))
        }
        if candidates.contains(where: \.isRevoked) {
            findings.append(finding(.contentRevoked,
                child: "有内容已经收回，先不会展示给别人。",
                guardian: "存在已撤回的候选，需确认撤回已生效并回滚旧展示。",
                actionRequired: true, role: role, visibleToChild: true, visibleToRelative: false))
        }
        if candidates.contains(where: \.isTakenDown) {
            findings.append(finding(.contentTakenDown,
                child: "有内容已经下架，先不会出现在荣誉墙。",
                guardian: "存在已删除 / 下架的候选，需确认徽章与展示已回滚。",
                actionRequired: true, role: role, visibleToChild: true, visibleToRelative: false))
        }
        if candidates.contains(where: \.isBlocked) {
            findings.append(finding(.publicationOnHold,
                child: "有些内容先暂停发布，等大人确认后再继续，你可以先做下一步。",
                guardian: "有候选处于暂停状态，需正式复核后再放行。",
                actionRequired: true, role: role, visibleToChild: true, visibleToRelative: false))
        }

        if role == .relative {
            // 亲友只看到只读说明 + 授权范围提示，不看到任何内部原因。
            findings.append(MobileHonorWallBadgeStorylinePublicationPreviewFinding(
                code: .relativeScopeApplied,
                message: "你只看到家人已同意并授权给你的鼓励内容；未公开、审核中或被撤回的内容不会出现。",
                actionRequired: false,
                visibleToChild: false,
                visibleToRelative: true
            ))
            return findings.filter(\.visibleToRelative)
        }

        guard role == .guardian else {
            return findings.filter(\.visibleToChild)
        }

        // 家长专属的发布前置条件 / 风险 findings。
        if candidates.contains(where: \.guardianConsentMissing) {
            findings.append(guardianFinding(.guardianConsentMissing,
                "缺少家长同意（guardian consent），未达发布前置条件。"))
        }
        if candidates.contains(where: \.childAssentMissing) {
            findings.append(guardianFinding(.childAssentMissing,
                "缺少孩子 assent，孩子未自愿同意前不能公开。"))
        }
        if candidates.contains(where: \.moderationRequired) {
            findings.append(guardianFinding(.moderationRequired,
                "创作与故事线通过内容审核前不能进入荣誉墙或亲友可见。"))
        }
        if candidates.contains(where: \.needsRollback) {
            findings.append(guardianFinding(.deletedNotRolledBack,
                "删除 / 下架 / 撤回后必须回滚徽章、能力卡、荣誉墙展示与公开摘要。"))
        }
        if candidates.contains(where: \.isRevoked) {
            findings.append(guardianFinding(.revokedStillVisible,
                "同意撤回后，撤回内容不得仍可见，需立即下线旧展示。"))
        }
        if candidates.contains(where: \.relativeOverscope) {
            findings.append(guardianFinding(.relativeOverscope,
                "存在超出授权亲友范围的可见候选，需重新限定授权范围后再恢复。"))
        }
        if candidates.contains(where: \.storylineSensitiveLeakRisk) {
            findings.append(guardianFinding(.storylineSensitiveLeak,
                "故事线存在拼出学校 / 家庭敏感信息风险，需审核与脱敏。"))
        }
        if candidates.contains(where: \.publicSummaryLeakRisk) {
            findings.append(guardianFinding(.publicSummaryLeak,
                "公开摘要可能泄露内部编号、凭证、路径、来源标识或对话记录等字段，需最小披露。"))
        }
        if candidates.contains(where: \.duplicateNotCollapsed) {
            findings.append(guardianFinding(.duplicateNotCollapsed,
                "存在重复发布候选未折叠，需去重后再发布。"))
        }
        return findings
    }

    private func finding(
        _ code: MobileHonorWallBadgeStorylinePublicationPreviewFindingCode,
        child: String,
        guardian: String,
        actionRequired: Bool,
        role: MobileHonorWallBadgeStorylinePublicationPreviewRole,
        visibleToChild: Bool,
        visibleToRelative: Bool
    ) -> MobileHonorWallBadgeStorylinePublicationPreviewFinding {
        MobileHonorWallBadgeStorylinePublicationPreviewFinding(
            code: code,
            message: role == .guardian ? guardian : child,
            actionRequired: actionRequired,
            visibleToChild: visibleToChild,
            visibleToRelative: visibleToRelative
        )
    }

    private func guardianFinding(
        _ code: MobileHonorWallBadgeStorylinePublicationPreviewFindingCode,
        _ message: String
    ) -> MobileHonorWallBadgeStorylinePublicationPreviewFinding {
        MobileHonorWallBadgeStorylinePublicationPreviewFinding(
            code: code,
            message: message,
            actionRequired: true,
            visibleToChild: false,
            visibleToRelative: false
        )
    }

    private func summary(
        role: MobileHonorWallBadgeStorylinePublicationPreviewRole,
        allCandidates: [MobileHonorWallBadgeStorylinePublicationPreviewCandidate],
        visibleCandidates: [MobileHonorWallBadgeStorylinePublicationPreviewCandidate],
        findings: [MobileHonorWallBadgeStorylinePublicationPreviewFinding]
    ) -> MobileHonorWallBadgeStorylinePublicationPreviewPublicSummary {
        MobileHonorWallBadgeStorylinePublicationPreviewPublicSummary(
            role: role,
            candidateCount: allCandidates.count,
            visibleCandidateCount: visibleCandidates.count,
            publicationCandidateCount: visibleCandidates.filter { $0.status == .publicationCandidate }.count,
            waitingConsentCount: visibleCandidates.filter { $0.status == .waitingConsent }.count,
            moderationRequiredCount: visibleCandidates.filter(\.moderationRequired).count,
            revokedCount: visibleCandidates.filter(\.isRevoked).count,
            takenDownCount: visibleCandidates.filter(\.isTakenDown).count,
            relativeVisibleCount: visibleCandidates.filter { $0.status == .relativeVisible }.count,
            blockedCount: visibleCandidates.filter(\.isBlocked).count,
            guardianConsentMissingCount: visibleCandidates.filter(\.guardianConsentMissing).count,
            childAssentMissingCount: visibleCandidates.filter(\.childAssentMissing).count,
            relativeOverscopeCount: visibleCandidates.filter(\.relativeOverscope).count,
            storylineLeakRiskCount: visibleCandidates.filter(\.storylineSensitiveLeakRisk).count,
            publicSummaryLeakRiskCount: visibleCandidates.filter(\.publicSummaryLeakRisk).count,
            duplicateCount: visibleCandidates.filter(\.duplicateNotCollapsed).count,
            findingCodes: findings.map(\.code)
        )
    }

    private func publicRef(_ seed: String) -> String {
        "hwp-\(Self.stableHash("\(Self.redactionSalt):\(seed)"))"
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
