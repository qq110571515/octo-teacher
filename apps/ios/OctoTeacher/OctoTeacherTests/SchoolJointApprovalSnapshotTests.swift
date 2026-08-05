import XCTest
@testable import OctoTeacher

final class SchoolJointApprovalSnapshotTests: XCTestCase {

    private struct Sources {
        var homeworks: [SchoolHomework]
        var runtime: GrowthRuntimeSettlementReport
        var evidence: GrowthEvidenceTimelineReport
        var offlineStatus: MobileOfflinePublicStatus
        var offlineReport: MobileOfflineReplayReport
        var credit: MobileCreditSettlementReport
    }

    private func makeSources(
        offlineStatus: MobileOfflinePublicStatus = .clean
    ) -> Sources {
        let family = LocalFamilyStore()
        let school = SchoolFamilyStore()
        let runtime = GrowthPackRuntimeStore().refresh(family: family, schoolFamily: school)
        let evidence = GrowthEvidenceTimelineStore().refresh(
            family: family,
            schoolFamily: school,
            runtime: GrowthEvidenceTimelineRuntimeContext(report: runtime)
        )
        let offlineReplay = MobileOfflineReplayStore()
        let replay = offlineReplay.replay(outbox: MobileOfflineOutboxStore.mock())
        let creditStore = MobileCreditSettlementStore()
        creditStore.refresh(
            offlineReport: replay,
            family: family,
            schoolFamily: school,
            screenTime: MockScreenTimeController()
        )
        return Sources(
            homeworks: school.homeworks,
            runtime: runtime,
            evidence: evidence,
            offlineStatus: offlineStatus,
            offlineReport: replay,
            credit: creditStore.report
        )
    }

    private func schoolSnapshot(
        role: SchoolGrowthCreditViewerRole,
        sources: Sources
    ) -> SchoolGrowthCreditSnapshot {
        SchoolGrowthCreditSnapshotBuilder().build(
            viewerRole: role,
            homeworks: sources.homeworks,
            runtimeReport: sources.runtime,
            evidenceReport: sources.evidence,
            offlineStatus: sources.offlineStatus,
            offlineReport: sources.offlineReport
        )
    }

    private func snapshot(
        role: SchoolJointApprovalViewerRole,
        sources: Sources? = nil,
        offlineStatus: MobileOfflinePublicStatus = .clean,
        offlineReport: MobileOfflineReplayReport = .empty,
        mutateSchool: ((inout SchoolGrowthCreditSnapshot) -> Void)? = nil,
        mutateCredit: ((inout MobileCreditSettlementReport) -> Void)? = nil,
        salt: String = "school-joint-approval-ios-v1"
    ) -> SchoolJointApprovalSnapshot {
        let source = sources ?? makeSources()
        var school = schoolSnapshot(role: schoolRole(role), sources: source)
        var credit = source.credit
        mutateSchool?(&school)
        mutateCredit?(&credit)
        return SchoolJointApprovalSnapshotBuilder(redactionSalt: salt).build(
            viewerRole: role,
            homeworks: source.homeworks,
            schoolCredit: school,
            creditSettlement: credit,
            offlineStatus: offlineStatus,
            offlineReport: offlineReport
        )
    }

    private func schoolRole(_ role: SchoolJointApprovalViewerRole) -> SchoolGrowthCreditViewerRole {
        switch role {
        case .guardian: return .guardian
        case .teacher: return .teacher
        case .child: return .child
        }
    }

    // MARK: - 角色可见性

    func testGuardianBoardBuildsReadOnlyStages() {
        let guardian = snapshot(role: .guardian)

        XCTAssertTrue(guardian.visibility.canSeeQueue)
        XCTAssertTrue(guardian.visibility.canSeeGuardianReason)
        XCTAssertTrue(guardian.visibility.canSeeCreditAmount)
        XCTAssertFalse(guardian.items.isEmpty)
        XCTAssertGreaterThan(guardian.stageSummary.totalCount, 0)
        XCTAssertTrue(guardian.items.allSatisfy { !$0.verifiesTeacher && !$0.confirmsGuardian && !$0.writesLedger && !$0.sendsNotification })
        XCTAssertTrue(guardian.items.contains { $0.guardianReason != nil })
        XCTAssertTrue(guardian.items.contains { $0.priority != nil })
    }

