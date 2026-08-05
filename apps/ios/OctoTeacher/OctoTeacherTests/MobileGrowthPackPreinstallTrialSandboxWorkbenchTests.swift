import XCTest
@testable import OctoTeacher

/// A94 iOS 成长包安装前试运行配置沙盒测试。
///
/// 覆盖孩子/家长/创作者视角、安装权益阻断、学校优先级、成长积分建议边界、只读副作用和入口编译。
final class MobileGrowthPackPreinstallTrialSandboxWorkbenchTests: XCTestCase {

    private func build(
        role: MobileGrowthPackPreinstallTrialRole,
        installInput: GrowthPackInstallCatalogInput = .mock,
        configuration: MobileModuleConfigurationDraftSnapshot? = nil,
        unsafePayload: [String] = []
    ) -> MobileGrowthPackPreinstallTrialSandboxWorkbench {
        MobileGrowthPackPreinstallTrialSandboxBuilder().build(
            role: role,
            installInput: installInput,
            configuration: configuration,
            unsafePayload: unsafePayload
        )
    }

    func testChildSeesTrialRhythmWithoutPaymentEntitlementCreditDeviceOrAdultReasons() {
        let workbench = build(role: .child)

        XCTAssertEqual(workbench.role, .child)
        XCTAssertFalse(workbench.rows.isEmpty)
        XCTAssertTrue(workbench.rows.allSatisfy(\.visibleToChild))
        XCTAssertTrue(workbench.findings.allSatisfy(\.visibleToChild))
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(workbench.hasUnsafeDisplayPayload)

        let text = workbench.displayValues.joined(separator: " ")
        for marker in [
            "$",
            "价格",
            "订单",
            "权益",
            "创作者收益",
            "成长积分金额",
            "成人原因",
            "设备命令",
            "解锁",
            "order",
            "entitlement"
        ] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "孩子视角泄露: \(marker)")
        }
    }

    func testGuardianSeesInstallBlocksSchoolPriorityAndCreditBoundaryWithoutWritingAnything() {
        let workbench = build(role: .guardian)

        XCTAssertEqual(workbench.role, .guardian)
        XCTAssertFalse(workbench.rows.isEmpty)
        XCTAssertGreaterThan(workbench.publicSummary.blockedCount, 0)
        XCTAssertGreaterThan(workbench.publicSummary.guardianReviewCount, 0)
        XCTAssertGreaterThan(workbench.publicSummary.schoolPriorityConflictCount, 0)
        XCTAssertGreaterThan(workbench.publicSummary.creditBoundaryReviewCount, 0)
        XCTAssertTrue(workbench.findings.contains { $0.code == .schoolPriorityConflict && $0.actionRequired })
        XCTAssertTrue(workbench.findings.contains { $0.code == .creditBoundaryReview && $0.actionRequired })
        XCTAssertTrue(workbench.findings.contains { $0.code == .listingOrEntitlementBlocked && $0.actionRequired })
        assertNoSideEffects(workbench)
    }

    func testCreatorOnlyGetsRedactedTrialFeedback() {
        let workbench = build(role: .creator)

        XCTAssertEqual(workbench.role, .creator)
        XCTAssertFalse(workbench.rows.isEmpty)
        XCTAssertTrue(workbench.rows.allSatisfy(\.visibleToCreator))
        XCTAssertTrue(workbench.findings.contains { $0.code == .creatorFeedbackRedacted })
        assertNoSideEffects(workbench)

        let text = workbench.displayValues.joined(separator: " ")
        for marker in ["family", "child", "order", "entitlement", "收益", "家长预算", "设备信息"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "创作者视角泄露: \(marker)")
        }
    }

    func testAgePermissionDelistRefundRevocationAndExpiryBlockTrial() {
        var input = GrowthPackInstallCatalogInput.mock
        input.childAge = 5
        input.packs[0].permissionsGranted = false
        input.packs[1].entitlementState = .expired
        input.packs[2].listingState = .delisted
        input.packs[3].entitlementState = .revoked

        let guardian = build(role: .guardian, installInput: input)

        XCTAssertGreaterThan(guardian.publicSummary.blockedCount, 0)
        XCTAssertTrue(guardian.findings.contains { $0.code == .agePolicyBlocked })
        XCTAssertTrue(guardian.findings.contains { $0.code == .permissionPolicyBlocked })
        XCTAssertTrue(guardian.findings.contains { $0.code == .listingOrEntitlementBlocked })
        XCTAssertFalse(guardian.rows.contains { $0.state == .canTrial })
        assertNoSideEffects(guardian)
    }

    func testCleanConfigurationCanProduceReadyTrialWithoutSchoolConflict() {
        let configuration = cleanConfiguration()
        var input = GrowthPackInstallCatalogInput.mock
        input.packs = [input.packs[0]]
        input.packs[0].entitlementState = .active
        input.packs[0].permissionsGranted = true
        input.childAge = 11

        let guardian = build(role: .guardian, installInput: input, configuration: configuration)
        let row = tryUnwrap(guardian.rows.first)

        XCTAssertEqual(row.state, .canTrial)
        XCTAssertFalse(row.schoolPriorityConflict)
        XCTAssertFalse(row.creditNeedsGuardianReview)
        XCTAssertTrue(guardian.findings.contains { $0.code == .readOnlyReady && !$0.actionRequired })
        assertNoSideEffects(guardian)
    }

    func testUnsafePayloadFallsBackWithoutEchoingRawInstallData() {
        var input = GrowthPackInstallCatalogInput.mock
        input.packs[0].summary = "http://192.168.1.252 order:raw entitlement:raw token sk-test"

        let workbench = build(role: .guardian, installInput: input)

        XCTAssertTrue(workbench.rows.isEmpty)
        XCTAssertEqual(workbench.publicSummary.findingCodes, [.unsafePayloadBlocked])
        assertNoSideEffects(workbench)

        let text = workbench.displayValues.joined(separator: " ")
        for raw in ["192.168.1.252", "order:raw", "entitlement:raw", "sk-test"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(raw), "fallback 泄露原文: \(raw)")
        }
    }

    func testPublicSummaryAndRowsNeverTriggerSideEffects() {
        for role in MobileGrowthPackPreinstallTrialRole.allCases {
            let workbench = build(role: role)
            assertNoSideEffects(workbench)
            XCTAssertTrue(workbench.rows.allSatisfy { row in
                !row.purchasesPack && !row.refundsPayment && !row.installsPack
                    && !row.createsAssignment && !row.writesEntitlement && !row.writesOrder
                    && !row.writesLedger && !row.grantsCredit && !row.grantsBadge
                    && !row.mutatesAbilityCard && !row.unlocksDevice && !row.sendsNotification
                    && !row.callsNetwork && !row.opensWebView && !row.callsAI && !row.writesSchoolSystem
            })
        }
    }

    func testDisplayValuesDoNotLeakRawIdsOrSensitiveMarkers() {
        for role in MobileGrowthPackPreinstallTrialRole.allCases {
            let text = build(role: role).displayValues.joined(separator: " ")
            for raw in [
                "electric-basics-v1",
                "official-maker",
                "order-morning",
                "ent-morning",
                "old-game-proof",
                "creator-art-vlog"
            ] {
                XCTAssertFalse(text.contains(raw), "\(role.label) 泄露内部 seed: \(raw)")
            }
            for marker in ["child:", "family:", "order:", "entitlement:", "ledger:", "device:", "http://", "https://", "/Users/", "/Volumes/", "192.168."] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "\(role.label) 泄露敏感标记: \(marker)")
            }
        }
    }

    @MainActor
    func testViewInitializersAndEntryViewsCompile() {
        _ = MobileGrowthPackPreinstallTrialSandboxWorkbenchView()
        _ = MobileGrowthPackPreinstallTrialSandboxWorkbenchView(initialRole: .child, allowedRoles: [.child])
        _ = MobileGrowthPackPreinstallTrialSandboxWorkbenchView(initialRole: .guardian, allowedRoles: [.guardian])
        _ = MobileGrowthPackPreinstallTrialSandboxWorkbenchView(initialRole: .creator, allowedRoles: [.creator])
        _ = GrowthPackInstallEntitlementView()
        _ = MobileModuleConfigurationDraftView()
    }

    private func cleanConfiguration() -> MobileModuleConfigurationDraftSnapshot {
        MobileModuleConfigurationDraftSnapshot(
            generatedAt: "2026-06-24T22:20:00Z",
            viewerRole: .guardian,
            status: .ready,
            headline: "干净试运行草稿",
            items: [
                MobileModuleConfigurationDraftItem(
                    publicItemRef: "mcd-clean",
                    moduleKey: .growthPackRuntime,
                    dayPart: .afterSchool,
                    title: "成长包试运行",
                    detail: "只读试运行。",
                    estimatedMinutes: 20,
                    creditPreviewMinutes: nil,
                    requiresGuardianApproval: false,
                    warning: nil
                )
            ],
            reviewActions: [],
            findings: [
                MobileModuleConfigurationFinding(
                    code: .draftReady,
                    severity: .ok,
                    message: "草稿可预览。",
                    publicRef: "mcd-finding-clean"
                )
            ],
            publicSummary: MobileModuleConfigurationPublicSummary(
                generatedAt: "2026-06-24T22:20:00Z",
                viewerRole: .guardian,
                status: .ready,
                visibleItemCount: 1,
                hiddenItemCount: 0,
                estimatedMinutesTotal: 20,
                creditPreviewTotal: nil,
                reviewActionCount: 0,
                blockingActionCount: 0,
                findingCodes: [.draftReady]
            ),
            sideEffects: MobileModuleConfigurationSideEffects()
        )
    }

    private func assertNoSideEffects(
        _ workbench: MobileGrowthPackPreinstallTrialSandboxWorkbench,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let summary = workbench.publicSummary
        XCTAssertFalse(summary.purchasesPack, file: file, line: line)
        XCTAssertFalse(summary.refundsPayment, file: file, line: line)
        XCTAssertFalse(summary.installsPack, file: file, line: line)
        XCTAssertFalse(summary.createsAssignment, file: file, line: line)
        XCTAssertFalse(summary.writesEntitlement, file: file, line: line)
        XCTAssertFalse(summary.writesOrder, file: file, line: line)
        XCTAssertFalse(summary.writesLedger, file: file, line: line)
        XCTAssertFalse(summary.grantsCredit, file: file, line: line)
        XCTAssertFalse(summary.grantsBadge, file: file, line: line)
        XCTAssertFalse(summary.mutatesAbilityCard, file: file, line: line)
        XCTAssertFalse(summary.unlocksDevice, file: file, line: line)
        XCTAssertFalse(summary.sendsNotification, file: file, line: line)
        XCTAssertFalse(summary.callsNetwork, file: file, line: line)
        XCTAssertFalse(summary.opensWebView, file: file, line: line)
        XCTAssertFalse(summary.callsAI, file: file, line: line)
        XCTAssertFalse(summary.writesSchoolSystem, file: file, line: line)
        XCTAssertFalse(summary.hasTriggeredSideEffect, file: file, line: line)
    }

    private func tryUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) -> T {
        guard let value else {
            XCTFail("Expected value", file: file, line: line)
            fatalError("Expected value")
        }
        return value
    }
}
