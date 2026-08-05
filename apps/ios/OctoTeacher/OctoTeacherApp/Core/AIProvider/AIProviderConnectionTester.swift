import Foundation

/// 连通性测试结果，给家长看的一句话结论。
enum AIProviderConnectionResult: Equatable {
    case ok
    /// 还没保存配置或密钥。
    case notConfigured
    /// 密钥无效或没有权限（401/403）。
    case unauthorized
    /// 其他 HTTP 错误。
    case failed(statusCode: Int)
    /// 网络不通或地址错误。
    case unreachable

    var message: String {
        switch self {
        case .ok: return "连接成功，密钥可用。"
        case .notConfigured: return "先保存服务商和密钥，再测试连接。"
        case .unauthorized: return "密钥无效或没有权限，请检查后重试。"
        case .failed(let code): return "服务返回错误（\(code)），稍后再试。"
        case .unreachable: return "连不上服务，请检查网络或服务地址。"
        }
    }
}

/// 服务商连通性测试：用最便宜的只读请求验证「地址通 + 密钥有效」。
///
/// - OpenAI 形态：GET {base}/models + Bearer。
/// - Claude：GET https://api.anthropic.com/v1/models + x-api-key + anthropic-version。
/// 不发送任何家庭或孩子数据，只带密钥本身。
struct AIProviderConnectionTester: Sendable {
    var session: URLSession = .shared

    func test(config: AIProviderConfig, apiKey: String) async -> AIProviderConnectionResult {
        guard let request = Self.buildRequest(config: config, apiKey: apiKey) else {
            return .unreachable
        }
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unreachable }
            switch http.statusCode {
            case 200..<300: return .ok
            case 401, 403: return .unauthorized
            default: return .failed(statusCode: http.statusCode)
            }
        } catch {
            return .unreachable
        }
    }

    static func buildRequest(config: AIProviderConfig, apiKey: String) -> URLRequest? {
        if config.kind == .anthropicClaude {
            guard let url = URL(string: "https://api.anthropic.com/v1/models") else { return nil }
            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            return request
        }
        guard let baseURL = config.resolvedOpenAIStyleBaseURL else { return nil }
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }
}
