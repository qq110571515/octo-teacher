import Foundation

/// AI 给出的一条学习视频建议。
/// AI 无法保证具体视频链接有效，所以建议以「片名/系列 + 频道 + 搜索深链」形式给出，
/// 家长点搜索链接找到真实视频后，把视频链接粘贴回任务表单确认。
struct VideoSuggestionDraft: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var channel: String
    var reason: String
    var searchQuery: String

    var youtubeSearchURL: URL? {
        var components = URLComponents(string: "https://www.youtube.com/results")
        components?.queryItems = [URLQueryItem(name: "search_query", value: searchQuery)]
        return components?.url
    }

    static func == (lhs: VideoSuggestionDraft, rhs: VideoSuggestionDraft) -> Bool {
        lhs.title == rhs.title && lhs.channel == rhs.channel && lhs.searchQuery == rhs.searchQuery
    }
}

/// 视频学习类别目录：覆盖幼儿到青少年的 30+ 类别，
/// 每类映射到学科徽章体系（考试成绩计入对应学科）。
enum VideoCategory: String, CaseIterable, Identifiable {
    case alphabetPhonics = "字母与自然拼读"
    case numbersCounting = "数字与数数"
    case colorsShapes = "颜色与形状"
    case nurseryRhymes = "儿歌律动"
    case habitsSafety = "好习惯与安全"
    case emotions = "情绪与社交"
    case chineseLiteracy = "识字与拼音"
    case chineseReading = "语文与阅读"
    case englishStarter = "英语启蒙"
    case englishStories = "英语故事"
    case mathThinking = "数学思维"
    case mentalMath = "口算与速算"
    case geometryLogic = "图形与逻辑"
    case scienceExperiments = "科学实验"
    case physicsFun = "趣味物理"
    case chemistryFun = "趣味化学"
    case biologyAnimals = "动物与生物"
    case natureEarth = "自然与地球"
    case spaceAstronomy = "太空与天文"
    case dinosaurs = "恐龙世界"
    case historyChina = "中国历史"
    case historyWorld = "世界历史"
    case geographyWorld = "地理与各国文化"
    case artDrawing = "绘画与美术"
    case handcraft = "手工制作"
    case musicInstruments = "音乐与乐器"
    case danceMovement = "舞蹈与律动"
    case sportsSkills = "体育技能"
    case codingKids = "少儿编程"
    case robotsTech = "机器人与科技"
    case financeKids = "儿童财商"
    case healthBody = "身体与健康"
    case documentaries = "儿童纪录片"

    var id: String { rawValue }

    /// 适龄提示，注入 AI prompt。
    var ageHint: String {
        switch self {
        case .alphabetPhonics, .numbersCounting, .colorsShapes, .nurseryRhymes, .habitsSafety, .emotions:
            return "3-6 岁"
        case .chineseLiteracy, .englishStarter, .mentalMath, .handcraft, .danceMovement:
            return "4-8 岁"
        case .chineseReading, .englishStories, .mathThinking, .geometryLogic, .scienceExperiments,
             .biologyAnimals, .natureEarth, .dinosaurs, .artDrawing, .musicInstruments,
             .sportsSkills, .healthBody:
            return "6-12 岁"
        case .physicsFun, .chemistryFun, .spaceAstronomy, .historyChina, .historyWorld,
             .geographyWorld, .codingKids, .robotsTech, .financeKids, .documentaries:
            return "8-14 岁"
        }
    }

    /// 计入哪个学科徽章。
    var subject: LearningSubject {
        switch self {
        case .alphabetPhonics, .englishStarter, .englishStories, .chineseLiteracy:
            return .language
        case .chineseReading, .nurseryRhymes, .emotions, .habitsSafety:
            return .literature
        case .numbersCounting, .mathThinking, .mentalMath, .geometryLogic, .codingKids, .financeKids:
            return .math
        case .scienceExperiments, .physicsFun, .chemistryFun, .biologyAnimals, .natureEarth,
             .spaceAstronomy, .dinosaurs, .robotsTech, .documentaries, .healthBody:
            return .science
        case .historyChina, .historyWorld, .geographyWorld:
            return .history
        case .artDrawing, .handcraft, .colorsShapes:
            return .art
        case .musicInstruments, .danceMovement:
            return .music
        case .sportsSkills:
            return .sports
        }
    }
}

/// AI 视频推荐：学科/主题 + 年龄 → 视频建议清单草稿。
enum AIVideoSuggester {

    static func systemPrompt() -> String {
        """
        你是儿童学习视频推荐助手。根据学科、主题和孩子年龄，推荐适合的学习视频。\
        只推荐知名、安全、适龄的教育频道内容（如 Khan Academy Kids、SciShow Kids、\
        National Geographic Kids、Numberblocks 等，中文内容优先官方教育频道）。\
        只输出 JSON，格式：{"videos":[{"title":"片名或系列名","channel":"频道名",\
        "reason":"一句话推荐理由","searchQuery":"用于在 YouTube 搜索到它的关键词"}]}。\
        推荐 5 条。不要编造具体视频链接。不要输出 JSON 以外的任何内容。
        """
    }

    static func userPrompt(subject: String, topic: String, childAge: Int) -> String {
        let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let topicPart = trimmedTopic.isEmpty ? "" : "；具体想看的内容：\(trimmedTopic)"
        return "学科：\(subject)；孩子年龄：\(childAge) 岁\(topicPart)。"
    }

    /// 解析模型输出；失败返回空数组（家长仍可手动贴链接）。
    static func parse(_ raw: String) -> [VideoSuggestionDraft] {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = text.data(using: .utf8) else { return [] }

        struct Payload: Decodable {
            struct Video: Decodable {
                let title: String
                let channel: String?
                let reason: String?
                let searchQuery: String?
            }
            let videos: [Payload.Video]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return [] }

        return payload.videos.compactMap { video in
            let title = video.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return VideoSuggestionDraft(
                title: title,
                channel: video.channel ?? "",
                reason: video.reason ?? "",
                searchQuery: video.searchQuery ?? title
            )
        }
    }
}

/// 视频学习验收摘要草稿：AI 根据推荐标题/简介生成，家长必须确认或编辑后才用于孩子复述评分。
enum AIVideoLearningAnalyzer {
    static func systemPrompt() -> String {
        """
        你是儿童视频学习验收设计助手。你不能直接观看外部视频，只能根据家长给出的标题、频道、简介和链接，\
        起草一个供家长确认的学习摘要。只输出 JSON：{"summary":"100字以内学习摘要",\
        "retellTargets":["孩子复述时应该提到的要点1","要点2","要点3"]}。\
        摘要要适合孩子年龄，不能假装已经核验视频真实内容；不要输出 JSON 以外的任何内容。
        """
    }

    static func userPrompt(title: String, channel: String, blurb: String, urlString: String, childAge: Int) -> String {
        """
        视频标题：\(title)
        频道：\(channel)
        AI 推荐理由/家长简介：\(blurb)
        链接：\(urlString)
        孩子年龄：\(childAge) 岁。
        请生成家长可编辑确认的学习摘要和复述要点。
        """
    }

    static func parse(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        struct Payload: Decodable {
            let summary: String
            let retellTargets: [String]?
        }
        guard let data = text.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        var parts = [payload.summary.trimmingCharacters(in: .whitespacesAndNewlines)]
        let targets = (payload.retellTargets ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !targets.isEmpty {
            parts.append("复述要点：" + targets.joined(separator: "；"))
        }
        let combined = parts.filter { !$0.isEmpty }.joined(separator: "\n")
        return combined.isEmpty ? nil : combined
    }
}
