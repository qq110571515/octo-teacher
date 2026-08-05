import Foundation

/// AI 小伙伴孩子端聊天窗口的本机安全回复。
///
/// 这一层只生成当前会话里的展示文案，不保存原始聊天全文；长期记录仍交给
/// `AICompanionSessionStore` 的脱敏 intent 摘要。
/// 所有孩子可见文案支持中英双语：不传 language 时保持中文，兼容既有调用与测试。
struct AICompanionChatReply: Equatable {
    var text: String
    var shouldAskTrustedAdult: Bool

    static func greeting(
        companionName: String,
        mode: AICompanionMode,
        language: AppInterfaceLanguage = .chinese
    ) -> AICompanionChatReply {
        let modeHint: String
        switch mode {
        case .nextStep:
            modeHint = language.pick(
                "你可以告诉我：现在想先做什么，或者什么事情最难开始。",
                "You can tell me what you'd like to do first, or which thing feels hardest to start."
            )
        case .homework:
            modeHint = language.pick(
                "你可以告诉我卡在哪里；我不会直接给答案，但会陪你找第一步。",
                "You can tell me where you're stuck; I won't give you the answer, but I'll help you find the first step."
            )
        case .emotion:
            modeHint = language.pick(
                "你可以告诉我刚才发生了什么，或者现在心里是什么感觉。",
                "You can tell me what just happened, or how you're feeling right now."
            )
        }
        return AICompanionChatReply(
            text: language.pick("你好，我是\(companionName)。\(modeHint)", "Hi, I'm \(companionName). \(modeHint)"),
            shouldAskTrustedAdult: false
        )
    }

    static func make(
        companionName: String,
        snapshot: AICompanionSnapshot,
        latestIntent: AICompanionIntent,
        mode: AICompanionMode,
        latestText: String = "",
        language: AppInterfaceLanguage = .chinese
    ) -> AICompanionChatReply {
        let reply: String
        let shouldAskTrustedAdult: Bool
        let safeTopic = safeConversationTopic(from: latestText)
        if let urgentSupport = urgentSupportReply(
            companionName: companionName,
            latestText: latestText,
            language: language
        ) {
            return urgentSupport
        }

        switch latestIntent {
        case .highRisk, .askTrustedAdult:
            reply = language.pick(
                "\(companionName)会先陪你保护自己：这件事现在要找爸爸妈妈、老师，或身边可信的大人。你可以直接说：我现在需要你陪我一下。",
                "\(companionName) will help you stay safe first: right now, go find Mom, Dad, a teacher, or another trusted grown-up. You can just say: I need you to stay with me for a bit."
            )
            shouldAskTrustedAdult = true
        case .wantsDirectAnswer:
            reply = language.pick(
                "\(companionName)不能直接告诉你作业答案，也不会替你写。我们换成三步：题目问什么？你已经知道哪些条件？你先试第一步，我只帮你检查方向。",
                "\(companionName) can't tell you the homework answer or write it for you. Let's try three steps instead: What is the question asking? What do you already know? You try the first step, and I'll only check your direction."
            )
            shouldAskTrustedAdult = false
        case .homeworkStuck:
            reply = language.pick(
                "\(companionName)可以陪你拆题，但不会替你完成。先告诉我：题目问什么？你已经知道什么？你想先试哪一步？",
                "\(companionName) can break the problem apart with you, but won't do it for you. First tell me: What is the question asking? What do you already know? Which step do you want to try first?"
            )
            shouldAskTrustedAdult = false
        case .emotionalSupport:
            reply = language.pick(
                "\(companionName)先陪你慢一点。我们先做三次呼吸，然后只说事实：刚才发生了什么？你现在最明显的感受是什么？",
                "\(companionName) will slow down with you. Let's take three breaths first, then just say the facts: What happened? What feeling is the strongest right now?"
            )
            shouldAskTrustedAdult = false
        case .offTopic:
            if let safeTopic {
                reply = language.pick(
                    "\(companionName)愿意陪你聊「\(safeTopic)」。先说一个小问题：你最喜欢它哪一点？聊完一分钟，我们再看看今天的小目标。",
                    "\(companionName) would love to chat about \"\(safeTopic)\" with you. One little question first: what do you like most about it? After a minute, let's peek at today's small goal."
                )
            } else {
                reply = language.pick(
                    "\(companionName)可以陪你聊这个。我们也把今天的小目标放在旁边：你想先聊一分钟，还是把它写进完成任务后的愿望清单？",
                    "\(companionName) can chat about that with you. Let's keep today's small goal nearby too: chat for a minute first, or save this fun thing for after the task?"
                )
            }
            shouldAskTrustedAdult = false
        case .findNextStep:
            let firstStep = snapshot.childSteps.first?.detail ?? snapshot.subtitle
            reply = language.pick(
                "\(companionName)建议先做一小步：\(firstStep)",
                "\(companionName) suggests one small step first: \(firstStep)"
            )
            shouldAskTrustedAdult = false
        case .unclear:
            if let safeTopic {
                reply = language.pick(
                    "\(companionName)听到你说「\(safeTopic)」了。你想让我陪你一起想、帮你看图片，还是只是想说给我听？你可以再说一句，也可以发照片或语音。",
                    "\(companionName) heard you say \"\(safeTopic)\". Do you want me to think it through with you, look at a picture, or just listen? You can say one more thing, or send a photo or voice note."
                )
            } else {
                switch mode {
                case .nextStep:
                    reply = language.pick(
                        "\(companionName)在这儿。你可以只说一个词：想玩、想休息、卡住了，还是想让我陪你看今天第一件小事？",
                        "\(companionName) is here. You can say just one word: play, rest, or stuck — or want me to look at today's first little thing with you?"
                    )
                case .homework:
                    reply = language.pick(
                        "\(companionName)会陪你想，但不会抢走你的思考。你可以只发题目里看懂的一句话，或者拍照后指出最卡的地方。",
                        "\(companionName) will think with you, without taking your thinking away. You can send just one line you understood from the problem, or snap a photo and point at the trickiest part."
                    )
                case .emotion:
                    reply = language.pick(
                        "\(companionName)先陪你待一会儿。你不用说完整，先选一个词：委屈、生气、害怕、烦，或者只说“陪我一下”。",
                        "\(companionName) will stay with you for a bit. You don't have to explain everything — pick one word first: sad, angry, scared, annoyed, or just say \"stay with me.\""
                    )
                }
            }
            shouldAskTrustedAdult = false
        }

        let sanitized = sanitizedReply(reply, language: language)
        return AICompanionChatReply(text: sanitized, shouldAskTrustedAdult: shouldAskTrustedAdult)
    }

