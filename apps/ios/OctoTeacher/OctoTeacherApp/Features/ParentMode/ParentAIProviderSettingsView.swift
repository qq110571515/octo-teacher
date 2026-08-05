import SwiftUI

enum ParentAICompanionImageConsentCopy {
    static func providerUnsupported(_ language: AppInterfaceLanguage) -> String {
        language.pick(
            "当前服务商不支持 OpenAI 形态聊天，孩子 AI 小伙伴会保持本地引导。",
            "This provider does not support OpenAI-compatible chat, so the child's AI companion will continue with local guidance."
        )
    }

    static func disabledUntilGuidance(_ language: AppInterfaceLanguage) -> String {
        language.pick(
            "先开启云端引导并保存可用密钥，才可以单独允许图片。图片权限默认关闭。",
            "Enable cloud guidance and save a working API key before allowing images. Image access is off by default."
        )
    }

    static func modelRequirement(_ language: AppInterfaceLanguage) -> String {
        language.pick(
            "看图需要你选择的模型支持图片/视觉输入；如果模型只能处理文字，小伙伴会降级为只读孩子写下的文字说明。",
            "Image understanding requires a model with vision support. Text-only models will use only the child's written description."
        )
    }

    static func privacyBoundary(_ language: AppInterfaceLanguage) -> String {
        language.pick(
            "图片开关只影响孩子 AI 小伙伴聊天。开启后，照片会先压缩去元数据，只用于本次对话发给你选择的 AI 服务商；章鱼老师本地长期记忆只保存文字摘要，不保存原图。第三方数据使用规则以家长选择的服务商为准。",
            "This setting applies only to the child's AI companion chat. Images are compressed, stripped of metadata, and sent to your selected AI provider only for the current conversation. Octo Teacher stores only a text summary in long-term memory, never the original image. Your provider's data policy also applies."
        )
    }

    static func readyFooter(_ language: AppInterfaceLanguage) -> String {
        "\(modelRequirement(language))\n\(privacyBoundary(language))\n\(language.pick("默认关闭；家长可随时关掉。", "Off by default; parents can turn it off at any time."))"
    }
}

enum ParentAIProviderSettingsCopy {
    static func providerLabel(_ kind: AIProviderKind, language: AppInterfaceLanguage) -> String {
        switch kind {
        case .anthropicClaude: return "Claude (Anthropic)"
        case .openAI: return "OpenAI (ChatGPT)"
        case .googleGemini: return "Gemini (Google)"
        case .deepSeek: return language.pick("DeepSeek（深度求索）", "DeepSeek")
        case .moonshotKimi: return language.pick("Kimi（月之暗面）", "Kimi (Moonshot AI)")
        case .alibabaQwen: return language.pick("通义千问（阿里云）", "Qwen (Alibaba Cloud)")
        case .openAICompatible: return language.pick("自定义（OpenAI 兼容）", "Custom (OpenAI-compatible)")
        }
    }

    static func providerBlurb(_ kind: AIProviderKind, language: AppInterfaceLanguage) -> String {
        switch kind {
        case .anthropicClaude:
            return language.pick("答疑和引导质量高；暂不支持语音转写。", "Strong guidance quality; voice transcription is not currently supported.")
        case .openAI:
            return language.pick("通用能力强，且支持 Whisper 语音转写。", "Strong general capabilities with Whisper voice transcription support.")
        case .googleGemini:
            return language.pick("有免费额度，适合先试用。", "A free tier makes it easy to try.")
        case .deepSeek:
            return language.pick("价格便宜，中文能力好。", "Affordable with strong Chinese-language support.")
        case .moonshotKimi:
            return language.pick("长文本能力强，国内访问稳定。", "Strong long-context support and reliable access in China.")
        case .alibabaQwen:
            return language.pick("阿里云百炼平台，国内访问稳定。", "Available through Alibaba Cloud Model Studio with reliable access in China.")
        case .openAICompatible:
            return language.pick("本地模型或其他兼容网关，自己填服务地址。", "Use a local model or another compatible gateway by entering its service URL.")
        }
    }

