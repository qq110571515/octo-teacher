import XCTest
@testable import OctoTeacher

/// A86 成长日记 / VLOG / 故事线工作台测试。
///
/// 覆盖孩子、家长、亲友三种角色裁剪；草稿、待复核、撤回、阻断内容不公开、不授信；
/// 以及页面只读、安全降级和 SwiftUI initializer。
final class MobileGrowthDiaryVlogStorylineWorkbenchTests: XCTestCase {

    private func build(
        role: MobileGrowthDiaryVlogViewerRole,
        store: FamilyGrowthAchievementStore = FamilyGrowthAchievementStore()
    ) -> MobileGrowthDiaryVlogStorylineWorkbench {
        MobileGrowthDiaryVlogStorylineBuilder(store: store).build(role: role)
    }

    private func card(
        seed: String,
        kind: FamilyGrowthCardKind = .journal,
        summary: String = "这是一条安全的脱敏摘要。",
        visibility: FamilyGrowthCardVisibility = .privateOnly,
        lifecycle: FamilyGrowthLifecycle = .published,
        allowsRelative: Bool = false
    ) -> FamilyGrowthCard {
        FamilyGrowthCard(
            id: UUID(),
            internalSeed: seed,
            kind: kind,
            title: "测试成长记录",
            summary: summary,
            occurredLabel: "今天",
            visibility: visibility,
            lifecycle: lifecycle,
            supportiveCopy: "按自己的节奏记录就很好。",
            nextStep: "由家长确认下一步。",
            tags: ["测试"],
            allowsRelative: allowsRelative,
            reactionCount: 0,
            approvedCommentCount: 0,
            ratings: nil
        )
    }

    func testChildSeesDiaryVlogAndStorylineWithoutSideEffects() {
        let workbench = build(role: .child)

        XCTAssertEqual(workbench.role, .child)
        XCTAssertTrue(workbench.items.contains { $0.kind == .diary })
        XCTAssertTrue(workbench.items.contains { $0.kind == .vlogDraft })
        XCTAssertTrue(workbench.items.contains { $0.kind == .storyline })
        XCTAssertTrue(workbench.items.contains { $0.canContinueDraft && $0.kind == .vlogDraft })
        XCTAssertTrue(workbench.items.allSatisfy { !$0.showsGuardianReviewHint })
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(workbench.hasUnsafeDisplayPayload)
    }

    func testGuardianSeesReviewStatesButDoesNotPublishOrGrantCredit() {
        let workbench = build(role: .guardian)
        let summary = workbench.publicSummary

        XCTAssertEqual(workbench.role, .guardian)
        XCTAssertGreaterThan(summary.pendingReviewCount, 0)
        XCTAssertGreaterThan(summary.blockedCount, 0)
        XCTAssertTrue(workbench.items.contains { $0.reviewState == .pendingGuardianReview })
        XCTAssertTrue(workbench.items.contains { $0.reviewState == .withdrawn })
        XCTAssertTrue(workbench.items.contains { $0.reviewState == .blocked })
        XCTAssertTrue(workbench.items.contains { $0.showsGuardianReviewHint })
        XCTAssertTrue(workbench.nextActions.contains { $0.actionRequired })
        XCTAssertFalse(summary.opensCamera)
        XCTAssertFalse(summary.opensPhotoLibrary)
        XCTAssertFalse(summary.uploadsMedia)
        XCTAssertFalse(summary.publishesStoryline)
        XCTAssertFalse(summary.sendsComment)
        XCTAssertFalse(summary.sendsNotification)
        XCTAssertFalse(summary.callsNetwork)
        XCTAssertFalse(summary.callsAIProvider)
        XCTAssertFalse(summary.writesLedger)
        XCTAssertFalse(summary.grantsCredit)
        XCTAssertFalse(summary.unlocksDevice)
        XCTAssertFalse(summary.writesSchoolSystem)
    }

    func testRelativeOnlySeesApprovedFamilyOrRelativeVisibleFragments() {
        let workbench = build(role: .relative)

        XCTAssertEqual(workbench.role, .relative)
        XCTAssertFalse(workbench.items.isEmpty)
        XCTAssertFalse(workbench.items.contains { $0.kind == .diary })
        XCTAssertFalse(workbench.items.contains { $0.kind == .vlogDraft })
        XCTAssertTrue(workbench.items.allSatisfy { $0.reviewState == .familyVisible || $0.reviewState == .relativeVisible })
        XCTAssertTrue(workbench.items.allSatisfy(\.canRelativeEncourage))
        XCTAssertEqual(workbench.publicSummary.pendingReviewCount, 0)
        XCTAssertGreaterThan(workbench.publicSummary.hiddenItemCount, 0)
        XCTAssertFalse(workbench.displayValues.joined(separator: " ").contains("今天的小心情"))
        XCTAssertFalse(workbench.displayValues.joined(separator: " ").contains("成长 VLOG 占位"))
    }

    func testPendingWithdrawnAndBlockedItemsNeverTriggerExternalActions() {
        let workbench = build(role: .guardian)

        XCTAssertTrue(workbench.items.contains { $0.reviewState.needsGuardianReview })
        XCTAssertTrue(workbench.boundaries.contains { $0.id == "publish" && $0.isBlocked })
        XCTAssertTrue(workbench.boundaries.contains { $0.id == "credit" && $0.isBlocked })
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(workbench.publicSummary.publishesStoryline)
        XCTAssertFalse(workbench.publicSummary.grantsCredit)
        XCTAssertFalse(workbench.publicSummary.sendsNotification)
        XCTAssertFalse(workbench.publicSummary.unlocksDevice)
    }

    func testUnsafeDisplayPayloadFallsBackToBlockedShell() {
        let store = FamilyGrowthAchievementStore(cards: [
            card(
                seed: "unsafe-diary",
                summary: "http://example.invalid child:raw-ref",
                visibility: .family,
                lifecycle: .published
            )
        ])

        let workbench = build(role: .guardian, store: store)

        XCTAssertEqual(workbench.items.count, 0)
        XCTAssertEqual(workbench.publicSummary.visibleItemCount, 0)
        XCTAssertEqual(workbench.publicSummary.blockedCount, 1)
        XCTAssertTrue(workbench.boundaries.contains { $0.id == "unsafe" })
        XCTAssertFalse(workbench.displayValues.joined(separator: " ").contains("example.invalid"))
        XCTAssertFalse(workbench.displayValues.joined(separator: " ").contains("child:raw-ref"))
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
    }

    func testDisplayValuesDoNotLeakInternalSeedsOrSensitiveMarkers() {
        for role in MobileGrowthDiaryVlogViewerRole.allCases {
            let text = build(role: role).displayValues.joined(separator: " ")
            for raw in [
                "journal-private",
                "journal-withdrawn",
                "journal-blocked",
                "vlog-placeholder",
                "relative-comment-pending",
                "honor-reading-star"
            ] {
                XCTAssertFalse(text.contains(raw), "\(role.label) 泄露 internalSeed: \(raw)")
            }
            for marker in ["http://", "https://", "file://", "/Users/", "/Volumes/", "192.168.", "Bearer "] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "\(role.label) 泄露敏感标记: \(marker)")
            }
        }
    }

    @MainActor
    func testViewInitializerCompiles() {
        _ = GrowthDiaryVlogStorylineWorkbenchView()
        _ = GrowthDiaryVlogStorylineWorkbenchView(initialRole: .child, allowedRoles: [.child])
        _ = GrowthDiaryVlogStorylineWorkbenchView(initialRole: .relative, allowedRoles: [.relative])
    }
}
