import Foundation

/// 服务商认证方式。
/// 当前所有厂商都只对第三方 App 开放 API 密钥；ChatGPT Plus / Claude Pro / Gemini
/// 等消费订阅不提供官方 OAuth 复用。这里预留 subscriptionLogin，厂商开放后即可接入。
enum AIProviderAuthMethod: String, Codable, CaseIterable {
    case apiKey = "api_key"
    case subscriptionLogin = "subscription_login"

    var label: String {
        switch self {
        case .apiKey: return "API 密钥"
        case .subscriptionLogin: return "订阅账号登录"
        }
    }
}

/// 家长可选择的 AI 服务商类型（BYOK：家长自己的账号和密钥）。
/// 见 docs/DECISIONS.md 2026-07-04: Parent BYOK via Keychain。
/// rawValue 一旦发布不可更改（已作为 Keychain account 与配置 JSON 持久化）。
enum AIProviderKind: String, Codable, CaseIterable, Identifiable {
    case anthropicClaude = "anthropic_claude"
    case openAI = "openai"
    case googleGemini = "google_gemini"
    case deepSeek = "deepseek"
    case moonshotKimi = "moonshot_kimi"
    case alibabaQwen = "alibaba_qwen"
    /// 自定义 OpenAI 兼容服务（自建、本地或其他厂商网关），需填 baseURL。
    case openAICompatible = "openai_compatible"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .anthropicClaude: return "Claude（Anthropic）"
        case .openAI: return "OpenAI（ChatGPT）"
        case .googleGemini: return "Gemini（Google）"
        case .deepSeek: return "DeepSeek（深度求索）"
        case .moonshotKimi: return "Kimi（月之暗面）"
        case .alibabaQwen: return "通义千问（阿里云）"
        case .openAICompatible: return "自定义（OpenAI 兼容）"
        }
    }

    /// 给家长看的一句话简介。
    var blurb: String {
        switch self {
        case .anthropicClaude: return "答疑和引导质量高；暂不支持语音转写。"
        case .openAI: return "通用能力强，且支持 Whisper 语音转写。"
        case .googleGemini: return "有免费额度，适合先试用。"
        case .deepSeek: return "价格便宜，中文能力好。"
        case .moonshotKimi: return "长文本能力强，国内访问稳定。"
        case .alibabaQwen: return "阿里云百炼平台，国内访问稳定。"
        case .openAICompatible: return "本地模型或其他兼容网关，自己填服务地址。"
        }
    }

    /// 家长获取 API 密钥的官方控制台地址（App 内跳转浏览器）。
    var keyConsoleURLString: String {
        switch self {
        case .anthropicClaude: return "https://console.anthropic.com/settings/keys"
        case .openAI: return "https://platform.openai.com/api-keys"
        case .googleGemini: return "https://aistudio.google.com/apikey"
        case .deepSeek: return "https://platform.deepseek.com/api_keys"
        case .moonshotKimi: return "https://platform.moonshot.cn/console/api-keys"
        case .alibabaQwen: return "https://bailian.console.aliyun.com/?apiKey=1"
        case .openAICompatible: return ""
        }
    }

    /// 当前可用的认证方式。订阅登录在所有厂商开放官方第三方 OAuth 前均不可用，
    /// 只在 UI 里展示为「厂商尚未开放」。
    var availableAuthMethods: [AIProviderAuthMethod] { [.apiKey] }

    var needsBaseURL: Bool { self == .openAICompatible }

    /// OpenAI 形态 API 的预置基础地址；Claude 走自家协议返回 nil，自定义由家长填。
    var presetOpenAIStyleBaseURLString: String? {
        switch self {
        case .anthropicClaude: return nil
        case .openAI: return "https://api.openai.com/v1"
        case .googleGemini: return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .deepSeek: return "https://api.deepseek.com/v1"
        case .moonshotKimi: return "https://api.moonshot.cn/v1"
        case .alibabaQwen: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .openAICompatible: return nil
        }
    }

    /// 默认模型建议；家长可覆盖。
    var defaultModelName: String {
        switch self {
        case .anthropicClaude: return "claude-haiku-4-5-20251001"
        case .openAI: return "gpt-4o-mini"
        case .googleGemini: return "gemini-2.5-flash"
        case .deepSeek: return "deepseek-chat"
        case .moonshotKimi: return "kimi-latest"
        case .alibabaQwen: return "qwen-plus"
        case .openAICompatible: return ""
        }
    }

    /// 是否支持音频转写（OpenAI /audio/transcriptions 形态的接口）。
    /// 只有确认提供 Whisper 形态接口的服务商标 true；
    /// 家长选了不支持的服务商时，孩子端语音入口隐藏（打字始终可用）。
    var supportsAudioTranscription: Bool {
        switch self {
        case .openAI, .openAICompatible: return true
        case .anthropicClaude, .googleGemini, .deepSeek, .moonshotKimi, .alibabaQwen: return false
        }
    }

    /// 默认转写模型。
    var defaultTranscriptionModelName: String {
        supportsAudioTranscription ? "whisper-1" : ""
    }
}