    static func connectionMessage(_ result: AIProviderConnectionResult, language: AppInterfaceLanguage) -> String {
        switch result {
        case .ok:
            return language.pick("连接成功，密钥可用。", "Connection successful. The API key is working.")
        case .notConfigured:
            return language.pick("先保存服务商和密钥，再测试连接。", "Save a provider and API key before testing the connection.")
        case .unauthorized:
            return language.pick("密钥无效或没有权限，请检查后重试。", "The API key is invalid or lacks permission. Check it and try again.")
        case .failed(let statusCode):
            return language.pick("服务返回错误（\(statusCode)），稍后再试。", "The service returned error \(statusCode). Try again later.")
        case .unreachable:
            return language.pick("连不上服务，请检查网络或服务地址。", "The service could not be reached. Check the network and service URL.")
        }
    }
}

/// 家长 AI 助手设置（BYOK）。
///
/// 家长从常用大模型目录里选一家，然后用自己的密钥连接；密钥只存本机 Keychain。
/// 订阅账号登录（ChatGPT Plus / Claude Pro 等）目前各厂商都未对第三方 App 开放
/// 官方接口，架构已预留，厂商开放后即可接入；当前统一走 API 密钥。
struct ParentAIProviderSettingsView: View {
    @Environment(ParentAIProviderStore.self) private var store
    @Environment(LocalFamilyStore.self) private var family

    @State private var kind: AIProviderKind = .openAI
    @State private var baseURLString = ""
    @State private var modelName = ""
    @State private var keyInput = ""
    @State private var feedback: String?
    @State private var isTestingConnection = false

