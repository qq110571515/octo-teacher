import Foundation

/// AI 生成的任务草稿（家长勾选/微调后才布置）。
struct GeneratedTaskDraft: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var instructions: String
    var category: TaskCategory
    var rewardPoints: Int
    var requiredProof: ProofKind
    var adultSupervisionRequired: Bool
    var reading: ReadingSpec?

    static func == (lhs: GeneratedTaskDraft, rhs: GeneratedTaskDraft) -> Bool {
        lhs.title == rhs.title && lhs.instructions == rhs.instructions
            && lhs.rewardPoints == rhs.rewardPoints
    }
}

/// AI 包任务生成器：包类型 + 孩子记忆摘要 + 家庭语言 → 个性化任务草稿。
/// 每个包有专属生成策略，记忆摘要保证每次生成都贴合孩子当下的进度和兴趣。
enum AIPackTaskGenerator {

    /// 危险动手关键词：出现即强制标记「需大人在场」。
    static let dangerKeywords = ["刀", "火", "电", "炉", "插座", "剪", "烫", "针", "锯", "钻"]
    /// 金融包禁止出现的真实交易词：出现即丢弃该条草稿。
    static let forbiddenFinanceWords = ["支付", "转账", "收款", "下单", "汇款", "红包"]

    /// 每个包的专属生成策略（注入 system prompt）。
    static func strategy(for packType: PackType) -> String {
        switch packType {
        case .basicHabits:
            return "生成适龄的每日基础生活习惯任务；优先补上摘要里最近没做过的习惯。"
        case .chores:
            return "生成适龄的家务任务；避开摘要里最近已完成的家务，做轮换。"
        case .outdoorSports:
            return "生成适龄、安全、可在院子、公园或社区完成的户外运动任务；优先替代刷短视频/游戏时间，涉及外出、骑行、水边或夜间活动必须标 adultSupervisionRequired=true。"
        case .learning:
            return "生成学习任务；如果摘要里有阅读进度，按进度往下推进（例如已读到第6章就安排第7-8章，用 reading 字段给出书名和章节）。"
        case .skillExtension:
            return "生成动手生活技能任务，结合孩子的兴趣定制，难度循序渐进；涉及刀/火/电等一律标 adultSupervisionRequired=true。"
        case .financeLiteracy:
            return "生成金融素养任务，按年龄阶梯（记账→储蓄目标→纯虚拟模拟）；只做记录和模拟，绝不出现支付、转账、收款等真实交易操作。"
        case .creativeWorks:
            return "生成绘画/手工/写作等创造任务，主题结合孩子兴趣与季节，避免与最近完成的重复。"
        case .familyResponsibility:
            return "生成亲情陪伴与家庭责任任务（打电话给长辈、教家人技能、陪弟妹等）。"
        }
    }

    static func systemPrompt(packType: PackType, language: FamilyLanguage) -> String {
        """
        你是儿童成长任务设计助手。为「\(packType.label)」生成任务。\(strategy(for: packType))\
        \(language.promptInstruction)\
        只输出 JSON，格式：{"tasks":[{"title":"任务名","instructions":"给孩子的说明",\
        "category":"home|learning|health|creative|family","rewardPoints":15,\
        "requiredProof":"text|photo","adultSupervisionRequired":false,\
        "reading":{"bookTitle":"书名","minMinutes":30,"chapterPlanText":"第7-8章"}}]}。\
        reading 字段只有阅读任务才带。rewardPoints 在 5-60 之间，按难度定。\
        标题简短有行动感；说明具体可执行。不要输出 JSON 以外的任何内容。
        """
    }

    static func userPrompt(digest: String, count: Int) -> String {
        "孩子情况：\n\(digest)\n请生成 \(count) 个任务，避免与摘要中未完成的任务重复。"
    }

    /// 解析并执行护栏；失败返回空数组（上层降级到模板库）。
    static func parse(_ raw: String, packType: PackType) -> [GeneratedTaskDraft] {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = text.data(using: .utf8) else { return [] }

        struct Payload: Decodable {
            struct Task: Decodable {
                struct Reading: Decodable {
                    let bookTitle: String
                    let minMinutes: Int?
                    let chapterPlanText: String?
                }
                let title: String
                let instructions: String?
                let category: String?
                let rewardPoints: Int?
                let requiredProof: String?
                let adultSupervisionRequired: Bool?
                let reading: Reading?
            }
            let tasks: [Task]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return [] }

        return payload.tasks.prefix(6).compactMap { task in
            let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let combined = title + (task.instructions ?? "")

            // 金融包护栏：真实交易词直接丢弃整条。
            if packType == .financeLiteracy,
               Self.forbiddenFinanceWords.contains(where: { combined.contains($0) }) {
                return nil
            }
            // 危险动手护栏：命中关键词强制需大人在场。
            let dangerous = Self.dangerKeywords.contains(where: { combined.contains($0) })

            var reading: ReadingSpec?
            if let spec = task.reading, !spec.bookTitle.isEmpty {
                reading = ReadingSpec(
                    bookTitle: spec.bookTitle,
                    minMinutes: max(5, min(120, spec.minMinutes ?? 30)),
                    chapterPlanText: spec.chapterPlanText ?? "",
                    deliveryMode: .digitalRequired
                )
            }

            return GeneratedTaskDraft(
                title: title,
                instructions: task.instructions ?? "",
                category: TaskCategory(rawValue: task.category ?? "") ?? .home,
                rewardPoints: max(5, min(60, task.rewardPoints ?? 15)),
                requiredProof: task.requiredProof == "photo" ? .photo : .text,
                adultSupervisionRequired: (task.adultSupervisionRequired ?? false) || dangerous,
                reading: reading
            )
        }
    }
}
