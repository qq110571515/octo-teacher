import Foundation

/// iOS 测验练习 / 自检工作台的纯本地安全投影。
///
/// 该层只把成长包 Manifest 中的 quiz 内容和 AI 作业引导中的安全意图组织成练习壳：
/// 不保存真实答案，不展示 answer key，不自动判分，不上传证明，不写账本，不发成长积分，不解锁设备。
enum MobileQuizSelfCheckViewerRole: String, CaseIterable, Equatable {
    case child
    case guardian

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        }
    }

    var note: String {
        switch self {
        case .child:
            return "这里帮你检查思路和格式，不会直接给答案，也不会自动判分。"
        case .guardian:
            return "只读查看测验边界、人工复核和直接要答案风险；真正评分仍需人工或正式服务确认。"
        }
    }
}

enum MobileQuizSelfCheckStatus: String, Equatable {
    case practiceOnly
    case selfCheck
    case needsReflection
    case guardianReview
    case blocked

    var label: String {
        switch self {
        case .practiceOnly: return "练习模式"
        case .selfCheck: return "自检中"
        case .needsReflection: return "回到思路"
        case .guardianReview: return "需复核"
        case .blocked: return "已阻断"
        }
    }
}

enum MobileQuizAnswerFormat: String, Equatable {
    case shortReasoning
    case checklist
    case explainInOwnWords

    var label: String {
        switch self {
        case .shortReasoning: return "简短说明"
        case .checklist: return "清单核对"
        case .explainInOwnWords: return "用自己的话解释"
        }
    }
}

struct MobileQuizSelfCheckPrompt: Identifiable, Equatable {
    var publicQuestionRef: String
    var title: String
    var prompt: String
    var answerFormat: MobileQuizAnswerFormat
    var status: MobileQuizSelfCheckStatus
    var selfCheckItems: [String]
    var nextStep: String
    var visibleToChild: Bool

    let revealsAnswerKey = false
    let givesDirectAnswer = false
    let storesRawAnswer = false
    let autoGrades = false
    let uploadsProof = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false

    var id: String { publicQuestionRef }

    var displayValues: [String] {
        [
            title,
            prompt,
            answerFormat.rawValue,
            answerFormat.label,
            status.rawValue,
            status.label,
            nextStep
        ] + selfCheckItems
    }
}

struct MobileQuizSelfCheckProofSummary: Identifiable, Equatable {
    var publicProofRef: String
    var title: String
    var verifierLabels: [String]
    var instructions: String

    let uploadsProof = false
    let writesSchoolSystem = false
    let writesLedger = false

    var id: String { publicProofRef }

    var displayValues: [String] { [title, instructions] + verifierLabels }
}

struct MobileQuizSelfCheckRisk: Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var actionRequired: Bool

    var displayValues: [String] { [id, title, detail] }
}

struct MobileQuizSelfCheckPublicSummary: Equatable {
    var role: MobileQuizSelfCheckViewerRole
    var promptCount: Int
    var selfCheckCount: Int
    var proofRequirementCount: Int
    var guardianReviewCount: Int
    var directAnswerRiskCount: Int
    var blockedCount: Int

    let revealsAnswerKey = false
    let givesDirectAnswer = false
    let storesRawAnswer = false
    let autoGrades = false
    let callsAIProvider = false
    let callsNetwork = false
    let callsSchoolSystem = false
    let opensWebView = false
    let uploadsProof = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false

    var hasTriggeredSideEffect: Bool {
        revealsAnswerKey || givesDirectAnswer || storesRawAnswer || autoGrades || callsAIProvider
            || callsNetwork || callsSchoolSystem || opensWebView || uploadsProof || writesLedger
            || grantsCredit || unlocksDevice
    }
}

struct MobileQuizSelfCheckPracticeWorkbench: Equatable {
    var role: MobileQuizSelfCheckViewerRole
    var title: String
    var subtitle: String
    var note: String
    var prompts: [MobileQuizSelfCheckPrompt]
    var proofs: [MobileQuizSelfCheckProofSummary]
    var risks: [MobileQuizSelfCheckRisk]
    var publicSummary: MobileQuizSelfCheckPublicSummary

    var displayValues: [String] {
        [role.rawValue, title, subtitle, note]
            + prompts.flatMap(\.displayValues)
            + proofs.flatMap(\.displayValues)
            + risks.flatMap(\.displayValues)
    }

    var hasUnsafeDisplayPayload: Bool {
        MobileQuizSelfCheckPracticeBuilder.hasUnsafeDisplayPayload(displayValues)
    }
}

struct MobileQuizSelfCheckPracticeBuilder {
    private static let sensitiveMarkers = [
        "child:", "family:", "school:", "teacher:", "guardian:", "quiz:",
        "question:", "attempt:", "answer:", "answerkey", "answer key",
        "transcript:", "provider:", "model:", "device:", "ledger:", "credit:",
        "session:", "token", "secret", "api_key", "apikey", "http://",
        "https://", "file://", "/users/", "/volumes/", "192.168."
    ]

