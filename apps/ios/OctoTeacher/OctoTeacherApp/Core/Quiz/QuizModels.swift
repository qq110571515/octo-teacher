import Foundation

/// 学科（对标真实世界奖项类别），承载 1000 小时徽章体系。
enum LearningSubject: String, Codable, CaseIterable, Identifiable {
    case science
    case literature
    case math
    case art
    case music
    case sports
    case history
    case language

    var id: String { rawValue }

    var label: String {
        switch self {
        case .science: return "科学"
        case .literature: return "文学"
        case .math: return "数学"
        case .art: return "艺术"
        case .music: return "音乐"
        case .sports: return "体育"
        case .history: return "历史"
        case .language: return "语言"
        }
    }

    func label(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return label }
        switch self {
        case .science: return "Science"
        case .literature: return "Literature"
        case .math: return "Math"
        case .art: return "Art"
        case .music: return "Music"
        case .sports: return "Sports"
        case .history: return "History"
        case .language: return "Language"
        }
    }

    var systemImage: String {
        switch self {
        case .science: return "atom"
        case .literature: return "book.fill"
        case .math: return "function"
        case .art: return "paintpalette.fill"
        case .music: return "music.note"
        case .sports: return "figure.run"
        case .history: return "building.columns.fill"
        case .language: return "character.bubble.fill"
        }
    }

    /// 从任务推导学科（v1 启发式）：阅读→文学、视频→科学、创造→艺术、
    /// 体育→体育、学校→数学；家务/家庭不参与学科考试。
    static func from(task: TaskTemplate) -> LearningSubject? {
        if task.reading != nil { return .literature }
        if let video = task.video {
            return LearningSubject(rawValue: video.subjectRaw ?? "") ?? .science
        }
        switch task.category {
        case .creative: return .art
        case .health: return .sports
        case .school: return .math
        case .learning: return .literature
        case .home, .family: return nil
        }
    }
}

/// 某学科的累计进度：学习分钟（任务 + 考试加成）与考试成绩。
struct SubjectProgressEntry: Codable, Equatable {
    var studyMinutes: Int = 0
    var quizPassed: Int = 0
    var quizPoints: Int = 0

    var studyHours: Double { Double(studyMinutes) / 60 }
}

/// 徽章阶梯：按 1000 小时学习量设计，终点是极少数人能达到的诺贝尔级。
enum BadgeLadder {
    /// (小时门槛, 徽章名, 图标)
    static let tiers: [(hours: Double, name: String, icon: String)] = [
        (10, "启蒙", "sparkle"),
        (50, "入门", "leaf.fill"),
        (100, "小学者", "graduationcap.fill"),
        (250, "进阶", "flame.fill"),
        (500, "专家", "star.fill"),
        (750, "大师", "crown.fill"),
        (1000, "诺贝尔级", "trophy.fill")
    ]

    /// 当前达到的徽章（未达到第一档返回 nil）。
    static func currentTier(hours: Double) -> (hours: Double, name: String, icon: String)? {
        tiers.last { hours >= $0.hours }
    }

    /// 下一个目标徽章（已到顶返回 nil）。
    static func nextTier(hours: Double) -> (hours: Double, name: String, icon: String)? {
        tiers.first { hours < $0.hours }
    }

    /// 徽章名的界面语言展示：英文孩子看英文徽章名，查不到时回退原名。
    static func displayName(_ name: String, for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return name }
        return englishNames[name] ?? name
    }

    private static let englishNames: [String: String] = [
        "启蒙": "Spark",
        "入门": "Beginner",
        "小学者": "Young Scholar",
        "进阶": "Rising Star",
        "专家": "Expert",
        "大师": "Master",
        "诺贝尔级": "Nobel Level"
    ]
}

/// 一道 AI 生成的选择题。
struct QuizQuestion: Identifiable, Equatable {
    let id = UUID()
    var question: String
    var options: [String]
    var answerIndex: Int
    /// 答错时给孩子看的答案与推理过程（支持朗读）。
    var explanation: String

    static func == (lhs: QuizQuestion, rhs: QuizQuestion) -> Bool {
        lhs.question == rhs.question && lhs.options == rhs.options
    }
}

/// AI 考试出题：根据孩子刚完成的学习内容（书的章节/视频主题）出选择题。
/// 题量按内容长度自适应（5-30 题）。
enum AIQuizGenerator {

    /// 按学习时长自适应题量：短视频 5 题起，每 3 分钟内容约加 1 题，封顶 30。
    static func questionCount(forMinutes minutes: Int) -> Int {
        min(30, max(5, 5 + minutes / 3))
    }

    static func systemPrompt(language: FamilyLanguage, count: Int, contentKind: TaskVerificationContentKind? = nil) -> String {
        let modeInstruction: String
        switch contentKind {
        case .literacy:
            modeInstruction = "这是识字/字母学习验收，题目应围绕字、词、拼读、字母或简单语义，不要写成故事情节题。"
        case .math:
            modeInstruction = "这是数学学习验收，题目应围绕给出的数学概念和例题，生成适龄练习题。"
        case .knowledge:
            modeInstruction = "这是知识理解验收，题目要围绕给出的真实内容摘要，不要凭空扩展。"
        case .story, .none:
            modeInstruction = "这是阅读理解验收，题目要围绕给出的真实阅读内容、人物、事件和因果关系。"
        }
        return """
        你是儿童学习检验助手。根据孩子刚学完的内容出选择题。\(language.promptInstruction)\
        只输出 JSON：{"questions":[{"question":"题目","options":["A","B","C","D"],\
        "answerIndex":0,"explanation":"答案是什么、为什么，用孩子能懂的话讲清楚推理过程"}]}。\
        出 \(count) 题，都是四选一；题目只围绕给出的学习内容，适合孩子年龄；\
        \(modeInstruction)\
        explanation 必须完整（先给正确答案，再一步步讲为什么）。\
        不要输出 JSON 以外的任何内容。
        """
    }

    static func userPrompt(task: TaskTemplate, childAge: Int, contentExcerpt: String? = nil) -> String {
        var content = "任务：\(task.title)。"
        if let reading = task.reading {
            content += "刚读完《\(reading.bookTitle)》\(reading.chapterPlanText)。"
        }
        if let video = task.video {
            content += "刚看完学习视频（\(video.platformLabel)）：\(task.title)。"
            if let summary = video.contentSummary, !summary.isEmpty {
                content += "家长确认的视频学习摘要：\(summary)。"
            }
        }
        if !task.instructions.isEmpty {
            content += "任务说明：\(task.instructions)。"
        }
        if let contentExcerpt, !contentExcerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            content += "\n真实学习内容摘录（只能据此出题）：\n\(contentExcerpt)"
        }
        return content + "孩子年龄：\(childAge) 岁。"
    }

    static func parse(_ raw: String) -> [QuizQuestion] {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = text.data(using: .utf8) else { return [] }

        struct Payload: Decodable {
            struct Question: Decodable {
                let question: String
                let options: [String]
                let answerIndex: Int?
                let explanation: String?
            }
            let questions: [Question]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return [] }

        return payload.questions.prefix(30).compactMap { item in
            let question = item.question.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !question.isEmpty, item.options.count == 4,
                  let answer = item.answerIndex, (0..<4).contains(answer) else { return nil }
            return QuizQuestion(
                question: question,
                options: item.options,
                answerIndex: answer,
                explanation: item.explanation ?? ""
            )
        }
    }
}
