import XCTest
@testable import OctoTeacher

final class MobileGrowthPackEvidenceTimelineTests: XCTestCase {

    private func build(
        role: MobileGrowthPackExecutionHubRole,
        input: MobileGrowthPackEvidenceTimelineInput = .mock
    ) -> MobileGrowthPackEvidenceTimeline {
        MobileGrowthPackEvidenceTimelineBuilder().build(role: role, input: input)
    }

    func testChildSeesSafeEvidenceTimelineWithoutAdultSensitiveDetails() {
        let timeline = build(role: .child)

        XCTAssertEqual(timeline.role, .child)
        XCTAssertEqual(timeline.publicSummary.nodeCount, 9)
        XCTAssertEqual(timeline.publicSummary.visibleNodeCount, 9)
        XCTAssertGreaterThanOrEqual(timeline.publicSummary.evidenceGapCount, 1)
        XCTAssertTrue(timeline.nodes.contains { $0.kind == .homeworkProof })
        XCTAssertTrue(timeline.nodes.contains { $0.kind == .creativeProof })
        XCTAssertTrue(timeline.nodes.contains { $0.kind == .rewardReview })
        XCTAssertTrue(timeline.findings.allSatisfy(\.visibleToChild))
        XCTAssertFalse(timeline.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(timeline.hasUnsafeDisplayPayload)

        let text = timeline.displayValues.joined(separator: " ")
        for forbidden in [
            "答案键",
            "answer key",
            "成长积分金额",
            "账本明细",
            "order:",
            "ledger:",
            "device:",
            "provider:",
            "model:",
            "transcript",
            "http://",
            "https://",
            "/Users/"
        ] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(forbidden), forbidden)
        }
    }

    func testGuardianSeesReviewGapsTeacherAndRewardBoundaries() {
        let timeline = build(role: .guardian)

        XCTAssertEqual(timeline.role, .guardian)
        XCTAssertEqual(timeline.publicSummary.visibleNodeCount, 9)
        XCTAssertGreaterThanOrEqual(timeline.publicSummary.reviewRequiredCount, 1)
        XCTAssertGreaterThanOrEqual(timeline.publicSummary.teacherReviewCount, 1)
        XCTAssertGreaterThanOrEqual(timeline.publicSummary.guardianReviewCount, 1)
        XCTAssertEqual(timeline.publicSummary.rewardReviewCount, 1)
        XCTAssertTrue(timeline.findings.contains { $0.code == .rewardReviewRequired && $0.actionRequired })
        XCTAssertTrue(timeline.nodes.contains { $0.kind == .guardianReview })
        XCTAssertTrue(timeline.nodes.contains { $0.kind == .relativeEncouragement })
        XCTAssertFalse(timeline.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(timeline.hasUnsafeDisplayPayload)
    }

    func testUnsafePayloadHidesTimelineWithoutEchoingRawValue() {
        let timeline = build(
            role: .guardian,
            input: MobileGrowthPackEvidenceTimelineInput(
                generatedAt: "2026-06-25T00:40:00.000Z",
                unsafePayload: "proof:raw child:raw provider:model transcript token http://example.invalid"
            )
        )

        XCTAssertTrue(timeline.nodes.isEmpty)
        XCTAssertEqual(timeline.publicSummary.evidenceGapCount, 1)
        XCTAssertEqual(timeline.publicSummary.findingCodes, [.unsafePayloadBlocked])
        XCTAssertFalse(timeline.displayValues.joined(separator: " ").localizedCaseInsensitiveContains("example.invalid"))
        XCTAssertFalse(timeline.publicSummary.hasTriggeredSideEffect)
    }

    func testTimelineOrderingIsDeterministicAndCoversExecutionHubStepKinds() {
        let timeline = build(role: .child)
        let sortOrders = timeline.nodes.map(\.sortOrder)
        let coveredStepKinds = Set(timeline.nodes.map(\.kind.executionStepKind))

        XCTAssertEqual(sortOrders, sortOrders.sorted())
        XCTAssertEqual(coveredStepKinds, Set(MobileGrowthPackExecutionHubStepKind.allCases))
        XCTAssertEqual(timeline.nodes.map(\.publicNodeRef), build(role: .child).nodes.map(\.publicNodeRef))
        XCTAssertNotEqual(timeline.nodes.map(\.publicNodeRef), build(role: .guardian).nodes.map(\.publicNodeRef))
    }

    func testPublicRefsAndDisplayValuesAreStableAndRedacted() {
        let timeline = build(role: .guardian)
        let refs = timeline.nodes.map(\.publicNodeRef)

        XCTAssertEqual(Set(refs).count, refs.count)
        XCTAssertTrue(refs.allSatisfy { $0.hasPrefix("gpet-") })
        for value in timeline.displayValues {
            for forbidden in ["child:", "family:", "school:", "proof:", "token", "192.168.", ".local", "/Volumes/"] {
                XCTAssertFalse(value.localizedCaseInsensitiveContains(forbidden), "\(value) contains \(forbidden)")
            }
        }
    }

    func testAllNodesAndSummaryRemainReadOnly() {
        for role in MobileGrowthPackExecutionHubRole.allCases {
            let timeline = build(role: role)

            XCTAssertFalse(timeline.publicSummary.callsNetwork)
            XCTAssertFalse(timeline.publicSummary.callsAiProvider)
            XCTAssertFalse(timeline.publicSummary.callsLocalModel)
            XCTAssertFalse(timeline.publicSummary.callsLms)
            XCTAssertFalse(timeline.publicSummary.writesSchoolSystem)
            XCTAssertFalse(timeline.publicSummary.writesLedger)
            XCTAssertFalse(timeline.publicSummary.grantsCredit)
            XCTAssertFalse(timeline.publicSummary.unlocksDevice)
            XCTAssertFalse(timeline.publicSummary.sendsNotification)
            XCTAssertFalse(timeline.publicSummary.opensExternalLink)
            XCTAssertFalse(timeline.publicSummary.opensCamera)
            XCTAssertFalse(timeline.publicSummary.opensPhotoLibrary)
            XCTAssertFalse(timeline.publicSummary.opensFilePicker)
            XCTAssertFalse(timeline.publicSummary.uploadsMedia)
            XCTAssertFalse(timeline.publicSummary.publishesContent)
            XCTAssertFalse(timeline.publicSummary.createsOrder)
            XCTAssertFalse(timeline.publicSummary.writesEntitlement)
            XCTAssertFalse(timeline.publicSummary.hasTriggeredSideEffect)
            XCTAssertTrue(timeline.nodes.allSatisfy { !$0.hasTriggeredSideEffect })
        }
    }

    @MainActor
    func testViewInitializersCompileWithLockedRoles() {
        _ = MobileGrowthPackEvidenceTimelineView()
        _ = MobileGrowthPackEvidenceTimelineView(initialRole: .child, allowedRoles: [.child])
        _ = MobileGrowthPackEvidenceTimelineView(initialRole: .guardian, allowedRoles: [.guardian])
        _ = MobileGrowthPackExecutionHubView(initialRole: .child, allowedRoles: [.child])
        _ = MobileGrowthPackExecutionHubView(initialRole: .guardian, allowedRoles: [.guardian])
    }
}
