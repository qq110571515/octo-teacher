import XCTest
@testable import OctoTeacher

final class GuardianChildConsentPolicyTests: XCTestCase {
    private let builder = GuardianChildConsentPolicyBuilder()

    func testGuardianAllowedFamilyStoryIsSideEffectFree() {
        let snapshot = builder.build(viewerRole: .guardian, purpose: .familyStory)

        XCTAssertEqual(snapshot.state, .allowed)
        XCTAssertTrue(snapshot.decision.familyVisible)
        XCTAssertTrue(snapshot.decision.relativeVisible)
        XCTAssertEqual(snapshot.guardianConsentDisplay, GuardianChildConsentState.granted.label)
        XCTAssertFalse(snapshot.sideEffects.callsNetwork)
        XCTAssertFalse(snapshot.sideEffects.callsAi)
        XCTAssertFalse(snapshot.sideEffects.writesPrivacyRecord)
        XCTAssertFalse(snapshot.sideEffects.writesPermissionGrant)
    }

    func testChildViewRedactsAdultAndPermissionDetails() {
        let snapshot = builder.build(viewerRole: .child, purpose: .honorWall)

        XCTAssertFalse(snapshot.visibility.canSeeGuardianReason)
        XCTAssertFalse(snapshot.visibility.canSeeRelativePermissionDetail)
        XCTAssertFalse(snapshot.visibility.canSeeTeacherInternalNote)
        XCTAssertFalse(snapshot.visibility.canSeeAuditDetail)
        XCTAssertTrue(snapshot.findings.contains { $0.code == .childVisibilityRedacted })
        XCTAssertFalse(snapshot.childSafeCopy.localizedCaseInsensitiveContains("内部原因"))
    }

    func testRelativeOnlySeesAuthorizedRelativePurposes() {
        let allowed = builder.build(viewerRole: .relative, purpose: .familyStory)
        let blocked = builder.build(viewerRole: .relative, purpose: .schoolTeacherVisibility)

        XCTAssertEqual(allowed.state, .allowed)
        XCTAssertTrue(allowed.decision.relativeVisible)
        XCTAssertEqual(allowed.guardianConsentDisplay, "不可见")
        XCTAssertFalse(allowed.publicSummary.guardianConsentGranted)
        XCTAssertEqual(blocked.state, .blocked)
        XCTAssertTrue(blocked.findings.contains { $0.code == .relativeScopeExceeded })
    }

    func testTeacherOnlySeesAuthorizedSchoolPurpose() {
        let allowed = builder.build(viewerRole: .teacher, purpose: .schoolTeacherVisibility)
        let blockedByPurpose = builder.build(viewerRole: .teacher, purpose: .honorWall)
        let blockedByAuthorization = builder.build(
            viewerRole: .teacher,
            purpose: .schoolTeacherVisibility,
            teacherAuthorized: false
        )

        XCTAssertEqual(allowed.state, .allowed)
        XCTAssertTrue(allowed.decision.schoolVisible)
        XCTAssertEqual(allowed.guardianConsentDisplay, "不可见")
        XCTAssertFalse(allowed.publicSummary.childAssentGranted)
        XCTAssertEqual(blockedByPurpose.state, .blocked)
        XCTAssertTrue(blockedByPurpose.findings.contains { $0.code == .teacherScopeExceeded })
        XCTAssertEqual(blockedByAuthorization.state, .blocked)
        XCTAssertTrue(blockedByAuthorization.findings.contains { $0.code == .teacherScopeExceeded })
    }

    func testPublicViewerSeesOnlyPublicRedactedSummary() {
        let snapshot = builder.build(
            viewerRole: .publicViewer,
            purpose: .publicShare,
            ageBand: .age16To17,
            publicCopyRedacted: true
        )

        XCTAssertEqual(snapshot.state, .allowed)
        XCTAssertTrue(snapshot.decision.publicVisible)
        XCTAssertEqual(snapshot.guardianConsentDisplay, "不可见")
        XCTAssertEqual(snapshot.childAssentDisplay, "不可见")
        XCTAssertFalse(snapshot.publicSummary.guardianConsentGranted)
        XCTAssertFalse(snapshot.publicSummary.childAssentGranted)
        XCTAssertTrue(snapshot.findings.contains { $0.code == .publicRedactionApplied })
    }

    func testMissingGuardianConsentAndChildAssentBlock() {
        let missingGuardian = builder.build(
            viewerRole: .guardian,
            purpose: .familyStory,
            guardianConsent: .pending
        )
        let missingAssent = builder.build(
            viewerRole: .guardian,
            purpose: .honorWall,
            ageBand: .age13To15,
            childAssent: .pending
        )

        XCTAssertEqual(missingGuardian.state, .blocked)
        XCTAssertTrue(missingGuardian.findings.contains { $0.code == .guardianConsentRequired })
        XCTAssertEqual(missingAssent.state, .blocked)
        XCTAssertTrue(missingAssent.findings.contains { $0.code == .childAssentRequired })
    }

