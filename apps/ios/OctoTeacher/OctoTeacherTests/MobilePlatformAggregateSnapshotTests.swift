import XCTest
@testable import OctoTeacher

final class MobilePlatformAggregateSnapshotTests: XCTestCase {

    private struct Sources {
        var family: LocalFamilyStore
        var school: SchoolFamilyStore
        var runtime: GrowthRuntimeSettlementReport
        var evidence: GrowthEvidenceTimelineReport
        var offlineStatus: MobileOfflinePublicStatus
        var offlineReport: MobileOfflineReplayReport
        var credit: MobileCreditSettlementReport
        var mobile: MobileSyncSnapshot
    }

    private func makeSources(
        offlineStatus: MobileOfflinePublicStatus = MobileOfflinePublicStatus(pendingCount: 2, conflictCount: 1, rolledBackCount: 1)
    ) -> Sources {
        let family = LocalFamilyStore()
        let school = SchoolFamilyStore()
        let runtimeStore = GrowthPackRuntimeStore()
        let runtime = runtimeStore.refresh(family: family, schoolFamily: school)
        let evidenceStore = GrowthEvidenceTimelineStore()
        let evidence = evidenceStore.refresh(
            family: family,
            schoolFamily: school,
            runtime: GrowthEvidenceTimelineRuntimeContext(report: runtime)
        )
        let offlineOutbox = MobileOfflineOutboxStore.mock()
        let offlineReplay = MobileOfflineReplayStore()
        let replayReport = offlineReplay.replay(outbox: offlineOutbox)
        let creditStore = MobileCreditSettlementStore()
        creditStore.refresh(
            offlineReport: replayReport,
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
            offlineReport: replayReport,
            credit: creditStore.report,
            mobile: MobileSyncClient.makeMockOrEmpty().snapshot
        )
    }

    private func snapshot(
        role: MobilePlatformAggregateViewerRole,
        sources: Sources? = nil,
        mobileOverride: MobileSyncSnapshot? = nil,
        growthPackInstallOverride: GrowthPackInstallSnapshot? = nil
    ) -> MobilePlatformAggregateSnapshot {
        let source = sources ?? makeSources()
        let growth = GrowthPackMobileDetailSnapshotBuilder().build(
            viewerRole: growthRole(role),
            runtimeReport: source.runtime,
            evidenceReport: source.evidence,
            offlineStatus: source.offlineStatus,
            offlineReport: source.offlineReport
        )
        let school = SchoolGrowthCreditSnapshotBuilder().build(
            viewerRole: schoolRole(role),
            homeworks: source.school.homeworks,
            runtimeReport: source.runtime,
            evidenceReport: source.evidence,
            offlineStatus: source.offlineStatus,
            offlineReport: source.offlineReport
        )
        let achievement = FamilyAchievementSnapshotDashboardBuilder().dashboard(for: familyRole(role))
        return MobilePlatformAggregateSnapshotBuilder().build(
            viewerRole: role,
            mobileSnapshot: mobileOverride ?? source.mobile,
            familyAchievement: achievement,
            growthPack: growth,
            schoolCredit: school,
            offlineStatus: source.offlineStatus,
            offlineReport: source.offlineReport,
            creditSettlement: source.credit,
            growthPackInstall: growthPackInstallOverride
        )
    }

    private func adapterSnapshot(
        role: MobilePlatformAggregateViewerRole,
        sources: Sources? = nil,
        growthPackInstallOverride: GrowthPackInstallSnapshot? = nil
    ) -> (snapshot: MobilePlatformAggregateSnapshot, adapter: MobilePlatformAggregateReadOnlyAdapter) {
        let source = sources ?? makeSources()
        let growth = GrowthPackMobileDetailSnapshotBuilder().build(
            viewerRole: growthRole(role),
            runtimeReport: source.runtime,
            evidenceReport: source.evidence,
            offlineStatus: source.offlineStatus,
            offlineReport: source.offlineReport
        )
        let school = SchoolGrowthCreditSnapshotBuilder().build(
            viewerRole: schoolRole(role),
            homeworks: source.school.homeworks,
            runtimeReport: source.runtime,
            evidenceReport: source.evidence,
            offlineStatus: source.offlineStatus,
            offlineReport: source.offlineReport
        )
        let achievement = FamilyAchievementSnapshotDashboardBuilder().dashboard(for: familyRole(role))
        let adapter = MobilePlatformAggregateReadOnlyAdapter()
        let snapshot = adapter.makeSnapshot(
            viewerRole: role,
            mobileSnapshot: source.mobile,
            familyAchievement: achievement,
            growthPack: growth,
            schoolCredit: school,
            offlineStatus: source.offlineStatus,
            offlineReport: source.offlineReport,
            creditSettlement: source.credit,
            growthPackInstall: growthPackInstallOverride
        )
        return (snapshot, adapter)
    }

