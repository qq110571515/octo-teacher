import XCTest
@testable import OctoTeacher

/// iOS 奖励商店库存履约安全壳测试。
///
/// 覆盖孩子隐藏订单/地址/账本/设备、家长看到库存与履约风险、兑换不执行副作用、
/// 离线/退款/取消 fallback、公开摘要脱敏和入口视图 initializer 编译。
final class MobileRewardStoreInventoryFulfillmentWorkbenchTests: XCTestCase {

    private func build(
        role: MobileRewardStoreFulfillmentRole,
        input: MobileRewardStoreFulfillmentInput = .mock
    ) -> MobileRewardStoreInventoryFulfillmentWorkbench {
        MobileRewardStoreInventoryFulfillmentBuilder().build(role: role, input: input)
    }

    func testGuardianSeesInventoryAndFulfillmentRisks() {
        let workbench = build(role: .guardian)

        XCTAssertEqual(workbench.role, .guardian)
        XCTAssertFalse(workbench.rows.isEmpty)
        XCTAssertGreaterThan(workbench.publicSummary.unavailableCount, 0)
        XCTAssertGreaterThan(workbench.publicSummary.needsParentCount, 0)
        XCTAssertGreaterThan(workbench.publicSummary.reservedCount, 0)
        XCTAssertGreaterThan(workbench.publicSummary.fulfillmentRiskCount, 0)

        let codes = Set(workbench.findings.map(\.code))
        XCTAssertTrue(codes.contains(.inventorySoldOutOrOversold))
        XCTAssertTrue(codes.contains(.redemptionReserved))
        XCTAssertTrue(codes.contains(.duplicateCreditDeduction))
        XCTAssertTrue(codes.contains(.fulfillmentFailed))
        XCTAssertTrue(codes.contains(.refundCancelRollbackReview))
        XCTAssertTrue(codes.contains(.physicalAddressConfirmation))
        XCTAssertTrue(codes.contains(.deviceTimeCapReview))
        XCTAssertTrue(codes.contains(.offlineReplayPending))
        XCTAssertTrue(workbench.findings.contains { $0.code == .duplicateCreditDeduction && $0.actionRequired })
        assertNoSideEffects(workbench)
    }

