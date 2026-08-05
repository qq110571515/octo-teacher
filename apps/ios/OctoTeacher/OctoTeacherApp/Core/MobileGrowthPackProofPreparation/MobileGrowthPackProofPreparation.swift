import Foundation

/// iOS 成长包证明准备的纯本地只读投影。
///
/// 这一层只整理“提交前该准备什么”，不打开相机/相册/文件/外链，不上传媒体，
/// 不写学校系统、账本或成长积分，也不控制设备或屏幕时间。
enum MobileGrowthPackProofPreparationKind: String, CaseIterable, Equatable {
    case homeworkNote = "homework_note"
    case quizReflection = "quiz_reflection"
    case creativeStatement = "creative_statement"
    case externalResourceNote = "external_resource_note"
    case wearableActivitySummary = "wearable_activity_summary"
    case guardianContext = "guardian_context"
    case rewardBoundary = "reward_boundary"

    var title: String {
        switch self {
        case .homeworkNote: return "作业说明"
        case .quizReflection: return "测验自检"
        case .creativeStatement: return "创作说明"
        case .externalResourceNote: return "外部学习记录"
        case .wearableActivitySummary: return "运动证明摘要"
        case .guardianContext: return "家长复核上下文"
        case .rewardBoundary: return "奖励前置条件"
        }
    }
}

enum MobileGrowthPackProofPreparationStatus: String, Equatable {
    case readyToPrepare = "ready_to_prepare"
    case needsMoreWork = "needs_more_work"
    case waitingConsent = "waiting_consent"
    case waitingReview = "waiting_review"
    case blocked

    var label: String {
        switch self {
        case .readyToPrepare: return "可以准备"
        case .needsMoreWork: return "还要补充"
        case .waitingConsent: return "等同意"
        case .waitingReview: return "等复核"
        case .blocked: return "已阻断"
        }
    }
}

enum MobileGrowthPackProofPreparationFindingCode: String, Equatable {
    case readOnlyPreparation = "READ_ONLY_PREPARATION"
    case completionRequired = "COMPLETION_REQUIRED"
    case consentRequired = "CONSENT_REQUIRED"
    case moderationRequired = "MODERATION_REQUIRED"
    case externalAllowlistRequired = "EXTERNAL_ALLOWLIST_REQUIRED"
    case wearableReviewRequired = "WEARABLE_REVIEW_REQUIRED"
    case rewardPressureBlocked = "REWARD_PRESSURE_BLOCKED"
    case unsafePayloadBlocked = "UNSAFE_PAYLOAD_BLOCKED"
}

struct MobileGrowthPackProofPreparationItem: Identifiable, Equatable {
    var publicPrepRef: String
    var kind: MobileGrowthPackProofPreparationKind
    var status: MobileGrowthPackProofPreparationStatus
    var title: String
    var instruction: String
    var missingReason: String
    var nextStep: String
    var safetyNote: String
    var visibleToChild: Bool
    var visibleToGuardian: Bool
    var requiresCompletion: Bool
    var requiresConsent: Bool
    var requiresModeration: Bool
    var requiresGuardianReview: Bool
    var requiresAllowlist: Bool
    var hasAnomaly: Bool
    var rewardPressureBlocked: Bool
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
    let unlocksDevice = false
    let controlsScreenTime = false
    let sendsNotification = false
    let publishesContent = false

    var id: String { publicPrepRef }

    var displayValues: [String] {
        [
            publicPrepRef,
            kind.rawValue,
            kind.title,
            status.rawValue,
            status.label,
            title,
            instruction,
            missingReason,
            nextStep,
            safetyNote
        ]
    }

    var hasTriggeredSideEffect: Bool {
        callsNetwork || callsAiProvider || callsLocalModel || callsLms || writesSchoolSystem
            || opensExternalLink || opensCamera || opensPhotoLibrary || opensFilePicker || uploadsMedia
            || writesLedger || grantsCredit || spendsCredit || fulfillsReward || grantsBadge
            || updatesAbilityCard || unlocksDevice || controlsScreenTime || sendsNotification || publishesContent
    }
}

struct MobileGrowthPackProofPreparationFinding: Identifiable, Equatable {
    var code: MobileGrowthPackProofPreparationFindingCode
    var message: String
    var actionRequired: Bool
    var visibleToChild: Bool

    var id: String { code.rawValue }
    var displayValues: [String] { [code.rawValue, message] }
}