    func testGuardianSeesPlatformModulesAndReviewQueues() {
        let guardian = snapshot(role: .guardian)

        XCTAssertEqual(guardian.header.viewerRole, .guardian)
        XCTAssertTrue(guardian.roleVisibility.canSeeCreditRewards)
        XCTAssertTrue(guardian.roleVisibility.canSeePendingReview)
        XCTAssertTrue(guardian.roleVisibility.canSeeOfflineSync)
        XCTAssertTrue(guardian.creditRewards.visible)
        XCTAssertTrue(guardian.growthPackInstall.visible)
        XCTAssertTrue(guardian.pendingReview.visible)
        XCTAssertGreaterThan(guardian.moduleCards.count, 5)
        XCTAssertGreaterThan(guardian.pendingReview.actionRequiredCount, 0)
        XCTAssertGreaterThan(guardian.offlineSync.conflictCount + guardian.offlineSync.rollbackRequiredCount, 0)
        XCTAssertTrue(guardian.nextActions.contains { $0.actionRequired })
        XCTAssertTrue(guardian.riskFlags.contains { $0.source == .offlineSync || $0.source == .creditReward })
    }

    func testChildHidesAdultReviewCreditAndOfflineConflictDetails() {
        let child = snapshot(role: .child)

        XCTAssertTrue(child.roleVisibility.canSeeTodayTasks)
        XCTAssertTrue(child.roleVisibility.canSeeGrowthPack)
        XCTAssertTrue(child.roleVisibility.canSeeSchoolHomework)
        XCTAssertFalse(child.roleVisibility.canSeeCreditRewards)
        XCTAssertFalse(child.roleVisibility.canSeePendingReview)
        XCTAssertFalse(child.creditRewards.visible)
        XCTAssertTrue(child.growthPackInstall.visible)
        XCTAssertGreaterThan(child.growthPackInstall.installedCount, 0)
        XCTAssertFalse(child.pendingReview.visible)
        XCTAssertEqual(child.creditRewards.proposalCount, 0)
        XCTAssertEqual(child.pendingReview.actionRequiredCount, 0)
        XCTAssertEqual(child.offlineSync.conflictCount, 0)
        XCTAssertEqual(child.offlineSync.rollbackRequiredCount, 0)
        XCTAssertFalse(child.riskFlags.contains { $0.source == .offlineSync })
        XCTAssertFalse(child.nextActions.contains { !$0.visibleToChild })
    }

    func testRelativeOnlyGetsPublicFamilyAchievementSummary() {
        let relative = snapshot(role: .relative)

        XCTAssertFalse(relative.roleVisibility.canSeeTodayTasks)
        XCTAssertFalse(relative.roleVisibility.canSeeGrowthPack)
        XCTAssertFalse(relative.roleVisibility.canSeeSchoolHomework)
        XCTAssertFalse(relative.roleVisibility.canSeeCreditRewards)
        XCTAssertFalse(relative.roleVisibility.canSeePendingReview)
        XCTAssertFalse(relative.growthPack.visible)
        XCTAssertFalse(relative.growthPackInstall.visible)
        XCTAssertEqual(relative.growthPackInstall.installedCount, 0)
        XCTAssertEqual(relative.publicSummary.growthPackInstallAttentionCount, 0)
        XCTAssertFalse(relative.schoolHomework.visible)
        XCTAssertFalse(relative.creditRewards.visible)
        XCTAssertTrue(relative.familyAchievements.visible)
        XCTAssertTrue(relative.familyAchievements.relativeParticipationVisible)
        XCTAssertEqual(relative.pendingReview.actionRequiredCount, 0)
        XCTAssertEqual(relative.pendingReview.appealCount, 0)
        XCTAssertEqual(relative.publicSummary.creditProposalCount, 0)
        XCTAssertEqual(relative.publicSummary.offlineConflictCount, 0)
    }