    func testChildHidesOrderAddressLedgerDeviceAndCreditAmount() {
        let workbench = build(role: .child)

        XCTAssertEqual(workbench.role, .child)
        XCTAssertFalse(workbench.rows.isEmpty)
        XCTAssertTrue(workbench.rows.allSatisfy(\.visibleToChild))
        XCTAssertTrue(workbench.findings.allSatisfy(\.visibleToChild))
        // 孩子只看到只读说明，不暴露任何风险发现码。
        XCTAssertEqual(workbench.findings.map(\.code), [.readOnlyReady])
        XCTAssertFalse(workbench.hasUnsafeDisplayPayload)
        assertNoSideEffects(workbench)

        let text = displayText(workbench)
        for marker in [
            "$",
            "成长积分金额",
            "账本",
            "订单",
            "库存 id",
            "履约地址",
            "收货地址",
            "退款",
            "超卖",
            "履约失败",
            "成人责任",
            "设备命令",
            "解锁",
            "order",
            "ledger",
            "device",
            "address",
            "refund"
        ] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "孩子视角泄露: \(marker)")
        }
    }

    func testChildOnlySeesRedeemableReservedNeedsParentOrUnavailable() {
        let workbench = build(role: .child)
        let allowed: Set<MobileRewardStoreFulfillmentDisplayState> = [.redeemable, .reserved, .needsParent, .unavailable]
        XCTAssertTrue(workbench.rows.allSatisfy { allowed.contains($0.state) })
        // 孩子端履约说明只指向家长流程，不暴露库存/履约细节。
        XCTAssertTrue(workbench.rows.allSatisfy { $0.fulfillmentLabel == "家长会处理领取流程" })
    }

    func testRedemptionPerformsNoSideEffectsAcrossRoles() {
        for role in MobileRewardStoreFulfillmentRole.allCases {
            let workbench = build(role: role)
            assertNoSideEffects(workbench)
            XCTAssertTrue(workbench.rows.allSatisfy { row in
                !row.redeemsReward && !row.deductsCredit && !row.shipsGoods && !row.writesOrder
                    && !row.writesInventory && !row.writesRedemption && !row.writesLedger
                    && !row.refundsPayment && !row.rollsBack && !row.grantsBadge
                    && !row.mutatesAbilityCard && !row.unlocksDevice && !row.sendsNotification
                    && !row.callsNetwork && !row.opensStoreKit && !row.callsAI
                    && !row.writesSchoolSystem && !row.hasTriggeredSideEffect
            })
        }
    }

    func testOfflineRefundAndCancelFallBackToNeedsParentOrUnavailable() {
        let workbench = build(role: .guardian)
        let byRef = Dictionary(uniqueKeysWithValues: workbench.rows.map { ($0.publicReviewRef, $0) })

        // 退款 + 重复扣成长积分 + 离线回放 → 待家长处理。
        let refundedRow = workbench.rows.first { $0.refundOrCancelRollback }
        XCTAssertNotNil(refundedRow)
        XCTAssertEqual(refundedRow?.state, .needsParent)
        XCTAssertTrue(refundedRow?.offlineReplayPending == true)
        XCTAssertTrue(refundedRow?.duplicateCreditDeduction == true)

        // 履约失败 / 售罄 → 不可兑换。
        XCTAssertTrue(workbench.rows.contains { $0.fulfillmentFailed && $0.state == .unavailable })

        // 设备时长超过每日上限 → 待家长处理。
        XCTAssertTrue(workbench.rows.contains { $0.deviceCapExceeded && $0.state == .needsParent })

        // 实物地址未确认 → 待家长处理。
        XCTAssertTrue(workbench.rows.contains { $0.addressConfirmationNeeded && $0.state == .needsParent })

        XCTAssertFalse(byRef.isEmpty)
    }

    func testUnsafePayloadFallsBackWithoutEchoingRawData() {
        var input = MobileRewardStoreFulfillmentInput.mock
        input.unsafePayload = [
            "http://192.168.1.50 order:raw ledger:raw device:raw address:raw /Users/secret sk-storetoken"
        ]

        let workbench = build(role: .guardian, input: input)

        XCTAssertTrue(workbench.rows.isEmpty)
        XCTAssertEqual(workbench.publicSummary.unavailableCount, input.items.count)
        XCTAssertEqual(workbench.publicSummary.findingCodes, [.unsafePayloadBlocked])
        XCTAssertTrue(workbench.findings.contains { $0.code == .unsafePayloadBlocked && $0.actionRequired })
        assertNoSideEffects(workbench)

        let text = displayText(workbench)
        for raw in ["192.168.1.50", "order:raw", "ledger:raw", "device:raw", "address:raw", "/Users/secret", "sk-storetoken"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(raw), "fallback 泄露原文: \(raw)")
        }
    }

    func testPublicSummaryAndDisplayValuesNeverLeakSeedsOrSensitiveMarkers() {
        for role in MobileRewardStoreFulfillmentRole.allCases {
            let text = displayText(build(role: role))
            for raw in [
                "weekend-movie",
                "long-game",
                "story-book",
                "robot-kit",
                "art-set",
                "order-movie",
                "order-robot",
                "redemption-art",
                "family-seed",
                "child-seed"
            ] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(raw), "\(role.label) 泄露内部 seed: \(raw)")
            }
            for marker in [
                "child:",
                "family:",
                "order:",
                "inventory:",
                "redemption:",
                "ledger:",
                "device:",
                "address:",
                "http://",
                "https://",
                "/Users/",
                "/Volumes/",
                "192.168."
            ] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "\(role.label) 泄露敏感标记: \(marker)")
            }
        }
    }

    func testPublicSummaryCarriesNoSideEffectFlags() {
        for role in MobileRewardStoreFulfillmentRole.allCases {
            assertNoSideEffects(build(role: role))
        }
    }

    @MainActor
    func testViewInitializersAndEntryViewsCompile() {
        _ = MobileRewardStoreInventoryFulfillmentWorkbenchView()
        _ = MobileRewardStoreInventoryFulfillmentWorkbenchView(initialRole: .child, allowedRoles: [.child])
        _ = MobileRewardStoreInventoryFulfillmentWorkbenchView(initialRole: .guardian, allowedRoles: [.guardian])
        _ = RewardRedemptionView()
        _ = RewardStatusView()
    }

    private func displayText(_ workbench: MobileRewardStoreInventoryFulfillmentWorkbench) -> String {
        workbench.displayValues.joined(separator: " ")
    }

    private func assertNoSideEffects(
        _ workbench: MobileRewardStoreInventoryFulfillmentWorkbench,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let summary = workbench.publicSummary
        XCTAssertFalse(summary.redeemsReward, file: file, line: line)
        XCTAssertFalse(summary.deductsCredit, file: file, line: line)
        XCTAssertFalse(summary.shipsGoods, file: file, line: line)
        XCTAssertFalse(summary.writesOrder, file: file, line: line)
        XCTAssertFalse(summary.writesInventory, file: file, line: line)
        XCTAssertFalse(summary.writesRedemption, file: file, line: line)
        XCTAssertFalse(summary.writesLedger, file: file, line: line)
        XCTAssertFalse(summary.refundsPayment, file: file, line: line)
        XCTAssertFalse(summary.rollsBack, file: file, line: line)
        XCTAssertFalse(summary.grantsBadge, file: file, line: line)
        XCTAssertFalse(summary.mutatesAbilityCard, file: file, line: line)
        XCTAssertFalse(summary.unlocksDevice, file: file, line: line)
        XCTAssertFalse(summary.sendsNotification, file: file, line: line)
        XCTAssertFalse(summary.callsNetwork, file: file, line: line)
        XCTAssertFalse(summary.opensStoreKit, file: file, line: line)
        XCTAssertFalse(summary.callsAI, file: file, line: line)
        XCTAssertFalse(summary.writesSchoolSystem, file: file, line: line)
        XCTAssertFalse(summary.hasTriggeredSideEffect, file: file, line: line)
    }
}
