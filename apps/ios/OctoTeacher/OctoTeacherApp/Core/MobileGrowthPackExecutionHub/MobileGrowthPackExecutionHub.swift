import Foundation

/// iOS 成长包执行中心的纯本地只读聚合。
///
/// 这一层把已落地的学校作业联动、测验自检、外部资源、创作展示、创作者量规、
/// 奖励履约和家庭荣誉安全壳收拢成孩子/家长可进入的执行入口。它只生成展示模型，
/// 不提交作业、不判分、不上传证明、不写账本、不发成长积分、不解锁设备。
enum MobileGrowthPackExecutionHubRole: String, CaseIterable, Equatable {
    case child
    case guardian

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        }
    }

    var audienceNote: String {
        switch self {
        case .child:
            return "这里只看今天能做什么、下一步和安全提示；所有完成仍要等家长或老师确认。"
        case .guardian:
            return "只读复核成长包步骤、证明、老师/亲友参与和奖励履约风险；真正批准仍走正式流程。"
        }
    }
}

enum MobileGrowthPackExecutionHubStepKind: String, CaseIterable, Equatable {
    case schoolHomework = "school_homework"
    case quizSelfCheck = "quiz_self_check"
    case externalResource = "external_resource"
    case creativeShowcase = "creative_showcase"
    case creatorRubric = "creator_rubric"
    case rewardFulfillment = "reward_fulfillment"
    case familyHonor = "family_honor"

    var title: String {
        switch self {
        case .schoolHomework: return "学校作业联动"
        case .quizSelfCheck: return "测验自检"
        case .externalResource: return "外部学习资源"
        case .creativeShowcase: return "创作展示"
        case .creatorRubric: return "创作者量规"
        case .rewardFulfillment: return "奖励库存履约"
        case .familyHonor: return "家庭荣誉"
        }
    }
}

enum MobileGrowthPackExecutionHubStepStatus: String, Equatable {
    case ready
    case active
    case reviewRequired = "review_required"
    case blocked

    var label: String {
        switch self {
        case .ready: return "可开始"
        case .active: return "进行中"
        case .reviewRequired: return "需复核"
        case .blocked: return "已阻断"
        }
    }
}

enum MobileGrowthPackExecutionHubDestination: String, Equatable, CaseIterable {
    case schoolHomework = "school_homework"
    case quizSelfCheck = "quiz_self_check"
    case externalResource = "external_resource"
    case creativeShowcase = "creative_showcase"
    case creatorRubric = "creator_rubric"
    case rewardFulfillment = "reward_fulfillment"
    case familyHonor = "family_honor"
}

enum MobileGrowthPackExecutionHubFindingCode: String, Equatable {
    case readOnlyReady = "READ_ONLY_READY"
    case guardianReviewRequired = "GUARDIAN_REVIEW_REQUIRED"
    case teacherReviewRequired = "TEACHER_REVIEW_REQUIRED"
    case rewardFulfillmentReview = "REWARD_FULFILLMENT_REVIEW"
    case unsafePayloadBlocked = "UNSAFE_PAYLOAD_BLOCKED"
}

struct MobileGrowthPackExecutionHubStep: Identifiable, Equatable {
    var publicStepRef: String
    var kind: MobileGrowthPackExecutionHubStepKind
    var title: String
    var detail: String
    var status: MobileGrowthPackExecutionHubStepStatus
    var badge: String
    var nextStep: String
    var safetyNote: String
    var destination: MobileGrowthPackExecutionHubDestination
    var visibleToChild: Bool
    var visibleToGuardian: Bool
    var requiresGuardianReview: Bool
    var requiresTeacherReview: Bool
    var blocked: Bool

    let callsNetwork = false
    let callsAiProvider = false
    let callsLocalModel = false
    let callsLms = false
    let writesSchoolSystem = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let sendsNotification = false
    let opensExternalLink = false
    let opensCamera = false
    let opensPhotoLibrary = false
    let opensFilePicker = false
    let uploadsMedia = false
    let createsOrder = false
    let writesEntitlement = false

    var id: String { publicStepRef }

    var displayValues: [String] {
        [
            kind.rawValue,
            title,
            detail,
            status.rawValue,
            status.label,
            badge,
            nextStep,
            safetyNote,
            destination.rawValue
        ]
    }

    var hasTriggeredSideEffect: Bool {
        callsNetwork || callsAiProvider || callsLocalModel || callsLms || writesSchoolSystem
            || writesLedger || grantsCredit || unlocksDevice || sendsNotification || opensExternalLink
            || opensCamera || opensPhotoLibrary || opensFilePicker || uploadsMedia || createsOrder
            || writesEntitlement
    }
}

struct MobileGrowthPackExecutionHubFinding: Identifiable, Equatable {
    var code: MobileGrowthPackExecutionHubFindingCode
    var message: String
    var actionRequired: Bool
    var visibleToChild: Bool

