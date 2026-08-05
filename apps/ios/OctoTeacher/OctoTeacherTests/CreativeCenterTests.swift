import XCTest
@testable import OctoTeacher

@MainActor
final class CreativeCenterTests: XCTestCase {

    func testCreativeKindsCoverBroadCreationScenes() {
        XCTAssertEqual(CreativeTaskKind.allCases.count, 14)
        XCTAssertTrue(CreativeTaskKind.allCases.contains(.drawing))
        XCTAssertTrue(CreativeTaskKind.allCases.contains(.music))
        XCTAssertTrue(CreativeTaskKind.allCases.contains(.lego))
        XCTAssertTrue(CreativeTaskKind.allCases.contains(.storytelling))
        XCTAssertTrue(CreativeTaskKind.allCases.contains(.scienceMaking))
        XCTAssertTrue(PackType.creativeWorks.supportsCustomTemplates)
        XCTAssertEqual(PackType.creativeWorks.defaultCustomCategory, .creative)
    }

    func testParentCanAssignStructuredCreativeTaskAndChildCenterSeesIt() throws {
        let store = LocalFamilyStore()
        let spec = CreativeTaskSpec(
            kind: .lego,
            creativePrompt: "搭一座能让小车通过的桥。",
            materials: ["乐高零件", "一辆小车"],
            estimatedMinutes: 30
        )
        let assignment = try XCTUnwrap(store.assignNewTask(
            title: "乐高桥梁挑战",
            instructions: "先画计划，再搭桥并让小车通过。",
            category: .creative,
            rewardMinutes: 20,
            requiredProof: .photo,
            creative: spec
        ))

        XCTAssertEqual(assignment.task.creative, spec)
        XCTAssertEqual(assignment.task.category, .creative)
        XCTAssertEqual(assignment.task.requiredProof, .photo)

        let snapshot = CreativeCenterSnapshot.build(
            assignments: store.assignments,
            childId: store.activeChildId
        )
        XCTAssertTrue(snapshot.active.contains { $0.id == assignment.id })
    }

    func testCreativeSubmissionGetsChildFriendlyCompanionFeedbackWithoutAutoApproval() throws {
        let store = LocalFamilyStore()
        let assignment = try XCTUnwrap(store.assignNewTask(
            title: "画一幅太空画",
            instructions: "画完介绍最喜欢的星球。",
            category: .creative,
            rewardMinutes: 20,
            requiredProof: .photo,
            creative: CreativeTaskSpec(
                kind: .drawing,
                creativePrompt: "画一个你想象中的太空世界。",
                materials: ["画纸", "彩笔"],
                estimatedMinutes: 30
            )
        ))

        store.submit(
            assignment,
            proof: ProofDraft(
                kind: .photo,
                text: "我画了一个有蓝色海洋的星球，这是我最喜欢的地方。",
                photoPlaceholderName: nil,
                photoFileName: "local-only-creative.jpg",
                status: .drafting
            )
        )

        let submitted = try XCTUnwrap(store.assignments.first { $0.id == assignment.id })
        XCTAssertEqual(submitted.status, .submitted)
        XCTAssertEqual(submitted.aiReview?.source, "local_rule")
        XCTAssertFalse(submitted.aiReview?.childFeedback?.isEmpty ?? true)
        XCTAssertTrue(CreativeCenterCopy.childFeedback(for: submitted).contains("绘画"))

        let snapshot = CreativeCenterSnapshot.build(
            assignments: store.assignments,
            childId: store.activeChildId
        )
        XCTAssertTrue(snapshot.waitingForParent.contains { $0.id == assignment.id })
    }

    func testLegacyCreativeTaskWithoutSpecStillAppearsInCenter() throws {
        let store = LocalFamilyStore()
        let assignment = try XCTUnwrap(store.assignNewTask(
            title: "旧版手工任务",
            instructions: "完成后拍照。",
            category: .creative,
            rewardMinutes: 10,
            requiredProof: .photo
        ))

        let snapshot = CreativeCenterSnapshot.build(
            assignments: store.assignments,
            childId: store.activeChildId
        )
        XCTAssertTrue(snapshot.active.contains { $0.id == assignment.id })
        XCTAssertEqual(CreativeCenterCopy.kind(for: assignment.task), .handcraft)
    }
}
