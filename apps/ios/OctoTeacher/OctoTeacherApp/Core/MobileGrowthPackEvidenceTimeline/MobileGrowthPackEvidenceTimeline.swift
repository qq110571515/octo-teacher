import Foundation

/// iOS 成长包证据时间线的纯本地只读投影。
///
/// 这一层只把成长包执行中心里的证明、复核和奖励建议状态整理成孩子/家长可读时间线。
/// 它不读取真实 proof/ref，不上传媒体，不写账本，不发成长积分，也不触发任何设备动作。
enum MobileGrowthPackEvidenceTimelineNodeKind: String, CaseIterable, Equatable {
    case homeworkProof = "homework_proof"
    case quizSelfCheck = "quiz_self_check"
    case externalResource = "external_resource"
    case creativeProof = "creative_proof"
    case teacherReview = "teacher_review"
    case guardianReview = "guardian_review"
    case relativeEncouragement = "relative_encouragement"
    case rewardReview = "reward_review"
    case familyHonor = "family_honor"

    var title: String {
        switch self {
        case .homeworkProof: return "作业证明"
        case .quizSelfCheck: return "测验自检"
        case .externalResource: return "学习资源"
        case .creativeProof: return "创作证明"
        case .teacherReview: return "老师确认"
        case .guardianReview: return "家长确认"
        case .relativeEncouragement: return "亲友鼓励"
        case .rewardReview: return "奖励复核"
        case .familyHonor: return "家庭荣誉"
        }
    }

    var executionStepKind: MobileGrowthPackExecutionHubStepKind {
        switch self {
        case .homeworkProof, .teacherReview: return .schoolHomework
        case .quizSelfCheck: return .quizSelfCheck
        case .externalResource: return .externalResource
        case .creativeProof: return .creativeShowcase
        case .guardianReview: return .creatorRubric
        case .relativeEncouragement, .familyHonor: return .familyHonor
        case .rewardReview: return .rewardFulfillment
        }
    }
}

enum MobileGrowthPackEvidenceTimelineNodeStatus: String, Equatable {
    case ready
    case waitingReview = "waiting_review"
    case needsMoreEvidence = "needs_more_evidence"
    case blocked

    var label: String {
        switch self {
        case .ready: return "已准备"
        case .waitingReview: return "等复核"
        case .needsMoreEvidence: return "补证明"
        case .blocked: return "已阻断"
        }
    }
}

enum MobileGrowthPackEvidenceTimelineFindingCode: String, Equatable {
    case readOnlyTimeline = "READ_ONLY_TIMELINE"
    case evidenceGap = "EVIDENCE_GAP"
    case teacherReviewRequired = "TEACHER_REVIEW_REQUIRED"
    case guardianReviewRequired = "GUARDIAN_REVIEW_REQUIRED"
    case rewardReviewRequired = "REWARD_REVIEW_REQUIRED"
    case unsafePayloadBlocked = "UNSAFE_PAYLOAD_BLOCKED"
}

struct MobileGrowthPackEvidenceTimelineNode: Identifiable, Equatable {
    var publicNodeRef: String
    var kind: MobileGrowthPackEvidenceTimelineNodeKind
    var status: MobileGrowthPackEvidenceTimelineNodeStatus
    var title: String
    var detail: String
    var nextStep: String
    var safetyNote: String
    var visibleToChild: Bool
    var visibleToGuardian: Bool
    var requiresTeacherReview: Bool
    var requiresGuardianReview: Bool
    var hasEvidenceGap: Bool
    var rewardRisk: Bool
    var sortOrder: Int

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
    let publishesContent = false
    let createsOrder = false
    let writesEntitlement = false

    var id: String { publicNodeRef }

    var displayValues: [String] {
        [
            publicNodeRef,
            kind.rawValue,
            kind.title,
            kind.executionStepKind.rawValue,
            status.rawValue,
            status.label,
            title,
            detail,
            nextStep,
            safetyNote
        ]
    }

    var hasTriggeredSideEffect: Bool {
        callsNetwork || callsAiProvider || callsLocalModel || callsLms || writesSchoolSystem
            || writesLedger || grantsCredit || unlocksDevice || sendsNotification || opensExternalLink
            || opensCamera || opensPhotoLibrary || opensFilePicker || uploadsMedia || publishesContent
            || createsOrder || writesEntitlement
    }
}