    var id: String { code.rawValue }
    var displayValues: [String] { [code.rawValue, message] }
}

struct MobileGrowthPackExecutionHubPublicSummary: Equatable {
    var role: MobileGrowthPackExecutionHubRole
    var stepCount: Int
    var visibleStepCount: Int
    var reviewRequiredCount: Int
    var blockedCount: Int
    var teacherReviewCount: Int
    var guardianReviewCount: Int
    var rewardReviewCount: Int
    var findingCodes: [MobileGrowthPackExecutionHubFindingCode]

    let callsNetwork = false
    let callsAiProvider = false
    let callsLocalModel = false
    let callsLms = false
    let writesSchoolSystem = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let sendsNotification = false
    let opensExternalLink = false
    let opensCamera = false
    let opensPhotoLibrary = false
    let opensFilePicker = false
    let uploadsMedia = false
    let createsOrder = false
    let writesEntitlement = false

    var hasTriggeredSideEffect: Bool {
        callsNetwork || callsAiProvider || callsLocalModel || callsLms || writesSchoolSystem
            || writesLedger || grantsCredit || unlocksDevice || sendsNotification || opensExternalLink
            || opensCamera || opensPhotoLibrary || opensFilePicker || uploadsMedia || createsOrder
            || writesEntitlement
    }
}

struct MobileGrowthPackExecutionHub: Equatable {
    var role: MobileGrowthPackExecutionHubRole
    var title: String
    var subtitle: String
    var audienceNote: String
    var steps: [MobileGrowthPackExecutionHubStep]
    var findings: [MobileGrowthPackExecutionHubFinding]
    var publicSummary: MobileGrowthPackExecutionHubPublicSummary

    var displayValues: [String] {
        [role.rawValue, title, subtitle, audienceNote]
            + steps.flatMap(\.displayValues)
            + findings.flatMap(\.displayValues)
    }

    var hasUnsafeDisplayPayload: Bool {
        MobileGrowthPackExecutionHubBuilder.hasUnsafeDisplayPayload(displayValues)
    }
}

struct MobileGrowthPackExecutionHubInput: Equatable {
    var generatedAt: String
    var unsafePayload: String?

    static let mock = MobileGrowthPackExecutionHubInput(
        generatedAt: "2026-06-25T00:00:00.000Z",
        unsafePayload: nil
    )
}

struct MobileGrowthPackExecutionHubBuilder {
    private static let redactionSalt = "mobile-growth-pack-execution-hub-v1"
    private static let sensitiveMarkers = [
        "child:", "family:", "school:", "teacher:", "guardian:", "relative:", "creator:",
        "pack:", "homework:", "quiz:", "question:", "answer key", "answerkey", "答案键",
        "attempt:", "transcript", "provider:", "model:", "resource:", "link:", "url:",
        "showcase:", "media:", "reward:", "order:", "inventory:", "address:", "ledger:",
        "device:", "entitlement:", "publicref", "task:", "claim:", "token", "api_key",
        "apikey", "secret", "credit amount", "成长积分金额", "账本明细", "设备命令",
        "http://", "https://", "file://", "/users/", "/volumes/", "192.168.", ".local"
    ]

    func build(
        role: MobileGrowthPackExecutionHubRole,
        input: MobileGrowthPackExecutionHubInput = .mock
    ) -> MobileGrowthPackExecutionHub {
        if let unsafePayload = input.unsafePayload, Self.hasUnsafeDisplayPayload([unsafePayload]) {
            return blockedHub(role: role)
        }

        let allSteps = makeSteps(for: role)
        let visibleSteps = allSteps.filter { step in
            switch role {
            case .child: return step.visibleToChild
            case .guardian: return step.visibleToGuardian
            }
        }
        let findings = makeFindings(role: role, steps: visibleSteps)

        return MobileGrowthPackExecutionHub(
            role: role,
            title: role == .child ? "成长包执行中心" : "成长包执行复核中心",
            subtitle: role == .child
                ? "把今天的作业、测验、资源、创作和奖励下一步放在一起；这里只读，不会自动完成。"
                : "把成长包步骤、证明、家校复核、亲友参与和奖励履约风险聚合成只读复核台。",
            audienceNote: role.audienceNote,
            steps: visibleSteps,
            findings: findings,
            publicSummary: summary(role: role, allSteps: allSteps, visibleSteps: visibleSteps, findings: findings)
        )
    }

    static func hasUnsafeDisplayPayload(_ values: [String]) -> Bool {
        let joined = values.joined(separator: " ").lowercased()
        return sensitiveMarkers.contains { joined.contains($0) }
    }

