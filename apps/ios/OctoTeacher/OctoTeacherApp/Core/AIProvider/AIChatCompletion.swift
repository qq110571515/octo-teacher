import Foundation

/// AI 聊天补全错误。
enum AIChatError: Error, Equatable {
    case notConfigured
    case providerUnsupported
    case requestFailed(statusCode: Int?)
    case badResponse
}

/// AI 聊天补全端口：给家长侧的「创作副驾」用（生成章节计划、视频建议、包草稿）。
///
/// 边界：
/// - 只发送最小信息（书名、年龄、主题），不发孩子照片、原始证明、设备信息。
/// - 产出永远是草稿，家长确认才落地。
protocol AIChatCompleting: Sendable {
    /// 发送 system+user 两条消息，要求 JSON 输出，返回助手回复的原始文本。
    func complete(system: String, user: String, config: AIProviderConfig, apiKey: String) async throws -> String
}

/// OpenAI 形态 `/chat/completions` 真实客户端。
/// 适用于 OpenAI 与所有 OpenAI 兼容服务（DeepSeek、Kimi、通义、Gemini 兼容层、自建网关）。
/// Claude 走自家协议，第一版暂不支持（家长会看到降级提示）。
struct OpenAIStyleChatClient: AIChatCompleting {
    var session: URLSession = .shared
    var prefersJSONResponseFormat = true

    func complete(system: String, user: String, config: AIProviderConfig, apiKey: String) async throws -> String {
        guard let baseURL = config.resolvedOpenAIStyleBaseURL else {
            throw AIChatError.providerUnsupported
        }

        let model = config.resolvedModelName
        var (data, statusCode) = try await perform(
            baseURL: baseURL,
            apiKey: apiKey,
            body: Self.requestBody(
                model: model,
                system: system,
                user: user,
                includeJSONResponseFormat: prefersJSONResponseFormat
            )
        )
        // 部分 OpenAI 兼容服务不支持 response_format=json_object，会直接 400；去掉后重试一次。
        if prefersJSONResponseFormat && statusCode == 400 {
            (data, statusCode) = try await perform(
                baseURL: baseURL,
                apiKey: apiKey,
                body: Self.requestBody(model: model, system: system, user: user, includeJSONResponseFormat: false)
            )
        }
        guard (200..<300).contains(statusCode) else {
            throw AIChatError.requestFailed(statusCode: statusCode)
        }

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        guard let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let content = decoded.choices.first?.message.content,
              !content.isEmpty else {
            throw AIChatError.badResponse
        }
        return content
    }

    static func requestBody(
        model: String,
        system: String,
        user: String,
        includeJSONResponseFormat: Bool
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": 0.3
        ]
        if includeJSONResponseFormat {
            body["response_format"] = ["type": "json_object"]
        }
        return body
    }

    private func perform(
        baseURL: URL,
        apiKey: String,
        body: [String: Any]
    ) async throws -> (Data, Int) {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIChatError.requestFailed(statusCode: nil)
        }
        guard let http = response as? HTTPURLResponse else { throw AIChatError.badResponse }
        return (data, http.statusCode)
    }
}

/// 把云端调用失败翻译成可读的诊断文案。
/// 只描述失败类别，不包含密钥、URL 或原始响应内容。
/// 不传 language 时保持中文（家长端），孩子端按孩子界面语言取词；技术词（API key、JSON）保留英文原词。
enum AICloudFailureDiagnosis {
    static func describe(_ error: Error, language: AppInterfaceLanguage = .chinese) -> String {
        if let chatError = error as? AIChatError {
            switch chatError {
            case .notConfigured:
                return language.pick(
                    "AI 服务商未配置或缺少密钥",
                    "The AI provider isn't set up or is missing an API key"
                )
            case .providerUnsupported:
                return language.pick(
                    "当前服务商暂不支持这种聊天调用",
                    "This provider doesn't support this kind of chat call yet"
                )
            case .requestFailed(let statusCode):
                return describeStatus(statusCode, language: language)
            case .badResponse:
                return language.pick(
                    "云端返回格式异常，无法解析",
                    "The cloud reply came back in an unexpected format"
                )
            }
        }
        if let coachError = error as? ParentAICompanionCoachError {
            switch coachError {
            case .blockedBySafetyGate:
                return language.pick(
                    "内容未通过本机安全检查，没有发送到云端",
                    "The content didn't pass the on-device safety check, so it was not sent to the cloud"
                )
            case .badResponse:
                return language.pick(
                    "云端回复不是可用的 JSON 格式，可能是模型不兼容",
                    "The cloud reply wasn't usable JSON — the model may not be compatible"
                )
            case .unsafeResponse:
                return language.pick(
                    "云端回复未通过本机安全检查，已拦截",
                    "The cloud reply didn't pass the on-device safety check and was blocked"
                )
            }
        }
        return language.pick("网络或未知错误", "A network or unknown error happened")
    }

    static func describeStatus(_ statusCode: Int?, language: AppInterfaceLanguage = .chinese) -> String {
        guard let statusCode else {
            return language.pick(
                "网络连接失败，请检查网络后重试",
                "The network connection failed — check the network and try again"
            )
        }
        switch statusCode {
        case 401, 403:
            return language.pick(
                "密钥无效或没有权限（\(statusCode)）",
                "The API key is invalid or has no permission (\(statusCode))"
            )
        case 400:
            return language.pick(
                "请求被服务商拒绝（400），可能是模型不兼容 JSON 输出或参数不支持",
                "The provider rejected the request (400) — the model may not support JSON output or a parameter"
            )
        case 404:
            return language.pick(
                "接口地址或模型名不存在（404）",
                "The endpoint or model name doesn't exist (404)"
            )
        case 429:
            return language.pick(
                "请求太频繁或额度不足（429）",
                "Too many requests or not enough quota (429)"
            )
        case 500...599:
            return language.pick(
                "AI 服务商服务异常（\(statusCode)）",
                "The AI provider had a service problem (\(statusCode))"
            )
        default:
            return language.pick(
                "云端请求失败（\(statusCode)）",
                "The cloud request failed (\(statusCode))"
            )
        }
    }
}

/// 测试与预览用聊天桩。
struct StubChatClient: AIChatCompleting {
    var result: Result<String, AIChatError>

    func complete(system: String, user: String, config: AIProviderConfig, apiKey: String) async throws -> String {
        switch result {
        case .success(let text): return text
        case .failure(let error): throw error
        }
    }
}
