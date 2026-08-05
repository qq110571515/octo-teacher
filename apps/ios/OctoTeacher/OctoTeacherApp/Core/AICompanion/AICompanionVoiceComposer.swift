import Foundation

/// 语音转写并入输入框的可测逻辑。
///
/// 规则：转写结果只并入待发送草稿，不直接发送；这样孩子可以继续补文字、
/// 加图片，最后把语音+图片合并成同一条消息发出去。
enum AICompanionVoiceComposer {
    /// 把转写文字并入当前草稿；两段都有内容时用空格衔接。
    static func mergedDraft(existingDraft: String, transcript: String) -> String {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else { return existingDraft }
        let trimmedDraft = existingDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return trimmedTranscript }
        return "\(trimmedDraft) \(trimmedTranscript)"
    }

    /// 转写成功后的提示文案：有待发送图片时说明会合并成同一条消息。
    /// 不传 language 时保持中文，兼容既有调用与测试。
    static func successFeedback(
        companionName: String,
        hasPendingImages: Bool,
        language: AppInterfaceLanguage = .chinese
    ) -> String {
        if hasPendingImages {
            return language.pick(
                "你说的话已经放进输入框，点发送后会和图片放进同一条消息给\(companionName)。",
                "Your words are in the message bar; tap send and they'll go with your pictures in one message to \(companionName)."
            )
        }
        return language.pick(
            "你说的话已经放进输入框，看一眼没问题就点发送。",
            "Your words are in the message bar — check them and tap send."
        )
    }
}
