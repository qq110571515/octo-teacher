import Foundation

/// 云端语音转写错误。对孩子端只展示友好文案，不暴露服务商细节。
enum AudioTranscriptionError: Error, Equatable {
    /// 家长未配置服务商、未存密钥或未开启语音转写。
    case notConfigured
    /// 当前服务商不支持音频转写（如 Claude API）。
    case providerUnsupported
    /// 本机音频文件读不出来。
    case audioUnreadable
    /// 网络或服务商返回错误（statusCode 供家长排查；不含响应体）。
    case requestFailed(statusCode: Int?)
    /// 服务商响应解析失败。
    case badResponse
}

/// 云端语音转写端口。
///
/// 边界（见 DECISIONS 2026-07-04: Cloud AI Transcription via Parent BYOK）：
/// - 家长设备直连服务商；绑定的孩子设备可经家长明确授权的家庭中继瞬时转发。
/// - 家庭中继不保存音频或转写文本，也不会把家长密钥下发到孩子设备。
/// - 调用方必须在转写成功后立即删除本机音频文件。
/// - 转写结果只是文字草稿，须经孩子确认后才进入证明提交。
protocol AudioTranscribing: Sendable {
    func transcribe(audioFileURL: URL, config: AIProviderConfig, apiKey: String) async throws -> String
}

/// OpenAI 形态 `/audio/transcriptions` 的真实客户端（multipart/form-data）。
/// 适用于 OpenAI 与自定义 OpenAI 兼容服务；Claude 配置直接抛 providerUnsupported。
struct OpenAIStyleTranscriptionClient: AudioTranscribing {
    /// 可注入以便单元测试用 URLProtocol 桩替换网络层。
    var session: URLSession = .shared

    func transcribe(audioFileURL: URL, config: AIProviderConfig, apiKey: String) async throws -> String {
        guard config.kind.supportsAudioTranscription,
              let baseURL = config.resolvedOpenAIStyleBaseURL else {
            throw AudioTranscriptionError.providerUnsupported
        }
        guard let audioData = try? Data(contentsOf: audioFileURL), !audioData.isEmpty else {
            throw AudioTranscriptionError.audioUnreadable
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("audio/transcriptions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = "octoteacher-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            boundary: boundary,
            audioData: audioData,
            fileName: audioFileURL.lastPathComponent,
            model: config.kind.defaultTranscriptionModelName
        )

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AudioTranscriptionError.requestFailed(statusCode: nil)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AudioTranscriptionError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AudioTranscriptionError.requestFailed(statusCode: http.statusCode)
        }

        struct TranscriptionResponse: Decodable { let text: String }
        guard let decoded = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) else {
            throw AudioTranscriptionError.badResponse
        }
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AudioTranscriptionError.badResponse }
        return text
    }

    static func multipartBody(boundary: String, audioData: Data, fileName: String, model: String) -> Data {
        var body = Data()
        func appendLine(_ string: String) {
            body.append(Data(string.utf8))
        }
        appendLine("--\(boundary)\r\n")
        appendLine("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        appendLine("\(model)\r\n")
        appendLine("--\(boundary)\r\n")
        appendLine("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        appendLine("Content-Type: audio/m4a\r\n\r\n")
        body.append(audioData)
        appendLine("\r\n--\(boundary)--\r\n")
        return body
    }
}

/// 测试与预览用转写桩：不发网络，按预置结果返回。
struct StubTranscriptionClient: AudioTranscribing {
    var result: Result<String, AudioTranscriptionError>

    func transcribe(audioFileURL: URL, config: AIProviderConfig, apiKey: String) async throws -> String {
        switch result {
        case .success(let text): return text
        case .failure(let error): throw error
        }
    }
}
