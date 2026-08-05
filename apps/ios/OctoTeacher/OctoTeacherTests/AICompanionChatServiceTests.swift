import XCTest
@testable import OctoTeacher

final class AICompanionChatServiceTests: XCTestCase {
    private func config(kind: AIProviderKind = .openAI) -> AIProviderConfig {
        AIProviderConfig(kind: kind, baseURLString: "", modelName: "gpt-test")
    }

    private func request(
        latestText: String = "我想聊聊恐龙",
        latestIntent: AICompanionIntent = .offTopic,
        imageAttachments: [AICompanionImageAttachment] = []
    ) -> AICompanionChatRequest {
        let childId = UUID()
        let memory = AICompanionMemoryDigest.empty(
            childId: childId,
            companionName: "小云",
            companionAvatarDescription: "一只蓝色星星小龙",
            personalityLabel: "活泼教练型"
        )
        return AICompanionChatRequest(
            childAge: 8,
            mode: .nextStep,
            latestText: latestText,
            latestIntent: latestIntent,
            companionName: "小云",
            companionVoice: .bright,
            companionPersonality: .playfulCoach,
            avatarDescription: "一只蓝色星星小龙",
            memory: memory,
            nextTaskTitle: "睡前阅读",
            attachmentSummaries: imageAttachments.map(\.localSummary),
            imageAttachments: imageAttachments
        )
    }

    func testChatSendsPersonaMemoryAndLatestMessageToProvider() async throws {
        let spy = CompanionRecordingChatClient(
            result: .success(
                #"{"reply":"恐龙很酷！你最想聊霸王龙还是三角龙？","guardian_signal":"none","memory_updates":{"interests":["恐龙"],"preferences":["喜欢像朋友一样聊天"],"learning_notes":[],"emotional_notes":[],"homework_guidance_notes":[],"summary":"孩子想聊恐龙"}}"#
            )
        )
        let service = AICompanionChatService(chatClient: spy)

        let turn = try await service.chat(request: request(), config: config(), apiKey: "sk-test-local-only")

        let captured = await spy.capturedRequest()
        let rendered = captured.system + "\n" + captured.user
        XCTAssertEqual(turn.reply, "恐龙很酷！你最想聊霸王龙还是三角龙？")
        XCTAssertEqual(turn.memoryUpdate.interests, ["恐龙"])
        XCTAssertTrue(turn.providerUsed)
        XCTAssertEqual(captured.apiKey, "sk-test-local-only")
        XCTAssertTrue(rendered.contains("小云"))
        XCTAssertTrue(rendered.contains("一只蓝色星星小龙"))
        XCTAssertTrue(rendered.contains("我想聊聊恐龙"))
        XCTAssertFalse(rendered.contains("sk-test-local-only"))
        XCTAssertEqual(captured.imageCount, 0)
    }

    func testImageAttachmentReachesVisionClient() async throws {
        let image = AICompanionImageAttachment(
            source: .camera,
            mimeType: "image/jpeg",
            data: Data("jpeg-bytes".utf8),
            localSummary: "孩子拍了一张照片并授权小伙伴查看。"
        )
        let spy = CompanionRecordingChatClient(
            result: .success(
                #"{"reply":"我看到了图片。我们先说说你想问哪一块。","guardian_signal":"none","memory_updates":{"summary":"孩子用图片交流"}}"#
            )
        )
        let service = AICompanionChatService(chatClient: spy)

        let turn = try await service.chat(
            request: request(latestText: "帮我看看这张图", imageAttachments: [image]),
            config: config(),
            apiKey: "sk-test-local-only"
        )

        let captured = await spy.capturedRequest()
        XCTAssertEqual(turn.reply, "我看到了图片。我们先说说你想问哪一块。")
        XCTAssertEqual(captured.imageCount, 1)
        XCTAssertTrue(captured.user.contains("image_count=1"))
        XCTAssertTrue(captured.user.contains("孩子拍了一张照片"))
        XCTAssertTrue(captured.system.contains("Vision rule"))
        XCTAssertTrue(captured.system.contains("Homework image rule"))
        XCTAssertTrue(captured.system.contains("do not solve it"))
        XCTAssertTrue(captured.system.contains("cannot browse the internet"))
        XCTAssertTrue(captured.system.contains("real-time web search"))
        XCTAssertTrue(captured.system.contains("Do not output JSON"))
    }

