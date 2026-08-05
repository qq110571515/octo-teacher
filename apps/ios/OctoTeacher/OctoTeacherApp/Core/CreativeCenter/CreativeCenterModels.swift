import Foundation

/// 创作广场只投影已有任务链，不另存第二份任务或作品，避免审批和成长积分分叉。
struct CreativeCenterSnapshot: Equatable {
    var active: [TaskAssignment]
    var waitingForParent: [TaskAssignment]
    var completed: [TaskAssignment]

    var totalCount: Int { active.count + waitingForParent.count + completed.count }
    var submittedWorkCount: Int { waitingForParent.count + completed.count }

    static func build(assignments: [TaskAssignment], childId: UUID) -> CreativeCenterSnapshot {
        let creativeAssignments = assignments
            .filter {
                $0.childId == childId
                    && $0.status != .cancelled
                    && ($0.task.creative != nil || $0.task.category == .creative)
            }
            .sorted { $0.date > $1.date }

        return CreativeCenterSnapshot(
            active: creativeAssignments.filter { $0.status == .open || $0.status == .rejected },
            waitingForParent: creativeAssignments.filter { $0.status == .submitted },
            completed: creativeAssignments.filter { $0.status == .approved }
        )
    }
}

enum CreativeCenterCopy {
    static func kind(for task: TaskTemplate) -> CreativeTaskKind {
        task.creative?.kind ?? .handcraft
    }

    static func childFeedback(for assignment: TaskAssignment) -> String {
        childFeedback(for: assignment, language: .chinese)
    }

    /// 孩子可见的状态反馈：AI 点评（数据内容，原样展示）优先，空缺时按界面语言给回退文案。
    static func childFeedback(for assignment: TaskAssignment, language: AppInterfaceLanguage) -> String {
        if let feedback = assignment.aiReview?.childFeedback,
           !feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return feedback
        }
        switch assignment.status {
        case .submitted:
            return language.pick(
                "作品已经交给大人啦。你可以想一想：自己最满意哪一个小细节？",
                "Your work is with a grown-up now. While you wait, think about the little detail you like most!"
            )
        case .approved:
            return language.pick(
                "这件作品已经被大人收藏进成长记录。下一次可以试试一个新的材料或玩法。",
                "A grown-up saved this work in your growth record. Next time, try a new material or a new idea!"
            )
        case .rejected:
            return language.pick(
                "大人请你再补充一点。看看任务里的说明，改好后再把作品交上来。",
                "A grown-up asked you to add a little more. Check the task notes, fix it up, and hand it in again."
            )
        case .open:
            return language.pick(
                "先大胆开始，不需要一次就做到完美。做完拍照，再用语音说说你的想法。",
                "Just dive in — it doesn't have to be perfect the first time. When you're done, take a photo and tell us about it with your voice."
            )
        case .cancelled:
            return language.pick("这个创作任务已经撤销。", "This creative task was cancelled.")
        }
    }
}
