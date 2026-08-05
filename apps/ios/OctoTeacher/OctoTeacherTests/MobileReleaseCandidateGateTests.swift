import XCTest
@testable import OctoTeacher

final class MobileReleaseCandidateGateTests: XCTestCase {

    private let builder = MobileReleaseCandidateGateBuilder()

    func testGuardianSeesDetailedReleaseGateChecks() {
        let snapshot = builder.build(viewerRole: .guardian)

        XCTAssertEqual(snapshot.viewerRole, .guardian)
        XCTAssertGreaterThanOrEqual(snapshot.checks.count, 10)
        XCTAssertTrue(snapshot.checks.contains { $0.kind == .moduleKeys })
        XCTAssertTrue(snapshot.checks.contains { $0.kind == .permissionGateway })
        XCTAssertTrue(snapshot.checks.contains { $0.kind == .rollbackGate })
        XCTAssertTrue(snapshot.publicSummary.visibleCheckCount >= 10)
        XCTAssertTrue(builder.redacts(snapshot))
    }

    func testChildGetsSafeSummaryWithoutInternalGateDetails() {
        let snapshot = builder.build(viewerRole: .child)

        XCTAssertEqual(snapshot.viewerRole, .child)
        XCTAssertTrue(snapshot.checks.allSatisfy(\.visibleToChild))
        XCTAssertFalse(snapshot.checks.contains { $0.kind == .moduleKeys })
        XCTAssertFalse(snapshot.checks.contains { $0.kind == .evidence })
        XCTAssertFalse(snapshot.displayValues.joined(separator: " ").localizedCaseInsensitiveContains("provider"))
        XCTAssertFalse(snapshot.displayValues.joined(separator: " ").localizedCaseInsensitiveContains("model"))
        XCTAssertTrue(builder.redacts(snapshot))
    }

    func testPublicSummaryAndSideEffectsAreReadOnly() {
        let snapshot = builder.build(viewerRole: .operations)
        let summary = snapshot.publicSummary

        XCTAssertFalse(snapshot.sideEffects.hasTriggeredSideEffect)
        XCTAssertFalse(summary.writesLedger)
        XCTAssertFalse(summary.unlocksDevice)
        XCTAssertFalse(summary.writesSchoolSystem)
        XCTAssertFalse(summary.callsLms)
        XCTAssertFalse(summary.sendsNotification)
        XCTAssertFalse(summary.uploadsAttachment)
        XCTAssertFalse(summary.callsAiProvider)
        XCTAssertFalse(summary.callsLocalModel)
        XCTAssertFalse(summary.callsCloud)
        XCTAssertFalse(summary.writesEntitlement)
        XCTAssertFalse(summary.createsOrder)
    }

    func testUnsafePayloadFallsBackToBlockedSnapshot() {
        let input = MobileReleaseCandidateGateInput.mock(
            viewerRole: .guardian,
            unsafePayload: ["http://192.168.1.99/private-token"]
        )

        let snapshot = builder.build(viewerRole: .guardian, input: input)

        XCTAssertEqual(snapshot.status, .blocked)
        XCTAssertEqual(snapshot.publicSummary.findingCodes, [.publicSummaryLeak])
        XCTAssertEqual(snapshot.checks.first?.findingCode, .publicSummaryLeak)
        XCTAssertTrue(builder.redacts(snapshot))
        XCTAssertFalse(snapshot.displayValues.joined(separator: " ").contains("192.168.1.99"))
    }

    func testMissingEvidenceAndRollbackGateBlockReleaseCandidate() {
        let evidence = MobileReleaseCandidateGateEvidence(
            hasIosUnitTests: false,
            hasSnapshotFixtures: true,
            hasQwenReview: false,
            hasBridgeReport: true,
            hasRollbackGate: false
        )
        let input = MobileReleaseCandidateGateInput.mock(viewerRole: .guardian, evidence: evidence)

        let snapshot = builder.build(viewerRole: .guardian, input: input)

        XCTAssertEqual(snapshot.status, .blocked)
        XCTAssertTrue(snapshot.publicSummary.findingCodes.contains(.missingEvidence))
        XCTAssertTrue(snapshot.publicSummary.findingCodes.contains(.missingRollbackGate))
        XCTAssertTrue(snapshot.nextActions.contains { $0.title == "补齐回滚门禁" })
    }

    func testPermissionBlockedBecomesBlockingFinding() {
        var input = MobileReleaseCandidateGateInput.mock(viewerRole: .guardian)
        input.permissionGateway = MobilePlatformPermissionGatewayAdapter().buildReadModel(
            viewerRole: .guardian,
            unsafePayload: ["https://example.com/token"]
        )

        let snapshot = builder.build(viewerRole: .guardian, input: input)

        XCTAssertEqual(snapshot.status, .blocked)
        XCTAssertTrue(snapshot.publicSummary.findingCodes.contains(.permissionGatewayBlocked))
        XCTAssertTrue(snapshot.checks.contains { $0.kind == .permissionGateway && $0.severity == .blocker })
    }

    func testOfflineAndJointApprovalPendingBecomeReviewFindings() {
        let snapshot = builder.build(viewerRole: .guardian)

        XCTAssertTrue(
            snapshot.publicSummary.findingCodes.contains(.offlineConflictActive)
                || snapshot.publicSummary.findingCodes.contains(.jointApprovalPending)
                || snapshot.publicSummary.findingCodes.contains(.homeworkInboxPending)
        )
        XCTAssertGreaterThanOrEqual(snapshot.publicSummary.warningCount, 1)
    }

    func testOutputDoesNotLeakSensitiveMarkers() {
        let snapshots = [
            builder.build(viewerRole: .guardian),
            builder.build(viewerRole: .operations),
            builder.build(viewerRole: .child)
        ]
        let text = snapshots.flatMap(\.displayValues).joined(separator: " ").lowercased()

        for marker in [
            "child:", "family:", "school:", "teacher:", "relative:", "guardian:",
            "task:", "claim:", "proof:", "ledger:", "device:", "order:", "entitlement:",
            "provider:", "model:", "token", "secret", "http://", "https://", "file://",
            "/users/", "/volumes/", "192.168."
        ] {
            XCTAssertFalse(text.contains(marker), "不应泄露 \(marker)")
        }
    }
}
