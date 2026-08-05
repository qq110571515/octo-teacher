import Foundation

/// AI 书目识别：从家长粘贴的链接或文本里识别书名（只取书名，不抓内容）。
enum AIBookLinkReader {
    static func systemPrompt() -> String {
        """
        你是图书识别助手。家长会给你一个图书链接或一段文字，请识别出书名。\
        只输出 JSON：{"bookTitle":"书名","author":"作者（不确定则留空）"}。\
        无法识别时输出 {"bookTitle":""}。不要输出 JSON 以外的任何内容。
        """
    }

    static func userPrompt(linkOrText: String) -> String {
        "链接或文字：\(linkOrText)"
    }

    static func parse(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        struct Payload: Decodable { let bookTitle: String }
        guard let data = text.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        let title = payload.bookTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }
}

/// AI 任务编辑：家长一句话意图 + 原任务 → 修改后的任务草稿（家长确认才替换）。
enum AITaskEditor {
    static func systemPrompt(language: FamilyLanguage) -> String {
        """
        你是儿童任务修改助手。家长会给你一个现有任务和修改意图，请输出修改后的任务。\
        \(language.promptInstruction)\
        只输出 JSON，格式：{"tasks":[{"title":"任务名","instructions":"给孩子的说明",\
        "category":"home|learning|health|creative|family","rewardPoints":15,\
        "requiredProof":"text|photo","adultSupervisionRequired":false}]}，恰好 1 个任务。\
        保留原任务的核心目标，只按意图调整。不要输出 JSON 以外的任何内容。
        """
    }

    static func userPrompt(task: TaskTemplate, intent: String, digest: String) -> String {
        """
        原任务：标题「\(task.title)」；说明「\(task.instructions)」；\
        类别 \(task.category.rawValue)；奖励 \(task.rewardMinutes) 成长积分。
        修改意图：\(intent)
        孩子情况：\(digest)
        """
    }

    /// 复用生成器的解析与护栏，取第一条。
    static func parse(_ raw: String, packType: PackType?) -> GeneratedTaskDraft? {
        AIPackTaskGenerator.parse(raw, packType: packType ?? .basicHabits).first
    }
}
