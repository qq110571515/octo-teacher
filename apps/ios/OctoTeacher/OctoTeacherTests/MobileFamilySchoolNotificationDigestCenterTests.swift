import XCTest
@testable import OctoTeacher

final class MobileFamilySchoolNotificationDigestCenterTests: XCTestCase {

    private let builder = MobileFamilySchoolNotificationDigestCenterBuilder()

    @MainActor
    func testViewInitializersCompileForScopedRoles() {
        _ = FamilySchoolNotificationDigestCenterView()
        _ = FamilySchoolNotificationDigestCenterView(initialRole: .child, allowedRoles: [.child])
        _ = FamilySchoolNotificationDigestCenterView(initialRole: .teacher, allowedRoles: [.teacher])
        _ = FamilySchoolNotificationDigestCenterView(initialRole: .relative, allowedRoles: [.relative])
    }

    func testGuardianDigestIsReadOnlyAndShowsFamilyReview() {
        let snapshot = builder.build(viewerRole: .guardian)

        XCTAssertEqual(snapshot.viewerRole, .guardian)
        XCTAssertFalse(snapshot.cards.isEmpty)
        XCTAssertTrue(snapshot.cards.contains { $0.kind == .guardianReview })
        XCTAssertTrue(snapshot.cards.contains { $0.kind == .guardianRewardPending })
        XCTAssertTrue(snapshot.cards.contains { $0.kind == .relativeFamily })
        XCTAssertTrue(snapshot.publicSummary.visibleCardCount >= 4)
        XCTAssertFalse(snapshot.sideEffects.hasTriggeredSideEffect)
        XCTAssertFalse(snapshot.publicSummary.callsNetwork)
        XCTAssertFalse(snapshot.publicSummary.callsAiProvider)
        XCTAssertFalse(snapshot.publicSummary.callsLms)
        XCTAssertFalse(snapshot.publicSummary.writesSchoolSystem)
        XCTAssertFalse(snapshot.publicSummary.sendsNotification)
        XCTAssertFalse(snapshot.publicSummary.writesQueue)
        XCTAssertFalse(snapshot.publicSummary.writesLedger)
        XCTAssertFalse(snapshot.publicSummary.grantsCredit)
        XCTAssertFalse(snapshot.publicSummary.unlocksDevice)
        XCTAssertTrue(snapshot.findings.contains { $0.code == .digestReady })
    }

    func testGuardianDigestShowsRewardPendingCountsWithoutWishTitles() throws {
        let family = LocalFamilyStore()
        var child = family.child
        child.rewardBalanceMinutes = 120
        family.child = child
        let proposedWish = try XCTUnwrap(family.submitWish(title: "滑板课", childId: family.activeChildId))
        XCTAssertEqual(proposedWish.status, .proposed)
        let redeemedWish = try XCTUnwrap(family.submitWish(title: "秘密恐龙礼物", childId: family.activeChildId))
        XCTAssertTrue(family.priceWish(redeemedWish.id, points: 30))
        XCTAssertTrue(family.redeemWish(redeemedWish.id))
        _ = try XCTUnwrap(family.requestPocketMoneyExchange(points: 20, childId: family.activeChildId))

        let snapshot = builder.build(viewerRole: .guardian, family: family)
        let rewardCard = try XCTUnwrap(snapshot.cards.first { $0.kind == .guardianRewardPending })

        XCTAssertEqual(rewardCard.state, .needsReview)
        XCTAssertTrue(rewardCard.detail.contains("3 个奖励项"))
        XCTAssertTrue(rewardCard.detail.contains("待定价 1"))
        XCTAssertTrue(rewardCard.detail.contains("待兑现 1"))
        XCTAssertTrue(rewardCard.detail.contains("零花钱确认 1"))
        XCTAssertFalse(rewardCard.detail.contains("滑板课"))
        XCTAssertFalse(rewardCard.detail.contains("秘密恐龙礼物"))
        XCTAssertFalse(rewardCard.sendsNotification)
        XCTAssertFalse(rewardCard.writesQueue)
        XCTAssertFalse(rewardCard.writesLedger)
        XCTAssertFalse(rewardCard.grantsCredit)
    }

    func testRewardPendingDigestIsGuardianOnly() throws {
        let family = LocalFamilyStore()
        var child = family.child
        child.rewardBalanceMinutes = 60
        family.child = child
        let wish = try XCTUnwrap(family.submitWish(title: "只给家长看的愿望", childId: family.activeChildId))
        XCTAssertTrue(family.priceWish(wish.id, points: 20))
        XCTAssertTrue(family.redeemWish(wish.id))

        let childSnapshot = builder.build(viewerRole: .child, family: family)

        XCTAssertFalse(childSnapshot.cards.contains { $0.kind == .guardianRewardPending })
        XCTAssertFalse(displayedText(childSnapshot).contains("只给家长看的愿望"))
    }

