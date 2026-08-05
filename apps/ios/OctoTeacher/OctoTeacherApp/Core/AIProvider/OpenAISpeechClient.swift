import CryptoKit
import Foundation

/// 云端真人语音（OpenAI 形态 /audio/speech）：音质接近真人，
/// 用家长自己的 BYOK 账号；只发送要朗读的文字本身。
struct OpenAISpeechClient: Sendable {
    var session: URLSession = .shared

    func synthesize(
        text: String,
        config: AIProviderConfig,
        apiKey: String,
        voiceStyle: AICompanionVoiceStyle? = nil,
        languageHint: String? = nil
    ) async throws -> Data {
        guard let baseURL = config.resolvedOpenAIStyleBaseURL else {
            throw AIChatError.providerUnsupported
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("audio/speech"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        // OpenAI /audio/speech 只接受官方字段，按已本地化文本自动匹配中英文；
        // languageHint 不进请求体，只留给本机 voice/cache 等本地决策使用。
        let body: [String: Any] = [
            "model": "tts-1",
            "voice": voiceStyle?.openAISpeechVoice ?? "nova",
            "input": String(text.prefix(600)),
            "response_format": "mp3"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              !data.isEmpty else {
            throw AIChatError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode)
        }
        return data
    }
}

/// 语音合成磁盘缓存：同一句话只花一次钱（按文本哈希存 Caches 目录）。
enum SpeechCache {
    private static var directory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("speech-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func key(for text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(32) + ".mp3"
    }

    static func textKey(
        _ text: String,
        voiceStyle: AICompanionVoiceStyle?,
        language: AppInterfaceLanguage? = nil
    ) -> String {
        let voicePart = voiceStyle.map { "voice=\($0.rawValue)" }
        let languagePart = language.map { "language=\($0.rawValue)" }
        let attributes = [voicePart, languagePart].compactMap { $0 }
        guard !attributes.isEmpty else { return text }
        return attributes.joined(separator: "|") + "|" + text
    }

    static func load(text: String) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(String(key(for: text))))
    }

    static func store(_ data: Data, text: String) {
        try? data.write(to: directory.appendingPathComponent(String(key(for: text))))
    }
}