    func testTeacherGetsSchoolContextWithoutGuardianCreditOrFamilyPrivateData() {
        let teacher = snapshot(role: .teacher)

        XCTAssertTrue(teacher.roleVisibility.canSeeSchoolHomework)
        XCTAssertTrue(teacher.roleVisibility.canSeeGrowthPack)
        XCTAssertFalse(teacher.roleVisibility.canSeeCreditRewards)
        XCTAssertFalse(teacher.roleVisibility.canSeeOfflineSync)
        XCTAssertFalse(teacher.roleVisibility.canSeeFamilyAchievements)
        XCTAssertFalse(teacher.growthPackInstall.visible)
        XCTAssertEqual(teacher.growthPackInstall.installedCount, 0)
        XCTAssertEqual(teacher.growthPackInstall.needsGuardianAttentionCount, 0)
        XCTAssertTrue(teacher.schoolHomework.visible)
        XCTAssertTrue(teacher.schoolHomework.canSeeTeacherVerification)
        XCTAssertFalse(teacher.schoolHomework.canSeeGuardianConfirmation)
        XCTAssertFalse(teacher.creditRewards.visible)
        XCTAssertFalse(teacher.familyAchievements.visible)
        XCTAssertFalse(teacher.nextActions.contains { $0.kind.hasPrefix("install_entitlement") })
        XCTAssertTrue(teacher.nextActions.allSatisfy { $0.source == .schoolHomework || $0.source == .growthPack || $0.source == .roleBoundary })
    }

    func testGuardianGrowthPackInstallEntitlementAggregateCountsAttentionWithoutInstallable() {
        let guardian = snapshot(role: .guardian)
        let install = GrowthPackInstallEntitlementBuilder().build(viewerRole: .guardian)
        let expectedAttention = install.decisions.filter {
            $0.state == .pendingGuardianConfirmation || $0.state == .frozen || $0.state == .blocked
        }.count

        XCTAssertTrue(guardian.growthPackInstall.visible)
        XCTAssertEqual(guardian.growthPackInstall.visiblePackCount, install.decisions.count)
        XCTAssertEqual(guardian.growthPackInstall.installedCount, install.publicSummary.installedCount)
        XCTAssertEqual(guardian.growthPackInstall.needsGuardianAttentionCount, expectedAttention)
        XCTAssertEqual(
            guardian.growthPackInstall.installableCount + guardian.growthPackInstall.needsGuardianAttentionCount + guardian.growthPackInstall.installedCount,
            install.decisions.count
        )
        XCTAssertLessThan(guardian.growthPackInstall.needsGuardianAttentionCount, install.decisions.count)
        XCTAssertEqual(guardian.publicSummary.growthPackInstalledCount, guardian.growthPackInstall.installedCount)
        XCTAssertEqual(guardian.publicSummary.growthPackInstallAttentionCount, expectedAttention)

        let growthCard = guardian.moduleCards.first { $0.kind == .growthPack }
        XCTAssertTrue(growthCard?.subtitle.contains("已安装") == true)
        XCTAssertTrue(growthCard?.metricLabel.contains("需关注") == true)
        XCTAssertTrue(guardian.nextActions.contains { $0.kind == "install_entitlement_review" && $0.actionRequired })
        XCTAssertTrue(guardian.riskFlags.contains { $0.source == .growthPack && $0.code == "GROWTH_PACK_INSTALL_ATTENTION" })
    }

    func testReadOnlyAdapterBuildsGrowthPackInstallDisplayWithoutSideEffects() {
        let result = adapterSnapshot(role: .guardian)
        let display = result.adapter.growthPackInstallDisplay(from: result.snapshot)

        XCTAssertTrue(display.visible)
        XCTAssertEqual(display.title, "成长包安装权益")
        XCTAssertTrue(display.detail.contains("家长复核"))
        XCTAssertEqual(display.metrics.map(\.label), ["可见", "已安装", "可安装", "待确认", "冻结", "阻断", "需关注"])
        XCTAssertEqual(display.metrics.first { $0.label == "已安装" }?.value, result.snapshot.growthPackInstall.installedCount)
        XCTAssertEqual(display.metrics.first { $0.label == "需关注" }?.value, result.snapshot.growthPackInstall.needsGuardianAttentionCount)
        XCTAssertTrue(display.actionRequired)
        XCTAssertTrue(MobilePlatformAggregateReadOnlyAdapter.redacts(display))

        XCTAssertFalse(display.chargesPayment)
        XCTAssertFalse(display.createsOrder)
        XCTAssertFalse(display.writesMarketplace)
        XCTAssertFalse(display.writesEntitlement)
        XCTAssertFalse(display.writesLedger)
        XCTAssertFalse(display.grantsCredit)
        XCTAssertFalse(display.unlocksDevice)
        XCTAssertFalse(display.callsCloud)
        XCTAssertFalse(display.callsAi)
        XCTAssertFalse(display.writesSchoolSystem)
    }

