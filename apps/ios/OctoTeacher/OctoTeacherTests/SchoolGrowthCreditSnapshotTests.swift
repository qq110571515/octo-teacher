import XCTest
@testable import OctoTeacher

final class SchoolGrowthCreditSnapshotTests: XCTestCase {

    private func reports() -> (
        homeworks: [SchoolHomework],
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
        return (school.homeworks, runtime, evidence)
    }

    private func snapshot(
        role: SchoolGrowthCreditViewerRole,
        homeworks: [SchoolHomework]? = nil,
        offlineStatus: MobileOfflinePublicStatus = .clean,
        offlineReport: MobileOfflineReplayReport = .empty
    ) -> SchoolGrowthCreditSnapshot {
        let source = reports()
        return SchoolGrowthCreditSnapshotBuilder().build(
            viewerRole: role,
            homeworks: homeworks ?? source.homeworks,
            runtimeReport: source.runtime,
            evidenceReport: source.evidence,
            offlineStatus: offlineStatus,
            offlineReport: offlineReport
        )
    }

    func testChildSnapshotIsSideEffectFreeAndHidesAdultInternals() {
        let child = snapshot(role: .child)

        XCTAssertEqual(child.header.viewerRole, .child)
        XCTAssertFalse(child.assignments.isEmpty)
        XCTAssertFalse(child.visibility.canSeeTeacherVerification)
        XCTAssertFalse(child.visibility.canSeeGuardianConfirmation)
        XCTAssertFalse(child.visibility.canSeeCreditPreview)
        XCTAssertFalse(child.visibility.canSeeAppealState)
        XCTAssertTrue(child.creditPreviews.isEmpty)
        XCTAssertEqual(child.publicSummary.creditPreviewCount, 0)
        XCTAssertEqual(child.evidenceStatus.appealCount, 0)
        XCTAssertEqual(child.evidenceStatus.creditFrozenCount, 0)
        XCTAssertFalse(child.publicSummary.writesSchoolHomework)
        XCTAssertFalse(child.publicSummary.modifiesHomework)
        XCTAssertFalse(child.publicSummary.writesLedger)
        XCTAssertFalse(child.publicSummary.unlocksDevice)
        XCTAssertFalse(child.publicSummary.uploadsAttachment)
        XCTAssertFalse(child.publicSummary.callsSchoolSystem)
        XCTAssertFalse(child.publicSummary.usesAiToAnswer)
    }

    func testGuardianSeesCreditPreviewsButTheyDoNotWriteLedger() {
        let guardian = snapshot(role: .guardian)

        XCTAssertTrue(guardian.visibility.canSeeCreditPreview)
        XCTAssertFalse(guardian.creditPreviews.isEmpty)
        XCTAssertEqual(guardian.publicSummary.creditPreviewCount, guardian.creditPreviews.count)
        XCTAssertTrue(guardian.creditPreviews.allSatisfy { !$0.writesLedger && !$0.unlocksDevice })
        XCTAssertTrue(guardian.creditPreviews.contains { $0.state == .blocked || $0.state == .frozen || $0.state == .reviewRequired })
    }

    func testCreditPreviewLabelsUseGrowthCreditsNotMinutes() throws {
        let guardian = snapshot(role: .guardian)
        let firstPreview = try XCTUnwrap(guardian.creditPreviews.first)

        XCTAssertTrue(firstPreview.amountLabel.contains("成长积分"))
        XCTAssertFalse(firstPreview.amountLabel.contains("分钟"))
    }

    func testTeacherCannotSeeGuardianConfirmationOrCreditPreview() {
        let teacher = snapshot(role: .teacher)

        XCTAssertTrue(teacher.visibility.canSeeTeacherVerification)
        XCTAssertFalse(teacher.visibility.canSeeGuardianConfirmation)
        XCTAssertFalse(teacher.visibility.canSeeCreditPreview)
        XCTAssertTrue(teacher.creditPreviews.isEmpty)
        XCTAssertFalse(teacher.nextActions.contains { $0.kind == .guardianConfirm })
        XCTAssertFalse(teacher.nextActions.contains { $0.kind == .resolveOfflineConflict })
    }

    func testReturnedHomeworkBlocksUsableCredit() {
        let guardian = snapshot(role: .guardian)

        let returnedAssignment = guardian.assignments.first { $0.title.contains("课外阅读") }
        XCTAssertEqual(returnedAssignment?.status, .blocked)
        XCTAssertFalse(returnedAssignment?.canShowCreditAsUsable ?? true)
        XCTAssertTrue(guardian.findings.contains { $0.code == .schoolHomeworkBlocked })
        XCTAssertTrue(guardian.creditPreviews.contains { $0.state == .blocked })
    }

