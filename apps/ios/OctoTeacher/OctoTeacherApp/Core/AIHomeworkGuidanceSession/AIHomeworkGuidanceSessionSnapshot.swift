import Foundation

/// iOS 端「AI 作业引导会话壳」只读快照。
///
/// 把已有的学校作业视图、`AIHomeworkGuidance` 安全边界和本地 mock 会话组合成一份
/// 角色感知、脱敏、无副作用的引导式会话投影：孩子输入/选择作业问题后看到苏格拉底式
/// 分步提示、追问、自检清单和下一步；家长/老师只看脱敏摘要、风险标签和是否需要人工介入。
///
/// 它只回答「现在该给孩子哪一步引导、家长老师该不该介入」，绝不真正调用 AI / 网络 /
/// 数据库 / LMS / 学校系统 / 通知 / 账本 / 设备，绝不给作业答案、代写、打分，也绝不
/// 留存原始隐私 transcript。所有内容都是本地确定性派生。
///
/// 角色边界：
/// - 孩子可见引导步骤、追问、自检清单、下一步与「AI 不直接给答案」的安抚文案。
/// - 家长/老师只看脱敏摘要、风险标签和是否需要人工介入，看不到引导步骤明细。
/// - 任何角色都看不到答案键、内部风险评分数值、跨孩子内容、原始 transcript、模型/供应商细节或成长积分金额。

enum AIHomeworkSessionViewerRole: String, Equatable, CaseIterable {
    case child
    case guardian
    case teacher

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        case .teacher: return "老师"
        }
    }

    /// 是否属于照护团队（家长/老师）视角。
    var isCareTeam: Bool { self != .child }
}

/// 孩子在会话中可以直接选择的预设问题。预设只覆盖安全意图，不含「要答案」。
enum AIHomeworkPresetQuestion: String, Equatable, CaseIterable {
    case whereToStart = "where_to_start"
    case stuckOnStep = "stuck_on_step"
    case howToCheck = "how_to_check"
    case wantUnderstanding = "want_understanding"

    var label: String {
        switch self {
        case .whereToStart: return "我不知道从哪里开始"
        case .stuckOnStep: return "我卡在某一步了"
        case .howToCheck: return "我做完了，怎么自己检查"
        case .wantUnderstanding: return "这道题为什么要这样做"
        }
    }

    var intent: AIHomeworkQuestionIntent {
        switch self {
        case .whereToStart: return .whereToStart
        case .stuckOnStep: return .stuckOnStep
        case .howToCheck: return .howToCheck
        case .wantUnderstanding: return .wantUnderstanding
        }
    }
}

/// 会话引擎对孩子一条输入的脱敏归类。绝不保留原始输入文本，只保留这个中性意图。
enum AIHomeworkQuestionIntent: String, Equatable, CaseIterable {
    case whereToStart = "where_to_start"
    case stuckOnStep = "stuck_on_step"
    case howToCheck = "how_to_check"
    case wantUnderstanding = "want_understanding"
    case wantsDirectAnswer = "wants_direct_answer"
    case offTopic = "off_topic"
    case unclear

    /// 中性意图标签：既用于孩子端回显，也用于家长/老师脱敏摘要，不含原始文本。
    var label: String {
        switch self {
        case .whereToStart: return "不知道从哪里开始"
        case .stuckOnStep: return "卡在某一步"
        case .howToCheck: return "想自己检查"
        case .wantUnderstanding: return "想理解为什么"
        case .wantsDirectAnswer: return "想要直接答案"
        case .offTopic: return "和作业无关的问题"
        case .unclear: return "问题还不清楚"
        }
    }

    /// 是否为需要引导回正轨的风险意图。
    var isRisky: Bool {
        switch self {
        case .wantsDirectAnswer, .offTopic:
            return true
        default:
            return false
        }
    }
}

/// 一条会话输入：孩子的预设选择或本地输入文本会在初始化时立即折叠成脱敏意图。
/// 结构体不保留原始文本，只保留中性意图和安全标记，避免形成原始 transcript。
struct AIHomeworkSessionMessage: Equatable {
    var intent: AIHomeworkQuestionIntent
    var containsUnsafeInput: Bool

