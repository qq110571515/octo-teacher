import XCTest
@testable import OctoTeacher

final class ParentApprovalInboxSnapshotTests: XCTestCase {

    private struct Sources {
        var family: LocalFamilyStore
        var school: SchoolFamilyStore
        var runtime: GrowthRuntimeSettlementReport
        var evidence: GrowthEvidenceTimelineReport
        var offlineStatus: MobileOfflinePublicStatus
        var offlineReport: MobileOfflineReplayReport
        var credit: MobileCreditSettlementReport
    }

    private func makeSources(
        offlineStatus: MobileOfflinePublicStatus = MobileOfflinePublicStatus(pendingCount: 2, conflictCount: 1, rolledBackCount: 1)
    ) -> Sources {
        let family = LocalFamilyStore()
        let school = SchoolFamilyStore()
        let runtime = GrowthPackRuntimeStore().refresh(family: family, schoolFamily: school)
        let evidence = GrowthEvidenceTimelineStore().refresh(
            family: family,
            schoolFamily: school,
            runtime: GrowthEvidenceTimelineRuntimeContext(report: runtime)
        )
        let offlineOutbox = MobileOfflineOutboxStore.mock()
        let offlineReplay = MobileOfflineReplayStore()
        let replay = offlineReplay.replay(outbox: offlineOutbox)
        let creditStore = MobileCreditSettlementStore()
        creditStore.refresh(
            offlineReport: replay,
            family: family,
            schoolFamily: school,
            screenTime: MockScreenTimeController()
        )
        return Sources(
            family: family,
            school: school,
            runtime: runtime,
            evidence: evidence,
            offlineStatus: offlineStatus,
            offlineReport: replay,
            credit: creditStore.report
        )
    }

    private func snapshot(
        role: ParentApprovalInboxViewerRole,
        sources: Sources? = nil,
        mutateGrowth: ((inout GrowthPackMobileDetailSnapshot) -> Void)? = nil,
        mutateSchool: ((inout SchoolGrowthCreditSnapshot) -> Void)? = nil,
        mutateCredit: ((inout MobileCreditSettlementReport) -> Void)? = nil
    ) -> ParentApprovalInboxSnapshot {
        let source = sources ?? makeSources()
        var growth = GrowthPackMobileDetailSnapshotBuilder().build(
            viewerRole: growthRole(role),
            runtimeReport: source.runtime,
            evidenceReport: source.evidence,
            offlineStatus: source.offlineStatus,
            offlineReport: source.offlineReport
        )
        var school = SchoolGrowthCreditSnapshotBuilder().build(
            viewerRole: schoolRole(role),
            homeworks: source.school.homeworks,
            runtimeReport: source.runtime,
            evidenceReport: source.evidence,
            offlineStatus: source.offlineStatus,
            offlineReport: source.offlineReport
        )
        let achievement = FamilyAchievementSnapshotDashboardBuilder().dashboard(for: familyRole(role))
        var credit = source.credit
        mutateGrowth?(&growth)
        mutateSchool?(&school)
        mutateCredit?(&credit)
        return ParentApprovalInboxSnapshotBuilder().build(
            viewerRole: role,
            growthPack: growth,
            schoolCredit: school,
            familyAchievement: achievement,
            creditSettlement: credit,
            offlineStatus: source.offlineStatus,
            offlineReport: source.offlineReport
        )
    }

    func testGuardianInboxBuildsReadOnlyQueue() {
        let guardian = snapshot(role: .guardian)

        XCTAssertTrue(guardian.visibility.canSeeQueue)
        XCTAssertFalse(guardian.items.isEmpty)
        XCTAssertGreaterThan(guardian.batchSummary.totalCount, 0)
        XCTAssertTrue(guardian.items.allSatisfy { !$0.writesLedger && !$0.modifiesHomework && !$0.sendsNotification })
        XCTAssertTrue(guardian.items.contains { $0.kind == .creditSuggestion || $0.kind == .offlineConflict || $0.kind == .evidenceAppeal })
        XCTAssertTrue(guardian.nextActions.contains { $0.actionRequired })
        XCTAssertFalse(guardian.batchSummary.approvesItems)
        XCTAssertFalse(guardian.batchSummary.rejectsItems)
    }

    func testNonGuardianViewersCannotSeeInternalQueue() {
        for role in [ParentApprovalInboxViewerRole.child, .relative, .teacher] {
            let inbox = snapshot(role: role)

            XCTAssertFalse(inbox.visibility.canSeeQueue)
            XCTAssertTrue(inbox.items.isEmpty)
            XCTAssertEqual(inbox.publicSummary.visibleItemCount, 0)
            XCTAssertTrue(inbox.findings.contains { $0.code == .nonGuardianQueueHidden })
            XCTAssertFalse(inbox.findings.contains { $0.code == .upstreamBlocked })
        }
    }

    func testChildDoesNotSeeHiddenUpstreamBlockedState() {
        let child = snapshot(role: .child) { _ in } mutateSchool: { school in
            school.header.status = .blocked
        }

        XCTAssertEqual(child.header.status, .empty)
        XCTAssertTrue(child.items.isEmpty)
        XCTAssertTrue(child.findings.contains { $0.code == .nonGuardianQueueHidden })
        XCTAssertFalse(child.findings.contains { $0.code == .upstreamBlocked })
    }