    private func blockedHub(role: MobileGrowthPackExecutionHubRole) -> MobileGrowthPackExecutionHub {
        let finding = MobileGrowthPackExecutionHubFinding(
            code: .unsafePayloadBlocked,
            message: "执行中心发现不安全字段，已隐藏成长包步骤，等待家长在正式流程复核。",
            actionRequired: true,
            visibleToChild: true
        )
        return MobileGrowthPackExecutionHub(
            role: role,
            title: role == .child ? "成长包执行中心" : "成长包执行复核中心",
            subtitle: "内容已安全隐藏；本地页面不会继续展示原始字段。",
            audienceNote: role.audienceNote,
            steps: [],
            findings: [finding],
            publicSummary: MobileGrowthPackExecutionHubPublicSummary(
                role: role,
                stepCount: 0,
                visibleStepCount: 0,
                reviewRequiredCount: 0,
                blockedCount: 1,
                teacherReviewCount: 0,
                guardianReviewCount: 1,
                rewardReviewCount: 0,
                findingCodes: [.unsafePayloadBlocked]
            )
        )
    }

    private func makeSteps(for role: MobileGrowthPackExecutionHubRole) -> [MobileGrowthPackExecutionHubStep] {
        [
            step(
                kind: .schoolHomework,
                role: role,
                status: .reviewRequired,
                badge: role == .child ? "等确认" : "老师/家长复核",
                childDetail: "先完成作业目标和自检，提交后等待老师和家长确认。",
                guardianDetail: "复核作业目标、成长包关联、老师验证、家长确认和逾期/退回状态。",
                nextStep: role == .child ? "打开作业联动，按自检清单整理证明。" : "查看退回、逾期、申诉冻结和确认边界。",
                safetyNote: "不提交作业、不验证老师、不写学校系统。",
                destination: .schoolHomework,
                requiresGuardianReview: true,
                requiresTeacherReview: true
            ),
            step(
                kind: .quizSelfCheck,
                role: role,
                status: .active,
                badge: role == .child ? "练习中" : "人工复核",
                childDetail: "只看题目说明、作答格式和重新思考提示；不会显示最终答案。",
                guardianDetail: "查看测验边界、直接要答案风险、证明引用和人工复核需求。",
                nextStep: role == .child ? "打开测验自检，先说思路再检查格式。" : "确认是否需要老师或家长人工复核。",
                safetyNote: "不保存作答、不判分、不发奖励。",
                destination: .quizSelfCheck,
                requiresGuardianReview: role == .guardian,
                requiresTeacherReview: false
            ),
            step(
                kind: .externalResource,
                role: role,
                status: .ready,
                badge: "只读",
                childDetail: "查看学习目标、可信来源标签和家长陪同提醒；不会打开链接。",
                guardianDetail: "查看来源、白名单、年龄、版权、证明引用和放行边界。",
                nextStep: role == .child ? "打开资源说明，按目标学习后再提交证明。" : "复核白名单、版权和年龄适配。",
                safetyNote: "不打开外链、不下载媒体、不上传证明。",
                destination: .externalResource,
                requiresGuardianReview: role == .guardian,
                requiresTeacherReview: false
            ),
            step(
                kind: .creativeShowcase,
                role: role,
                status: .reviewRequired,
                badge: role == .child ? "等家长" : "展示复核",
                childDetail: "查看创作目标和提交前自检；作品展示要等家长确认。",
                guardianDetail: "复核创作同意、内容审核、亲友评论、奖励压力和撤回边界。",
                nextStep: role == .child ? "打开创作展示，先做自检，不上传媒体。" : "确认亲友可见范围和证明要求。",
                safetyNote: "不打开相册、不发布作品、不通知亲友。",
                destination: .creativeShowcase,
                requiresGuardianReview: true,
                requiresTeacherReview: false
            ),
            step(
                kind: .creatorRubric,
                role: role,
                status: .reviewRequired,
                badge: role == .child ? "安全检查" : "量规复核",
                childDetail: "只看适龄目标、证明下一步和安全提示。",
                guardianDetail: "查看年龄适配、量规完整性、证明角色、徽章和能力卡证据门。",
                nextStep: role == .child ? "确认这个成长包适合练习，再继续下一步。" : "复核量规缺证据、市场文案和奖励承诺。",
                safetyNote: "不发布市场、不收费、不授徽章。",
                destination: .creatorRubric,
                requiresGuardianReview: true,
                requiresTeacherReview: false
            ),
            step(
                kind: .rewardFulfillment,
                role: role,
                status: .reviewRequired,
                badge: role == .child ? "看库存" : "履约复核",
                childDetail: "看奖励能不能换、还剩多少；想换什么先告诉家长。",
                guardianDetail: "复核库存售罄、兑换预留、履约失败、退款回滚和上限边界。",
                nextStep: role == .child ? "打开奖励商店，只看状态，不会兑换。" : "确认履约风险，真实处理仍走正式流程。",
                safetyNote: "不扣积分、不发货、不解锁设备。",
                destination: .rewardFulfillment,
                requiresGuardianReview: role == .guardian,
                requiresTeacherReview: false
            ),
            step(
                kind: .familyHonor,
                role: role,
                status: .ready,
                badge: role == .child ? "可记录" : "荣誉复核",
                childDetail: "查看成长记录、徽章和鼓励故事线；公开前要等家长确认。",
                guardianDetail: "查看荣誉墙、成长球星卡、亲友参与、撤回和申诉传播。",
                nextStep: role == .child ? "记录成长亮点，先保持家庭私密。" : "复核哪些内容能进荣誉墙和亲友可见。",
                safetyNote: "不发布社交内容、不授徽章、不发通知。",
                destination: .familyHonor,
                requiresGuardianReview: role == .guardian,
                requiresTeacherReview: false
            )
        ]
    }

