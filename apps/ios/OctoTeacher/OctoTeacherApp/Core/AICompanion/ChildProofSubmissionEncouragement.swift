import Foundation

/// 孩子提交证明后的本地小伙伴反馈。
///
/// 这是等待家长确认期间的即时安抚与下一步提示，不调用云端、不读取照片文件、
/// 不判断通过、不发成长积分，也不替孩子解作业。
struct ChildProofSubmissionEncouragement: Equatable {
    var title: String
    var message: String
    var nextAction: String
    var speakText: String

    var displayValues: [String] { [title, message, nextAction, speakText] }

    static func make(
        task: TaskTemplate,
        proof: ProofDraft,
        rewardMinutes: Int,
        language: AppInterfaceLanguage = .chinese
    ) -> ChildProofSubmissionEncouragement {
        let title = language.pick(
            "AI 章鱼老师：我看到你交上去了",
            "AI Octo Teacher: I saw you hand it in!"
        )
        let proofMessage: String
        switch proof.kind {
        case .photo, .photoPlaceholder:
            proofMessage = proof.photoFileName != nil || proof.photoPlaceholderName != nil
                ? language.pick(
                    "你的照片证明已经留在这台设备里，大人会亲自看。",
                    "Your photo proof is saved on this device, and a grown-up will look at it.")
                : language.pick(
                    "你的证明已经保存，等大人看一看。",
                    "Your proof is saved — now a grown-up will take a look.")
        case .text:
            let trimmed = proof.text.trimmingCharacters(in: .whitespacesAndNewlines)
            proofMessage = trimmed.isEmpty
                ? language.pick(
                    "你的证明已经交给大人确认。",
                    "Your proof is off to a grown-up to check.")
                : language.pick(
                    "你的说明已经交给大人确认。",
                    "Your note is off to a grown-up to check.")
        }

        let taskHint = hint(for: task, language: language)
        let nextAction = language.pick(
            "现在可以休息一下，也可以点我聊聊下一步；确认后会得到 \(rewardMinutes) 成长积分。",
            "You can rest now, or tap me to chat about what's next. After the check you'll earn \(rewardMinutes) Growth Points."
        )
        // 英文用空格衔接句子；中文保持原有直接拼接。
        let glue = language == .english ? " " : ""
        return ChildProofSubmissionEncouragement(
            title: title,
            message: "\(proofMessage)\(glue)\(taskHint)",
            nextAction: nextAction,
            speakText: "\(title)\(language.pick("。", "."))\(glue)\(proofMessage)\(glue)\(taskHint)\(glue)\(nextAction)"
        )
    }

    private static func hint(for task: TaskTemplate, language: AppInterfaceLanguage) -> String {
        if let reading = task.reading, !reading.bookTitle.isEmpty {
            return language.pick(
                "你刚完成了《\(reading.bookTitle)》相关任务，已经很棒了。",
                "You just finished a task about \"\(reading.bookTitle)\" — great job!"
            )
        }
        switch task.category {
        case .school, .learning:
            return language.pick(
                "如果这是作业或学习任务，我只会陪你想步骤，不会直接给最终答案。",
                "If this is homework or study, I'll help you think through the steps, not hand you the final answer."
            )
        case .home:
            return language.pick(
                "家务做完后能让家里更舒服，等大人确认就好。",
                "Chores make home nicer — now just wait for a grown-up to check."
            )
        case .health:
            return language.pick(
                "运动完成后先喝点水，等大人确认就好。",
                "Nice moving! Drink some water while a grown-up checks."
            )
        case .creative:
            return language.pick(
                "你的创作已经交上去了，等大人看看你的想法。",
                "Your creation is handed in — a grown-up will get to see your ideas."
            )
        case .family:
            return language.pick(
                "这件家庭小事已经交上去了，等大人确认就好。",
                "This little family task is handed in — just wait for a grown-up to check."
            )
        }
    }
}
