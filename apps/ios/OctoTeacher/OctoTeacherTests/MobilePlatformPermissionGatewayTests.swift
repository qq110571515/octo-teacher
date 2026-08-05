import XCTest
@testable import OctoTeacher

final class MobilePlatformPermissionGatewayTests: XCTestCase {

    private func displayedStrings(_ snapshot: MobilePlatformPermissionGatewaySnapshot) -> [String] {
        snapshot.displayValues
    }

    private func displayedStrings(_ report: MobilePlatformPermissionGatewayReadModelReport) -> [String] {
        report.displayValues
    }

    func testGuardianGatewayShowsActionableReadOnlyGatesWithoutSideEffects() {
        let adapter = MobilePlatformPermissionGatewayAdapter()
        let snapshot: MobilePlatformPermissionGatewaySnapshot = adapter.build(viewerRole: .guardian)

        XCTAssertEqual(snapshot.viewerRole, MobilePlatformPermissionGatewayViewerRole.guardian)
        XCTAssertTrue(snapshot.gates.contains { $0.kind == MobilePlatformPermissionGateKind.growthPackInstall })
        XCTAssertGreaterThanOrEqual(snapshot.publicSummary.actionRequiredCount, 0)
        XCTAssertFalse(snapshot.sideEffects.callsFamilyControls)
        XCTAssertFalse(snapshot.sideEffects.callsCloud)
        XCTAssertFalse(snapshot.sideEffects.callsAi)
        XCTAssertFalse(snapshot.sideEffects.callsSchoolSystem)
        XCTAssertFalse(snapshot.sideEffects.chargesPayment)
        XCTAssertFalse(snapshot.sideEffects.createsOrder)
        XCTAssertFalse(snapshot.sideEffects.writesEntitlement)
        XCTAssertFalse(snapshot.sideEffects.writesLedger)
        XCTAssertFalse(snapshot.sideEffects.grantsCredit)
        XCTAssertFalse(snapshot.sideEffects.unlocksDevice)
        XCTAssertFalse(snapshot.sideEffects.hasTriggeredSideEffect)
        XCTAssertTrue(MobilePlatformPermissionGatewayAdapter.redacts(snapshot))
    }

    func testChildGatewayHidesAdultPowerAndUsesSafeCopy() throws {
        let orchestrator = MobileHomeOrchestrator(
            sync: try MobileSyncClient.makeMock(),
            schoolFamily: SchoolFamilyStore(),
            family: LocalFamilyStore()
        )
        let home = orchestrator.makeViewModel(for: .child)
        let section = try XCTUnwrap(home.sections.first { $0.id == "permission-gateway" })
        let texts = section.items.flatMap { [$0.title, $0.detail, $0.badge].compactMap { $0 } }.joined(separator: " ")

        // 分区已由共享 ReadModel 驱动：条目为 permission-module-* 而非旧的 permission-gate-*。
        XCTAssertTrue(section.items.allSatisfy { $0.id.hasPrefix("permission-module-") })
        XCTAssertTrue(section.items.contains { $0.id == "permission-module-device_control" })
        // 孩子端必须隐藏 marketplace/credit consent 等敏感共享模块。
        XCTAssertFalse(section.items.contains { $0.id == "permission-module-marketplace_entitlement" })
        XCTAssertFalse(section.items.contains { $0.id == "permission-module-credit_consent_reconciliation" })
        XCTAssertFalse(texts.contains("批准"))
        XCTAssertFalse(texts.contains("发成长积分"))
        XCTAssertFalse(texts.contains("订单"))
        XCTAssertFalse(texts.localizedCaseInsensitiveContains("entitlement"))
        XCTAssertTrue(texts.contains("家长"))
    }

    func testRelativeAndTeacherGatewaysHideGrowthPackInstallEntitlements() {
        let adapter = MobilePlatformPermissionGatewayAdapter()
        let relative = adapter.build(viewerRole: .relative)
        let teacher = adapter.build(viewerRole: .teacher)

        for snapshot in [relative, teacher] {
            let installGate = snapshot.gates.first { $0.kind == .growthPackInstall }
            XCTAssertEqual(installGate?.state, .hidden)
            XCTAssertFalse(snapshot.gates.contains { $0.kind == .creditReward && $0.state == .visible })
            XCTAssertTrue(MobilePlatformPermissionGatewayAdapter.redacts(snapshot))
        }
    }

