import Foundation

/// iOS 能力卡回退 / 冻结 / 申诉解释预览的纯本地只读投影（B85 能力卡回退申诉解释审计闭环到 iOS）。
///
/// 这一层把“能力维度回退、能力卡冻结、申诉 / 复核、证据撤回、学校作业退回 / 重提交、
/// 可穿戴异常、创作撤权、公开 / 亲友可见边界和敏感摘要泄露风险”整理成温和的本地解释。
/// 它只生成展示模型，不真实回退能力卡、不降低能力分、不处理申诉、不提交 / 退回作业、
/// 不验证老师、不确认家长、不通知亲友、不写账本、不发 / 扣成长积分、不兑换奖励、
/// 不控制屏幕时间、不解锁设备，也不接网络 / 云 API / AI / 本地模型 / LMS。
///
/// - 孩子视角：只看温和解释和“申诉中 / 等待复核 / 继续努力”的下一步；
///   不显示成人原因、能力评分算法、成长积分金额、账本、设备命令、原始证据或跨孩子内容。
/// - 家长视角：只读查看能力维度回退、冻结、申诉、证据撤回、学校作业退回、可穿戴异常、
///   创作撤权、公开 / 亲友可见边界和敏感摘要泄露风险。
/// - 亲友视角：只看稳定优势和已同意公开的正向成长，不看回退原因 / 申诉状态。
/// - 老师视角：只看学校作业相关退回 / 重提交流程，不看家庭成长积分、设备或亲友内容。

/// 解释预览角色。rawValue 只是安全枚举，不携带真实 child/family/school/teacher/relative。
enum MobileAbilityCardRegressionAppealExplanationPreviewRole: String, CaseIterable, Equatable {
    case child
    case guardian
    case relative
    case teacher

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        case .relative: return "亲友"
        case .teacher: return "老师"
        }
    }
}

/// 解释条目分类。rawValue 只是安全枚举，不携带真实 card/ability/appeal/proof/ref。
enum MobileAbilityCardRegressionAppealExplanationPreviewCategory: String, CaseIterable, Equatable {
    case abilityRegression = "ability_regression"
    case abilityCardFrozen = "ability_card_frozen"
    case appealReview = "appeal_review"
    case evidenceRevoked = "evidence_revoked"
    case schoolHomeworkReturn = "school_homework_return"
    case wearableAnomaly = "wearable_anomaly"
    case creationRevoked = "creation_revoked"
    case visibilityBoundary = "visibility_boundary"
    case sensitiveSummaryRisk = "sensitive_summary_risk"
    case stableStrength = "stable_strength"
    case consentedPublicGrowth = "consented_public_growth"

    var title: String {
        switch self {
        case .abilityRegression: return "能力维度回退"
        case .abilityCardFrozen: return "能力卡冻结"
        case .appealReview: return "申诉 / 复核"
        case .evidenceRevoked: return "证据撤回"
        case .schoolHomeworkReturn: return "学校作业退回 / 重提交"
        case .wearableAnomaly: return "可穿戴异常"
        case .creationRevoked: return "创作撤权"
        case .visibilityBoundary: return "公开 / 亲友可见边界"
        case .sensitiveSummaryRisk: return "敏感摘要泄露风险"
        case .stableStrength: return "稳定优势"
        case .consentedPublicGrowth: return "已同意公开的正向成长"
        }
    }
}

/// 解释条目状态。面向孩子的措辞优先温和。
enum MobileAbilityCardRegressionAppealExplanationPreviewStatus: String, Equatable {
    case appealInProgress = "appeal_in_progress"
    case waitingReview = "waiting_review"
    case keepGoing = "keep_going"
    case onHold = "on_hold"
    case stable = "stable"
    case guardianReview = "guardian_review"
    case teacherReturn = "teacher_return"
    case blocked

    var label: String {
        switch self {
        case .appealInProgress: return "申诉中"
        case .waitingReview: return "等待复核"
        case .keepGoing: return "继续努力"
        case .onHold: return "先暂停"
        case .stable: return "稳定保持"
        case .guardianReview: return "家长复核"
        case .teacherReturn: return "等待重提交"
        case .blocked: return "已隐藏"
        }
    }
}

enum MobileAbilityCardRegressionAppealExplanationPreviewFindingCode: String, Equatable {
    case readOnlyPreview = "READ_ONLY_PREVIEW"
    case keepGoingEncouragement = "KEEP_GOING_ENCOURAGEMENT"
    case appealInProgress = "APPEAL_IN_PROGRESS"
    case waitingReview = "WAITING_REVIEW"
    case abilityReverted = "ABILITY_REVERTED"
    case abilityCardFrozen = "ABILITY_CARD_FROZEN"
    case evidenceRevoked = "EVIDENCE_REVOKED"
    case homeworkReturned = "HOMEWORK_RETURNED"
    case wearableAnomaly = "WEARABLE_ANOMALY"
    case creationRevoked = "CREATION_REVOKED"
    case visibilityBoundary = "VISIBILITY_BOUNDARY"
    case sensitiveSummaryRisk = "SENSITIVE_SUMMARY_RISK"
    case unsafePayloadBlocked = "UNSAFE_PAYLOAD_BLOCKED"
}

