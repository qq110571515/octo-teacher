import Foundation

/// AI 验证初评端口：对孩子提交的文字证明（打字或云端转写的语音）产出初评草稿。
///
/// 边界：
/// - 输入只允许文字。孩子原始音频、照片不进入该端口（见 DECISIONS 2026-07-04）。
/// - 输出只是给家长的建议草稿；终审、发成长积分、解锁设备永远不经过这里。
protocol AIVerificationDrafting {
    /// - Parameters:
    ///   - task: 被验证的任务模板（用于取阅读规格等上下文）。
    ///   - childText: 孩子的文字证明（云端转写完成的语音同样是文字）。
    ///   - minConfidence: 验证规则要求的最低置信度，低于则必须转人工。
    func draftReview(task: TaskTemplate, childText: String, minConfidence: Double) -> AIReviewDraft
}

/// 本地确定性 Mock 初评器：不发任何网络请求。
///
/// 用途：在家长尚未配置 AI 服务商、或真实 adapter 未接入前，
/// 让「AI 初评 + 家长终审」的 UI 与数据流先跑通。启发式规则刻意保守：
/// 宁可判 needsParentJudgment，也不轻易 suggestApprove。
struct MockAIVerificationDrafter: AIVerificationDrafting {
    func draftReview(task: TaskTemplate, childText: String, minConfidence: Double) -> AIReviewDraft {
        let trimmed = childText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return AIReviewDraft(
                confidence: 0,
                summary: "孩子还没有写下学到了什么，请家长直接判断。",
                recommendation: .needsParentJudgment
            )
        }

        var confidence = 0.35
        // 有一定长度的复述比一两个字可信。
        if trimmed.count >= 20 { confidence += 0.25 }
        // 阅读任务：提到书名或章节计划里的关键词加分。
        if let reading = task.reading {
            if trimmed.contains(reading.bookTitle) { confidence += 0.15 }
            if !reading.chapterPlanText.isEmpty, trimmed.contains(reading.chapterPlanText) {
                confidence += 0.1
            }
        }
        confidence = min(confidence, 0.85)

        if confidence >= minConfidence {
            return AIReviewDraft(
                confidence: confidence,
                summary: "孩子写了 \(trimmed.count) 字的完成说明，内容有细节，建议家长确认通过。",
                recommendation: .suggestApprove
            )
        }
        return AIReviewDraft(
            confidence: confidence,
            summary: "说明比较简短，看不出足够细节，请家长自行判断。",
            recommendation: .needsParentJudgment
        )
    }
}
