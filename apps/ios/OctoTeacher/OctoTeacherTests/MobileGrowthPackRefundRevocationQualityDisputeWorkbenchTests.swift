import XCTest
@testable import OctoTeacher

/// A95 iOS 成长包退款、撤权、质量争议复核安全壳测试。
///
/// 覆盖孩子/家长/创作者视角、云镜像与安装权益组合、进度保留、成长积分冻结、
/// 不安全负载阻断、无副作用边界和入口视图编译。
final class MobileGrowthPackRefundRevocationQualityDisputeWorkbenchTests: XCTestCase {

    private func build(
        role: MobileGrowthPackRefundDisputeRole,
        input: MobileGrowthPackRefundDisputeInput = .mock
    ) -> MobileGrowthPackRefundDisputeWorkbench {
        MobileGrowthPackRefundRevocationQualityDisputeBuilder().build(role: role, input: input)
    }

    func testGuardianSeesRefundRevocationQualityProgressAndCreditBoundaries() {
        let workbench = build(role: .guardian)

        XCTAssertEqual(workbench.role, .guardian)
        XCTAssertFalse(workbench.rows.isEmpty)
        XCTAssertGreaterThan(workbench.publicSummary.reviewRequiredCount, 0)
        XCTAssertGreaterThan(workbench.publicSummary.frozenCount, 0)
        XCTAssertGreaterThan(workbench.publicSummary.blockedCount, 0)
        XCTAssertGreaterThan(workbench.publicSummary.completedProgressPreservedCount, 0)
        XCTAssertGreaterThan(workbench.publicSummary.creditRollbackReviewCount, 0)
        XCTAssertTrue(workbench.findings.contains { $0.code == .refundWindowReview || $0.code == .revocationOrDelistBlocked })
        XCTAssertTrue(workbench.findings.contains { $0.code == .qualityDisputeFrozen && $0.actionRequired })
        XCTAssertTrue(workbench.findings.contains { $0.code == .progressRetentionReview })
        XCTAssertTrue(workbench.findings.contains { $0.code == .creditRollbackReview && $0.actionRequired })
        assertNoSideEffects(workbench)
    }