/// 单条解释。所有副作用标记恒为 false。
struct MobileAbilityCardRegressionAppealExplanationPreviewEntry: Identifiable, Equatable {
    var publicPreviewRef: String
    var category: MobileAbilityCardRegressionAppealExplanationPreviewCategory
    var status: MobileAbilityCardRegressionAppealExplanationPreviewStatus
    var title: String
    var explanation: String
    var nextStep: String
    var safetyNote: String
    var visibleToChild: Bool
    var visibleToGuardian: Bool
    var visibleToRelative: Bool
    var visibleToTeacher: Bool
    var isAppealing: Bool
    var isWaitingReview: Bool
    var isReverted: Bool
    var isFrozen: Bool
    var evidenceRevoked: Bool
    var homeworkReturned: Bool
    var wearableAnomaly: Bool
    var creationRevoked: Bool
    var visibilityBoundary: Bool
    var leakRisk: Bool
    var sortOrder: Int

    let callsNetwork = false
    let callsAiProvider = false
    let callsLocalModel = false
    let callsLms = false
    let writesSchoolSystem = false
    let opensExternalLink = false
    let revertsAbilityCard = false
    let lowersAbilityScore = false
    let processesAppeal = false
    let revokesEvidence = false
    let returnsHomework = false
    let verifiesTeacher = false
    let confirmsGuardian = false
    let notifiesRelative = false
    let writesLedger = false
    let grantsCredit = false
    let spendsCredit = false
    let fulfillsReward = false
    let controlsScreenTime = false
    let unlocksDevice = false
    let publishesContent = false
    let sendsNotification = false
    let submitsProof = false

    var id: String { publicPreviewRef }

    var isOnHold: Bool {
        status == .blocked || status == .onHold || isFrozen || evidenceRevoked
            || creationRevoked
    }

    var displayValues: [String] {
        [
            publicPreviewRef,
            category.rawValue,
            category.title,
            status.rawValue,
            status.label,
            title,
            explanation,
            nextStep,
            safetyNote
        ]
    }

    var hasTriggeredSideEffect: Bool {
        callsNetwork || callsAiProvider || callsLocalModel || callsLms || writesSchoolSystem
            || opensExternalLink || revertsAbilityCard || lowersAbilityScore || processesAppeal
            || revokesEvidence || returnsHomework || verifiesTeacher || confirmsGuardian
            || notifiesRelative || writesLedger || grantsCredit || spendsCredit || fulfillsReward
            || controlsScreenTime || unlocksDevice || publishesContent || sendsNotification
            || submitsProof
    }
}

struct MobileAbilityCardRegressionAppealExplanationPreviewFinding: Identifiable, Equatable {
    var code: MobileAbilityCardRegressionAppealExplanationPreviewFindingCode
    var message: String
    var actionRequired: Bool
    var visibleToChild: Bool

    var id: String { code.rawValue }
    var displayValues: [String] { [code.rawValue, message] }
}

struct MobileAbilityCardRegressionAppealExplanationPreviewPublicSummary: Equatable {
    var role: MobileAbilityCardRegressionAppealExplanationPreviewRole
    var entryCount: Int
    var visibleEntryCount: Int
    var appealInProgressCount: Int
    var waitingReviewCount: Int
    var revertedCount: Int
    var frozenCount: Int
    var evidenceRevokedCount: Int
    var homeworkReturnCount: Int
    var wearableAnomalyCount: Int
    var creationRevokedCount: Int
    var leakRiskCount: Int
    var stableStrengthCount: Int
    var findingCodes: [MobileAbilityCardRegressionAppealExplanationPreviewFindingCode]

    let callsNetwork = false
    let callsAiProvider = false
    let callsLocalModel = false
    let callsLms = false
    let writesSchoolSystem = false
    let opensExternalLink = false
    let revertsAbilityCard = false
    let lowersAbilityScore = false
    let processesAppeal = false
    let revokesEvidence = false
    let returnsHomework = false
    let verifiesTeacher = false
    let confirmsGuardian = false
    let notifiesRelative = false
    let writesLedger = false
    let grantsCredit = false
    let spendsCredit = false
    let fulfillsReward = false
    let controlsScreenTime = false
    let unlocksDevice = false
    let publishesContent = false
    let sendsNotification = false
    let submitsProof = false

