import XCTest
@testable import OctoTeacher

final class MobileTodayTaskPackageWorkbenchTests: XCTestCase {
    private let builder = MobileTodayTaskPackageWorkbenchBuilder(
        generatedAt: "2026-06-24T03:00:00Z",
        redactionSalt: "test-mobile-today-task-package"
    )

    func testDefaultWorkbenchMirrorsGrowthPackOrderAndCounts() {
        let store = LocalFamilyStore()
        let workbench = builder.build(store: store)

        XCTAssertEqual(workbench.cards.count, store.growthPack.steps.count)
        XCTAssertEqual(workbench.counts.total, store.assignments.count)
        XCTAssertEqual(workbench.cards.map(\.order), store.growthPack.steps.map(\.order))
        // 自由选择模式：全部卡片 active，无锁定。
        XCTAssertEqual(workbench.cards.first?.state, .active)
        XCTAssertEqual(workbench.cards.dropFirst().map(\.state), [.active, .active])
        XCTAssertEqual(workbench.credit.availableMinutes, 0)
        XCTAssertEqual(workbench.credit.pendingMinutes, 0)
        XCTAssertFalse(workbench.publicSummary.writesLedger)
        XCTAssertFalse(workbench.publicSummary.grantsCredit)
        XCTAssertFalse(workbench.publicSummary.approvesTask)
        XCTAssertFalse(workbench.publicSummary.unlocksDevice)
        XCTAssertTrue(builder.redacts(workbench))
    }

    func testSubmittedTaskMovesToWaitingAndPendingCredit() {
        let store = LocalFamilyStore()
        let assignment = store.assignments[0]

        store.submit(assignment, text: "done")
        let workbench = builder.build(store: store)

        XCTAssertEqual(workbench.cards[0].state, .waitingCheck)
        XCTAssertEqual(workbench.counts.waitingCheck, 1)
        XCTAssertEqual(workbench.credit.pendingMinutes, assignment.task.rewardMinutes)
        XCTAssertEqual(workbench.credit.availableMinutes, 0)
        XCTAssertTrue(workbench.cards[0].creditHint.contains("等待确认"))
    }

    func testApprovedTaskUnlocksNextStepAndAvailableCredit() throws {
        let store = LocalFamilyStore()
        let assignment = store.assignments[0]

        _ = try XCTUnwrap(store.approve(assignment))
        let workbench = builder.build(store: store)

        XCTAssertEqual(workbench.cards[0].state, .done)
        XCTAssertEqual(workbench.cards[1].state, .active)
        XCTAssertEqual(workbench.counts.done, 1)
        XCTAssertEqual(workbench.credit.availableMinutes, assignment.task.rewardMinutes)
        XCTAssertEqual(workbench.credit.lifetimeEarnedMinutes, assignment.task.rewardMinutes)
    }

    func testRejectedTaskUsesRedoWithoutAdultApprovalLanguage() {
        let store = LocalFamilyStore()
        let assignment = store.assignments[0]

        store.submit(assignment, text: "needs another try")
        store.reject(store.assignments[0], reason: .proofUnclear)
        let workbench = builder.build(store: store)
        let text = displayedText(workbench)

        XCTAssertEqual(workbench.cards[0].state, .redo)
        XCTAssertTrue(workbench.cards[0].nextStep.contains("再试一次"))
        for marker in ["家长批准", "审批", "发成长积分", "ledger:", "task:", "claim:"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), marker)
        }
    }

    func testCancelledTaskIsHiddenFromTodayWorkbench() throws {
        let store = LocalFamilyStore()
        let target = try XCTUnwrap(store.assignments.first)

        XCTAssertTrue(store.cancelAssignment(target.id, actor: .guardian))
        let workbench = builder.build(store: store)

        XCTAssertFalse(workbench.cards.contains { $0.title == target.task.title })
        XCTAssertEqual(workbench.counts.total, store.assignments.count - 1)
        XCTAssertFalse(store.todayTasks.contains { $0.id == target.id })
    }

    func testOfflinePendingHintIsReadOnly() {
        let store = LocalFamilyStore()
        let offline = MobileOfflinePublicStatus(pendingCount: 2, conflictCount: 0, rolledBackCount: 0)
        let workbench = builder.build(store: store, offlineStatus: offline)

        XCTAssertEqual(workbench.offlineHint.pendingCount, 2)
        XCTAssertTrue(workbench.offlineHint.hasPending)
        XCTAssertEqual(workbench.publicSummary.offlinePendingCount, 2)
        XCTAssertFalse(workbench.offlineHint.sendsNotification)
        XCTAssertFalse(workbench.offlineHint.unlocksDevice)
        XCTAssertTrue(workbench.findings.contains { $0.code == .offlinePending })
    }

    func testUnsafeDisplayInputFallsBackToSafeShell() {
        let store = LocalFamilyStore()
        store.growthPack.title = "http://192.168.1.252 token sk-test /Users/developer/private"

        let workbench = builder.build(store: store)
        let text = displayedText(workbench)

        XCTAssertTrue(workbench.cards.isEmpty)
        XCTAssertEqual(workbench.publicSummary.findingCodes, [.publicSummaryLeak])
        XCTAssertFalse(text.localizedCaseInsensitiveContains("192.168.1.252"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("sk-test"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("/Users/developer"))
        XCTAssertTrue(builder.redacts(workbench))
    }

    @MainActor
    func testChildHomeAndTaskDetailInitializersCompile() {
        let store = LocalFamilyStore()

        _ = ChildHomeView()
        _ = TaskDetailView(assignment: store.assignments[0])
    }

    func testChildHomeQuickAccessIncludesReportsBeforeEntertainmentPolicy() {
        XCTAssertEqual(
            ChildHomeQuickAccess.ordered,
            [
                .creditWallet,
                .basicHabitChore,
                .growthDiaryVlog,
                .reportsPreview,
                .appSelectionPreview,
                .onboardingGuide
            ]
        )
        XCTAssertEqual(ChildHomeQuickAccess.ordered.count, ChildHomeQuickAccess.allCases.count)
        XCTAssertEqual(ChildHomeQuickAccess.reportsPreview.label, "成长报告预览")
        XCTAssertEqual(ChildHomeQuickAccess.reportsPreview.systemImage, "doc.text")
    }

    private func displayedText(_ workbench: MobileTodayTaskPackageWorkbench) -> String {
        var values = [
            workbench.generatedAt,
            workbench.publicPackRef,
            workbench.packTitle,
            workbench.packSummary,
            workbench.credit.headline,
            workbench.offlineHint.title,
            workbench.offlineHint.message
        ]
        values += workbench.cards.flatMap {
            [$0.publicTaskRef, $0.title, $0.categoryLabel, $0.state.label, $0.proof.label, $0.nextStep, $0.creditHint]
        }
        values += workbench.findings.flatMap { [$0.publicRef, $0.code.rawValue, $0.message] }
        values += workbench.publicSummary.findingCodes.map(\.rawValue)
        return values.joined(separator: " ")
    }
}
