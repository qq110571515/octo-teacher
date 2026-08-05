import XCTest
@testable import OctoTeacher

final class GrowthPackInstallEntitlementTests: XCTestCase {
    private let builder = GrowthPackInstallEntitlementBuilder()

    private func snapshot(
        role: GrowthPackInstallViewerRole,
        input: GrowthPackInstallCatalogInput = .mock,
        salt: String = "growth-pack-install-entitlement-ios-v1"
    ) -> GrowthPackInstallSnapshot {
        GrowthPackInstallEntitlementBuilder(redactionSalt: salt).build(viewerRole: role, input: input)
    }

    func testGuardianSeesInstallEntitlementAndRefundDetails() {
        let snap = snapshot(role: .guardian)

        XCTAssertEqual(snap.viewerRole, .guardian)
        XCTAssertTrue(snap.visibility.canSeePrice)
        XCTAssertTrue(snap.visibility.canSeeOrderAndEntitlement)
        XCTAssertTrue(snap.decisions.contains { $0.state == .installable && $0.priceLabel == "$4.99" })
        XCTAssertTrue(snap.decisions.contains { $0.state == .installed && $0.entitlementPublicRef != nil })
        XCTAssertTrue(snap.decisions.contains { $0.state == .frozen && $0.refundWindowOpen == false })
        XCTAssertTrue(snap.findings.contains { $0.code == .entitlementRefundedOrRevoked })
        XCTAssertTrue(snap.findings.contains { $0.code == .permissionPolicyBlocked })
    }

    func testChildViewRedactsMoneyOrderEntitlementAndInternalReasons() {
        let child = snapshot(role: .child)

        XCTAssertFalse(child.visibility.canSeePrice)
        XCTAssertFalse(child.visibility.canSeeOrderAndEntitlement)
        XCTAssertTrue(child.decisions.allSatisfy { $0.priceLabel == nil })
        XCTAssertTrue(child.decisions.allSatisfy { $0.orderPublicRef == nil && $0.entitlementPublicRef == nil })
        XCTAssertTrue(child.decisions.allSatisfy { $0.requiredPermissionLabels.isEmpty })
        XCTAssertFalse(String(describing: child).contains("$4.99"))
        XCTAssertFalse(String(describing: child).contains("order-morning"))
        XCTAssertFalse(String(describing: child).contains("ent-morning"))
        XCTAssertTrue(child.findings.contains { $0.code == .childVisibilityRedacted })
    }

    func testRefundRevocationDelistingAgeAndPermissionBlockers() {
        let guardian = snapshot(role: .guardian)
        let states = guardian.decisions.map(\.state)

        XCTAssertTrue(states.contains(.frozen))
        XCTAssertTrue(states.contains(.blocked))
        XCTAssertTrue(guardian.findings.contains { $0.code == .listingDelisted })
        XCTAssertTrue(guardian.findings.contains { $0.code == .entitlementRefundedOrRevoked })
        XCTAssertTrue(guardian.findings.contains { $0.code == .agePolicyBlocked })
        XCTAssertTrue(guardian.findings.contains { $0.code == .permissionPolicyBlocked })
    }

    func testRelativeAndCreatorViewsAreCropped() {
        let relative = snapshot(role: .relative)
        let creator = snapshot(role: .creator)

        XCTAssertFalse(relative.visibility.canSeePrice)
        XCTAssertFalse(relative.visibility.canSeeOrderAndEntitlement)
        XCTAssertTrue(relative.decisions.allSatisfy { $0.priceLabel == nil && $0.entitlementPublicRef == nil })
        XCTAssertTrue(relative.findings.contains { $0.code == .relativeVisibilityRedacted })

        XCTAssertTrue(creator.visibility.canSeeCreatorListingState)
        XCTAssertFalse(creator.visibility.canSeeOrderAndEntitlement)
        XCTAssertTrue(creator.decisions.contains { $0.listingLabel == GrowthPackMarketListingState.delisted.label })
        XCTAssertTrue(creator.decisions.allSatisfy { $0.orderPublicRef == nil && $0.entitlementPublicRef == nil })
        XCTAssertTrue(creator.findings.contains { $0.code == .creatorVisibilityRedacted })
    }

    func testSnapshotIsStableAndRedacted() {
        let first = snapshot(role: .guardian)
        let second = snapshot(role: .guardian)
        let changedSalt = snapshot(role: .guardian, salt: "different-install-salt")

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first.publicSummary.catalogPublicRef, changedSalt.publicSummary.catalogPublicRef)
        XCTAssertFalse(GrowthPackInstallEntitlementBuilder.reportLeaks(first))

        let serialized = String(describing: first)
        for marker in ["child:", "family:", "pack:", "creator:", "order:", "entitlement:", "http://", "https://", "192.168.", "/Users/", "/Volumes/", "file://"] {
            XCTAssertFalse(serialized.lowercased().contains(marker.lowercased()), "泄漏 marker: \(marker)")
        }
    }

    func testPublicSummaryAndDecisionsAreSideEffectFree() {
        let summary = snapshot(role: .guardian).publicSummary
        XCTAssertFalse(summary.chargesPayment)
        XCTAssertFalse(summary.createsOrder)
        XCTAssertFalse(summary.writesMarketplace)
        XCTAssertFalse(summary.writesEntitlement)
        XCTAssertFalse(summary.writesBilling)
        XCTAssertFalse(summary.callsCloud)
        XCTAssertFalse(summary.fetchesCdn)
        XCTAssertFalse(summary.sendsNotification)
        XCTAssertFalse(summary.writesLedger)
        XCTAssertFalse(summary.grantsCredit)
        XCTAssertFalse(summary.unlocksDevice)
        XCTAssertFalse(summary.callsAi)
        XCTAssertFalse(summary.writesSchoolSystem)

        for decision in snapshot(role: .guardian).decisions {
            XCTAssertFalse(decision.chargesPayment)
            XCTAssertFalse(decision.writesMarketplace)
            XCTAssertFalse(decision.writesEntitlement)
            XCTAssertFalse(decision.writesLedger)
            XCTAssertFalse(decision.grantsCredit)
            XCTAssertFalse(decision.unlocksDevice)
            XCTAssertFalse(decision.callsCloud)
        }
    }

    func testUnsafeInputFallsBackToBlockedSnapshotWithoutRawPayload() {
        var input = GrowthPackInstallCatalogInput.mock
        input.familySeed = "family:raw-1"
        input.packs[0].title = "http://192.168.1.9/internal /Users/secret entitlement:raw"

        let blocked = snapshot(role: .guardian, input: input)
        XCTAssertTrue(blocked.decisions.isEmpty)
        XCTAssertEqual(blocked.publicSummary.blockedCount, 1)
        XCTAssertTrue(blocked.findings.contains { $0.code == .unsafePayloadBlocked })
        XCTAssertFalse(String(describing: blocked).contains("192.168.1.9"))
        XCTAssertFalse(String(describing: blocked).contains("entitlement:raw"))
    }
}
