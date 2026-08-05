import Foundation

/// App 内阅读内容生成：按书名+本次章节+年龄，生成适龄的改写阅读文本。
/// 版权边界：不复制受版权保护的原文；输出的是 AI 的改写/复述版
/// （公版故事可完整改编），供孩子在 App 内阅读并跟进进度。
enum AIReadingContentGenerator {

    static func systemPrompt(language: FamilyLanguage) -> String {
        """
        你是儿童阅读材料作者。根据书名、本次要读的章节和孩子年龄，\
        写出这一段内容的适龄改写版，让孩子直接在 App 里阅读。\(language.promptInstruction)\
        只输出 JSON：{"title":"这一段的小标题","content":"正文"}。\
        要求：用孩子能读懂的语言完整讲述这一段的故事/内容（不是摘要，是可以当阅读材料的完整文本）；\
        长度 500-1200 字；分成自然段；忠于原书情节但用你自己的话写（不逐字复制原文）；\
        如果你不了解这本书，就围绕书名主题写一篇同题材的原创小故事，并在开头注明"这是为你写的小故事"。\
        不要输出 JSON 以外的任何内容。
        """
    }

    static func userPrompt(bookTitle: String, chapters: String, childAge: Int) -> String {
        "书名：《\(bookTitle)》；本次要读：\(chapters)；孩子年龄：\(childAge) 岁。"
    }

    static func parse(_ raw: String) -> (title: String, content: String)? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        struct Payload: Decodable {
            let title: String?
            let content: String
        }
        guard let data = text.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.content.count >= 50 else { return nil }
        return (payload.title ?? "", payload.content)
    }
}