struct MobileGrowthPackEvidenceTimelineFinding: Identifiable, Equatable {
    var code: MobileGrowthPackEvidenceTimelineFindingCode
    var message: String
    var actionRequired: Bool
    var visibleToChild: Bool

    var id: String { code.rawValue }
    var displayValues: [String] { [code.rawValue, message] }
}

struct MobileGrowthPackEvidenceTimelinePublicSummary: Equatable {
    var role: MobileGrowthPackExecutionHubRole
    var nodeCount: Int
    var visibleNodeCount: Int
    var evidenceGapCount: Int
    var reviewRequiredCount: Int
    var teacherReviewCount: Int
    var guardianReviewCount: Int
    var rewardReviewCount: Int
    var findingCodes: [MobileGrowthPackEvidenceTimelineFindingCode]

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
    let publishesContent = false
    let createsOrder = false
    let writesEntitlement = false

    var hasTriggeredSideEffect: Bool {
        callsNetwork || callsAiProvider || callsLocalModel || callsLms || writesSchoolSystem
            || writesLedger || grantsCredit || unlocksDevice || sendsNotification || opensExternalLink
            || opensCamera || opensPhotoLibrary || opensFilePicker || uploadsMedia || publishesContent
            || createsOrder || writesEntitlement
    }
}

struct MobileGrowthPackEvidenceTimeline: Equatable {
    var role: MobileGrowthPackExecutionHubRole
    var title: String
    var subtitle: String
    var audienceNote: String
    var nodes: [MobileGrowthPackEvidenceTimelineNode]
    var findings: [MobileGrowthPackEvidenceTimelineFinding]
    var publicSummary: MobileGrowthPackEvidenceTimelinePublicSummary

    var displayValues: [String] {
        [role.rawValue, title, subtitle, audienceNote]
            + nodes.flatMap(\.displayValues)
            + findings.flatMap(\.displayValues)
    }

    var hasUnsafeDisplayPayload: Bool {
        MobileGrowthPackEvidenceTimelineBuilder.hasUnsafeDisplayPayload(displayValues)
    }
}

struct MobileGrowthPackEvidenceTimelineInput: Equatable {
    var generatedAt: String
    var unsafePayload: String?

    static let mock = MobileGrowthPackEvidenceTimelineInput(
        generatedAt: "2026-06-25T00:40:00.000Z",
        unsafePayload: nil
    )
}

struct MobileGrowthPackEvidenceTimelineBuilder {
    private static let redactionSalt = "mobile-growth-pack-evidence-timeline-v1"
    private static let sensitiveMarkers = [
        "child:", "family:", "school:", "teacher:", "guardian:", "relative:", "creator:",
        "pack:", "homework:", "quiz:", "question:", "answer key", "answerkey", "答案键",
        "proof:", "media:", "photo:", "screenshot:", "transcript", "provider:", "model:",
        "resource:", "link:", "url:", "showcase:", "reward:", "order:", "inventory:",
        "address:", "ledger:", "device:", "entitlement:", "publicref", "task:", "claim:",
        "token", "api_key", "apikey", "secret", "credit amount", "成长积分金额", "账本明细",
        "设备命令", "http://", "https://", "file://", "/users/", "/volumes/",
        "192.168.", ".local"
    ]

