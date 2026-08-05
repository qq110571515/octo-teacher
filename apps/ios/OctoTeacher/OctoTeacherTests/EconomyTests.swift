import XCTest
@testable import OctoTeacher

/// P3 成长积分与零花钱经济系统的回归测试。
final class EconomyTests: XCTestCase {

    private func dateOf(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - 汇率

    func testScreenRateMath() {
        XCTAssertEqual(ScreenExchangeRate.onePointPerMinute.pointsRequired(forMinutes: 15), 15)
        XCTAssertEqual(ScreenExchangeRate.twoPointsPerMinute.pointsRequired(forMinutes: 15), 30)
        XCTAssertEqual(ScreenExchangeRate.onePointPerTwoMinutes.pointsRequired(forMinutes: 15), 8, "向上取整")
    }

    func testScreenSessionUsesParentRate() {
        let store = LocalFamilyStore()
        var policy = FamilyExchangePolicy.default
        policy.screenRate = .twoPointsPerMinute
        store.setExchangePolicy(policy, for: store.activeChildId)
        store.child.rewardBalanceMinutes = 40

        let controller = MockScreenTimeController(persistenceKey: nil)
        let result = StartRewardSessionUseCase(store: store, screenTimeController: controller)(minutes: 15)
        guard case .started = result else { return XCTFail("应成功开启") }
        XCTAssertEqual(store.child.rewardBalanceMinutes, 10, "15 分钟 × 2 分/分钟 = 扣 30 分")
    }

    func testScreenSessionInsufficientPoints() {
        let store = LocalFamilyStore()
        var policy = FamilyExchangePolicy.default
        policy.screenRate = .twoPointsPerMinute
        store.setExchangePolicy(policy, for: store.activeChildId)
        store.child.rewardBalanceMinutes = 20 // 够 15 分钟的旧语义，不够 2:1 的 30 分

        let controller = MockScreenTimeController(persistenceKey: nil)
        let result = StartRewardSessionUseCase(store: store, screenTimeController: controller)(minutes: 15)
        XCTAssertEqual(result, .insufficientBalance)
        XCTAssertEqual(store.child.rewardBalanceMinutes, 20, "失败不扣分")
    }

    func testCustomScreenExchangeControlsBothMinutesAndPoints() {
        let store = LocalFamilyStore()
        var policy = FamilyExchangePolicy.default
        policy.customScreenExchangeMinutes = 40
        policy.customScreenPointsPer15Minutes = 75
        store.setExchangePolicy(policy, for: store.activeChildId)

        let saved = store.policy(for: store.activeChildId)
        XCTAssertEqual(saved.resolvedScreenExchangeMinutes, 40)
        XCTAssertEqual(saved.screenPointsRequired(forMinutes: 40), 75)
        XCTAssertEqual(saved.screenPointsRequired(forMinutes: 20), 38, "非整份时长向上取整")
    }

    func testDailyUnlockLimitBlocksAdditionalSessionWithoutSpendingPoints() {
        let store = LocalFamilyStore()
        store.updateChildProfile(
            childId: store.activeChildId,
            name: store.child.name,
            age: store.child.age,
            dailyLimitMinutes: 15,
            interests: [],
            parentNotes: ""
        )
        store.child.rewardBalanceMinutes = 100
        let controller = MockScreenTimeController(persistenceKey: nil)
        let start = dateOf(2026, 7, 11)

        let first = StartRewardSessionUseCase(store: store, screenTimeController: controller)(minutes: 15, now: start)
        guard case .started = first else { return XCTFail("第一次兑换应成功") }
        _ = controller.tick(now: start.addingTimeInterval(15 * 60))

        let second = StartRewardSessionUseCase(store: store, screenTimeController: controller)(
            minutes: 15,
            now: start.addingTimeInterval(16 * 60)
        )
        XCTAssertEqual(second, .dailyLimitExceeded(remainingMinutes: 0))
        XCTAssertEqual(store.child.rewardBalanceMinutes, 85, "超上限的第二次兑换不能再扣积分")
    }

    func testParentCanUseBroadMoneyAndWishPricingRanges() throws {
        let store = LocalFamilyStore()
        var policy = FamilyExchangePolicy.default
        policy.baseMonthlyAllowance = 25_000
        policy.pointsPerCurrencyUnit = 50_000
        policy.monthlyPocketMoneyCap = 500_000
        store.setExchangePolicy(policy, for: store.activeChildId)

        let saved = store.policy(for: store.activeChildId)
        XCTAssertEqual(saved.baseMonthlyAllowance, 25_000)
        XCTAssertEqual(saved.pointsPerCurrencyUnit, 50_000)
        XCTAssertEqual(saved.monthlyPocketMoneyCap, 500_000)

        let wish = try XCTUnwrap(store.submitWish(title: "一项很大的长期愿望"))
        XCTAssertTrue(store.priceWish(wish.id, points: 250_000))
        XCTAssertEqual(store.wishes.first(where: { $0.id == wish.id })?.pricePoints, 250_000)
    }

    // MARK: - 每月基础零花钱

    func testMonthlyAllowanceCreditsOncePerMonth() {
        let store = LocalFamilyStore()
        var policy = FamilyExchangePolicy.default
        policy.baseMonthlyAllowance = 30
        store.exchangePolicies[store.activeChildId] = policy

        let july = dateOf(2026, 7, 4)
        store.creditMonthlyAllowancesIfNeeded(now: july)
        store.creditMonthlyAllowancesIfNeeded(now: july)
        store.creditMonthlyAllowancesIfNeeded(now: dateOf(2026, 7, 20))

        let entries = store.moneyLedger.filter { $0.kind == .baseAllowance }
        XCTAssertEqual(entries.count, 1, "同月只入账一次")
        XCTAssertEqual(entries[0].amount, 30)
        XCTAssertEqual(entries[0].status, .pendingPayout)

        // 下个月再入一次。
        store.creditMonthlyAllowancesIfNeeded(now: dateOf(2026, 8, 1))
        XCTAssertEqual(store.moneyLedger.filter { $0.kind == .baseAllowance }.count, 2)
    }

    func testMonthlyAllowanceWaitsForConfiguredDay() {
        let store = LocalFamilyStore()
        var policy = FamilyExchangePolicy.default
        policy.baseMonthlyAllowance = 30
        policy.allowanceDayOfMonth = 10
        store.exchangePolicies[store.activeChildId] = policy

        store.creditMonthlyAllowancesIfNeeded(now: dateOf(2026, 7, 4))
        XCTAssertTrue(store.moneyLedger.isEmpty, "未到入账日不入账")

        store.creditMonthlyAllowancesIfNeeded(now: dateOf(2026, 7, 10))
        XCTAssertEqual(store.moneyLedger.count, 1)
    }

    func testZeroAllowanceNeverCredits() {
        let store = LocalFamilyStore()
        store.creditMonthlyAllowancesIfNeeded(now: dateOf(2026, 7, 4))
        XCTAssertTrue(store.moneyLedger.isEmpty, "默认底薪为 0 不入账")
    }

    // MARK: - 成长积分兑换零花钱

    func testPocketMoneyExchangeHoldsPointsAndAwaitsApproval() throws {
        let store = LocalFamilyStore()
        store.child.rewardBalanceMinutes = 25

        let entry = try XCTUnwrap(store.requestPocketMoneyExchange(points: 25))
        // 25 分 ÷ 10 分/元 = ¥2，实际扣 20 分（不吃余数）。
        XCTAssertEqual(entry.amount, 2)
        XCTAssertEqual(entry.pointsSpent, 20)
        XCTAssertEqual(entry.status, .awaitingApproval)
        XCTAssertEqual(store.child.rewardBalanceMinutes, 5, "扣 20 留 5")
    }

    func testPocketMoneyExchangeRejectsWhenInsufficient() {
        let store = LocalFamilyStore()
        store.child.rewardBalanceMinutes = 5
        XCTAssertNil(store.requestPocketMoneyExchange(points: 5), "不足 1 个货币单位")
        XCTAssertEqual(store.child.rewardBalanceMinutes, 5)
    }

    func testPocketMoneyMonthlyCapEnforced() throws {
        let store = LocalFamilyStore()
        var policy = FamilyExchangePolicy.default
        policy.monthlyPocketMoneyCap = 3
        store.setExchangePolicy(policy, for: store.activeChildId)
        store.child.rewardBalanceMinutes = 100

        _ = try XCTUnwrap(store.requestPocketMoneyExchange(points: 30)) // ¥3 = 顶满
        XCTAssertNil(store.requestPocketMoneyExchange(points: 10), "超过每月上限应拒绝")
    }

    func testApproveThenPaidFlow() throws {
        let store = LocalFamilyStore()
        store.child.rewardBalanceMinutes = 20
        let entry = try XCTUnwrap(store.requestPocketMoneyExchange(points: 20))

        XCTAssertTrue(store.approvePocketMoney(entry.id))
        XCTAssertEqual(store.moneyLedger.first?.status, .pendingPayout)
        XCTAssertFalse(store.approvePocketMoney(entry.id), "重复批准应失败（幂等）")

        XCTAssertTrue(store.markPocketMoneyPaid(entry.id))
        XCTAssertEqual(store.moneyLedger.first?.status, .paid)
        XCTAssertEqual(store.pocketMoneySummary(for: store.activeChildId).paidTotal, 2)
    }

    func testRejectRefundsPoints() throws {
        let store = LocalFamilyStore()
        store.child.rewardBalanceMinutes = 20
        let entry = try XCTUnwrap(store.requestPocketMoneyExchange(points: 20))
        XCTAssertEqual(store.child.rewardBalanceMinutes, 0)

        XCTAssertTrue(store.rejectPocketMoney(entry.id))
        XCTAssertEqual(store.child.rewardBalanceMinutes, 20, "驳回必须全额退分")
        XCTAssertEqual(store.moneyLedger.first?.status, .rejected)
    }

    func testInstantExchangeWhenApprovalNotRequired() throws {
        let store = LocalFamilyStore()
        var policy = FamilyExchangePolicy.default
        policy.pocketMoneyRequiresApproval = false
        store.setExchangePolicy(policy, for: store.activeChildId)
        store.child.rewardBalanceMinutes = 10

        let entry = try XCTUnwrap(store.requestPocketMoneyExchange(points: 10))
        XCTAssertEqual(entry.status, .pendingPayout, "免批准直接进入待发放")
    }

    func testAdjustmentRequiresNoteAndNonZero() {
        let store = LocalFamilyStore()
        XCTAssertNil(store.adjustPocketMoney(childId: store.activeChildId, amount: 0, note: "x"))
        XCTAssertNil(store.adjustPocketMoney(childId: store.activeChildId, amount: 5, note: "  "))
        XCTAssertNotNil(store.adjustPocketMoney(childId: store.activeChildId, amount: -5, note: "打碎花瓶"))
    }

    // MARK: - 持久化

    func testEconomyFieldsSurviveRoundTrip() throws {
        let store = LocalFamilyStore()
        var policy = FamilyExchangePolicy.default
        policy.baseMonthlyAllowance = 50
        policy.screenRate = .twoPointsPerMinute
        store.setExchangePolicy(policy, for: store.activeChildId)
        store.child.rewardBalanceMinutes = 30
        _ = store.requestPocketMoneyExchange(points: 10)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(store.snapshot)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FamilyStoreSnapshot.self, from: data)

        XCTAssertEqual(decoded.exchangePolicies?[store.activeChildId]?.screenRate, .twoPointsPerMinute)
        XCTAssertEqual(decoded.moneyLedger?.count, store.moneyLedger.count)
        XCTAssertNotNil(decoded.allowanceCursors)
    }

    /// 旧快照（无经济字段）解码后使用默认策略与空账本。
    func testLegacySnapshotWithoutEconomyFieldsDecodes() throws {
        let store = LocalFamilyStore()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var json = try JSONSerialization.jsonObject(with: encoder.encode(store.snapshot)) as! [String: Any]
        json.removeValue(forKey: "exchangePolicies")
        json.removeValue(forKey: "moneyLedger")
        json.removeValue(forKey: "allowanceCursors")
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FamilyStoreSnapshot.self, from: data)
        XCTAssertNil(decoded.exchangePolicies)
        XCTAssertNil(decoded.moneyLedger)
    }
}
