import XCTest
@testable import OctoTeacher

final class MobileGrowthPackProofPreparationTests: XCTestCase {

    private func build(
        role: MobileGrowthPackExecutionHubRole,
        input: MobileGrowthPackProofPreparationInput = .mock
    ) -> MobileGrowthPackProofPreparation {
        MobileGrowthPackProofPreparationBuilder().build(role: role, input: input)
    }

    func testChildSeesSafePreparationWithoutAdultSensitiveDetails() {
        let preparation = build(role: .child)

        XCTAssertEqual(preparation.role, .child)
        XCTAssertEqual(preparation.publicSummary.itemCount, 7)
        XCTAssertEqual(preparation.publicSummary.visibleItemCount, 6)
        XCTAssertFalse(preparation.items.contains { $0.kind == .guardianContext })
        XCTAssertTrue(preparation.items.contains { $0.kind == .homeworkNote })
        XCTAssertTrue(preparation.items.contains { $0.kind == .rewardBoundary })
        XCTAssertGreaterThanOrEqual(preparation.publicSummary.readyCount, 1)
        XCTAssertGreaterThanOrEqual(preparation.publicSummary.blockedCount, 1)
        XCTAssertTrue(preparation.findings.allSatisfy(\.visibleToChild))
        XCTAssertFalse(preparation.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(preparation.hasUnsafeDisplayPayload)

        let text = preparation.displayValues.joined(separator: " ")
        for forbidden in [
            "答案键",
            "answer key",
            "成长积分金额",
            "账本明细",
            "复核策略",
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

    func testGuardianSeesReviewGapsConsentAndRewardBoundaries() {
        let preparation = build(role: .guardian)

        XCTAssertEqual(preparation.role, .guardian)
        XCTAssertEqual(preparation.publicSummary.visibleItemCount, 7)
        XCTAssertTrue(preparation.items.contains { $0.kind == .guardianContext })
        XCTAssertEqual(preparation.publicSummary.consentRequiredCount, 1)
        XCTAssertEqual(preparation.publicSummary.moderationRequiredCount, 1)
        XCTAssertGreaterThanOrEqual(preparation.publicSummary.reviewRequiredCount, 1)
        XCTAssertTrue(preparation.findings.contains { $0.code == .moderationRequired })
        XCTAssertFalse(preparation.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(preparation.hasUnsafeDisplayPayload)
    }

    func testPreparationFindingsCoverConsentCompletionExternalWearableAndReward() {
        let guardian = build(role: .guardian)
        let codes = Set(guardian.findings.map(\.code))

        XCTAssertTrue(codes.contains(.completionRequired))
        XCTAssertTrue(codes.contains(.consentRequired))
        XCTAssertTrue(codes.contains(.moderationRequired))
        XCTAssertTrue(codes.contains(.externalAllowlistRequired))
        XCTAssertTrue(codes.contains(.wearableReviewRequired))
        XCTAssertTrue(codes.contains(.rewardPressureBlocked))

        let child = build(role: .child)
        let childCodes = Set(child.findings.map(\.code))
        XCTAssertFalse(childCodes.contains(.moderationRequired))
        XCTAssertTrue(childCodes.contains(.consentRequired))
        XCTAssertTrue(childCodes.contains(.rewardPressureBlocked))
    }

    func testPreparationOrderingIsDeterministicAndStable() {
        let preparation = build(role: .child)
        let sortOrders = preparation.items.map(\.sortOrder)

        XCTAssertEqual(sortOrders, sortOrders.sorted())
        let kinds = preparation.items.map(\.kind)
        if let homeworkIndex = kinds.firstIndex(of: .homeworkNote),
           let quizIndex = kinds.firstIndex(of: .quizReflection),
           let rewardIndex = kinds.firstIndex(of: .rewardBoundary) {
            XCTAssertLessThan(homeworkIndex, quizIndex)
            XCTAssertLessThan(quizIndex, rewardIndex)
        } else {
            XCTFail("缺少关键准备项")
        }
        XCTAssertEqual(preparation.items.map(\.publicPrepRef), build(role: .child).items.map(\.publicPrepRef))
        XCTAssertNotEqual(preparation.items.map(\.publicPrepRef), build(role: .guardian).items.map(\.publicPrepRef))
    }

    func testUnsafePayloadHidesPreparationWithoutEchoingRawValue() {
        let preparation = build(
            role: .guardian,
            input: MobileGrowthPackProofPreparationInput(
                generatedAt: "2026-06-25T01:30:00.000Z",
                unsafePayload: "proof:raw media:raw ledger:raw device:raw http://example.invalid"
            )
        )

        XCTAssertTrue(preparation.items.isEmpty)
        XCTAssertEqual(preparation.publicSummary.findingCodes, [.unsafePayloadBlocked])
        XCTAssertFalse(preparation.displayValues.joined(separator: " ").localizedCaseInsensitiveContains("example.invalid"))
        XCTAssertFalse(preparation.publicSummary.hasTriggeredSideEffect)
    }

    func testUnmarkedPersonalPayloadIsNeverEchoed() {
        let preparation = build(
            role: .child,
            input: MobileGrowthPackProofPreparationInput(
                generatedAt: "2026-06-25T01:30:00.000Z",
                unsafePayload: "家长李四 电话13900000000 家庭住址示例巷2号"
            )
        )

        let text = preparation.displayValues.joined(separator: " ")
        for forbidden in ["李四", "13900000000", "示例巷2号"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(forbidden), forbidden)
        }
        XCTAssertFalse(preparation.publicSummary.hasTriggeredSideEffect)
    }

    func testPublicRefsAndDisplayValuesAreStableAndRedacted() {
        let preparation = build(role: .guardian)
        let refs = preparation.items.map(\.publicPrepRef)

        XCTAssertEqual(Set(refs).count, refs.count)
        XCTAssertTrue(refs.allSatisfy { $0.hasPrefix("gpp-") })
        for value in preparation.displayValues {
            for forbidden in ["child:", "family:", "proof:", "media:", "ledger:", "device:", "token", "192.168.", ".local", "/Volumes/"] {
                XCTAssertFalse(value.localizedCaseInsensitiveContains(forbidden), "\(value) contains \(forbidden)")
            }
        }
    }

    func testAllItemsAndSummaryRemainReadOnly() {
        for role in MobileGrowthPackExecutionHubRole.allCases {
            let preparation = build(role: role)

            XCTAssertFalse(preparation.publicSummary.callsNetwork)
            XCTAssertFalse(preparation.publicSummary.callsAiProvider)
            XCTAssertFalse(preparation.publicSummary.callsLocalModel)
            XCTAssertFalse(preparation.publicSummary.callsLms)
            XCTAssertFalse(preparation.publicSummary.writesSchoolSystem)
            XCTAssertFalse(preparation.publicSummary.opensExternalLink)
            XCTAssertFalse(preparation.publicSummary.opensCamera)
            XCTAssertFalse(preparation.publicSummary.opensPhotoLibrary)
            XCTAssertFalse(preparation.publicSummary.opensFilePicker)
            XCTAssertFalse(preparation.publicSummary.uploadsMedia)
            XCTAssertFalse(preparation.publicSummary.writesLedger)
            XCTAssertFalse(preparation.publicSummary.grantsCredit)
            XCTAssertFalse(preparation.publicSummary.spendsCredit)
            XCTAssertFalse(preparation.publicSummary.fulfillsReward)
            XCTAssertFalse(preparation.publicSummary.grantsBadge)
            XCTAssertFalse(preparation.publicSummary.updatesAbilityCard)
            XCTAssertFalse(preparation.publicSummary.unlocksDevice)
            XCTAssertFalse(preparation.publicSummary.controlsScreenTime)
            XCTAssertFalse(preparation.publicSummary.sendsNotification)
            XCTAssertFalse(preparation.publicSummary.publishesContent)
            XCTAssertFalse(preparation.publicSummary.hasTriggeredSideEffect)
            XCTAssertTrue(preparation.items.allSatisfy { !$0.hasTriggeredSideEffect })
        }
    }

    @MainActor
    func testViewInitializersCompileWithLockedRoles() {
        _ = MobileGrowthPackProofPreparationView()
        _ = MobileGrowthPackProofPreparationView(initialRole: .guardian, allowedRoles: [])
        _ = MobileGrowthPackProofPreparationView(initialRole: .child, allowedRoles: [.child])
        _ = MobileGrowthPackProofPreparationView(initialRole: .guardian, allowedRoles: [.guardian])
        _ = MobileGrowthPackExecutionHubView(initialRole: .child, allowedRoles: [.child])
        _ = MobileGrowthPackExecutionHubView(initialRole: .guardian, allowedRoles: [.guardian])
    }
}