    var hasTriggeredSideEffect: Bool {
        callsNetwork || callsAiProvider || callsLocalModel || callsLms || writesSchoolSystem
            || opensExternalLink || revertsAbilityCard || lowersAbilityScore || processesAppeal
            || revokesEvidence || returnsHomework || verifiesTeacher || confirmsGuardian
            || notifiesRelative || writesLedger || grantsCredit || spendsCredit || fulfillsReward
            || controlsScreenTime || unlocksDevice || publishesContent || sendsNotification
            || submitsProof
    }
}

struct MobileAbilityCardRegressionAppealExplanationPreview: Equatable {
    var role: MobileAbilityCardRegressionAppealExplanationPreviewRole
    var title: String
    var subtitle: String
    var audienceNote: String
    var entries: [MobileAbilityCardRegressionAppealExplanationPreviewEntry]
    var findings: [MobileAbilityCardRegressionAppealExplanationPreviewFinding]
    var publicSummary: MobileAbilityCardRegressionAppealExplanationPreviewPublicSummary

    var displayValues: [String] {
        [role.rawValue, title, subtitle, audienceNote]
            + entries.flatMap(\.displayValues)
            + findings.flatMap(\.displayValues)
    }

    var hasUnsafeDisplayPayload: Bool {
        MobileAbilityCardRegressionAppealExplanationPreviewBuilder.hasUnsafeDisplayPayload(displayValues)
    }
}

struct MobileAbilityCardRegressionAppealExplanationPreviewInput: Equatable {
    var generatedAt: String
    var unsafePayload: String?

    static let mock = MobileAbilityCardRegressionAppealExplanationPreviewInput(
        generatedAt: "2026-06-25T03:00:00.000Z",
        unsafePayload: nil
    )
}

struct MobileAbilityCardRegressionAppealExplanationPreviewBuilder {
    private static let redactionSalt = "mobile-ability-card-regression-appeal-explanation-preview-v1"
    private static let sensitiveMarkers = [
        "child:", "family:", "school:", "teacher:", "guardian:", "relative:", "creator:",
        "proof:", "media:", "photo:", "screenshot:", "transcript", "answer key", "answerkey",
        "答案键", "provider:", "model:", "resource:", "link:", "url:", "homework:", "quiz:",
        "badge:", "card:", "ability:", "appeal:", "pack:", "reward:", "order:", "inventory:",
        "ledger:", "device:", "entitlement:", "publicref", "adultreason", "adult reason",
        "internalref", "internal ref", "ref:", "task:", "taskid", "claim:", "claimid", "token",
        "api_key", "apikey", "secret", "credit amount", "成长积分金额", "账本明细", "设备命令",
        "复核策略", "公开排序", "排序策略", "能力评分", "评分算法", "回退算法", "http://",
        "https://", "file://", "/users/", "/volumes/", "child_real", "family_real", "proof_real",
        "card_real", "appeal_real", "192.168.", ".local"
    ]

    func build(
        role: MobileAbilityCardRegressionAppealExplanationPreviewRole,
        input: MobileAbilityCardRegressionAppealExplanationPreviewInput = .mock
    ) -> MobileAbilityCardRegressionAppealExplanationPreview {
        if let unsafePayload = input.unsafePayload, Self.hasUnsafeDisplayPayload([unsafePayload]) {
            return blockedPreview(role: role)
        }

        let allEntries = makeEntries(for: role)
        let visibleEntries = allEntries
            .filter { visible($0, for: role) }
            .sorted { left, right in
                if left.sortOrder == right.sortOrder {
                    return left.publicPreviewRef < right.publicPreviewRef
                }
                return left.sortOrder < right.sortOrder
            }

        let findings = makeFindings(role: role, entries: visibleEntries)

        return MobileAbilityCardRegressionAppealExplanationPreview(
            role: role,
            title: title(for: role),
            subtitle: subtitle(for: role),
            audienceNote: audienceNote(for: role),
            entries: visibleEntries,
            findings: findings,
            publicSummary: summary(
                role: role,
                allEntries: allEntries,
                visibleEntries: visibleEntries,
                findings: findings
            )
        )
    }

    static func hasUnsafeDisplayPayload(_ values: [String]) -> Bool {
        let joined = values.joined(separator: " ").lowercased()
        return sensitiveMarkers.contains { joined.contains($0) }
    }

    private func visible(
        _ entry: MobileAbilityCardRegressionAppealExplanationPreviewEntry,
        for role: MobileAbilityCardRegressionAppealExplanationPreviewRole
    ) -> Bool {
        switch role {
        case .child: return entry.visibleToChild
        case .guardian: return entry.visibleToGuardian
        case .relative: return entry.visibleToRelative
        case .teacher: return entry.visibleToTeacher
        }
    }