    static func makeCloudBubble(_ guide: AICompanionCloudGuide, companionName: String) -> AICompanionChatReply? {
        let questions = guide.nextQuestions
            .prefix(2)
            .map { "想一想：\($0)" }
            .joined(separator: "\n")
        let body = questions.isEmpty ? guide.reply : "\(guide.reply)\n\(questions)"
        let text = "\(companionName)补充一个安全小提示：\(body)"
        let sanitized = sanitizedReply(text)
        guard !sanitized.isEmpty else { return nil }
        return AICompanionChatReply(
            text: sanitized,
            shouldAskTrustedAdult: guide.guardianSignal == .actNow
        )
    }

    static func containsForbiddenFinalAnswerPhrase(_ text: String) -> Bool {
        forbiddenFinalAnswerPhrases.contains {
            text.localizedCaseInsensitiveContains($0)
        }
    }

    private static func sanitizedReply(_ text: String, language: AppInterfaceLanguage = .chinese) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if containsForbiddenFinalAnswerPhrase(result) {
            result = language.pick(
                "我不能直接给最终答案。我们先换成提示：题目问什么？你已经知道哪些条件？你先说第一步。",
                "I can't give the final answer. Let's switch to hints: What is the question asking? What do you already know? You say the first step."
            )
        }
        return result
    }

    private static func safeConversationTopic(from text: String) -> String? {
        var result = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.count >= 2, !MobileSyncPayloadGuard.isUnsafe(result) else { return nil }
        for prefix in ["我想聊聊", "我想聊", "聊聊", "想聊", "我想说说", "说说"] {
            if result.hasPrefix(prefix) {
                result.removeFirst(prefix.count)
                result = result.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "。！？!?，, "))
        guard result.count >= 2 else { return nil }
        if result.count > 18 {
            return "\(String(result.prefix(18)))…"
        }
        return result
    }

    private static func urgentSupportReply(
        companionName: String,
        latestText: String,
        language: AppInterfaceLanguage = .chinese
    ) -> AICompanionChatReply? {
        let text = latestText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if containsAny(text, ["笨", "傻", "听不懂", "不懂", "没用", "你错了"]) {
            return AICompanionChatReply(
                text: language.pick(
                    "\(companionName)刚才确实没有理解好，对不起。我们重新来：你说的是一件真的发生的事，还是图片里的东西？如果是着急的事，我会先帮你找最安全的下一步。",
                    "\(companionName) really didn't understand well just now — I'm sorry. Let's start over: is this something that really happened, or something in a picture? If it's urgent, I'll help you find the safest next step first."
                ),
                shouldAskTrustedAdult: false
            )
        }
        if containsAny(text, ["走丢", "丢了", "不见了", "找不到", "失踪"]) {
            return AICompanionChatReply(
                text: language.pick(
                    "\(companionName)听起来这件事让人很着急。先马上告诉爸爸妈妈或身边可信的大人，不要自己跑出去找。我们一起回想三件事：最后一次看到它在哪里、是什么时候、有没有项圈或特别标记？你先告诉我最后看到的地方。",
                    "\(companionName) can hear how worrying this is. Tell Mom, Dad, or a trusted grown-up right away — don't run out to search by yourself. Let's remember three things together: where you last saw it, when that was, and whether it has a collar or a special mark. Start by telling me where you last saw it."
                ),
                shouldAskTrustedAdult: true
            )
        }
        return nil
    }

    private static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private static let forbiddenFinalAnswerPhrases = [
        "答案是",
        "答案就是",
        "正确答案是",
        "标准答案是",
        "直接答案",
        "我替你写",
        "answer:",
        "final answer is",
        "solution is",
        "the solution is",
        "the answer is"
    ]
}