struct MobileGrowthPackProofPreparationPublicSummary: Equatable {
    var role: MobileGrowthPackExecutionHubRole
    var itemCount: Int
    var visibleItemCount: Int
    var readyCount: Int
    var blockedCount: Int
    var consentRequiredCount: Int
    var moderationRequiredCount: Int
    var reviewRequiredCount: Int
    var findingCodes: [MobileGrowthPackProofPreparationFindingCode]

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
    let unlocksDevice = false
    let controlsScreenTime = false
    let sendsNotification = false
    let publishesContent = false

    var hasTriggeredSideEffect: Bool {
        callsNetwork || callsAiProvider || callsLocalModel || callsLms || writesSchoolSystem
            || opensExternalLink || opensCamera || opensPhotoLibrary || opensFilePicker || uploadsMedia
            || writesLedger || grantsCredit || spendsCredit || fulfillsReward || grantsBadge
            || updatesAbilityCard || unlocksDevice || controlsScreenTime || sendsNotification || publishesContent
    }
}

struct MobileGrowthPackProofPreparation: Equatable {
    var role: MobileGrowthPackExecutionHubRole
    var title: String
    var subtitle: String
    var audienceNote: String
    var items: [MobileGrowthPackProofPreparationItem]
    var findings: [MobileGrowthPackProofPreparationFinding]
    var publicSummary: MobileGrowthPackProofPreparationPublicSummary

    var displayValues: [String] {
        [role.rawValue, title, subtitle, audienceNote]
            + items.flatMap(\.displayValues)
            + findings.flatMap(\.displayValues)
    }

    var hasUnsafeDisplayPayload: Bool {
        MobileGrowthPackProofPreparationBuilder.hasUnsafeDisplayPayload(displayValues)
    }
}

struct MobileGrowthPackProofPreparationInput: Equatable {
    var generatedAt: String
    var unsafePayload: String?

    static let mock = MobileGrowthPackProofPreparationInput(
        generatedAt: "2026-06-25T01:30:00.000Z",
        unsafePayload: nil
    )
}

struct MobileGrowthPackProofPreparationBuilder {
    private static let redactionSalt = "mobile-growth-pack-proof-preparation-v1"
    private static let sensitiveMarkers = [
        "child:", "family:", "school:", "teacher:", "guardian:", "relative:",
        "proof:", "media:", "photo:", "screenshot:", "transcript", "answer key", "answerkey",
        "答案键", "provider:", "model:", "resource:", "link:", "url:", "homework:", "quiz:",
        "reward:", "order:", "inventory:", "ledger:", "device:", "badge:", "ability:",
        "calendar:", "schedule:", "task:", "claim:", "token", "api_key", "apikey", "secret",
        "credit amount", "成长积分金额", "账本明细", "设备命令", "复核策略",
        "http://", "https://", "file://", "/users/", "/volumes/", "192.168.", ".local"
    ]

    func build(
        role: MobileGrowthPackExecutionHubRole,
        input: MobileGrowthPackProofPreparationInput = .mock
    ) -> MobileGrowthPackProofPreparation {
        if let unsafePayload = input.unsafePayload, Self.hasUnsafeDisplayPayload([unsafePayload]) {
            return blockedPreparation(role: role)
        }

        let allItems = makeItems(for: role)
        let visibleItems = allItems.filter { item in
            switch role {
            case .child: return item.visibleToChild
            case .guardian: return item.visibleToGuardian
            }
        }
        .sorted { left, right in
            if left.sortOrder == right.sortOrder {
                return left.publicPrepRef < right.publicPrepRef
            }
            return left.sortOrder < right.sortOrder
        }
        let findings = makeFindings(role: role, items: visibleItems)

        return MobileGrowthPackProofPreparation(
            role: role,
            title: role == .child ? "准备证明" : "证明准备复核",
            subtitle: role == .child
                ? "先把说明准备好；这里只读检查，不会提交、上传或发奖励。"
                : "只读复核证明缺口、同意/审核、外部资源、运动异常和奖励前置条件。",
            audienceNote: role == .child
                ? "这里只告诉你怎么安全准备证明；真正提交和奖励都要等正式流程。"
                : "这里只读整理提交前边界；真正审核、发成长积分、授徽章或改能力卡仍走正式流程。",
            items: visibleItems,
            findings: findings,
            publicSummary: summary(role: role, allItems: allItems, visibleItems: visibleItems, findings: findings)
        )
    }