    func build(
        role: MobileGrowthPackExecutionHubRole,
        input: MobileGrowthPackEvidenceTimelineInput = .mock
    ) -> MobileGrowthPackEvidenceTimeline {
        if let unsafePayload = input.unsafePayload, Self.hasUnsafeDisplayPayload([unsafePayload]) {
            return blockedTimeline(role: role)
        }

        let allNodes = makeNodes(for: role)
        let visibleNodes = allNodes.filter { node in
            switch role {
            case .child: return node.visibleToChild
            case .guardian: return node.visibleToGuardian
            }
        }
        .sorted { left, right in
            if left.sortOrder == right.sortOrder {
                return left.publicNodeRef < right.publicNodeRef
            }
            return left.sortOrder < right.sortOrder
        }
        let findings = makeFindings(role: role, nodes: visibleNodes)

        return MobileGrowthPackEvidenceTimeline(
            role: role,
            title: role == .child ? "成长包证据时间线" : "成长包证据复核线",
            subtitle: role == .child
                ? "按顺序看哪些证明已准备、哪些还要补充；这里只读，不会上传或发奖励。"
                : "按时间线复核证明缺口、家校确认、亲友鼓励和奖励履约建议。",
            audienceNote: role == .child
                ? "这里只显示安全提示和下一步；证明通过仍要等家长或老师确认。"
                : "这里只读整理证据状态；真正批准、给成长积分、发布荣誉或履约奖励仍走正式流程。",
            nodes: visibleNodes,
            findings: findings,
            publicSummary: summary(role: role, allNodes: allNodes, visibleNodes: visibleNodes, findings: findings)
        )
    }

    static func hasUnsafeDisplayPayload(_ values: [String]) -> Bool {
        let joined = values.joined(separator: " ").lowercased()
        return sensitiveMarkers.contains { joined.contains($0) }
    }

    private func blockedTimeline(role: MobileGrowthPackExecutionHubRole) -> MobileGrowthPackEvidenceTimeline {
        let finding = MobileGrowthPackEvidenceTimelineFinding(
            code: .unsafePayloadBlocked,
            message: "证据时间线发现不安全字段，已隐藏节点，等待家长在正式流程复核。",
            actionRequired: true,
            visibleToChild: true
        )
        return MobileGrowthPackEvidenceTimeline(
            role: role,
            title: role == .child ? "成长包证据时间线" : "成长包证据复核线",
            subtitle: "内容已安全隐藏；本地页面不会继续展示原始字段。",
            audienceNote: role == .child
                ? "这里只显示安全提示和下一步；证明通过仍要等家长或老师确认。"
                : "这里只读整理证据状态；真正批准仍走正式流程。",
            nodes: [],
            findings: [finding],
            publicSummary: MobileGrowthPackEvidenceTimelinePublicSummary(
                role: role,
                nodeCount: 0,
                visibleNodeCount: 0,
                evidenceGapCount: 1,
                reviewRequiredCount: 1,
                teacherReviewCount: 0,
                guardianReviewCount: 1,
                rewardReviewCount: 0,
                findingCodes: [.unsafePayloadBlocked]
            )
        )
    }

