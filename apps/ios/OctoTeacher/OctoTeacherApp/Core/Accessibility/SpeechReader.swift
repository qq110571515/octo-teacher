import AVFoundation
import Foundation
import SwiftUI

/// 儿童无障碍朗读：系统 TTS（设备端、离线、不联网），给不会认字的孩子读出
/// 任务、按钮和说明。家长在设置里开关；会认字的孩子可以关掉。
@MainActor
final class SpeechReader {
    static let shared = SpeechReader()
    private let synthesizer = AVSpeechSynthesizer()
    private var cloudPlayer: AVAudioPlayer?
    private var audioSessionConfigured = false
    /// 云端真人语音通道：App 启动时接线（家庭开关 + BYOK 就绪时返回 mp3）。
    /// 第三个参数是当前孩子界面语言 hint（nil = 按文本内容自动判断）。
    /// nil 或返回 nil 时回落本机 TTS。
    var cloudSynthesizer: ((String, AICompanionVoiceStyle?, AppInterfaceLanguage?) async -> Data?)?

    var isSpeaking: Bool {
        synthesizer.isSpeaking || (cloudPlayer?.isPlaying ?? false)
    }

    private init() {}

    /// UI 测试遍历页面时静音：朗读不应发声拖慢断言，也不影响可见元素。
    nonisolated static let isSuppressedForUITests = ProcessInfo.processInfo.arguments
        .contains { $0.hasPrefix("-OctoTeacherUITest") }

    /// 朗读一段文字：优先跟随传入的孩子界面语言选音色（en-US / zh-CN），
    /// 未传时按内容自动判断；语速放慢适合儿童。
    /// 关键：把音频会话设为 playback，静音键拨到静音也能出声
    /// （否则孩子手机常年静音，喇叭按了"没反应"）。
    func speak(
        _ text: String,
        language: AppInterfaceLanguage? = nil,
        voiceStyle: AICompanionVoiceStyle? = nil,
        rateMultiplier: Double = 1.0,
        prefersLocalLowLatency: Bool = true
    ) {
        guard !Self.isSuppressedForUITests else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeRateMultiplier = min(1.5, max(1.0, rateMultiplier))
        guard !trimmed.isEmpty else { return }
        stop()
        configureAudioSessionIfNeeded()

        // 普通小喇叭/阅读器优先低延迟本机 TTS；AI 气泡朗读可显式保留云端真人语音。
        if !prefersLocalLowLatency, let cloudSynthesizer {
            let cacheText = SpeechCache.textKey(
                trimmed,
                voiceStyle: voiceStyle,
                language: language
            )
            if let cached = SpeechCache.load(text: cacheText) {
                playCloud(cached, rateMultiplier: safeRateMultiplier)
                return
            }
            Task { [weak self] in
                if let data = await cloudSynthesizer(trimmed, voiceStyle, language) {
                    SpeechCache.store(data, text: cacheText)
                    self?.playCloud(data, rateMultiplier: safeRateMultiplier)
                } else {
                    self?.speakLocally(trimmed, language: language, voiceStyle: voiceStyle, rateMultiplier: safeRateMultiplier)
                }
            }
            return
        }
        speakLocally(trimmed, language: language, voiceStyle: voiceStyle, rateMultiplier: safeRateMultiplier)
    }

    private func configureAudioSessionIfNeeded() {
        guard !audioSessionConfigured else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        audioSessionConfigured = true
    }

    private func playCloud(_ data: Data, rateMultiplier: Double) {
        cloudPlayer = try? AVAudioPlayer(data: data)
        cloudPlayer?.enableRate = true
        cloudPlayer?.rate = Float(rateMultiplier)
        cloudPlayer?.prepareToPlay()
        cloudPlayer?.play()
    }

    private func speakLocally(
        _ text: String,
        language: AppInterfaceLanguage?,
        voiceStyle: AICompanionVoiceStyle?,
        rateMultiplier: Double
    ) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestVoice(for: Self.voiceLanguageCode(language: language, text: text))
        let baseRate = voiceStyle?.localSpeechRate ?? 0.48
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, baseRate * Float(rateMultiplier))
        utterance.pitchMultiplier = voiceStyle?.localPitchMultiplier ?? 1.0
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        cloudPlayer?.stop()
    }

    /// 选设备上音质最好的音色：高级版 > 增强版 > 默认，告别机械音。
    /// （家长可在 系统设置→辅助功能→朗读内容→声音 里下载更好的中文语音包。）
    nonisolated static func bestVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        let candidates = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(languageCode.prefix(2)) }
        if #available(iOS 16.0, *) {
            if let premium = candidates.first(where: { $0.quality == .premium }) { return premium }
        }
        if let enhanced = candidates.first(where: { $0.quality == .enhanced }) { return enhanced }
        return AVSpeechSynthesisVoice(language: languageCode)
    }

    /// 含中日韩字符用中文音色，否则用英文音色。纯函数便于测试。
    nonisolated static func languageCode(for text: String) -> String {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
        } ? "zh-CN" : "en-US"
    }

    /// 孩子界面语言到 TTS 音色 locale 的确定性映射。
    nonisolated static func voiceLanguageCode(for language: AppInterfaceLanguage) -> String {
        switch language {
        case .chinese: return "zh-CN"
        case .english: return "en-US"
        }
    }

    /// 音色解析：显式语言优先，未传时按文本内容自动判断。
    nonisolated static func voiceLanguageCode(language: AppInterfaceLanguage?, text: String) -> String {
        guard let language else { return languageCode(for: text) }
        return voiceLanguageCode(for: language)
    }
}

/// 小喇叭按钮：家长开启「语音朗读」后出现在孩子端的文字旁，点一下读出来。
/// 未开启时不渲染（会认字的孩子界面保持干净）。
/// 朗读音色严格跟随当前孩子的界面语言（未显式指定时取活跃孩子的语言）。
struct SpeakButton: View {
    @Environment(LocalFamilyStore.self) private var store
    let text: String
    var language: AppInterfaceLanguage?
    var rateMultiplier: Double = 1.0

    private var resolvedLanguage: AppInterfaceLanguage {
        language ?? store.activeChildInterfaceLanguage
    }

    var body: some View {
        if store.isSpeechEnabled {
            Button {
                SpeechReader.shared.speak(
                    text,
                    language: resolvedLanguage,
                    rateMultiplier: rateMultiplier
                )
            } label: {
                Image(systemName: "speaker.wave.2.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(resolvedLanguage.pick("读给我听", "Read aloud"))
        }
    }
}
