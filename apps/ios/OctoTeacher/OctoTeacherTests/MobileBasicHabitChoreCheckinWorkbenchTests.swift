import XCTest
@testable import OctoTeacher

final class MobileBasicHabitChoreCheckinWorkbenchTests: XCTestCase {
    private let builder = MobileBasicHabitChoreCheckinWorkbenchBuilder(
        generatedAt: "2026-06-24T09:30:00Z",
        redactionSalt: "test-basic-habit-chore"
    )

    func testChildDefaultWorkbenchClassifiesBasicHabitsAndStaysReadOnly() {
        let store = LocalFamilyStore()
        let workbench = builder.build(store: store, viewerRole: .child)

        XCTAssertEqual(workbench.viewerRole, .child)
        XCTAssertEqual(workbench.counts.total, 3)
        // 自由选择模式：全部任务可打卡，无锁定。
        XCTAssertEqual(workbench.counts.ready, 3)
        XCTAssertEqual(workbench.counts.locked, 0)
        XCTAssertEqual(workbench.projection.visibleItems.map(\.kind), [.reading, .chore, .movement])
        XCTAssertEqual(workbench.projection.visibleItems.first?.title, "晨读 / 睡前阅读")
        XCTAssertEqual(workbench.projection.visibleItems.first?.assignmentId, store.assignments[0].id)
        XCTAssertEqual(workbench.projection.visibleItems.first?.rewardLabel, "\(store.assignments[0].task.rewardMinutes) 成长积分")
        XCTAssertFalse(workbench.projection.visibleItems.first?.rewardLabel.contains("分钟") ?? true)
        XCTAssertTrue(workbench.projection.headline.contains("可打卡"))
        XCTAssertFalse(displayedText(workbench).contains("图片占位"))
        XCTAssertFalse(workbench.publicSummary.approvesTask)
        XCTAssertFalse(workbench.publicSummary.grantsCredit)
        XCTAssertFalse(workbench.publicSummary.writesLedger)
        XCTAssertFalse(workbench.publicSummary.unlocksDevice)
        XCTAssertFalse(workbench.publicSummary.sendsNotification)
        XCTAssertTrue(builder.redacts(workbench), displayedText(workbench))
    }