    private func makeNodes(for role: MobileGrowthPackExecutionHubRole) -> [MobileGrowthPackEvidenceTimelineNode] {
        [
            node(
                kind: .homeworkProof,
                role: role,
                status: .waitingReview,
                childDetail: "作业目标和自检已整理，等老师或家长确认。",
                guardianDetail: "作业证明等待家校复核；退回、逾期和申诉冻结仍要走正式流程。",
                nextStep: role == .child ? "检查步骤是否完整，再等确认。" : "查看老师确认和家长确认是否都到位。",
                safetyNote: "不提交作业、不写学校系统。",
                sortOrder: 10,
                requiresTeacherReview: true,
                requiresGuardianReview: true,
                hasEvidenceGap: false,
                rewardRisk: false
            ),
            node(
                kind: .quizSelfCheck,
                role: role,
                status: .needsMoreEvidence,
                childDetail: "先补充思路说明；页面不会显示答案。",
                guardianDetail: "测验自检缺少可复核思路，不能直接作为成长积分依据。",
                nextStep: role == .child ? "写下自己怎么想，再请家长或老师看。" : "确认是否需要人工复核。",
                safetyNote: "不判分、不保存答案、不发奖励。",
                sortOrder: 20,
                requiresTeacherReview: false,
                requiresGuardianReview: true,
                hasEvidenceGap: true,
                rewardRisk: false
            ),
            node(
                kind: .externalResource,
                role: role,
                status: .ready,
                childDetail: "学习资源只显示目标和安全提示；不会打开外部链接。",
                guardianDetail: "外部资源只读显示白名单、年龄适配和证明边界。",
                nextStep: role == .child ? "按目标学习后，再用安全方式说明完成情况。" : "复核来源可信和版权边界。",
                safetyNote: "不打开外链、不下载媒体。",
                sortOrder: 30,
                requiresTeacherReview: false,
                requiresGuardianReview: role == .guardian,
                hasEvidenceGap: false,
                rewardRisk: false
            ),
            node(
                kind: .creativeProof,
                role: role,
                status: .waitingReview,
                childDetail: "创作证明等待家长确认，公开前保持家庭私密。",
                guardianDetail: "创作证明需要同意、内容审核、可见范围和撤回边界确认。",
                nextStep: role == .child ? "先做创作自检，不上传照片。" : "确认是否允许进入荣誉墙或亲友可见。",
                safetyNote: "不打开相册、不上传媒体、不发布作品。",
                sortOrder: 40,
                requiresTeacherReview: false,
                requiresGuardianReview: true,
                hasEvidenceGap: false,
                rewardRisk: false
            ),
            node(
                kind: .teacherReview,
                role: role,
                status: .waitingReview,
                childDetail: "老师确认还在等待中。",
                guardianDetail: "老师确认还未完成；不能把学校作业当作已通过。",
                nextStep: role == .child ? "等老师确认后再看下一步。" : "等待老师验证或处理退回原因。",
                safetyNote: "不冒充老师、不写学校系统。",
                sortOrder: 50,
                requiresTeacherReview: true,
                requiresGuardianReview: false,
                hasEvidenceGap: false,
                rewardRisk: false
            ),
            node(
                kind: .guardianReview,
                role: role,
                status: .waitingReview,
                childDetail: "家长确认还在等待中。",
                guardianDetail: "家长确认节点只读展示，不会批准、扣分或发成长积分。",
                nextStep: role == .child ? "等家长看完再继续。" : "到正式复核流程处理确认。",
                safetyNote: "不批准任务、不写账本。",
                sortOrder: 60,
                requiresTeacherReview: false,
                requiresGuardianReview: true,
                hasEvidenceGap: false,
                rewardRisk: false
            ),
            node(
                kind: .relativeEncouragement,
                role: role,
                status: .ready,
                childDetail: "亲友鼓励只显示安全摘要，不会产生奖励压力。",
                guardianDetail: "亲友鼓励需经过可见范围和关系权限检查。",
                nextStep: role == .child ? "把鼓励当作支持，不代表自动加分。" : "复核亲友可见范围和评论边界。",
                safetyNote: "不通知亲友、不发布社交内容。",
                sortOrder: 70,
                requiresTeacherReview: false,
                requiresGuardianReview: role == .guardian,
                hasEvidenceGap: false,
                rewardRisk: false
            ),
            node(
                kind: .rewardReview,
                role: role,
                status: .needsMoreEvidence,
                childDetail: "奖励要等证明和家长确认都完成；这里不会兑换。",
                guardianDetail: "证据链未定稿前不能消耗成长积分或履约奖励。",
                nextStep: role == .child ? "先完成证明，再和家长商量奖励。" : "确认成长积分、库存和履约风险后再走正式流程。",
                safetyNote: "不扣成长积分、不下单、不解锁设备。",
                sortOrder: 80,
                requiresTeacherReview: false,
                requiresGuardianReview: true,
                hasEvidenceGap: true,
                rewardRisk: true
            ),
            node(
                kind: .familyHonor,
                role: role,
                status: .ready,
                childDetail: "家庭荣誉可先保存在家庭里，公开前要家长确认。",
                guardianDetail: "荣誉墙和能力卡只读预览，发布、撤回和申诉仍走正式流程。",
                nextStep: role == .child ? "记录亮点，先保持家庭私密。" : "复核哪些内容可进入荣誉墙。",
                safetyNote: "不授徽章、不改能力卡、不公开发布。",
                sortOrder: 90,
                requiresTeacherReview: false,
                requiresGuardianReview: role == .guardian,
                hasEvidenceGap: false,
                rewardRisk: false
            )
        ]
    }