    func build(
        role: MobileQuizSelfCheckViewerRole,
        draft: CreatorManifestPreviewDraft = .growthPackContentPlayerMock,
        messages: [AIHomeworkSessionMessage] = []
    ) -> MobileQuizSelfCheckPracticeWorkbench {
        if Self.hasUnsafeDraftPayload(draft) || messages.contains(where: \.containsUnsafeInput) {
            return blockedShell(role: role, hiddenCount: draft.contentBlocks.filter { $0.kind == .quiz }.count)
        }
        if draft.contentBlocks.contains(where: { $0.kind == .quiz && ($0.containsDirectAnswer || !$0.assetModerationPassed) }) {
            return blockedShell(role: role, hiddenCount: draft.contentBlocks.filter { $0.kind == .quiz }.count)
        }

        let directAnswerCount = messages.filter { $0.intent == .wantsDirectAnswer }.count
        let quizBlocks = draft.contentBlocks.filter { $0.kind == .quiz && (role == .guardian || $0.visibleToChild) }
        let prompts = quizBlocks.map { prompt(from: $0, role: role, directAnswerCount: directAnswerCount) }
        let proofIds = Set(quizBlocks.flatMap(\.proofRequirementIds))
        let proofs = draft.proofRequirements
            .filter { proofIds.contains($0.proofId) }
            .map { proof(from: $0, role: role) }
        let risks = riskRows(for: role, prompts: prompts, proofs: proofs, directAnswerCount: directAnswerCount)
        let summary = MobileQuizSelfCheckPublicSummary(
            role: role,
            promptCount: prompts.count,
            selfCheckCount: prompts.reduce(0) { $0 + $1.selfCheckItems.count },
            proofRequirementCount: proofs.count,
            guardianReviewCount: prompts.filter { $0.status == .guardianReview }.count,
            directAnswerRiskCount: role == .guardian ? directAnswerCount : 0,
            blockedCount: prompts.filter { $0.status == .blocked }.count
        )
        let workbench = MobileQuizSelfCheckPracticeWorkbench(
            role: role,
            title: "测验练习自检",
            subtitle: "\(draft.title) · \(draft.ageBand.gradeBand)",
            note: role.note,
            prompts: prompts,
            proofs: role == .child ? proofs.map(childProof) : proofs,
            risks: risks,
            publicSummary: summary
        )
        return workbench.hasUnsafeDisplayPayload ? blockedShell(role: role, hiddenCount: quizBlocks.count) : workbench
    }

