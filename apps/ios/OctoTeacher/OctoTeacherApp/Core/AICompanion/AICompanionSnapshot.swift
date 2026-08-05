import Foundation

/// 孩子端「AI 小伙伴」的本地安全快照。
///
/// 第一版只做确定性陪伴壳：帮孩子判断现在先做什么、作业卡在哪里、情绪先怎么稳住。
/// 它不接真实 AI、不联网、不保存原始输入、不替孩子给答案；家长只看到脱敏摘要和介入建议。
enum AICompanionViewerRole: String, Codable, Equatable, CaseIterable {
    case child
    case guardian

    var isCareTeam: Bool { self == .guardian }
}

enum AICompanionMode: String, Codable, Equatable, CaseIterable {
    case nextStep = "next_step"
    case homework = "homework"
    case emotion = "emotion"

    var label: String {
        switch self {
        case .nextStep: return "不知道先做什么"
        case .homework: return "作业卡住了"
        case .emotion: return "心情有点难"
        }
    }

    func label(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return label }
        switch self {
        case .nextStep: return "Not sure what to do first"
        case .homework: return "Stuck on homework"
        case .emotion: return "Feeling a bit down"
        }
    }

    var systemImage: String {
        switch self {
        case .nextStep: return "sparkles"
        case .homework: return "pencil.and.outline"
        case .emotion: return "heart.circle"
        }
    }
}

enum AICompanionPresetQuestion: String, Codable, Equatable, CaseIterable {
    case whatNow = "what_now"
    case homeworkStuck = "homework_stuck"
    case feelingBad = "feeling_bad"
    case needAdult = "need_adult"

    var label: String {
        switch self {
        case .whatNow: return "我现在该先做什么？"
        case .homeworkStuck: return "我有一道题不会。"
        case .feelingBad: return "我现在不太开心。"
        case .needAdult: return "我想找大人帮忙。"
        }
    }

    func label(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return label }
        switch self {
        case .whatNow: return "What should I do first?"
        case .homeworkStuck: return "I'm stuck on a problem."
        case .feelingBad: return "I'm not feeling great."
        case .needAdult: return "I want a grown-up's help."
        }
    }

    var intent: AICompanionIntent {
        switch self {
        case .whatNow: return .findNextStep
        case .homeworkStuck: return .homeworkStuck
        case .feelingBad: return .emotionalSupport
        case .needAdult: return .askTrustedAdult
        }
    }
}

enum AICompanionIntent: String, Codable, Equatable, CaseIterable {
    case findNextStep = "find_next_step"
    case homeworkStuck = "homework_stuck"
    case emotionalSupport = "emotional_support"
    case askTrustedAdult = "ask_trusted_adult"
    case wantsDirectAnswer = "wants_direct_answer"
    case highRisk = "high_risk"
    case offTopic = "off_topic"
    case unclear

    var label: String {
        switch self {
        case .findNextStep: return "需要下一步"
        case .homeworkStuck: return "作业卡住"
        case .emotionalSupport: return "需要情绪陪伴"
        case .askTrustedAdult: return "想找可信大人"
        case .wantsDirectAnswer: return "想要直接答案"
        case .highRisk: return "需要立即保护"
        case .offTopic: return "暂时偏离任务"
        case .unclear: return "还没说清楚"
        }
    }

    /// 孩子可见的意图标签双语版本；家长端摘要继续用中文 `label`。
    func label(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return label }
        switch self {
        case .findNextStep: return "Needs a next step"
        case .homeworkStuck: return "Stuck on homework"
        case .emotionalSupport: return "Needs comfort"
        case .askTrustedAdult: return "Wants a trusted grown-up"
        case .wantsDirectAnswer: return "Wants the answer directly"
        case .highRisk: return "Needs protection right now"
        case .offTopic: return "Off the task for now"
        case .unclear: return "Not clear yet"
        }
    }
}

enum AICompanionRiskLabel: String, Codable, Equatable, CaseIterable {
    case directAnswer = "direct_answer"
    case repeatedStuck = "repeated_stuck"
    case emotionalDistress = "emotional_distress"
    case highRisk = "high_risk"
    case unsafeInput = "unsafe_input"

    var label: String {
        switch self {
        case .directAnswer: return "想要直接答案"
        case .repeatedStuck: return "反复卡住"
        case .emotionalDistress: return "情绪低落"
        case .highRisk: return "需要立即保护"
        case .unsafeInput: return "输入含不安全内容"
        }
    }
}

