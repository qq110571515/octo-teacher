import Foundation

struct AICompanionImageAttachment: Equatable {
    enum Source: String, Equatable {
        case camera
        case photoLibrary = "photo_library"
    }

    var source: Source
    var mimeType: String
    var data: Data
    var localSummary: String

    var byteCount: Int { data.count }
    var base64Data: String { data.base64EncodedString() }
}

/// 孩子端「最近图片上下文」：孩子发过图片后，短期内的追问自动带回这张图。
///
/// 只保存在内存里（不落盘、不进长期记忆），切换孩子或用完跟进轮数即失效；
/// 家长关闭图片上传权限时退化为只携带上一张图的文字摘要。
struct AICompanionRecentImageContext: Equatable {
    static let maxFollowUpTurns = 4
    /// 判定“孩子在追问上一张图片”的引用词；命中任意一个即视为追问。
    static let referenceKeywords = [
        "这个", "那个", "这张", "那张", "这是什么", "是什么",
        "图片", "照片", "图里", "图上", "仔细看", "看清楚", "再看", "看看",
        "上网找", "网上找", "上网查", "网上查", "搜一下", "搜索", "帮我查"
    ]

    var attachments: [AICompanionImageAttachment]
    /// 上一张图的文字摘要：初始为本机来源描述，云端看图成功后更新为回复摘要。
    var visualSummary: String
    var remainingTurns: Int

    init(
        attachments: [AICompanionImageAttachment],
        visualSummary: String,
        remainingTurns: Int = AICompanionRecentImageContext.maxFollowUpTurns
    ) {
        self.attachments = attachments
        self.visualSummary = visualSummary
        self.remainingTurns = remainingTurns
    }

    var isActive: Bool { remainingTurns > 0 && !attachments.isEmpty }

    /// 追问时附带的说明；无论是否重发图片本体都会带上，帮助模型接住上下文。
    var followUpSummary: String {
        let trimmed = visualSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? "（自动补充）孩子在追问上一轮发送的图片，这张图已重新附上。"
            : "（自动补充）孩子在追问上一轮发送的图片。上次看图摘要：\(String(trimmed.prefix(120)))"
    }

    static func referencesRecentImage(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return referenceKeywords.contains { trimmed.localizedCaseInsensitiveContains($0) }
    }

    mutating func consumeTurn() {
        remainingTurns = max(0, remainingTurns - 1)
    }

    /// 图片被重新发给云端后刷新轮数，让连续追问不中断。
    mutating func refresh() {
        remainingTurns = Self.maxFollowUpTurns
    }
}

struct AICompanionChatRequest: Equatable {
    var childAge: Int
    var responseLanguage: AppInterfaceLanguage = .chinese
    var mode: AICompanionMode
    var latestText: String
    var latestIntent: AICompanionIntent
    var companionName: String
    var companionVoice: AICompanionVoiceStyle
    var companionPersonality: AICompanionPersonalityStyle
    var avatarDescription: String
    var memory: AICompanionMemoryDigest
    /// 跨模块成长画像的脱敏摘要（GrowthMemoryDigest.promptSummary），不含原始记录。
    var growthProfileSummary: String = ""
    /// 最近少量聊天上下文（已剪裁、已过滤），不是完整 transcript。
    var recentContextLines: [String] = []
    var nextTaskTitle: String?
    var attachmentSummaries: [String]
    var imageAttachments: [AICompanionImageAttachment] = []

    var isProviderRequestAllowed: Bool {
        let trimmed = latestText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !imageAttachments.isEmpty else { return false }
        if latestIntent == .highRisk || latestIntent == .askTrustedAdult { return false }
        if MobileSyncPayloadGuard.isUnsafe(
            [trimmed, avatarDescription, growthProfileSummary] + attachmentSummaries + recentContextLines
        ) { return false }
        if imageAttachments.contains(where: { $0.data.isEmpty || !$0.mimeType.hasPrefix("image/") }) { return false }
        return true
    }

    var containsImages: Bool { !imageAttachments.isEmpty }
}

struct AICompanionChatTurn: Equatable {
    var reply: String
    var memoryUpdate: AICompanionMemoryUpdate
    var guardianSignal: AICompanionGuardianSignal
    var providerUsed: Bool

    var givesFinalAnswer: Bool { false }
    var storesRawTranscript: Bool { false }
}

enum AICompanionChatServiceError: Error, Equatable {
    case blockedBySafetyGate
    case notConfigured
    case providerUnsupported
    case imageUploadNotAllowed
    case badResponse
    case unsafeResponse
}

