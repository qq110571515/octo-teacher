import XCTest
@testable import OctoTeacher

final class AICompanionVoiceComposerTests: XCTestCase {
    func testTranscriptionMergesIntoDraftWithoutAutoSending() {
        XCTAssertEqual(
            AICompanionVoiceComposer.mergedDraft(existingDraft: "帮我看看图片", transcript: "这里是什么？"),
            "帮我看看图片 这里是什么？"
        )
        XCTAssertEqual(
            AICompanionVoiceComposer.mergedDraft(existingDraft: "   ", transcript: "我想问这个图"),
            "我想问这个图"
        )
        XCTAssertEqual(
            AICompanionVoiceComposer.mergedDraft(existingDraft: "保留原文", transcript: "  "),
            "保留原文"
        )
    }

    func testFeedbackExplainsImageAndVoiceWillSendTogether() {
        let feedback = AICompanionVoiceComposer.successFeedback(companionName: "星星", hasPendingImages: true)
        XCTAssertTrue(feedback.contains("同一条消息"))
        XCTAssertTrue(feedback.contains("星星"))
    }
}
