import Foundation

/// 书籍类别目录：从幼儿启蒙到青少年，家长选类别，AI 负责选书。
enum BookCategory: String, CaseIterable, Identifiable {
    case alphabet = "字母启蒙"
    case numbers = "数字与数学启蒙"
    case colorsShapes = "颜色与形状"
    case nurseryRhymes = "儿歌童谣"
    case habitPicture = "习惯养成绘本"
    case emotionPicture = "情绪管理绘本"
    case classicFairy = "经典童话"
    case fables = "寓言与成语故事"
    case bridgeBooks = "桥梁书（拼音/初级章节）"
    case childrenLiterature = "儿童文学经典"
    case scienceEncyclopedia = "科普百科"
    case dinosaurNature = "恐龙与自然"
    case spaceUniverse = "太空与宇宙"
    case historyStories = "历史故事"
    case biography = "人物传记"
    case detectiveAdventure = "侦探与冒险"
    case fantasyMagic = "奇幻与魔法"
    case scienceFiction = "科幻"
    case poetryProse = "诗歌与散文"
    case englishGraded = "英语分级阅读"
    case comicScience = "漫画科普"
    case growthPsychology = "心理与成长"
    case safetyEducation = "安全与自我保护"
    case traditionalCulture = "传统文化与节日"
    case artMusic = "艺术与音乐启蒙"
    case teenNovel = "青少年小说"

    var id: String { rawValue }

    /// 大致适龄段，注入 prompt 帮 AI 选书。
    var ageHint: String {
        switch self {
        case .alphabet, .numbers, .colorsShapes, .nurseryRhymes: return "3-6 岁"
        case .habitPicture, .emotionPicture, .classicFairy: return "3-8 岁"
        case .fables, .bridgeBooks: return "6-9 岁"
        case .childrenLiterature, .scienceEncyclopedia, .dinosaurNature, .spaceUniverse,
             .historyStories, .detectiveAdventure, .comicScience, .safetyEducation,
             .traditionalCulture, .artMusic: return "6-12 岁"
        case .biography, .fantasyMagic, .poetryProse, .englishGraded, .growthPsychology: return "8-14 岁"
        case .scienceFiction, .teenNovel: return "10-16 岁"
        }
    }

    /// 这几类是给不识字或刚开始识字的孩子用的，推荐和找书都要更严格。
    var isPreReaderFoundation: Bool {
        switch self {
        case .alphabet, .numbers, .colorsShapes, .nurseryRhymes:
            return true
        default:
            return false
        }
    }

    /// 这些类别默认按图文书规划：每两章形成一次阅读任务。
    var usesPictureBookSessionPlanning: Bool {
        switch self {
        case .alphabet, .numbers, .colorsShapes, .nurseryRhymes, .habitPicture, .emotionPicture:
            return true
        default:
            return false
        }
    }

    var preReaderRecommendationBrief: String {
        guard isPreReaderFoundation else {
            return "按类别选择适龄、真实、可找到免费/无 DRM 来源的书。"
        }
        let shared = """
        早教硬性筛选：孩子可能还不识字，优先亲子共读/听读、图画支撑强、\
        单页文字少、重复句式或韵律明显、概念单一清楚、可在 5-15 分钟内读完一小段的书。\
        避免长篇章节书、密集小说、青少年读物、成人散文、抽象说教和需要大量独立阅读的材料。\
        如果中文免费来源不足，优先选择英文公版早教/童谣/启蒙读物，App 会提供逐段中英双语辅助。\
        blurb 必须说明为什么适合“不识字/刚识字”的孩子，以及家长怎样陪读。
        """
        switch self {
        case .alphabet:
            return shared + "\n专项目标：围绕 ABC、字母形状、字母音、押韵、首字母认知；优先 alphabet book、ABC primer、phonics primer、read-aloud picture book。"
        case .numbers:
            return shared + "\n专项目标：围绕 1-10/1-20 数数、多少比较、实物数量、简单加减的直观感知；优先 counting book、number primer、arithmetic primer、picture book。"
        case .colorsShapes:
            return shared + "\n专项目标：围绕颜色、形状、分类、模式和日常物体观察；优先 color book、shape book、picture book。"
        case .nurseryRhymes:
            return shared + "\n专项目标：围绕儿歌、童谣、节奏、押韵和可跟读；优先 nursery rhymes、Mother Goose、read-aloud rhyme book。"
        default:
            return shared
        }
    }