    func testReadOnlyAdapterInstallDisplayHonorsRoleVisibility() {
        let child = adapterSnapshot(role: .child)
        let childDisplay = child.adapter.growthPackInstallDisplay(from: child.snapshot)

        XCTAssertTrue(childDisplay.visible)
        XCTAssertFalse(childDisplay.actionRequired)
        XCTAssertTrue(childDisplay.detail.contains("等待家长确认") || child.snapshot.growthPackInstall.needsGuardianAttentionCount == 0)
        XCTAssertTrue(MobilePlatformAggregateReadOnlyAdapter.redacts(childDisplay))

        for role in [MobilePlatformAggregateViewerRole.relative, .teacher] {
            let result = adapterSnapshot(role: role)
            let display = result.adapter.growthPackInstallDisplay(from: result.snapshot)

            XCTAssertFalse(display.visible)
            XCTAssertTrue(display.metrics.isEmpty)
            XCTAssertEqual(result.snapshot.growthPackInstall.installedCount, 0)
            XCTAssertEqual(result.snapshot.publicSummary.growthPackInstalledCount, 0)
            XCTAssertEqual(result.snapshot.publicSummary.growthPackInstallAttentionCount, 0)
            XCTAssertTrue(MobilePlatformAggregateReadOnlyAdapter.redacts(display))
        }
    }

    func testReadOnlyAdapterBlocksUnsafeInstallSnapshotBeforeDisplay() {
        var install = GrowthPackInstallEntitlementBuilder().build(viewerRole: .guardian)
        install.decisions[0].title = "https://example.com/private 123e4567-e89b-12d3-a456-426614174000"

        let result = adapterSnapshot(role: .guardian, growthPackInstallOverride: install)
        let display = result.adapter.growthPackInstallDisplay(from: result.snapshot)

        XCTAssertEqual(result.snapshot.header.status, .blocked)
        XCTAssertFalse(display.visible)
        XCTAssertTrue(display.metrics.isEmpty)
        XCTAssertEqual(result.snapshot.publicSummary.growthPackInstallAttentionCount, 0)
        XCTAssertEqual(result.snapshot.findings.first?.code, .publicSummaryLeak)
        XCTAssertTrue(MobilePlatformAggregateReadOnlyAdapter.redacts(display))
        XCTAssertFalse(String(describing: display).contains("https://example.com/private"))
        XCTAssertFalse(String(describing: display).contains("123e4567-e89b-12d3-a456-426614174000"))
        XCTAssertFalse(String(describing: result.snapshot).contains("https://example.com/private"))
        XCTAssertFalse(String(describing: result.snapshot).contains("123e4567-e89b-12d3-a456-426614174000"))
    }

    func testPublicSummaryHasNoSideEffects() {
        let guardian = snapshot(role: .guardian)
        let summary = guardian.publicSummary

        XCTAssertFalse(summary.writesLedger)
        XCTAssertFalse(summary.modifiesTaskState)
        XCTAssertFalse(summary.modifiesHomework)
        XCTAssertFalse(summary.writesSchoolHomework)
        XCTAssertFalse(summary.grantsBadge)
        XCTAssertFalse(summary.updatesAbilityCard)
        XCTAssertFalse(summary.publishesHonorWall)
        XCTAssertFalse(summary.sendsNotification)
        XCTAssertFalse(summary.notifiesRelatives)
        XCTAssertFalse(summary.unlocksDevice)
        XCTAssertFalse(summary.createsOrder)
        XCTAssertFalse(summary.writesMarketplace)
        XCTAssertFalse(summary.writesEntitlement)
        XCTAssertFalse(summary.callsCloud)
        XCTAssertFalse(summary.uploadsMedia)
        XCTAssertFalse(summary.uploadsAttachment)
        XCTAssertFalse(summary.callsSchoolSystem)
        XCTAssertFalse(summary.usesAiToAnswer)

        XCTAssertFalse(guardian.growthPackInstall.chargesPayment)
        XCTAssertFalse(guardian.growthPackInstall.createsOrder)
        XCTAssertFalse(guardian.growthPackInstall.writesMarketplace)
        XCTAssertFalse(guardian.growthPackInstall.writesEntitlement)
        XCTAssertFalse(guardian.growthPackInstall.writesLedger)
        XCTAssertFalse(guardian.growthPackInstall.grantsCredit)
        XCTAssertFalse(guardian.growthPackInstall.unlocksDevice)
        XCTAssertFalse(guardian.growthPackInstall.callsCloud)
        XCTAssertFalse(guardian.growthPackInstall.callsAi)
        XCTAssertFalse(guardian.growthPackInstall.writesSchoolSystem)
    }

