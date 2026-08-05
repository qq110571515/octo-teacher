import XCTest
@testable import OctoTeacher

/// AI 证明初评接入家长审批流：提交即有本地确定性初评，批准仍由家长手动触发，
/// 初评绝不泄露照片文件名/路径。
@MainActor
final class AIProofLocalReviewTests: XCTestCase {

    private func makeSubmittedReadingAssignment(store: LocalFamilyStore, text: String) -> TaskAssignment {
        let assignment = store.assignNewTask(
            title: "读《夏洛的网》",
            instructions: "读完说说讲了什么。",
            category: .learning,
            rewardMinutes: 15,
            requiredProof: .text,
            reading: ReadingSpec(bookTitle: "夏洛的网", minMinutes: 15, chapterPlanText: "第 1-2 章")
        )!
        store.submit(assignment, text: text)
        return store.assignments.first { $0.id == assignment.id }!
    }

    func testSubmitGeneratesLocalReviewWithoutApproving() {
        let store = LocalFamilyStore()
        let rewardsBefore = store.rewards.count
        let submitted = makeSubmittedReadingAssignment(store: store, text: "我读了夏洛的网第一章，蜘蛛帮小猪威尔伯。")

        let review = submitted.aiReview
        XCTAssertNotNil(review, "提交后应立即生成本地初评")
        XCTAssertEqual(review?.source, "local_rule")
        XCTAssertEqual(submitted.status, .submitted, "初评绝不自动批准")
        XCTAssertEqual(store.rewards.count, rewardsBefore, "初评绝不发放成长积分")
    }

    func testApproveStillRequiresManualParentAction() {
        let store = LocalFamilyStore()
        let submitted = makeSubmittedReadingAssignment(store: store, text: "我读了夏洛的网，写了很多细节的说明内容。")
        XCTAssertEqual(submitted.status, .submitted)

        let grant = store.approve(submitted)
        XCTAssertNotNil(grant, "家长手动批准后才发放成长积分")
        XCTAssertEqual(store.assignments.first { $0.id == submitted.id }?.status, .approved)
    }

    func testLocalReviewIsDeterministic() {
        let task = TaskTemplate(
            id: UUID(), title: "整理书桌", category: .home, difficulty: .easy,
            rewardMinutes: 10, instructions: "", requiredProof: .photo
        )
        let a = AIProofReviewer.localReview(task: task, childText: "整理好了", proofKind: .photo, hasLocalPhoto: true)
        let b = AIProofReviewer.localReview(task: task, childText: "整理好了", proofKind: .photo, hasLocalPhoto: true)
        XCTAssertEqual(a, b, "同样输入必须得到同样初评，便于测试")
    }

    func testLocalReviewNeverLeaksPhotoFileNameOrPath() {
        let store = LocalFamilyStore()
        let assignment = store.assignNewTask(
            title: "打扫房间",
            instructions: "拍照给爸妈看。",
            category: .home,
            rewardMinutes: 10,
            requiredProof: .photo
        )!
        let photoName = "secret-photo-abc123.jpg"
        store.submit(
            assignment,
            proof: ProofDraft(kind: .photo, text: "", photoPlaceholderName: nil, photoFileName: photoName, status: .drafting)
        )

        let review = store.assignments.first { $0.id == assignment.id }?.aiReview
        XCTAssertNotNil(review)
        XCTAssertFalse(review!.summary.contains(photoName), "初评不得泄露照片文件名")
        XCTAssertFalse(review!.summary.contains("proof-photos"), "初评不得泄露照片路径")
        XCTAssertTrue(review!.summary.contains("仅供参考"))
    }

    func testMissingPhotoLowersConfidenceAndDefersToParent() {
        let task = TaskTemplate(
            id: UUID(), title: "浇花", category: .home, difficulty: .easy,
            rewardMinutes: 5, instructions: "", requiredProof: .photo
        )
        let review = AIProofReviewer.localReview(task: task, childText: "", proofKind: .photo, hasLocalPhoto: false)
        XCTAssertEqual(review.recommendation, "needs_parent_judgment")
        XCTAssertLessThan(review.confidence, 0.5)
    }
}