protocol AICompanionChatCompleting: Sendable {
    func complete(
        system: String,
        user: String,
        imageAttachments: [AICompanionImageAttachment],
        config: AIProviderConfig,
        apiKey: String
    ) async throws -> String
}

struct OpenAIStyleCompanionChatClient: AICompanionChatCompleting {
    var session: URLSession = .shared

    func complete(
        system: String,
        user: String,
        imageAttachments: [AICompanionImageAttachment],
        config: AIProviderConfig,
        apiKey: String
    ) async throws -> String {
        guard let baseURL = config.resolvedOpenAIStyleBaseURL else {
            throw AIChatError.providerUnsupported
        }

        let model = config.resolvedModelName
        let (data, statusCode) = try await perform(
            baseURL: baseURL,
            apiKey: apiKey,
            body: Self.requestBody(
                model: model,
                system: system,
                user: user,
                imageAttachments: imageAttachments,
                includeJSONResponseFormat: false
            )
        )
        guard (200..<300).contains(statusCode) else {
            throw AIChatError.requestFailed(statusCode: statusCode)
        }

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        guard let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let content = decoded.choices.first?.message.content,
              !content.isEmpty else {
            throw AIChatError.badResponse
        }
        return content
    }

    static func requestBody(
        model: String,
        system: String,
        user: String,
        imageAttachments: [AICompanionImageAttachment],
        includeJSONResponseFormat: Bool = false
    ) -> [String: Any] {
        let userContent: Any
        if imageAttachments.isEmpty {
            userContent = user
        } else {
            var parts: [[String: Any]] = [
                ["type": "text", "text": user]
            ]
            for attachment in imageAttachments {
                parts.append([
                    "type": "image_url",
                    "image_url": [
                        "url": "data:\(attachment.mimeType);base64,\(attachment.base64Data)",
                        // auto 让视觉模型按需要取分辨率；low 曾导致看图质量不足、回答像固定话术。
                        "detail": "auto"
                    ]
                ])
            }
            userContent = parts
        }

        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userContent]
            ],
            "temperature": 0.4
        ]
        if includeJSONResponseFormat {
            body["response_format"] = ["type": "json_object"]
        }
        return body
    }

    private func perform(
        baseURL: URL,
        apiKey: String,
        body: [String: Any]
    ) async throws -> (Data, Int) {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIChatError.requestFailed(statusCode: nil)
        }
        guard let http = response as? HTTPURLResponse else { throw AIChatError.badResponse }
        return (data, http.statusCode)
    }
}

/// 孩子 AI 小伙伴的真实聊天服务。
///
/// 只在家长 BYOK + 显式授权后调用；请求中只放当前一句、人格设置和脱敏记忆摘要。
/// 云端返回后本机仍会做作业答案与敏感内容拦截。
struct AICompanionChatService {
    var chatClient: any AICompanionChatCompleting

    init(chatClient: any AICompanionChatCompleting = OpenAIStyleCompanionChatClient()) {
        self.chatClient = chatClient
    }

    func chat(
        request: AICompanionChatRequest,
        config: AIProviderConfig?,
        apiKey: String?
    ) async throws -> AICompanionChatTurn {
        guard request.isProviderRequestAllowed else {
            throw AICompanionChatServiceError.blockedBySafetyGate
        }
        guard let config else { throw AICompanionChatServiceError.notConfigured }
        guard config.resolvedOpenAIStyleBaseURL != nil else {
            throw AICompanionChatServiceError.providerUnsupported
        }
        let trimmedKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedKey.isEmpty else { throw AICompanionChatServiceError.notConfigured }

        let response = try await chatClient.complete(
            system: systemPrompt(request),
            user: userPrompt(request),
            imageAttachments: request.imageAttachments,
            config: config,
            apiKey: trimmedKey
        )
        return try parseTurn(response, request: request)
    }

    /// 孩子设备不接触家长 API Key，只把同一份经过本机隐私门禁的请求交给家庭云中继。
    /// 中继端会再次追加不可覆盖的作业防代答与儿童安全规则。
    func familyRelayRequest(for request: AICompanionChatRequest) throws -> FamilyAIChatRelayRequest {
        guard request.isProviderRequestAllowed else {
            throw AICompanionChatServiceError.blockedBySafetyGate
        }
        return FamilyAIChatRelayRequest(
            system: systemPrompt(request),
            user: userPrompt(request),
            images: request.imageAttachments.map {
                FamilyAIChatRelayRequest.Image(mimeType: $0.mimeType, base64Data: $0.base64Data)
            },
            homeworkSensitive: isHomeworkSensitive(request)
        )
    }