    func testTeacherSeesOnlySchoolVerificationStates() {
        let teacher = snapshot(role: .teacher)

        XCTAssertTrue(teacher.visibility.canSeeQueue)
        XCTAssertFalse(teacher.visibility.canSeeGuardianReason)
        XCTAssertFalse(teacher.visibility.canSeeInternalPriority)
        XCTAssertFalse(teacher.visibility.canSeeCreditAmount)
        XCTAssertTrue(teacher.items.allSatisfy { $0.guardianReason == nil })
        XCTAssertTrue(teacher.items.allSatisfy { $0.priority == nil })
        XCTAssertTrue(teacher.items.allSatisfy { $0.stage != .appealFrozen && $0.stage != .offlineRollback })
        XCTAssertTrue(teacher.creditNotes.isEmpty)
        XCTAssertEqual(teacher.publicSummary.creditNoteCount, 0)
    }

    func testChildSeesOnlySafeProgressCopy() {
        let child = snapshot(role: .child) { school in
            school.header.status = .blocked
        }

        XCTAssertFalse(child.visibility.canSeeQueue)
        XCTAssertFalse(child.visibility.canSeeGuardianReason)
        XCTAssertFalse(child.visibility.canSeeCreditAmount)
        XCTAssertNotEqual(child.header.status, .blocked, "孩子不应看到上游阻断态")
        XCTAssertTrue(child.items.allSatisfy { $0.guardianReason == nil && $0.priority == nil })
        XCTAssertTrue(child.items.allSatisfy { !$0.childSafeCopy.isEmpty })
        XCTAssertTrue(child.creditNotes.isEmpty)
        XCTAssertFalse(child.findings.contains { $0.code == .upstreamBlocked })
    }

    func testCreditNotesOnlyVisibleToGuardian() {
        let source = makeSources()
        let guardian = snapshot(role: .guardian, sources: source)
        let teacher = snapshot(role: .teacher, sources: source)
        let child = snapshot(role: .child, sources: source)

        XCTAssertFalse(guardian.creditNotes.isEmpty)
        XCTAssertTrue(guardian.creditNotes.allSatisfy { !$0.writesLedger && !$0.issuesCredit && !$0.unlocksDevice })
        XCTAssertTrue(teacher.creditNotes.isEmpty)
        XCTAssertTrue(child.creditNotes.isEmpty)
    }

    // MARK: - 阶段与发现项

    func testGuardianSeesAppealFreezeStage() {
        let guardian = snapshot(role: .guardian) { school in
            if !school.assignments.isEmpty {
                school.assignments[0].status = .appealed
            }
        }

        XCTAssertTrue(guardian.items.contains { $0.stage == .appealFrozen })
        XCTAssertEqual(guardian.header.status, .appealFrozen)
        XCTAssertTrue(guardian.findings.contains { $0.code == .appealOrFreezeActive })
        XCTAssertFalse(guardian.publicSummary.freezesCredit)
    }

    func testGuardianSeesOfflineRollbackStage() {
        let guardian = snapshot(
            role: .guardian,
            offlineStatus: MobileOfflinePublicStatus(pendingCount: 1, conflictCount: 1, rolledBackCount: 1)
        ) { school in
            if !school.assignments.isEmpty {
                school.assignments[0].status = .offlineConflict
            }
        }

        XCTAssertTrue(guardian.items.contains { $0.stage == .offlineRollback })
        XCTAssertEqual(guardian.header.status, .offlineRollback)
        XCTAssertTrue(guardian.findings.contains { $0.code == .offlineRollbackActive })
    }