    private func step(
        kind: MobileGrowthPackExecutionHubStepKind,
        role: MobileGrowthPackExecutionHubRole,
        status: MobileGrowthPackExecutionHubStepStatus,
        badge: String,
        childDetail: String,
        guardianDetail: String,
        nextStep: String,
        safetyNote: String,
        destination: MobileGrowthPackExecutionHubDestination,
        requiresGuardianReview: Bool,
        requiresTeacherReview: Bool
    ) -> MobileGrowthPackExecutionHubStep {
        MobileGrowthPackExecutionHubStep(
            publicStepRef: publicRef("step:\(kind.rawValue):\(role.rawValue)"),
            kind: kind,
            title: kind.title,
            detail: role == .child ? childDetail : guardianDetail,
            status: status,
            badge: badge,
            nextStep: nextStep,
            safetyNote: safetyNote,
            destination: destination,
            visibleToChild: true,
            visibleToGuardian: true,
            requiresGuardianReview: requiresGuardianReview,
            requiresTeacherReview: requiresTeacherReview,
            blocked: status == .blocked
        )
    }

    private func makeFindings(
        role: MobileGrowthPackExecutionHubRole,
        steps: [MobileGrowthPackExecutionHubStep]
    ) -> [MobileGrowthPackExecutionHubFinding] {
        var findings: [MobileGrowthPackExecutionHubFinding] = [
            MobileGrowthPackExecutionHubFinding(
                code: .readOnlyReady,
                message: "执行中心只读聚合本地安全壳，不会自动完成任务或触发奖励。",
                actionRequired: false,
                visibleToChild: true
            )
        ]
        if steps.contains(where: \.requiresTeacherReview) {
            findings.append(
                MobileGrowthPackExecutionHubFinding(
                    code: .teacherReviewRequired,
                    message: role == .child ? "有步骤需要老师确认后才算完成。" : "学校作业相关步骤需要老师验证证据。",
                    actionRequired: true,
                    visibleToChild: true
                )
            )
        }
        if steps.contains(where: \.requiresGuardianReview) {
            findings.append(
                MobileGrowthPackExecutionHubFinding(
                    code: .guardianReviewRequired,
                    message: role == .child ? "有步骤要等家长确认。" : "家长需复核证明、同意、展示和奖励边界。",
                    actionRequired: true,
                    visibleToChild: true
                )
            )
        }
        if role == .guardian {
            findings.append(
                MobileGrowthPackExecutionHubFinding(
                    code: .rewardFulfillmentReview,
                    message: "奖励履约只给出复核提示，真实兑换、扣减、发货和设备动作仍由正式流程处理。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        return findings.filter { role == .guardian || $0.visibleToChild }
    }

    private func summary(
        role: MobileGrowthPackExecutionHubRole,
        allSteps: [MobileGrowthPackExecutionHubStep],
        visibleSteps: [MobileGrowthPackExecutionHubStep],
        findings: [MobileGrowthPackExecutionHubFinding]
    ) -> MobileGrowthPackExecutionHubPublicSummary {
        MobileGrowthPackExecutionHubPublicSummary(
            role: role,
            stepCount: allSteps.count,
            visibleStepCount: visibleSteps.count,
            reviewRequiredCount: visibleSteps.filter { $0.status == .reviewRequired }.count,
            blockedCount: visibleSteps.filter(\.blocked).count,
            teacherReviewCount: visibleSteps.filter(\.requiresTeacherReview).count,
            guardianReviewCount: visibleSteps.filter(\.requiresGuardianReview).count,
            rewardReviewCount: visibleSteps.filter { $0.kind == .rewardFulfillment && $0.requiresGuardianReview }.count,
            findingCodes: findings.map(\.code)
        )
    }

    private func publicRef(_ seed: String) -> String {
        "gpe-\(Self.stableHash("\(Self.redactionSalt):\(seed)"))"
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
