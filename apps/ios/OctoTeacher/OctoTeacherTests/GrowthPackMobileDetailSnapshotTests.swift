import XCTest
@testable import OctoTeacher

final class GrowthPackMobileDetailSnapshotTests: XCTestCase {

    private func reports() -> (
        runtime: GrowthRuntimeSettlementReport,
        evidence: GrowthEvidenceTimelineReport
    ) {
        let family = LocalFamilyStore()
        let school = SchoolFamilyStore()
        let runtime = GrowthPackRuntimeStore().refresh(family: family, schoolFamily: school)
        let evidence = GrowthEvidenceTimelineStore().refresh(
            family: family,
            schoolFamily: school,
            runtime: GrowthEvidenceTimelineRuntimeContext(report: runtime)
        )
        return (runtime, evidence)
    }

    private func snapshot(
        role: GrowthPackMobileDetailViewerRole,
        offlineStatus: MobileOfflinePublicStatus = .clean,
        offlineReport: MobileOfflineReplayReport = .empty
    ) -> GrowthPackMobileDetailSnapshot {
        let source = reports()
        return GrowthPackMobileDetailSnapshotBuilder().build(
            viewerRole: role,
            runtimeReport: source.runtime,
            evidenceReport: source.evidence,
            offlineStatus: offlineStatus,
            offlineReport: offlineReport
        )
    }

    func testChildSnapshotHasNoSideEffectsAndUsesRoleVisibility() {
        let child = snapshot(role: .child)

        XCTAssertEqual(child.header.viewerRole, .child)
        XCTAssertFalse(child.tasks.isEmpty)
        XCTAssertFalse(child.steps.isEmpty)
        XCTAssertFalse(child.proofRequirements.isEmpty)
        XCTAssertFalse(child.roleVisibility.canSeeSettlementPreview)
        XCTAssertFalse(child.roleVisibility.canSeeGuardianReviewQueue)
        XCTAssertFalse(child.publicSummary.writesLedger)
        XCTAssertFalse(child.publicSummary.grantsBadge)
        XCTAssertFalse(child.publicSummary.updatesAbilityCard)
        XCTAssertFalse(child.publicSummary.publishesHonorWall)
        XCTAssertFalse(child.publicSummary.unlocksDevice)
        XCTAssertFalse(child.publicSummary.uploadsMedia)
    }

    func testGuardianSeesSettlementPreviewWhileChildDoesNot() {
        let child = snapshot(role: .child)
        let guardian = snapshot(role: .guardian)

        XCTAssertTrue(child.creditPreviews.isEmpty)
        XCTAssertEqual(child.rewardSummary.creditPreviewCount, 0)
        XCTAssertEqual(child.publicSummary.creditPreviewCount, 0)
        XCTAssertEqual(child.rewardSummary.badgeSuggestionCount, 0)
        XCTAssertFalse(guardian.creditPreviews.isEmpty)
        XCTAssertEqual(guardian.rewardSummary.creditPreviewCount, guardian.creditPreviews.count)
        XCTAssertEqual(guardian.publicSummary.creditPreviewCount, guardian.creditPreviews.count)
        XCTAssertTrue(guardian.creditPreviews.allSatisfy { !$0.writesLedger && !$0.unlocksDevice })
    }

    func testCreditPreviewLabelsUseGrowthCreditsNotMinutes() throws {
        let guardian = snapshot(role: .guardian)
        let firstPreview = try XCTUnwrap(guardian.creditPreviews.first)

        XCTAssertTrue(firstPreview.creditLabel.contains("成长积分"))
        XCTAssertFalse(firstPreview.creditLabel.contains("分钟"))
    }

    func testChildHidesAdultReviewCountsAndGuardianKeepsThem() {
        let child = snapshot(role: .child)
        let guardian = snapshot(role: .guardian)

        XCTAssertEqual(child.evidenceAppealSummary.conflictCount, 0)
        XCTAssertEqual(child.evidenceAppealSummary.relativeReviewCount, 0)
        XCTAssertEqual(child.evidenceAppealSummary.creditFrozenCount, 0)
        XCTAssertGreaterThan(guardian.evidenceAppealSummary.conflictCount, 0)
        XCTAssertGreaterThan(guardian.evidenceAppealSummary.relativeReviewCount, 0)
        XCTAssertGreaterThan(guardian.evidenceAppealSummary.creditFrozenCount, 0)
        XCTAssertTrue(child.findings.contains { $0.code == .relativeReviewHiddenFromChild })
    }

