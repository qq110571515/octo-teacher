import XCTest
@testable import OctoTeacher

final class GrowthPackCloudSyncMobileBridgeTests: XCTestCase {
    private func snapshot(
        role: GrowthPackCloudSyncMobileBridgeViewerRole,
        input: GrowthPackCloudSyncMobileBridgeInput? = nil,
        salt: String = "growth-pack-cloud-sync-mobile-bridge-ios-v1"
    ) -> GrowthPackCloudSyncMobileBridgeSnapshot {
        GrowthPackCloudSyncMobileBridgeBuilder(redactionSalt: salt).build(viewerRole: role, input: input)
    }

    private func input(
        role: GrowthPackCloudSyncMobileBridgeViewerRole = .guardian,
        cloudState: GrowthPackCloudSyncMobileBridgeCloudState = .fresh,
        offlineStatus: MobileOfflinePublicStatus = .clean,
        offlineReport: MobileOfflineReplayReport = .empty,
        consentRevoked: Bool = false,
        creditFrozen: Bool = false,
        unsafePayload: [String] = []
    ) -> GrowthPackCloudSyncMobileBridgeInput {
        GrowthPackCloudSyncMobileBridgeInput(
            generatedAt: "2026-06-24T15:10:00Z",
            installSnapshot: GrowthPackInstallEntitlementBuilder().build(viewerRole: installRole(for: role)),
            permissionReport: MobilePlatformPermissionGatewayAdapter().buildReadModel(viewerRole: permissionRole(for: role)),
            offlineStatus: offlineStatus,
            offlineReport: offlineReport,
            cloudState: cloudState,
            consentRevoked: consentRevoked,
            creditFrozen: creditFrozen,
            unsafePayload: unsafePayload
        )
    }

    func testChildBridgeHidesSensitiveFieldsAndStaysSideEffectFree() {
        let child = snapshot(role: .child)

        XCTAssertEqual(child.viewerRole, .child)
        XCTAssertTrue(child.visibility.canSeeHome)
        XCTAssertTrue(child.visibility.canSeeDetail)
        XCTAssertFalse(child.visibility.canSeeGuardianReview)
        XCTAssertFalse(child.homeCards.isEmpty)
        XCTAssertTrue(child.homeCards.allSatisfy { card in
            !card.showsPrice
                && !card.showsOrderOrEntitlement
                && !card.showsCreditAmount
                && !card.showsCloudInternalState
                && !card.writesCloud
                && !card.grantsCredit
                && !card.unlocksDevice
        })
        XCTAssertTrue(child.detailItems.allSatisfy { item in
            !item.showsOrderOrEntitlement
                && !item.showsGuardianConsentDetail
                && !item.showsCreditAmount
                && !item.writesSystem
        })
        XCTAssertTrue(child.findings.contains { $0.code == .childSensitiveFieldsHidden })
        XCTAssertFalse(child.sideEffects.hasTriggeredSideEffect)
    }

    func testGuardianSeesReviewSignalsButDoesNotWriteSystems() {
        let guardian = snapshot(role: .guardian)

        XCTAssertEqual(guardian.viewerRole, .guardian)
        XCTAssertTrue(guardian.visibility.canSeeGuardianReview)
        XCTAssertTrue(guardian.publicSummary.actionRequiredCount > 0)
        XCTAssertTrue(guardian.findings.contains { $0.code == .localDraftPending })
        XCTAssertTrue(guardian.findings.contains { $0.code == .creditFrozen })
        XCTAssertFalse(guardian.publicSummary.callsCloud)
        XCTAssertFalse(guardian.publicSummary.writesCloud)
        XCTAssertFalse(guardian.publicSummary.writesEntitlement)
        XCTAssertFalse(guardian.publicSummary.writesLedger)
        XCTAssertFalse(guardian.publicSummary.grantsCredit)
        XCTAssertFalse(guardian.publicSummary.unlocksDevice)
        XCTAssertFalse(guardian.sideEffects.hasTriggeredSideEffect)
    }