    func testSnapshotRedactionIsStableAndBlocksRawRefs() {
        let sources = makeSources()
        let builder = MobilePlatformAggregateSnapshotBuilder()
        let first = snapshot(role: .guardian, sources: sources)
        let second = snapshot(role: .guardian, sources: sources)

        XCTAssertEqual(first, second)
        XCTAssertTrue(builder.redacts(first))
        let text = (
            first.header.childPublicRefs
            + first.todayTasks.map(\.publicTaskRef)
            + first.moduleCards.map(\.publicCardRef)
            + first.nextActions.map(\.publicActionRef)
            + first.riskFlags.map(\.publicRiskRef)
            + first.findings.map(\.publicRef)
        ).joined(separator: " ")
        for marker in ["child:", "family:", "school:", "teacher:", "relative:", "pack:", "creator:", "order:", "entitlement:", "proof:", "ledger:", "device:", "gpi-order", "gpi-ent", "192.168.", "file://", "http://", "https://"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "不应泄露 \(marker)")
        }
    }

    func testUnsafeMobileInputFallsBackToBlockedSnapshot() throws {
        var mobile = MobileSyncClient.makeMockOrEmpty().snapshot
        try XCTSkipIf(mobile.tasks.isEmpty)
        mobile.tasks[0].title = "打开 file://secret-proof.png"

        let blocked = snapshot(role: .child, mobileOverride: mobile)

        XCTAssertEqual(blocked.header.status, .blocked)
        XCTAssertTrue(blocked.todayTasks.isEmpty)
        XCTAssertEqual(blocked.findings.first?.code, .publicSummaryLeak)
        XCTAssertEqual(blocked.publicSummary.findingCodes, [.publicSummaryLeak])
    }

    func testUnsafeGrowthPackInstallAggregateFallsBackToBlockedSnapshot() {
        var install = GrowthPackInstallEntitlementBuilder().build(viewerRole: .guardian)
        install.decisions[0].title = "https://example.com/private 123e4567-e89b-12d3-a456-426614174000"

        let blocked = snapshot(role: .guardian, growthPackInstallOverride: install)

        XCTAssertEqual(blocked.header.status, .blocked)
        XCTAssertFalse(blocked.growthPackInstall.visible)
        XCTAssertEqual(blocked.publicSummary.growthPackInstallAttentionCount, 0)
        XCTAssertEqual(blocked.findings.first?.code, .publicSummaryLeak)
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
        let first = MobilePlatformAggregateSnapshotBuilder(redactionSalt: "salt-one").build(
            viewerRole: .guardian,
            mobileSnapshot: source.mobile,
            familyAchievement: achievement,
            growthPack: growth,
            schoolCredit: school,
            offlineStatus: source.offlineStatus,
            offlineReport: source.offlineReport,
            creditSettlement: source.credit
        )
        let second = MobilePlatformAggregateSnapshotBuilder(redactionSalt: "salt-two").build(
            viewerRole: .guardian,
            mobileSnapshot: source.mobile,
            familyAchievement: achievement,
            growthPack: growth,
            schoolCredit: school,
            offlineStatus: source.offlineStatus,
            offlineReport: source.offlineReport,
            creditSettlement: source.credit
        )

        XCTAssertNotEqual(first.moduleCards.first?.publicCardRef, second.moduleCards.first?.publicCardRef)
        XCTAssertNotEqual(first.todayTasks.first?.publicTaskRef, second.todayTasks.first?.publicTaskRef)
    }

    private func growthRole(_ role: MobilePlatformAggregateViewerRole) -> GrowthPackMobileDetailViewerRole {
        switch role {
        case .child: return .child
        case .guardian: return .guardian
        case .relative: return .relative
        case .teacher: return .teacher
        }
    }

    private func schoolRole(_ role: MobilePlatformAggregateViewerRole) -> SchoolGrowthCreditViewerRole {
        switch role {
        case .child, .relative: return .child
        case .guardian: return .guardian
        case .teacher: return .teacher
        }
    }

    private func familyRole(_ role: MobilePlatformAggregateViewerRole) -> FamilyGrowthViewerRole {
        switch role {
        case .child, .teacher: return .child
        case .guardian: return .guardian
        case .relative: return .relative
        }
    }
}