    private func title(for role: MobileAbilityCardRegressionAppealExplanationPreviewRole) -> String {
        switch role {
        case .child: return "发生了什么 · 下一步"
        case .guardian: return "能力卡回退申诉解释复核"
        case .relative: return "稳定优势与已公开成长"
        case .teacher: return "学校作业退回 / 重提交"
        }
    }

    private func subtitle(for role: MobileAbilityCardRegressionAppealExplanationPreviewRole) -> String {
        switch role {
        case .child:
            return "用温和的话说明能力卡为什么先暂停，以及现在是申诉中、等待复核还是继续努力；这里只读，不会真的改你的卡或分数。"
        case .guardian:
            return "只读复核能力维度回退、能力卡冻结、申诉 / 复核、证据撤回、学校作业退回、可穿戴异常、创作撤权、公开 / 亲友可见边界和敏感摘要泄露风险。"
        case .relative:
            return "只看孩子稳定的优势和已经同意公开的正向成长；看不到回退原因、申诉状态或学校 / 家庭内部内容。"
        case .teacher:
            return "只看与学校作业相关的退回与重提交流程；看不到家庭成长积分、设备或亲友内容。"
        }
    }

    private func audienceNote(for role: MobileAbilityCardRegressionAppealExplanationPreviewRole) -> String {
        switch role {
        case .child:
            return "这里只看温和解释和下一步；真正的复核、回退和申诉结果都由家长和老师在正式流程里决定。"
        case .guardian:
            return "这里只读整理回退 / 冻结 / 申诉解释；真正回退能力卡、降分、处理申诉和发 / 扣成长积分仍走正式流程。"
        case .relative:
            return "这里只看已同意公开的正向内容；不显示回退原因、申诉状态、成长积分或设备信息。"
        case .teacher:
            return "这里只看作业退回与重提交流程；不显示家庭成长积分、设备、亲友或跨孩子内容。"
        }
    }

    private func blockedPreview(
        role: MobileAbilityCardRegressionAppealExplanationPreviewRole
    ) -> MobileAbilityCardRegressionAppealExplanationPreview {
        let finding = MobileAbilityCardRegressionAppealExplanationPreviewFinding(
            code: .unsafePayloadBlocked,
            message: "预览发现不安全字段，已隐藏全部解释，等待家长在正式流程复核。",
            actionRequired: true,
            visibleToChild: true
        )
        return MobileAbilityCardRegressionAppealExplanationPreview(
            role: role,
            title: title(for: role),
            subtitle: "内容已安全隐藏；本地页面不会继续展示原始字段。",
            audienceNote: role == .child
                ? "先不用着急，等家长确认后再继续。"
                : "请回正式复核流程查看原因；本页不显示原始字段。",
            entries: [],
            findings: [finding],
            publicSummary: MobileAbilityCardRegressionAppealExplanationPreviewPublicSummary(
                role: role,
                entryCount: 0,
                visibleEntryCount: 0,
                appealInProgressCount: 0,
                waitingReviewCount: 0,
                revertedCount: 0,
                frozenCount: 0,
                evidenceRevokedCount: 0,
                homeworkReturnCount: 0,
                wearableAnomalyCount: 0,
                creationRevokedCount: 0,
                leakRiskCount: 0,
                stableStrengthCount: 0,
                findingCodes: [.unsafePayloadBlocked]
            )
        )
    }

