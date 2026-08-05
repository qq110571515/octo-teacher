import XCTest
@testable import OctoTeacher

final class MobileGrowthPackExecutionHubTests: XCTestCase {

    private func build(
        role: MobileGrowthPackExecutionHubRole,
        input: MobileGrowthPackExecutionHubInput = .mock
    ) -> MobileGrowthPackExecutionHub {
        MobileGrowthPackExecutionHubBuilder().build(role: role, input: input)
    }

    func testChildSeesExecutionStepsWithoutAdultSensitiveDetails() {
        let hub = build(role: .child)

        XCTAssertEqual(hub.role, .child)
        XCTAssertEqual(hub.publicSummary.stepCount, 7)
        XCTAssertEqual(hub.publicSummary.visibleStepCount, 7)
        XCTAssertTrue(hub.steps.contains { $0.kind == .schoolHomework })
        XCTAssertTrue(hub.steps.contains { $0.kind == .quizSelfCheck })
        XCTAssertTrue(hub.steps.contains { $0.kind == .rewardFulfillment })
        XCTAssertTrue(hub.findings.allSatisfy(\.visibleToChild))
        XCTAssertFalse(hub.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(hub.hasUnsafeDisplayPayload)

        let text = hub.displayValues.joined(separator: " ")
        for forbidden in [
            "答案键",
            "answer key",
            "成长积分金额",
            "账本明细",
            "order:",
            "provider:",
            "model:",
            "transcript",
            "设备命令",
            "http://",
            "https://",
            "/Users/"
        ] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(forbidden), forbidden)
        }
    }

    func testGuardianSeesReviewTeacherAndRewardBoundaries() {
        let hub = build(role: .guardian)

        XCTAssertEqual(hub.role, .guardian)
        XCTAssertEqual(hub.publicSummary.visibleStepCount, 7)
        XCTAssertGreaterThanOrEqual(hub.publicSummary.guardianReviewCount, 1)
        XCTAssertGreaterThanOrEqual(hub.publicSummary.teacherReviewCount, 1)
        XCTAssertEqual(hub.publicSummary.rewardReviewCount, 1)
        XCTAssertTrue(hub.findings.contains { $0.code == .rewardFulfillmentReview && $0.actionRequired })
        XCTAssertTrue(hub.steps.contains { $0.destination == .familyHonor })
        XCTAssertFalse(hub.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(hub.hasUnsafeDisplayPayload)
    }

    func testUnsafePayloadHidesStepsWithoutEchoingRawValue() {
        let hub = build(
            role: .guardian,
            input: MobileGrowthPackExecutionHubInput(
                generatedAt: "2026-06-25T00:00:00.000Z",
                unsafePayload: "child:raw provider:model transcript token http://example.invalid"
            )
        )

        XCTAssertTrue(hub.steps.isEmpty)
        XCTAssertEqual(hub.publicSummary.blockedCount, 1)
        XCTAssertEqual(hub.publicSummary.findingCodes, [.unsafePayloadBlocked])
        XCTAssertFalse(hub.displayValues.joined(separator: " ").localizedCaseInsensitiveContains("example.invalid"))
        XCTAssertFalse(hub.publicSummary.hasTriggeredSideEffect)
    }

    func testAllRowsAndSummaryRemainReadOnly() {
        for role in MobileGrowthPackExecutionHubRole.allCases {
            let hub = build(role: role)

            XCTAssertFalse(hub.publicSummary.callsNetwork)
            XCTAssertFalse(hub.publicSummary.callsAiProvider)
            XCTAssertFalse(hub.publicSummary.callsLocalModel)
            XCTAssertFalse(hub.publicSummary.callsLms)
            XCTAssertFalse(hub.publicSummary.writesSchoolSystem)
            XCTAssertFalse(hub.publicSummary.writesLedger)
            XCTAssertFalse(hub.publicSummary.grantsCredit)
            XCTAssertFalse(hub.publicSummary.unlocksDevice)
            XCTAssertFalse(hub.publicSummary.sendsNotification)
            XCTAssertFalse(hub.publicSummary.opensExternalLink)
            XCTAssertFalse(hub.publicSummary.opensCamera)
            XCTAssertFalse(hub.publicSummary.opensPhotoLibrary)
            XCTAssertFalse(hub.publicSummary.opensFilePicker)
            XCTAssertFalse(hub.publicSummary.uploadsMedia)
            XCTAssertFalse(hub.publicSummary.createsOrder)
            XCTAssertFalse(hub.publicSummary.writesEntitlement)
            XCTAssertFalse(hub.publicSummary.hasTriggeredSideEffect)

            XCTAssertTrue(hub.steps.allSatisfy { !$0.hasTriggeredSideEffect })
        }
    }

    func testDestinationRawValuesAreStableAndRedacted() {
        let destinations = Set(build(role: .child).steps.map(\.destination))

        XCTAssertEqual(destinations, Set(MobileGrowthPackExecutionHubDestination.allCases))
        for destination in destinations {
            XCTAssertFalse(destination.rawValue.localizedCaseInsensitiveContains("provider"))
            XCTAssertFalse(destination.rawValue.localizedCaseInsensitiveContains("model"))
            XCTAssertFalse(destination.rawValue.localizedCaseInsensitiveContains("transcript"))
            XCTAssertFalse(destination.rawValue.localizedCaseInsensitiveContains("token"))
            XCTAssertFalse(destination.rawValue.localizedCaseInsensitiveContains("ledger"))
            XCTAssertFalse(destination.rawValue.localizedCaseInsensitiveContains("device"))
            XCTAssertFalse(destination.rawValue.localizedCaseInsensitiveContains("order"))
        }
    }

    func testHomeIncludesRoleLockedExecutionHubEntries() throws {
        let orchestrator = MobileHomeOrchestrator(
            sync: try MobileSyncClient.makeMock(),
            schoolFamily: SchoolFamilyStore(),
            family: LocalFamilyStore()
        )
        let childHome = orchestrator.makeViewModel(for: .child)
        let guardianHome = orchestrator.makeViewModel(for: .parent)

        XCTAssertTrue(childHome.sections.contains { section in
            section.id == "growth-pack-execution-hub"
                && section.items.contains { $0.destination == .growthPackExecutionHub }
        })
        XCTAssertTrue(guardianHome.sections.contains { section in
            section.id == "growth-pack-execution-hub"
                && section.items.contains { $0.destination == .growthPackExecutionHub }
        })
        XCTAssertEqual(MobileHomeDestination.growthPackExecutionHub.allowedPerspectives, [.child, .parent])
        XCTAssertFalse(MobileHomeDestination.growthPackExecutionHub.rawValue.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(MobileHomeDestination.growthPackExecutionHub.rawValue.localizedCaseInsensitiveContains("ledger"))
        XCTAssertFalse(MobileHomeDestination.growthPackExecutionHub.rawValue.localizedCaseInsensitiveContains("device"))
    }

    func testModuleLaunchCenterRoutesExecutionHubByRole() {
        let resolver = MobileModuleLaunchRouteResolver()
        let childRoute = resolver.route(for: .growthPackExecutionHub, viewerRole: .child)
        let guardianRoute = resolver.route(for: .growthPackExecutionHub, viewerRole: .guardian)
        let operationsRoute = resolver.route(for: .growthPackExecutionHub, viewerRole: .operations)
        let relativeRoute = resolver.route(for: .growthPackExecutionHub, viewerRole: .relative)

        XCTAssertEqual(childRoute?.destinationKind, .growthPackExecutionHub)
        XCTAssertEqual(childRoute?.allowedRoles, [.child, .guardian, .operations])
        XCTAssertEqual(guardianRoute?.destinationKind, .growthPackExecutionHub)
        XCTAssertEqual(operationsRoute?.destinationKind, .safePreview)
        XCTAssertNil(relativeRoute)
        XCTAssertTrue(resolver.redacts([childRoute, guardianRoute, operationsRoute].compactMap { $0 }))
    }

    @MainActor
    func testViewInitializersCompileWithLockedRoles() {
        _ = MobileGrowthPackExecutionHubView()
        _ = MobileGrowthPackExecutionHubView(initialRole: .child, allowedRoles: [.child])
        _ = MobileGrowthPackExecutionHubView(initialRole: .guardian, allowedRoles: [.guardian])
    }
}
