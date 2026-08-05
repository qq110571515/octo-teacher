import XCTest
@testable import OctoTeacher

final class RewardPathwaySnapshotTests: XCTestCase {
    func testChildSnapshotConnectsAllRewardOutletsWithPlainLanguage() {
        let store = LocalFamilyStore()
        let screenTime = MockScreenTimeController()
        let snapshot = RewardPathwayBuilder().build(
            store: store,
            screenTime: screenTime,
            viewerRole: .child
        )

        XCTAssertEqual(snapshot.viewerRole, .child)
        XCTAssertEqual(snapshot.outlets.map(\.kind), [.screenTime, .pocketMoney, .wishList])
        XCTAssertEqual(snapshot.publicSummary.outletCount, 3)
        XCTAssertTrue(displayedText(snapshot).contains("屏幕时间"))
        XCTAssertTrue(displayedText(snapshot).contains("零花钱"))
        XCTAssertTrue(displayedText(snapshot).contains("愿望清单"))
        XCTAssertFalse(displayedText(snapshot).contains("够换 15 分钟"))
        for outlet in snapshot.outlets {
            XCTAssertLessThanOrEqual(outlet.childExplanation.count, 40)
            XCTAssertFalse(outlet.speakText.isEmpty)
        }
    }

    func testScreenTimeRewardCopyUsesGrowthCreditsInsteadOfMinutePrimaryLabels() {
        let visibleCopies = [
            ScreenTimeRewardCopy.buttonTitle(cost: 15),
            ScreenTimeRewardCopy.speakText(cost: 15),
            ScreenTimeRewardCopy.statusButtonTitle,
            ScreenTimeRewardCopy.offlineRequestTitle,
            ScreenTimeRewardCopy.offlineSuccessText
        ]

        for copy in visibleCopies {
            XCTAssertTrue(copy.contains("成长积分") || copy.contains("屏幕时间"))
            XCTAssertFalse(copy.contains("15 分钟"))
            XCTAssertFalse(copy.contains("30 分钟"))
            XCTAssertFalse(copy.contains("分钟屏幕时间"))
        }
    }

