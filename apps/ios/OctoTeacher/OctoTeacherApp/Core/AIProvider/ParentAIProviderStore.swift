import Foundation
import Observation

/// 家长 AI 服务商配置 Store。
///
/// 非敏感配置（服务商、baseURL、模型名）存 UserDefaults；
/// 密钥只经 AIProviderKeyStoring 进 Keychain，二者物理分离。
/// UI 直读直写，隔离在主线程；转写的网络部分由 Sendable 客户端在后台执行。
@MainActor
@Observable
final class ParentAIProviderStore {
    private(set) var config: AIProviderConfig?
    /// 当前配置的服务商是否已有密钥（只暴露布尔值，不暴露密钥内容）。
    private(set) var hasKey = false

    /// 家长是否显式允许孩子使用云端语音转写。默认关闭。
    /// 见 DECISIONS 2026-07-04: Cloud AI Transcription via Parent BYOK。
    private(set) var allowsChildVoiceTranscription = false

    /// 家长是否显式允许孩子 AI 小伙伴使用云端引导。默认关闭。
    private(set) var allowsChildAICompanionGuidance = false

    /// 家长是否显式允许孩子 AI 小伙伴把图片发给云端模型。默认关闭。
    private(set) var allowsChildAICompanionImageUpload = false

    @ObservationIgnored private let keyStore: any AIProviderKeyStoring
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private weak var familyCloud: FamilyCloudSessionStore?
    private static let configKey = "octoteacher.aiprovider.config"
    private static let voiceConsentKey = "octoteacher.aiprovider.voiceconsent"
    private static let companionGuidanceConsentKey = "octoteacher.aiprovider.companionguidanceconsent"
    private static let companionImageUploadConsentKey = "octoteacher.aiprovider.companionimageuploadconsent"

    /// - Parameters:
    ///   - keyStore: 密钥端口；生产用 Keychain，测试用内存。
    ///   - defaults: 配置落盘目标；传 nil 时纯内存（测试）。
    init(
        keyStore: any AIProviderKeyStoring = KeychainAIProviderKeyStore(),
        defaults: UserDefaults? = .standard
    ) {
        self.keyStore = keyStore
        self.defaults = defaults

        if let data = defaults?.data(forKey: Self.configKey),
           let saved = try? JSONDecoder().decode(AIProviderConfig.self, from: data) {
            let normalized = saved.normalizedForPersistence
            config = normalized
            hasKey = keyStore.hasKey(for: normalized.kind)
            if normalized != saved, let migrated = try? JSONEncoder().encode(normalized) {
                defaults?.set(migrated, forKey: Self.configKey)
            }
        }
        allowsChildVoiceTranscription = defaults?.bool(forKey: Self.voiceConsentKey) ?? false
        allowsChildAICompanionGuidance = defaults?.bool(forKey: Self.companionGuidanceConsentKey) ?? false
        allowsChildAICompanionImageUpload = defaults?.bool(forKey: Self.companionImageUploadConsentKey) ?? false
    }

    /// 保存配置与密钥。密钥为空时保留已有密钥（家长只改模型名的场景）。
    @discardableResult
    func apply(kind: AIProviderKind, baseURLString: String, modelName: String, key: String) -> Bool {
        let trimmedBase = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind.needsBaseURL, trimmedBase.isEmpty { return false }

        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            guard keyStore.saveKey(trimmedKey, for: kind) else { return false }
        }