    func parseFamilyRelayResponse(
        _ response: String,
        request: AICompanionChatRequest
    ) throws -> AICompanionChatTurn {
        try parseTurn(response, request: request)
    }

    private func isHomeworkSensitive(_ request: AICompanionChatRequest) -> Bool {
        request.latestIntent == .wantsDirectAnswer
            || request.latestIntent == .homeworkStuck
            || request.mode == .homework
            || request.latestText.localizedCaseInsensitiveContains("作业")
            || request.latestText.localizedCaseInsensitiveContains("答案")
            || request.latestText.localizedCaseInsensitiveContains("题")
            || request.latestText.localizedCaseInsensitiveContains("homework")
            || request.latestText.localizedCaseInsensitiveContains("answer")
    }

    private func systemPrompt(_ request: AICompanionChatRequest) -> String {
        let languageInstruction = request.responseLanguage == .english
            ? "Reply in natural, warm, age-appropriate English."
            : "Reply in natural, warm, age-appropriate Simplified Chinese."
        return """
        You are Octo Teacher's child AI companion named \(request.companionName). \(languageInstruction) Be specific. Do not output JSON, Markdown tables, or internal fields.
        Persona: \(request.companionPersonality.label). Voice: \(request.companionVoice.label). Avatar: \(request.avatarDescription).
        Act like a warm, real companion for a child, not a fixed script. You may chat about interests, feelings, books, play, plans, and photos.
        Conversation rule: answer the child's actual latest message first, using recent_context only as background. Do not repeat a fixed greeting or a generic "tell me more" sentence unless you truly need clarification.
        Vision rule: if an image is attached, inspect the image directly. Do not say you cannot see it unless no image was attached. Describe only what is helpful for the child's question.
        Image follow-up rule: attachment_context may mark an image as re-attached from a previous turn; treat the child's current question as being about that image, and answer by looking at it again.
        Web rule: you cannot browse the internet, open links, or do real-time web search. If the child asks you to search online, honestly say you cannot go online. Offer instead to reason from the attached photo or the child's description, or suggest asking a parent to search together.
        Homework rule: never give final answers, full solutions, copied essays, direct calculations, multiple-choice letters, or completed writing. Use Socratic guidance: ask what the problem asks, what is known, and the child's first attempt. Give at most one hint at a time, then ask the child to try.
        Homework image rule: if the image appears to contain a school problem, worksheet, quiz, or homework, do not solve it. Ask the child to point to the part they tried, restate the problem in simple words, and give one hint at a time.
        Safety rule: if there is danger, bullying, self-harm, abuse, violence, or a need for an adult, tell the child to find a trusted adult immediately and set guardian_signal to act_now.
        Privacy rule: do not ask for addresses, school names, contact details, secrets, provider details, URLs, files, or API keys.
        Memory rule: do not include memory_updates or hidden notes in the visible reply. OctoTeacher will extract memory locally later.
        """
    }

    private func userPrompt(_ request: AICompanionChatRequest) -> String {
        let task = request.nextTaskTitle == nil ? "none" : "has_active_task"
        let attachments = request.attachmentSummaries.isEmpty ? "none" : request.attachmentSummaries.joined(separator: " | ")
        let imageCount = request.imageAttachments.count
        let recentContext = request.recentContextLines.isEmpty
            ? "none"
            : request.recentContextLines
                .suffix(AICompanionTranscriptStore.maxCloudContextLines)
                .joined(separator: "\n")
        let growthProfile = request.growthProfileSummary.isEmpty ? "none" : request.growthProfileSummary
        return """
        child_age=\(request.childAge)
        response_language=\(request.responseLanguage.rawValue)
        mode=\(request.mode.rawValue)
        latest_intent=\(request.latestIntent.rawValue)
        active_task=\(task)
        attachment_context=\(attachments)
        image_count=\(imageCount)
        local_memory:
        \(request.memory.promptSummary)
        recent_context:
        \(recentContext)
        growth_profile:
        \(growthProfile)

        child_message:
        \(request.latestText)
        """
    }