    func testRelativeCreatorAndOperationsVisibilityIsCropped() {
        let relative = snapshot(role: .relative)
        let creator = snapshot(role: .creator)
        let operations = snapshot(role: .operations)

        XCTAssertTrue(relative.visibility.canSeeHome)
        XCTAssertFalse(relative.visibility.canSeeDetail)
        XCTAssertTrue(relative.detailItems.isEmpty)
        XCTAssertNil(relative.offlinePrompt)
        XCTAssertTrue(relative.findings.contains { $0.code == .nonGuardianSensitiveFieldsHidden })

        XCTAssertTrue(creator.visibility.canSeeDetail)
        XCTAssertFalse(creator.visibility.canSeeGuardianReview)
        XCTAssertNil(creator.offlinePrompt)
        XCTAssertTrue(creator.detailItems.allSatisfy { !$0.showsOrderOrEntitlement && !$0.showsCrossChildContent })

        XCTAssertFalse(operations.visibility.canSeeHome)
        XCTAssertTrue(operations.visibility.canSeeOperationsSummary)
        XCTAssertEqual(operations.homeCards.count, 1)
        XCTAssertEqual(operations.homeCards.first?.surface, .operationsSummary)
        XCTAssertTrue(operations.detailItems.allSatisfy { $0.surface == .operationsSummary })
    }

    func testOfflineConflictAndReplayRollbackRequireReview() {
        let replayReport = MobileOfflineReplayReport(
            results: [
                MobileOfflineReplayResult(
                    clientMutationRef: "offline-conflict-demo",
                    kind: .childTaskSubmission,
                    actorRole: .child,
                    status: .conflict,
                    conflictReason: .staleVersion,
                    message: "本地内容已过期",
                    nextStep: "联网刷新后再提交一次"
                ),
                MobileOfflineReplayResult(
                    clientMutationRef: "offline-rollback-demo",
                    kind: .rewardRequest,
                    actorRole: .child,
                    status: .rolledBack,
                    conflictReason: .supersededByGuardian,
                    message: "家长已在另一处做了处理",
                    nextStep: "以家长侧最新处理为准"
                )
            ],
            replayedAt: "2026-06-24T15:11:00Z"
        )
        let bridge = snapshot(
            role: .guardian,
            input: input(
                cloudState: .fresh,
                offlineStatus: MobileOfflinePublicStatus(pendingCount: 1, conflictCount: 1, rolledBackCount: 0),
                offlineReport: replayReport
            )
        )

        XCTAssertEqual(bridge.state, .conflict)
        XCTAssertEqual(bridge.publicSummary.offlineAttentionCount, 3)
        XCTAssertTrue(bridge.offlinePrompt?.actionRequired == true)
        XCTAssertTrue(bridge.findings.contains { $0.code == .offlineConflict })
        XCTAssertFalse(bridge.sideEffects.hasTriggeredSideEffect)
    }

    func testRefundRevocationDelistConsentAndCreditFreezeBlockOrFreeze() {
        let refunded = snapshot(role: .guardian, input: input(cloudState: .refunded))
        let revoked = snapshot(role: .guardian, input: input(cloudState: .revoked))
        let delisted = snapshot(role: .guardian, input: input(cloudState: .delisted))
        let consent = snapshot(role: .guardian, input: input(consentRevoked: true))
        let credit = snapshot(role: .guardian, input: input(creditFrozen: true))

        XCTAssertEqual(refunded.state, .blocked)
        XCTAssertTrue(refunded.findings.contains { $0.code == .refundOrRevocationBlocked })
        XCTAssertEqual(revoked.state, .blocked)
        XCTAssertTrue(revoked.findings.contains { $0.code == .refundOrRevocationBlocked })
        XCTAssertEqual(delisted.state, .blocked)
        XCTAssertTrue(delisted.findings.contains { $0.code == .packDelisted })
        XCTAssertEqual(consent.state, .blocked)
        XCTAssertTrue(consent.findings.contains { $0.code == .consentRevoked })
        XCTAssertEqual(credit.state, .frozen)
        XCTAssertTrue(credit.findings.contains { $0.code == .creditFrozen })
    }