    static func hasUnsafeDisplayPayload(_ values: [String]) -> Bool {
        let joined = values.joined(separator: " ").lowercased()
        return sensitiveMarkers.contains { joined.contains($0) }
    }

    private func blockedPreparation(role: MobileGrowthPackExecutionHubRole) -> MobileGrowthPackProofPreparation {
        let finding = MobileGrowthPackProofPreparationFinding(
            code: .unsafePayloadBlocked,
            message: "准备清单发现不安全字段，已隐藏内容，等待家长在正式流程复核。",
            actionRequired: true,
            visibleToChild: true
        )
        return MobileGrowthPackProofPreparation(
            role: role,
            title: role == .child ? "准备证明" : "证明准备复核",
            subtitle: "内容已安全隐藏；本地页面不会展示原始字段。",
            audienceNote: role == .child
                ? "先不用着急，等家长确认后再继续。"
                : "请回正式复核流程查看原因；本页不显示原始字段。",
            items: [],
            findings: [finding],
            publicSummary: MobileGrowthPackProofPreparationPublicSummary(
                role: role,
                itemCount: 0,
                visibleItemCount: 0,
                readyCount: 0,
                blockedCount: 1,
                consentRequiredCount: 0,
                moderationRequiredCount: 0,
                reviewRequiredCount: 1,
                findingCodes: [.unsafePayloadBlocked]
            )
        )
    }