    private func node(
        kind: MobileGrowthPackEvidenceTimelineNodeKind,
        role: MobileGrowthPackExecutionHubRole,
        status: MobileGrowthPackEvidenceTimelineNodeStatus,
        childDetail: String,
        guardianDetail: String,
        nextStep: String,
        safetyNote: String,
        sortOrder: Int,
        requiresTeacherReview: Bool,
        requiresGuardianReview: Bool,
        hasEvidenceGap: Bool,
        rewardRisk: Bool
    ) -> MobileGrowthPackEvidenceTimelineNode {
        MobileGrowthPackEvidenceTimelineNode(
            publicNodeRef: publicRef("node:\(kind.rawValue):\(role.rawValue):\(sortOrder)"),
            kind: kind,
            status: status,
            title: kind.title,
            detail: role == .child ? childDetail : guardianDetail,
            nextStep: nextStep,
            safetyNote: safetyNote,
            visibleToChild: true,
            visibleToGuardian: true,
            requiresTeacherReview: requiresTeacherReview,
            requiresGuardianReview: requiresGuardianReview,
            hasEvidenceGap: hasEvidenceGap,
            rewardRisk: rewardRisk,
            sortOrder: sortOrder
        )
    }

    private func makeFindings(
        role: MobileGrowthPackExecutionHubRole,
        nodes: [MobileGrowthPackEvidenceTimelineNode]
    ) -> [MobileGrowthPackEvidenceTimelineFinding] {
        var findings: [MobileGrowthPackEvidenceTimelineFinding] = [
            MobileGrowthPackEvidenceTimelineFinding(
                code: .readOnlyTimeline,
                message: "证据时间线只读展示本地安全摘要，不会上传、批准、发成长积分或解锁设备。",
                actionRequired: false,
                visibleToChild: true
            )
        ]
        if nodes.contains(where: \.hasEvidenceGap) {
            findings.append(
                MobileGrowthPackEvidenceTimelineFinding(
                    code: .evidenceGap,
                    message: role == .child ? "有证明还要补充。" : "存在证明缺口，不能进入成长积分或奖励履约。",
                    actionRequired: true,
                    visibleToChild: true
                )
            )
        }
        if nodes.contains(where: \.requiresTeacherReview) {
            findings.append(
                MobileGrowthPackEvidenceTimelineFinding(
                    code: .teacherReviewRequired,
                    message: role == .child ? "有节点要等老师确认。" : "学校相关证明需要老师确认。",
                    actionRequired: true,
                    visibleToChild: true
                )
            )
        }
        if nodes.contains(where: \.requiresGuardianReview) {
            findings.append(
                MobileGrowthPackEvidenceTimelineFinding(
                    code: .guardianReviewRequired,
                    message: role == .child ? "有节点要等家长确认。" : "家长需复核证明、同意、荣誉和奖励边界。",
                    actionRequired: true,
                    visibleToChild: true
                )
            )
        }
        if role == .guardian, nodes.contains(where: \.rewardRisk) {
            findings.append(
                MobileGrowthPackEvidenceTimelineFinding(
                    code: .rewardReviewRequired,
                    message: "奖励履约只读提示；证据链定稿前不能消耗成长积分、下单或解锁设备。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        return findings.filter { role == .guardian || $0.visibleToChild }
    }

    private func summary(
        role: MobileGrowthPackExecutionHubRole,
        allNodes: [MobileGrowthPackEvidenceTimelineNode],
        visibleNodes: [MobileGrowthPackEvidenceTimelineNode],
        findings: [MobileGrowthPackEvidenceTimelineFinding]
    ) -> MobileGrowthPackEvidenceTimelinePublicSummary {
        MobileGrowthPackEvidenceTimelinePublicSummary(
            role: role,
            nodeCount: allNodes.count,
            visibleNodeCount: visibleNodes.count,
            evidenceGapCount: visibleNodes.filter(\.hasEvidenceGap).count,
            reviewRequiredCount: visibleNodes.filter { $0.requiresTeacherReview || $0.requiresGuardianReview }.count,
            teacherReviewCount: visibleNodes.filter(\.requiresTeacherReview).count,
            guardianReviewCount: visibleNodes.filter(\.requiresGuardianReview).count,
            rewardReviewCount: visibleNodes.filter(\.rewardRisk).count,
            findingCodes: findings.map(\.code)
        )
    }

    private func publicRef(_ seed: String) -> String {
        "gpet-\(Self.stableHash("\(Self.redactionSalt):\(seed)"))"
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