    func testUnsafePayloadFallsBackToBlockedSnapshot() {
        let blocked = snapshot(
            role: .guardian,
            input: input(
                unsafePayload: [
                    "http://192.168.1.253:8080/v1",
                    "/Users/developer/secret entitlement:raw"
                ]
            )
        )

        XCTAssertEqual(blocked.state, .blocked)
        XCTAssertTrue(blocked.homeCards.isEmpty)
        XCTAssertTrue(blocked.detailItems.isEmpty)
        XCTAssertEqual(blocked.findings.first?.code, .publicSummaryLeak)
        XCTAssertFalse(String(describing: blocked).contains("192.168.1.253"))
        XCTAssertFalse(String(describing: blocked).contains("entitlement:raw"))
    }

    func testSnapshotIsStableRedactedAndSalted() {
        let first = snapshot(role: .guardian, input: input(cloudState: .localDraftPending, creditFrozen: true))
        let second = snapshot(role: .guardian, input: input(cloudState: .localDraftPending, creditFrozen: true))
        let changedSalt = snapshot(
            role: .guardian,
            input: input(cloudState: .localDraftPending, creditFrozen: true),
            salt: "different-growth-pack-cloud-sync-bridge-salt"
        )
        let displayed = displayText(first)

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first.publicSummary.bridgePublicRef, changedSalt.publicSummary.bridgePublicRef)
        XCTAssertTrue(GrowthPackCloudSyncMobileBridgeBuilder().redacts(first))
        for marker in ["child:", "family:", "pack:", "creator:", "order:", "entitlement:", "credit:", "cloud:", "http://", "https://", "192.168.", "/Users/", "/Volumes/", "file://"] {
            XCTAssertFalse(displayed.lowercased().contains(marker.lowercased()), "泄漏 marker: \(marker)")
        }
    }

    private func displayText(_ snapshot: GrowthPackCloudSyncMobileBridgeSnapshot) -> String {
        var values = [snapshot.generatedAt, snapshot.viewerRole.rawValue, snapshot.state.rawValue, snapshot.headline]
        values.append(contentsOf: snapshot.homeCards.flatMap {
            [$0.publicCardRef, $0.surface.rawValue, $0.title, $0.detail, $0.badge, $0.state.rawValue]
        })
        values.append(contentsOf: snapshot.detailItems.flatMap {
            [$0.publicItemRef, $0.surface.rawValue, $0.title, $0.detail]
        })
        if let offlinePrompt = snapshot.offlinePrompt {
            values.append(contentsOf: [offlinePrompt.publicItemRef, offlinePrompt.surface.rawValue, offlinePrompt.title, offlinePrompt.detail])
        }
        values.append(contentsOf: snapshot.findings.flatMap {
            [$0.code.rawValue, $0.severity.rawValue, $0.message, $0.publicRef]
        })
        values.append(contentsOf: [
            snapshot.publicSummary.bridgePublicRef,
            "\(snapshot.publicSummary.visibleCardCount)",
            "\(snapshot.publicSummary.visibleDetailCount)",
            "\(snapshot.publicSummary.actionRequiredCount)",
            "\(snapshot.publicSummary.offlineAttentionCount)"
        ])
        return values.joined(separator: " ")
    }

    private func installRole(
        for role: GrowthPackCloudSyncMobileBridgeViewerRole
    ) -> GrowthPackInstallViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .operations: return .guardian
        case .relative: return .relative
        case .creator: return .creator
        }
    }

    private func permissionRole(
        for role: GrowthPackCloudSyncMobileBridgeViewerRole
    ) -> MobilePlatformPermissionGatewayViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .creator, .operations: return .guardian
        case .relative: return .relative
        }
    }
}
