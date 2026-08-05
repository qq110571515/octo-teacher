import XCTest
@testable import OctoTeacher

final class MobileModuleConfigurationDraftTests: XCTestCase {
    private let builder = MobileModuleConfigurationDraftBuilder()

    func testGuardianSeesDraftPlanAndCreditPreviewWithoutSideEffects() {
        let snapshot = builder.build(viewerRole: .guardian)

        XCTAssertEqual(snapshot.viewerRole, .guardian)
        XCTAssertFalse(snapshot.items.isEmpty)
        XCTAssertTrue(snapshot.items.contains { $0.moduleKey == .todayTasks })
        XCTAssertTrue(snapshot.items.contains { $0.moduleKey == .growthPackRuntime })
        XCTAssertTrue(snapshot.items.contains { $0.moduleKey == .schoolHomework })
        XCTAssertTrue(snapshot.items.contains { $0.moduleKey == .honorWall })
        XCTAssertTrue(snapshot.items.contains { $0.moduleKey == .rewardWindow })
        XCTAssertNotNil(snapshot.publicSummary.creditPreviewTotal)
        XCTAssertGreaterThan(snapshot.publicSummary.creditPreviewTotal ?? 0, 0)
        XCTAssertTrue(snapshot.items.contains { $0.requiresGuardianApproval })
        XCTAssertEqual(snapshot.publicSummary.reviewActionCount, snapshot.reviewActions.count)
        XCTAssertGreaterThan(snapshot.publicSummary.reviewActionCount, 0)
        assertNoSideEffects(snapshot)
    }

    func testGuardianReviewActionsReferenceVisibleItemsAndStayReadOnly() {
        let snapshot = builder.build(viewerRole: .guardian)
        let itemRefs = Set(snapshot.items.map(\.publicItemRef))

        XCTAssertFalse(snapshot.reviewActions.isEmpty)
        XCTAssertTrue(snapshot.reviewActions.allSatisfy { itemRefs.contains($0.itemRef) })
        XCTAssertTrue(snapshot.reviewActions.allSatisfy(\.requiresGuardianDecision))
        XCTAssertTrue(snapshot.reviewActions.allSatisfy { $0.publicActionRef.hasPrefix("mcd-") })
        XCTAssertEqual(snapshot.publicSummary.reviewActionCount, snapshot.reviewActions.count)
        XCTAssertEqual(
            snapshot.publicSummary.blockingActionCount,
            snapshot.reviewActions.filter(\.blockedUntilReviewed).count
        )
        assertNoSideEffects(snapshot)
    }

