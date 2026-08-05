import Foundation

/// AI 验收初评：孩子提交阅读/视频/创作证明后，AI 按任务要求给出置信度和建议，
/// 供家长审核参考。边界：AI 永不终审、不发积分；家长看到的是"AI 初评 + 建议"。
enum AIProofReviewer {

    /// 该任务是否值得 AI 初评（学习类内容才有判断价值）。
    static func supportsReview(_ task: TaskTemplate) -> Bool {
        task.reading != nil || task.video != nil
            || task.category == .learning || task.category == .creative || task.category == .school
    }

    static func systemPrompt(childLanguage: AppInterfaceLanguage = .chinese) -> String {
        // childFeedback 会直接展示给孩子，必须跟孩子界面语言；summary 面向家长保持中文。
        let feedbackLanguageRule = childLanguage == .english
            ? "childFeedback 必须用简单、适合儿童的英文书写；summary 仍用简体中文。"
            : "childFeedback 用简体中文书写。"
        return """
        你是儿童任务验收助手。孩子完成任务后提交了文字说明，请判断完成质量。\
        只输出 JSON：{"confidence":0.7,"summary":"两句话告诉家长孩子说了什么、\
        是否体现真的完成了","childFeedback":"一句直接对孩子说的具体、温暖、不过度夸张的点评",\
        "recommendation":"suggest_approve 或 needs_parent_judgment"}。\
        \(feedbackLanguageRule)\
        confidence 0-1；说明有细节、能对上任务内容或真实内容摘录才给高分；宁可保守转家长判断。\
        对阅读/视频复述，只评价孩子是否讲到关键内容，不要因为表达稚嫩而苛刻。\
        对创作任务，指出一个已经做到的具体点，再给一个可选择的探索方向；不要替孩子重做作品。\
        不要输出 JSON 以外的任何内容。
        """
    }

    static func userPrompt(task: TaskTemplate, childText: String, contentExcerpt: String? = nil) -> String {
        var content = "任务：\(task.title)。"
        if let reading = task.reading {
            content += "要求读《\(reading.bookTitle)》\(reading.chapterPlanText)。"
        }
        if let video = task.video, let summary = video.contentSummary, !summary.isEmpty {
            content += "家长确认的视频学习摘要：\(summary)。"
        }
        if !task.instructions.isEmpty {
            content += "要求：\(task.instructions)。"
        }
        if let creative = task.creative {
            content += "创作类型：\(creative.kind.label)。创作提示：\(creative.creativePrompt)。"
            if !creative.materials.isEmpty {
                content += "建议材料：\(creative.materials.joined(separator: "、"))。"
            }
        }
        if let contentExcerpt, !contentExcerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            content += "\n真实学习内容摘录/家长确认摘要（用来核对孩子复述）：\n\(contentExcerpt)"
        }
        return content + "\n孩子的完成说明：\(childText)"
    }

    /// 本地确定性初评：没有真实 AI provider/key 时的 fallback，同样便于测试。
    /// 输入只允许任务标题/要求、孩子文字说明、证明类型和「是否已附本机照片」布尔值；
    /// 绝不接触照片文件名、路径或文件内容。同样只是建议，通过与否始终由家长手动决定。
    static func localReview(
        task: TaskTemplate,
        childText: String,
        proofKind: ProofKind,
        hasLocalPhoto: Bool,
        childLanguage: AppInterfaceLanguage = .chinese
    ) -> AIReviewSummary {
        let text = childText.trimmingCharacters(in: .whitespacesAndNewlines)
        var score = 0.35
        var observations: [String] = []

        if text.isEmpty {
            score -= 0.1
            observations.append("孩子没有写文字说明")
        } else {
            observations.append("孩子写了 \(text.count) 字完成说明")
            if text.count >= 20 { score += 0.2 } else if text.count >= 6 { score += 0.1 }
            if let book = task.reading?.bookTitle, !book.isEmpty, text.contains(book) {
                score += 0.15
                observations.append("提到了要读的《\(book)》")
            }
        }

        switch proofKind {
        case .photo, .photoPlaceholder:
            if hasLocalPhoto {
                score += 0.15
                observations.append("附了一张本机照片，请家长亲自查看")
            } else {
                score -= 0.15
                observations.append("还没有附照片")
            }
        case .text:
            break
        }

        // 本地规则宁可保守：置信度封顶 0.85，只有信号足够才建议通过，其余转家长判断。
        let confidence = min(0.85, max(0.1, score))
        // childFeedback 直接展示给孩子，跟随孩子界面语言；summary 面向家长，保持中文。
        let childFeedback: String
        if let creative = task.creative {
            if text.isEmpty {
                childFeedback = childLanguage.pick(
                    "你已经把\(creative.kind.label)作品交出来啦。我很想听你说说：你最满意哪一个地方？",
                    "You handed in your \(creative.kind.label(for: .english).lowercased()) work! I'd love to hear which part you like best."
                )
            } else {
                childFeedback = childLanguage.pick(
                    "我听懂了你的\(creative.kind.label)想法，尤其喜欢你愿意介绍自己的作品。下次还可以试试加一个你自己发明的小细节。",
                    "I understood your \(creative.kind.label(for: .english).lowercased()) idea, and I love that you told us about your work. Next time, try adding one little detail you invented yourself!"
                )
            }
        } else if text.isEmpty {
            childFeedback = childLanguage.pick(
                "你已经把这一步交出来啦。等大人看过后，也可以再告诉我你最满意的地方。",
                "You handed this step in! After a grown-up takes a look, tell me which part you're proudest of."
            )
        } else {
            childFeedback = childLanguage.pick(
                "我听到了你的完成说明。你能说出自己做了什么，这就是一次认真复盘。",
                "I heard how you finished it. Being able to say what you did is great thinking!"
            )
        }
        return AIReviewSummary(
            confidence: confidence,
            summary: observations.joined(separator: "；") + "。此为本地规则初评，仅供参考。",
            recommendation: confidence >= 0.7 ? "suggest_approve" : "needs_parent_judgment",
            source: "local_rule",
            childFeedback: childFeedback
        )
    }

    static func parse(_ raw: String) -> AIReviewSummary? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        struct Payload: Decodable {
            let confidence: Double?
            let summary: String
            let recommendation: String?
            let childFeedback: String?
        }
        guard let data = text.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              !payload.summary.isEmpty else { return nil }
        return AIReviewSummary(
            confidence: min(1, max(0, payload.confidence ?? 0.5)),
            summary: payload.summary,
            recommendation: payload.recommendation == "suggest_approve" ? "suggest_approve" : "needs_parent_judgment",
            childFeedback: payload.childFeedback
        )
    }
}
