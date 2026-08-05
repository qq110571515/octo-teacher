import XCTest
@testable import OctoTeacher

final class AICompanionMemoryStoreTests: XCTestCase {
    func testMemoryStorePersistsCompactDigestWithoutRawTranscript() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("octoteacher-memory-\(UUID().uuidString)", isDirectory: true)
        let persistence = FileAICompanionMemoryPersistence(directory: directory)
        let store = AICompanionMemoryStore(persistence: persistence)
        let childId = UUID()

        store.apply(
            AICompanionMemoryUpdate(
                interests: ["恐龙"],
                preferences: ["喜欢蓝色星星伙伴"],
                learningNotes: ["数学题先圈条件"],
                emotionalNotes: ["紧张时先慢慢说事实"],
                homeworkGuidanceNotes: ["不给最终答案"],
                summary: "孩子喜欢聊恐龙，作业需要分步骤提示"
            ),
            childId: childId,
            companionName: "蓝蓝",
            avatarDescription: "一只蓝色星星小龙",
            personalityLabel: "活泼教练型"
        )

        let restored = AICompanionMemoryStore(persistence: persistence)
        let digest = restored.digest(
            for: childId,
            companionName: "蓝蓝",
            avatarDescription: "一只蓝色星星小龙",
            personalityLabel: "活泼教练型"
        )

        XCTAssertEqual(digest.companionName, "蓝蓝")
        XCTAssertEqual(digest.interests, ["恐龙"])
        XCTAssertEqual(digest.homeworkGuidanceNotes, ["不给最终答案"])
        XCTAssertEqual(digest.conversationCount, 1)
        XCTAssertFalse(digest.storesRawTranscript)
        XCTAssertFalse(digest.promptSummary.contains("api_key"))
    }

    func testLocalMemoryUpdateCapturesHomeworkBoundary() {
        let update = AICompanionMemoryUpdate.local(intent: .wantsDirectAnswer, childText: "直接告诉我答案")

        XCTAssertTrue(update.homeworkGuidanceNotes.contains("只给提示和检查方向，不给最终答案"))
        XCTAssertTrue(update.summary.contains("作业引导"))
    }
}