    func testGuardianAwaitingTeacherAndGuardianFindings() {
        let guardian = snapshot(role: .guardian) { school in
            guard school.assignments.count >= 2 else { return }
            school.assignments[0].status = .submitted
            school.assignments[1].status = .teacherVerified
        }

        XCTAssertTrue(guardian.items.contains { $0.stage == .awaitingTeacher })
        XCTAssertTrue(guardian.items.contains { $0.stage == .awaitingGuardian })
        XCTAssertTrue(guardian.findings.contains { $0.code == .awaitingTeacherVerify })
        XCTAssertTrue(guardian.findings.contains { $0.code == .awaitingGuardianConfirm })
    }

    func testGuardianBlockedWhenUpstreamBlocked() {
        let guardian = snapshot(role: .guardian) { school in
            school.header.status = .blocked
        }

        XCTAssertEqual(guardian.header.status, .blocked)
        XCTAssertTrue(guardian.findings.contains { $0.code == .upstreamBlocked })
    }

    func testReturnedHomeworkSurfacesWarning() {
        // 默认本地学校 fixture 含一条被退回作业，学校快照会把它折叠成 blocked，
        // 联合审批台借 homework 原始状态把「退回重做」单独还原成只读阶段。
        let guardian = snapshot(role: .guardian)

        XCTAssertTrue(guardian.items.contains { $0.stage == .returned })
        XCTAssertTrue(guardian.findings.contains { $0.code == .homeworkReturned })
    }

    // MARK: - 脱敏与确定性

    func testUnsafeInputFallsBackToBlockedSnapshot() {
        let blocked = snapshot(role: .guardian) { school in
            if !school.assignments.isEmpty {
                school.assignments[0].title = "file://private/proof.png"
            }
        }

        XCTAssertEqual(blocked.header.status, .blocked)
        XCTAssertTrue(blocked.items.isEmpty)
        XCTAssertEqual(blocked.findings.first?.code, .publicSummaryLeak)
    }

    func testSnapshotIsStableAndRedacted() {
        let source = makeSources()
        let first = snapshot(role: .guardian, sources: source)
        let second = snapshot(role: .guardian, sources: source)
        let builder = SchoolJointApprovalSnapshotBuilder()

        XCTAssertEqual(first, second)
        XCTAssertTrue(builder.redacts(first))
        let text = (
            first.items.flatMap { [$0.publicItemRef, $0.headline, $0.childSafeCopy, $0.guardianReason ?? ""] }
            + first.creditNotes.flatMap { [$0.publicNoteRef, $0.reason ?? ""] }
            + first.findings.map(\.publicRef)
        ).joined(separator: " ")
        for marker in ["child:", "family:", "school:", "teacher:", "guardian:", "homework:", "proof:", "ledger:", "credit:", "event:", "192.168.", "file://", "device-token"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "不应泄露 \(marker)")
        }
    }

    func testPublicSummarySideEffectsAreAlwaysFalse() {
        let summary = snapshot(role: .guardian).publicSummary

        XCTAssertFalse(summary.verifiesTeacher)
        XCTAssertFalse(summary.confirmsGuardian)
        XCTAssertFalse(summary.returnsHomework)
        XCTAssertFalse(summary.freezesCredit)
        XCTAssertFalse(summary.writesLedger)
        XCTAssertFalse(summary.writesSchoolHomework)
        XCTAssertFalse(summary.sendsNotification)
        XCTAssertFalse(summary.unlocksDevice)
        XCTAssertFalse(summary.callsSchoolSystem)
        XCTAssertFalse(summary.callsLms)
        XCTAssertFalse(summary.usesAiToAnswer)
    }

    func testChangingSaltChangesPublicRefs() {
        let source = makeSources()
        let first = snapshot(role: .guardian, sources: source, salt: "salt-one")
        let second = snapshot(role: .guardian, sources: source, salt: "salt-two")

        XCTAssertNotEqual(first.items.first?.publicItemRef, second.items.first?.publicItemRef)
        XCTAssertNotEqual(first.findings.first?.publicRef, second.findings.first?.publicRef)
    }
}