enum AICompanionStatus: String, Codable, Equatable {
    case awaitingChildInput = "awaiting_child_input"
    case guiding
    case emotionalSupport = "emotional_support"
    case needsTrustedAdult = "needs_trusted_adult"
    case blocked

    var label: String {
        switch self {
        case .awaitingChildInput: return "等待孩子说一句"
        case .guiding: return "陪伴进行中"
        case .emotionalSupport: return "先接住情绪"
        case .needsTrustedAdult: return "建议可信大人介入"
        case .blocked: return "已安全阻断"
        }
    }
}

enum AICompanionFindingCode: String, Codable, Equatable {
    case ready = "AI_COMPANION_READY"
    case roleVisibilityApplied = "ROLE_VISIBILITY_APPLIED"
    case nextStepSuggested = "NEXT_STEP_SUGGESTED"
    case directAnswerRedirected = "DIRECT_ANSWER_REDIRECTED"
    case emotionalSupportSuggested = "EMOTIONAL_SUPPORT_SUGGESTED"
    case trustedAdultNeeded = "TRUSTED_ADULT_NEEDED"
    case unsafeInputBlocked = "UNSAFE_INPUT_BLOCKED"
    case redactionFallback = "REDACTION_FALLBACK"
}

struct AICompanionMessage: Codable, Equatable {
    var intent: AICompanionIntent
    var containsUnsafeInput: Bool

    init(preset: AICompanionPresetQuestion) {
        intent = preset.intent
        containsUnsafeInput = false
    }

    init(freeText: String) {
        intent = Self.classify(freeText)
        containsUnsafeInput = Self.hasUnsafeInput(freeText)
    }

    private static func classify(_ text: String) -> AICompanionIntent {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 2 { return .unclear }
        if contains(trimmed, highRiskKeywords) { return .highRisk }
        if contains(trimmed, constructiveHintKeywords) { return .homeworkStuck }
        if contains(trimmed, directAnswerKeywords) { return .wantsDirectAnswer }
        if contains(trimmed, adultKeywords) { return .askTrustedAdult }
        if contains(trimmed, emotionKeywords) { return .emotionalSupport }
        if contains(trimmed, homeworkKeywords) { return .homeworkStuck }
        if contains(trimmed, nextStepKeywords) { return .findNextStep }
        if contains(trimmed, offTopicKeywords) { return .offTopic }
        return .unclear
    }