    init(preset: AIHomeworkPresetQuestion) {
        self.intent = preset.intent
        self.containsUnsafeInput = false
    }

    init(freeText: String) {
        self.intent = Self.classifyFreeText(freeText)
        self.containsUnsafeInput = Self.hasUnsafeRawText(freeText)
    }

    private static func classifyFreeText(_ text: String) -> AIHomeworkQuestionIntent {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 2 { return .unclear }
        if contains(trimmed, directAnswerKeywords) { return .wantsDirectAnswer }
        if contains(trimmed, offTopicKeywords) { return .offTopic }
        if contains(trimmed, checkKeywords) { return .howToCheck }
        if contains(trimmed, understandingKeywords) { return .wantUnderstanding }
        if contains(trimmed, startKeywords) { return .whereToStart }
        if contains(trimmed, stuckKeywords) { return .stuckOnStep }
        return .unclear
    }

    private static func contains(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private static func hasUnsafeRawText(_ text: String) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe([text]) { return true }
        let rawPatterns = [
            "(?i)\\b(child|family|school|class|teacher|guardian|homework|submission|proof|ledger|credit|event|session|transcript|provider|model|source|ref):[a-z0-9_-]+",
            "(?i)\\b(taskId|claimId|server-secret|device-token|api[_-]?key)\\b"
        ]
        return rawPatterns.contains { pattern in
            text.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static let directAnswerKeywords = [
        "答案", "标准答案", "正确答案", "直接告诉我", "告诉我答案", "帮我写", "帮我做",
        "替我做", "替我写", "抄", "给我结果", "answer", "solve it for me"
    ]
    private static let offTopicKeywords = ["游戏", "玩", "看视频", "动画片", "无聊", "聊天", "笑话"]
    private static let checkKeywords = ["检查", "对不对", "对吗", "确认", "做完了", "复查", "核对"]
    private static let understandingKeywords = ["为什么", "为啥", "原理", "怎么来的", "什么意思", "理解"]
    private static let startKeywords = ["从哪", "怎么开始", "无从下手", "不知道开始", "第一步", "怎么入手"]
    private static let stuckKeywords = ["卡住", "卡在", "不会", "做不出", "下一步", "想不出", "难"]
}

enum AIHomeworkStepKind: String, Equatable {
    case probe
    case hint
    case check

    var label: String {
        switch self {
        case .probe: return "引导提问"
        case .hint: return "思路提示"
        case .check: return "自检"
        }
    }

    var systemImage: String {
        switch self {
        case .probe: return "questionmark.bubble"
        case .hint: return "lightbulb"
        case .check: return "checklist"
        }
    }
}

/// 单步苏格拉底式引导。护栏 `revealsAnswer` 恒为 false：步骤只提问/给思路/自检，绝不给答案。
struct AIHomeworkSocraticStep: Identifiable, Equatable {
    var order: Int
    var kind: AIHomeworkStepKind
    var prompt: String

    let revealsAnswer = false

    var id: Int { order }
}

enum AIHomeworkRiskLabel: String, Equatable, CaseIterable {
    case wantsDirectAnswer = "wants_direct_answer"
    case repeatedlyStuck = "repeatedly_stuck"
    case offTopic = "off_topic"
    case possibleFrustration = "possible_frustration"
    case unsafeContent = "unsafe_content"

    var label: String {
        switch self {
        case .wantsDirectAnswer: return "多次想要直接答案"
        case .repeatedlyStuck: return "反复卡住"
        case .offTopic: return "偏离作业主题"
        case .possibleFrustration: return "可能有畏难情绪"
        case .unsafeContent: return "输入含不安全内容"
        }
    }

    var severity: AIHomeworkSeverity {
        switch self {
        case .unsafeContent:
            return .blocker
        case .repeatedlyStuck, .possibleFrustration:
            return .warning
        case .wantsDirectAnswer, .offTopic:
            return .info
        }
    }
}

enum AIHomeworkSeverity: String, Equatable {
    case ok
    case info
    case warning
    case blocker
}

enum AIHomeworkSessionStatus: String, Equatable {
    case empty
    case awaitingChildInput = "awaiting_child_input"
    case guiding
    case selfCheck = "self_check"
    case needsHumanReview = "needs_human_review"
    case blocked

    var label: String {
        switch self {
        case .empty: return "暂无作业"
        case .awaitingChildInput: return "等待孩子提问"
        case .guiding: return "引导进行中"
        case .selfCheck: return "进入自检"
        case .needsHumanReview: return "建议人工跟进"
        case .blocked: return "已安全阻断"
        }
    }
}

enum AIHomeworkSessionFindingCode: String, Equatable {
    case sessionOK = "AI_HOMEWORK_SESSION_OK"
    case roleVisibilityApplied = "ROLE_VISIBILITY_APPLIED"
    case awaitingChildInput = "AWAITING_CHILD_INPUT"
    case directAnswerRedirected = "DIRECT_ANSWER_REDIRECTED"
    case repeatedlyStuck = "REPEATEDLY_STUCK"
    case offTopicRedirected = "OFF_TOPIC_REDIRECTED"
    case needsHumanReview = "NEEDS_HUMAN_REVIEW"
    case unsafeInputBlocked = "UNSAFE_INPUT_BLOCKED"
    case publicSummaryLeak = "PUBLIC_SUMMARY_LEAK"
}

struct AIHomeworkSessionFinding: Identifiable, Equatable {
    var code: AIHomeworkSessionFindingCode
    var severity: AIHomeworkSeverity
    var message: String
    var publicRef: String

    var id: String { "\(code.rawValue):\(publicRef)" }
}

struct AIHomeworkSessionVisibility: Equatable {
    var viewerRole: AIHomeworkSessionViewerRole
    var canSeeSteps: Bool
    var canSeeFollowUps: Bool
    var canSeeChecklist: Bool
    var canSeeCareSummary: Bool
    var canSeeRiskLabels: Bool
    var canSeeNeedsHuman: Bool
}

/// 家长/老师脱敏摘要：只给意图标签、风险标签与是否需要介入，
/// 不含答案、原始 transcript、内部风险评分数值、模型/供应商细节或孩子原话。
struct AIHomeworkSessionCareSummary: Equatable {
    var subjectLabel: String
    var topicLabel: String
    var messageCount: Int
    var intentLabels: [String]
    var riskLabels: [AIHomeworkRiskLabel]
    var needsHumanIntervention: Bool
    var recommendedAction: String
    var lastActivityLabel: String

    let exposesChildAnswer = false
    let exposesRawTranscript = false
    let exposesInternalRiskScore = false
    let exposesModelOrProvider = false
}

struct AIHomeworkSessionHeader: Equatable {
    var viewerRole: AIHomeworkSessionViewerRole
    var status: AIHomeworkSessionStatus
    var generatedAt: String
    var privacyScope: String
}

struct AIHomeworkSessionPublicSummary: Equatable {
    var generatedAt: String
    var viewerRole: AIHomeworkSessionViewerRole
    var status: AIHomeworkSessionStatus
    var subjectLabel: String
    var stepCount: Int
    var followUpCount: Int
    var checklistCount: Int
    var messageCount: Int
    var riskLabelCount: Int
    var needsHumanIntervention: Bool
    var findingCodes: [AIHomeworkSessionFindingCode]

    let givesAnswer = false
    let writesEssay = false
    let gradesWork = false
    let callsAiProvider = false
    let callsNetwork = false
    let callsSchoolSystem = false
    let callsLms = false
    let sendsNotification = false
    let writesLedger = false
    let unlocksDevice = false
    let retainsRawTranscript = false
    let revealsModelOrProvider = false
    let suggestsCreditAmount = false
}

struct AIHomeworkGuidanceSessionSnapshot: Equatable {
    var generatedAt: String
    var header: AIHomeworkSessionHeader
    var visibility: AIHomeworkSessionVisibility
    var subjectLabel: String
    var topicLabel: String
    /// 当前孩子提问的脱敏意图标签（中性，不含原话）。
    var currentIntentLabel: String?
    var steps: [AIHomeworkSocraticStep]
    var followUps: [String]
    var checklist: [String]
    var nextStep: String
    var assurance: String
    var careSummary: AIHomeworkSessionCareSummary?
    var findings: [AIHomeworkSessionFinding]
    var publicSummary: AIHomeworkSessionPublicSummary
}

struct AIHomeworkGuidanceSessionBuilder {
    private let generatedAt: String
    private let redactionSalt: String

    init(
        generatedAt: String = "2026-06-24T10:00:00Z",
        redactionSalt: String = "ai-homework-guidance-session-ios-v1"
    ) {
        self.generatedAt = generatedAt
        self.redactionSalt = redactionSalt
    }

    func build(
        viewerRole: AIHomeworkSessionViewerRole,
        homework: SchoolHomework?,
        messages: [AIHomeworkSessionMessage] = []
    ) -> AIHomeworkGuidanceSessionSnapshot {
        let visibility = visibility(for: viewerRole)
        if hasUnsafeInput(homework: homework, messages: messages) {
            return safeFallback(viewerRole: viewerRole, visibility: visibility)
        }

        guard let homework else {
            return emptySnapshot(viewerRole: viewerRole, visibility: visibility)
        }

        let intents = messages.map(classify)
        let latest = intents.last
        let risk = riskLabels(for: intents)
        let needsHuman = needsHumanIntervention(risk)
        let status = status(
            viewerRole: viewerRole,
            messages: messages,
            latest: latest,
            needsHuman: needsHuman
        )

        let steps = visibility.canSeeSteps
            ? socraticSteps(intent: latest, guidance: homework.guidance)
            : []
        let followUps = visibility.canSeeFollowUps ? followUps(for: latest ?? .whereToStart) : []
        let checklist = visibility.canSeeChecklist ? homework.guidance.checklist : []
        let nextStep = visibility.canSeeChecklist ? homework.guidance.nextStep : ""

        let careSummary = visibility.canSeeCareSummary
            ? careSummary(
                viewerRole: viewerRole,
                homework: homework,
                intents: intents,
                risk: risk,
                needsHuman: needsHuman
            )
            : nil

        let findings = findings(
            viewerRole: viewerRole,
            visibility: visibility,
            status: status,
            messages: messages,
            risk: risk,
            needsHuman: needsHuman
        )

        let body = AIHomeworkGuidanceSessionSnapshot(
            generatedAt: generatedAt,
            header: AIHomeworkSessionHeader(
                viewerRole: viewerRole,
                status: status,
                generatedAt: generatedAt,
                privacyScope: privacyScope(for: viewerRole)
            ),
            visibility: visibility,
            subjectLabel: homework.subject.label,
            topicLabel: homework.title,
            currentIntentLabel: visibility.canSeeSteps ? latest?.label : nil,
            steps: steps,
            followUps: followUps,
            checklist: checklist,
            nextStep: nextStep,
            assurance: assuranceCopy,
            careSummary: careSummary,
            findings: findings,
            publicSummary: publicSummary(
                viewerRole: viewerRole,
                status: status,
                subjectLabel: homework.subject.label,
                steps: steps,
                followUps: followUps,
                checklist: checklist,
                messages: messages,
                risk: risk,
                needsHuman: needsHuman,
                findings: findings
            )
        )
        return redacts(body) ? body : safeFallback(viewerRole: viewerRole, visibility: visibility)
    }

    func redacts(_ snapshot: AIHomeworkGuidanceSessionSnapshot) -> Bool {
        !hasUnsafeDisplayValues(displayValues(snapshot))
    }

    // MARK: - Visibility

    private func visibility(for role: AIHomeworkSessionViewerRole) -> AIHomeworkSessionVisibility {
        switch role {
        case .child:
            return AIHomeworkSessionVisibility(
                viewerRole: role,
                canSeeSteps: true,
                canSeeFollowUps: true,
                canSeeChecklist: true,
                canSeeCareSummary: false,
                canSeeRiskLabels: false,
                canSeeNeedsHuman: false
            )
        case .guardian, .teacher:
            return AIHomeworkSessionVisibility(
                viewerRole: role,
                canSeeSteps: false,
                canSeeFollowUps: false,
                canSeeChecklist: false,
                canSeeCareSummary: true,
                canSeeRiskLabels: true,
                canSeeNeedsHuman: true
            )
        }
    }

    private func privacyScope(for role: AIHomeworkSessionViewerRole) -> String {
        switch role {
        case .child: return "private"
        case .guardian: return "family_care"
        case .teacher: return "school_care"
        }
    }

    // MARK: - Intent classification

    /// 把一条本地输入归类成脱敏意图。绝不保留原始文本，只看关键词命中。
    private func classify(_ message: AIHomeworkSessionMessage) -> AIHomeworkQuestionIntent {
        message.intent
    }

    // MARK: - Risk

    private func riskLabels(for intents: [AIHomeworkQuestionIntent]) -> [AIHomeworkRiskLabel] {
        var labels: [AIHomeworkRiskLabel] = []
        let directCount = intents.filter { $0 == .wantsDirectAnswer }.count
        let stuckCount = intents.filter { $0 == .stuckOnStep }.count
        if directCount >= 1 { labels.append(.wantsDirectAnswer) }
        if stuckCount >= 2 { labels.append(.repeatedlyStuck) }
        if intents.contains(.offTopic) { labels.append(.offTopic) }
        if directCount >= 2 || stuckCount >= 2 { labels.append(.possibleFrustration) }
        return labels
    }

    private func needsHumanIntervention(_ risk: [AIHomeworkRiskLabel]) -> Bool {
        risk.contains(.repeatedlyStuck)
            || risk.contains(.possibleFrustration)
            || risk.contains(.unsafeContent)
    }

    // MARK: - Status

    private func status(
        viewerRole: AIHomeworkSessionViewerRole,
        messages: [AIHomeworkSessionMessage],
        latest: AIHomeworkQuestionIntent?,
        needsHuman: Bool
    ) -> AIHomeworkSessionStatus {
        if messages.isEmpty { return .awaitingChildInput }
        // 孩子端永远不展示「需要人工跟进」这种内部判断，只看到引导态。
        if viewerRole.isCareTeam && needsHuman { return .needsHumanReview }
        if latest == .howToCheck { return .selfCheck }
        return .guiding
    }

    // MARK: - Socratic steps

    private func socraticSteps(
        intent: AIHomeworkQuestionIntent?,
        guidance: AIHomeworkGuidance
    ) -> [AIHomeworkSocraticStep] {
        // 没有提问时（nil）按「从哪里开始」给开场引导。
        let resolved = intent ?? .whereToStart
        var prompts = leadProbes(for: resolved)
        prompts.append(contentsOf: hintPrompts(for: resolved, guidance: guidance))
        prompts.append(contentsOf: checkPrompt(for: resolved, guidance: guidance))
        return prompts.enumerated().map { index, pair in
            AIHomeworkSocraticStep(order: index + 1, kind: pair.0, prompt: pair.1)
        }
    }

    /// 每种意图的开场引导提问。`wantsDirectAnswer` 用坚定但友好的回正轨，绝不给答案。
    private func leadProbes(for intent: AIHomeworkQuestionIntent) -> [(AIHomeworkStepKind, String)] {
        switch intent {
        case .whereToStart:
            return [(.probe, "先别急着算，你能用自己的话说说这道题在问什么吗？")]
        case .stuckOnStep:
            return [(.probe, "你已经做到哪一步了？把你卡住的那一步指出来，我们只往前走一小步。")]
        case .howToCheck:
            return [(.check, "做完了真棒！我们一项一项对一遍，看看有没有漏掉的。")]
        case .wantUnderstanding:
            return [(.probe, "好问题！你觉得这一步是在帮我们解决什么呢？")]
        case .wantsDirectAnswer:
            return [
                (.probe, "我不能直接告诉你答案，因为自己想出来你才真的学会了。我们一起把它拆开，好吗？"),
                (.probe, "先看一眼题目，你觉得它最先要我们求什么？")
            ]
        case .offTopic:
            return [(.probe, "这个问题和作业不太相关，我们先把作业完成，再去做喜欢的事，好不好？")]
        case .unclear:
            return [(.probe, "可以再说具体一点吗？你是不知道从哪里开始，还是卡在某一步了？")]
        }
    }

    private func hintPrompts(
        for intent: AIHomeworkQuestionIntent,
        guidance: AIHomeworkGuidance
    ) -> [(AIHomeworkStepKind, String)] {
        // 自检意图不追加思路提示，避免冲淡「自己检查」的重点。
        if intent == .howToCheck { return [] }
        let take = intent == .unclear ? 1 : 2
        return guidance.hints.prefix(take).map { (.hint, $0) }
    }

    private func checkPrompt(
        for intent: AIHomeworkQuestionIntent,
        guidance: AIHomeworkGuidance
    ) -> [(AIHomeworkStepKind, String)] {
        if intent == .howToCheck {
            return guidance.checklist.map { (.check, "确认一下：\($0)") }
        }
        guard let first = guidance.checklist.first else { return [] }
        return [(.check, "做的时候记得留意：\(first)")]
    }

    private func followUps(for intent: AIHomeworkQuestionIntent) -> [String] {
        switch intent {
        case .howToCheck:
            return ["有一项我还不太确定", "我想再确认一次思路对不对"]
        case .wantsDirectAnswer, .offTopic:
            return ["好，那我们从第一步开始", "再给我一个小提示"]
        default:
            return ["再给我一个小提示", "我想确认我的思路对不对", "我做完了，帮我看看要检查什么"]
        }
    }

    private let assuranceCopy = "我只会陪你一步步想，给你提示和检查清单，不会直接告诉你答案。需要时也可以找老师或家长帮忙。"

    // MARK: - Care summary

    private func careSummary(
        viewerRole: AIHomeworkSessionViewerRole,
        homework: SchoolHomework,
        intents: [AIHomeworkQuestionIntent],
        risk: [AIHomeworkRiskLabel],
        needsHuman: Bool
    ) -> AIHomeworkSessionCareSummary {
        AIHomeworkSessionCareSummary(
            subjectLabel: homework.subject.label,
            topicLabel: homework.title,
            messageCount: intents.count,
            intentLabels: intents.map(\.label),
            riskLabels: risk,
            needsHumanIntervention: needsHuman,
            recommendedAction: recommendedAction(
                viewerRole: viewerRole,
                intents: intents,
                risk: risk,
                needsHuman: needsHuman
            ),
            lastActivityLabel: intents.isEmpty ? "孩子还没开始提问" : "刚刚（本地会话）"
        )
    }

    private func recommendedAction(
        viewerRole: AIHomeworkSessionViewerRole,
        intents: [AIHomeworkQuestionIntent],
        risk: [AIHomeworkRiskLabel],
        needsHuman: Bool
    ) -> String {
        if intents.isEmpty {
            return "孩子还没开始这道题的引导会话，暂不需要介入。"
        }
        if needsHuman {
            return viewerRole == .teacher
                ? "建议老师在课堂或辅导时跟进这名同学的这道题。"
                : "建议家长坐下来和孩子一起看看这道题。"
        }
        if risk.contains(.wantsDirectAnswer) {
            return "孩子几次想直接要答案，AI 已引导其自己思考，可留意学习方法。"
        }
        if risk.contains(.offTopic) {
            return "孩子有些走神，AI 已把话题引回作业，暂不需要介入。"
        }
        return "孩子正在按引导一步步完成，暂不需要介入。"
    }

    // MARK: - Findings

    private func findings(
        viewerRole: AIHomeworkSessionViewerRole,
        visibility: AIHomeworkSessionVisibility,
        status: AIHomeworkSessionStatus,
        messages: [AIHomeworkSessionMessage],
        risk: [AIHomeworkRiskLabel],
        needsHuman: Bool
    ) -> [AIHomeworkSessionFinding] {
        var result: [AIHomeworkSessionFinding] = []
        func push(_ code: AIHomeworkSessionFindingCode, _ severity: AIHomeworkSeverity, _ message: String) {
            result.append(AIHomeworkSessionFinding(
                code: code,
                severity: severity,
                message: message,
                publicRef: publicRef("ai-hw-find", "\(viewerRole.rawValue):\(code.rawValue):\(result.count)")
            ))
        }

        if messages.isEmpty {
            push(.awaitingChildInput, .info, "孩子还没开始提问，会话等待孩子选择或输入问题。")
        }
        if visibility.canSeeRiskLabels {
            if risk.contains(.wantsDirectAnswer) {
                push(.directAnswerRedirected, .info, "孩子想要直接答案，AI 已引导其自己思考，未给答案。")
            }
            if risk.contains(.offTopic) {
                push(.offTopicRedirected, .info, "孩子偏离作业主题，AI 已把话题引回作业。")
            }
            if risk.contains(.repeatedlyStuck) {
                push(.repeatedlyStuck, .warning, "孩子在同一处反复卡住，建议人工跟进。")
            }
            if needsHuman {
                push(.needsHumanReview, .warning, "本次会话建议家长或老师人工跟进。")
            }
        }
        push(.roleVisibilityApplied, .info, "已按 \(viewerRole.label) 视角裁剪 AI 作业引导会话。")
        if !result.contains(where: { $0.severity == .warning || $0.severity == .blocker }) {
            push(.sessionOK, .ok, "AI 作业引导会话只读、脱敏、不给答案且无副作用。")
        }
        return result
    }

    // MARK: - Public summary

    private func publicSummary(
        viewerRole: AIHomeworkSessionViewerRole,
        status: AIHomeworkSessionStatus,
        subjectLabel: String,
        steps: [AIHomeworkSocraticStep],
        followUps: [String],
        checklist: [String],
        messages: [AIHomeworkSessionMessage],
        risk: [AIHomeworkRiskLabel],
        needsHuman: Bool,
        findings: [AIHomeworkSessionFinding]
    ) -> AIHomeworkSessionPublicSummary {
        AIHomeworkSessionPublicSummary(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            status: status,
            subjectLabel: subjectLabel,
            stepCount: steps.count,
            followUpCount: followUps.count,
            checklistCount: checklist.count,
            messageCount: messages.count,
            riskLabelCount: viewerRole.isCareTeam ? risk.count : 0,
            needsHumanIntervention: viewerRole.isCareTeam ? needsHuman : false,
            findingCodes: findings.map(\.code)
        )
    }

    // MARK: - Empty & safe fallback

    private func emptySnapshot(
        viewerRole: AIHomeworkSessionViewerRole,
        visibility: AIHomeworkSessionVisibility
    ) -> AIHomeworkGuidanceSessionSnapshot {
        let finding = AIHomeworkSessionFinding(
            code: .sessionOK,
            severity: .ok,
            message: "当前没有可引导的作业，会话保持只读空态。",
            publicRef: publicRef("ai-hw-find", "\(viewerRole.rawValue):empty")
        )
        return AIHomeworkGuidanceSessionSnapshot(
            generatedAt: generatedAt,
            header: AIHomeworkSessionHeader(
                viewerRole: viewerRole,
                status: .empty,
                generatedAt: generatedAt,
                privacyScope: privacyScope(for: viewerRole)
            ),
            visibility: visibility,
            subjectLabel: "",
            topicLabel: "",
            currentIntentLabel: nil,
            steps: [],
            followUps: [],
            checklist: [],
            nextStep: "",
            assurance: viewerRole == .child ? assuranceCopy : "",
            careSummary: nil,
            findings: [finding],
            publicSummary: AIHomeworkSessionPublicSummary(
                generatedAt: generatedAt,
                viewerRole: viewerRole,
                status: .empty,
                subjectLabel: "",
                stepCount: 0,
                followUpCount: 0,
                checklistCount: 0,
                messageCount: 0,
                riskLabelCount: 0,
                needsHumanIntervention: false,
                findingCodes: [finding.code]
            )
        )
    }

    private func safeFallback(
        viewerRole: AIHomeworkSessionViewerRole,
        visibility: AIHomeworkSessionVisibility
    ) -> AIHomeworkGuidanceSessionSnapshot {
        let finding = AIHomeworkSessionFinding(
            code: viewerRole.isCareTeam ? .unsafeInputBlocked : .publicSummaryLeak,
            severity: .blocker,
            message: "AI 作业引导会话未通过本地脱敏检查，已进入安全降级模式。",
            publicRef: publicRef("ai-hw-find", "\(viewerRole.rawValue):unsafe")
        )
        return AIHomeworkGuidanceSessionSnapshot(
            generatedAt: generatedAt,
            header: AIHomeworkSessionHeader(
                viewerRole: viewerRole,
                status: .blocked,
                generatedAt: generatedAt,
                privacyScope: "private"
            ),
            visibility: visibility,
            subjectLabel: "",
            topicLabel: "",
            currentIntentLabel: nil,
            steps: [],
            followUps: [],
            checklist: [],
            nextStep: "",
            assurance: viewerRole == .child ? "这条问题需要先让大人看看，我们待会儿再继续，好吗？" : "",
            careSummary: nil,
            findings: [finding],
            publicSummary: AIHomeworkSessionPublicSummary(
                generatedAt: generatedAt,
                viewerRole: viewerRole,
                status: .blocked,
                subjectLabel: "",
                stepCount: 0,
                followUpCount: 0,
                checklistCount: 0,
                messageCount: 0,
                riskLabelCount: 0,
                needsHumanIntervention: viewerRole.isCareTeam,
                findingCodes: [finding.code]
            )
        )
    }

    // MARK: - Safety

    private func hasUnsafeInput(
        homework: SchoolHomework?,
        messages: [AIHomeworkSessionMessage]
    ) -> Bool {
        if messages.contains(where: \.containsUnsafeInput) { return true }
        var values: [String] = []
        if let homework {
            values.append(contentsOf: [homework.title, homework.instructions, homework.dueLabel, homework.subject.label])
            values.append(contentsOf: homework.guidance.hints)
            values.append(contentsOf: homework.guidance.checklist)
            values.append(homework.guidance.nextStep)
        }
        return hasUnsafeDisplayValues(values)
    }

    private func hasUnsafeDisplayValues(_ values: [String]) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        let rawPatterns = [
            "(?i)\\b(child|family|school|class|teacher|guardian|homework|submission|proof|ledger|credit|event|session|transcript|provider|model|source|ref):[a-z0-9_-]+",
            "(?i)\\b(taskId|claimId|server-secret|device-token|api[_-]?key)\\b"
        ]
        return values.contains { value in
            rawPatterns.contains { pattern in
                value.range(of: pattern, options: .regularExpression) != nil
            }
        }
    }

    private func displayValues(_ snapshot: AIHomeworkGuidanceSessionSnapshot) -> [String] {
        var values = [
            snapshot.generatedAt,
            snapshot.header.privacyScope,
            snapshot.header.viewerRole.rawValue,
            snapshot.header.status.rawValue,
            snapshot.subjectLabel,
            snapshot.topicLabel,
            snapshot.currentIntentLabel ?? "",
            snapshot.nextStep,
            snapshot.assurance
        ]
        values.append(contentsOf: snapshot.steps.map(\.prompt))
        values.append(contentsOf: snapshot.followUps)
        values.append(contentsOf: snapshot.checklist)
        if let care = snapshot.careSummary {
            values.append(contentsOf: [care.subjectLabel, care.topicLabel, care.recommendedAction, care.lastActivityLabel])
            values.append(contentsOf: care.intentLabels)
        }
        values.append(contentsOf: snapshot.findings.flatMap { [$0.publicRef, $0.message] })
        return values
    }

    private func publicRef(_ prefix: String, _ source: String) -> String {
        var hash = 5381
        for scalar in "\(redactionSalt):\(source)".unicodeScalars {
            hash = ((hash << 5) &+ hash) ^ Int(scalar.value)
        }
        return "\(prefix)-\(String(UInt(bitPattern: hash), radix: 36))"
    }
}