    func testGuardianSeesOfflineConflictAndCreditReviewFindings() {
        let guardian = snapshot(role: .guardian) { _ in } mutateSchool: { _ in } mutateCredit: { report in
            if !report.proposals.isEmpty {
                report.proposals[0].status = .conflict
                report.proposals[0].actionRequired = true
            }
        }

        XCTAssertNotEqual(guardian.header.status, .empty)
        XCTAssertTrue(guardian.items.contains { $0.kind == .offlineConflict && $0.priority == .urgent })
        XCTAssertTrue(guardian.items.contains { $0.kind == .creditSuggestion && $0.priority == .urgent })
        XCTAssertTrue(guardian.findings.contains { $0.code == .offlineConflictActive })
        XCTAssertTrue(guardian.findings.contains { $0.code == .creditReviewRequired })
        XCTAssertFalse(guardian.publicSummary.writesLedger)
    }

    func testGuardianBlockedWhenUpstreamProjectionBlocked() {
        let guardian = snapshot(role: .guardian) { growth in
            growth.header.status = .blocked
        }

        XCTAssertEqual(guardian.header.status, .blocked)
        XCTAssertTrue(guardian.findings.contains { $0.code == .upstreamBlocked })
    }

    func testUnsafeVisibleTextFallsBackToBlockedSnapshot() throws {
        let blocked = snapshot(role: .guardian) { growth in
            if !growth.tasks.isEmpty {
                growth.tasks[0].title = "file://private/proof.png"
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
        let builder = ParentApprovalInboxSnapshotBuilder()

        XCTAssertEqual(first, second)
        XCTAssertTrue(builder.redacts(first))
        let text = (
            first.items.flatMap { [$0.publicApprovalRef, $0.idempotencyPublicRef, $0.title] }
            + first.nextActions.map(\.publicActionRef)
            + first.findings.map(\.publicRef)
        ).joined(separator: " ")
        for marker in ["child:", "family:", "school:", "teacher:", "relative:", "approval:", "homework:", "proof:", "ledger:", "event:", "192.168.", "file://"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "不应泄露 \(marker)")
        }
    }

    func testPublicSummarySideEffectsAreAlwaysFalse() {
        let summary = snapshot(role: .guardian).publicSummary

        XCTAssertFalse(summary.approvesItems)
        XCTAssertFalse(summary.rejectsItems)
        XCTAssertFalse(summary.writesLedger)
        XCTAssertFalse(summary.modifiesHomework)
        XCTAssertFalse(summary.writesSchoolHomework)
        XCTAssertFalse(summary.sendsNotification)
        XCTAssertFalse(summary.notifiesRelatives)
        XCTAssertFalse(summary.unlocksDevice)
        XCTAssertFalse(summary.uploadsMedia)
        XCTAssertFalse(summary.callsSchoolSystem)
        XCTAssertFalse(summary.usesAiToAnswer)
    }

    func testChangingSaltChangesPublicRefs() {
        let source = makeSources()
        let growth = GrowthPackMobileDetailSnapshotBuilder().build(
            viewerRole: .guardian,
            runtimeReport: source.runtime,
            evidenceReport: source.evidence,
            offlineStatus: source.offlineStatus,
            offlineReport: source.offlineReport
        )
        let school = SchoolGrowthCreditSnapshotBuilder().build(
            viewerRole: .guardian,
            homeworks: source.school.homeworks,
            runtimeReport: source.runtime,
            evidenceReport: source.evidence,
            offlineStatus: source.offlineStatus,
            offlineReport: source.offlineReport
        )
        let achievement = FamilyAchievementSnapshotDashboardBuilder().dashboard(for: .guardian)
        let first = ParentApprovalInboxSnapshotBuilder(redactionSalt: "salt-one").build(
            viewerRole: .guardian,
            growthPack: growth,
            schoolCredit: school,
            familyAchievement: achievement,
            creditSettlement: source.credit,
            offlineStatus: source.offlineStatus,
            offlineReport: source.offlineReport
        )
        let second = ParentApprovalInboxSnapshotBuilder(redactionSalt: "salt-two").build(
            viewerRole: .guardian,
            growthPack: growth,
            schoolCredit: school,
            familyAchievement: achievement,
            creditSettlement: source.credit,
            offlineStatus: source.offlineStatus,
            offlineReport: source.offlineReport
        )

        XCTAssertNotEqual(first.items.first?.publicApprovalRef, second.items.first?.publicApprovalRef)
        XCTAssertNotEqual(first.findings.first?.publicRef, second.findings.first?.publicRef)
    }

    private func growthRole(_ role: ParentApprovalInboxViewerRole) -> GrowthPackMobileDetailViewerRole {
        switch role {
        case .guardian: return .guardian
        case .child: return .child
        case .relative: return .relative
        case .teacher: return .teacher
        }
    }

    private func schoolRole(_ role: ParentApprovalInboxViewerRole) -> SchoolGrowthCreditViewerRole {
        switch role {
        case .guardian: return .guardian
        case .teacher: return .teacher
        case .child, .relative: return .child
        }
    }

    private func familyRole(_ role: ParentApprovalInboxViewerRole) -> FamilyGrowthViewerRole {
        switch role {
        case .guardian: return .guardian
        case .relative: return .relative
        case .child, .teacher: return .child
        }
    }
}
