import XCTest
@testable import OctoTeacher

final class ChildProofSubmissionEncouragementTests: XCTestCase {

    func testPhotoEncouragementDoesNotLeakFileNameOrPath() {
        let task = TaskTemplate(
            id: UUID(),
            title: "整理书桌",
            category: .home,
            difficulty: .easy,
            rewardMinutes: 10,
            instructions: "拍一张整理后的照片。",
            requiredProof: .photo
        )
        let proof = ProofDraft(
            kind: .photo,
            text: "",
            photoPlaceholderName: nil,
            photoFileName: "private-proof-photo-123.jpg",
            status: .submitted
        )

        let encouragement = ChildProofSubmissionEncouragement.make(task: task, proof: proof, rewardMinutes: 10)
        let text = encouragement.displayValues.joined(separator: " ")

        XCTAssertTrue(text.contains("照片证明"))
        XCTAssertFalse(text.contains("private-proof-photo-123.jpg"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("proof-photos"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("/Users/"))
    }

    func testLearningEncouragementKeepsHomeworkAnswerBoundary() {
        let task = TaskTemplate(
            id: UUID(),
            title: "数学练习",
            category: .school,
            difficulty: .medium,
            rewardMinutes: 15,
            instructions: "完成两道应用题。",
            requiredProof: .text
        )
        let proof = ProofDraft(kind: .text, text: "我做完了两道题。", photoPlaceholderName: nil, status: .submitted)

        let encouragement = ChildProofSubmissionEncouragement.make(task: task, proof: proof, rewardMinutes: 15)
        let text = encouragement.displayValues.joined(separator: " ")

        XCTAssertTrue(text.contains("不会直接给最终答案"))
        XCTAssertFalse(text.contains("答案是"))
        XCTAssertFalse(text.contains("直接给答案"))
    }

    func testEncouragementUsesChildFacingCreditCopy() {
        let task = TaskTemplate(
            id: UUID(),
            title: "阅读 15 分钟",
            category: .learning,
            difficulty: .easy,
            rewardMinutes: 20,
            instructions: "",
            requiredProof: .text,
            reading: ReadingSpec(bookTitle: "小王子", minMinutes: 15, chapterPlanText: "第 1 章")
        )
        let proof = ProofDraft(kind: .text, text: "我读完了第一章。", photoPlaceholderName: nil, status: .submitted)

        let encouragement = ChildProofSubmissionEncouragement.make(task: task, proof: proof, rewardMinutes: 20)
        let text = encouragement.displayValues.joined(separator: " ")

        XCTAssertTrue(text.contains("成长积分"))
        XCTAssertTrue(text.contains("《小王子》"))
        XCTAssertFalse(text.contains("发成长积分"))
        XCTAssertFalse(text.contains("批准"))
        XCTAssertFalse(text.contains("审批"))
    }
}
