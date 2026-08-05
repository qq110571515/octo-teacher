import XCTest
@testable import OctoTeacher

final class AICompanionCloudGuideServiceTests: XCTestCase {
    private let builder = AICompanionSnapshotBuilder()
    private let gateway = AICompanionPrivacyGateway()

    private func draft(messages: [AICompanionMessage], childName: String = "乐乐") -> AICompanionCloudRequestDraft {
        let input = AICompanionInput(
            childName: childName,
            mode: .homework,
            nextTaskTitle: "完成英文阅读",
            messages: messages
        )
        let snapshot = builder.build(viewerRole: .guardian, input: input)
        return gateway.makeDraft(input: input, snapshot: snapshot)
    }

    private func config(kind: AIProviderKind = .openAI) -> AIProviderConfig {
        AIProviderConfig(kind: kind, baseURLString: "", modelName: "gpt-test")
    }

    func testSendsOnlyRedactedDraftToProvider() async throws {
        let rawText = "乐乐卡在第3题，直接告诉我答案"
        let spy = RecordingChatClient(
            result: .success(
                #"{"reply":"先圈出题目问什么，再说出你已经知道的条件。","next_questions":["题目问你求什么？","你已经知道哪些条件？"],"guardian_signal":"none"}"#
            )
        )
        let service = AICompanionCloudGuideService(chatClient: spy)

        let guide = try await service.guide(
            draft: draft(messages: [AICompanionMessage(freeText: rawText)]),
            config: config(),
            apiKey: "sk-test-local-only"
        )

        let captured = await spy.capturedRequest()
        let rendered = captured.system + "\n" + captured.user
        XCTAssertEqual(guide.guardianSignal, .none)
        XCTAssertEqual(guide.nextQuestions.count, 2)
        XCTAssertEqual(captured.callCount, 1)
        XCTAssertFalse(rendered.contains(rawText))
        XCTAssertFalse(rendered.contains("乐乐"))
        XCTAssertFalse(rendered.contains("完成英文阅读"))
        XCTAssertFalse(rendered.contains("sk-test-local-only"))
        XCTAssertFalse(rendered.localizedCaseInsensitiveContains("api_key"))
        XCTAssertFalse(rendered.localizedCaseInsensitiveContains("provider:"))
    }