    func testUnsafePayloadFallsBackToBlockedGateway() {
        let adapter = MobilePlatformPermissionGatewayAdapter()
        let snapshot = adapter.build(
            viewerRole: .guardian,
            unsafePayload: [
                "order:raw-123",
                "entitlement:raw-456",
                "http://192.168.1.252/private",
                "123e4567-e89b-12d3-a456-426614174000",
                "abcdef1234567890abcdef1234567890"
            ]
        )

        XCTAssertEqual(snapshot.gates.count, 1)
        XCTAssertEqual(snapshot.gates.first?.state, .blocked)
        XCTAssertEqual(snapshot.publicSummary.blockedCount, 1)
        XCTAssertTrue(snapshot.publicSummary.findingCodes.contains("unsafe_payload_blocked"))
        XCTAssertTrue(MobilePlatformPermissionGatewayAdapter.redacts(snapshot))

        let residual = displayedStrings(snapshot).joined(separator: " ")
        for marker in ["order:", "entitlement:", "http://", "192.168.", "123e4567", "abcdef1234567890"] {
            XCTAssertFalse(residual.localizedCaseInsensitiveContains(marker))
        }
    }

    func testPermissionGatewayHomeSectionIsRoleAware() throws {
        let orchestrator = MobileHomeOrchestrator(
            sync: try MobileSyncClient.makeMock(),
            schoolFamily: SchoolFamilyStore(),
            family: LocalFamilyStore()
        )
        let child = orchestrator.makeViewModel(for: .child)
        let parent = orchestrator.makeViewModel(for: .parent)

        let childSection = try XCTUnwrap(child.sections.first { $0.id == "permission-gateway" })
        let parentSection = try XCTUnwrap(parent.sections.first { $0.id == "permission-gateway" })

        // 孩子端设备控制需家长确认；家长端能看到成长积分同意对账等共享模块。
        XCTAssertTrue(childSection.items.contains { $0.id == "permission-module-device_control" && $0.badge == "需家长" })
        XCTAssertTrue(parentSection.items.contains { $0.id == "permission-module-credit_consent_reconciliation" })
        XCTAssertNotEqual(childSection.items.map(\.id), parentSection.items.map(\.id))
    }

    func testParentGatewayInheritsHomeGrowthPackAttentionMetric() throws {
        let orchestrator = MobileHomeOrchestrator(
            sync: try MobileSyncClient.makeMock(),
            schoolFamily: SchoolFamilyStore(),
            family: LocalFamilyStore()
        )
        let parent = orchestrator.makeViewModel(for: .parent)
        let metric = try XCTUnwrap(parent.metrics.first { $0.id == "growth-pack-entitlements" })
        let section = try XCTUnwrap(parent.sections.first { $0.id == "permission-gateway" })
        let installModule = try XCTUnwrap(section.items.first { $0.id == "permission-module-growth_pack_install" })

        // 成长包需关注时，共享模块进入「需家长」可见性；否则保持「可见」。
        XCTAssertEqual(installModule.badge, metric.value == "0" ? "可见" : "需家长")
    }

    func testReadModelAlignsSharedModuleKeysAndStaysReadOnly() {
        let adapter = MobilePlatformPermissionGatewayAdapter()
        let report = adapter.buildReadModel(viewerRole: .guardian, platform: .ios)

        XCTAssertEqual(report.modules.map(\.module), MobilePlatformPermissionGatewayModuleKey.allCases)
        XCTAssertEqual(report.publicSummary.viewerRole, .guardian)
        XCTAssertEqual(report.viewer.platform, .ios)
        XCTAssertFalse(report.sideEffects.hasTriggeredSideEffect)
        XCTAssertTrue(report.modules.allSatisfy { module in
            module.writesEntitlement == false
                && module.writesLedger == false
                && module.unlocksDevice == false
                && module.callsLms == false
                && module.callsAiProvider == false
                && module.sendsNotification == false
        })
        XCTAssertTrue(MobilePlatformPermissionGatewayAdapter.redacts(report))
    }

