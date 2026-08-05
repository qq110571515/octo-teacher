import XCTest
@testable import OctoTeacher

final class CreatorManifestPreviewSnapshotTests: XCTestCase {

    private func snapshot(
        role: CreatorManifestPreviewViewerRole,
        draft: CreatorManifestPreviewDraft = .mock,
        salt: String = "creator-manifest-preview-ios-v1"
    ) -> CreatorManifestPreviewSnapshot {
        CreatorManifestPreviewSnapshotBuilder(redactionSalt: salt).build(
            viewerRole: role,
            draft: draft
        )
    }

    func testGuardianAndCreatorCanReviewCompleteManifestDraft() {
        for role in [CreatorManifestPreviewViewerRole.guardian, .creator] {
            let preview = snapshot(role: role)

            XCTAssertEqual(preview.status, .readyForReview)
            XCTAssertTrue(preview.visibility.canSeeManifest)
            XCTAssertTrue(preview.visibility.canSeeCreditDrafts)
            XCTAssertTrue(preview.visibility.canSeeBadgeAbilityDrafts)
            XCTAssertNotNil(preview.licenseBoundary)
            XCTAssertEqual(preview.contentBlocks.count, 5)
            XCTAssertEqual(preview.proofRequirements.count, 4)
            XCTAssertEqual(preview.creditDrafts.count, 2)
            XCTAssertEqual(preview.badgeAbilityDrafts.count, 2)
            XCTAssertTrue(preview.findings.contains { $0.code == .manifestPreviewOK })
            XCTAssertTrue(preview.findings.contains { $0.code == .roleVisibilityApplied })
        }
    }

    func testCreditDraftLabelsUseGrowthCreditsNotMinutes() throws {
        let preview = snapshot(role: .guardian)
        let firstCredit = try XCTUnwrap(preview.creditDrafts.first)

        XCTAssertTrue(firstCredit.amountLabel.contains("成长积分"))
        XCTAssertFalse(firstCredit.amountLabel.contains("分钟"))
    }

    func testChildSeesLearningPreviewButNotAdultDrafts() {
        var draft = CreatorManifestPreviewDraft.mock
        draft.contentBlocks[0].containsDirectAnswer = true
        let child = snapshot(role: .child, draft: draft)

        XCTAssertEqual(child.status, .needsWork)
        XCTAssertTrue(child.visibility.canSeeManifest)
        XCTAssertFalse(child.visibility.canSeeCreditDrafts)
        XCTAssertFalse(child.visibility.canSeeLicenseBoundary)
        XCTAssertTrue(child.creditDrafts.isEmpty)
        XCTAssertTrue(child.badgeAbilityDrafts.isEmpty)
        XCTAssertNil(child.licenseBoundary)
        XCTAssertFalse(child.findings.contains { $0.code == .directAnswerBlocked })
        XCTAssertFalse(child.contentBlocks.contains { $0.kind == .schoolHomeworkHook })
        XCTAssertTrue(child.contentBlocks.allSatisfy(\.visibleToChild))
    }

    func testRelativeCannotSeeCreatorManifestDraft() {
        let relative = snapshot(role: .relative)

        XCTAssertEqual(relative.status, .hidden)
        XCTAssertFalse(relative.visibility.canSeeManifest)
        XCTAssertTrue(relative.contentBlocks.isEmpty)
        XCTAssertTrue(relative.proofRequirements.isEmpty)
        XCTAssertEqual(relative.publicSummary.visibleContentCount, 0)
        XCTAssertTrue(relative.findings.contains { $0.code == .nonAuthorPreviewHidden })
    }

    func testDirectAnswerBlocksAdultPreview() {
        var draft = CreatorManifestPreviewDraft.mock
        draft.contentBlocks[1].containsDirectAnswer = true
        let guardian = snapshot(role: .guardian, draft: draft)

        XCTAssertEqual(guardian.status, .blocked)
        XCTAssertTrue(guardian.findings.contains { $0.code == .directAnswerBlocked && $0.severity == .blocker })
        XCTAssertFalse(guardian.publicSummary.issuesCredit)
    }