    func testBlockingReviewActionsComeFromSchoolRewardOrWarnings() {
        let snapshot = builder.build(viewerRole: .guardian)
        let itemsByRef = Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.publicItemRef, $0) })
        let blocking = snapshot.reviewActions.filter(\.blockedUntilReviewed)

        XCTAssertFalse(blocking.isEmpty)
        XCTAssertTrue(blocking.contains { $0.moduleKey == .schoolHomework && $0.priority == .urgent })
        XCTAssertTrue(blocking.contains { $0.moduleKey == .rewardWindow && $0.priority == .high })
        XCTAssertTrue(blocking.allSatisfy { action in
            guard let item = itemsByRef[action.itemRef] else { return false }
            return item.warning != nil || action.moduleKey == .schoolHomework || action.moduleKey == .rewardWindow
        })
        XCTAssertTrue(blocking.allSatisfy { $0.detail.contains("复核前不发布配置") })
    }

    func testChildSeesSafeSummaryWithoutConfigurationControlsOrCreditPreview() {
        let snapshot = builder.build(viewerRole: .child)

        XCTAssertEqual(snapshot.viewerRole, .child)
        XCTAssertFalse(snapshot.items.isEmpty)
        XCTAssertNil(snapshot.publicSummary.creditPreviewTotal)
        XCTAssertTrue(snapshot.reviewActions.isEmpty)
        XCTAssertEqual(snapshot.publicSummary.reviewActionCount, 0)
        XCTAssertEqual(snapshot.publicSummary.blockingActionCount, 0)
        XCTAssertTrue(snapshot.items.allSatisfy { $0.creditPreviewMinutes == nil })
        XCTAssertTrue(snapshot.items.allSatisfy { !$0.requiresGuardianApproval })
        XCTAssertTrue(snapshot.findings.contains { $0.code == .childControlsHidden })
        assertNoSideEffects(snapshot)
    }

    func testOperationsViewIsRedactedAndCountOnly() {
        let snapshot = builder.build(viewerRole: .operations)

        XCTAssertEqual(snapshot.viewerRole, .operations)
        XCTAssertFalse(snapshot.items.isEmpty)
        XCTAssertNil(snapshot.publicSummary.creditPreviewTotal)
        XCTAssertTrue(snapshot.reviewActions.isEmpty)
        XCTAssertEqual(snapshot.publicSummary.reviewActionCount, 0)
        XCTAssertEqual(snapshot.publicSummary.blockingActionCount, 0)
        XCTAssertTrue(snapshot.items.allSatisfy { $0.creditPreviewMinutes == nil })
        XCTAssertTrue(snapshot.findings.contains { $0.code == .operationsRedacted })
        XCTAssertTrue(snapshot.items.allSatisfy { $0.detail.localizedCaseInsensitiveContains("脱敏") })
    }

    func testBudgetAndSchoolPriorityFindingsArePresent() {
        let snapshot = builder.build(viewerRole: .guardian)

        XCTAssertEqual(snapshot.status, .reviewRequired)
        XCTAssertTrue(snapshot.findings.contains { $0.code == .creditBudgetReview })
        XCTAssertTrue(snapshot.findings.contains { $0.code == .schoolPriority })
        XCTAssertTrue(snapshot.items.contains { $0.warning?.contains("学校作业") == true })
    }

    func testBudgetFindingUsesInjectedFamilyLimit() {
        let family = LocalFamilyStore()
        family.child.dailyLimitMinutes = 20
        let snapshot = builder.build(
            viewerRole: .guardian,
            family: family,
            schoolFamily: SchoolFamilyStore()
        )

        XCTAssertTrue(snapshot.findings.contains { $0.code == .creditBudgetReview })
        XCTAssertEqual(snapshot.status, .reviewRequired)
    }

    func testUnsafeInputFallsBackWithoutEchoingRawPayload() {
        let snapshot = builder.build(
            viewerRole: .guardian,
            unsafePayload: ["provider:model:qwen http://192.168.1.252/v1 token sk-test /Users/developer/private task:raw claim:raw"]
        )

        XCTAssertEqual(snapshot.status, .blocked)
        XCTAssertTrue(snapshot.items.isEmpty)
        XCTAssertTrue(snapshot.reviewActions.isEmpty)
        XCTAssertEqual(snapshot.publicSummary.reviewActionCount, 0)
        XCTAssertEqual(snapshot.publicSummary.blockingActionCount, 0)
        XCTAssertEqual(snapshot.publicSummary.findingCodes, [.unsafeInputBlocked])
        let text = displayedText(snapshot)
        XCTAssertFalse(text.localizedCaseInsensitiveContains("192.168.1.252"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("sk-test"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("/Users/developer"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("task:raw"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("claim:raw"))
    }

    func testUnsafeDraftItemTitleCannotLeakThroughReviewActions() {
        let family = LocalFamilyStore()
        family.assignments[0].task.title = "provider:model:qwen http://192.168.1.252/v1 token sk-test task:raw"
        let snapshot = builder.build(viewerRole: .guardian, family: family)

        XCTAssertEqual(snapshot.status, .blocked)
        XCTAssertTrue(snapshot.items.isEmpty)
        XCTAssertTrue(snapshot.reviewActions.isEmpty)
        let text = displayedText(snapshot)
        XCTAssertFalse(text.localizedCaseInsensitiveContains("provider:model"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("192.168.1.252"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("sk-test"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("task:raw"))
    }

    func testOutputDoesNotLeakSensitiveMarkers() {
        for role in MobileModuleConfigurationDraftViewerRole.allCases {
            let snapshot = builder.build(viewerRole: role)
            let text = displayedText(snapshot)
            for marker in [
                "publicRef",
                "provider:",
                "model:",
                "transcript",
                "答案键",
                "成长积分金额",
                "task:",
                "claim:",
                "ledger:",
                "order:",
                "entitlement:",
                "http://",
                "https://",
                "192.168.",
                "/Users/",
                "/Volumes/"
            ] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "\(role.label) leaked \(marker)")
            }
        }
    }

    private func assertNoSideEffects(_ snapshot: MobileModuleConfigurationDraftSnapshot) {
        XCTAssertFalse(snapshot.sideEffects.hasTriggeredSideEffect)
        XCTAssertFalse(snapshot.publicSummary.writesAssignments)
        XCTAssertFalse(snapshot.publicSummary.writesLedger)
        XCTAssertFalse(snapshot.publicSummary.grantsCredit)
        XCTAssertFalse(snapshot.publicSummary.unlocksDevice)
        XCTAssertFalse(snapshot.publicSummary.sendsNotification)
        XCTAssertFalse(snapshot.publicSummary.callsNetwork)
        XCTAssertFalse(snapshot.publicSummary.callsAiProvider)
        XCTAssertFalse(snapshot.publicSummary.callsLocalModel)
        XCTAssertFalse(snapshot.publicSummary.callsLms)
        XCTAssertFalse(snapshot.publicSummary.writesSchoolSystem)
        XCTAssertFalse(snapshot.publicSummary.writesEntitlement)
        XCTAssertFalse(snapshot.publicSummary.createsOrder)
        XCTAssertTrue(snapshot.items.allSatisfy { item in
            !item.writesAssignments
                && !item.writesLedger
                && !item.grantsCredit
                && !item.unlocksDevice
                && !item.sendsNotification
                && !item.callsNetwork
                && !item.callsAiProvider
                && !item.callsLms
                && !item.writesSchoolSystem
                && !item.writesEntitlement
                && !item.createsOrder
        })
        XCTAssertTrue(snapshot.reviewActions.allSatisfy { action in
            !action.writesAssignments
                && !action.writesLedger
                && !action.grantsCredit
                && !action.unlocksDevice
                && !action.sendsNotification
                && !action.callsNetwork
                && !action.callsAiProvider
                && !action.callsLms
                && !action.writesSchoolSystem
                && !action.writesEntitlement
                && !action.createsOrder
        })
    }

    private func displayedText(_ snapshot: MobileModuleConfigurationDraftSnapshot) -> String {
        snapshot.displayValues.joined(separator: " ")
    }
}
