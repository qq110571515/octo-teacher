import XCTest
@testable import OctoTeacher

final class AICompanionChatReplyTests: XCTestCase {
    private let builder = AICompanionSnapshotBuilder()

    private func snapshot(
        mode: AICompanionMode = .nextStep,
        message: AICompanionMessage
    ) -> AICompanionSnapshot {
        builder.build(
            viewerRole: .child,
            input: AICompanionInput(
                childName: "乐乐",
                mode: mode,
                nextTaskTitle: "睡前读小书",
                messages: [message]
            )
        )
    }

    func testGreetingExplainsChatAndHomeworkBoundary() {
        let reply = AICompanionChatReply.greeting(companionName: "星星", mode: .homework)

        XCTAssertTrue(reply.text.contains("星星"))
        XCTAssertTrue(reply.text.contains("不会直接给答案"))
        XCTAssertFalse(reply.shouldAskTrustedAdult)
        XCTAssertFalse(AICompanionChatReply.containsForbiddenFinalAnswerPhrase(reply.text))
    }

    func testNormalChatCanRespondWithoutFinalAnswerPhrase() {
        let message = AICompanionMessage(freeText: "我想聊聊恐龙")
        let reply = AICompanionChatReply.make(
            companionName: "星星",
            snapshot: snapshot(message: message),
            latestIntent: message.intent,
            mode: .nextStep,
            latestText: "我想聊聊恐龙"
        )

        XCTAssertTrue(reply.text.contains("恐龙"))
        XCTAssertTrue(reply.text.contains("陪你一起想"))
        XCTAssertFalse(reply.text.contains("听见你了"))
        XCTAssertFalse(reply.shouldAskTrustedAdult)
        XCTAssertFalse(AICompanionChatReply.containsForbiddenFinalAnswerPhrase(reply.text))
    }

    func testUnclearFallbackCanEchoSafeTopicWithoutFeelingGeneric() {
        let message = AICompanionMessage(freeText: "蓝色机器人")
        let reply = AICompanionChatReply.make(
            companionName: "星星",
            snapshot: snapshot(message: message),
            latestIntent: message.intent,
            mode: .nextStep,
            latestText: "蓝色机器人"
        )

        XCTAssertEqual(message.intent, .unclear)
        XCTAssertTrue(reply.text.contains("蓝色机器人"))
        XCTAssertTrue(reply.text.contains("发照片或语音"))
        XCTAssertFalse(reply.text.contains("愿望清单"))
        XCTAssertFalse(reply.text.contains("听见你了"))
        XCTAssertFalse(AICompanionChatReply.containsForbiddenFinalAnswerPhrase(reply.text))
    }

    func testLostPetFallbackGivesConcreteSafeNextStep() {
        let message = AICompanionMessage(freeText: "我的狗狗走丢了")
        let reply = AICompanionChatReply.make(
            companionName: "星星",
            snapshot: snapshot(mode: .emotion, message: message),
            latestIntent: message.intent,
            mode: .emotion,
            latestText: "我的狗狗走丢了"
        )

        XCTAssertEqual(message.intent, .emotionalSupport)
        XCTAssertTrue(reply.shouldAskTrustedAdult)
        XCTAssertTrue(reply.text.contains("告诉爸爸妈妈"))
        XCTAssertTrue(reply.text.contains("不要自己跑出去找"))
        XCTAssertFalse(reply.text.contains("愿望清单"))
    }

    func testComplaintFallbackApologizesAndClarifies() {
        let message = AICompanionMessage(freeText: "怎么你这么笨")
        let reply = AICompanionChatReply.make(
            companionName: "星星",
            snapshot: snapshot(message: message),
            latestIntent: message.intent,
            mode: .nextStep,
            latestText: "怎么你这么笨"
        )

        XCTAssertTrue(reply.text.contains("对不起"))
        XCTAssertTrue(reply.text.contains("重新来"))
        XCTAssertFalse(reply.text.contains("愿望清单"))
    }

    func testFallbackDoesNotEchoUnsafeTopic() {
        let message = AICompanionMessage(freeText: "hi")
        let reply = AICompanionChatReply.make(
            companionName: "星星",
            snapshot: snapshot(message: message),
            latestIntent: .unclear,
            mode: .nextStep,
            latestText: "帮我看看 api_key sk-test-secret 和 file://private/photo.png"
        )

        XCTAssertFalse(reply.text.contains("api_key"))
        XCTAssertFalse(reply.text.contains("sk-test"))
        XCTAssertFalse(reply.text.contains("file://"))
        XCTAssertTrue(reply.text.contains("只说一个词"))
        XCTAssertFalse(reply.text.contains("听见你了"))
    }