    func testChildReadModelHidesSensitiveSharedFields() {
        let adapter = MobilePlatformPermissionGatewayAdapter()
        let report = adapter.buildReadModel(viewerRole: .child)

        XCTAssertEqual(report.modules.first { $0.module == .marketplaceEntitlement }?.visibility, .hidden)
        XCTAssertEqual(report.modules.first { $0.module == .creditConsentReconciliation }?.visibility, .hidden)
        XCTAssertTrue(report.modules.allSatisfy { module in
            module.showsOrder == false
                && module.showsEntitlementDetail == false
                && module.showsProviderOrModel == false
                && module.showsConsentDetail == false
                && module.showsCreditAmount == false
                && module.showsRawTranscript == false
                && module.showsTeacherPrivateNote == false
                && module.showsCrossChildContent == false
        })
    }

    func testTeacherAndRelativeReadModelVisibilityMatchesBoundary() {
        let adapter = MobilePlatformPermissionGatewayAdapter()
        let teacher = adapter.buildReadModel(viewerRole: .teacher, platform: .cloud)
        let relative = adapter.buildReadModel(viewerRole: .relative)

        XCTAssertNotEqual(teacher.modules.first { $0.module == .schoolLmsBoundary }?.visibility, .hidden)
        XCTAssertNotEqual(teacher.modules.first { $0.module == .aiHomeworkReview }?.visibility, .hidden)
        XCTAssertEqual(teacher.modules.first { $0.module == .marketplaceEntitlement }?.visibility, .hidden)
        XCTAssertEqual(teacher.modules.first { $0.module == .creditConsentReconciliation }?.visibility, .hidden)
        XCTAssertEqual(relative.modules.first { $0.module == .growthPackInstall }?.visibility, .hidden)
        XCTAssertEqual(relative.modules.first { $0.module == .schoolLmsBoundary }?.visibility, .hidden)
        XCTAssertTrue(MobilePlatformPermissionGatewayAdapter.redacts(teacher))
        XCTAssertTrue(MobilePlatformPermissionGatewayAdapter.redacts(relative))
    }

    func testUnsafePayloadFallsBackToBlockedReadModelWithoutResidualMarkers() {
        let adapter = MobilePlatformPermissionGatewayAdapter()
        let report = adapter.buildReadModel(
            viewerRole: .guardian,
            unsafePayload: [
                "order:raw-123",
                "entitlement:raw-456",
                "provider:qwen",
                "model:secret",
                "http://192.168.1.252/private",
                "123e4567-e89b-12d3-a456-426614174000",
                "abcdef1234567890abcdef1234567890"
            ]
        )

        XCTAssertFalse(report.accepted)
        XCTAssertEqual(report.state, .blocked)
        XCTAssertEqual(report.modules.count, 1)
        XCTAssertEqual(report.modules.first?.visibility, .blocked)
        XCTAssertTrue(report.publicSummary.findingCodes.contains(.unsafePayloadBlocked))
        XCTAssertTrue(MobilePlatformPermissionGatewayAdapter.redacts(report))

        let residual = displayedStrings(report).joined(separator: " ")
        for marker in ["order:", "entitlement:", "provider:", "model:", "http://", "192.168.", "123e4567", "abcdef1234567890"] {
            XCTAssertFalse(residual.localizedCaseInsensitiveContains(marker))
        }
    }

    func testReadModelCanRenderHomeItems() {
        let adapter = MobilePlatformPermissionGatewayAdapter()
        let report = adapter.buildReadModel(viewerRole: .guardian)
        let items = adapter.homeItems(from: report)

        XCTAssertFalse(items.isEmpty)
        XCTAssertTrue(items.contains { $0.id == "permission-module-growth_pack_install" })
        XCTAssertTrue(items.allSatisfy { $0.id.hasPrefix("permission-module-") })
    }
}
