import Foundation

enum ParentAIPlanGoal: String, Equatable {
    case reading
    case outdoor
    case tidy
    case sleep
}

/// 家庭 AI 中心的确定性首页快照。它只整理本机事实，不伪装成云端结论；
/// 云端聊天负责深入讨论，家长确认后才进入任务编辑器。
struct ParentFamilyAIInsight: Equatable {
    var todaySummary: String
    var attentionItems: [String]
    var recentPattern: String
    var communicationSuggestion: String
    var recommendedGoal: ParentAIPlanGoal

    static func build(
        childName: String,
        assignments: [TaskAssignment],
        growthDigest: GrowthMemoryDigest,
        creditBalance: CreditBalance,
        language: AppInterfaceLanguage,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ParentFamilyAIInsight {
        let active = assignments.filter { $0.status != .cancelled }
        let today = active.filter { calendar.isDate($0.date, inSameDayAs: now) }
        let approved = today.filter { $0.status == .approved }.count
        let submitted = active.filter { $0.status == .submitted }.count
        let rejected = active.filter { $0.status == .rejected }.count
        let open = active.filter { $0.status == .open }.count

        let todaySummary = language.pick(
            "\(childName) 今天完成 \(approved) 项，待家长确认 \(submitted) 项，还有 \(open) 项可以继续。",
            "Today, \(childName) completed \(approved), has \(submitted) waiting for review, and \(open) ready to continue."
        )

        var attention: [String] = []
        if submitted > 0 {
            attention.append(language.pick(
                "有 \(submitted) 项成果等待你审核。",
                "\(submitted) submission(s) are waiting for your review."
            ))
        }
        if rejected > 0 {
            attention.append(language.pick(
                "有 \(rejected) 项任务需要重新尝试，先确认步骤是否太大。",
                "\(rejected) task(s) need another try; check whether the first step is too large."
            ))
        }
        if creditBalance.pendingMinutes > 0 {
            attention.append(language.pick(
                "还有 \(creditBalance.pendingMinutes) 成长积分等待确认。",
                "\(creditBalance.pendingMinutes) Growth Points are waiting for confirmation."
            ))
        }
        if attention.isEmpty {
            attention.append(language.pick(
                "目前没有紧急待办，可以和孩子一起选下一件最容易开始的事。",
                "Nothing urgent is waiting. Choose the easiest next step together."
            ))
        }

        let readingCount = growthDigest.kindCounts[GrowthMemoryEventKind.readingProgress.rawValue, default: 0]
        let taskCount = growthDigest.kindCounts[GrowthMemoryEventKind.taskCompletion.rawValue, default: 0]
        let quizCount = growthDigest.kindCounts[GrowthMemoryEventKind.quizResult.rawValue, default: 0]
        let recentPattern = language.pick(
            "近期记录里有 \(taskCount) 次任务完成、\(readingCount) 次阅读和 \(quizCount) 次测验。先观察哪类活动最容易主动开始。",
            "Recent records include \(taskCount) task completion(s), \(readingCount) reading session(s), and \(quizCount) quiz result(s). Notice which activity starts most naturally."
        )

        let communication = rejected > 0
            ? language.pick(
                "先说：『我不是来批评你的，我们把第一步再变小一点。』再让孩子自己选重新开始的时间。",
                "Try: ‘I’m not here to criticize you. Let’s make the first step smaller.’ Then let your child choose when to restart."
            )
            : language.pick(
                "先描述你看到的努力，再问一个问题：『今天哪件事最容易开始？』不要一次给多个要求。",
                "Name the effort you noticed, then ask one question: ‘What feels easiest to start today?’ Avoid giving several demands at once."
            )

        let goal: ParentAIPlanGoal
        if readingCount == 0 {
            goal = .reading
        } else if open == 0 {
            goal = .outdoor
        } else if rejected > 0 {
            goal = .tidy
        } else {
            goal = .sleep
        }

        return ParentFamilyAIInsight(
            todaySummary: todaySummary,
            attentionItems: attention,
            recentPattern: recentPattern,
            communicationSuggestion: communication,
            recommendedGoal: goal
        )
    }
}
