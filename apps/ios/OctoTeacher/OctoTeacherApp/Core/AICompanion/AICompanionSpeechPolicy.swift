import Foundation

/// AI 小伙伴聊天朗读边界：普通进入页面、文字和图片消息绝不自动播放；
/// 只有孩子明确用语音发起一轮对话时，AI 才用语音回答这一轮。
/// 孩子可见文案支持中英双语：不传 language 时保持中文，兼容既有调用与测试。
enum AICompanionSpeechPolicy {
    static let autoReadsCompanionReplies = false

    static func shouldAutoReadReply(inputWasVoice: Bool, isSpeechEnabled: Bool = true) -> Bool {
        inputWasVoice && isSpeechEnabled
    }

    static func canManuallyRead(isCompanionMessage: Bool, text: String, isSpeechEnabled: Bool = true) -> Bool {
        guard isSpeechEnabled else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 「正在认真想 / is thinking hard」是云端回复前的占位气泡，不该出现小喇叭。
        return isCompanionMessage
            && !trimmed.isEmpty
            && !trimmed.contains("正在认真想")
            && !trimmed.contains("is thinking hard")
    }

    static func utterance(
        companionName: String,
        text: String,
        language: AppInterfaceLanguage = .chinese
    ) -> String {
        let name = companionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = name.isEmpty ? language.pick("AI 章鱼老师", "AI Octo Teacher") : name
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return language.pick("\(safeName)：\(trimmedText)", "\(safeName): \(trimmedText)")
    }

    static func manualReadControlLabel(
        isSpeaking: Bool,
        language: AppInterfaceLanguage = .chinese
    ) -> String {
        isSpeaking
            ? language.pick("停止朗读", "Stop reading")
            : language.pick("读给我听", "Read aloud")
    }

    static func manualReadControlSystemImage(isSpeaking: Bool) -> String {
        isSpeaking ? "stop.circle.fill" : "speaker.wave.2.circle.fill"
    }
}
