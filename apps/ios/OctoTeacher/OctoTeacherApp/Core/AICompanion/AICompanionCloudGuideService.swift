import Foundation

enum AICompanionGuardianSignal: String, Codable, Equatable, CaseIterable {
    case none
    case watch
    case actNow = "act_now"
}

struct AICompanionCloudGuide: Codable, Equatable {
    var reply: String
    var nextQuestions: [String]
    var guardianSignal: AICompanionGuardianSignal

    let givesFinalAnswer = false
    let storesRawTranscript = false
    let writesLedger = false
    let sendsNotification = false

    enum CodingKeys: String, CodingKey {
        case reply
        case nextQuestions
        case guardianSignal
        case givesFinalAnswer
        case storesRawTranscript
        case writesLedger
        case sendsNotification
    }

    init(reply: String, nextQuestions: [String], guardianSignal: AICompanionGuardianSignal) {
        self.reply = reply
        self.nextQuestions = nextQuestions
        self.guardianSignal = guardianSignal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reply = try container.decode(String.self, forKey: .reply)
        nextQuestions = try container.decodeIfPresent([String].self, forKey: .nextQuestions) ?? []
        guardianSignal = (try? container.decodeIfPresent(AICompanionGuardianSignal.self, forKey: .guardianSignal)) ?? .none
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reply, forKey: .reply)
        try container.encode(nextQuestions, forKey: .nextQuestions)
        try container.encode(guardianSignal, forKey: .guardianSignal)
        try container.encode(givesFinalAnswer, forKey: .givesFinalAnswer)
        try container.encode(storesRawTranscript, forKey: .storesRawTranscript)
        try container.encode(writesLedger, forKey: .writesLedger)
        try container.encode(sendsNotification, forKey: .sendsNotification)
    }
}

enum AICompanionCloudGuideError: Error, Equatable {
    case blockedByPrivacyGateway(String)
    case notConfigured
    case providerUnsupported
    case badResponse
    case unsafeResponse
}

/// AI 小伙伴云端回复的安全回收层。
///
/// 这一层只接收 `AICompanionPrivacyGateway` 产出的脱敏草稿；如果草稿未放行，
/// 不会触碰 provider client。云端返回后先解析为受限 JSON，再做本地安全检查。
struct AICompanionCloudGuideService {
    var chatClient: any AIChatCompleting

    init(chatClient: any AIChatCompleting = OpenAIStyleChatClient()) {
        self.chatClient = chatClient
    }

    func guide(
        draft: AICompanionCloudRequestDraft,
        config: AIProviderConfig?,
        apiKey: String?
    ) async throws -> AICompanionCloudGuide {
        guard draft.isProviderRequestAllowed else {
            throw AICompanionCloudGuideError.blockedByPrivacyGateway(
                draft.blockReason ?? "本地隐私网关未放行。"
            )
        }
        guard let config else { throw AICompanionCloudGuideError.notConfigured }
        guard config.resolvedOpenAIStyleBaseURL != nil else {
            throw AICompanionCloudGuideError.providerUnsupported
        }
        let trimmedKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedKey.isEmpty else { throw AICompanionCloudGuideError.notConfigured }

        let response = try await chatClient.complete(
            system: draft.systemPrompt,
            user: draft.userPrompt,
            config: config,
            apiKey: trimmedKey
        )
        return try parseGuide(response)
    }

    private func parseGuide(_ response: String) throws -> AICompanionCloudGuide {
        let normalized = normalizedJSONText(response)
        guard let data = normalized.data(using: .utf8) else {
            throw AICompanionCloudGuideError.badResponse
        }
        struct Envelope: Decodable {
            var reply: String
            var nextQuestions: [String]?
            var guardianSignal: AICompanionGuardianSignal?

            enum CodingKeys: String, CodingKey {
                case reply
                case nextQuestions = "next_questions"
                case guardianSignal = "guardian_signal"
            }
        }
        let decoded: Envelope
        do {
            decoded = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw AICompanionCloudGuideError.badResponse
        }

        let reply = decoded.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        let questions = (decoded.nextQuestions ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(2)
        let guide = AICompanionCloudGuide(
            reply: reply,
            nextQuestions: Array(questions),
            guardianSignal: decoded.guardianSignal ?? .none
        )
        guard !guide.reply.isEmpty else { throw AICompanionCloudGuideError.badResponse }
        guard responseIsSafe(guide) else { throw AICompanionCloudGuideError.unsafeResponse }
        return guide
    }

    private func responseIsSafe(_ guide: AICompanionCloudGuide) -> Bool {
        let values = [guide.reply] + guide.nextQuestions + [guide.guardianSignal.rawValue]
        guard !MobileSyncPayloadGuard.isUnsafe(values) else { return false }
        let rendered = values.joined(separator: " ")
        let forbiddenPhrases = [
            "答案是",
            "答案就是",
            "正确答案是",
            "直接答案",
            "我替你写",
            "answer:",
            "final answer is",
            "solution is",
            "the solution is",
            "the answer is"
        ]
        return !forbiddenPhrases.contains {
            rendered.localizedCaseInsensitiveContains($0)
        }
    }

    private func normalizedJSONText(_ response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
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