    private static func hasUnsafeInput(_ text: String) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe([text]) { return true }
        let patterns = [
            "(?i)\\b(child|family|school|guardian|homework|session|transcript|provider|model|source|ref):[a-z0-9_-]+",
            "(?i)\\b(api[_-]?key|device-token|server-secret|private-key|file://)\\b"
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private static func contains(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private static let highRiskKeywords = [
        "不想活", "自杀", "伤害自己", "割腕", "被打", "打我", "欺负我", "霸凌",
        "猥亵", "侵犯", "性侵", "离家出走", "死了算了", "kill myself", "suicide", "abuse"
    ]
    private static let directAnswerKeywords = [
        "答案", "正确答案", "标准答案", "直接告诉我", "帮我写", "替我做", "替我写",
        "抄", "solve it for me", "give me the answer"
    ]
    private static let constructiveHintKeywords = [
        "一个提示", "只给我提示", "只给我一个提示", "不要给答案", "不要直接给答案",
        "检查清单", "我先说", "我的想法"
    ]
    private static let adultKeywords = ["找爸爸", "找妈妈", "找老师", "找大人", "告诉家长", "需要大人"]
    private static let emotionKeywords = ["难过", "害怕", "生气", "焦虑", "紧张", "委屈", "哭", "孤单", "烦", "走丢", "丢了", "不见了", "找不到"]
    private static let homeworkKeywords = ["作业", "题", "不会", "卡住", "算不出", "写不出来", "读不懂"]
    private static let nextStepKeywords = ["先做什么", "现在做什么", "不知道干嘛", "下一步", "开始"]
    private static let offTopicKeywords = ["游戏", "视频", "动画片", "刷手机", "聊天"]
}

struct AICompanionInput: Equatable {
    var childName: String
    var mode: AICompanionMode
    var nextTaskTitle: String?
    var messages: [AICompanionMessage]

    init(
        childName: String,
        mode: AICompanionMode,
        nextTaskTitle: String? = nil,
        messages: [AICompanionMessage] = []
    ) {
        self.childName = childName
        self.mode = mode
        self.nextTaskTitle = nextTaskTitle
        self.messages = messages
    }
}

struct AICompanionGuideStep: Identifiable, Equatable {
    var order: Int
    var title: String
    var detail: String
    var systemImage: String

    let givesFinalAnswer = false
    var id: Int { order }
}

struct AICompanionCareSummary: Equatable {
    var childLabel: String
    var status: AICompanionStatus
    var intentLabels: [String]
    var riskLabels: [AICompanionRiskLabel]
    var needsGuardianAction: Bool
    var suggestedGuardianAction: String

    let exposesRawTranscript = false
    let exposesChildPrivateJournal = false
    let exposesModelOrProvider = false
}

struct AICompanionPublicSummary: Equatable {
    var viewerRole: AICompanionViewerRole
    var status: AICompanionStatus
    var stepCount: Int
    var messageCount: Int
    var riskLabelCount: Int
    var needsGuardianAction: Bool
    var findingCodes: [AICompanionFindingCode]

    let callsAiProvider = false
    let callsNetwork = false
    let storesRawTranscript = false
    let givesFinalAnswer = false
    let sendsNotification = false
    let writesLedger = false
    let unlocksDevice = false
}

struct AICompanionSnapshot: Equatable {
    var generatedAt: String
    var viewerRole: AICompanionViewerRole
    var status: AICompanionStatus
    var headline: String
    var subtitle: String
    var currentIntentLabel: String?
    var childSteps: [AICompanionGuideStep]
    var quickReplies: [String]
    var assurance: String
    var careSummary: AICompanionCareSummary?
    var findings: [AICompanionFindingCode]
    var publicSummary: AICompanionPublicSummary
}

struct AICompanionSnapshotBuilder {
    var generatedAt = "2026-07-05T09:00:00Z"

    /// language 只影响孩子可见文案；家长侧 careSummary 保持中文。不传时保持中文，兼容既有调用与测试。
    func build(
        viewerRole: AICompanionViewerRole,
        input: AICompanionInput,
        language: AppInterfaceLanguage = .chinese
    ) -> AICompanionSnapshot {
        if input.messages.contains(where: \.containsUnsafeInput) {
            return safeFallback(viewerRole: viewerRole, input: input, language: language)
        }

        let intents = input.messages.map(\.intent)
        let latest = intents.last ?? defaultIntent(for: input.mode)
        let risk = riskLabels(for: intents)
        let needsGuardian = needsGuardianAction(latest: latest, risk: risk)
        let status = status(for: viewerRole, latest: latest, messages: input.messages, needsGuardian: needsGuardian)
        let childSteps = viewerRole == .child ? steps(for: latest, input: input, language: language) : []
        let careSummary = viewerRole == .guardian
            ? careSummary(input: input, status: status, intents: intents, risk: risk, needsGuardian: needsGuardian)
            : nil
        let findings = findings(for: viewerRole, latest: latest, status: status, input: input, risk: risk, needsGuardian: needsGuardian)
        let snapshot = AICompanionSnapshot(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            status: status,
            headline: headline(for: latest, input: input, language: language),
            subtitle: subtitle(for: latest, input: input, language: language),
            currentIntentLabel: viewerRole == .child ? latest.label(for: language) : nil,
            childSteps: childSteps,
            quickReplies: viewerRole == .child ? quickReplies(for: latest, language: language) : [],
            assurance: assurance(for: latest, language: language),
            careSummary: careSummary,
            findings: findings,
            publicSummary: AICompanionPublicSummary(
                viewerRole: viewerRole,
                status: status,
                stepCount: childSteps.count,
                messageCount: input.messages.count,
                riskLabelCount: viewerRole.isCareTeam ? risk.count : 0,
                needsGuardianAction: viewerRole.isCareTeam ? needsGuardian : false,
                findingCodes: findings
            )
        )
        return redacts(snapshot) ? snapshot : safeFallback(viewerRole: viewerRole, input: input, language: language)
    }

    func redacts(_ snapshot: AICompanionSnapshot) -> Bool {
        let values = displayValues(snapshot)
        if MobileSyncPayloadGuard.isUnsafe(values) { return false }
        let forbidden = ["child:", "family:", "guardian:", "homework:", "session:", "transcript:", "provider:", "model:", "api_key", "file://"]
        return !values.joined(separator: " ").localizedCaseInsensitiveContainsAny(forbidden)
    }

    private func defaultIntent(for mode: AICompanionMode) -> AICompanionIntent {
        switch mode {
        case .nextStep: return .findNextStep
        case .homework: return .homeworkStuck
        case .emotion: return .emotionalSupport
        }
    }

    private func riskLabels(for intents: [AICompanionIntent]) -> [AICompanionRiskLabel] {
        var labels: [AICompanionRiskLabel] = []
        if intents.contains(.wantsDirectAnswer) { labels.append(.directAnswer) }
        if intents.filter({ $0 == .homeworkStuck }).count >= 2 { labels.append(.repeatedStuck) }
        if intents.contains(.emotionalSupport) { labels.append(.emotionalDistress) }
        if intents.contains(.highRisk) { labels.append(.highRisk) }
        return labels
    }

    private func needsGuardianAction(latest: AICompanionIntent, risk: [AICompanionRiskLabel]) -> Bool {
        latest == .askTrustedAdult
            || risk.contains(.highRisk)
            || risk.contains(.repeatedStuck)
    }

    private func status(
        for role: AICompanionViewerRole,
        latest: AICompanionIntent,
        messages: [AICompanionMessage],
        needsGuardian: Bool
    ) -> AICompanionStatus {
        if messages.isEmpty && latest == .findNextStep { return .awaitingChildInput }
        if latest == .highRisk || latest == .askTrustedAdult { return .needsTrustedAdult }
        if latest == .emotionalSupport { return .emotionalSupport }
        if role.isCareTeam && needsGuardian { return .needsTrustedAdult }
        return .guiding
    }

    private func headline(
        for intent: AICompanionIntent,
        input: AICompanionInput,
        language: AppInterfaceLanguage = .chinese
    ) -> String {
        switch intent {
        case .findNextStep:
            return input.nextTaskTitle.map { language.pick("先做：\($0)", "Start with: \($0)") }
                ?? language.pick("先选一个小任务开始", "Pick one small task to start")
        case .homeworkStuck:
            return language.pick("我们只拆下一小步", "Let's break off just the next small step")
        case .emotionalSupport:
            return language.pick("先把心情放稳一点", "Let's settle your feelings first")
        case .askTrustedAdult, .highRisk:
            return language.pick("现在先找一个可信的大人", "Find a trusted grown-up right now")
        case .wantsDirectAnswer:
            return language.pick("我不替你写答案，但会陪你想", "I won't write the answer, but I'll think with you")
        case .offTopic:
            return language.pick("先回到今天的小目标", "Back to today's small goal first")
        case .unclear:
            return language.pick("你可以再说具体一点", "Can you say a bit more?")
        }
    }

    private func subtitle(
        for intent: AICompanionIntent,
        input: AICompanionInput,
        language: AppInterfaceLanguage = .chinese
    ) -> String {
        switch intent {
        case .findNextStep:
            return language.pick(
                "只需要开始第一步，不用一下子完成全部。",
                "You only need to start the first step — not finish everything at once."
            )
        case .homeworkStuck:
            return language.pick(
                "说出你已经知道什么，比直接要答案更有用。",
                "Saying what you already know helps more than asking for the answer."
            )
        case .emotionalSupport:
            return language.pick(
                "我会先陪你整理发生了什么，再决定下一步。",
                "I'll help you sort out what happened first, then we'll decide the next step."
            )
        case .askTrustedAdult, .highRisk:
            return language.pick(
                "有些事情不该一个人扛，马上让身边的大人知道。",
                "Some things shouldn't be carried alone — let a grown-up nearby know right away."
            )
        case .wantsDirectAnswer:
            return language.pick(
                "我会给提示、问题和检查清单，不会给最终答案。",
                "I'll give hints, questions, and a checklist — never the final answer."
            )
        case .offTopic:
            return language.pick(
                "喜欢的事情可以留到完成任务后，现在先把小目标收尾。",
                "Fun things can wait until the task is done; let's wrap up the small goal first."
            )
        case .unclear:
            return language.pick(
                "你可以先点一句开始，也可以打一句自己的话。",
                "You can tap a line to start, or type something of your own."
            )
        }
    }

    private func steps(
        for intent: AICompanionIntent,
        input: AICompanionInput,
        language: AppInterfaceLanguage = .chinese
    ) -> [AICompanionGuideStep] {
        let taskTitle = input.nextTaskTitle ?? language.pick("今天最小的一件事", "today's smallest little thing")
        let rows: [(String, String, String)]
        switch intent {
        case .findNextStep:
            rows = [
                (language.pick("先看一眼", "Take a peek"),
                 language.pick("找到「\(taskTitle)」，只读标题和要求。", "Find \"\(taskTitle)\" and read just the title and what it asks."),
                 "eye"),
                (language.pick("准备材料", "Get things ready"),
                 language.pick("把要用的书、本子或工具放到桌上。", "Put the books, notebook, or tools you need on the desk."),
                 "square.and.pencil"),
                (language.pick("开始两分钟", "Start for two minutes"),
                 language.pick("先做两分钟，做完再决定要不要继续。", "Do just two minutes first, then decide whether to keep going."),
                 "timer")
            ]
        case .homeworkStuck:
            rows = [
                (language.pick("圈出问题", "Circle the question"),
                 language.pick("先圈出题目到底问什么，不急着算。", "Circle what the problem is really asking — no rushing to solve it."),
                 "questionmark.circle"),
                (language.pick("说出已知", "Say what you know"),
                 language.pick("用自己的话说出已经知道的条件。", "Say the clues you already know in your own words."),
                 "text.bubble"),
                (language.pick("只试一步", "Try one step"),
                 language.pick("只尝试下一小步，做不出来就换一种提示。", "Try just the next small step; if it doesn't work, switch to another hint."),
                 "arrow.forward.circle")
            ]
        case .emotionalSupport:
            rows = [
                (language.pick("先停一下", "Pause first"),
                 language.pick("慢慢吸气，再慢慢呼气，做三次。", "Breathe in slowly, breathe out slowly — three times."),
                 "wind"),
                (language.pick("说出发生了什么", "Say what happened"),
                 language.pick("只说事实：刚才发生了什么，我现在是什么感受。", "Just the facts: what happened, and how I feel right now."),
                 "heart.text.square"),
                (language.pick("选一个动作", "Pick one action"),
                 language.pick("可以喝水、离开一下、写一句想说的话，或找大人。", "Drink some water, step away for a bit, write one sentence, or find a grown-up."),
                 "figure.walk")
            ]
        case .askTrustedAdult, .highRisk:
            rows = [
                (language.pick("立刻告诉大人", "Tell a grown-up now"),
                 language.pick("请现在去找爸爸妈妈、老师或身边可信的大人。", "Please go find Mom, Dad, a teacher, or another trusted grown-up right now."),
                 "person.crop.circle.badge.exclamationmark"),
                (language.pick("别一个人处理", "Don't handle it alone"),
                 language.pick("如果身边没人，先到安全、有人看见的地方。", "If no one is nearby, go to a safe place where people can see you."),
                 "shield.lefthalf.filled"),
                (language.pick("只说一句也可以", "One sentence is enough"),
                 language.pick("可以直接说：我现在需要你陪我一下。", "You can just say: I need you to stay with me for a bit."),
                 "bubble.left.and.exclamationmark.bubble.right")
            ]
        case .wantsDirectAnswer:
            rows = [
                (language.pick("不直接给答案", "No direct answers"),
                 language.pick("答案我不能替你写，但我能陪你拆题。", "I can't write the answer for you, but I can break the problem apart with you."),
                 "hand.raised"),
                (language.pick("改成要提示", "Ask for a hint"),
                 language.pick("可以说：只给我一个提示，不要直接给答案。", "You can say: give me one hint, not the answer."),
                 "lightbulb"),
                (language.pick("先说你的想法", "Say your idea first"),
                 language.pick("你先说自己猜的第一步，我只帮你检查方向。", "You guess the first step, and I'll only check the direction."),
                 "text.bubble"),
                (language.pick("再做检查", "Then double-check"),
                 language.pick("我可以帮你列检查点，最后答案由你自己写。", "I can list check points; you'll write the final answer yourself."),
                 "checklist")
            ]
        case .offTopic:
            rows = [
                (language.pick("先收回注意力", "Gather your focus"),
                 language.pick("把想玩的事情写到稍后清单里。", "Write the fun thing on your later list."),
                 "list.bullet.clipboard"),
                (language.pick("回到小目标", "Back to the small goal"),
                 language.pick("回到「\(taskTitle)」的第一步。", "Go back to the first step of \"\(taskTitle)\"."),
                 "arrow.uturn.left.circle")
            ]
        case .unclear:
            rows = [
                (language.pick("选一句开始聊", "Tap a line to start"),
                 language.pick("先点一句开始，不用一次说完整。", "Tap one line first — you don't have to say it all at once."),
                 "hand.tap"),
                (language.pick("只说一件事", "Say just one thing"),
                 language.pick("比如：我不会第一题，或我现在很烦。", "Like: I can't do question one, or I feel really annoyed."),
                 "text.cursor")
            ]
        }
        return rows.enumerated().map {
            AICompanionGuideStep(order: $0.offset + 1, title: $0.element.0, detail: $0.element.1, systemImage: $0.element.2)
        }
    }

    private func quickReplies(
        for intent: AICompanionIntent,
        language: AppInterfaceLanguage = .chinese
    ) -> [String] {
        switch intent {
        case .emotionalSupport, .highRisk, .askTrustedAdult:
            return language == .english
                ? ["I want a grown-up's help.", "I'm not feeling great.", "I just want some quiet first."]
                : ["我想找大人帮忙。", "我现在不太开心。", "我只想先安静一下。"]
        case .wantsDirectAnswer:
            return language == .english
                ? ["Give me one hint, not the answer.", "Help me make a checklist.", "I'll say my idea first."]
                : ["只给我一个提示，不要给答案。", "帮我列检查清单。", "我先说我的想法。"]
        case .homeworkStuck:
            return language == .english
                ? ["I'm stuck on one step.", "I want to know where to start.", "I'm done and want to check it."]
                : ["我卡在某一步了。", "我想知道从哪里开始。", "我做完了，想检查。"]
        default:
            return AICompanionPresetQuestion.allCases.map { $0.label(for: language) }
        }
    }

    private func assurance(
        for intent: AICompanionIntent,
        language: AppInterfaceLanguage = .chinese
    ) -> String {
        if intent == .highRisk || intent == .askTrustedAdult {
            return language.pick(
                "我会提醒你找可信的大人帮忙；安全比任何任务都重要。",
                "I'll remind you to find a trusted grown-up; staying safe matters more than any task."
            )
        }
        return language.pick(
            "我会陪你拆步骤、整理心情和提醒下一步，不会替你写答案，也不会保存你的原话。",
            "I'll help you break steps apart, sort out feelings, and remember the next step. I won't write answers for you, and I won't keep your exact words."
        )
    }

    private func careSummary(
        input: AICompanionInput,
        status: AICompanionStatus,
        intents: [AICompanionIntent],
        risk: [AICompanionRiskLabel],
        needsGuardian: Bool
    ) -> AICompanionCareSummary {
        AICompanionCareSummary(
            childLabel: input.childName,
            status: status,
            intentLabels: intents.map(\.label),
            riskLabels: risk,
            needsGuardianAction: needsGuardian,
            suggestedGuardianAction: suggestedGuardianAction(intents: intents, risk: risk, needsGuardian: needsGuardian)
        )
    }

    private func suggestedGuardianAction(
        intents: [AICompanionIntent],
        risk: [AICompanionRiskLabel],
        needsGuardian: Bool
    ) -> String {
        if risk.contains(.highRisk) {
            return "请立即线下确认孩子安全，并联系可信成年人或专业支持。"
        }
        if needsGuardian {
            return "建议家长现在陪孩子看一下卡住的任务，先共情再拆步骤。"
        }
        if risk.contains(.directAnswer) {
            return "孩子想直接要答案，小伙伴已回到提示式引导，家长可观察学习方法。"
        }
        if risk.contains(.emotionalDistress) {
            return "孩子可能有情绪波动，建议晚些时候轻声问问今天发生了什么。"
        }
        return "当前无需介入，孩子可以继续按小步骤推进。"
    }

    private func findings(
        for role: AICompanionViewerRole,
        latest: AICompanionIntent,
        status: AICompanionStatus,
        input: AICompanionInput,
        risk: [AICompanionRiskLabel],
        needsGuardian: Bool
    ) -> [AICompanionFindingCode] {
        var result: [AICompanionFindingCode] = [.roleVisibilityApplied]
        if latest == .findNextStep { result.append(.nextStepSuggested) }
        if latest == .wantsDirectAnswer { result.append(.directAnswerRedirected) }
        if latest == .emotionalSupport { result.append(.emotionalSupportSuggested) }
        if needsGuardian || status == .needsTrustedAdult { result.append(.trustedAdultNeeded) }
        if result.count == 1 { result.append(.ready) }
        return result
    }

    private func safeFallback(
        viewerRole: AICompanionViewerRole,
        input: AICompanionInput,
        language: AppInterfaceLanguage = .chinese
    ) -> AICompanionSnapshot {
        let findings: [AICompanionFindingCode] = [.unsafeInputBlocked, .redactionFallback, .roleVisibilityApplied]
        return AICompanionSnapshot(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            status: .blocked,
            headline: language.pick("这句话先不显示", "Let's not show that message"),
            subtitle: language.pick(
                "为了保护你，刚才的内容不会进入会话。可以换一种简单说法，或直接找可信大人。",
                "To protect you, what you just typed won't go into the chat. Try a simpler way to say it, or find a trusted grown-up."
            ),
            currentIntentLabel: viewerRole == .child ? AICompanionIntent.unclear.label(for: language) : nil,
            childSteps: viewerRole == .child ? [
                AICompanionGuideStep(
                    order: 1,
                    title: language.pick("换一句说法", "Say it another way"),
                    detail: language.pick(
                        "只说你现在需要什么帮助，不要写隐私编号或链接。",
                        "Just say what help you need — no private numbers or links."
                    ),
                    systemImage: "text.bubble"
                ),
                AICompanionGuideStep(
                    order: 2,
                    title: language.pick("找大人", "Find a grown-up"),
                    detail: language.pick(
                        "如果这件事让你害怕或不舒服，请马上找可信大人。",
                        "If this scares you or feels wrong, find a trusted grown-up right away."
                    ),
                    systemImage: "person.crop.circle.badge.exclamationmark"
                )
            ] : [],
            quickReplies: viewerRole == .child
                ? (language == .english
                    ? ["I want a grown-up's help.", "I'm not feeling great."]
                    : ["我想找大人帮忙。", "我现在不太开心。"])
                : [],
            assurance: language.pick(
                "为了保护孩子隐私，本地已拦截这次输入。原文不会保存。",
                "To protect your privacy, this device blocked that message. The original words are not saved."
            ),
            careSummary: viewerRole == .guardian ? AICompanionCareSummary(
                childLabel: input.childName,
                status: .blocked,
                intentLabels: [],
                riskLabels: [.unsafeInput],
                needsGuardianAction: true,
                suggestedGuardianAction: "孩子输入命中了隐私/不安全模式，建议家长线下确认。"
            ) : nil,
            findings: findings,
            publicSummary: AICompanionPublicSummary(
                viewerRole: viewerRole,
                status: .blocked,
                stepCount: viewerRole == .child ? 2 : 0,
                messageCount: input.messages.count,
                riskLabelCount: viewerRole.isCareTeam ? 1 : 0,
                needsGuardianAction: viewerRole.isCareTeam,
                findingCodes: findings
            )
        )
    }

    private func displayValues(_ snapshot: AICompanionSnapshot) -> [String] {
        var values = [
            snapshot.generatedAt,
            snapshot.viewerRole.rawValue,
            snapshot.status.rawValue,
            snapshot.headline,
            snapshot.subtitle,
            snapshot.currentIntentLabel ?? "",
            snapshot.assurance
        ]
        values += snapshot.childSteps.flatMap { [$0.title, $0.detail, $0.systemImage] }
        values += snapshot.quickReplies
        values += snapshot.findings.map(\.rawValue)
        if let care = snapshot.careSummary {
            values += [
                care.childLabel,
                care.status.rawValue,
                care.suggestedGuardianAction
            ]
            values += care.intentLabels
            values += care.riskLabels.map(\.rawValue)
            values += care.riskLabels.map(\.label)
        }
        return values
    }
}

private extension String {
    func localizedCaseInsensitiveContainsAny(_ values: [String]) -> Bool {
        values.contains { localizedCaseInsensitiveContains($0) }
    }
}