    func testLicenseAgeCreditAndModerationBlockers() {
        var draft = CreatorManifestPreviewDraft.mock
        draft.licenseBoundary.allowsExternalVideo = false
        draft.ageBand.minAge = 3
        draft.creditDrafts[0].writesLedger = true
        draft.contentBlocks[0].assetModerationPassed = false
        let guardian = snapshot(role: .guardian, draft: draft)

        XCTAssertEqual(guardian.status, .blocked)
        XCTAssertTrue(guardian.findings.contains { $0.code == .licenseBoundaryBlocked })
        XCTAssertTrue(guardian.findings.contains { $0.code == .ageRatingBlocked })
        XCTAssertTrue(guardian.findings.contains { $0.code == .creditSuggestionBlocked })
        XCTAssertTrue(guardian.findings.contains { $0.code == .assetModerationRequired })
        XCTAssertFalse(guardian.creditDrafts.contains { $0.writesLedger || $0.issuesCredit || $0.unlocksDevice })
    }

    func testUnsafePayloadFallsBackToBlockedSnapshot() {
        var draft = CreatorManifestPreviewDraft.mock
        draft.summary = "请打开 local-model-host.local 或 100.100.1.2，再读取 token=abc"
        let blocked = snapshot(role: .guardian, draft: draft)

        XCTAssertEqual(blocked.status, .blocked)
        XCTAssertTrue(blocked.contentBlocks.isEmpty)
        XCTAssertEqual(blocked.findings.first?.code, .publicSummaryLeak)
        XCTAssertTrue(blocked.publicSummary.findingCodes.contains(.publicSummaryLeak))
    }

    func testSnapshotIsStableAndRedacted() {
        let first = snapshot(role: .guardian)
        let second = snapshot(role: .guardian)
        let builder = CreatorManifestPreviewSnapshotBuilder()

        XCTAssertEqual(first, second)
        XCTAssertTrue(builder.redacts(first))
        let text = (
            first.contentBlocks.map(\.publicContentRef)
            + first.proofRequirements.map(\.publicProofRef)
            + first.creditDrafts.map(\.publicCreditRef)
            + first.badgeAbilityDrafts.map(\.publicDraftRef)
            + first.findings.map(\.publicRef)
            + [first.publicSummary.packPublicRef, first.publicSummary.creatorPublicRef]
        ).joined(separator: " ")
        for marker in ["creator:", "child:", "family:", "pack:", "content:", "license:", "homework:", "proof:", "media:", "ledger:", "device:", "task:", "claim:", "192.168.", "file://"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "不应泄露 \(marker)")
        }
    }

    func testPublicSummarySideEffectsAreAlwaysFalse() {
        let summary = snapshot(role: .guardian).publicSummary

        XCTAssertFalse(summary.uploadsMedia)
        XCTAssertFalse(summary.publishesPack)
        XCTAssertFalse(summary.chargesPayment)
        XCTAssertFalse(summary.writesReviewQueue)
        XCTAssertFalse(summary.writesMarketplace)
        XCTAssertFalse(summary.writesLedger)
        XCTAssertFalse(summary.issuesCredit)
        XCTAssertFalse(summary.grantsBadge)
        XCTAssertFalse(summary.mutatesAbilityCard)
        XCTAssertFalse(summary.callsAi)
        XCTAssertFalse(summary.fetchesExternalMedia)
        XCTAssertFalse(summary.unlocksDevice)
    }

    func testChangingSaltChangesPublicRefs() {
        let first = snapshot(role: .guardian, salt: "salt-one")
        let second = snapshot(role: .guardian, salt: "salt-two")

        XCTAssertNotEqual(first.publicSummary.packPublicRef, second.publicSummary.packPublicRef)
        XCTAssertNotEqual(first.contentBlocks.first?.publicContentRef, second.contentBlocks.first?.publicContentRef)
    }
}