    private func parseTurn(_ response: String, request: AICompanionChatRequest) throws -> AICompanionChatTurn {
        let normalized = normalizedJSONText(response)
        guard let data = normalized.data(using: .utf8) else {
            throw AICompanionChatServiceError.badResponse
        }
        struct Envelope: Decodable {
            struct MemoryUpdates: Decodable {
                var interests: [String]?
                var preferences: [String]?
                var learningNotes: [String]?
                var emotionalNotes: [String]?
                var homeworkGuidanceNotes: [String]?
                var summary: String?

                enum CodingKeys: String, CodingKey {
                    case interests
                    case preferences
                    case learningNotes = "learning_notes"
                    case emotionalNotes = "emotional_notes"
                    case homeworkGuidanceNotes = "homework_guidance_notes"
                    case summary
                }
            }

            var reply: String
            var guardianSignal: AICompanionGuardianSignal?
            var memoryUpdates: MemoryUpdates?

            enum CodingKeys: String, CodingKey {
                case reply
                case guardianSignal = "guardian_signal"
                case memoryUpdates = "memory_updates"
            }
        }

        let decoded: Envelope
        do {
            decoded = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            return try parsePlainTurn(response, request: request)
        }

        let reply = decoded.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { throw AICompanionChatServiceError.badResponse }
        guard responseIsSafe(reply, request: request) else { throw AICompanionChatServiceError.unsafeResponse }

        let updates = decoded.memoryUpdates
        return AICompanionChatTurn(
            reply: reply,
            memoryUpdate: AICompanionMemoryUpdate(
                interests: capped(updates?.interests),
                preferences: capped(updates?.preferences),
                learningNotes: capped(updates?.learningNotes),
                emotionalNotes: capped(updates?.emotionalNotes),
                homeworkGuidanceNotes: capped(updates?.homeworkGuidanceNotes),
                summary: updates?.summary ?? ""
            ),
            guardianSignal: decoded.guardianSignal ?? .none,
            providerUsed: true
        )
    }

