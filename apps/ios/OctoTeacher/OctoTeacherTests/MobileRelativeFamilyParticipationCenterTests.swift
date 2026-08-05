import XCTest
@testable import OctoTeacher

/// A83 亲友/祖辈参与中心测试。
///
/// 覆盖亲友可见性、离线待审核留言、只读副作用边界、敏感内容安全降级和 SwiftUI initializer。
final class MobileRelativeFamilyParticipationCenterTests: XCTestCase {

    private func build(
        family: LocalFamilyStore = LocalFamilyStore(),
        school: SchoolFamilyStore = SchoolFamilyStore(),
        achievementStore: FamilyGrowthAchievementStore = FamilyGrowthAchievementStore(),
        outbox: MobileOfflineOutboxStore = MobileOfflineOutboxStore()
    ) -> MobileRelativeFamilyParticipationCenter {
        MobileRelativeFamilyParticipationCenterBuilder(
            family: family,
            schoolFamily: school,
            achievementStore: achievementStore,
            offlineOutbox: outbox
        )
        .build()
    }

    func testDefaultCenterShowsOnlyRelativeVisibleApprovedContent() {
        let center = build()

        XCTAssertEqual(center.status, .ready)
        XCTAssertEqual(center.relativeCount, 2)
        XCTAssertEqual(center.visibleFeedCount, 1)
        XCTAssertEqual(center.visibleHonorCount, 1)
        XCTAssertEqual(center.approvedCommentCount, 1)
        XCTAssertEqual(center.pendingLocalCommentCount, 0)
        XCTAssertFalse(center.visibleCards.isEmpty)
        XCTAssertTrue(center.visibleCards.contains { $0.title == "坚持阅读第 7 天" })
        XCTAssertFalse(center.visibleCards.contains { $0.title == "数学小进步" })
        XCTAssertFalse(center.visibleCards.contains { $0.title == "情绪小记" })
        XCTAssertTrue(center.comments.allSatisfy { $0.statusLabel == "已通过" })
        XCTAssertTrue(center.nextActions.contains { $0.action == .leaveEncouragement })
    }

    func testRelativeCommentOnlyEntersLocalPendingQueue() throws {
        let outbox = MobileOfflineOutboxStore()
        let composer = MobileOfflineActionComposer()
        let result = outbox.enqueue(composer.relativeComment(
            targetSeed: "family-feed",
            relativeSeed: "relative-self",
            message: "看到你坚持阅读很开心"
        ))

        guard case .success(let mutation) = result else {
            return XCTFail("亲友鼓励应能进入本地队列")
        }
        XCTAssertEqual(mutation.kind, .relativeComment)
        XCTAssertEqual(mutation.actorRole, .relative)
        XCTAssertEqual(mutation.status, .pending)

        let center = build(outbox: outbox)
        XCTAssertEqual(center.status, .waitingForGuardianReview)
        XCTAssertEqual(center.pendingLocalCommentCount, 1)
        XCTAssertTrue(center.comments.contains { $0.statusLabel == "待家长审核" })
        XCTAssertTrue(center.nextActions.contains { $0.action == .waitForGuardianReview })
        XCTAssertFalse(center.publicSummary.grantsCredit)
        XCTAssertFalse(center.publicSummary.writesLedger)
        XCTAssertFalse(center.publicSummary.unlocksDevice)
        XCTAssertFalse(center.publicSummary.sendsNotification)
    }

    func testPublicSummaryAndBoundariesAreSideEffectFree() {
        let center = build()
        let summary = center.publicSummary

        XCTAssertFalse(summary.grantsCredit)
        XCTAssertFalse(summary.spendsCredit)
        XCTAssertFalse(summary.approvesTask)
        XCTAssertFalse(summary.rejectsTask)
        XCTAssertFalse(summary.writesLedger)
        XCTAssertFalse(summary.unlocksDevice)
        XCTAssertFalse(summary.sendsNotification)
        XCTAssertFalse(summary.uploadsMedia)
        XCTAssertFalse(summary.callsNetwork)
        XCTAssertFalse(summary.writesSchoolSystem)
        XCTAssertFalse(summary.publishesHonorWall)
        XCTAssertTrue(center.boundaries.contains { $0.id == "credit" && $0.isBlocked })
        XCTAssertTrue(center.boundaries.contains { $0.id == "device" && $0.isBlocked })
    }

    func testUnsafeDisplayInputFallsBackToBlockedShell() {
        let school = SchoolFamilyStore()
        school.feed[0].summary = "http://example.invalid child:raw-ref"

        let center = build(school: school)

        XCTAssertEqual(center.status, .blocked)
        XCTAssertTrue(center.visibleCards.isEmpty)
        XCTAssertTrue(center.comments.isEmpty)
        XCTAssertEqual(center.publicSummary.visibleFeedCount, 0)
        XCTAssertTrue(center.nextActions.contains { $0.action == .fixUnsafeInput })
        XCTAssertFalse(center.publicSummary.callsNetwork)
        XCTAssertFalse(center.publicSummary.unlocksDevice)
    }

    func testUnsafeAchievementCardFallsBackToBlockedShell() {
        let achievementStore = FamilyGrowthAchievementStore(cards: [
            FamilyGrowthCard(
                id: UUID(),
                internalSeed: "relative-visible-unsafe",
                kind: .honorWall,
                title: "亲友可见荣誉",
                summary: "https://example.invalid/path",
                occurredLabel: "本周",
                visibility: .relatives,
                lifecycle: .published,
                supportiveCopy: "保持自己的节奏。",
                nextStep: "由家长确认下一步。",
                tags: ["测试"],
                allowsRelative: true,
                reactionCount: 0,
                approvedCommentCount: 0,
                ratings: nil
            )
        ])

        let center = build(achievementStore: achievementStore)

        XCTAssertEqual(center.status, .blocked)
        XCTAssertTrue(center.visibleCards.isEmpty)
        XCTAssertEqual(center.publicSummary.visibleHonorCount, 0)
        XCTAssertFalse(center.publicSummary.uploadsMedia)
        XCTAssertFalse(center.publicSummary.sendsNotification)
    }

    func testUnsafePendingOutboxCommentFallsBackToBlockedShell() {
        let unsafeMutation = MobileOfflineMutation(
            clientMutationRef: "offline-safe-ref",
            kind: .relativeComment,
            actorRole: .relative,
            actorPublicRef: "actor-relative-demo",
            subjectPublicRef: "feed-demo",
            summaryPreview: "Bearer sk-local-secret-token",
            idempotencyKey: "idem-safe-ref",
            status: .pending,
            enqueuedAt: "2026-06-23T21:00:00Z",
            conflictReason: nil
        )
        let outbox = MobileOfflineOutboxStore(mutations: [unsafeMutation])

        let center = build(outbox: outbox)

        XCTAssertEqual(center.status, .blocked)
        XCTAssertTrue(center.comments.isEmpty)
        XCTAssertEqual(center.publicSummary.pendingLocalCommentCount, 0)
        XCTAssertFalse(center.publicSummary.writesLedger)
        XCTAssertFalse(center.publicSummary.unlocksDevice)
    }

    @MainActor
    func testViewInitializerCompiles() {
        _ = RelativeFamilyParticipationCenterView()
        _ = RelativeFamilyParticipationCenterView(achievementStore: FamilyGrowthAchievementStore())
    }
}
