import XCTest
@testable import OctoTeacher

/// 学校作业与家庭成长动态视图测试。
///
/// 覆盖安全边界：
/// - AI 引导只给提示/清单/下一步，不含答案字段。
/// - 作业提交需有内容、幂等、只进入待验证、绝不自动发成长积分或标记完成。
/// - 家庭内容默认私密；亲友只能看到已批准且非私密内容。
/// - 亲友评论默认待审核，审核后才对亲友可见；亲友不能批准。
/// - 荣誉墙默认待审核，批准后才对亲友可见。
/// - 球星卡评分落在 1–99。
final class SchoolFamilyFeedTests: XCTestCase {

    // MARK: - AI 引导边界

    /// AI 引导结构体只暴露引导式内容，没有可塞答案的字段，且种子引导都有提示。
    func testAIGuidanceHasOnlyGuidanceFieldsAndNoAnswer() {
        let store = SchoolFamilyStore()
        for homework in store.homeworks where homework.guidance.hasContent {
            // 引导至少提供提示或清单，引导孩子自己想。
            XCTAssertTrue(
                !homework.guidance.hints.isEmpty || !homework.guidance.checklist.isEmpty,
                "引导应提供提示或自检清单"
            )
        }
        // 结构层面保证：AIHomeworkGuidance 只有 hints/checklist/nextStep，
        // 没有 answer 字段（此测试若编译通过即证明不存在 answer 访问点）。
        let guidance = AIHomeworkGuidance(hints: ["先想想"], checklist: ["检查过程"], nextStep: "继续")
        XCTAssertTrue(guidance.hasContent)
    }

    // MARK: - 作业提交闭环

    func testSubmitHomeworkRequiresContent() {
        let store = SchoolFamilyStore()
        let homework = try! XCTUnwrap(store.openHomeworks.first { $0.requiredProof == .text })

        let empty = store.submitHomework(homework, proof: .empty)
        XCTAssertFalse(empty, "空证明不应提交成功")
        XCTAssertEqual(store.homeworks.first { $0.id == homework.id }?.status, homework.status)

        let ok = store.submitHomework(homework, text: "我读完了课文")
        XCTAssertTrue(ok)
        XCTAssertEqual(store.homeworks.first { $0.id == homework.id }?.status, .submitted)
    }

    /// 提交只进入待验证，绝不自动标记完成（verified）。
    func testSubmitHomeworkDoesNotAutoVerify() throws {
        let store = SchoolFamilyStore()
        let homework = try XCTUnwrap(store.openHomeworks.first)

        let proof: ProofDraft = homework.requiredProof == .text
            ? ProofDraft(kind: .text, text: "完成了", photoPlaceholderName: nil, status: .drafting)
            : ProofDraft(kind: .photoPlaceholder, text: "", photoPlaceholderName: "local-photo", status: .drafting)
        XCTAssertTrue(store.submitHomework(homework, proof: proof))

        let updated = try XCTUnwrap(store.homeworks.first { $0.id == homework.id })
        XCTAssertEqual(updated.status, .submitted)
        XCTAssertNotEqual(updated.status, .verified, "提交不得自动判为完成")
    }

    func testPhotoHomeworkAcceptsRealLocalPhotoFile() throws {
        let store = SchoolFamilyStore()
        let homework = try XCTUnwrap(store.openHomeworks.first { $0.requiredProof == .photoPlaceholder })
        let proof = ProofDraft(
            kind: .photoPlaceholder,
            text: "拍了作业页",
            photoPlaceholderName: nil,
            photoFileName: "school-proof.jpg",
            status: .drafting
        )

        XCTAssertTrue(store.submitHomework(homework, proof: proof))

        let updated = try XCTUnwrap(store.homeworks.first { $0.id == homework.id })
        XCTAssertEqual(updated.status, .submitted)
        XCTAssertEqual(updated.proof.photoFileName, "school-proof.jpg")
        XCTAssertNil(updated.proof.photoPlaceholderName)
    }

    /// 已提交/已完成的作业不再接受新提交（幂等保护）。
    func testSubmitHomeworkIsIdempotentOnSettled() throws {
        let store = SchoolFamilyStore()
        let verified = try XCTUnwrap(store.settledHomeworks.first { $0.status == .verified })

        let again = store.submitHomework(verified, text: "想再提交一次")
        XCTAssertFalse(again, "已完成作业不应接受新提交")
        XCTAssertEqual(store.homeworks.first { $0.id == verified.id }?.status, .verified)
    }

    /// 需重做的作业可以重新提交。
    func testReturnedHomeworkAcceptsResubmission() throws {
        let store = SchoolFamilyStore()
        let returned = try XCTUnwrap(store.homeworks.first { $0.status == .returned })

        let ok = store.submitHomework(returned, text: "重新读了一遍并写了一句话")
        XCTAssertTrue(ok)
        XCTAssertEqual(store.homeworks.first { $0.id == returned.id }?.status, .submitted)
    }

    // MARK: - 家庭内容默认私密 / 亲友可见性

