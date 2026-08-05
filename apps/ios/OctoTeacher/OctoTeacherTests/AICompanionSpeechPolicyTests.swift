import XCTest
@testable import OctoTeacher

final class AICompanionSpeechPolicyTests: XCTestCase {
    func testCompanionReplyCanBeReadManually() {
        XCTAssertTrue(
            AICompanionSpeechPolicy.canManuallyRead(
                isCompanionMessage: true,
                text: "我们先看题目问了什么。"
            )
        )
        XCTAssertEqual(
            AICompanionSpeechPolicy.utterance(companionName: "小云", text: "我们先做第一步。"),
            "小云：我们先做第一步。"
        )
    }

    func testChildMessageAndThinkingBubbleDoNotShowManualReadButton() {
        XCTAssertFalse(
            AICompanionSpeechPolicy.canManuallyRead(
                isCompanionMessage: false,
                text: "我不会这道题。"
            )
        )
        XCTAssertFalse(
            AICompanionSpeechPolicy.canManuallyRead(
                isCompanionMessage: true,
                text: "星星正在认真想……"
            )
        )
        XCTAssertFalse(
            AICompanionSpeechPolicy.canManuallyRead(
                isCompanionMessage: true,
                text: "   \n  "
            )
        )
    }

    func testCompanionRepliesAreNeverAutoRead() {
        XCTAssertFalse(AICompanionSpeechPolicy.autoReadsCompanionReplies)
        XCTAssertFalse(AICompanionSpeechPolicy.shouldAutoReadReply(inputWasVoice: false))
        XCTAssertTrue(AICompanionSpeechPolicy.shouldAutoReadReply(inputWasVoice: true))
        XCTAssertFalse(AICompanionSpeechPolicy.shouldAutoReadReply(inputWasVoice: true, isSpeechEnabled: false))
    }

    func testManualReadRespectsFamilySpeechSwitch() {
        XCTAssertFalse(
            AICompanionSpeechPolicy.canManuallyRead(
                isCompanionMessage: true,
                text: "我们一步一步来。",
                isSpeechEnabled: false
            )
        )
    }

    func testManualReadControlHasVisibleStartAndStopStates() {
        XCTAssertEqual(AICompanionSpeechPolicy.manualReadControlLabel(isSpeaking: false), "读给我听")
        XCTAssertEqual(AICompanionSpeechPolicy.manualReadControlSystemImage(isSpeaking: false), "speaker.wave.2.circle.fill")
        XCTAssertEqual(AICompanionSpeechPolicy.manualReadControlLabel(isSpeaking: true), "停止朗读")
        XCTAssertEqual(AICompanionSpeechPolicy.manualReadControlSystemImage(isSpeaking: true), "stop.circle.fill")
    }

    func testUtteranceTrimsTextAndFallsBackToDefaultName() {
        XCTAssertEqual(
            AICompanionSpeechPolicy.utterance(companionName: "  ", text: "  我们慢慢来。 \n"),
            "AI 章鱼老师：我们慢慢来。"
        )
    }
}