    private func capped(_ values: [String]?) -> [String] {
        Array((values ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(4))
    }

    private func responseIsSafe(_ reply: String, request: AICompanionChatRequest) -> Bool {
        guard !MobileSyncPayloadGuard.isUnsafe([reply]) else { return false }
        guard !looksLikeInternalPromptLeak(reply) else { return false }
        guard !looksLikeFinalHomeworkAnswer(reply, request: request) else { return false }
        return !AICompanionChatReply.containsForbiddenFinalAnswerPhrase(reply)
    }

    private func parsePlainTurn(_ response: String, request: AICompanionChatRequest) throws -> AICompanionChatTurn {
        let reply = normalizedPlainText(response)
        guard !reply.isEmpty else { throw AICompanionChatServiceError.badResponse }
        guard responseIsSafe(reply, request: request) else { throw AICompanionChatServiceError.unsafeResponse }
        return AICompanionChatTurn(
            reply: reply,
            memoryUpdate: AICompanionMemoryUpdate(),
            guardianSignal: .none,
            providerUsed: true
        )
    }

    private func normalizedPlainText(_ response: String) -> String {
        var trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```"), trimmed.hasSuffix("```") {
            var lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if lines.count >= 3 {
                lines.removeFirst()
                lines.removeLast()
                trimmed = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            guard let looseReply = extractLooseReply(from: trimmed) else { return "" }
            trimmed = looseReply
        }
        return String(trimmed.prefix(900))
    }

    private func extractLooseReply(from text: String) -> String? {
        let markers = ["\"reply\"", "reply", "回复", "回答"]
        for marker in markers {
            guard let markerRange = text.range(of: marker, options: [.caseInsensitive]) else { continue }
            let tail = text[markerRange.upperBound...]
            guard let colon = tail.firstIndex(of: ":") else { continue }
            var value = String(tail[tail.index(after: colon)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\"") { value.removeFirst() }
            let stopMarkers = [
                "\",\"guardian_signal", "\", \"guardian_signal",
                "\", guardian_signal", ", guardian_signal",
                "\",\"memory_updates", "\", \"memory_updates",
                "\", memory_updates", ", memory_updates",
                "\n}", "\n]", "}"
            ]
            for stop in stopMarkers {
                if let range = value.range(of: stop) {
                    value = String(value[..<range.lowerBound])
                }
            }
            value = value
                .trimmingCharacters(in: CharacterSet(charactersIn: "\" ,}\n\t"))
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\\"", with: "\"")
            guard !value.isEmpty, !looksLikeInternalPromptLeak(value) else { continue }
            return String(value.prefix(900))
        }
        return nil
    }

    private func looksLikeFinalHomeworkAnswer(_ reply: String, request: AICompanionChatRequest) -> Bool {
        guard request.latestIntent == .wantsDirectAnswer
            || request.latestIntent == .homeworkStuck
            || request.mode == .homework
            || request.latestText.localizedCaseInsensitiveContains("作业")
            || request.latestText.localizedCaseInsensitiveContains("答案")
            || request.latestText.localizedCaseInsensitiveContains("题")
        else { return false }

        let normalized = reply
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = normalized.lowercased()
        if containsAny(lower, ["我不会直接", "不能直接", "不要直接", "不直接给", "不会替你", "不能替你"]) {
            return false
        }
        let riskyPhrases = [
            "答案是", "答案为", "答案就是", "正确答案", "标准答案",
            "最终答案", "最终结果", "结果是", "所以答案", "选 a", "选 b",
            "选 c", "选 d", "选择 a", "选择 b", "选择 c", "选择 d",
            "the answer is", "final answer", "correct answer"
        ]
        if containsAny(lower, riskyPhrases) { return true }
        let compact = lower.replacingOccurrences(of: " ", with: "")
        if compact.contains("x=") || compact.contains("y=") || compact.contains("所以x") || compact.contains("所以y") {
            return true
        }
        return false
    }

    private func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private func looksLikeInternalPromptLeak(_ text: String) -> Bool {
        let markers = [
            "companion_name=", "conversation_count=", "latest_summary=", "growth_event_count=",
            "ai_chat_summary=", "growth_recent:", "child_ai_memory:", "child_growth_profile:",
            "parent_coach_memory:", "parent_memory_updates", "memory_updates", "guardian_signal",
            "active_tasks:", "reward_context:", "local_memory:", "recent_context:"
        ]
        return containsAny(text, markers)
    }

    private func normalizedJSONText(_ response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.firstIndex(of: "{"),
           let last = trimmed.lastIndex(of: "}"),
           first < last {
            return String(trimmed[first...last]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```") else { return trimmed }
        var lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 3 else { return trimmed }
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveContains("json") == true else {
            return trimmed
        }
        lines.removeFirst()
        lines.removeLast()
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AICompanionProfilePatch: Equatable {
    var name: String?
    var voice: AICompanionVoiceStyle?
    var personality: AICompanionPersonalityStyle?
    var avatarDescription: String?

    var hasChanges: Bool {
        name != nil || voice != nil || personality != nil || avatarDescription != nil
    }
}

enum AICompanionProfileCommandParser {
    static func parse(_ text: String) -> AICompanionProfilePatch? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        var patch = AICompanionProfilePatch()
        patch.name = extractName(from: value)
        patch.voice = extractVoice(from: value)
        patch.personality = extractPersonality(from: value)
        patch.avatarDescription = extractAvatar(from: value)
        return patch.hasChanges ? patch : nil
    }

    private static func extractName(from text: String) -> String? {
        let markers = ["你以后叫", "你的名字叫", "你叫", "名字叫", "叫你"]
        for marker in markers {
            guard let range = text.range(of: marker) else { continue }
            let tail = text[range.upperBound...]
            let name = clippedPhrase(String(tail), maxCount: 12)
            if !name.isEmpty { return name }
        }
        return nil
    }

    private static func extractAvatar(from text: String) -> String? {
        let markers = ["你长得像", "你的样子是", "你看起来像", "外貌是", "形象是", "你是一只", "你是一个"]
        for marker in markers {
            guard let range = text.range(of: marker) else { continue }
            let tail = text[range.lowerBound...]
            let avatar = clippedPhrase(String(tail), maxCount: 80)
            if !avatar.isEmpty { return avatar }
        }
        return nil
    }

    private static func extractVoice(from text: String) -> AICompanionVoiceStyle? {
        guard containsAny(text, ["声音", "说话", "语气", "读出来", "朗读", "嗓音", "音色"]) else {
            return nil
        }
        if containsAny(text, ["活泼", "活力", "开心", "鼓励", "精神", "明亮"]) {
            return .bright
        }
        if containsAny(text, ["安静", "冷静", "平静", "慢一点", "低一点", "讲解"]) {
            return .calm
        }
        if containsAny(text, ["温柔", "柔和", "暖", "陪伴", "慢慢"]) {
            return .warm
        }
        return nil
    }

    private static func extractPersonality(from text: String) -> AICompanionPersonalityStyle? {
        guard containsAny(text, ["性格", "人格", "风格", "像", "你要", "你以后", "小伙伴", "陪我", "说话方式"]) else {
            return nil
        }
        if containsAny(text, ["教练", "活泼", "游戏", "挑战", "鼓励", "带我冲"]) {
            return .playfulCoach
        }
        if containsAny(text, ["安静", "朋友", "陪伴", "先听", "少说", "轻轻"]) {
            return .quietBuddy
        }
        if containsAny(text, ["耐心", "引导", "一步一步", "问我", "慢慢"]) {
            return .gentleGuide
        }
        return nil
    }

    private static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private static func clippedPhrase(_ raw: String, maxCount: Int) -> String {
        let separators = CharacterSet(charactersIn: "。！？!?，,\n")
        let first = raw
            .components(separatedBy: separators)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return String(first.prefix(maxCount))
    }
}