    private func makeItems(for role: MobileGrowthPackExecutionHubRole) -> [MobileGrowthPackProofPreparationItem] {
        [
            item(
                kind: .homeworkNote,
                role: role,
                status: .readyToPrepare,
                childInstruction: "用自己的话写今天完成了哪一步，不写答案和老师内部要求。",
                guardianInstruction: "作业证明只保留孩子可见说明；学校授权、老师验证和退回状态仍在作业安全壳复核。",
                missingReason: "",
                nextStep: role == .child ? "写清楚你做了什么和哪里还不懂。" : "确认作业未退回且证明不含答案或老师内部信息。",
                safetyNote: "不提交作业、不判分、不写学校系统。",
                sortOrder: 10,
                requiresCompletion: false,
                requiresConsent: false,
                requiresModeration: false,
                requiresGuardianReview: false,
                requiresAllowlist: false,
                hasAnomaly: false,
                rewardPressureBlocked: false,
                visibleToChild: true,
                visibleToGuardian: true
            ),
            item(
                kind: .quizReflection,
                role: role,
                status: .needsMoreWork,
                childInstruction: "写下你怎么检查答案，不写标准答案或评分规则。",
                guardianInstruction: "测验证明还缺自检说明；答案、评分规则和 AI 对话原文不进入孩子端证明。",
                missingReason: "还缺自检说明，不能把答案当证明。",
                nextStep: role == .child ? "补一句你是怎么想的。" : "确认题目答案和评分规则没有进入证明草稿。",
                safetyNote: "不判分、不自动通过、不发成长积分。",
                sortOrder: 20,
                requiresCompletion: true,
                requiresConsent: false,
                requiresModeration: false,
                requiresGuardianReview: true,
                requiresAllowlist: false,
                hasAnomaly: false,
                rewardPressureBlocked: false,
                visibleToChild: true,
                visibleToGuardian: true
            ),
            item(
                kind: .creativeStatement,
                role: role,
                status: .waitingConsent,
                childInstruction: "先写作品说明，等家长同意和审核后才能展示。",
                guardianInstruction: "创作证明需要孩子同意、家长确认和内容审核；未通过前不能进荣誉墙或奖励建议。",
                missingReason: "还要等同意和审核。",
                nextStep: role == .child ? "先保存想法，等家长一起看。" : "确认同意、审核和可见范围。",
                safetyNote: "不上传媒体、不发布荣誉墙、不授徽章。",
                sortOrder: 30,
                requiresCompletion: false,
                requiresConsent: true,
                requiresModeration: true,
                requiresGuardianReview: true,
                requiresAllowlist: false,
                hasAnomaly: false,
                rewardPressureBlocked: false,
                visibleToChild: true,
                visibleToGuardian: true
            ),
            item(
                kind: .externalResourceNote,
                role: role,
                status: .blocked,
                childInstruction: "外部视频或网页先只写学到了什么，不点链接、不贴原始地址。",
                guardianInstruction: "外部资源缺白名单/重定向复核前不能成为可提交证明，原始 URL 不进入公开摘要。",
                missingReason: "外部资源还没确认安全。",
                nextStep: role == .child ? "写一句你学到的内容，等家长确认资源。" : "核对 allowlist、年龄适配、版权和重定向。",
                safetyNote: "不打开外链、不显示原始链接、不上传截图。",
                sortOrder: 40,
                requiresCompletion: false,
                requiresConsent: false,
                requiresModeration: false,
                requiresGuardianReview: true,
                requiresAllowlist: true,
                hasAnomaly: false,
                rewardPressureBlocked: false,
                visibleToChild: true,
                visibleToGuardian: true
            ),
            item(
                kind: .wearableActivitySummary,
                role: role,
                status: .waitingReview,
                childInstruction: "运动证明先写今天做了什么运动，数据要等大人确认。",
                guardianInstruction: "可穿戴运动证明存在异常/跨设备风险，确认前不能建议成长积分或能力卡运动维度升级。",
                missingReason: "运动数据还要人工复核。",
                nextStep: role == .child ? "写运动感受，等家长看数据。" : "复核设备来源、时间窗口、异常分和跨孩子风险。",
                safetyNote: "不读 HealthKit、不发成长积分、不更新能力卡。",
                sortOrder: 50,
                requiresCompletion: false,
                requiresConsent: false,
                requiresModeration: false,
                requiresGuardianReview: true,
                requiresAllowlist: false,
                hasAnomaly: true,
                rewardPressureBlocked: false,
                visibleToChild: true,
                visibleToGuardian: true
            ),
            item(
                kind: .rewardBoundary,
                role: role,
                status: .blocked,
                childInstruction: "证明没定稿前不要催奖励，先把今天做的事说清楚。",
                guardianInstruction: "奖励、徽章和能力卡更新都必须等证明链定稿、申诉窗口和人工复核结束。",
                missingReason: "证明还没定稿，不能用奖励催促。",
                nextStep: role == .child ? "先准备证明，再和家长聊奖励。" : "确认成长积分、奖励、徽章和能力卡都没有提前动作。",
                safetyNote: "不扣成长积分、不下单、不解锁设备、不授徽章。",
                sortOrder: 60,
                requiresCompletion: false,
                requiresConsent: false,
                requiresModeration: false,
                requiresGuardianReview: true,
                requiresAllowlist: false,
                hasAnomaly: false,
                rewardPressureBlocked: true,
                visibleToChild: true,
                visibleToGuardian: true
            ),
            item(
                kind: .guardianContext,
                role: role,
                status: .waitingReview,
                childInstruction: "",
                guardianInstruction: "家长只读查看证明准备原因、同意/审核和跨模块复核边界；孩子端不显示成人内部原因。",
                missingReason: "",
                nextStep: role == .child ? "" : "在正式复核流程确认后再允许提交。",
                safetyNote: "不确认家长、不发通知、不写账本。",
                sortOrder: 70,
                requiresCompletion: false,
                requiresConsent: false,
                requiresModeration: false,
                requiresGuardianReview: true,
                requiresAllowlist: false,
                hasAnomaly: false,
                rewardPressureBlocked: false,
                visibleToChild: false,
                visibleToGuardian: true
            )
        ]
    }

    private func item(
        kind: MobileGrowthPackProofPreparationKind,
        role: MobileGrowthPackExecutionHubRole,
        status: MobileGrowthPackProofPreparationStatus,
        childInstruction: String,
        guardianInstruction: String,
        missingReason: String,
        nextStep: String,
        safetyNote: String,
        sortOrder: Int,
        requiresCompletion: Bool,
        requiresConsent: Bool,
        requiresModeration: Bool,
        requiresGuardianReview: Bool,
        requiresAllowlist: Bool,
        hasAnomaly: Bool,
        rewardPressureBlocked: Bool,
        visibleToChild: Bool,
        visibleToGuardian: Bool
    ) -> MobileGrowthPackProofPreparationItem {
        MobileGrowthPackProofPreparationItem(
            publicPrepRef: publicRef("prep:\(kind.rawValue):\(role.rawValue):\(sortOrder)"),
            kind: kind,
            status: status,
            title: kind.title,
            instruction: role == .child ? childInstruction : guardianInstruction,
            missingReason: missingReason,
            nextStep: nextStep,
            safetyNote: safetyNote,
            visibleToChild: visibleToChild,
            visibleToGuardian: visibleToGuardian,
            requiresCompletion: requiresCompletion,
            requiresConsent: requiresConsent,
            requiresModeration: requiresModeration,
            requiresGuardianReview: requiresGuardianReview,
            requiresAllowlist: requiresAllowlist,
            hasAnomaly: hasAnomaly,
            rewardPressureBlocked: rewardPressureBlocked,
            sortOrder: sortOrder
        )
    }