    func testAppealAndFreezeCountsHiddenFromChildVisibleToGuardian() {
        let child = snapshot(role: .child)
        let guardian = snapshot(role: .guardian)

        XCTAssertEqual(child.evidenceStatus.appealCount, 0)
        XCTAssertEqual(child.evidenceStatus.openAppealCount, 0)
        XCTAssertEqual(child.evidenceStatus.creditFrozenCount, 0)
        XCTAssertGreaterThan(guardian.evidenceStatus.appealCount, 0)
        XCTAssertGreaterThan(guardian.evidenceStatus.creditFrozenCount, 0)
        XCTAssertTrue(guardian.findings.contains { $0.code == .appealOrFreezeActive })
    }

    func testOfflineConflictsHiddenFromChildVisibleToGuardian() {
        let offline = MobileOfflinePublicStatus(pendingCount: 2, conflictCount: 1, rolledBackCount: 1)
        let child = snapshot(role: .child, offlineStatus: offline)
        let guardian = snapshot(role: .guardian, offlineStatus: offline)

        XCTAssertEqual(child.offlineStatus.conflictCount, 0)
        XCTAssertEqual(child.offlineStatus.rollbackRequiredCount, 0)
        XCTAssertEqual(child.publicSummary.offlineConflictCount, 0)
        XCTAssertGreaterThan(guardian.offlineStatus.conflictCount, 0)
        XCTAssertGreaterThan(guardian.offlineStatus.rollbackRequiredCount, 0)
        XCTAssertGreaterThan(guardian.publicSummary.offlineConflictCount, 0)
        XCTAssertTrue(guardian.findings.contains { $0.code == .offlineConflictActive })
        XCTAssertFalse(guardian.offlineStatus.sendsNotification)
        XCTAssertFalse(guardian.offlineStatus.writesCredit)
    }

    func testChildOnlyReceivesChildVisibleNextActions() {
        let child = snapshot(role: .child)

        XCTAssertFalse(child.nextActions.isEmpty)
        XCTAssertTrue(child.nextActions.allSatisfy(\.visibleToChild))
        XCTAssertFalse(child.nextActions.contains { $0.kind == .teacherVerify || $0.kind == .guardianConfirm })
    }

    func testUnsafeHomeworkPayloadFallsBackToBlockedRedactedSnapshot() throws {
        var source = reports().homeworks
        try XCTSkipIf(source.isEmpty)
        source[0].title = "file://private/homework-answer.png"

        let snapshot = SchoolGrowthCreditSnapshotBuilder().build(
            viewerRole: .guardian,
            homeworks: source
        )

        XCTAssertEqual(snapshot.header.status, .blocked)
        XCTAssertTrue(snapshot.assignments.isEmpty)
        XCTAssertEqual(snapshot.findings.map(\.code), [.publicSummaryLeak])
    }

    func testSnapshotIsDeterministicAndRedacted() {
        let source = reports()
        let builder = SchoolGrowthCreditSnapshotBuilder()
        let first = builder.build(
            viewerRole: .guardian,
            homeworks: source.homeworks,
            runtimeReport: source.runtime,
            evidenceReport: source.evidence
        )
        let second = builder.build(
            viewerRole: .guardian,
            homeworks: source.homeworks,
            runtimeReport: source.runtime,
            evidenceReport: source.evidence
        )
        let text = (
            first.header.childPublicRefs +
            first.assignments.flatMap { [$0.publicAssignmentRef, $0.childPublicRef, $0.title, $0.verificationMode] } +
            first.creditPreviews.flatMap { [$0.publicCreditPreviewRef, $0.reason] } +
            first.nextActions.flatMap { [$0.publicActionRef, $0.title] } +
            first.findings.flatMap { [$0.publicRef, $0.message] }
        ).joined(separator: " ")

        XCTAssertEqual(first, second)
        XCTAssertTrue(builder.redacts(first))
        for marker in ["child:", "family:", "school:", "teacher:", "homework:", "proof:", "ledger:", "file://", "192.168."] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "不应泄露 \(marker)")
        }
    }

    func testChangingSaltChangesPublicRefs() {
        let source = reports()
        let first = SchoolGrowthCreditSnapshotBuilder(redactionSalt: "salt-one").build(
            viewerRole: .guardian,
            homeworks: source.homeworks,
            runtimeReport: source.runtime,
            evidenceReport: source.evidence
        )
        let second = SchoolGrowthCreditSnapshotBuilder(redactionSalt: "salt-two").build(
            viewerRole: .guardian,
            homeworks: source.homeworks,
            runtimeReport: source.runtime,
            evidenceReport: source.evidence
        )

        XCTAssertNotEqual(first.header.childPublicRefs.first, second.header.childPublicRefs.first)
        XCTAssertNotEqual(first.assignments.first?.publicAssignmentRef, second.assignments.first?.publicAssignmentRef)
    }
}