    private func makeEntries(
        for role: MobileAbilityCardRegressionAppealExplanationPreviewRole
    ) -> [MobileAbilityCardRegressionAppealExplanationPreviewEntry] {
        [
            entry(
                category: .abilityRegression,
                role: role,
                status: role == .child ? .keepGoing : .guardianReview,
                child: "有一个能力先回到了之前的样子，这不是你不好，继续努力就会慢慢回来。",
                guardian: "能力维度出现回退：依据复核后调整，回退幅度与原因在正式审计流程查看，确认前不再降分。",
                relative: "",
                teacher: "",
                childNext: "先做下一步的小目标，能力会慢慢长回来。",
                guardianNext: "在正式审计流程复核回退依据与幅度，确认前不再降低能力分。",
                teacherNext: "",
                safetyNote: "不回退能力卡、不降低能力分、不发 / 扣成长积分。",
                sortOrder: 10,
                visibleToChild: true, visibleToGuardian: true, visibleToRelative: false, visibleToTeacher: false,
                isAppealing: false, isWaitingReview: false, isReverted: true, isFrozen: false,
                evidenceRevoked: false, homeworkReturned: false, wearableAnomaly: false,
                creationRevoked: false, visibilityBoundary: false, leakRisk: false
            ),
            entry(
                category: .abilityCardFrozen,
                role: role,
                status: role == .child ? .onHold : .guardianReview,
                child: "你的成长球星卡先暂停更新，等大人看过后再继续，不用担心。",
                guardian: "能力卡冻结中：等待人工复核后再决定是否解冻，冻结期间不更新成长球星卡。",
                relative: "",
                teacher: "",
                childNext: "先做下一步，卡晚点会自己更新。",
                guardianNext: "复核冻结原因与证据来源，再决定是否解冻能力卡。",
                teacherNext: "",
                safetyNote: "不更新能力卡、不改能力维度、不发成长积分。",
                sortOrder: 20,
                visibleToChild: true, visibleToGuardian: true, visibleToRelative: false, visibleToTeacher: false,
                isAppealing: false, isWaitingReview: false, isReverted: false, isFrozen: true,
                evidenceRevoked: false, homeworkReturned: false, wearableAnomaly: false,
                creationRevoked: false, visibilityBoundary: false, leakRisk: false
            ),
            entry(
                category: .appealReview,
                role: role,
                status: role == .child ? .appealInProgress : .waitingReview,
                child: "已经帮你提出了申诉，现在正在等待复核，你可以一边继续努力一边等结果。",
                guardian: "申诉 / 复核进行中：结果确认前不回退能力卡、不降分、不发 / 扣成长积分，也不改变可见范围。",
                relative: "",
                teacher: "",
                childNext: "继续努力，等待复核的结果出来。",
                guardianNext: "在正式复核流程查看申诉进度与依据，确认后再放行后续动作。",
                teacherNext: "",
                safetyNote: "不处理申诉、不改结论、不发 / 扣成长积分。",
                sortOrder: 30,
                visibleToChild: true, visibleToGuardian: true, visibleToRelative: false, visibleToTeacher: false,
                isAppealing: true, isWaitingReview: true, isReverted: false, isFrozen: false,
                evidenceRevoked: false, homeworkReturned: false, wearableAnomaly: false,
                creationRevoked: false, visibilityBoundary: false, leakRisk: false
            ),
            entry(
                category: .evidenceRevoked,
                role: role,
                status: .guardianReview,
                child: "",
                guardian: "证据撤回：相关证据已被撤回，撤回后必须回滚由它带来的能力卡 / 徽章变化。",
                relative: "",
                teacher: "",
                childNext: "",
                guardianNext: "确认撤回已生效、旧链路已回滚，再决定后续能力卡处理。",
                teacherNext: "",
                safetyNote: "不读取原始证据、不写账本、不发成长积分。",
                sortOrder: 40,
                visibleToChild: false, visibleToGuardian: true, visibleToRelative: false, visibleToTeacher: false,
                isAppealing: false, isWaitingReview: false, isReverted: false, isFrozen: false,
                evidenceRevoked: true, homeworkReturned: false, wearableAnomaly: false,
                creationRevoked: false, visibilityBoundary: false, leakRisk: false
            ),
            entry(
                category: .schoolHomeworkReturn,
                role: role,
                status: role == .teacher ? .teacherReturn : .guardianReview,
                child: "",
                guardian: "学校作业退回：相关作业被退回需重提交，作业流程不直接改家庭成长积分或能力分。",
                relative: "",
                teacher: "作业已退回，等待孩子按要求重新提交；本页只读，不直接验证身份或写入学校系统。",
                childNext: "",
                guardianNext: "确认作业退回原因走学校流程，不与家庭成长积分 / 设备混合。",
                teacherNext: "在正式教学流程说明退回原因，等待孩子按要求重提交。",
                safetyNote: "不提交 / 退回作业、不验证老师、不写学校系统。",
                sortOrder: 50,
                visibleToChild: false, visibleToGuardian: true, visibleToRelative: false, visibleToTeacher: true,
                isAppealing: false, isWaitingReview: false, isReverted: false, isFrozen: false,
                evidenceRevoked: false, homeworkReturned: true, wearableAnomaly: false,
                creationRevoked: false, visibilityBoundary: false, leakRisk: false
            ),
            entry(
                category: .wearableAnomaly,
                role: role,
                status: .guardianReview,
                child: "",
                guardian: "可穿戴异常：运动 / 健康类数据出现异常，确认前不让设备数据造成能力维度跳变。",
                relative: "",
                teacher: "",
                childNext: "",
                guardianNext: "复核可穿戴异常来源，确认前不据此调整运动力等维度。",
                teacherNext: "",
                safetyNote: "不读取健康数据、不连设备、不改能力维度。",
                sortOrder: 60,
                visibleToChild: false, visibleToGuardian: true, visibleToRelative: false, visibleToTeacher: false,
                isAppealing: false, isWaitingReview: false, isReverted: false, isFrozen: false,
                evidenceRevoked: false, homeworkReturned: false, wearableAnomaly: true,
                creationRevoked: false, visibilityBoundary: false, leakRisk: false
            ),
            entry(
                category: .creationRevoked,
                role: role,
                status: .guardianReview,
                child: "",
                guardian: "创作撤权：某项创作的展示授权被撤回，撤回后须回滚公开 / 亲友可见与相关能力反映。",
                relative: "",
                teacher: "",
                childNext: "",
                guardianNext: "确认创作撤权已生效、公开与亲友可见已回滚，再处理能力反映。",
                teacherNext: "",
                safetyNote: "不公开内容、不通知亲友、不发成长积分。",
                sortOrder: 70,
                visibleToChild: false, visibleToGuardian: true, visibleToRelative: false, visibleToTeacher: false,
                isAppealing: false, isWaitingReview: false, isReverted: false, isFrozen: false,
                evidenceRevoked: false, homeworkReturned: false, wearableAnomaly: false,
                creationRevoked: true, visibilityBoundary: false, leakRisk: false
            ),
            entry(
                category: .visibilityBoundary,
                role: role,
                status: .guardianReview,
                child: "",
                guardian: "公开 / 亲友可见边界：回退 / 撤回后亲友与公开可见必须同步收敛，不暴露回退原因与申诉状态。",
                relative: "",
                teacher: "",
                childNext: "",
                guardianNext: "确认亲友与公开视图只剩稳定优势与已同意内容，不泄露回退 / 申诉细节。",
                teacherNext: "",
                safetyNote: "不改可见范围、不通知亲友、不公开内容。",
                sortOrder: 80,
                visibleToChild: false, visibleToGuardian: true, visibleToRelative: false, visibleToTeacher: false,
                isAppealing: false, isWaitingReview: false, isReverted: false, isFrozen: false,
                evidenceRevoked: false, homeworkReturned: false, wearableAnomaly: false,
                creationRevoked: false, visibilityBoundary: true, leakRisk: false
            ),
            entry(
                category: .sensitiveSummaryRisk,
                role: role,
                status: .guardianReview,
                child: "",
                guardian: "敏感摘要泄露风险：解释摘要可能拼出学校 / 家庭敏感信息，发布前须做最小披露收敛。",
                relative: "",
                teacher: "",
                childNext: "",
                guardianNext: "复核摘要是否最小披露，避免拼出学校 / 家庭信息或跨孩子内容。",
                teacherNext: "",
                safetyNote: "不外发摘要、不公开位置、不混入跨孩子内容。",
                sortOrder: 90,
                visibleToChild: false, visibleToGuardian: true, visibleToRelative: false, visibleToTeacher: false,
                isAppealing: false, isWaitingReview: false, isReverted: false, isFrozen: false,
                evidenceRevoked: false, homeworkReturned: false, wearableAnomaly: false,
                creationRevoked: false, visibilityBoundary: false, leakRisk: true
            ),
            entry(
                category: .stableStrength,
                role: role,
                status: .stable,
                child: "有些优势一直很稳，没有被这次暂停影响，继续保持就好。",
                guardian: "稳定优势：未受本次回退影响的稳定能力，可安全保留并对亲友只读展示。",
                relative: "孩子有一些稳定的优势一直保持得很好，可以放心鼓励。",
                teacher: "",
                childNext: "继续保持你擅长的事。",
                guardianNext: "确认稳定优势可对亲友只读展示，不附带回退原因。",
                teacherNext: "",
                safetyNote: "不公开回退原因、不发成长积分、不通知设备。",
                sortOrder: 100,
                visibleToChild: true, visibleToGuardian: true, visibleToRelative: true, visibleToTeacher: false,
                isAppealing: false, isWaitingReview: false, isReverted: false, isFrozen: false,
                evidenceRevoked: false, homeworkReturned: false, wearableAnomaly: false,
                creationRevoked: false, visibilityBoundary: false, leakRisk: false
            ),
            entry(
                category: .consentedPublicGrowth,
                role: role,
                status: .stable,
                child: "已经和家长一起同意公开的成长可以分享给亲友，让大家一起开心。",
                guardian: "已同意公开的正向成长：仅展示同意范围内的正向内容，不含回退 / 申诉 / 学校退回信息。",
                relative: "这些正向成长是孩子和家长同意公开的，可以一起为他高兴。",
                teacher: "",
                childNext: "继续记录你愿意分享的成长亮点。",
                guardianNext: "确认亲友只看到同意范围内的正向成长，不含内部原因。",
                teacherNext: "",
                safetyNote: "只展示已同意内容、不发成长积分、不通知设备。",
                sortOrder: 110,
                visibleToChild: true, visibleToGuardian: true, visibleToRelative: true, visibleToTeacher: false,
                isAppealing: false, isWaitingReview: false, isReverted: false, isFrozen: false,
                evidenceRevoked: false, homeworkReturned: false, wearableAnomaly: false,
                creationRevoked: false, visibilityBoundary: false, leakRisk: false
            )
        ]
    }