        let newConfig = AIProviderConfig(
            kind: kind,
            baseURLString: kind.needsBaseURL ? trimmedBase : "",
            modelName: modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        ).normalizedForPersistence
        config = newConfig
        hasKey = keyStore.hasKey(for: kind)
        persistConfig(newConfig)
        return true
    }

    /// 删除当前服务商的密钥并清空配置。
    func disconnect() {
        if let kind = config?.kind {
            keyStore.deleteKey(for: kind)
        }
        config = nil
        hasKey = false
        defaults?.removeObject(forKey: Self.configKey)
    }

    /// AI 初评是否就绪：有配置且有密钥。
    /// 未就绪时上层必须降级为纯人工验证通道，不阻塞任何审批。
    var isReadyForDrafting: Bool {
        config != nil && hasKey
    }

    /// 家长开关：允许/禁止孩子语音转写。
    func setChildVoiceTranscription(allowed: Bool) {
        allowsChildVoiceTranscription = allowed
        defaults?.set(allowed, forKey: Self.voiceConsentKey)
    }

    /// 家长开关：允许/禁止孩子 AI 小伙伴使用云端引导。
    func setChildAICompanionGuidance(allowed: Bool) {
        allowsChildAICompanionGuidance = allowed
        defaults?.set(allowed, forKey: Self.companionGuidanceConsentKey)
    }

    /// 家长开关：允许/禁止孩子 AI 小伙伴把图片发给云端视觉模型。
    func setChildAICompanionImageUpload(allowed: Bool) {
        allowsChildAICompanionImageUpload = allowed
        defaults?.set(allowed, forKey: Self.companionImageUploadConsentKey)
    }

    func attachFamilyCloud(_ familyCloud: FamilyCloudSessionStore) {
        self.familyCloud = familyCloud
    }

    /// 孩子端语音转写是否可用：已配置 + 有密钥 + 服务商支持转写 + 家长显式开启。
    /// 任一条件不满足时语音入口隐藏，孩子始终可以打字。
    var isVoiceTranscriptionReady: Bool {
        let localReady = config.map {
            hasKey && $0.kind.supportsAudioTranscription && allowsChildVoiceTranscription
        } ?? false
        return localReady || familyCloud?.isChildAIVoiceRelayReady == true
    }

    /// 家长 AI 中心语音输入是否可用。家长使用自己配置的 BYOK，不受孩子语音授权开关影响。
    var isParentVoiceTranscriptionReady: Bool {
        guard let config, hasKey else { return false }
        return config.kind.supportsAudioTranscription
    }

    /// 转写一段孩子的语音证明：完成所有门禁检查后调用转写客户端。
    /// 成功后立即删除本机音频文件（无论调用方是否记得删）。
    func transcribeChildProofAudio(
        at audioFileURL: URL,
        using client: any AudioTranscribing
    ) async throws -> String {
        if let config, hasKey, allowsChildVoiceTranscription {
            guard config.kind.supportsAudioTranscription else {
                throw AudioTranscriptionError.providerUnsupported
            }
            guard let apiKey = keyStore.loadKey(for: config.kind) else {
                throw AudioTranscriptionError.notConfigured
            }
            let text = try await client.transcribe(audioFileURL: audioFileURL, config: config, apiKey: apiKey)
            try? FileManager.default.removeItem(at: audioFileURL)
            return text
        }
        guard let familyCloud, familyCloud.isChildAIVoiceRelayReady else {
            throw AudioTranscriptionError.notConfigured
        }
        return try await familyCloud.transcribeChildAIAudio(at: audioFileURL)
    }

    /// 转写家长在 AI 中心录入的语音。音频仍只落 tmp，完成后立即删除。
    func transcribeParentAIAudio(
        at audioFileURL: URL,
        using client: any AudioTranscribing
    ) async throws -> String {
        guard let config, hasKey else { throw AudioTranscriptionError.notConfigured }
        guard config.kind.supportsAudioTranscription else {
            throw AudioTranscriptionError.providerUnsupported
        }
        guard let apiKey = keyStore.loadKey(for: config.kind) else {
            throw AudioTranscriptionError.notConfigured
        }

        let text = try await client.transcribe(audioFileURL: audioFileURL, config: config, apiKey: apiKey)
        try? FileManager.default.removeItem(at: audioFileURL)
        return text
    }

    /// 家长侧 AI 副驾是否可用：已配置 + 有密钥 + 服务商支持 OpenAI 形态聊天。
    /// Claude 走自家协议，第一版聊天副驾暂不支持（UI 显示降级提示）。
    var isReadyForAIComposer: Bool {
        guard let config, hasKey else { return false }
        return config.resolvedOpenAIStyleBaseURL != nil
    }

    /// AI 副驾聊天通道：完成门禁检查后调用聊天客户端，返回 JSON 草稿文本。
    /// 只发送最小信息（书名/年龄/主题），产出仅是草稿，家长确认才落地。
    func completeDraftJSON(
        system: String,
        user: String,
        using client: any AIChatCompleting
    ) async throws -> String {
        guard let config, hasKey else { throw AIChatError.notConfigured }
        guard config.resolvedOpenAIStyleBaseURL != nil else { throw AIChatError.providerUnsupported }
        guard let apiKey = keyStore.loadKey(for: config.kind) else { throw AIChatError.notConfigured }
        return try await client.complete(system: system, user: user, config: config, apiKey: apiKey)
    }

    /// 家长 AI 中心的多模态聊天通道。图片来自家长主动选择或拍摄，不复用孩子图片授权开关。
    func completeParentMultimodalChat(
        system: String,
        user: String,
        imageAttachments: [AICompanionImageAttachment],
        using client: any AICompanionChatCompleting = OpenAIStyleCompanionChatClient()
    ) async throws -> String {
        guard let config, hasKey else { throw AIChatError.notConfigured }
        guard config.resolvedOpenAIStyleBaseURL != nil else { throw AIChatError.providerUnsupported }
        guard let apiKey = keyStore.loadKey(for: config.kind) else { throw AIChatError.notConfigured }
        return try await client.complete(
            system: system,
            user: user,
            imageAttachments: imageAttachments,
            config: config,
            apiKey: apiKey
        )
    }

    /// 孩子阅读器的中英双语辅助。
    ///
    /// 复用 AI 小伙伴的家长 BYOK + 显式授权门禁；只发送当前页的书籍段落和年龄，
    /// 不发送孩子姓名、聊天记录、成长记忆、任务状态或阅读进度。
    func translateReadingPage(
        paragraphs: [String],
        childAge: Int,
        targetLanguage: FamilyLanguage,
        using client: any AIChatCompleting
    ) async throws -> [ReadingBilingualParagraph] {
        let cleaned = Array(paragraphs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(AIReadingTranslator.maxParagraphsPerPage))
        guard !cleaned.isEmpty else { throw AIChatError.badResponse }
        guard let config, hasKey, allowsChildAICompanionGuidance else {
            throw AIChatError.notConfigured
        }
        guard config.resolvedOpenAIStyleBaseURL != nil else { throw AIChatError.providerUnsupported }
        guard let apiKey = keyStore.loadKey(for: config.kind) else { throw AIChatError.notConfigured }

        let raw = try await client.complete(
            system: AIReadingTranslator.systemPrompt(childAge: childAge, targetLanguage: targetLanguage),
            user: AIReadingTranslator.userPrompt(paragraphs: cleaned),
            config: config,
            apiKey: apiKey
        )
        let result = AIReadingTranslator.parse(raw, originalParagraphs: cleaned)
        guard !result.isEmpty else { throw AIChatError.badResponse }
        guard !MobileSyncPayloadGuard.isUnsafe(result.map(\.translation)) else {
            throw AIChatError.badResponse
        }
        return result
    }

    /// 孩子端 AI 小伙伴云端引导是否可用：家长 BYOK 已配置 + 有密钥 + OpenAI 形态聊天 + 家长显式开启。
    ///
    /// UI 只能通过下面的 `guideChildAICompanion` 进入云端路径，不能直接读取 Keychain。
    var isReadyForChildAICompanion: Bool {
        isLocalChildAICompanionReady || familyCloud?.isChildAIRelayReady == true
    }

    var isReadyForChildAICompanionImages: Bool {
        (isLocalChildAICompanionReady && allowsChildAICompanionImageUpload)
            || familyCloud?.isChildAIImageRelayReady == true
    }

    private var isLocalChildAICompanionReady: Bool {
        isReadyForAIComposer && allowsChildAICompanionGuidance
    }

    /// 只供已认证的家长设备上传到家庭 AI 中继。服务端立即 AES-GCM 加密，孩子设备只获能力标记。
    /// 自定义 URL 与 Claude 协议不允许进入中继，避免服务端 SSRF 或协议误配。
    var familyAIProviderProvisioning: FamilyAIProviderProvisioning? {
        guard let config, hasKey,
              config.kind != .openAICompatible,
              config.kind != .anthropicClaude,
              let apiKey = keyStore.loadKey(for: config.kind) else { return nil }
        return FamilyAIProviderProvisioning(
            providerKind: config.kind.rawValue,
            modelName: config.resolvedModelName,
            apiKey: apiKey,
            guidanceEnabled: allowsChildAICompanionGuidance,
            imageUploadEnabled: allowsChildAICompanionImageUpload,
            voiceEnabled: allowsChildVoiceTranscription
        )
    }

    /// AI 小伙伴云端引导通道。
    ///
    /// 只接收 `AICompanionPrivacyGateway` 已放行的脱敏草稿；密钥由 Store 内部取出并传给服务层，
    /// 不返回、不打印、不保存。服务层会二次检查云端响应，不安全则 fail-closed。
    func guideChildAICompanion(
        draft: AICompanionCloudRequestDraft,
        using service: AICompanionCloudGuideService = AICompanionCloudGuideService()
    ) async throws -> AICompanionCloudGuide {
        guard draft.isProviderRequestAllowed else {
            throw AICompanionCloudGuideError.blockedByPrivacyGateway(draft.blockReason ?? "blocked")
        }
        guard let config, hasKey, allowsChildAICompanionGuidance else {
            throw AICompanionCloudGuideError.notConfigured
        }
        guard config.resolvedOpenAIStyleBaseURL != nil else {
            throw AICompanionCloudGuideError.providerUnsupported
        }
        guard let apiKey = keyStore.loadKey(for: config.kind) else {
            throw AICompanionCloudGuideError.notConfigured
        }
        return try await service.guide(draft: draft, config: config, apiKey: apiKey)
    }

    /// AI 小伙伴真实聊天通道。
    ///
    /// 与 `guideChildAICompanion` 共用家长 BYOK + 显式授权门禁；只发送服务请求中已经裁剪的
    /// 当前一句、人格设置和本地记忆摘要。高风险或隐私网关不放行时不会读取 Keychain。
    func chatChildAICompanion(
        request: AICompanionChatRequest,
        using service: AICompanionChatService = AICompanionChatService()
    ) async throws -> AICompanionChatTurn {
        guard request.isProviderRequestAllowed else {
            throw AICompanionChatServiceError.blockedBySafetyGate
        }
        guard !request.containsImages || isReadyForChildAICompanionImages else {
            throw AICompanionChatServiceError.imageUploadNotAllowed
        }
        if isLocalChildAICompanionReady,
           let config,
           let apiKey = keyStore.loadKey(for: config.kind) {
            return try await service.chat(request: request, config: config, apiKey: apiKey)
        }
        if let familyCloud, familyCloud.isChildAIRelayReady {
            return try await familyCloud.chatChildAICompanion(request: request, using: service)
        }
        throw AICompanionChatServiceError.notConfigured
    }

    /// 云端真人语音是否可用（OpenAI 形态服务 + 有密钥）。
    var isCloudVoiceCapable: Bool {
        guard let config, hasKey else { return false }
        return config.resolvedOpenAIStyleBaseURL != nil
    }

    /// 合成一段语音（mp3）。门禁同其它 BYOK 调用；只发送朗读文字本身。
    /// languageHint 是当前孩子界面语言（en-US / zh-CN 提示），不含任何家庭数据。
    func synthesizeSpeech(
        _ text: String,
        voiceStyle: AICompanionVoiceStyle? = nil,
        languageHint: AppInterfaceLanguage? = nil,
        using client: OpenAISpeechClient = OpenAISpeechClient()
    ) async throws -> Data {
        guard let config, hasKey else { throw AIChatError.notConfigured }
        guard config.resolvedOpenAIStyleBaseURL != nil else { throw AIChatError.providerUnsupported }
        guard let apiKey = keyStore.loadKey(for: config.kind) else { throw AIChatError.notConfigured }
        return try await client.synthesize(
            text: text,
            config: config,
            apiKey: apiKey,
            voiceStyle: voiceStyle,
            languageHint: languageHint.map { SpeechReader.voiceLanguageCode(for: $0) }
        )
    }

    /// 测试当前已保存配置的连通性（地址通 + 密钥有效）。
    /// 只发只读的 models 列表请求，不发送任何家庭或孩子数据。
    func testCurrentConnection(
        using tester: AIProviderConnectionTester = AIProviderConnectionTester()
    ) async -> AIProviderConnectionResult {
        guard let config, let apiKey = keyStore.loadKey(for: config.kind) else {
            return .notConfigured
        }
        return await tester.test(config: config, apiKey: apiKey)
    }

    private func persistConfig(_ config: AIProviderConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults?.set(data, forKey: Self.configKey)
    }
}