    func testPublicShareAgeAndRedactionGatesBlock() {
        let tooYoung = builder.build(
            viewerRole: .guardian,
            purpose: .publicShare,
            ageBand: .age13To15
        )
        let notRedacted = builder.build(
            viewerRole: .guardian,
            purpose: .publicShare,
            ageBand: .age16To17,
            publicCopyRedacted: false
        )

        XCTAssertEqual(tooYoung.state, .blocked)
        XCTAssertTrue(tooYoung.findings.contains { $0.code == .agePublicShareBlocked })
        XCTAssertEqual(notRedacted.state, .blocked)
        XCTAssertTrue(notRedacted.findings.contains { $0.code == .publicShareNotRedacted })
    }

    func testRevocationExpiryAndExportAuditBlock() {
        let revoked = builder.build(
            viewerRole: .guardian,
            purpose: .familyStory,
            guardianConsent: .revoked
        )
        let notPropagated = builder.build(
            viewerRole: .guardian,
            purpose: .honorWall,
            revocationRequired: true,
            revocationPropagated: false
        )
        let missingAudit = builder.build(
            viewerRole: .guardian,
            purpose: .dataExportDelete,
            exportRequested: true,
            exportDeleteAuditLinked: false
        )

        XCTAssertEqual(revoked.state, .blocked)
        XCTAssertTrue(revoked.findings.contains { $0.code == .consentExpiredOrRevoked })
        XCTAssertEqual(notPropagated.state, .blocked)
        XCTAssertTrue(notPropagated.findings.contains { $0.code == .revocationNotPropagated })
        XCTAssertEqual(missingAudit.state, .blocked)
        XCTAssertTrue(missingAudit.findings.contains { $0.code == .exportDeleteAuditMissing })
    }

    func testIdentityMismatchAndUnsafeInputBlockWithoutRawPayload() {
        let mismatch = builder.build(
            viewerRole: .guardian,
            purpose: .familyStory,
            sameFamily: false
        )
        let unsafe = builder.build(
            viewerRole: .guardian,
            purpose: .familyStory,
            inputRisk: .unsafePayloadDetected
        )

        XCTAssertEqual(mismatch.state, .blocked)
        XCTAssertTrue(mismatch.findings.contains { $0.code == .crossChildFamilyMismatch })
        XCTAssertEqual(unsafe.state, .blocked)
        XCTAssertTrue(unsafe.findings.contains { $0.code == .unsafePayloadBlocked })
        XCTAssertFalse(String(describing: unsafe).localizedCaseInsensitiveContains("baseUrl"))
        XCTAssertFalse(String(describing: unsafe).localizedCaseInsensitiveContains("local-model-host"))
    }

    func testSnapshotIsStableAndRedacted() {
        let first = builder.build(viewerRole: .guardian, purpose: .aiHomeworkAssist)
        let second = builder.build(viewerRole: .guardian, purpose: .aiHomeworkAssist)

        XCTAssertEqual(first, second)
        XCTAssertTrue(builder.redacts(first))

        let text = (
            [first.headline, first.childSafeCopy, first.publicSummary.policyPublicRef, first.publicSummary.requestPublicRef]
            + first.findings.flatMap { [$0.publicRef, $0.message] }
        ).joined(separator: " ")

        for marker in ["child:", "family:", "guardian:", "relative:", "teacher:", "school:", "consent:", "policy:", "session:", "transcript:", "provider:", "model:", "taskId", "claimId", "baseUrl", "192.168.", "file://", "/Users/", "/Volumes/"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "不应泄露 \(marker)")
        }
    }

    func testPublicSummarySideEffectsAreAlwaysFalse() {
        let summary = builder.build(viewerRole: .guardian, purpose: .dataExportDelete).publicSummary

        XCTAssertFalse(summary.writesDatabase)
        XCTAssertFalse(summary.writesLedger)
        XCTAssertFalse(summary.writesPrivacyRecord)
        XCTAssertFalse(summary.writesPermissionGrant)
        XCTAssertFalse(summary.writesDeletion)
        XCTAssertFalse(summary.publishesContent)
        XCTAssertFalse(summary.sendsNotification)
        XCTAssertFalse(summary.callsNetwork)
        XCTAssertFalse(summary.callsAi)
        XCTAssertFalse(summary.callsQueue)
        XCTAssertFalse(summary.callsSchoolSystem)
        XCTAssertFalse(summary.callsSocialPlatform)
        XCTAssertFalse(summary.touchesDevice)
    }
}