    private func makeFindings(
        role: MobileGrowthPackExecutionHubRole,
        items: [MobileGrowthPackProofPreparationItem]
    ) -> [MobileGrowthPackProofPreparationFinding] {
        var findings = [
            MobileGrowthPackProofPreparationFinding(
                code: .readOnlyPreparation,
                message: "准备清单只读整理本地安全摘要，不会提交、上传、发成长积分、授徽章或解锁设备。",
                actionRequired: false,
                visibleToChild: true
            )
        ]
        if items.contains(where: \.requiresCompletion) {
            findings.append(
                MobileGrowthPackProofPreparationFinding(
                    code: .completionRequired,
                    message: role == .child ? "有的说明还要补完整。" : "存在未完成证明说明，不能提交或进入成长积分建议。",
                    actionRequired: true,
                    visibleToChild: true
                )
            )
        }
        if items.contains(where: \.requiresConsent) {
            findings.append(
                MobileGrowthPackProofPreparationFinding(
                    code: .consentRequired,
                    message: role == .child ? "创作展示要等你和家长都同意。" : "创作证明需要同意和可见范围确认。",
                    actionRequired: true,
                    visibleToChild: true
                )
            )
        }
        if role == .guardian, items.contains(where: \.requiresModeration) {
            findings.append(
                MobileGrowthPackProofPreparationFinding(
                    code: .moderationRequired,
                    message: "创作证明通过审核前不能进入荣誉墙、奖励或能力卡。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        if items.contains(where: \.requiresAllowlist) {
            findings.append(
                MobileGrowthPackProofPreparationFinding(
                    code: .externalAllowlistRequired,
                    message: role == .child ? "外部资源要等家长确认安全。" : "外部资源缺 allowlist 或重定向复核前不能提交。",
                    actionRequired: true,
                    visibleToChild: true
                )
            )
        }
        if items.contains(where: \.hasAnomaly) {
            findings.append(
                MobileGrowthPackProofPreparationFinding(
                    code: .wearableReviewRequired,
                    message: role == .child ? "运动数据要等家长确认。" : "可穿戴运动证明异常需人工复核。",
                    actionRequired: true,
                    visibleToChild: true
                )
            )
        }
        if items.contains(where: \.rewardPressureBlocked) {
            findings.append(
                MobileGrowthPackProofPreparationFinding(
                    code: .rewardPressureBlocked,
                    message: role == .child ? "先准备证明，奖励晚点再说。" : "证明定稿前不得推动奖励、徽章或能力卡更新。",
                    actionRequired: true,
                    visibleToChild: true
                )
            )
        }
        return findings.filter { role == .guardian || $0.visibleToChild }
    }

    private func summary(
        role: MobileGrowthPackExecutionHubRole,
        allItems: [MobileGrowthPackProofPreparationItem],
        visibleItems: [MobileGrowthPackProofPreparationItem],
        findings: [MobileGrowthPackProofPreparationFinding]
    ) -> MobileGrowthPackProofPreparationPublicSummary {
        MobileGrowthPackProofPreparationPublicSummary(
            role: role,
            itemCount: allItems.count,
            visibleItemCount: visibleItems.count,
            readyCount: visibleItems.filter { $0.status == .readyToPrepare }.count,
            blockedCount: visibleItems.filter { $0.status == .blocked }.count,
            consentRequiredCount: visibleItems.filter(\.requiresConsent).count,
            moderationRequiredCount: visibleItems.filter(\.requiresModeration).count,
            reviewRequiredCount: visibleItems.filter(\.requiresGuardianReview).count,
            findingCodes: findings.map(\.code)
        )
    }

    private func publicRef(_ seed: String) -> String {
        "gpp-\(Self.stableHash("\(Self.redactionSalt):\(seed)"))"
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