    func testChildDigestHidesAnswerTranscriptAndAdultReasons() {
        let snapshot = builder.build(
            viewerRole: .child,
            scenario: MobileFamilySchoolNotificationDigestScenario(
                containsAnswerKey: true,
                containsRawTranscript: true,
                containsAdultInternalReason: true
            )
        )

        XCTAssertEqual(snapshot.viewerRole, .child)
        XCTAssertEqual(snapshot.status, .reviewRequired)
        XCTAssertTrue(snapshot.cards.contains { $0.kind == .childHomework })
        XCTAssertTrue(snapshot.findings.contains { $0.code == .rolePrivateDetailHidden })
        XCTAssertTrue(snapshot.cards.allSatisfy {
            !$0.showsAnswerKey && !$0.showsRawTranscript && !$0.showsAdultInternalReason
        })
        XCTAssertFalse(displayedText(snapshot).localizedCaseInsensitiveContains("answerkey"))
        XCTAssertFalse(displayedText(snapshot).localizedCaseInsensitiveContains("transcript_private"))
    }

    func testTeacherRosterInactiveBlocksSchoolSummary() {
        let snapshot = builder.build(
            viewerRole: .teacher,
            scenario: MobileFamilySchoolNotificationDigestScenario(teacherRosterActive: false)
        )

        XCTAssertEqual(snapshot.status, .blocked)
        XCTAssertTrue(snapshot.cards.contains { $0.kind == .teacherSchool && $0.state == .suppressed })
        XCTAssertTrue(snapshot.findings.contains { $0.code == .teacherRosterExpired && $0.severity == .blocker })
        XCTAssertTrue(snapshot.cards.allSatisfy { !$0.writesSchoolSystem && !$0.callsLms })
    }

    func testRelativeDigestBlocksConsentCreditBudgetAndRawProofDetails() {
        let snapshot = builder.build(
            viewerRole: .relative,
            scenario: MobileFamilySchoolNotificationDigestScenario(
                guardianConsentGranted: false,
                relativeConsentGranted: false,
                containsCreditAmount: true,
                containsBudget: true,
                containsRawProof: true,
                containsCrossChildContent: true
            )
        )

        XCTAssertEqual(snapshot.status, .blocked)
        XCTAssertTrue(snapshot.cards.contains { $0.kind == .relativeFamily && $0.state == .suppressed })
        XCTAssertTrue(snapshot.findings.contains { $0.code == .guardianConsentRequired })
        XCTAssertTrue(snapshot.findings.contains { $0.code == .relativePrivateDetailBlocked })
        XCTAssertTrue(snapshot.cards.allSatisfy {
            !$0.showsCreditAmount && !$0.showsRawProof && !$0.showsCrossChildContent
        })
        XCTAssertFalse(displayedText(snapshot).localizedCaseInsensitiveContains("成长积分金额"))
    }

    func testMissingGuardianConsentBlocksRelativeDigestEvenWhenRelativeConsentExists() {
        let snapshot = builder.build(
            viewerRole: .relative,
            scenario: MobileFamilySchoolNotificationDigestScenario(
                guardianConsentGranted: false,
                relativeConsentGranted: true
            )
        )

        XCTAssertEqual(snapshot.status, .blocked)
        XCTAssertTrue(snapshot.cards.contains { $0.kind == .relativeFamily && $0.state == .suppressed })
        XCTAssertTrue(snapshot.findings.contains { $0.code == .guardianConsentRequired && $0.severity == .blocker })
        XCTAssertFalse(snapshot.publicSummary.sendsNotification)
        XCTAssertFalse(snapshot.publicSummary.writesQueue)
    }

    func testEmptyStoresStillProduceStableReadOnlySnapshot() {
        let family = LocalFamilyStore()
        family.assignments = []
        let schoolFamily = SchoolFamilyStore()
        schoolFamily.homeworks = []
        schoolFamily.relativeComments = []
        schoolFamily.honorWall = []

        let snapshot = builder.build(viewerRole: .guardian, family: family, schoolFamily: schoolFamily)

        XCTAssertEqual(snapshot.status, .ready)
        XCTAssertTrue(snapshot.cards.contains { $0.kind == .guardianReview && $0.state == .deliverable })
        XCTAssertTrue(snapshot.cards.contains { $0.kind == .relativeFamily && $0.state == .deliverable })
        XCTAssertFalse(snapshot.sideEffects.hasTriggeredSideEffect)
        XCTAssertFalse(displayedText(snapshot).localizedCaseInsensitiveContains("child:"))
    }