enum AICompanionImageFallbackReason: Equatable {
    case notAuthorized
    case cloudUnavailable
}

enum AICompanionImageFallbackReply {
    static func make(
        companionName: String,
        latestText: String,
        latestIntent: AICompanionIntent,
        reason: AICompanionImageFallbackReason,
        language: AppInterfaceLanguage = .chinese
    ) -> AICompanionChatReply {
        let homeworkHint = latestIntent == .homeworkStuck || latestIntent == .wantsDirectAnswer || looksLikeHomework(latestText)
            ? language.pick(
                "如果这是作业题，我会陪你看题目、找条件、给一个提示，但不会直接给最终答案。",
                "If this is a homework problem, I'll look at the question with you, find the clues, and give one hint — but I won't give the final answer."
            )
            : language.pick(
                "如果你想聊图片里的东西，可以先说：它是什么、你最想问哪一块。",
                "If you want to chat about what's in the picture, start by saying what it is and which part you're most curious about."
            )
        let reasonText: String
        switch reason {
        case .notAuthorized:
            reasonText = language.pick(
                "家长还没有允许我把图片交给真实 AI 看，所以这张图没有上传。",
                "A parent hasn't allowed me to show pictures to the real AI yet, so this picture wasn't uploaded."
            )
        case .cloudUnavailable:
            reasonText = language.pick(
                "刚刚没有拿到视觉 AI 的看图结果，所以我不会假装已经看懂图片。",
                "I didn't get the vision AI's look at the picture just now, so I won't pretend I've seen it."
            )
        }
        return AICompanionChatReply(
            text: language.pick(
                "\(companionName)收到图片了。\(reasonText)\(homeworkHint)",
                "\(companionName) got your picture. \(reasonText) \(homeworkHint)"
            ),
            shouldAskTrustedAdult: false
        )
    }

    private static func looksLikeHomework(_ text: String) -> Bool {
        let keywords = ["作业", "题", "答案", "算", "写", "读不懂", "不会", "worksheet", "homework", "answer"]
        return keywords.contains { text.localizedCaseInsensitiveContains($0) }
    }
}
