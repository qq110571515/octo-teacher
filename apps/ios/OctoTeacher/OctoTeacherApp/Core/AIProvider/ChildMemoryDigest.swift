import Foundation

/// 孩子记忆摘要：从现有任务/奖励数据推导出的脱敏文本，
/// 作为 AI 生成个性化任务的上下文。
///
/// 隐私红线：只含昵称、年龄、兴趣、任务标题/类别/次数、书名与章节进度；
/// 绝不包含照片、语音、证明正文、设备信息。只经家长 BYOK 通道发送。
enum ChildMemoryDigestBuilder {

    /// 生成指定孩子的记忆摘要。纯函数：同样的 store 状态产出同样的文本。
    static func digest(for childId: UUID, store: LocalFamilyStore, recentLimit: Int = 12) -> String {
        guard let child = store.children.first(where: { $0.id == childId }) else { return "" }

        var lines: [String] = []

        // 基础信息
        var intro = "\(child.name)，\(child.age) 岁"
        if !child.resolvedInterests.isEmpty {
            intro += "，兴趣：\(child.resolvedInterests.joined(separator: "、"))"
        }
        lines.append(intro + "。")
        if let notes = child.parentNotes, !notes.isEmpty {
            lines.append("家长备注：\(notes)。")
        }

        let mine = store.assignments.filter { $0.childId == childId }

        // 最近完成
        let approved = mine.filter { $0.status == .approved }
            .sorted { $0.date > $1.date }
            .prefix(recentLimit)
        if approved.isEmpty {
            lines.append("最近还没有完成过任务。")
        } else {
            let items = approved.map { "\($0.task.title)（\($0.task.category.label)）" }
            lines.append("最近完成：\(items.joined(separator: "、"))。")
        }

        // 阅读进度（书名 + 已批准的章节）
        let readingDone = mine
            .filter { $0.status == .approved && $0.task.reading != nil }
            .sorted { $0.date > $1.date }
        if !readingDone.isEmpty {
            var byBook: [String: [String]] = [:]
            for assignment in readingDone {
                guard let reading = assignment.task.reading else { continue }
                if !reading.chapterPlanText.isEmpty {
                    byBook[reading.bookTitle, default: []].append(reading.chapterPlanText)
                }
            }
            let progress = byBook.sorted { $0.key < $1.key }.map { book, chapters in
                "《\(book)》已读完 \(chapters.joined(separator: "、"))"
            }
            if !progress.isEmpty {
                lines.append("阅读进度：\(progress.joined(separator: "；"))。")
            }
        }

        // 类别统计与驳回
        let doneByCategory = Dictionary(grouping: mine.filter { $0.status == .approved }, by: { $0.task.category })
        if !doneByCategory.isEmpty {
            let stats = TaskCategory.allCases.compactMap { category -> String? in
                guard let count = doneByCategory[category]?.count, count > 0 else { return nil }
                return "\(category.label)×\(count)"
            }
            lines.append("完成统计：\(stats.joined(separator: "、"))。")
        }
        let rejectedCount = mine.filter { $0.status == .rejected }.count
        if rejectedCount > 0 {
            lines.append("有 \(rejectedCount) 个任务被驳回过（需要更清楚的完成证明）。")
        }

        // 未完成（避免 AI 重复布置）
        let openTitles = mine.filter { $0.status == .open || $0.status == .submitted }.map(\.task.title)
        if !openTitles.isEmpty {
            lines.append("当前还没完成的任务（生成时避免重复）：\(openTitles.joined(separator: "、"))。")
        }

        return lines.joined(separator: "\n")
    }
}