    func testQuietWindowSuppressesUrgentOverrideWithoutSendingNotification() {
        let snapshot = builder.build(
            viewerRole: .guardian,
            scenario: MobileFamilySchoolNotificationDigestScenario(urgentQuietOverrideAllowed: false)
        )

        XCTAssertEqual(snapshot.status, .reviewRequired)
        XCTAssertTrue(snapshot.cards.contains { $0.kind == .quietWindow && $0.state == .suppressed })
        XCTAssertTrue(snapshot.findings.contains { $0.code == .urgentQuietOverrideBlocked })
        XCTAssertFalse(snapshot.boundary.sendsNotification)
        XCTAssertFalse(snapshot.publicSummary.sendsNotification)
        XCTAssertFalse(snapshot.publicSummary.writesQueue)
    }

    func testUnsafePayloadFallsBackWithoutEchoingSensitiveInput() {
        let snapshot = builder.build(
            viewerRole: .guardian,
            scenario: MobileFamilySchoolNotificationDigestScenario(
                unsafePayload: "child:raw http://192.168.1.252/v1 token sk-test /Users/developer/private transcript_private"
            )
        )

        XCTAssertEqual(snapshot.status, .blocked)
        XCTAssertTrue(snapshot.cards.isEmpty)
        XCTAssertEqual(snapshot.publicSummary.findingCodes, [.unsafePayloadBlocked])
        XCTAssertFalse(displayedText(snapshot).localizedCaseInsensitiveContains("192.168.1.252"))
        XCTAssertFalse(displayedText(snapshot).localizedCaseInsensitiveContains("sk-test"))
        XCTAssertFalse(displayedText(snapshot).localizedCaseInsensitiveContains("/Users/developer"))
        XCTAssertFalse(displayedText(snapshot).localizedCaseInsensitiveContains("transcript_private"))
    }

    func testPublicSummaryAndCardsRemainSideEffectFreeForAllRoles() {
        for role in MobileFamilySchoolNotificationDigestViewerRole.allCases {
            let snapshot = builder.build(viewerRole: role)
            XCTAssertFalse(snapshot.sideEffects.hasTriggeredSideEffect, role.label)
            XCTAssertFalse(snapshot.publicSummary.callsNetwork, role.label)
            XCTAssertFalse(snapshot.publicSummary.callsAiProvider, role.label)
            XCTAssertFalse(snapshot.publicSummary.callsLocalModel, role.label)
            XCTAssertFalse(snapshot.publicSummary.callsLms, role.label)
            XCTAssertFalse(snapshot.publicSummary.writesSchoolSystem, role.label)
            XCTAssertFalse(snapshot.publicSummary.sendsNotification, role.label)
            XCTAssertFalse(snapshot.publicSummary.writesQueue, role.label)
            XCTAssertFalse(snapshot.publicSummary.writesDatabase, role.label)
            XCTAssertFalse(snapshot.publicSummary.writesLedger, role.label)
            XCTAssertFalse(snapshot.publicSummary.grantsCredit, role.label)
            XCTAssertFalse(snapshot.publicSummary.unlocksDevice, role.label)
            XCTAssertFalse(snapshot.publicSummary.storesRawTranscript, role.label)
            XCTAssertTrue(snapshot.cards.allSatisfy { card in
                !card.callsAiProvider && !card.callsLms && !card.writesSchoolSystem
                    && !card.sendsNotification && !card.writesQueue && !card.writesLedger
                    && !card.grantsCredit && !card.unlocksDevice
            }, role.label)
        }
    }

    func testOutputDoesNotLeakUnsafeMarkers() {
        for role in MobileFamilySchoolNotificationDigestViewerRole.allCases {
            let snapshot = builder.build(viewerRole: role)
            let text = displayedText(snapshot)
            for marker in [
                "child:",
                "family:",
                "teacher:",
                "guardian:",
                "relative:",
                "taskid",
                "claimid",
                "baseurl",
                "token",
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

    private func displayedText(_ snapshot: MobileFamilySchoolNotificationDigestSnapshot) -> String {
        var values = [
            snapshot.generatedAt,
            snapshot.viewerRole.rawValue,
            snapshot.status.rawValue,
            snapshot.headline
        ]
        values += snapshot.cards.flatMap {
            [$0.publicCardRef, $0.kind.rawValue, $0.title, $0.detail, $0.state.rawValue]
        }
        values += snapshot.findings.flatMap {
            [$0.code.rawValue, $0.severity.rawValue, $0.message, $0.publicRef]
        }
        values += snapshot.publicSummary.findingCodes.map(\.rawValue)
        return values.joined(separator: " ")
    }
}
