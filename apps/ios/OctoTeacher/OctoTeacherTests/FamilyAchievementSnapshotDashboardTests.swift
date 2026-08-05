import XCTest
@testable import OctoTeacher

/// 家庭成就快照仪表盘测试。
///
/// 覆盖 B32 iOS 落地的关键边界：家长可见审核/阻断，孩子和亲友只读且不泄露待审核计数、
/// 家长审批动作或内部引用；仪表盘无发布、授徽章、改能力卡、写账本、通知亲友或解锁设备副作用。
final class FamilyAchievementSnapshotDashboardTests: XCTestCase {

    private func builder() -> FamilyAchievementSnapshotDashboardBuilder {
        FamilyAchievementSnapshotDashboardBuilder(store: FamilyGrowthAchievementStore())
    }

    func testGuardianDashboardShowsReviewWorkAndRiskActions() {
        let dashboard = builder().dashboard(for: .guardian)

        XCTAssertEqual(dashboard.role, .guardian)
        XCTAssertEqual(dashboard.status, .blocked)
        XCTAssertGreaterThan(dashboard.evidence.visibleAchievementCount, 0)
        XCTAssertGreaterThan(dashboard.evidence.reviewRequiredCount, 0)
        XCTAssertGreaterThan(dashboard.evidence.blockedCount, 0)
        XCTAssertGreaterThan(dashboard.relativeParticipation.pendingCommentCount, 0)
        XCTAssertTrue(dashboard.hasActionableGuardianWork)
        XCTAssertTrue(dashboard.nextActions.contains { $0.kind == .approveRelativeComment })
        XCTAssertTrue(dashboard.nextActions.contains { $0.kind == .reviewPendingAchievement })
        XCTAssertTrue(dashboard.nextActions.contains { $0.kind == .reviewBlockedContent })
        XCTAssertTrue(dashboard.riskFlags.contains { $0.severity == .blocker })
    }

    func testRelativeDashboardDoesNotExposeGuardianReviewState() {
        let dashboard = builder().dashboard(for: .relative)

        XCTAssertEqual(dashboard.role, .relative)
        XCTAssertTrue(dashboard.relativeParticipation.canSeeParticipation)
        XCTAssertGreaterThan(dashboard.relativeParticipation.approvedCommentCount, 0)
        XCTAssertEqual(dashboard.relativeParticipation.pendingCommentCount, 0)
        XCTAssertEqual(dashboard.relativeParticipation.blockedActionCount, 0)
        XCTAssertTrue(dashboard.riskFlags.isEmpty)
        XCTAssertTrue(dashboard.nextActions.allSatisfy { !$0.actionRequired })
        XCTAssertFalse(dashboard.nextActions.contains { $0.kind == .approveRelativeComment })
        XCTAssertTrue(dashboard.relativeParticipation.viewerRelativePublicRef?.hasPrefix("relative:") == true)
    }

    func testChildDashboardIsReadOnlyAndDoesNotExposeRelativeReviewCounts() {
        let dashboard = builder().dashboard(for: .child)

        XCTAssertEqual(dashboard.role, .child)
        XCTAssertFalse(dashboard.relativeParticipation.canSeeParticipation)
        XCTAssertEqual(dashboard.relativeParticipation.approvedCommentCount, 0)
        XCTAssertEqual(dashboard.relativeParticipation.pendingCommentCount, 0)
        XCTAssertEqual(dashboard.relativeParticipation.blockedActionCount, 0)
        XCTAssertTrue(dashboard.riskFlags.isEmpty)
        XCTAssertTrue(dashboard.nextActions.allSatisfy { $0.kind == .readOnly && !$0.actionRequired })
    }

    func testSummarySectionsStaySideEffectFree() {
        let dashboard = builder().dashboard(for: .guardian)
        let summary = dashboard.publicSummary

        XCTAssertFalse(dashboard.evidence.writesLedger)
        XCTAssertFalse(dashboard.evidence.modifiesHomework)
        XCTAssertTrue(dashboard.badgeSummary.sideEffectFree)
        XCTAssertTrue(dashboard.honorSummary.sideEffectFree)
        XCTAssertTrue(dashboard.storylineSummary.sideEffectFree)
        XCTAssertFalse(dashboard.abilityCardSummary.updatesAbilityCard)
        XCTAssertFalse(summary.grantsBadge)
        XCTAssertFalse(summary.updatesAbilityCard)
        XCTAssertFalse(summary.publishesHonorWall)
        XCTAssertFalse(summary.emitsEvent)
        XCTAssertFalse(summary.writesLedger)
        XCTAssertFalse(summary.modifiesTaskState)
        XCTAssertFalse(summary.modifiesHomework)
        XCTAssertFalse(summary.uploadsMedia)
        XCTAssertFalse(summary.sendsNotification)
        XCTAssertFalse(summary.notifiesRelatives)
        XCTAssertFalse(summary.unlocksDevice)
    }

    func testAbilityCardSummaryIsBoundedAndDeterministic() {
        let first = builder().dashboard(for: .guardian).abilityCardSummary
        let second = builder().dashboard(for: .guardian).abilityCardSummary

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.cardCount, 1)
        XCTAssertEqual(first.dimensionScoreCount, AbilityDimension.allCases.count)
        XCTAssertNotNil(first.averageScore)
        XCTAssertGreaterThanOrEqual(first.averageScore ?? 0, 1)
        XCTAssertLessThanOrEqual(first.averageScore ?? 0, 99)
    }

    func testDashboardPublicRefsAreStableAndRedacted() {
        let first = builder().dashboard(for: .guardian)
        let second = builder().dashboard(for: .guardian)
        let serialized = [
            first.familyPublicRef,
            first.childPublicRef,
            first.riskFlags.map(\.id).joined(separator: " "),
            first.nextActions.map(\.id).joined(separator: " ")
        ].joined(separator: " ")

        XCTAssertEqual(first.familyPublicRef, second.familyPublicRef)
        XCTAssertEqual(first.childPublicRef, second.childPublicRef)
        XCTAssertTrue(first.familyPublicRef.hasPrefix("family:"))
        XCTAssertTrue(first.childPublicRef.hasPrefix("child:"))
        for raw in ["family-self", "child-self", "relative-self", "journal-blocked", "relative-comment-pending"] {
            XCTAssertFalse(serialized.contains(raw), "仪表盘公开引用不得包含内部 seed：\(raw)")
        }
    }
}