    var body: some View {
        Form {
            statusSection
            providerSection
            credentialSection
            voiceSection
            companionSection
            actionSection
        }
        .navigationTitle(lang.pick("AI 助手设置", "AI Assistant Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: syncFromStore)
    }

    // MARK: - 分区

    private var statusSection: some View {
        Section {
            if store.isReadyForDrafting, let config = store.config {
                Label(lang.pick("已连接 \(providerLabel(config.kind))", "Connected to \(providerLabel(config.kind))"), systemImage: "checkmark.seal")
                    .foregroundStyle(.green)
                if !config.modelName.isEmpty {
                    Text(lang.pick("模型：\(config.modelName)", "Model: \(config.modelName)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label(lang.pick("未配置 AI 助手", "AI assistant is not configured"), systemImage: "sparkles")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(lang.pick("当前状态", "Status"))
        } footer: {
            Text(lang.pick(
                "不配置也完全可以使用：所有任务验证会走家长人工确认。配置后 AI 只做初评摘要，最终批准权始终在家长。",
                "The app works without AI: parents review every task manually. When configured, AI provides only an initial summary; final approval always belongs to the parent."
            ))
        }
    }

    private var providerSection: some View {
        Section {
            Picker(lang.pick("服务商", "Provider"), selection: $kind) {
                ForEach(AIProviderKind.allCases) { item in
                    Text(providerLabel(item)).tag(item)
                }
            }
            .accessibilityIdentifier("ai-provider-kind")
            .onChange(of: kind) { _, _ in
                modelName = ""
                baseURLString = ""
                feedback = nil
            }

            Text(ParentAIProviderSettingsCopy.providerBlurb(kind, language: lang))
                .font(.caption)
                .foregroundStyle(.secondary)

            if kind.needsBaseURL {
                TextField(lang.pick("服务地址，例如 http://192.168.1.10:8000/v1", "Service URL, for example http://192.168.1.10:8000/v1"), text: $baseURLString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("ai-provider-base-url")
            }
        } header: {
            Text(lang.pick("选择大模型", "Choose a model provider"))
        } footer: {
            Text(lang.pick(
                "订阅账号登录（如 ChatGPT Plus、Claude Pro）目前各厂商都没有对第三方 App 开放，暂时只能用 API 密钥；厂商开放后这里会直接支持登录。",
                "Providers do not currently offer third-party sign-in for subscriptions such as ChatGPT Plus or Claude Pro, so an API key is required. Direct sign-in can be added when providers support it."
            ))
        }
    }

    private var credentialSection: some View {
        Section {
            if let url = URL(string: kind.keyConsoleURLString), !kind.keyConsoleURLString.isEmpty {
                Link(destination: url) {
                    Label(lang.pick("去 \(providerLabel(kind)) 官网获取密钥", "Get an API key from \(providerLabel(kind))"), systemImage: "safari")
                }
                .accessibilityIdentifier("ai-provider-key-console")
            }

            SecureField(lang.pick("粘贴 API 密钥（只存本机 Keychain）", "Paste API key (stored only in this device's Keychain)"), text: $keyInput)
                .accessibilityIdentifier("ai-provider-key")

            TextField(
                lang.pick(
                    "模型名（留空用默认：\(kind.defaultModelName.isEmpty ? "无" : kind.defaultModelName)）",
                    "Model name (leave blank for default: \(kind.defaultModelName.isEmpty ? "none" : kind.defaultModelName))"
                ),
                text: $modelName
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } header: {
            Text(lang.pick("密钥", "API key"))
        } footer: {
            Text(lang.pick(
                "密钥先保存在这台手机的系统 Keychain。启用家庭云和孩子 AI 后，会经加密连接写入家庭专属 AI 中继；孩子手机只能使用 AI 能力，不能读取密钥。密钥不会进入任务、聊天记忆或日志。",
                "The key is first stored in this phone's system Keychain. When Family Cloud and child AI are enabled, it is sent through an encrypted connection to the family's private AI relay. Child devices can use AI but cannot read the key. The key never appears in tasks, chat memory, or logs."
            ))
        }
    }

    private var voiceSection: some View {
        Section {
            Toggle(
                lang.pick("允许孩子语音转写", "Allow child voice transcription"),
                isOn: Binding(
                    get: { store.allowsChildVoiceTranscription },
                    set: { store.setChildVoiceTranscription(allowed: $0) }
                )
            )
            .disabled(!(store.config?.kind.supportsAudioTranscription ?? false) || !store.hasKey)
            .accessibilityIdentifier("ai-provider-voice-consent")
        } header: {
            Text(lang.pick("孩子语音转写", "Child voice transcription"))
        } footer: {
            if let configured = store.config?.kind, !configured.supportsAudioTranscription {
                Text(lang.pick(
                    "\(providerLabel(configured)) 不支持语音转写。想让孩子用语音，请选 OpenAI 或自定义 OpenAI 兼容服务。",
                    "\(providerLabel(configured)) does not support voice transcription. Choose OpenAI or a custom OpenAI-compatible service to enable voice input."
                ))
            } else {
                Text(lang.pick(
                    "开启后，孩子可以对着手机说一说完成情况，录音会发给你选择的 AI 服务商转成文字，转写完成后录音立即删除。默认关闭。",
                    "When enabled, the child can describe progress by voice. Audio is sent to your selected AI provider for transcription and deleted immediately afterward. Off by default."
                ))
            }
        }
    }

    private var companionSection: some View {
        Section {
            Toggle(
                lang.pick("允许孩子 AI 小伙伴使用云端引导", "Allow cloud guidance for the child's AI companion"),
                isOn: Binding(
                    get: { store.allowsChildAICompanionGuidance },
                    set: { store.setChildAICompanionGuidance(allowed: $0) }
                )
            )
            .disabled(store.config?.resolvedOpenAIStyleBaseURL == nil || !store.hasKey)
            .accessibilityIdentifier("ai-provider-companion-guidance-consent")

            Toggle(
                lang.pick("允许 AI 小伙伴看孩子发的图片", "Allow the AI companion to view images sent by the child"),
                isOn: Binding(
                    get: { store.allowsChildAICompanionImageUpload },
                    set: { store.setChildAICompanionImageUpload(allowed: $0) }
                )
            )
            .disabled(!store.isReadyForChildAICompanion)
            .accessibilityIdentifier("ai-provider-companion-image-consent")

            if store.isReadyForChildAICompanion {
                Label(lang.pick("看图需要视觉模型", "Images require a vision-capable model"), systemImage: "eye")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ai-provider-companion-vision-requirement")
                Label(lang.pick("照片只用于本次对话", "Images are used only for this conversation"), systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ai-provider-companion-image-privacy")
            }
        } header: {
            Text(lang.pick("AI 小伙伴", "AI Companion"))
        } footer: {
            if store.config?.resolvedOpenAIStyleBaseURL == nil, store.config != nil {
                Text(ParentAICompanionImageConsentCopy.providerUnsupported(lang))
            } else if !store.isReadyForChildAICompanion {
                Text(ParentAICompanionImageConsentCopy.disabledUntilGuidance(lang))
            } else {
                Text(ParentAICompanionImageConsentCopy.readyFooter(lang))
            }
        }
    }

    private var actionSection: some View {
        Section {
            Button(lang.pick("保存配置", "Save Configuration")) {
                save()
            }
            .disabled(!canSave)
            .accessibilityIdentifier("ai-provider-save")

            if store.config != nil {
                Button {
                    Task { await testConnection() }
                } label: {
                    if isTestingConnection {
                        Label(lang.pick("正在测试……", "Testing..."), systemImage: "antenna.radiowaves.left.and.right")
                    } else {
                        Label(lang.pick("测试连接", "Test Connection"), systemImage: "bolt.horizontal")
                    }
                }
                .disabled(isTestingConnection)
                .accessibilityIdentifier("ai-provider-test-connection")

                Button(lang.pick("断开并删除密钥", "Disconnect and Delete Key"), role: .destructive) {
                    store.disconnect()
                    feedback = lang.pick("已删除密钥并断开。", "The key was deleted and the provider was disconnected.")
                }
                .accessibilityIdentifier("ai-provider-disconnect")
            }
        } footer: {
            if let feedback {
                Text(feedback)
            }
        }
    }

    // MARK: - 动作

    private var canSave: Bool {
        let hasNewKey = !keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let keepsExistingKey = store.hasKey && store.config?.kind == kind
        let baseOK = !kind.needsBaseURL || !baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return baseOK && (hasNewKey || keepsExistingKey)
    }

    private var lang: AppInterfaceLanguage {
        family.settings.resolvedParentInterfaceLanguage
    }

    private func providerLabel(_ kind: AIProviderKind) -> String {
        ParentAIProviderSettingsCopy.providerLabel(kind, language: lang)
    }

    private func save() {
        let resolvedModel = modelName.isEmpty ? kind.defaultModelName : modelName
        if store.apply(kind: kind, baseURLString: baseURLString, modelName: resolvedModel, key: keyInput) {
            keyInput = ""
            feedback = lang.pick("已保存。可以点「测试连接」确认密钥可用。", "Saved. Use Test Connection to verify the API key.")
        } else {
            feedback = lang.pick("保存失败：请检查服务地址和密钥。", "Could not save. Check the service URL and API key.")
        }
    }

    private func testConnection() async {
        isTestingConnection = true
        defer { isTestingConnection = false }
        let result = await store.testCurrentConnection()
        feedback = ParentAIProviderSettingsCopy.connectionMessage(result, language: lang)
    }

    private func syncFromStore() {
        guard let config = store.config else { return }
        kind = config.kind
        baseURLString = config.baseURLString
        modelName = config.modelName
    }
}