    var sourceDiscoveryKeywords: [String] {
        switch self {
        case .alphabet:
            return ["ABC", "alphabet book", "phonics primer", "letters", "picture book", "read aloud"]
        case .numbers:
            return ["counting", "number book", "numbers", "arithmetic primer", "picture book", "read aloud"]
        case .colorsShapes:
            return ["colors", "shapes", "color book", "shape book", "picture book", "read aloud"]
        case .nurseryRhymes:
            return ["nursery rhymes", "Mother Goose", "rhyme book", "read aloud", "picture book"]
        default:
            return []
        }
    }
}

/// AI 推荐的一本候选书。
struct BookCandidate: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var author: String
    var blurb: String

    var sourceKey: String {
        "\(title.lowercased())|\(author.lowercased())"
    }

    static func == (lhs: BookCandidate, rhs: BookCandidate) -> Bool {
        lhs.title == rhs.title && lhs.author == rhs.author
    }
}

/// AI 选书：类别 + 年龄 + 记忆摘要 → 3 本候选书（含给家长看的简介）。
enum AIBookRecommender {

    static func systemPrompt(language: FamilyLanguage, parentLanguage: FamilyLanguage = .chinese) -> String {
        """
        你是儿童书目推荐专家。根据类别、孩子年龄和阅读历史，推荐 3 本真实存在的、\
        适龄的、口碑好的书。避开孩子已读过的书。\
        书是给孩子读的：\(language.promptInstruction)（title 用该语言的原书名）。\
        优先推荐能在 Project Gutenberg、Standard Ebooks、Internet Archive、Open Library、\
        Wikisource 中找到免费/公版/可阅读版本的真实书，\
        尤其优先推荐可下载并导入 App 的公版经典。\
        如果孩子内容语言是中文或中英双语，但家庭地区/免费来源更容易拿到英文 EPUB，\
        可以推荐英文公版书；App 内阅读器会提供逐段中英双语翻译辅助。\
        blurb 是给家长看的：\(parentLanguage.promptInstruction)\
        只输出 JSON：{"books":[{"title":"书名","author":"作者",\
        "blurb":"两三句话的简介，告诉家长这本书讲什么、适合什么样的孩子"}]}。\
        对“字母启蒙、数字与数学启蒙、颜色与形状、儿歌童谣”这类幼儿启蒙类别，\
        必须额外严格：优先适合不识字孩子的亲子共读/听读/图画支撑/重复韵律材料，\
        不要把长篇章节书、密集小说或青少年经典伪装成启蒙书。\
        必须是真实出版过的书，不要编造。不要输出 JSON 以外的任何内容。
        """
    }

    static func userPrompt(category: BookCategory, digest: String) -> String {
        """
        类别：\(category.rawValue)（适龄参考 \(category.ageHint)）。
        \(category.preReaderRecommendationBrief)
        孩子情况：
        \(digest)
        """
    }

    static func parse(_ raw: String) -> [BookCandidate] {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = text.data(using: .utf8) else { return [] }

        struct Payload: Decodable {
            struct Book: Decodable {
                let title: String
                let author: String?
                let blurb: String?
            }
            let books: [Book]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return [] }
        return payload.books.prefix(5).compactMap { book in
            let title = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return BookCandidate(title: title, author: book.author ?? "", blurb: book.blurb ?? "")
        }
    }
}
