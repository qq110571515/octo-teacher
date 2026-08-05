import XCTest
@testable import OctoTeacher

/// AI 布置助手（聊天客户端、阅读规划、视频推荐、来源目录）的回归测试。
@MainActor
final class AIComposerTests: XCTestCase {

    nonisolated(unsafe) private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: "test.octoteacher.aicomposer")
        testDefaults.removePersistentDomain(forName: "test.octoteacher.aicomposer")
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: "test.octoteacher.aicomposer")
        super.tearDown()
    }

    // MARK: - 聊天客户端

    private func stubbedChatClient() -> OpenAIStyleChatClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TranscriptionStubURLProtocol.self]
        return OpenAIStyleChatClient(session: URLSession(configuration: configuration))
    }

    func testChatClientParsesChoices() async throws {
        TranscriptionStubURLProtocol.stub = (200, #"{"choices":[{"message":{"content":"{\"sessions\":[]}"}}]}"#)
        defer { TranscriptionStubURLProtocol.stub = nil }

        let config = AIProviderConfig(kind: .openAI, baseURLString: "", modelName: "")
        let content = try await stubbedChatClient().complete(system: "s", user: "u", config: config, apiKey: "sk")
        XCTAssertEqual(content, #"{"sessions":[]}"#)

        let request = try XCTUnwrap(TranscriptionStubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk")
    }

    func testChatClientThrowsOnAuthFailure() async throws {
        TranscriptionStubURLProtocol.stub = (401, "{}")
        defer { TranscriptionStubURLProtocol.stub = nil }

        let config = AIProviderConfig(kind: .openAI, baseURLString: "", modelName: "")
        do {
            _ = try await stubbedChatClient().complete(system: "s", user: "u", config: config, apiKey: "bad")
            XCTFail("401 必须抛错")
        } catch let error as AIChatError {
            XCTAssertEqual(error, .requestFailed(statusCode: 401))
        }
    }

    // MARK: - Store 门禁

    func testDraftJSONBlockedWithoutKey() async {
        let store = ParentAIProviderStore(keyStore: InMemoryAIProviderKeyStore(), defaults: testDefaults)
        do {
            _ = try await store.completeDraftJSON(system: "s", user: "u", using: StubChatClient(result: .success("{}")))
            XCTFail("无配置必须抛错")
        } catch let error as AIChatError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("错误类型不对")
        }
    }

    func testDraftJSONBlockedForClaude() async {
        let store = ParentAIProviderStore(keyStore: InMemoryAIProviderKeyStore(), defaults: testDefaults)
        store.apply(kind: .anthropicClaude, baseURLString: "", modelName: "", key: "sk-1")
        XCTAssertFalse(store.isReadyForAIComposer)
        do {
            _ = try await store.completeDraftJSON(system: "s", user: "u", using: StubChatClient(result: .success("{}")))
            XCTFail("Claude 第一版聊天副驾必须抛错")
        } catch let error as AIChatError {
            XCTAssertEqual(error, .providerUnsupported)
        } catch {
            XCTFail("错误类型不对")
        }
    }

    func testDraftJSONSucceedsWithOpenAI() async throws {
        let store = ParentAIProviderStore(keyStore: InMemoryAIProviderKeyStore(), defaults: testDefaults)
        store.apply(kind: .openAI, baseURLString: "", modelName: "", key: "sk-1")
        XCTAssertTrue(store.isReadyForAIComposer)
        let result = try await store.completeDraftJSON(
            system: "s",
            user: "u",
            using: StubChatClient(result: .success(#"{"ok":true}"#))
        )
        XCTAssertEqual(result, #"{"ok":true}"#)
    }

    func testReadingTranslationRequiresChildAICompanionConsent() async {
        let store = ParentAIProviderStore(keyStore: InMemoryAIProviderKeyStore(), defaults: testDefaults)
        store.apply(kind: .openAI, baseURLString: "", modelName: "", key: "sk-1")
        XCTAssertFalse(store.isReadyForChildAICompanion)

        do {
            _ = try await store.translateReadingPage(
                paragraphs: ["Once upon a time."],
                childAge: 8,
                targetLanguage: .chinese,
                using: StubChatClient(result: .success(#"{"translations":[{"i":0,"text":"从前。"}]}"#))
            )
            XCTFail("孩子端阅读翻译必须复用 AI 小伙伴授权门禁")
        } catch let error as AIChatError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("错误类型不对")
        }
    }

    func testReadingTranslationSucceedsWithChildAICompanionConsent() async throws {
        let store = ParentAIProviderStore(keyStore: InMemoryAIProviderKeyStore(), defaults: testDefaults)
        store.apply(kind: .openAI, baseURLString: "", modelName: "", key: "sk-1")
        store.setChildAICompanionGuidance(allowed: true)

        let result = try await store.translateReadingPage(
            paragraphs: ["Once upon a time.", "Peter looked at the window."],
            childAge: 8,
            targetLanguage: .chinese,
            using: StubChatClient(result: .success(#"{"translations":[{"i":1,"text":"彼得看着窗户。"},{"i":0,"text":"从前。"}]}"#))
        )

        XCTAssertEqual(result.map(\.original), ["Once upon a time.", "Peter looked at the window."])
        XCTAssertEqual(result.map(\.translation), ["从前。", "彼得看着窗户。"])
    }

    // MARK: - 阅读规划解析

    func testBookRecommenderPromptPrioritizesDownloadablePublicDomainSources() {
        let prompt = AIBookRecommender.systemPrompt(language: .english, parentLanguage: .chinese)
        XCTAssertTrue(prompt.contains("Project Gutenberg"))
        XCTAssertTrue(prompt.contains("Standard Ebooks"))
        XCTAssertTrue(prompt.contains("Internet Archive"))
        XCTAssertTrue(prompt.contains("可下载并导入 App"))
    }

    func testBookRecommenderExplainsBilingualFallbackForChineseFamilies() {
        let prompt = AIBookRecommender.systemPrompt(language: .chinese, parentLanguage: .chinese)
        XCTAssertTrue(prompt.contains("英文 EPUB"))
        XCTAssertTrue(prompt.contains("中英双语翻译辅助"))
    }

    func testPreReaderBookPromptUsesStrictFoundationCriteria() {
        XCTAssertTrue(BookCategory.alphabet.isPreReaderFoundation)
        XCTAssertTrue(BookCategory.numbers.isPreReaderFoundation)
        XCTAssertFalse(BookCategory.childrenLiterature.isPreReaderFoundation)

        let prompt = AIBookRecommender.userPrompt(category: .numbers, digest: "孩子还不识字，喜欢看图。")
        XCTAssertTrue(prompt.contains("不识字"))
        XCTAssertTrue(prompt.contains("图画支撑"))
        XCTAssertTrue(prompt.contains("counting book"))
        XCTAssertTrue(prompt.contains("1-10/1-20"))
        XCTAssertTrue(prompt.contains("避免长篇章节书"))
    }

    func testBookCandidateSourceKeyIgnoresGeneratedUUID() {
        let first = BookCandidate(title: "Peter Pan", author: "J. M. Barrie", blurb: "")
        let second = BookCandidate(title: "Peter Pan", author: "J. M. Barrie", blurb: "different")
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.sourceKey, second.sourceKey)
    }

    func testReadingPlannerParsesValidJSON() {
        let raw = """
        {"sessions":[
            {"order":1,"chapters":"第1-2章","estimatedMinutes":30,"note":"开篇"},
            {"order":2,"chapters":"第3-5章","estimatedMinutes":35,"note":""}
        ]}
        """
        let drafts = AIReadingPlanner.parse(raw)
        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts[0].chapters, "第1-2章")
        XCTAssertEqual(drafts[1].order, 2)
    }

    func testReadingPlannerStripsMarkdownFences() {
        let raw = """
        ```json
        {"sessions":[{"order":1,"chapters":"第1章","estimatedMinutes":20,"note":""}]}
        ```
        """
        XCTAssertEqual(AIReadingPlanner.parse(raw).count, 1)
    }

    func testReadingPlannerHandlesMalformedOutput() {
        XCTAssertTrue(AIReadingPlanner.parse("对不起我不能输出 JSON").isEmpty)
        XCTAssertTrue(AIReadingPlanner.parse("{\"sessions\": [{\"chapters\": \"  \"}]}").isEmpty)
    }

    func testReadingTranslatorParsesMarkdownAndAlignsParagraphs() {
        let raw = """
        ```json
        {"translations":[{"i":1,"text":"第二段。"},{"i":0,"text":"第一段。"}]}
        ```
        """
        let result = AIReadingTranslator.parse(raw, originalParagraphs: ["First.", "Second."])
        XCTAssertEqual(result.map(\.original), ["First.", "Second."])
        XCTAssertEqual(result.map(\.translation), ["第一段。", "第二段。"])
    }

    func testReadingTranslatorRejectsMismatchedOutput() {
        XCTAssertTrue(AIReadingTranslator.parse(
            #"{"translations":[{"i":0,"text":"第一段。"}]}"#,
            originalParagraphs: ["First.", "Second."]
        ).isEmpty)
        XCTAssertTrue(AIReadingTranslator.parse("not json", originalParagraphs: ["First."]).isEmpty)
    }

    func testReadingTranslatorSplitsCurrentPageIntoSafeParagraphs() {
        let text = "First paragraph.\n\nSecond paragraph.\n\n\nThird paragraph."
        XCTAssertEqual(
            AIReadingTranslator.paragraphs(from: text),
            ["First paragraph.", "Second paragraph.", "Third paragraph."]
        )
    }

    func testReadingPlannerClampsMinutesAndFillsOrder() {
        let raw = #"{"sessions":[{"chapters":"第1章","estimatedMinutes":999}]}"#
        let drafts = AIReadingPlanner.parse(raw)
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].estimatedMinutes, 120, "时长必须封顶")
        XCTAssertEqual(drafts[0].order, 1, "缺失 order 时按序补齐")
    }

    // MARK: - 视频推荐解析

    func testVideoSuggesterParsesAndBuildsSearchURL() throws {
        let raw = """
        {"videos":[
            {"title":"火山爆发的秘密","channel":"SciShow Kids","reason":"适龄科普","searchQuery":"SciShow Kids volcano"},
            {"title":"  ","channel":"x","reason":"","searchQuery":"skip"}
        ]}
        """
        let drafts = AIVideoSuggester.parse(raw)
        XCTAssertEqual(drafts.count, 1, "空标题必须跳过")
        let url = try XCTUnwrap(drafts[0].youtubeSearchURL)
        XCTAssertTrue(url.absoluteString.contains("youtube.com/results"))
        XCTAssertTrue(url.absoluteString.contains("SciShow"))
    }

    // MARK: - 来源目录

    func testReadingSourceDirectoryIsWellFormed() {
        let sources = ReadingSourceDirectory.sources
        XCTAssertEqual(sources.count, 10)
        XCTAssertEqual(Set(sources.map(\.id)).count, 10, "来源 id 不能重复")
        for source in sources {
            XCTAssertFalse(source.name.isEmpty)
            XCTAssertFalse(source.blurb.isEmpty)
            if !source.urlString.isEmpty {
                XCTAssertTrue(source.urlString.hasPrefix("https://"), "\(source.name) 链接必须是 https")
            }
        }
    }

    // MARK: - 视频任务持久化

    func testVideoSpecSurvivesSnapshotRoundTrip() throws {
        let store = LocalFamilyStore()
        store.assignNewTask(
            title: "看火山视频",
            instructions: "看完说说学到了什么。",
            category: .learning,
            rewardMinutes: 15,
            requiredProof: .text,
            video: VideoSpec(urlString: "https://www.youtube.com/watch?v=abc", platformLabel: "YouTube", minWatchMinutes: 15)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(store.snapshot)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FamilyStoreSnapshot.self, from: data)

        let restored = try XCTUnwrap(decoded.assignments.last?.task.video)
        XCTAssertEqual(restored.platformLabel, "YouTube")
        XCTAssertEqual(restored.minWatchMinutes, 15)
    }
}