/// AI 服务商的非敏感配置。密钥绝不出现在这里：
/// 密钥只存 iOS Keychain（AIProviderKeyStoring），不进家庭 JSON、不进事件流、不进日志。
struct AIProviderConfig: Codable, Equatable {
    var kind: AIProviderKind
    /// 仅 openAICompatible 使用。
    var baseURLString: String
    var modelName: String
    /// 认证方式；旧配置缺省视为 API 密钥。
    var authMethod: AIProviderAuthMethod?

    init(
        kind: AIProviderKind,
        baseURLString: String,
        modelName: String,
        authMethod: AIProviderAuthMethod? = nil
    ) {
        self.kind = kind
        self.baseURLString = baseURLString
        self.modelName = modelName
        self.authMethod = authMethod
    }

    static let none: AIProviderConfig? = nil

    var resolvedAuthMethod: AIProviderAuthMethod { authMethod ?? .apiKey }

    /// 把旧版本里误填的人类产品名迁移为真正可调用的模型 ID。
    /// 未知的合法自定义模型名仍原样保留，避免阻断未来模型。
    var resolvedModelName: String {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return kind.defaultModelName }
        if kind == .openAI {
            let alias = trimmed.lowercased().filter(\.isLetter)
            if ["chatgpt", "openai", "gpt"].contains(alias) {
                return kind.defaultModelName
            }
        }
        return trimmed
    }

    var normalizedForPersistence: AIProviderConfig {
        var normalized = self
        normalized.modelName = resolvedModelName
        return normalized
    }

    /// OpenAI 形态 API 的基础地址；Claude 无此形态返回 nil。
    var resolvedOpenAIStyleBaseURL: URL? {
        if kind == .openAICompatible {
            let trimmed = baseURLString.hasSuffix("/") ? String(baseURLString.dropLast()) : baseURLString
            return URL(string: trimmed)
        }
        guard let preset = kind.presetOpenAIStyleBaseURLString else { return nil }
        return URL(string: preset)
    }
}

/// AI 对孩子提交证明的「初评草稿」。
///
/// 边界（不可动摇）：这只是给家长看的建议摘要，永远不是终审，
/// 不含任何成长积分发放、任务批准或设备解锁能力；批准权始终在家长。
struct AIReviewDraft: Equatable {
    /// 0...1 的置信度；低于验证规则的 minConfidence 时必须转人工。
    var confidence: Double
    /// 给家长看的一句话摘要（脱敏，不复制孩子原文全文）。
    var summary: String
    var recommendation: Recommendation

    enum Recommendation: String, Equatable {
        /// AI 认为证明充分，建议家长通过（仍需家长点确认）。
        case suggestApprove = "suggest_approve"
        /// AI 不确定或证明不足，请家长自行判断。
        case needsParentJudgment = "needs_parent_judgment"
    }
}