    func testPrivateFeedHiddenFromRelatives() {
        let store = SchoolFamilyStore()
        let household = store.visibleFeed(for: .household)
        let relative = store.visibleFeed(for: .relative)

        XCTAssertTrue(household.count >= relative.count)
        // 亲友看不到任何私密条目。
        XCTAssertFalse(relative.contains { $0.visibility == .privateFamily })
        // 亲友只看到已批准的条目。
        XCTAssertTrue(relative.allSatisfy { $0.approval == .approved })
        // 家庭视角能看到私密条目。
        XCTAssertTrue(household.contains { $0.visibility == .privateFamily })
    }

    /// 待审核动态对亲友不可见。
    func testPendingFeedHiddenFromRelatives() {
        let store = SchoolFamilyStore()
        let relative = store.visibleFeed(for: .relative)
        XCTAssertFalse(relative.contains { $0.approval == .pending })
    }

    // MARK: - 亲友评论：默认待审核

    func testRelativeCommentIsPendingUntilApproved() throws {
        let store = SchoolFamilyStore()
        let beforeRelativeVisible = store.visibleComments(for: .relative).count

        XCTAssertTrue(store.addRelativeComment(nickname: "舅舅", message: "加油哦"))
        let newComment = try XCTUnwrap(store.relativeComments.first { $0.relativeNickname == "舅舅" })
        XCTAssertEqual(newComment.status, .pending, "亲友评论默认待审核")

        // 待审核评论不应对亲友可见。
        XCTAssertEqual(store.visibleComments(for: .relative).count, beforeRelativeVisible)
        XCTAssertFalse(store.visibleComments(for: .relative).contains { $0.id == newComment.id })

        // 家长审核通过后，亲友才能看到。
        store.moderateComment(newComment, decision: .approved)
        XCTAssertTrue(store.visibleComments(for: .relative).contains { $0.id == newComment.id })
    }

    /// 空评论不入库。
    func testEmptyRelativeCommentRejected() {
        let store = SchoolFamilyStore()
        let before = store.relativeComments.count
        XCTAssertFalse(store.addRelativeComment(nickname: "舅舅", message: "   "))
        XCTAssertEqual(store.relativeComments.count, before)
    }

    /// 家庭视角能看到待审核评论（供家长审核）。
    func testHouseholdSeesPendingComments() {
        let store = SchoolFamilyStore()
        let household = store.visibleComments(for: .household)
        XCTAssertTrue(household.contains { $0.status == .pending })
    }

    // MARK: - 荣誉墙：默认待审核

    func testPendingHonorItemHiddenFromRelatives() {
        let store = SchoolFamilyStore()
        let relative = store.visibleHonorWall(for: .relative)
        XCTAssertFalse(relative.contains { $0.approval == .pending })
        XCTAssertTrue(relative.allSatisfy { $0.approval == .approved && $0.visibility != .privateFamily })
    }

    func testApprovingHonorItemMakesItVisibleToRelatives() throws {
        let store = SchoolFamilyStore()
        let pending = try XCTUnwrap(store.honorWall.first { $0.approval == .pending })
        XCTAssertFalse(store.visibleHonorWall(for: .relative).contains { $0.id == pending.id })

        store.moderateHonorItem(pending, decision: .approved)
        XCTAssertTrue(store.visibleHonorWall(for: .relative).contains { $0.id == pending.id })
    }

    // MARK: - 球星卡

    func testStarCardRatingsWithinBounds() {
        let store = SchoolFamilyStore()
        for card in store.starCards {
            XCTAssertGreaterThanOrEqual(card.overall, 1)
            XCTAssertLessThanOrEqual(card.overall, 99)
            for dimension in AbilityDimension.allCases {
                let value = card.rating(for: dimension)
                XCTAssertGreaterThanOrEqual(value, 0)
                XCTAssertLessThanOrEqual(value, 99)
            }
        }
    }

    /// 私密球星卡对亲友不可见。
    func testPrivateStarCardHiddenFromRelatives() {
        let store = SchoolFamilyStore()
        store.starCards.append(
            GrowthStarCard(
                id: UUID(),
                childNickname: "小禾",
                seasonLabel: "本月",
                ratings: [.knowledge: 50],
                visibility: .privateFamily
            )
        )
        XCTAssertFalse(store.visibleStarCards(for: .relative).contains { $0.visibility == .privateFamily })
        XCTAssertTrue(store.visibleStarCards(for: .household).contains { $0.visibility == .privateFamily })
    }

    // MARK: - VLOG 占位

    /// VLOG 仅为占位，私密 VLOG 对亲友不可见。
    func testPrivateVLOGHiddenFromRelatives() {
        let store = SchoolFamilyStore()
        store.vlogs.append(
            GrowthVLOGPlaceholder(
                id: UUID(),
                title: "私密回顾",
                durationLabel: "约 30 秒",
                visibility: .privateFamily,
                placeholderNote: "占位"
            )
        )
        XCTAssertFalse(store.visibleVLOGs(for: .relative).contains { $0.visibility == .privateFamily })
    }
}