    func testAppealActionIsGuardianOnly() {
        let child = snapshot(role: .child)
        let guardian = snapshot(role: .guardian)

        XCTAssertFalse(child.nextActions.contains { $0.kind == .appealReview })
        XCTAssertTrue(guardian.nextActions.contains { $0.kind == .appealReview && $0.actionRequired })
        XCTAssertTrue(guardian.findings.contains { $0.code == .appealReviewRequired })
    }

    func testOfflineHintsDoNotSendNotificationsOrUnlockDevice() {
        let offline = MobileOfflinePublicStatus(pendingCount: 2, conflictCount: 1, rolledBackCount: 1)
        let child = snapshot(role: .child, offlineStatus: offline)
        let guardian = snapshot(role: .guardian, offlineStatus: offline)

        XCTAssertEqual(child.offlineHints.count, 1)
        XCTAssertTrue(child.offlineHints.allSatisfy { $0.sendsNotification == false })
        XCTAssertTrue(guardian.offlineHints.contains { $0.kind == .conflict && $0.actionRequired })
        XCTAssertTrue(guardian.offlineHints.allSatisfy { $0.sendsNotification == false })
        XCTAssertFalse(guardian.publicSummary.sendsNotification)
        XCTAssertFalse(guardian.publicSummary.unlocksDevice)
        XCTAssertTrue(guardian.findings.contains { $0.code == .offlineSyncActionRequired })
    }

    func testUnsafeDisplayPayloadFallsBackToBlockedRedactedSnapshot() throws {
        var source = reports()
        try XCTSkipIf(source.runtime.steps.isEmpty)
        source.runtime.steps[0].title = "Open C:\\Users\\Leo\\secret-proof.png"

        let snapshot = GrowthPackMobileDetailSnapshotBuilder().build(
            viewerRole: .child,
            runtimeReport: source.runtime,
            evidenceReport: source.evidence
        )

        XCTAssertEqual(snapshot.header.status, .blocked)
        XCTAssertTrue(snapshot.tasks.isEmpty)
        XCTAssertEqual(snapshot.findings.first?.code, .publicSummaryLeak)
    }

    func testSnapshotIsRedactedAndStable() {
        let source = reports()
        let builder = GrowthPackMobileDetailSnapshotBuilder()
        let first = builder.build(viewerRole: .guardian, runtimeReport: source.runtime, evidenceReport: source.evidence)
        let second = builder.build(viewerRole: .guardian, runtimeReport: source.runtime, evidenceReport: source.evidence)
        var displayValues = [first.header.publicPackRef, first.header.childPublicRef]
        displayValues.append(contentsOf: first.tasks.flatMap {
            [$0.publicTaskRef, $0.childPublicRef, $0.title, $0.category]
        })
        displayValues.append(contentsOf: first.steps.flatMap {
            [$0.publicStepRef, $0.publicTaskRef, $0.childPublicRef, $0.title, $0.reason, $0.nextStep]
        })
        displayValues.append(contentsOf: first.proofRequirements.flatMap {
            [$0.publicRequirementRef, $0.publicTaskRef, $0.childPublicRef, $0.kindLabel]
        })
        displayValues.append(contentsOf: first.creditPreviews.flatMap { item in
            [item.publicCreditPreviewRef, item.reason] + item.usableFor
        })
        displayValues.append(contentsOf: first.evidenceAppealSummary.visibleTimeline.flatMap {
            [$0.publicItemRef, $0.summary]
        })
        displayValues.append(contentsOf: first.findings.flatMap {
            [$0.publicRef, $0.message]
        })
        let text = displayValues.joined(separator: " ")

        XCTAssertEqual(first, second)
        XCTAssertTrue(builder.redacts(first))
        for marker in ["child:", "family:", "task:", "proof:", "ledger:", "device:", "192.168.", "file://"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "不应泄露 \(marker)")
        }
    }

    func testChangingSaltChangesPublicRefs() {
        let source = reports()
        let first = GrowthPackMobileDetailSnapshotBuilder(redactionSalt: "salt-one").build(
            viewerRole: .guardian,
            runtimeReport: source.runtime,
            evidenceReport: source.evidence
        )
        let second = GrowthPackMobileDetailSnapshotBuilder(redactionSalt: "salt-two").build(
            viewerRole: .guardian,
            runtimeReport: source.runtime,
            evidenceReport: source.evidence
        )

        XCTAssertNotEqual(first.header.publicPackRef, second.header.publicPackRef)
        XCTAssertNotEqual(first.steps.first?.publicStepRef, second.steps.first?.publicStepRef)
    }
}