    func testPlainCloudReplyIsAcceptedWhenProviderIgnoresJSONFormat() async throws {
        let spy = CompanionRecordingChatClient(
            result: .success("我看见一盒红色的小物品。你想让我帮你一起判断它像什么，还是想聊它从哪里来的？")
        )
        let service = AICompanionChatService(chatClient: spy)

        let turn = try await service.chat(
            request: request(latestText: "这是什么"),
            config: config(),
            apiKey: "sk-test-local-only"
        )

        XCTAssertTrue(turn.providerUsed)
        XCTAssertTrue(turn.reply.contains("红色"))
        XCTAssertEqual(turn.memoryUpdate.summary, "")
    }

    func testLooseReplyIsAcceptedFromMalformedJSONLikeProviderOutput() async throws {
        let spy = CompanionRecordingChatClient(
            result: .success(#"{reply: "我看到一个红色盒子。我们先一起说说它上面有哪些字。", guardian_signal: none}"#)
        )
        let service = AICompanionChatService(chatClient: spy)

        let turn = try await service.chat(
            request: request(latestText: "这是什么"),
            config: config(),
            apiKey: "sk-test-local-only"
        )

        XCTAssertTrue(turn.providerUsed)
        XCTAssertTrue(turn.reply.contains("红色盒子"))
        XCTAssertFalse(turn.reply.contains("guardian_signal"))
    }

    func testInternalMemoryEchoFromProviderIsRejected() async {
        let service = AICompanionChatService(
            chatClient: CompanionRecordingChatClient(
                result: .success("companion_name=星星伙伴 conversation_count=10 latest_summary=孩子问我能做什么")
            )
        )

        await XCTAssertThrowsErrorAsync(
            try await service.chat(
                request: request(latestText: "你能做什么"),
                config: config(),
                apiKey: "sk-test"
            )
        ) { error in
            XCTAssertEqual(error as? AICompanionChatServiceError, .unsafeResponse)
        }
    }

    func testRecentImageContextDetectsFollowUpReferences() {
        XCTAssertTrue(AICompanionRecentImageContext.referencesRecentImage("你仔细看看这个到底是什么"))
        XCTAssertTrue(AICompanionRecentImageContext.referencesRecentImage("你在网上找找呢"))
        XCTAssertTrue(AICompanionRecentImageContext.referencesRecentImage("那张照片里有什么"))
        XCTAssertFalse(AICompanionRecentImageContext.referencesRecentImage("我今天想聊恐龙"))

        var context = AICompanionRecentImageContext(
            attachments: [
                AICompanionImageAttachment(
                    source: .camera,
                    mimeType: "image/jpeg",
                    data: Data("jpeg".utf8),
                    localSummary: "孩子拍了一张照片。"
                )
            ],
            visualSummary: "我看见一个黑色小盒子。"
        )
        XCTAssertTrue(context.isActive)
        XCTAssertTrue(context.followUpSummary.contains("上次看图摘要"))
        context.consumeTurn()
        XCTAssertEqual(context.remainingTurns, AICompanionRecentImageContext.maxFollowUpTurns - 1)
        context.refresh()
        XCTAssertEqual(context.remainingTurns, AICompanionRecentImageContext.maxFollowUpTurns)
    }

    func testOpenAIMultimodalBodyUsesImageURLParts() throws {
        let image = AICompanionImageAttachment(
            source: .photoLibrary,
            mimeType: "image/jpeg",
            data: Data("image-data".utf8),
            localSummary: "孩子从相册选择了一张图片并授权小伙伴查看。"
        )

        let body = OpenAIStyleCompanionChatClient.requestBody(
            model: "gpt-4o-mini",
            system: "system",
            user: "user",
            imageAttachments: [image]
        )
        let data = try JSONSerialization.data(withJSONObject: body)
        let rendered = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(rendered.contains("\"type\":\"image_url\""))
        XCTAssertTrue(rendered.contains("\"detail\":\"auto\""))
        XCTAssertTrue(rendered.contains("data:image\\/jpeg;base64"))
        XCTAssertTrue(rendered.contains(Data("image-data".utf8).base64EncodedString()))
        XCTAssertFalse(rendered.contains("response_format"))
    }

    func testHighRiskAndUnsafeInputDoNotReachProvider() async {
        let spy = CompanionRecordingChatClient(
            result: .success(#"{"reply":"不会被调用","guardian_signal":"none","memory_updates":{"summary":"none"}}"#)
        )
        let service = AICompanionChatService(chatClient: spy)

        await XCTAssertThrowsErrorAsync(
            try await service.chat(
                request: request(latestText: "我不想活", latestIntent: .highRisk),
                config: config(),
                apiKey: "sk-test"
            )
        ) { error in
            XCTAssertEqual(error as? AICompanionChatServiceError, .blockedBySafetyGate)
        }

        let captured = await spy.capturedRequest()
        XCTAssertEqual(captured.callCount, 0)
    }

    func testRejectsFinalHomeworkAnswerFromProvider() async {
        let service = AICompanionChatService(
            chatClient: CompanionRecordingChatClient(
                result: .success(
                    #"{"reply":"答案是 42。","guardian_signal":"none","memory_updates":{"summary":"bad"}}"#
                )
            )
        )

        await XCTAssertThrowsErrorAsync(
            try await service.chat(
                request: request(latestText: "这道题答案是什么", latestIntent: .wantsDirectAnswer),
                config: config(),
                apiKey: "sk-test"
            )
        ) { error in
            XCTAssertEqual(error as? AICompanionChatServiceError, .unsafeResponse)
        }
    }

    func testRejectsNaturalLanguageFinalHomeworkAnswerFromProvider() async {
        let service = AICompanionChatService(
            chatClient: CompanionRecordingChatClient(
                result: .success("最终答案是 42，直接填上去就可以。")
            )
        )

        await XCTAssertThrowsErrorAsync(
            try await service.chat(
                request: request(latestText: "这道题答案是什么", latestIntent: .wantsDirectAnswer),
                config: config(),
                apiKey: "sk-test"
            )
        ) { error in
            XCTAssertEqual(error as? AICompanionChatServiceError, .unsafeResponse)
        }
    }

    func testRequiresOpenAIStyleProviderAndKey() async {
        let service = AICompanionChatService(
            chatClient: CompanionRecordingChatClient(
                result: .success(#"{"reply":"ok","guardian_signal":"none","memory_updates":{"summary":"ok"}}"#)
            )
        )

        await XCTAssertThrowsErrorAsync(
            try await service.chat(request: request(), config: nil, apiKey: "sk-test")
        ) { error in
            XCTAssertEqual(error as? AICompanionChatServiceError, .notConfigured)
        }

        await XCTAssertThrowsErrorAsync(
            try await service.chat(request: request(), config: config(kind: .anthropicClaude), apiKey: "sk-test")
        ) { error in
            XCTAssertEqual(error as? AICompanionChatServiceError, .providerUnsupported)
        }

        await XCTAssertThrowsErrorAsync(
            try await service.chat(request: request(), config: config(), apiKey: " ")
        ) { error in
            XCTAssertEqual(error as? AICompanionChatServiceError, .notConfigured)
        }
    }

    func testProfileCommandParserExtractsNameAndAvatar() {
        let patch = AICompanionProfileCommandParser.parse("你以后叫蓝蓝，你长得像一只会发光的蓝色小龙。")

        XCTAssertEqual(patch?.name, "蓝蓝")
        XCTAssertEqual(patch?.avatarDescription, "你长得像一只会发光的蓝色小龙")
    }

    func testProfileCommandParserExtractsVoiceAndPersonality() {
        let patch = AICompanionProfileCommandParser.parse(
            "你以后叫闪闪，声音要更活泼，性格像小教练，你长得像一只黄色小机器人。"
        )

        XCTAssertEqual(patch?.name, "闪闪")
        XCTAssertEqual(patch?.voice, .bright)
        XCTAssertEqual(patch?.personality, .playfulCoach)
        XCTAssertEqual(patch?.avatarDescription, "你长得像一只黄色小机器人")
    }

    func testProfileCoachExampleExercisesFullProfileParser() {
        let patch = AICompanionProfileCommandParser.parse(AICompanionProfileCoachCopy.exampleCommand)

        XCTAssertEqual(patch?.name, "闪闪")
        XCTAssertEqual(patch?.voice, .bright)
        XCTAssertEqual(patch?.personality, .playfulCoach)
        XCTAssertEqual(patch?.avatarDescription, "你长得像一只黄色小机器人")
    }

    func testProfileCoachCopyGuidesPreReadersWithoutHomeworkAnswerPromise() {
        XCTAssertTrue(AICompanionProfileCoachCopy.instruction.contains("小喇叭"))
        XCTAssertTrue(AICompanionProfileCoachCopy.instruction.contains("麦克风"))
        XCTAssertTrue(AICompanionProfileCoachCopy.speakText.contains(AICompanionProfileCoachCopy.exampleCommand))
        XCTAssertFalse(AICompanionProfileCoachCopy.speakText.contains("答案"))
    }

    func testMediaConsentCopyExplainsSameChatAndNoAutomaticUpload() {
        let enabled = AICompanionMediaConsentCopy.setupExplanation(imagesEnabled: true)
        let disabled = AICompanionMediaConsentCopy.setupExplanation(imagesEnabled: false)
        let queued = AICompanionMediaConsentCopy.queued(source: .camera, imagesEnabled: true)

        XCTAssertTrue(enabled.contains("同一条聊天"))
        XCTAssertTrue(enabled.contains("只有点发送后"))
        XCTAssertTrue(enabled.contains("本机安全检查"))
        XCTAssertTrue(disabled.contains("不会上传图片"))
        XCTAssertTrue(AICompanionMediaConsentCopy.imagePermissionNeeded.contains("家长还没允许图片发给 AI"))
        XCTAssertTrue(queued.contains("点发送后 AI 才能看图"))
        XCTAssertFalse(enabled.contains("自动发给云端"))
        XCTAssertFalse(disabled.contains("自动发给云端"))
    }

    func testProfileCommandParserDoesNotTreatCasualMoodAsProfileChange() {
        XCTAssertNil(AICompanionProfileCommandParser.parse("我今天很活泼，想聊恐龙。"))
    }
}

final class ParentAICompanionCoachServiceTests: XCTestCase {
    private func parentRequest(latestText: String) -> ParentAICompanionCoachRequest {
        let childId = UUID()
        return ParentAICompanionCoachRequest(
            childName: "Sam",
            childAge: 8,
            latestText: latestText,
            childMemory: AICompanionMemoryDigest(
                childId: childId,
                updatedAt: Date(),
                companionName: "星星伙伴",
                companionAvatarDescription: "会发光的小星星",
                personalityLabel: "耐心引导型",
                conversationCount: 6,
                interests: ["恐龙", "电子设备"],
                preferences: ["喜欢先被鼓励"],
                learningNotes: ["识字还需要慢一点"],
                emotionalNotes: ["睡前容易烦躁"],
                homeworkGuidanceNotes: ["不能直接给答案"],
                latestSummary: "孩子最近用图片问电子设备，也在尝试阅读。"
            ),
            growthProfileSummary: "阅读：完成恐龙书 10 分钟；视频：学习自然科学；测验：识字题正确率 70%",
            childRecentContextLines: ["child: 不对，你在网上找找呢", "companion: 我不能联网，但可以继续看图。"],
            parentMemory: .empty(childId: childId),
            parentRecentContextLines: [],
            activeTasksSummary: "- 睡前阅读：待开始，10 成长积分",
            rewardSummary: "可用成长积分 20；愿望清单：恐龙书"
        )
    }

    func testPromptUsesChildMemoryGrowthAndParentQuestion() {
        let service = ParentAICompanionCoachService()
        let childId = UUID()
        let childMemory = AICompanionMemoryDigest(
            childId: childId,
            updatedAt: Date(),
            companionName: "闪闪",
            companionAvatarDescription: "黄色小机器人",
            personalityLabel: "活泼教练型",
            conversationCount: 8,
            interests: ["恐龙"],
            preferences: ["喜欢先听鼓励"],
            learningNotes: ["识字需要慢一点"],
            emotionalNotes: ["晚睡时容易烦躁"],
            homeworkGuidanceNotes: ["只给提示，不给答案"],
            latestSummary: "孩子最近对阅读和恐龙感兴趣"
        )
        let parentMemory = ParentAICompanionCoachMemoryDigest(
            childId: childId,
            updatedAt: Date(),
            conversationCount: 2,
            parentGoals: ["减少短视频冲突"],
            usefulStrategies: ["先共情再约定小步骤"],
            boundaryNotes: ["不用羞辱推动孩子"],
            latestSummary: "家长想调整睡前节奏"
        )
        let request = ParentAICompanionCoachRequest(
            childName: "乐乐",
            childAge: 8,
            latestText: "今晚怎么让孩子少刷短视频？",
            childMemory: childMemory,
            growthProfileSummary: "growth_event_count=3\n阅读进展：读了恐龙书",
            childRecentContextLines: ["child: 我想聊恐龙"],
            parentMemory: parentMemory,
            parentRecentContextLines: ["parent: 昨天沟通时孩子哭了"],
            activeTasksSummary: "- 整理书包：待开始，10 成长积分",
            rewardSummary: "可用成长积分 20，愿望：恐龙书"
        )

        XCTAssertTrue(request.isProviderRequestAllowed)
        let system = service.systemPrompt(request)
        let user = service.userPrompt(request)

        XCTAssertTrue(system.contains("parent AI coach"))
        XCTAssertTrue(system.contains("Do not expose or reconstruct"))
        XCTAssertTrue(system.contains("Do not output JSON"))
        XCTAssertTrue(user.contains("companion_name=闪闪"))
        XCTAssertTrue(user.contains("growth_event_count=3"))
        XCTAssertTrue(user.contains("今晚怎么让孩子少刷短视频？"))
        XCTAssertTrue(user.contains("可用成长积分 20"))
        XCTAssertFalse(user.contains("sk-test"))
    }

    func testParentCoachRespectsEnglishInterfaceAndImageContext() {
        var request = parentRequest(latestText: "How should I respond tonight?")
        request.language = .english
        request.attachmentSummaries = ["The parent selected a picture for context."]

        let service = ParentAICompanionCoachService()
        XCTAssertTrue(service.systemPrompt(request).contains("parent-facing English"))
        XCTAssertTrue(service.userPrompt(request).contains("parent selected a picture"))
        XCTAssertTrue(service.localTurn(request: request).reply.contains("Start"))
    }

    func testParseTurnExtractsReplyAndParentMemory() throws {
        let service = ParentAICompanionCoachService()
        let raw = """
        {"reply":"今晚先把目标改成：刷牙后读五分钟恐龙书，再决定是否兑换屏幕时间。","parent_memory_updates":{"parent_goals":["减少短视频冲突"],"useful_strategies":["把要求拆成一个五分钟动作"],"boundary_notes":["不把屏幕时间当威胁"],"summary":"家长尝试用阅读替代短视频"}}
        """

        let turn = try service.parseTurn(raw)
        XCTAssertTrue(turn.providerUsed)
        XCTAssertTrue(turn.reply.contains("恐龙书"))
        XCTAssertEqual(turn.memoryUpdate.parentGoals, ["减少短视频冲突"])
        XCTAssertEqual(turn.memoryUpdate.usefulStrategies, ["把要求拆成一个五分钟动作"])
        XCTAssertEqual(turn.memoryUpdate.summary, "家长尝试用阅读替代短视频")
    }

    func testUnsafeParentCoachRequestIsBlocked() {
        let childId = UUID()
        let request = ParentAICompanionCoachRequest(
            childName: "乐乐",
            childAge: 8,
            latestText: "帮我保存 api_key sk-test-secret",
            childMemory: .empty(
                childId: childId,
                companionName: "星星伙伴",
                companionAvatarDescription: "小星星",
                personalityLabel: "耐心引导型"
            ),
            growthProfileSummary: "",
            childRecentContextLines: [],
            parentMemory: .empty(childId: childId),
            parentRecentContextLines: [],
            activeTasksSummary: "",
            rewardSummary: ""
        )

        XCTAssertFalse(request.isProviderRequestAllowed)
    }

    func testLocalTurnVariesByParentIntent() {
        let service = ParentAICompanionCoachService()

        let capabilities = service.localTurn(request: parentRequest(latestText: "你能做什么"))
        let status = service.localTurn(request: parentRequest(latestText: "告诉我 Sam 现况如何"))
        let rewards = service.localTurn(request: parentRequest(latestText: "任务和积分奖励怎么安排"))

        XCTAssertNotEqual(capabilities.reply, status.reply)
        XCTAssertNotEqual(status.reply, rewards.reply)
        XCTAssertTrue(capabilities.reply.contains("四件事"))
        XCTAssertTrue(status.reply.contains("本机摘要"))
        XCTAssertTrue(rewards.reply.contains("任务和奖励"))
        XCTAssertFalse(status.reply.contains("companion_name="))
        XCTAssertFalse(status.reply.contains("growth_event_count="))
        XCTAssertFalse(status.reply.contains("ai_chat_summary="))
    }

    func testParentPlainCloudReplyIsAcceptedWhenProviderIgnoresJSONFormat() throws {
        let service = ParentAICompanionCoachService()

        let turn = try service.parseTurn("先共情孩子丢失感，再把今晚目标缩成一个 5 分钟动作：一起选一本书读两页。")

        XCTAssertTrue(turn.providerUsed)
        XCTAssertTrue(turn.reply.contains("先共情"))
        XCTAssertEqual(turn.memoryUpdate.summary, "")
    }

    func testParentLooseReplyIsAcceptedFromMalformedJSONLikeProviderOutput() throws {
        let service = ParentAICompanionCoachService()

        let turn = try service.parseTurn(#"{reply: "先问孩子今天最难开始的是哪件事，再一起选一个五分钟动作。", parent_memory_updates: {}}"#)

        XCTAssertTrue(turn.providerUsed)
        XCTAssertTrue(turn.reply.contains("五分钟动作"))
        XCTAssertFalse(turn.reply.contains("parent_memory_updates"))
    }

    func testParentInternalMemoryEchoIsRejected() {
        let service = ParentAICompanionCoachService()

        XCTAssertThrowsError(
            try service.parseTurn("companion_name=星星伙伴 conversation_count=10 growth_event_count=7")
        ) { error in
            XCTAssertEqual(error as? ParentAICompanionCoachError, .unsafeResponse)
        }
    }

    func testCloudFailureLocalTurnDoesNotPolluteUsefulStrategies() {
        let service = ParentAICompanionCoachService()

        let fallback = service.localTurn(
            request: parentRequest(latestText: "告诉我 Sam 现况如何"),
            shouldRecordStrategy: false
        )

        XCTAssertFalse(fallback.providerUsed)
        XCTAssertTrue(fallback.memoryUpdate.usefulStrategies.isEmpty)
        XCTAssertTrue(fallback.memoryUpdate.parentGoals.isEmpty)
        XCTAssertTrue(fallback.memoryUpdate.summary.contains("未写入长期策略"))
    }
}

private actor CompanionRecordingChatClient: AICompanionChatCompleting {
    struct Captured: Equatable {
        var system: String = ""
        var user: String = ""
        var apiKey: String = ""
        var imageCount: Int = 0
        var callCount: Int = 0
    }

    private let result: Result<String, AIChatError>
    private var captured = Captured()

    init(result: Result<String, AIChatError>) {
        self.result = result
    }

    func complete(
        system: String,
        user: String,
        imageAttachments: [AICompanionImageAttachment],
        config: AIProviderConfig,
        apiKey: String
    ) async throws -> String {
        captured.system = system
        captured.user = user
        captured.apiKey = apiKey
        captured.imageCount = imageAttachments.count
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