    private func entry(
        category: MobileAbilityCardRegressionAppealExplanationPreviewCategory,
        role: MobileAbilityCardRegressionAppealExplanationPreviewRole,
        status: MobileAbilityCardRegressionAppealExplanationPreviewStatus,
        child: String,
        guardian: String,
        relative: String,
        teacher: String,
        childNext: String,
        guardianNext: String,
        teacherNext: String,
        safetyNote: String,
        sortOrder: Int,
        visibleToChild: Bool,
        visibleToGuardian: Bool,
        visibleToRelative: Bool,
        visibleToTeacher: Bool,
        isAppealing: Bool,
        isWaitingReview: Bool,
        isReverted: Bool,
        isFrozen: Bool,
        evidenceRevoked: Bool,
        homeworkReturned: Bool,
        wearableAnomaly: Bool,
        creationRevoked: Bool,
        visibilityBoundary: Bool,
        leakRisk: Bool
    ) -> MobileAbilityCardRegressionAppealExplanationPreviewEntry {
        MobileAbilityCardRegressionAppealExplanationPreviewEntry(
            publicPreviewRef: publicRef("entry:\(category.rawValue):\(role.rawValue):\(sortOrder)"),
            category: category,
            status: status,
            title: category.title,
            explanation: pick(role, child: child, guardian: guardian, relative: relative, teacher: teacher),
            nextStep: pick(role, child: childNext, guardian: guardianNext, relative: "", teacher: teacherNext),
            safetyNote: safetyNote,
            visibleToChild: visibleToChild,
            visibleToGuardian: visibleToGuardian,
            visibleToRelative: visibleToRelative,
            visibleToTeacher: visibleToTeacher,
            isAppealing: isAppealing,
            isWaitingReview: isWaitingReview,
            isReverted: isReverted,
            isFrozen: isFrozen,
            evidenceRevoked: evidenceRevoked,
            homeworkReturned: homeworkReturned,
            wearableAnomaly: wearableAnomaly,
            creationRevoked: creationRevoked,
            visibilityBoundary: visibilityBoundary,
            leakRisk: leakRisk,
            sortOrder: sortOrder
        )
    }