    func testChildSeesSafeDowngradeWithoutPaymentEntitlementBudgetDisputeOrDeviceCopy() {
        let workbench = build(role: .child)

        XCTAssertEqual(workbench.role, .child)
        XCTAssertFalse(workbench.rows.isEmpty)
        XCTAssertTrue(workbench.rows.allSatisfy(\.visibleToChild))
        XCTAssertTrue(workbench.findings.allSatisfy(\.visibleToChild))
        XCTAssertFalse(workbench.hasUnsafeDisplayPayload)
        assertNoSideEffects(workbench)

        let text = displayText(workbench)
        for marker in [
            "$",
            "价格",
            "订单",
            "权益",
            "退款",
            "撤权",
            "质量争议",
            "创作者收益",
            "成人责任",
            "预算",
            "账本",
            "设备",
            "解锁",
            "order",
            "entitlement",
            "refund",
            "dispute",
            "ledger",
            "device"
        ] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "孩子视角泄露: \(marker)")
        }
    }

    func testCreatorOnlyGetsRedactedFeedbackAndNoFamilyOrTransactionContext() {
        let workbench = build(role: .creator)

        XCTAssertEqual(workbench.role, .creator)
        XCTAssertFalse(workbench.rows.isEmpty)
        XCTAssertTrue(workbench.rows.allSatisfy(\.visibleToCreator))
        XCTAssertTrue(workbench.findings.contains { $0.code == .creatorFeedbackRedacted })
        XCTAssertTrue(workbench.rows.contains { $0.creatorFeedback?.isEmpty == false })
        assertNoSideEffects(workbench)

        let text = displayText(workbench)
        for marker in [
            "$",
            "家庭",
            "孩子",
            "订单",
            "权益",
            "退款",
            "预算",
            "成长积分金额",
            "设备",
            "order",
            "entitlement",
            "refund",
            "child:",
            "family:",
            "guardian:"
        ] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "创作者视角泄露: \(marker)")
        }
    }

    func testCreatorFeedbackSummaryIsSanitizedWhenItContainsPrivateContext() {
        var input = MobileGrowthPackRefundDisputeInput.mock
        input.qualityDisputes[0].creatorVisibleSummary = "家庭反馈提到孩子设备和预算，需要内部处理。"

        let workbench = build(role: .creator, input: input)

        XCTAssertTrue(workbench.rows.contains { $0.creatorFeedback == "已收到脱敏质量反馈。" })
        assertNoSideEffects(workbench)

        let text = displayText(workbench)
        for marker in ["家庭", "孩子", "设备", "预算"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "创作者反馈未清洗: \(marker)")
        }
    }

    func testUnsafePayloadFallsBackWithoutEchoingRawInstallOrNetworkData() {
        var input = MobileGrowthPackRefundDisputeInput.mock
        input.unsafePayload = [
            "http://192.168.1.252 refund:raw entitlement:raw order:raw /Users/secret sk-testtoken"
        ]

        let workbench = build(role: .guardian, input: input)

        XCTAssertTrue(workbench.rows.isEmpty)
        XCTAssertEqual(workbench.publicSummary.blockedCount, input.installInput.packs.count)
        XCTAssertEqual(workbench.publicSummary.findingCodes, [.unsafePayloadBlocked])
        XCTAssertTrue(workbench.findings.contains { $0.code == .unsafePayloadBlocked && $0.actionRequired })
        assertNoSideEffects(workbench)

        let text = displayText(workbench)
        for raw in ["192.168.1.252", "refund:raw", "entitlement:raw", "order:raw", "/Users/secret", "sk-testtoken"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(raw), "fallback 泄露原文: \(raw)")
        }
    }

    func testPublicSummaryRowsAndFindingsNeverTriggerSideEffects() {
        for role in MobileGrowthPackRefundDisputeRole.allCases {
            let workbench = build(role: role)

            assertNoSideEffects(workbench)
            XCTAssertTrue(workbench.rows.allSatisfy { row in
                !row.chargesPayment && !row.refundsPayment && !row.restoresEntitlement
                    && !row.writesEntitlement && !row.writesOrder && !row.writesLedger
                    && !row.grantsCredit && !row.deductsCredit && !row.grantsBadge
                    && !row.mutatesAbilityCard && !row.unlocksDevice && !row.sendsNotification
                    && !row.callsNetwork && !row.opensStoreKit && !row.callsAI && !row.writesSchoolSystem
                    && !row.hasTriggeredSideEffect
            })
        }
    }

    func testDisplayValuesDoNotLeakRawSeedsOrSensitiveMarkers() {
        for role in MobileGrowthPackRefundDisputeRole.allCases {
            let text = displayText(build(role: role))
            for raw in [
                "electric-basics-v1",
                "morning-routine-v2",
                "creator-art-vlog",
                "old-game-proof",
                "order-art",
                "ent-art",
                "order-game",
                "ent-game"
            ] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(raw), "\(role.label) 泄露内部 seed: \(raw)")
            }
            for marker in [
                "child:",
                "family:",
                "guardian:",
                "order:",
                "entitlement:",
                "refund:",
                "dispute:",
                "ledger:",
                "device:",
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

    @MainActor
    func testViewInitializersAndEntryViewsCompile() {
        _ = MobileGrowthPackRefundRevocationQualityDisputeWorkbenchView()
        _ = MobileGrowthPackRefundRevocationQualityDisputeWorkbenchView(initialRole: .child, allowedRoles: [.child])
        _ = MobileGrowthPackRefundRevocationQualityDisputeWorkbenchView(initialRole: .guardian, allowedRoles: [.guardian])
        _ = MobileGrowthPackRefundRevocationQualityDisputeWorkbenchView(initialRole: .creator, allowedRoles: [.creator])
        _ = GrowthPackInstallEntitlementView(initialRole: .guardian, allowsRoleSwitching: false)
        _ = GrowthPackCloudSyncMobileBridgeView(initialRole: .guardian, allowsRoleSwitching: false)
    }

    private func displayText(_ workbench: MobileGrowthPackRefundDisputeWorkbench) -> String {
        workbench.displayValues.joined(separator: " ")
    }

    private func assertNoSideEffects(
        _ workbench: MobileGrowthPackRefundDisputeWorkbench,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let summary = workbench.publicSummary
        XCTAssertFalse(summary.chargesPayment, file: file, line: line)
        XCTAssertFalse(summary.refundsPayment, file: file, line: line)
        XCTAssertFalse(summary.restoresEntitlement, file: file, line: line)
        XCTAssertFalse(summary.writesEntitlement, file: file, line: line)
        XCTAssertFalse(summary.writesOrder, file: file, line: line)
        XCTAssertFalse(summary.writesLedger, file: file, line: line)
        XCTAssertFalse(summary.grantsCredit, file: file, line: line)
        XCTAssertFalse(summary.deductsCredit, file: file, line: line)
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