    static func hasUnsafeDisplayPayload(_ values: [String]) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        let joined = values.joined(separator: " ").lowercased()
        return sensitiveMarkers.contains { joined.contains($0) }
    }

    private static func hasUnsafeDraftPayload(_ draft: CreatorManifestPreviewDraft) -> Bool {
        let values = [draft.title, draft.summary, draft.contentVersion, draft.ageBand.gradeBand]
            + draft.contentBlocks.flatMap { [$0.title, $0.summary] }
            + draft.proofRequirements.map(\.instructions)
        return hasUnsafeDisplayPayload(values)
    }

    private func prompt(
        from block: CreatorManifestContentDraft,
        role: MobileQuizSelfCheckViewerRole,
        directAnswerCount: Int
    ) -> MobileQuizSelfCheckPrompt {
        let status: MobileQuizSelfCheckStatus
        if block.containsDirectAnswer || !block.assetModerationPassed {
            status = .blocked
        } else if directAnswerCount > 0 {
            status = role == .guardian ? .guardianReview : .needsReflection
        } else {
            status = role == .guardian && block.guardianReviewRequired ? .guardianReview : .selfCheck
        }
        return MobileQuizSelfCheckPrompt(
            publicQuestionRef: publicRef("mq", block.contentId),
            title: block.title,
            prompt: childSafePrompt(for: block, role: role),
            answerFormat: .explainInOwnWords,
            status: status,
            selfCheckItems: selfCheckItems(for: role, directAnswerCount: directAnswerCount),
            nextStep: nextStep(for: role, directAnswerCount: directAnswerCount),
            visibleToChild: block.visibleToChild
        )
    }

    private func childSafePrompt(
        for block: CreatorManifestContentDraft,
        role: MobileQuizSelfCheckViewerRole
    ) -> String {
        if role == .guardian {
            return "复核「\(block.title)」是否只要求孩子解释思路，不暴露答案或评分规则。"
        }
        return "读完「\(block.title)」后，先用自己的话说出关键概念，再检查每一步是否有理由。"
    }

    private func selfCheckItems(for role: MobileQuizSelfCheckViewerRole, directAnswerCount: Int) -> [String] {
        if role == .guardian {
            return [
                "孩子端没有答案、答案键或评分规则。",
                "测验结果只作为人工确认前的练习状态。",
                directAnswerCount > 0 ? "出现直接要答案意图，需要回到引导或人工陪伴。" : "当前没有直接要答案意图。"
            ]
        }
        return [
            "我能说出自己用了哪个概念。",
            "我能解释为什么这样想，而不是只写结果。",
            "我检查了题目要求和自己的每一步。"
        ]
    }

    private func nextStep(for role: MobileQuizSelfCheckViewerRole, directAnswerCount: Int) -> String {
        if role == .guardian {
            return directAnswerCount > 0
                ? "请家长或老师陪孩子回到思路，不在本页判分。"
                : "确认孩子完成练习后，再到正式证明/审核流程处理。"
        }
        return directAnswerCount > 0
            ? "先写下你已经想到的第一步，再请求提示。"
            : "完成自检后，请家长或老师确认。"
    }

    private func proof(
        from proof: CreatorManifestProofRequirementDraft,
        role: MobileQuizSelfCheckViewerRole
    ) -> MobileQuizSelfCheckProofSummary {
        MobileQuizSelfCheckProofSummary(
            publicProofRef: publicRef("mqp", proof.proofId),
            title: proof.kind.label,
            verifierLabels: role == .child ? ["家长"] : proof.verifierRoles.map(\.label),
            instructions: role == .child ? "练习完成后等待家长确认，本页不上传、不判分。" : proof.instructions
        )
    }

    private func childProof(_ proof: MobileQuizSelfCheckProofSummary) -> MobileQuizSelfCheckProofSummary {
        MobileQuizSelfCheckProofSummary(
            publicProofRef: proof.publicProofRef,
            title: proof.title,
            verifierLabels: ["家长"],
            instructions: "练习完成后等待家长确认，本页不上传、不判分。"
        )
    }

    private func riskRows(
        for role: MobileQuizSelfCheckViewerRole,
        prompts: [MobileQuizSelfCheckPrompt],
        proofs: [MobileQuizSelfCheckProofSummary],
        directAnswerCount: Int
    ) -> [MobileQuizSelfCheckRisk] {
        guard role == .guardian else { return [] }
        var rows: [MobileQuizSelfCheckRisk] = [
            MobileQuizSelfCheckRisk(
                id: "no-auto-grade",
                title: "测验练习不自动判分",
                detail: "本地壳只展示自检清单，不能生成成绩、成长积分或设备解锁。",
                actionRequired: false
            )
        ]
        if !proofs.isEmpty {
            rows.append(MobileQuizSelfCheckRisk(
                id: "proof-review",
                title: "证明引用需人工确认",
                detail: "测验结果只能作为脱敏证明引用，不能在本页上传或落账。",
                actionRequired: true
            ))
        }
        if directAnswerCount > 0 {
            rows.append(MobileQuizSelfCheckRisk(
                id: "direct-answer",
                title: "直接要答案风险",
                detail: "孩子输入被折叠为风险意图，页面只引导回思路，不回显原文。",
                actionRequired: true
            ))
        }
        if prompts.contains(where: { $0.status == .blocked }) {
            rows.append(MobileQuizSelfCheckRisk(
                id: "blocked",
                title: "测验内容已阻断",
                detail: "检测到直接答案或素材审核失败，不能进入孩子练习面。",
                actionRequired: true
            ))
        }
        return rows
    }

    private func blockedShell(
        role: MobileQuizSelfCheckViewerRole,
        hiddenCount: Int
    ) -> MobileQuizSelfCheckPracticeWorkbench {
        MobileQuizSelfCheckPracticeWorkbench(
            role: role,
            title: "测验练习已被安全保护",
            subtitle: "本地安全壳",
            note: role.note,
            prompts: [],
            proofs: [],
            risks: [
                MobileQuizSelfCheckRisk(
                    id: "unsafe",
                    title: "测验内容已隐藏",
                    detail: "检测到链接、路径、答案、密钥、局域网地址或内部标识，本地壳不回显原文。",
                    actionRequired: role == .guardian
                )
            ],
            publicSummary: MobileQuizSelfCheckPublicSummary(
                role: role,
                promptCount: 0,
                selfCheckCount: 0,
                proofRequirementCount: 0,
                guardianReviewCount: 0,
                directAnswerRiskCount: 0,
                blockedCount: hiddenCount
            )
        )
    }

    private func publicRef(_ prefix: String, _ source: String) -> String {
        var hash: UInt32 = 5381
        for scalar in "mobile-quiz-self-check:\(source)".unicodeScalars {
            hash = (hash &* 33) ^ (scalar.value & 0xFFFF)
        }
        return "\(prefix)-\(String(hash, radix: 36))"
    }
}
