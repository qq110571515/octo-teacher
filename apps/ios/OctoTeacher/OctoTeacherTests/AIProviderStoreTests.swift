import XCTest
@testable import OctoTeacher

/// 家长 BYOK AI 服务商配置与验证初评 Mock 的回归测试（成长包平台化阶段 2 脚手架）。
@MainActor
final class AIProviderStoreTests: XCTestCase {
    func testOpenAIHumanProductAliasMigratesToCallableModelID() {
        let config = AIProviderConfig(kind: .openAI, baseURLString: "", modelName: "Chatgpt")
        XCTAssertEqual(config.resolvedModelName, "gpt-4o-mini")
        XCTAssertEqual(config.normalizedForPersistence.modelName, "gpt-4o-mini")
    }


    nonisolated(unsafe) private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: "test.octoteacher.aiprovider")
        testDefaults.removePersistentDomain(forName: "test.octoteacher.aiprovider")
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: "test.octoteacher.aiprovider")
        super.tearDown()
    }

    // MARK: - 密钥存取端口

    func testInMemoryKeyStoreRoundTrip() {
        let store = InMemoryAIProviderKeyStore()
        XCTAssertFalse(store.hasKey(for: .openAI))

        XCTAssertTrue(store.saveKey("sk-test-123", for: .openAI))
        XCTAssertEqual(store.loadKey(for: .openAI), "sk-test-123")
        XCTAssertTrue(store.hasKey(for: .openAI))

        store.deleteKey(for: .openAI)
        XCTAssertNil(store.loadKey(for: .openAI))
    }

    func testKeyStoreRejectsEmptyKey() {
        let store = InMemoryAIProviderKeyStore()
        XCTAssertFalse(store.saveKey("   ", for: .anthropicClaude))
        XCTAssertFalse(store.hasKey(for: .anthropicClaude))
    }

    // MARK: - 配置 Store

    func testApplySavesConfigAndKeySeparately() {
        let keyStore = InMemoryAIProviderKeyStore()
        let store = ParentAIProviderStore(keyStore: keyStore, defaults: testDefaults)

        XCTAssertTrue(
            store.apply(kind: .anthropicClaude, baseURLString: "", modelName: "claude-haiku-4-5-20251001", key: "sk-ant-xxx")
        )
        XCTAssertTrue(store.isReadyForDrafting)
        XCTAssertEqual(store.config?.kind, .anthropicClaude)

        // 非敏感配置落 UserDefaults，但密钥绝不出现在其中。
        let raw = testDefaults.data(forKey: "octoteacher.aiprovider.config")
        let rawString = String(data: raw ?? Data(), encoding: .utf8) ?? ""
        XCTAssertFalse(rawString.contains("sk-ant-xxx"), "密钥泄露进了 UserDefaults 配置")
        XCTAssertEqual(keyStore.loadKey(for: .anthropicClaude), "sk-ant-xxx")
    }

    func testCustomProviderRequiresBaseURL() {
        let store = ParentAIProviderStore(keyStore: InMemoryAIProviderKeyStore(), defaults: testDefaults)
        XCTAssertFalse(store.apply(kind: .openAICompatible, baseURLString: "  ", modelName: "qwen", key: "k"))
        XCTAssertFalse(store.isReadyForDrafting)

        XCTAssertTrue(
            store.apply(kind: .openAICompatible, baseURLString: "http://local-model-host:8000/v1", modelName: "qwen", key: "k")
        )
        XCTAssertTrue(store.isReadyForDrafting)
    }

    func testApplyWithEmptyKeyKeepsExistingKey() {
        let keyStore = InMemoryAIProviderKeyStore()
        let store = ParentAIProviderStore(keyStore: keyStore, defaults: testDefaults)

        XCTAssertTrue(store.apply(kind: .openAI, baseURLString: "", modelName: "gpt-4o-mini", key: "sk-1"))
        // 只改模型名，不重填密钥。
        XCTAssertTrue(store.apply(kind: .openAI, baseURLString: "", modelName: "gpt-4o", key: ""))
        XCTAssertEqual(store.config?.modelName, "gpt-4o")
        XCTAssertEqual(keyStore.loadKey(for: .openAI), "sk-1")
        XCTAssertTrue(store.isReadyForDrafting)
    }

    func testDisconnectDeletesKeyAndConfig() {
        let keyStore = InMemoryAIProviderKeyStore()
        let store = ParentAIProviderStore(keyStore: keyStore, defaults: testDefaults)
        store.apply(kind: .openAI, baseURLString: "", modelName: "", key: "sk-1")

        store.disconnect()
        XCTAssertNil(store.config)
        XCTAssertFalse(store.isReadyForDrafting)
        XCTAssertNil(keyStore.loadKey(for: .openAI))
        XCTAssertNil(testDefaults.data(forKey: "octoteacher.aiprovider.config"))
    }

    func testConfigRestoresAcrossStoreInstances() {
        let keyStore = InMemoryAIProviderKeyStore()
        let first = ParentAIProviderStore(keyStore: keyStore, defaults: testDefaults)
        first.apply(kind: .openAI, baseURLString: "", modelName: "gpt-4o-mini", key: "sk-1")

        // 模拟 App 重启：新实例从 UserDefaults + keyStore 恢复。
        let second = ParentAIProviderStore(keyStore: keyStore, defaults: testDefaults)
        XCTAssertEqual(second.config?.kind, .openAI)
        XCTAssertTrue(second.isReadyForDrafting)
    }

    // MARK: - Mock 初评器

    private func readingTask() -> TaskTemplate {
        TaskTemplate(
            id: UUID(),
            title: "读《夏洛的网》",
            category: .learning,
            difficulty: .easy,
            rewardMinutes: 20,
            instructions: "读完说说学到了什么。",
            requiredProof: .text,
            reading: ReadingSpec(bookTitle: "夏洛的网", minMinutes: 30, chapterPlanText: "第 1-2 章")
        )
    }

    func testEmptyChildTextNeedsParentJudgment() {
        let draft = MockAIVerificationDrafter().draftReview(task: readingTask(), childText: "  ", minConfidence: 0.6)
        XCTAssertEqual(draft.confidence, 0)
        XCTAssertEqual(draft.recommendation, .needsParentJudgment)
    }

    func testDetailedRetellingWithBookTitleSuggestsApprove() {
        let text = "我今天读了夏洛的网的第一章和第二章，小猪威尔伯差点被杀掉，芬救了它，我觉得芬很勇敢。"
        let draft = MockAIVerificationDrafter().draftReview(task: readingTask(), childText: text, minConfidence: 0.6)
        XCTAssertGreaterThanOrEqual(draft.confidence, 0.6)
        XCTAssertEqual(draft.recommendation, .suggestApprove)
    }

    func testShortAnswerStaysWithParent() {
        let draft = MockAIVerificationDrafter().draftReview(task: readingTask(), childText: "读完了", minConfidence: 0.6)
        XCTAssertLessThan(draft.confidence, 0.6)
        XCTAssertEqual(draft.recommendation, .needsParentJudgment)
    }

    func testConfidenceIsCappedBelowCertainty() {
        let text = String(repeating: "夏洛的网第 1-2 章讲了很多细节。", count: 10)
        let draft = MockAIVerificationDrafter().draftReview(task: readingTask(), childText: text, minConfidence: 0.6)
        XCTAssertLessThanOrEqual(draft.confidence, 0.85, "初评置信度必须留出人工空间，不能到 1")
    }

    func testDrafterIsDeterministic() {
        let text = "我读了夏洛的网，学到了友谊的重要。"
        let first = MockAIVerificationDrafter().draftReview(task: readingTask(), childText: text, minConfidence: 0.6)
        let second = MockAIVerificationDrafter().draftReview(task: readingTask(), childText: text, minConfidence: 0.6)
        XCTAssertEqual(first, second)
    }

    // MARK: - 云端语音转写：能力与门禁

    func testTranscriptionCapabilityFlags() {
        XCTAssertFalse(AIProviderKind.anthropicClaude.supportsAudioTranscription)
        XCTAssertTrue(AIProviderKind.openAI.supportsAudioTranscription)
        XCTAssertTrue(AIProviderKind.openAICompatible.supportsAudioTranscription)
        XCTAssertEqual(AIProviderKind.openAI.defaultTranscriptionModelName, "whisper-1")
    }

    func testResolvedBaseURL() {
        let openAI = AIProviderConfig(kind: .openAI, baseURLString: "", modelName: "")
        XCTAssertEqual(openAI.resolvedOpenAIStyleBaseURL?.absoluteString, "https://api.openai.com/v1")

        let custom = AIProviderConfig(kind: .openAICompatible, baseURLString: "http://local-model-host:8000/v1/", modelName: "")
        XCTAssertEqual(custom.resolvedOpenAIStyleBaseURL?.absoluteString, "http://local-model-host:8000/v1")

        let claude = AIProviderConfig(kind: .anthropicClaude, baseURLString: "", modelName: "")
        XCTAssertNil(claude.resolvedOpenAIStyleBaseURL)
    }

    func testVoiceConsentDefaultsOffAndPersists() {
        let keyStore = InMemoryAIProviderKeyStore()
        let store = ParentAIProviderStore(keyStore: keyStore, defaults: testDefaults)
        XCTAssertFalse(store.allowsChildVoiceTranscription)

        store.setChildVoiceTranscription(allowed: true)
        let restored = ParentAIProviderStore(keyStore: keyStore, defaults: testDefaults)
        XCTAssertTrue(restored.allowsChildVoiceTranscription)
    }

    func testAICompanionImageUploadConsentDefaultsOffAndPersists() {
        let keyStore = InMemoryAIProviderKeyStore()
        let store = ParentAIProviderStore(keyStore: keyStore, defaults: testDefaults)
        XCTAssertFalse(store.allowsChildAICompanionImageUpload)

        store.setChildAICompanionImageUpload(allowed: true)
        let restored = ParentAIProviderStore(keyStore: keyStore, defaults: testDefaults)
        XCTAssertTrue(restored.allowsChildAICompanionImageUpload)
    }

    func testAICompanionImageConsentCopyExplainsVisionModelAndMemoryBoundary() {
        let ready = ParentAICompanionImageConsentCopy.readyFooter(.chinese)

        XCTAssertTrue(ready.contains("AI 小伙伴"))
        XCTAssertTrue(ready.contains("图片"))
        XCTAssertTrue(ready.contains("视觉"))
        XCTAssertTrue(ready.contains("模型"))
        XCTAssertTrue(ready.contains("本次对话"))
        XCTAssertTrue(ready.contains("长期记忆"))
        XCTAssertTrue(ready.contains("文字摘要"))
        XCTAssertTrue(ready.contains("服务商"))
        XCTAssertTrue(ready.contains("默认关闭"))
        XCTAssertTrue(ParentAICompanionImageConsentCopy.disabledUntilGuidance(.chinese).contains("单独允许图片"))
    }

    func testVoiceReadinessRequiresProviderSupportAndConsent() {
        let keyStore = InMemoryAIProviderKeyStore()
        let store = ParentAIProviderStore(keyStore: keyStore, defaults: testDefaults)

        // Claude：即使开了开关也不可用。
        store.apply(kind: .anthropicClaude, baseURLString: "", modelName: "", key: "sk-1")
        store.setChildVoiceTranscription(allowed: true)
        XCTAssertFalse(store.isVoiceTranscriptionReady)

        // OpenAI + 密钥 + 开关：可用。
        store.apply(kind: .openAI, baseURLString: "", modelName: "", key: "sk-2")
        XCTAssertTrue(store.isVoiceTranscriptionReady)

        // 关掉开关立即不可用。
        store.setChildVoiceTranscription(allowed: false)
        XCTAssertFalse(store.isVoiceTranscriptionReady)
    }

    func testAICompanionImageUploadRequiresSeparateConsent() async throws {
        let keyStore = InMemoryAIProviderKeyStore()
        let store = ParentAIProviderStore(keyStore: keyStore, defaults: testDefaults)
        store.apply(kind: .openAI, baseURLString: "", modelName: "gpt-test", key: "sk-1")
        store.setChildAICompanionGuidance(allowed: true)

        let image = AICompanionImageAttachment(
            source: .camera,
            mimeType: "image/jpeg",
            data: Data("image".utf8),
            localSummary: "孩子拍了一张照片并授权小伙伴查看。"
        )
        let request = AICompanionChatRequest(
            childAge: 8,
            mode: .nextStep,
            latestText: "看看这张图",
            latestIntent: .offTopic,
            companionName: "小云",
            companionVoice: .warm,
            companionPersonality: .gentleGuide,
            avatarDescription: "星星",
            memory: AICompanionMemoryDigest.empty(
                childId: UUID(),
                companionName: "小云",
                companionAvatarDescription: "星星",
                personalityLabel: "耐心引导型"
            ),
            nextTaskTitle: nil,
            attachmentSummaries: [image.localSummary],
            imageAttachments: [image]
        )

        XCTAssertFalse(store.isReadyForChildAICompanionImages)
        do {
            _ = try await store.chatChildAICompanion(
                request: request,
                using: AICompanionChatService(
                    chatClient: StoreImageConsentSpyChatClient()
                )
            )
            XCTFail("图片权限未开启时必须阻断")
        } catch {
            XCTAssertEqual(error as? AICompanionChatServiceError, .imageUploadNotAllowed)
        }

        store.setChildAICompanionImageUpload(allowed: true)
        XCTAssertTrue(store.isReadyForChildAICompanionImages)
    }

    private func makeTempAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-audio-\(UUID().uuidString).m4a")
        try Data("fake-audio".utf8).write(to: url)
        return url
    }

    func testTranscribeDeletesAudioFileAfterSuccess() async throws {
        let keyStore = InMemoryAIProviderKeyStore()
        let store = ParentAIProviderStore(keyStore: keyStore, defaults: testDefaults)
        store.apply(kind: .openAI, baseURLString: "", modelName: "", key: "sk-1")
        store.setChildVoiceTranscription(allowed: true)

        let audioURL = try makeTempAudioFile()
        let text = try await store.transcribeChildProofAudio(
            at: audioURL,
            using: StubTranscriptionClient(result: .success("我今天读了两章书"))
        )
        XCTAssertEqual(text, "我今天读了两章书")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: audioURL.path),
            "转写成功后必须立即删除本机音频"
        )
    }

    func testTranscribeBlockedWithoutConsent() async throws {
        let keyStore = InMemoryAIProviderKeyStore()
        let store = ParentAIProviderStore(keyStore: keyStore, defaults: testDefaults)
        store.apply(kind: .openAI, baseURLString: "", modelName: "", key: "sk-1")
        // 未开启家长同意开关。
        let audioURL = try makeTempAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        do {
            _ = try await store.transcribeChildProofAudio(
                at: audioURL,
                using: StubTranscriptionClient(result: .success("不应该到这里"))
            )
            XCTFail("家长未同意时必须抛错")
        } catch let error as AudioTranscriptionError {
            XCTAssertEqual(error, .notConfigured)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path), "失败时不应删除音频")
    }

    func testTranscribeBlockedForClaudeProvider() async throws {
        let keyStore = InMemoryAIProviderKeyStore()
        let store = ParentAIProviderStore(keyStore: keyStore, defaults: testDefaults)
        store.apply(kind: .anthropicClaude, baseURLString: "", modelName: "", key: "sk-1")
        store.setChildVoiceTranscription(allowed: true)

        let audioURL = try makeTempAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        do {
            _ = try await store.transcribeChildProofAudio(
                at: audioURL,
                using: StubTranscriptionClient(result: .success("不应该到这里"))
            )
            XCTFail("Claude 不支持转写，必须抛错")
        } catch let error as AudioTranscriptionError {
            XCTAssertEqual(error, .providerUnsupported)
        }
    }

    // MARK: - 云端语音转写：真实客户端（URLProtocol 桩）

    private func stubbedClient() -> OpenAIStyleTranscriptionClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TranscriptionStubURLProtocol.self]
        return OpenAIStyleTranscriptionClient(session: URLSession(configuration: configuration))
    }

    func testClientParsesSuccessResponse() async throws {
        TranscriptionStubURLProtocol.stub = (200, #"{"text": "我把书桌整理好了"}"#)
        defer { TranscriptionStubURLProtocol.stub = nil }

        let audioURL = try makeTempAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let config = AIProviderConfig(kind: .openAI, baseURLString: "", modelName: "")
        let text = try await stubbedClient().transcribe(audioFileURL: audioURL, config: config, apiKey: "sk-test")
        XCTAssertEqual(text, "我把书桌整理好了")

        // 请求形态：POST /v1/audio/transcriptions + Bearer 头。
        let request = try XCTUnwrap(TranscriptionStubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/v1/audio/transcriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
    }

    func testClientThrowsOnAuthFailure() async throws {
        TranscriptionStubURLProtocol.stub = (401, #"{"error": "bad key"}"#)
        defer { TranscriptionStubURLProtocol.stub = nil }

        let audioURL = try makeTempAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let config = AIProviderConfig(kind: .openAI, baseURLString: "", modelName: "")
        do {
            _ = try await stubbedClient().transcribe(audioFileURL: audioURL, config: config, apiKey: "sk-bad")
            XCTFail("401 必须抛错")
        } catch let error as AudioTranscriptionError {
            XCTAssertEqual(error, .requestFailed(statusCode: 401))
        }
    }

    func testClientThrowsOnMalformedResponse() async throws {
        TranscriptionStubURLProtocol.stub = (200, "not-json")
        defer { TranscriptionStubURLProtocol.stub = nil }

        let audioURL = try makeTempAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let config = AIProviderConfig(kind: .openAI, baseURLString: "", modelName: "")
        do {
            _ = try await stubbedClient().transcribe(audioFileURL: audioURL, config: config, apiKey: "sk")
            XCTFail("坏响应必须抛错")
        } catch let error as AudioTranscriptionError {
            XCTAssertEqual(error, .badResponse)
        }
    }

    func testMultipartBodyContainsModelAndAudio() {
        let body = OpenAIStyleTranscriptionClient.multipartBody(
            boundary: "b",
            audioData: Data("audio-bytes".utf8),
            fileName: "proof.m4a",
            model: "whisper-1"
        )
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"model\""))
        XCTAssertTrue(text.contains("whisper-1"))
        XCTAssertTrue(text.contains("filename=\"proof.m4a\""))
        XCTAssertTrue(text.contains("audio-bytes"))
    }

    // MARK: - 服务商目录

    func testProviderCatalogIsWellFormed() {
        let labels = AIProviderKind.allCases.map(\.label)
        XCTAssertEqual(labels.count, Set(labels).count, "服务商名称不能重复")

        for kind in AIProviderKind.allCases {
            XCTAssertFalse(kind.blurb.isEmpty, "\(kind.label) 缺少简介")
            // 目前所有厂商只开放 API 密钥；订阅登录留待官方开放。
            XCTAssertEqual(kind.availableAuthMethods, [.apiKey])

            if kind != .openAICompatible {
                XCTAssertTrue(
                    kind.keyConsoleURLString.hasPrefix("https://"),
                    "\(kind.label) 密钥控制台链接必须是 https"
                )
            }
            if let preset = kind.presetOpenAIStyleBaseURLString {
                XCTAssertNotNil(URL(string: preset), "\(kind.label) 预置地址非法")
                XCTAssertFalse(preset.hasSuffix("/"), "\(kind.label) 预置地址不应带尾斜杠")
                XCTAssertFalse(kind.defaultModelName.isEmpty, "\(kind.label) 缺少默认模型")
            }
        }
    }

    func testPresetProvidersResolveBaseURLWithoutManualInput() {
        let deepSeek = AIProviderConfig(kind: .deepSeek, baseURLString: "", modelName: "")
        XCTAssertEqual(deepSeek.resolvedOpenAIStyleBaseURL?.absoluteString, "https://api.deepseek.com/v1")

        let gemini = AIProviderConfig(kind: .googleGemini, baseURLString: "", modelName: "")
        XCTAssertEqual(
            gemini.resolvedOpenAIStyleBaseURL?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/openai"
        )
    }

    func testLegacyConfigWithoutAuthMethodDecodesAsAPIKey() throws {
        let legacyJSON = #"{"kind": "openai", "baseURLString": "", "modelName": "gpt-4o-mini"}"#
        let config = try JSONDecoder().decode(AIProviderConfig.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(config.resolvedAuthMethod, .apiKey)
    }

    func testVoiceStaysHiddenForProvidersWithoutTranscription() {
        for kind in [AIProviderKind.googleGemini, .deepSeek, .moonshotKimi, .alibabaQwen] {
            let keyStore = InMemoryAIProviderKeyStore()
            let store = ParentAIProviderStore(keyStore: keyStore, defaults: testDefaults)
            store.apply(kind: kind, baseURLString: "", modelName: "", key: "sk-x")
            store.setChildVoiceTranscription(allowed: true)
            XCTAssertFalse(store.isVoiceTranscriptionReady, "\(kind.label) 不支持转写，语音必须隐藏")
        }
    }

    func testParentVoiceDoesNotDependOnChildConsent() {
        let store = ParentAIProviderStore(keyStore: InMemoryAIProviderKeyStore(), defaults: testDefaults)
        XCTAssertTrue(store.apply(kind: .openAI, baseURLString: "", modelName: "gpt-4o-mini", key: "sk-parent"))

        XCTAssertFalse(store.allowsChildVoiceTranscription)
        XCTAssertFalse(store.isVoiceTranscriptionReady)
        XCTAssertTrue(store.isParentVoiceTranscriptionReady)
    }

    func testParentMultimodalChatUsesParentBYOKWithoutChildImageConsent() async throws {
        let store = ParentAIProviderStore(keyStore: InMemoryAIProviderKeyStore(), defaults: testDefaults)
        XCTAssertTrue(store.apply(kind: .openAI, baseURLString: "", modelName: "gpt-4o-mini", key: "sk-parent"))
        XCTAssertFalse(store.allowsChildAICompanionImageUpload)

        let result = try await store.completeParentMultimodalChat(
            system: "parent coach",
            user: "help me understand this picture",
            imageAttachments: [
                AICompanionImageAttachment(
                    source: .photoLibrary,
                    mimeType: "image/jpeg",
                    data: Data([1, 2, 3]),
                    localSummary: "parent selected a picture"
                )
            ],
            using: StoreParentMultimodalSpyChatClient()
        )
        XCTAssertEqual(result, "parent multimodal ok")
    }

    // MARK: - 连通性测试

    func testConnectionRequestShapes() throws {
        let openAI = AIProviderConfig(kind: .openAI, baseURLString: "", modelName: "")
        let openAIRequest = try XCTUnwrap(AIProviderConnectionTester.buildRequest(config: openAI, apiKey: "sk-1"))
        XCTAssertEqual(openAIRequest.url?.absoluteString, "https://api.openai.com/v1/models")
        XCTAssertEqual(openAIRequest.value(forHTTPHeaderField: "Authorization"), "Bearer sk-1")

        let claude = AIProviderConfig(kind: .anthropicClaude, baseURLString: "", modelName: "")
        let claudeRequest = try XCTUnwrap(AIProviderConnectionTester.buildRequest(config: claude, apiKey: "sk-ant"))
        XCTAssertEqual(claudeRequest.url?.absoluteString, "https://api.anthropic.com/v1/models")
        XCTAssertEqual(claudeRequest.value(forHTTPHeaderField: "x-api-key"), "sk-ant")
        XCTAssertEqual(claudeRequest.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    }

    private func stubbedTester() -> AIProviderConnectionTester {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TranscriptionStubURLProtocol.self]
        return AIProviderConnectionTester(session: URLSession(configuration: configuration))
    }

    func testConnectionResultMapping() async {
        let config = AIProviderConfig(kind: .openAI, baseURLString: "", modelName: "")

        TranscriptionStubURLProtocol.stub = (200, #"{"data": []}"#)
        var result = await stubbedTester().test(config: config, apiKey: "sk")
        XCTAssertEqual(result, .ok)

        TranscriptionStubURLProtocol.stub = (401, "{}")
        result = await stubbedTester().test(config: config, apiKey: "sk")
        XCTAssertEqual(result, .unauthorized)

        TranscriptionStubURLProtocol.stub = (500, "{}")
        result = await stubbedTester().test(config: config, apiKey: "sk")
        XCTAssertEqual(result, .failed(statusCode: 500))

        TranscriptionStubURLProtocol.stub = nil
    }

    func testStoreConnectionTestRequiresSavedKey() async {
        let store = ParentAIProviderStore(keyStore: InMemoryAIProviderKeyStore(), defaults: testDefaults)
        let result = await store.testCurrentConnection()
        XCTAssertEqual(result, .notConfigured)
    }
}

/// 转写客户端测试用 URLProtocol 桩：拦截请求并返回预置响应，不触网。
final class TranscriptionStubURLProtocol: URLProtocol {
    /// (statusCode, body)。测试串行执行且每个用例自行设置/清理，
    /// 这里用 nonisolated(unsafe) 关闭静态可变状态检查。
    nonisolated(unsafe) static var stub: (Int, String)?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        guard let (status, body) = Self.stub,
              let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct StoreImageConsentSpyChatClient: AICompanionChatCompleting {
    func complete(
        system: String,
        user: String,
        imageAttachments: [AICompanionImageAttachment],
        config: AIProviderConfig,
        apiKey: String
    ) async throws -> String {
        #"{"reply":"不应该调用","guardian_signal":"none","memory_updates":{"summary":"bad"}}"#
    }
}

private struct StoreParentMultimodalSpyChatClient: AICompanionChatCompleting {
    func complete(
        system: String,
        user: String,
        imageAttachments: [AICompanionImageAttachment],
        config: AIProviderConfig,
        apiKey: String
    ) async throws -> String {
        guard system == "parent coach",
              user.contains("picture"),
              imageAttachments.count == 1,
              apiKey == "sk-parent" else {
            throw AIChatError.badResponse
        }
        return "parent multimodal ok"
    }
}