    func testSubmittedHabitShowsWaitingCheckAndPendingRewardWithoutAdultWords() {
        let store = LocalFamilyStore()
        let assignment = store.assignments[0]

        store.submit(assignment, text: "finished")
        let workbench = builder.build(store: store, viewerRole: .child)
        let text = displayedText(workbench)

        XCTAssertEqual(workbench.counts.waitingCheck, 1)
        XCTAssertEqual(workbench.pendingRewardMinutes, assignment.task.rewardMinutes)
        XCTAssertEqual(workbench.projection.visibleItems[0].state, .waitingCheck)
        XCTAssertTrue(workbench.projection.visibleItems[0].proofSummary.contains("已提交文字证明"))
        XCTAssertFalse(text.contains("分钟成长积分"))
        XCTAssertTrue(workbench.findings.contains { $0.code == .waitingCheck })
        for marker in ["批准", "驳回", "发成长积分", "写账本", "解锁设备", "task:", "claim:", "ledger:"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), marker)
        }
    }

    func testSubmittedPhotoHabitShowsRealLocalPhotoProofSummary() throws {
        let store = LocalFamilyStore()
        let assignment = try XCTUnwrap(store.assignments.first { $0.task.requiredProof != .text })
        let proof = ProofDraft(
            kind: assignment.task.requiredProof,
            text: "整理好了",
            photoPlaceholderName: nil,
            photoFileName: "habit-proof.jpg",
            status: .drafting
        )

        store.submit(assignment, proof: proof)

        let workbench = builder.build(store: store, viewerRole: .child)
        let item = try XCTUnwrap(workbench.projection.visibleItems.first { $0.assignmentId == assignment.id })
        XCTAssertTrue(item.proofSummary.contains("本机照片证明"))
        XCTAssertFalse(item.proofSummary.contains("图片占位"))
    }

    func testGuardianProjectionShowsContinuityRiskWithoutProcessingActions() throws {
        let store = LocalFamilyStore()
        let first = store.assignments[0]

        _ = try XCTUnwrap(store.approve(first))
        store.submit(store.assignments[1], text: "desk ready")

        let workbench = builder.build(store: store, viewerRole: .guardian)

        XCTAssertEqual(workbench.viewerRole, .guardian)
        XCTAssertEqual(workbench.counts.done, 1)
        XCTAssertEqual(workbench.counts.waitingCheck, 1)
        XCTAssertGreaterThanOrEqual(workbench.longestStreakDays, 3)
        XCTAssertTrue(workbench.projection.headline.contains("待确认"))
        XCTAssertTrue(workbench.projection.nextActions.contains { $0.contains("脱敏证明摘要") })
        XCTAssertFalse(workbench.projection.approvesTask)
        XCTAssertFalse(workbench.projection.rejectsTask)
        XCTAssertFalse(workbench.projection.grantsCredit)
        XCTAssertEqual(store.creditBalance.availableMinutes, first.task.rewardMinutes)
    }

    func testOfflinePendingIsShownButDoesNotNotifyOrUnlock() {
        let store = LocalFamilyStore()
        let offline = MobileOfflinePublicStatus(pendingCount: 2, conflictCount: 0, rolledBackCount: 0)

        let workbench = builder.build(store: store, viewerRole: .child, offlineStatus: offline)

        XCTAssertEqual(workbench.offlineHint.pendingCount, 2)
        XCTAssertEqual(workbench.publicSummary.offlinePendingCount, 2)
        XCTAssertTrue(workbench.findings.contains { $0.code == .offlinePending })
        XCTAssertFalse(workbench.offlineHint.sendsNotification)
        XCTAssertFalse(workbench.publicSummary.sendsNotification)
        XCTAssertFalse(workbench.publicSummary.unlocksDevice)
    }

    func testUnsafeDisplayInputFallsBackToSafeShell() {
        let store = LocalFamilyStore()
        store.growthPack.steps[0].title = "task:raw http://192.168.1.252 token /Users/developer/private"

        let workbench = builder.build(store: store, viewerRole: .guardian)
        let text = displayedText(workbench)

        XCTAssertTrue(workbench.isEmpty)
        XCTAssertEqual(workbench.publicSummary.findingCodes, [.publicSummaryLeak])
        XCTAssertFalse(text.localizedCaseInsensitiveContains("192.168.1.252"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("/Users/developer"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(text.contains("暂不可用"))
        XCTAssertFalse(text.contains("安全空壳"))
        XCTAssertTrue(text.contains("安全保护模式"))
        XCTAssertTrue(builder.redacts(workbench))
    }

    @MainActor
    func testViewInitializersCompile() {
        _ = BasicHabitChoreCheckinWorkbenchView()
        _ = BasicHabitChoreCheckinWorkbenchView(initialRole: .child, allowedRoles: [.child])
        _ = BasicHabitChoreCheckinWorkbenchView(initialRole: .guardian, allowedRoles: [.guardian])
        _ = ChildHomeView()
        _ = ParentModeView()
        _ = MobileModuleLaunchCenterView(initialRole: .child, allowedRoles: [.child])
    }

    private func displayedText(_ workbench: MobileBasicHabitChoreCheckinWorkbench) -> String {
        var values = [
            workbench.generatedAt,
            workbench.publicWorkbenchRef,
            workbench.title,
            workbench.viewerRole.rawValue,
            workbench.viewerRole.label,
            workbench.offlineHint.title,
            workbench.offlineHint.message,
            workbench.projection.headline
        ]
        values += workbench.projection.nextActions
        values += workbench.projection.visibleItems.flatMap {
            [
                $0.publicItemRef,
                $0.title,
                $0.kind.rawValue,
                $0.kind.label,
                $0.state.rawValue,
                $0.state.label,
                $0.proof.label,
                $0.proofSummary,
                $0.childNextStep,
                $0.guardianNextStep,
                $0.rewardLabel
            ]
        }
        values += workbench.findings.flatMap { [$0.publicRef, $0.code.rawValue, $0.message] }
        values += workbench.publicSummary.findingCodes.map(\.rawValue)
        return values.joined(separator: " ")
    }
}
