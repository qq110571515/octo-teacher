import XCTest
@testable import OctoTeacher

final class MobileChildCreditWalletTests: XCTestCase {
    private let builder = MobileChildCreditWalletBuilder(
        generatedAt: "2026-06-24T07:30:00Z",
        redactionSalt: "test-child-credit-wallet"
    )

    func testDefaultWalletShowsNoAvailableCreditAndTodayPackagePotential() {
        let store = LocalFamilyStore()
        let screenTime = MockScreenTimeController()

        let wallet = builder.build(store: store, screenTime: screenTime)

        XCTAssertEqual(wallet.balance.availableMinutes, 0)
        XCTAssertEqual(wallet.balance.pendingMinutes, 0)
        XCTAssertEqual(wallet.balance.todayPackageRewardMinutes, 50)
        XCTAssertEqual(wallet.title, "成长积分钱包")
        XCTAssertTrue(wallet.balance.headline.contains("成长积分"))
        XCTAssertEqual(wallet.session.state, .locked)
        XCTAssertTrue(wallet.actions.contains { $0.kind == .earnToday })
        XCTAssertFalse(wallet.publicSummary.grantsCredit)
        XCTAssertFalse(wallet.publicSummary.spendsCredit)
        XCTAssertFalse(wallet.publicSummary.writesLedger)
        XCTAssertFalse(wallet.publicSummary.unlocksDevice)
        XCTAssertTrue(builder.redacts(wallet))
    }

    func testApprovedCreditEnablesRedemptionNavigationWithoutSpending() throws {
        let store = LocalFamilyStore()
        let screenTime = MockScreenTimeController()
        let assignment = store.assignments[0]

        _ = try XCTUnwrap(store.approve(assignment))
        let wallet = builder.build(store: store, screenTime: screenTime)

        XCTAssertEqual(wallet.balance.availableMinutes, assignment.task.rewardMinutes)
        XCTAssertEqual(wallet.balance.lifetimeEarnedMinutes, assignment.task.rewardMinutes)
        XCTAssertEqual(wallet.balance.todayDoneRewardMinutes, assignment.task.rewardMinutes)
        XCTAssertTrue(wallet.actions.contains { $0.kind == .openRedemption })
        XCTAssertEqual(store.creditBalance.availableMinutes, assignment.task.rewardMinutes)
    }

    func testRedemptionActionDoesNotPresentMinutesAsRewardLabel() throws {
        let store = LocalFamilyStore()
        let screenTime = MockScreenTimeController()
        let assignment = store.assignments[0]

        _ = try XCTUnwrap(store.approve(assignment))
        let wallet = builder.build(store: store, screenTime: screenTime)
        let text = displayedText(wallet)

        XCTAssertTrue(text.contains("成长积分"))
        XCTAssertTrue(text.contains("屏幕时间"))
        XCTAssertFalse(text.contains("15 或 30 分钟"))
        XCTAssertFalse(text.contains("分钟屏幕时间"))
    }

    func testSubmittedTaskAppearsAsPendingCreditWithoutAdultWords() {
        let store = LocalFamilyStore()
        let screenTime = MockScreenTimeController()
        let assignment = store.assignments[0]

        store.submit(assignment, text: "done")
        let wallet = builder.build(store: store, screenTime: screenTime)
        let text = displayedText(wallet)

        XCTAssertEqual(wallet.balance.pendingMinutes, assignment.task.rewardMinutes)
        XCTAssertTrue(wallet.actions.contains { $0.kind == .waitForCheck })
        XCTAssertTrue(wallet.findings.contains { $0.code == .pendingCredit })
        for marker in ["批准", "发成长积分", "写账本", "审批", "ledger:", "task:", "claim:"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), marker)
        }
    }

    func testActiveSessionShowsRemainingButDoesNotUnlockFromWallet() throws {
        let store = LocalFamilyStore()
        let screenTime = MockScreenTimeController()
        let now = Date(timeIntervalSince1970: 1000)

        _ = try screenTime.startSession(minutes: 15, now: now)
        let wallet = builder.build(
            store: store,
            screenTime: screenTime,
            now: now.addingTimeInterval(240)
        )

        XCTAssertEqual(wallet.session.state, .active)
        XCTAssertEqual(wallet.session.grantedMinutes, 15)
        XCTAssertEqual(wallet.session.remainingSeconds, 660)
        XCTAssertTrue(wallet.actions.contains { $0.kind == .viewStatus })
        XCTAssertFalse(wallet.session.unlocksDevice)
        XCTAssertFalse(wallet.publicSummary.unlocksDevice)
    }

    func testOfflinePendingAddsSyncActionButNoNotification() {
        let store = LocalFamilyStore()
        let screenTime = MockScreenTimeController()
        let offline = MobileOfflinePublicStatus(pendingCount: 2, conflictCount: 0, rolledBackCount: 0)

        let wallet = builder.build(store: store, screenTime: screenTime, offlineStatus: offline)

        XCTAssertEqual(wallet.offlineHint.pendingCount, 2)
        XCTAssertTrue(wallet.actions.contains { $0.kind == .viewSync })
        XCTAssertFalse(wallet.offlineHint.sendsNotification)
        XCTAssertFalse(wallet.publicSummary.sendsNotification)
    }

    func testUnsafeDisplayInputFallsBackToSafeShell() {
        let store = LocalFamilyStore()
        let screenTime = MockScreenTimeController()
        store.growthPack.steps[0].title = "task:secret http://192.168.1.252 token /Users/developer/private"

        let wallet = builder.build(store: store, screenTime: screenTime)
        let text = displayedText(wallet)

        XCTAssertEqual(wallet.publicSummary.findingCodes, [.publicSummaryLeak])
        XCTAssertTrue(wallet.actions.isEmpty)
        XCTAssertFalse(text.localizedCaseInsensitiveContains("192.168.1.252"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("/Users/developer"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("token"))
        XCTAssertTrue(builder.redacts(wallet))
    }

    @MainActor
    func testViewInitializersCompile() {
        _ = ChildCreditWalletView()
        _ = ChildHomeView()
        _ = MobileHomeView()
        _ = MobileModuleLaunchCenterView(initialRole: .child, allowedRoles: [.child])
    }

    private func displayedText(_ wallet: MobileChildCreditWallet) -> String {
        var values = [
            wallet.generatedAt,
            wallet.publicWalletRef,
            wallet.title,
            wallet.balance.headline,
            wallet.session.state.label,
            wallet.session.latestReceiptSummary,
            wallet.offlineHint.title,
            wallet.offlineHint.message
        ]
        values += wallet.actions.flatMap { [$0.publicActionRef, $0.kind.rawValue, $0.title, $0.detail] }
        values += wallet.findings.flatMap { [$0.publicRef, $0.code.rawValue, $0.message] }
        values += wallet.publicSummary.findingCodes.map(\.rawValue)
        return values.joined(separator: " ")
    }
}