    private func pick(
        _ role: MobileAbilityCardRegressionAppealExplanationPreviewRole,
        child: String,
        guardian: String,
        relative: String,
        teacher: String
    ) -> String {
        switch role {
        case .child: return child
        case .guardian: return guardian
        case .relative: return relative
        case .teacher: return teacher
        }
    }

    private func makeFindings(
        role: MobileAbilityCardRegressionAppealExplanationPreviewRole,
        entries: [MobileAbilityCardRegressionAppealExplanationPreviewEntry]
    ) -> [MobileAbilityCardRegressionAppealExplanationPreviewFinding] {
        let readOnlyMessage: String
        switch role {
        case .child:
            readOnlyMessage = "预览只读说明能力卡暂停和下一步，不会改能力卡、降分、处理申诉或发 / 扣成长积分。"
        case .guardian:
            readOnlyMessage = "预览只读说明回退 / 冻结 / 申诉边界，不会回退能力卡、降分、处理申诉、退回作业或发 / 扣成长积分。"
        case .relative:
            readOnlyMessage = "预览只读展示已同意公开的正向成长，其他内部内容不会出现在这里。"
        case .teacher:
            readOnlyMessage = "预览只读展示学校作业退回与重提交流程，不写学校系统，也不显示家庭侧内部内容。"
        }

        var findings = [
            MobileAbilityCardRegressionAppealExplanationPreviewFinding(
                code: .readOnlyPreview,
                message: readOnlyMessage,
                actionRequired: false,
                visibleToChild: true
            )
        ]

        if entries.contains(where: \.isAppealing) {
            findings.append(
                MobileAbilityCardRegressionAppealExplanationPreviewFinding(
                    code: .appealInProgress,
                    message: role == .child ? "你的申诉正在进行中，先继续努力，等待复核结果。" : "申诉进行中，结果确认前不回退能力卡、不降分、不发 / 扣成长积分。",
                    actionRequired: true,
                    visibleToChild: true
                )
            )
        }
        if entries.contains(where: \.isWaitingReview) {
            findings.append(
                MobileAbilityCardRegressionAppealExplanationPreviewFinding(
                    code: .waitingReview,
                    message: role == .child ? "现在在等待复核，结果出来前不用着急。" : "等待复核中，复核完成前不改变能力卡或可见范围。",
                    actionRequired: true,
                    visibleToChild: true
                )
            )
        }
        if role == .child {
            findings.append(
                MobileAbilityCardRegressionAppealExplanationPreviewFinding(
                    code: .keepGoingEncouragement,
                    message: "暂停只是暂时的，继续努力，做好下一步就好。",
                    actionRequired: false,
                    visibleToChild: true
                )
            )
            return findings.filter(\.visibleToChild)
        }

        if role == .relative || role == .teacher {
            // 亲友 / 老师不看任何回退 / 申诉 / 家庭内部原因的提示。
            return findings.filter { $0.code == .readOnlyPreview }
        }

        // 以下仅家长可见。
        if entries.contains(where: \.isReverted) {
            findings.append(
                MobileAbilityCardRegressionAppealExplanationPreviewFinding(
                    code: .abilityReverted,
                    message: "能力维度已回退，回退依据与幅度走正式审计流程，确认前不再降分。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        if entries.contains(where: \.isFrozen) {
            findings.append(
                MobileAbilityCardRegressionAppealExplanationPreviewFinding(
                    code: .abilityCardFrozen,
                    message: "能力卡冻结中，解冻前不更新成长球星卡。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        if entries.contains(where: \.evidenceRevoked) {
            findings.append(
                MobileAbilityCardRegressionAppealExplanationPreviewFinding(
                    code: .evidenceRevoked,
                    message: "证据已撤回，须回滚由它带来的能力卡 / 徽章变化后再处理。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        if entries.contains(where: \.homeworkReturned) {
            findings.append(
                MobileAbilityCardRegressionAppealExplanationPreviewFinding(
                    code: .homeworkReturned,
                    message: "学校作业退回走学校流程，不直接改家庭成长积分或能力分。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        if entries.contains(where: \.wearableAnomaly) {
            findings.append(
                MobileAbilityCardRegressionAppealExplanationPreviewFinding(
                    code: .wearableAnomaly,
                    message: "可穿戴数据异常，确认前不让设备数据造成能力维度跳变。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        if entries.contains(where: \.creationRevoked) {
            findings.append(
                MobileAbilityCardRegressionAppealExplanationPreviewFinding(
                    code: .creationRevoked,
                    message: "创作授权已撤回，须回滚公开 / 亲友可见与相关能力反映。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        if entries.contains(where: \.visibilityBoundary) {
            findings.append(
                MobileAbilityCardRegressionAppealExplanationPreviewFinding(
                    code: .visibilityBoundary,
                    message: "公开 / 亲友可见须同步收敛，不暴露回退原因与申诉状态。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        if entries.contains(where: \.leakRisk) {
            findings.append(
                MobileAbilityCardRegressionAppealExplanationPreviewFinding(
                    code: .sensitiveSummaryRisk,
                    message: "解释摘要存在敏感信息拼合风险，发布前须做最小披露收敛。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        return findings
    }

    private func summary(
        role: MobileAbilityCardRegressionAppealExplanationPreviewRole,
        allEntries: [MobileAbilityCardRegressionAppealExplanationPreviewEntry],
        visibleEntries: [MobileAbilityCardRegressionAppealExplanationPreviewEntry],
        findings: [MobileAbilityCardRegressionAppealExplanationPreviewFinding]
    ) -> MobileAbilityCardRegressionAppealExplanationPreviewPublicSummary {
        MobileAbilityCardRegressionAppealExplanationPreviewPublicSummary(
            role: role,
            entryCount: allEntries.count,
            visibleEntryCount: visibleEntries.count,
            appealInProgressCount: visibleEntries.filter(\.isAppealing).count,
            waitingReviewCount: visibleEntries.filter(\.isWaitingReview).count,
            revertedCount: visibleEntries.filter(\.isReverted).count,
            frozenCount: visibleEntries.filter(\.isFrozen).count,
            evidenceRevokedCount: visibleEntries.filter(\.evidenceRevoked).count,
            homeworkReturnCount: visibleEntries.filter(\.homeworkReturned).count,
            wearableAnomalyCount: visibleEntries.filter(\.wearableAnomaly).count,
            creationRevokedCount: visibleEntries.filter(\.creationRevoked).count,
            leakRiskCount: visibleEntries.filter(\.leakRisk).count,
            stableStrengthCount: visibleEntries.filter { $0.category == .stableStrength || $0.category == .consentedPublicGrowth }.count,
            findingCodes: findings.map(\.code)
        )
    }

    private func publicRef(_ seed: String) -> String {
        "acr-\(Self.stableHash("\(Self.redactionSalt):\(seed)"))"
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