    func testBlockedDraftDoesNotCallProvider() async {
        let spy = RecordingChatClient(
            result: .success(#"{"reply":"不会被调用","next_questions":[],"guardian_signal":"none"}"#)
        )
        let service = AICompanionCloudGuideService(chatClient: spy)
        let blocked = draft(messages: [AICompanionMessage(freeText: "我被欺负了，不想活")])

        do {
            _ = try await service.guide(draft: blocked, config: config(), apiKey: "sk-test-local-only")
            XCTFail("高风险草稿不应调用 provider")
        } catch AICompanionCloudGuideError.blockedByPrivacyGateway(let reason) {
            XCTAssertTrue(reason.contains("可信大人"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        let captured = await spy.capturedRequest()
        XCTAssertEqual(captured.callCount, 0)
    }

    func testRequiresConfiguredOpenAIStyleProviderAndKey() async {
        let spy = RecordingChatClient(
            result: .success(#"{"reply":"ok","next_questions":[],"guardian_signal":"none"}"#)
        )
        let service = AICompanionCloudGuideService(chatClient: spy)
        let allowed = draft(messages: [AICompanionMessage(freeText: "我作业不会")])

        await XCTAssertThrowsErrorAsync(
            try await service.guide(draft: allowed, config: nil, apiKey: "sk-test")
        ) { error in
            XCTAssertEqual(error as? AICompanionCloudGuideError, .notConfigured)
        }
        await XCTAssertThrowsErrorAsync(
            try await service.guide(draft: allowed, config: config(), apiKey: "   ")
        ) { error in
            XCTAssertEqual(error as? AICompanionCloudGuideError, .notConfigured)
        }
        await XCTAssertThrowsErrorAsync(
            try await service.guide(draft: allowed, config: config(kind: .anthropicClaude), apiKey: "sk-test")
        ) { error in
            XCTAssertEqual(error as? AICompanionCloudGuideError, .providerUnsupported)
        }
    }

    func testRejectsMalformedUnsafeOrAnswerLikeResponse() async throws {
        let allowed = draft(messages: [AICompanionMessage(freeText: "我作业不会")])

        let malformed = AICompanionCloudGuideService(
            chatClient: RecordingChatClient(result: .success("not-json"))
        )
        await XCTAssertThrowsErrorAsync(
            try await malformed.guide(draft: allowed, config: config(), apiKey: "sk-test")
        ) { error in
            XCTAssertEqual(error as? AICompanionCloudGuideError, .badResponse)
        }

        let unsafe = AICompanionCloudGuideService(
            chatClient: RecordingChatClient(
                result: .success(#"{"reply":"请打开 file://private/photo.png","next_questions":[],"guardian_signal":"none"}"#)
            )
        )
        await XCTAssertThrowsErrorAsync(
            try await unsafe.guide(draft: allowed, config: config(), apiKey: "sk-test")
        ) { error in
            XCTAssertEqual(error as? AICompanionCloudGuideError, .unsafeResponse)
        }

        let finalAnswer = AICompanionCloudGuideService(
            chatClient: RecordingChatClient(
                result: .success(#"{"reply":"答案是 42。","next_questions":[],"guardian_signal":"none"}"#)
            )
        )
        await XCTAssertThrowsErrorAsync(
            try await finalAnswer.guide(draft: allowed, config: config(), apiKey: "sk-test")
        ) { error in
            XCTAssertEqual(error as? AICompanionCloudGuideError, .unsafeResponse)
        }

        let answerLikeQuestion = AICompanionCloudGuideService(
            chatClient: RecordingChatClient(
                result: .success(#"{"reply":"先试一步。","next_questions":["answer: 42"],"guardian_signal":"none"}"#)
            )
        )
        await XCTAssertThrowsErrorAsync(
            try await answerLikeQuestion.guide(draft: allowed, config: config(), apiKey: "sk-test")
        ) { error in
            XCTAssertEqual(error as? AICompanionCloudGuideError, .unsafeResponse)
        }
    }

    func testPropagatesChatClientFailureWithoutSavingKey() async {
        let spy = RecordingChatClient(result: .failure(.requestFailed(statusCode: 429)))
        let service = AICompanionCloudGuideService(chatClient: spy)

        await XCTAssertThrowsErrorAsync(
            try await service.guide(
                draft: draft(messages: [AICompanionMessage(freeText: "我作业不会")]),
                config: config(),
                apiKey: "sk-test-local-only"
            )
        ) { error in
            XCTAssertEqual(error as? AIChatError, .requestFailed(statusCode: 429))
        }

        let captured = await spy.capturedRequest()
        XCTAssertEqual(captured.callCount, 1)
        XCTAssertEqual(captured.apiKey, "sk-test-local-only")
        XCTAssertFalse((captured.system + captured.user).contains("sk-test-local-only"))
    }

    func testAcceptsStrictJSONWrappedInCodeFence() async throws {
        let service = AICompanionCloudGuideService(
            chatClient: RecordingChatClient(
                result: .success(
                    """
                    ```json
                    {"reply":"先读题目，再圈出关键词。","next_questions":["题目问什么？"],"guardian_signal":"none"}
                    ```
                    """
                )
            )
        )

        let guide = try await service.guide(
            draft: draft(messages: [AICompanionMessage(freeText: "我作业不会")]),
            config: config(),
            apiKey: "sk-test"
        )

        XCTAssertEqual(guide.reply, "先读题目，再圈出关键词。")
        XCTAssertEqual(guide.nextQuestions, ["题目问什么？"])
        XCTAssertEqual(guide.guardianSignal, .none)
    }

    func testTrimsAndCapsNextQuestions() async throws {
        let service = AICompanionCloudGuideService(
            chatClient: RecordingChatClient(
                result: .success(
                    #"{"reply":"  先试一小步。  ","next_questions":[" 第一问？ ","","第二问？","第三问？"],"guardian_signal":"watch"}"#
                )
            )
        )

        let guide = try await service.guide(
            draft: draft(messages: [AICompanionMessage(freeText: "我作业不会")]),
            config: config(),
            apiKey: "sk-test"
        )

        XCTAssertEqual(guide.reply, "先试一小步。")
        XCTAssertEqual(guide.nextQuestions, ["第一问？", "第二问？"])
        XCTAssertEqual(guide.guardianSignal, .watch)
        XCTAssertFalse(guide.givesFinalAnswer)
        XCTAssertFalse(guide.storesRawTranscript)
    }

    func testCloudGuideCodableIgnoresExternalSideEffectFlags() throws {
        // 这里覆盖的是本地持久化/往返 Codable 路径；云端 snake_case 响应另由 parseGuide 测试覆盖。
        let json = """
        {
          "reply": "先试一个小提示。",
          "nextQuestions": ["你已经知道什么？"],
          "guardianSignal": "act_now",
          "givesFinalAnswer": true,
          "storesRawTranscript": true,
          "writesLedger": true,
          "sendsNotification": true
        }
        """

        let guide = try JSONDecoder().decode(AICompanionCloudGuide.self, from: Data(json.utf8))

        XCTAssertEqual(guide.reply, "先试一个小提示。")
        XCTAssertEqual(guide.nextQuestions, ["你已经知道什么？"])
        XCTAssertEqual(guide.guardianSignal, .actNow)
        XCTAssertFalse(guide.givesFinalAnswer)
        XCTAssertFalse(guide.storesRawTranscript)
        XCTAssertFalse(guide.writesLedger)
        XCTAssertFalse(guide.sendsNotification)

        let encoded = try JSONDecoder().decode(
            AICompanionCloudGuide.self,
            from: JSONEncoder().encode(guide)
        )
        XCTAssertFalse(encoded.givesFinalAnswer)
        XCTAssertFalse(encoded.storesRawTranscript)
        XCTAssertFalse(encoded.writesLedger)
        XCTAssertFalse(encoded.sendsNotification)
    }

    func testCloudGuideCodableDefaultsMissingOptionalFields() throws {
        let guide = try JSONDecoder().decode(
            AICompanionCloudGuide.self,
            from: Data(#"{"reply":"先说说你卡在哪里。","guardianSignal":"future_signal"}"#.utf8)
        )

        XCTAssertEqual(guide.reply, "先说说你卡在哪里。")
        XCTAssertEqual(guide.nextQuestions, [])
        XCTAssertEqual(guide.guardianSignal, .none)
        XCTAssertFalse(guide.givesFinalAnswer)
        XCTAssertFalse(guide.storesRawTranscript)
        XCTAssertFalse(guide.writesLedger)
        XCTAssertFalse(guide.sendsNotification)
    }
}

private actor RecordingChatClient: AIChatCompleting {
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

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("expected error", file: file, line: line)
    } catch {
        handler(error)
    }
}
