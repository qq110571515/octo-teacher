import XCTest
@testable import OctoTeacher

final class MobileParentTodayTaskPackageReviewTests: XCTestCase {
    private let builder = MobileParentTodayTaskPackageReviewBuilder(
        generatedAt: "2026-06-24T04:00:00Z",
        redactionSalt: "test-parent-today-task-package"
    )

    func testGuardianDefaultReviewMirrorsTodayPackageCounts() {
        let store = LocalFamilyStore()
        let review = builder.build(store: store)

        XCTAssertTrue(review.visibility.canSeeReviewQueue)
        XCTAssertEqual(review.items.count, store.growthPack.steps.count)
        XCTAssertEqual(review.items.map(\.order), store.growthPack.steps.map(\.order))
        // 自由选择模式：全部任务可开始，无锁定。
        XCTAssertEqual(review.counts.readyToStart, 3)
        XCTAssertEqual(review.counts.locked, 0)
        XCTAssertEqual(review.counts.waitingCheck, 0)
        XCTAssertFalse(review.publicSummary.approvesTask)
        XCTAssertFalse(review.publicSummary.rejectsTask)
        XCTAssertFalse(review.publicSummary.grantsCredit)
        XCTAssertFalse(review.publicSummary.writesLedger)
        XCTAssertFalse(review.publicSummary.unlocksDevice)
        XCTAssertTrue(builder.redacts(review))
    }

    func testSubmittedTaskAppearsAsWaitingReviewWithProofSummary() {
        let store = LocalFamilyStore()
        let assignment = store.assignments[0]

        store.submit(assignment, text: "finished without leaking this raw note")
        let review = builder.build(store: store)

        XCTAssertEqual(review.counts.waitingCheck, 1)
        XCTAssertEqual(review.counts.needsAttention, 1)
        XCTAssertTrue(review.items[0].actionRequired)
        XCTAssertEqual(review.items[0].proofSummary, "文字证明已提交")
        XCTAssertTrue(review.items[0].nextAction.contains("原有待批准任务区"))
        XCTAssertEqual(review.credit.pendingMinutes, assignment.task.rewardMinutes)
        XCTAssertEqual(review.items[0].rewardLabel, "\(assignment.task.rewardMinutes) 成长积分")
        XCTAssertFalse(review.items[0].rewardLabel.contains("分钟"))
        XCTAssertFalse(displayedText(review).contains("finished without leaking"))
    }

    func testApprovedTaskUnlocksNextStepAndAvailableCredit() throws {
        let store = LocalFamilyStore()
        let assignment = store.assignments[0]

        _ = try XCTUnwrap(store.approve(assignment))
        let review = builder.build(store: store)

        XCTAssertEqual(review.items[0].state, .done)
        XCTAssertEqual(review.items[1].state, .active)
        XCTAssertEqual(review.counts.done, 1)
        XCTAssertEqual(review.credit.availableMinutes, assignment.task.rewardMinutes)
    }

    func testOfflinePendingIsVisibleButReadOnly() {
        let store = LocalFamilyStore()
        let offline = MobileOfflinePublicStatus(pendingCount: 3, conflictCount: 0, rolledBackCount: 0)
        let review = builder.build(store: store, offlineStatus: offline)

        XCTAssertEqual(review.offlineHint.pendingCount, 3)
        XCTAssertEqual(review.publicSummary.offlinePendingCount, 3)
        XCTAssertFalse(review.offlineHint.sendsNotification)
        XCTAssertFalse(review.offlineHint.unlocksDevice)
        XCTAssertTrue(review.findings.contains { $0.code == .offlinePending })
    }