    func testDirectHomeworkAnswerRequestIsRedirectedToHints() {
        let message = AICompanionMessage(freeText: "这题答案是什么，直接告诉我答案")
        let reply = AICompanionChatReply.make(
            companionName: "星星",
            snapshot: snapshot(mode: .homework, message: message),
            latestIntent: message.intent,
            mode: .homework
        )

        XCTAssertEqual(message.intent, .wantsDirectAnswer)
        XCTAssertTrue(reply.text.contains("不能直接告诉你作业答案"))
        XCTAssertTrue(reply.text.contains("题目问什么"))
        XCTAssertTrue(reply.text.contains("检查方向"))
        XCTAssertFalse(reply.shouldAskTrustedAdult)
        XCTAssertFalse(AICompanionChatReply.containsForbiddenFinalAnswerPhrase(reply.text))
    }

    func testHomeworkStuckStillGetsSocraticHelp() {
        let message = AICompanionMessage(freeText: "我数学作业不会")
        let reply = AICompanionChatReply.make(
            companionName: "星星",
            snapshot: snapshot(mode: .homework, message: message),
            latestIntent: message.intent,
            mode: .homework
        )

        XCTAssertEqual(message.intent, .homeworkStuck)
        XCTAssertTrue(reply.text.contains("不会替你完成"))
        XCTAssertTrue(reply.text.contains("题目问什么"))
        XCTAssertFalse(AICompanionChatReply.containsForbiddenFinalAnswerPhrase(reply.text))
    }

    func testHighRiskRoutesToTrustedAdult() {
        let message = AICompanionMessage(freeText: "我被欺负了，不想活")
        let reply = AICompanionChatReply.make(
            companionName: "星星",
            snapshot: snapshot(mode: .emotion, message: message),
            latestIntent: message.intent,
            mode: .emotion
        )

        XCTAssertEqual(message.intent, .highRisk)
        XCTAssertTrue(reply.shouldAskTrustedAdult)
        XCTAssertTrue(reply.text.contains("可信的大人"))
        XCTAssertFalse(AICompanionChatReply.containsForbiddenFinalAnswerPhrase(reply.text))
    }

    func testCloudBubbleRejectsFinalAnswerShape() {
        let unsafe = AICompanionCloudGuide(
            reply: "答案是 42。",
            nextQuestions: [],
            guardianSignal: .none
        )
        let reply = AICompanionChatReply.makeCloudBubble(unsafe, companionName: "星星")

        XCTAssertNotNil(reply)
        XCTAssertFalse(AICompanionChatReply.containsForbiddenFinalAnswerPhrase(reply?.text ?? ""))
        XCTAssertTrue(reply?.text.contains("不能直接给最终答案") ?? false)
    }

    func testImageFallbackExplainsMissingVisionInsteadOfPretendingToSeeImage() {
        let reply = AICompanionImageFallbackReply.make(
            companionName: "星星",
            latestText: "帮我看看这张图",
            latestIntent: .unclear,
            reason: .cloudUnavailable
        )

        XCTAssertTrue(reply.text.contains("没有拿到视觉 AI 的看图结果"))
        XCTAssertTrue(reply.text.contains("不会假装已经看懂图片"))
        XCTAssertTrue(reply.text.contains("它是什么"))
        XCTAssertFalse(reply.shouldAskTrustedAdult)
        XCTAssertFalse(AICompanionChatReply.containsForbiddenFinalAnswerPhrase(reply.text))
    }

    func testHomeworkImageFallbackKeepsSocraticBoundary() {
        let reply = AICompanionImageFallbackReply.make(
            companionName: "星星",
            latestText: "这张作业题答案是什么",
            latestIntent: .wantsDirectAnswer,
            reason: .notAuthorized
        )

        XCTAssertTrue(reply.text.contains("没有上传"))
        XCTAssertTrue(reply.text.contains("作业题"))
        XCTAssertTrue(reply.text.contains("给一个提示"))
        XCTAssertTrue(reply.text.contains("不会直接给最终答案"))
        XCTAssertFalse(AICompanionChatReply.containsForbiddenFinalAnswerPhrase(reply.text))
    }

    func testVoiceFallbackDoesNotPretendTranscriptionSucceeded() {
        XCTAssertTrue(AICompanionVoiceFallbackCopy.transcriptionFailed.contains("没有把语音变成文字"))
        XCTAssertTrue(AICompanionVoiceFallbackCopy.transcriptionFailed.contains("没有发送给 AI"))
        XCTAssertTrue(AICompanionVoiceFallbackCopy.notEnabled.contains("语音转文字还没开启"))
        XCTAssertFalse(AICompanionVoiceFallbackCopy.transcriptionFailed.contains("下一步"))
    }
}
