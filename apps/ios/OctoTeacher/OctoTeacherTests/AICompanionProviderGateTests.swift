import XCTest
@testable import OctoTeacher

@MainActor
final class AICompanionProviderGateTests: XCTestCase {
    nonisolated(unsafe) private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: "test.octoteacher.ai-companion-provider")
        testDefaults.removePersistentDomain(forName: "test.octoteacher.ai-companion-provider")
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: "test.octoteacher.ai-companion-provider")
        super.tearDown()
    }

    private func makeDraft() -> AICompanionCloudRequestDraft {
        let input = AICompanionInput(
            childName: "乐乐",
            mode: .homework,
            nextTaskTitle: "完成英文阅读",
            messages: [AICompanionMessage(freeText: "我作业不会")]
        )
        let snapshot = AICompanionSnapshotBuilder().build(viewerRole: .guardian, input: input)
        return AICompanionPrivacyGateway().makeDraft(input: input, snapshot: snapshot)
    }

    func testChildAICompanionGateRequiresConfigAndSupportedProvider() async {
        let keyStore = InMemoryAIProviderKeyStore()
        let store = ParentAIProviderStore(keyStore: keyStore, defaults: testDefaults)
        let draft = makeDraft()
        let service = AICompanionCloudGuideService(
            chatClient: ProviderGateRecordingChatClient(
                result: .success(#"{"reply":"ok","next_questions":[],"guardian_signal":"none"}"#)
            )
        )

        XCTAssertFalse(store.isReadyForChildAICompanion)
        do {
            _ = try await store.guideChildAICompanion(draft: draft, using: service)
            XCTFail("未配置时不应调用 AI 小伙伴云端引导")
        } catch {
            XCTAssertEqual(error as? AICompanionCloudGuideError, .notConfigured)
        }

        XCTAssertTrue(store.apply(kind: .openAI, baseURLString: "", modelName: "gpt-test", key: "sk-test"))
        XCTAssertFalse(store.isReadyForChildAICompanion, "孩子端云端小伙伴必须默认关闭，不能因为家长配置了 BYOK 就隐式开启")
        do {
            _ = try await store.guideChildAICompanion(draft: draft, using: service)
            XCTFail("未开启家长授权时不应调用 AI 小伙伴云端引导")
        } catch {
            XCTAssertEqual(error as? AICompanionCloudGuideError, .notConfigured)
        }
        store.setChildAICompanionGuidance(allowed: true)
        XCTAssertTrue(store.isReadyForChildAICompanion)

        let restored = ParentAIProviderStore(keyStore: keyStore, defaults: testDefaults)
        XCTAssertTrue(restored.allowsChildAICompanionGuidance)
        XCTAssertTrue(restored.isReadyForChildAICompanion)

        XCTAssertTrue(store.apply(kind: .anthropicClaude, baseURLString: "", modelName: "", key: "sk-test"))
        XCTAssertFalse(store.isReadyForChildAICompanion)
        do {
            _ = try await store.guideChildAICompanion(draft: draft, using: service)
            XCTFail("非 OpenAI-style provider 不应调用 AI 小伙伴云端引导")
        } catch {
            XCTAssertEqual(error as? AICompanionCloudGuideError, .providerUnsupported)
        }
    }

    func testChildAICompanionGateUsesKeyInternallyAndKeepsPromptRedacted() async throws {
        let keyStore = InMemoryAIProviderKeyStore()
        let store = ParentAIProviderStore(keyStore: keyStore, defaults: testDefaults)
        XCTAssertTrue(store.apply(kind: .openAI, baseURLString: "", modelName: "gpt-test", key: "sk-test-local-only"))
        store.setChildAICompanionGuidance(allowed: true)
        let chat = ProviderGateRecordingChatClient(
            result: .success(
                #"{"reply":"先圈出题目问什么。","next_questions":["题目问你求什么？"],"guardian_signal":"none"}"#
            )
        )
        let service = AICompanionCloudGuideService(chatClient: chat)

        XCTAssertTrue(store.isReadyForChildAICompanion)
        let guide = try await store.guideChildAICompanion(draft: makeDraft(), using: service)

        let captured = await chat.capturedRequest()
        let renderedPrompt = captured.system + "\n" + captured.user
        XCTAssertEqual(guide.reply, "先圈出题目问什么。")
        XCTAssertEqual(captured.apiKey, "sk-test-local-only")
        XCTAssertFalse(renderedPrompt.contains("sk-test-local-only"))
        XCTAssertFalse(renderedPrompt.contains("乐乐"))
        XCTAssertFalse(renderedPrompt.contains("完成英文阅读"))
    }

    func testBlockedDraftDoesNotReachProviderThroughStoreGate() async {
        let keyStore = CountingAIProviderKeyStore()
        let store = ParentAIProviderStore(keyStore: keyStore, defaults: testDefaults)
        XCTAssertTrue(store.apply(kind: .openAI, baseURLString: "", modelName: "gpt-test", key: "sk-test-local-only"))
        store.setChildAICompanionGuidance(allowed: true)
        keyStore.resetLoadCount()
        let input = AICompanionInput(
            childName: "乐乐",
            mode: .emotion,
            messages: [AICompanionMessage(freeText: "我不想活")]
        )
        let snapshot = AICompanionSnapshotBuilder().build(viewerRole: .guardian, input: input)
        let blocked = AICompanionPrivacyGateway().makeDraft(input: input, snapshot: snapshot)
        let chat = ProviderGateRecordingChatClient(
            result: .success(#"{"reply":"不会被调用","next_questions":[],"guardian_signal":"none"}"#)
        )
        let service = AICompanionCloudGuideService(chatClient: chat)

        do {
            _ = try await store.guideChildAICompanion(draft: blocked, using: service)
            XCTFail("隐私网关阻断的草稿不应进入 provider")
        } catch {
            guard case AICompanionCloudGuideError.blockedByPrivacyGateway = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }

        let captured = await chat.capturedRequest()
        XCTAssertEqual(captured.callCount, 0)
        XCTAssertEqual(keyStore.loadCount, 0, "隐私网关阻断后不应再触发 Keychain 读取")
    }
}

private final class CountingAIProviderKeyStore: AIProviderKeyStoring {
    private var keys: [AIProviderKind: String] = [:]
    private(set) var loadCount = 0

    func saveKey(_ key: String, for provider: AIProviderKind) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        keys[provider] = trimmed
        return true
    }

    func loadKey(for provider: AIProviderKind) -> String? {
        loadCount += 1
        return keys[provider]
    }

    func deleteKey(for provider: AIProviderKind) {
        keys[provider] = nil
    }

    func hasKey(for provider: AIProviderKind) -> Bool {
        keys[provider] != nil
    }

    func resetLoadCount() {
        loadCount = 0
    }
}

private actor ProviderGateRecordingChatClient: AIChatCompleting {
    struct Captured: Equatable {
        var system: String = ""
        var user: String = ""
        var apiKey: String = ""
        var callCount: Int = 0
    }

    private let result: Result<String, AIChatError>
    private var captured = Captured()

    init(result: Result<String, AIChatError>) {
        self.result = result
    }

    func complete(system: String, user: String, config: AIProviderConfig, apiKey: String) async throws -> String {
        captured.system = system
        captured.user = user
        captured.apiKey = apiKey
        captured.callCount += 1
        switch result {
        case .success(let text): return text
        case .failure(let error): throw error
        }
    }

    func capturedRequest() -> Captured {
        captured
    }
}