    func testNonGuardianViewsHideReviewQueueAndAdultActions() {
        let store = LocalFamilyStore()
        store.submit(store.assignments[0], text: "done")

        for role in [MobileParentTodayTaskPackageReviewViewerRole.child, .relative] {
            let review = builder.build(viewerRole: role, store: store)
            let text = displayedText(review)

            XCTAssertFalse(review.visibility.canSeeReviewQueue)
            XCTAssertTrue(review.items.isEmpty)
            XCTAssertEqual(review.publicSummary.findingCodes, [.nonGuardianHidden])
            for marker in ["待批准", "批准", "驳回", "发成长积分", "ledger:", "task:", "claim:"] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "\(role): \(marker)")
            }
        }
    }

    func testUnsafeDisplayInputFallsBackToSafeShell() {
        let store = LocalFamilyStore()
        store.growthPack.steps[0].title = "task:secret http://192.168.1.252 token /Users/developer/private"

        let review = builder.build(store: store)
        let text = displayedText(review)

        XCTAssertTrue(review.items.isEmpty)
        XCTAssertEqual(review.publicSummary.findingCodes, [.publicSummaryLeak])
        XCTAssertFalse(text.localizedCaseInsensitiveContains("192.168.1.252"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("/Users/developer"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("token"))
        XCTAssertTrue(builder.redacts(review))
    }

    @MainActor
    func testViewInitializersCompile() {
        _ = ParentTodayTaskPackageReviewView()
        _ = ParentModeView()
        _ = MobileModuleLaunchCenterView(initialRole: .guardian, allowedRoles: [.guardian])
    }

    func testParentModeQuickAccessOrderCoversReviewBrandAndReportEntries() {
        XCTAssertEqual(ParentModeQuickAccess.ordered.count, ParentModeQuickAccess.allCases.count)
        XCTAssertEqual(ParentModeQuickAccess.ordered.first, .todayTaskReview)
        XCTAssertTrue(ParentModeQuickAccess.ordered.contains(.appSelectionPolicy))
        XCTAssertTrue(ParentModeQuickAccess.ordered.contains(.reportsPreview))
        XCTAssertTrue(ParentModeQuickAccess.ordered.contains(.onboardingBoundary))
        XCTAssertEqual(ParentModeQuickAccess.onboardingBoundary.label, "首次使用检查")
        XCTAssertEqual(ParentModeQuickAccess.reportsPreview.systemImage, "doc.text")
    }

    func testParentModeQuickAccessExplainsDailyVersusPreviewEntries() {
        XCTAssertEqual(ParentModeQuickAccess.todayTaskReview.statusLabel, "日常")
        XCTAssertEqual(ParentModeQuickAccess.approvalInbox.statusLabel, "日常")
        XCTAssertEqual(ParentModeQuickAccess.aiLmsBoundary.statusLabel, "规划")
        XCTAssertTrue(ParentModeQuickAccess.todayTaskReview.detail.contains("集中处理"))
        XCTAssertTrue(ParentModeQuickAccess.appSelectionPolicy.detail.contains("娱乐 App"))

        for item in ParentModeQuickAccess.allCases {
            XCTAssertFalse(item.statusLabel.isEmpty, item.rawValue)
            XCTAssertFalse(item.detail.isEmpty, item.rawValue)
            XCTAssertFalse(item.label.isEmpty, item.rawValue)
        }
    }

    private func displayedText(_ review: MobileParentTodayTaskPackageReview) -> String {
        var values = [
            review.generatedAt,
            review.viewerRole.rawValue,
            review.publicPackRef,
            review.title,
            review.summary,
            review.credit.headline,
            review.offlineHint.title,
            review.offlineHint.message
        ]
        values += review.items.flatMap {
            [
                $0.publicReviewRef,
                $0.title,
                $0.categoryLabel,
                $0.state.label,
                $0.proofRequirement.label,
                $0.proofSummary,
                $0.rewardLabel,
                $0.nextAction
            ]
        }
        values += review.findings.flatMap { [$0.publicRef, $0.code.rawValue, $0.message] }
        values += review.publicSummary.findingCodes.map(\.rawValue)
        return values.joined(separator: " ")
    }
}
