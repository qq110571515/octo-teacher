import Foundation

/// 家长自定义任务的发布前翻译器。翻译结果与原文并存，绝不覆盖家长输入。
enum AITaskTranslator {
    struct BatchInput: Codable {
        var id: UUID
        var title: String
        var instructions: String
    }

    static func needsTranslation(
        title: String,
        instructions: String,
        target: AppInterfaceLanguage
    ) -> Bool {
        let text = title + instructions
        let containsHan = text.range(of: #"\p{Han}"#, options: .regularExpression) != nil
        switch target {
        case .english: return containsHan
        case .chinese: return !containsHan && text.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
        }
    }

    static func systemPrompt(target: AppInterfaceLanguage) -> String {
        let language = target == .english ? "natural, child-friendly English" : "自然、适龄的简体中文"
        return """
        You translate a parent-authored child task into \(language). Return JSON only.
        Preserve the exact goal, safety limits, reward meaning, names, durations and proof requirement.
        Do not add advice, remove requirements, answer homework, or change the task difficulty.
        Output exactly {"title":"...","instructions":"..."}. No markdown and no extra keys.
        """
    }

    static func userPrompt(title: String, instructions: String) -> String {
        let payload = Payload(title: title, instructions: instructions)
        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? #"{"title":"","instructions":""}"#
    }

    static func parse(_ raw: String, language: AppInterfaceLanguage) -> TaskLocalizedContent? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = text.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructions = payload.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !MobileSyncPayloadGuard.isUnsafe([title, instructions]) else { return nil }
        return TaskLocalizedContent(language: language, title: title, instructions: instructions)
    }

    static func batchSystemPrompt(target: AppInterfaceLanguage) -> String {
        systemPrompt(target: target) + "\nInput contains tasks. Output exactly {\"tasks\":[{\"id\":\"same UUID\",\"title\":\"...\",\"instructions\":\"...\"}]} and include every input id once."
    }

    static func batchUserPrompt(_ tasks: [BatchInput]) -> String {
        let data = (try? JSONEncoder().encode(["tasks": tasks])) ?? Data()
        return String(data: data, encoding: .utf8) ?? #"{"tasks":[]}"#
    }

    static func parseBatch(
        _ raw: String,
        language: AppInterfaceLanguage,
        expectedIDs: Set<UUID>
    ) -> [UUID: TaskLocalizedContent]? {
        let text = normalizedJSON(raw)
        guard let data = text.data(using: .utf8),
              let payload = try? JSONDecoder().decode(BatchPayload.self, from: data) else { return nil }
        var result: [UUID: TaskLocalizedContent] = [:]
        for item in payload.tasks where expectedIDs.contains(item.id) {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let instructions = item.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !MobileSyncPayloadGuard.isUnsafe([title, instructions]) else { return nil }
            result[item.id] = TaskLocalizedContent(
                language: language,
                title: title,
                instructions: instructions
            )
        }
        return Set(result.keys) == expectedIDs ? result : nil
    }

    private static func normalizedJSON(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private struct Payload: Codable {
        var title: String
        var instructions: String
    }

    private struct BatchPayload: Codable {
        var tasks: [BatchItem]
    }

    private struct BatchItem: Codable {
        var id: UUID
        var title: String
        var instructions: String
    }
}
