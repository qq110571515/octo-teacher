import Foundation

enum ReadingPlanMode: String, CaseIterable, Identifiable {
    case automatic
    case custom

    var id: String { rawValue }
}

/// AI 生成的一次阅读安排草稿（家长可改，确认后才成为任务）。
struct ReadingSessionDraft: Identifiable, Equatable {
    let id = UUID()
    var order: Int
    var chapters: String
    var estimatedMinutes: Int
    /// 给家长看的一句话说明（如"本章有生词较多，可陪读"）。
    var note: String
    /// AI 按难度建议的成长积分；缺省时用家长设的默认值。
    var suggestedPoints: Int?
    /// 本地导入 EPUB/TXT 后由 App 计算的真实字符范围；AI 生成计划可为空。
    var startCharacter: Int? = nil
    var endCharacter: Int? = nil

    static func == (lhs: ReadingSessionDraft, rhs: ReadingSessionDraft) -> Bool {
        lhs.order == rhs.order && lhs.chapters == rhs.chapters
            && lhs.estimatedMinutes == rhs.estimatedMinutes && lhs.note == rhs.note
            && lhs.startCharacter == rhs.startCharacter && lhs.endCharacter == rhs.endCharacter
    }
}

/// AI 阅读布置：书名 + 年龄 + 家长划分偏好 → 逐章阅读计划草稿。
///
/// 关键设计：知名童书不需要抓全文——模型已了解主流童书结构，
/// 直接按书名生成章节安排；冷门书由模型按页数/时长均分并注明"家长可调整"。
enum AIReadingPlanner {

    static func systemPrompt() -> String {
        """
        你是儿童阅读规划助手。根据书名和孩子年龄，生成整本书的分次阅读计划。\
        只输出 JSON，格式：{"intro":"给家长看的书籍简介（三四句话：讲什么、孩子能收获什么）",\
        "sessions":[{"order":1,"chapters":"第1-2章","estimatedMinutes":60,\
        "suggestedPoints":20,"note":"一句话说明"}]}。\
        规则：普通文本每次安排约 5,000-10,000 个英文单词（目标约 7,500）；\
        幼儿图文书默认每 2 章安排一次。若用户明确给出“家长指定次数”，sessions 数组必须严格等于该次数，\
        再把全书章节尽量均衡、连续、无遗漏地分配进去。suggestedPoints 按这一次的难度和量给 10-45 的成长积分建议\
        （难的章节分多一点）。如果你熟悉这本书，按真实章节结构分配；\
        如果不熟悉，按均匀节奏分配，并在 intro 里注明"我不熟悉这本书，家长可调整"。\
        chapters 用中文描述（如"第1-2章"或"第10-25页"）。不要输出 JSON 以外的任何内容。
        """
    }

    static func userPrompt(
        bookTitle: String,
        childAge: Int,
        requestedSessions: Int? = nil,
        isPictureBook: Bool = false
    ) -> String {
        let planningRule: String
        if let requestedSessions {
            planningRule = "家长指定次数：\(requestedSessions) 次。必须严格生成 \(requestedSessions) 个 sessions。"
        } else if isPictureBook {
            planningRule = "这是幼儿图文书：每 2 章为一次阅读任务，末次可以只有 1 章。"
        } else {
            planningRule = "自动划分：普通文本每次约 5,000-10,000 个单词。"
        }
        return "书名：《\(bookTitle)》；孩子年龄：\(childAge) 岁。\(planningRule)"
    }

    /// 解析模型输出（含书籍简介）。容忍 markdown 代码围栏；解析失败返回空计划。
    static func parseWithIntro(_ raw: String) -> (intro: String, sessions: [ReadingSessionDraft]) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        struct IntroPayload: Decodable { let intro: String? }
        let intro = (try? JSONDecoder().decode(IntroPayload.self, from: Data(text.utf8)))?.intro ?? ""
        return (intro, parse(text))
    }

    /// 解析模型输出。容忍 markdown 代码围栏；解析失败返回空数组（上层降级为手动计划）。
    static func parse(_ raw: String) -> [ReadingSessionDraft] {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = text.data(using: .utf8) else { return [] }

        struct Payload: Decodable {
            struct Session: Decodable {
                let order: Int?
                let chapters: String
                let estimatedMinutes: Int?
                let suggestedPoints: Int?
                let note: String?
            }
            let sessions: [Session]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return [] }

        return payload.sessions.enumerated().compactMap { index, session in
            let chapters = session.chapters.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !chapters.isEmpty else { return nil }
            return ReadingSessionDraft(
                order: session.order ?? (index + 1),
                chapters: chapters,
                estimatedMinutes: max(5, min(120, session.estimatedMinutes ?? 60)),
                note: session.note ?? "",
                suggestedPoints: session.suggestedPoints.map { max(5, min(60, $0)) }
            )
        }
    }
}

/// 书目来源目录：家长自行登录选书，App 只登记书名，不抓取版权内容。
struct ReadingSource: Identifiable, Equatable {
    let id: String
    var name: String
    var blurb: String
    /// 为空表示无需跳转（实体书/学校课本）。
    var urlString: String
}

enum ReadingSourceDirectory {
    static let sources: [ReadingSource] = [
        ReadingSource(id: "physical", name: "实体书 / 家里的书", blurb: "最推荐：家里书架上的书直接登记书名即可。", urlString: ""),
        ReadingSource(id: "school", name: "学校课本 / 老师指定", blurb: "语文课本、学校发的阅读书目。", urlString: ""),
        ReadingSource(id: "gutenberg", name: "Project Gutenberg", blurb: "英文公版书库，免费全文。", urlString: "https://www.gutenberg.org"),
        ReadingSource(id: "openlibrary", name: "Open Library", blurb: "网上图书馆，可借阅英文电子书。", urlString: "https://openlibrary.org"),
        ReadingSource(id: "weread", name: "微信读书", blurb: "中文电子书，家长用自己账号登录。", urlString: "https://weread.qq.com"),
        ReadingSource(id: "kada", name: "KaDa 咔哒故事", blurb: "中文儿童绘本与分级阅读。", urlString: "https://www.kadastory.com"),
        ReadingSource(id: "epic", name: "Epic!", blurb: "英文儿童分级阅读平台。", urlString: "https://www.getepic.com"),
        ReadingSource(id: "palfish", name: "伴鱼绘本", blurb: "英文绘本跟读。", urlString: "https://www.ipalfish.com"),
        ReadingSource(id: "smartedu", name: "国家中小学智慧教育平台", blurb: "官方免费课程与读物。", urlString: "https://www.zxx.edu.cn"),
        ReadingSource(id: "storyweaver", name: "StoryWeaver", blurb: "多语言免费儿童故事。", urlString: "https://storyweaver.org.in")
    ]
}