    func testGuardianSnapshotShowsReviewBacklogAndOfflineFulfillmentBoundaries() throws {
        let store = LocalFamilyStore()
        let screenTime = MockScreenTimeController()
        var child = store.child
        child.rewardBalanceMinutes = 120
        store.child = child
        var policy = store.policy(for: store.activeChildId)
        policy.pocketMoneyRequiresApproval = true
        policy.pointsPerCurrencyUnit = 10
        store.setExchangePolicy(policy, for: store.activeChildId)

        let wish = try XCTUnwrap(store.submitWish(title: "恐龙图鉴", childId: store.activeChildId))
        XCTAssertTrue(store.priceWish(wish.id, points: 30))
        XCTAssertTrue(store.redeemWish(wish.id))
        _ = try XCTUnwrap(store.requestPocketMoneyExchange(points: 20, childId: store.activeChildId))

        let snapshot = RewardPathwayBuilder().build(
            store: store,
            screenTime: screenTime,
            viewerRole: .guardian
        )
        let text = displayedText(snapshot)

        XCTAssertEqual(snapshot.viewerRole, .guardian)
        XCTAssertEqual(snapshot.publicSummary.pendingGuardianReviewCount, 2)
        XCTAssertTrue(text.contains("线下"))
        XCTAssertTrue(text.contains("家长"))
        XCTAssertTrue(text.contains("待发放"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("在线支付"))
    }

    func testPendingBreakdownSplitsGuardianReviewCountByActionKind() throws {
        let store = LocalFamilyStore()
        let screenTime = MockScreenTimeController()
        var child = store.child
        child.rewardBalanceMinutes = 120
        store.child = child

        let proposedWish = try XCTUnwrap(store.submitWish(title: "滑板课", childId: store.activeChildId))
        XCTAssertEqual(proposedWish.status, .proposed)
        let redeemedWish = try XCTUnwrap(store.submitWish(title: "恐龙图鉴", childId: store.activeChildId))
        XCTAssertTrue(store.priceWish(redeemedWish.id, points: 30))
        XCTAssertTrue(store.redeemWish(redeemedWish.id))
        _ = try XCTUnwrap(store.requestPocketMoneyExchange(points: 20, childId: store.activeChildId))

        let snapshot = RewardPathwayBuilder().build(
            store: store,
            screenTime: screenTime,
            viewerRole: .guardian
        )
        let breakdown = snapshot.publicSummary.pendingBreakdown

        XCTAssertEqual(breakdown.pricingWishCount, 1)
        XCTAssertEqual(breakdown.fulfillmentWishCount, 1)
        XCTAssertEqual(breakdown.pocketMoneyConfirmCount, 1)
        XCTAssertEqual(breakdown.total, snapshot.publicSummary.pendingGuardianReviewCount)
    }

    func testPendingBreakdownIsZeroWhenNothingAwaitsGuardian() {
        let store = LocalFamilyStore()
        let screenTime = MockScreenTimeController()

        let snapshot = RewardPathwayBuilder().build(
            store: store,
            screenTime: screenTime,
            viewerRole: .guardian
        )
        let breakdown = snapshot.publicSummary.pendingBreakdown

        XCTAssertEqual(breakdown, RewardPathwayPendingBreakdown(
            pricingWishCount: 0,
            fulfillmentWishCount: 0,
            pocketMoneyConfirmCount: 0
        ))
        XCTAssertEqual(snapshot.publicSummary.pendingGuardianReviewCount, 0)
    }

    func testPricedWishlistBecomesRedeemableWhenCreditIsEnough() throws {
        let store = LocalFamilyStore()
        let screenTime = MockScreenTimeController()
        var child = store.child
        child.rewardBalanceMinutes = 80
        store.child = child
        let wish = try XCTUnwrap(store.submitWish(title: "去公园野餐", childId: store.activeChildId))
        XCTAssertTrue(store.priceWish(wish.id, points: 60))

        let snapshot = RewardPathwayBuilder().build(
            store: store,
            screenTime: screenTime,
            viewerRole: .child
        )
        let wishOutlet = try XCTUnwrap(snapshot.outlets.first { $0.kind == .wishList })

        XCTAssertEqual(snapshot.publicSummary.redeemableWishCount, 1)
        XCTAssertTrue(wishOutlet.status.contains("可以兑换"))
        XCTAssertTrue(wishOutlet.nextStep.contains("兑换"))
    }

    func testScreenTimeOutletRoutesToEarnCreditsWhenCreditIsNotEnough() throws {
        let store = LocalFamilyStore()
        let screenTime = MockScreenTimeController()

        let snapshot = RewardPathwayBuilder().build(
            store: store,
            screenTime: screenTime,
            viewerRole: .child
        )
        let screenOutlet = try XCTUnwrap(snapshot.outlets.first { $0.kind == .screenTime })

        XCTAssertEqual(screenOutlet.suggestedRoute, .earnCredits)
        XCTAssertTrue(screenOutlet.nextStep.contains("完成"))
    }

    func testScreenTimeOutletRoutesToRedemptionWhenCreditIsEnoughOrSessionIsActive() throws {
        let store = LocalFamilyStore()
        let screenTime = MockScreenTimeController()
        var child = store.child
        child.rewardBalanceMinutes = 40
        store.child = child

        var snapshot = RewardPathwayBuilder().build(
            store: store,
            screenTime: screenTime,
            viewerRole: .child
        )
        var screenOutlet = try XCTUnwrap(snapshot.outlets.first { $0.kind == .screenTime })
        XCTAssertEqual(screenOutlet.suggestedRoute, .redeemScreenTime)

        child.rewardBalanceMinutes = 0
        store.child = child
        _ = try screenTime.startSession(minutes: 15)
        snapshot = RewardPathwayBuilder().build(
            store: store,
            screenTime: screenTime,
            viewerRole: .child
        )
        screenOutlet = try XCTUnwrap(snapshot.outlets.first { $0.kind == .screenTime })
        XCTAssertEqual(screenOutlet.suggestedRoute, .redeemScreenTime)
    }

    func testScreenTimeOutletExplainsDeviceFailureWithoutSpendingCredit() throws {
        let store = LocalFamilyStore()
        let screenTime = MockScreenTimeController()
        var child = store.child
        child.rewardBalanceMinutes = 40
        store.child = child
        screenTime.simulateDeviceFailure = true

        let result = StartRewardSessionUseCase(store: store, screenTimeController: screenTime)(minutes: 15)
        XCTAssertEqual(result, .deviceFailureRolledBack)
        XCTAssertEqual(store.child.rewardBalanceMinutes, 40)

        let snapshot = RewardPathwayBuilder().build(
            store: store,
            screenTime: screenTime,
            viewerRole: .child
        )
        let screenOutlet = try XCTUnwrap(snapshot.outlets.first { $0.kind == .screenTime })

        XCTAssertEqual(screenOutlet.status, "上次设备未打开")
        XCTAssertTrue(screenOutlet.speakText.contains("成长积分已经保护"))
        XCTAssertTrue(screenOutlet.guardrails.contains("设备失败会退回成长积分"))
    }

    func testMoneyAndWishOutletsRouteToPocketMoneyCenter() throws {
        let store = LocalFamilyStore()
        let screenTime = MockScreenTimeController()

        let snapshot = RewardPathwayBuilder().build(
            store: store,
            screenTime: screenTime,
            viewerRole: .child
        )
        let moneyOutlet = try XCTUnwrap(snapshot.outlets.first { $0.kind == .pocketMoney })
        let wishOutlet = try XCTUnwrap(snapshot.outlets.first { $0.kind == .wishList })

        XCTAssertEqual(moneyOutlet.suggestedRoute, .pocketMoneyCenter)
        XCTAssertEqual(wishOutlet.suggestedRoute, .pocketMoneyCenter)
    }

    func testPocketMoneyBlockerExplainsInsufficientCredits() {
        let store = LocalFamilyStore()
        var policy = store.policy(for: store.activeChildId)
        policy.pointsPerCurrencyUnit = 10
        store.setExchangePolicy(policy, for: store.activeChildId)

        XCTAssertEqual(
            store.pocketMoneyExchangeBlocker(points: 10, childId: store.activeChildId),
            .insufficientCredits(requiredPoints: 10, availablePoints: 0)
        )
    }

    func testPocketMoneyOutletShowsMonthlyCapInsteadOfGenericFailure() throws {
        let store = LocalFamilyStore()
        let screenTime = MockScreenTimeController()
        let now = Date()
        var child = store.child
        child.rewardBalanceMinutes = 120
        store.child = child
        var policy = store.policy(for: store.activeChildId)
        policy.pointsPerCurrencyUnit = 10
        policy.monthlyPocketMoneyCap = 1
        store.setExchangePolicy(policy, for: store.activeChildId)

        _ = try XCTUnwrap(store.requestPocketMoneyExchange(points: 10, childId: store.activeChildId, now: now))

        XCTAssertEqual(
            store.pocketMoneyExchangeBlocker(points: 10, childId: store.activeChildId, now: now),
            .monthlyCapReached(cap: 1, alreadyExchanged: 1)
        )

        let snapshot = RewardPathwayBuilder().build(
            store: store,
            screenTime: screenTime,
            viewerRole: .child
        )
        let moneyOutlet = try XCTUnwrap(snapshot.outlets.first { $0.kind == .pocketMoney })

        XCTAssertTrue(moneyOutlet.status.contains("上限"))
        XCTAssertTrue(moneyOutlet.nextStep.contains("下个月"))
    }

    func testReadOnlySnapshotHasNoSideEffects() {
        let store = LocalFamilyStore()
        let screenTime = MockScreenTimeController()
        let beforeBalance = store.creditBalance.availableMinutes
        let beforeLedgerCount = store.moneyLedger.count
        let beforeWishCount = store.wishes.count

        let snapshot = RewardPathwayBuilder().build(
            store: store,
            screenTime: screenTime,
            viewerRole: .guardian
        )

        XCTAssertEqual(store.creditBalance.availableMinutes, beforeBalance)
        XCTAssertEqual(store.moneyLedger.count, beforeLedgerCount)
        XCTAssertEqual(store.wishes.count, beforeWishCount)
        XCTAssertFalse(snapshot.publicSummary.sideEffects.writesLedger)
        XCTAssertFalse(snapshot.publicSummary.sideEffects.grantsCredit)
        XCTAssertFalse(snapshot.publicSummary.sideEffects.spendsCredit)
        XCTAssertFalse(snapshot.publicSummary.sideEffects.unlocksDevice)
        XCTAssertFalse(snapshot.publicSummary.sideEffects.paysMoney)
        XCTAssertFalse(snapshot.publicSummary.sideEffects.fulfillsWish)
        XCTAssertFalse(snapshot.publicSummary.sideEffects.callsNetwork)
        XCTAssertFalse(snapshot.publicSummary.sideEffects.callsAI)
    }

    func testChildVisibleTextDoesNotExposeInternalOrPaymentDetails() {
        let store = LocalFamilyStore()
        let screenTime = MockScreenTimeController()
        let snapshot = RewardPathwayBuilder().build(
            store: store,
            screenTime: screenTime,
            viewerRole: .child
        )
        let text = displayedText(snapshot)

        for marker in ["订单", "回执ID", "API", "URL", "http", "token", "ledger", "在线支付"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), marker)
        }
    }

    private func displayedText(_ snapshot: RewardPathwaySnapshot) -> String {
        var values = [
            snapshot.title,
            snapshot.headline,
            snapshot.publicSummary.childName
        ]
        values += snapshot.safetyNotes
        values += snapshot.outlets.flatMap {
            [
                $0.kind.rawValue,
                $0.title,
                $0.childExplanation,
                $0.guardianExplanation,
                $0.status,
                $0.availability,
                $0.nextStep,
                $0.visibleMetric,
                $0.speakText,
                $0.suggestedRoute.rawValue
            ] + $0.guardrails
        }
        return values.joined(separator: " ")
    }
}
