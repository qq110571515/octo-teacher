import XCTest
@testable import OctoTeacher

/// A91 iOS 孩子创作作品展示安全壳测试。
///
/// 覆盖孩子/家长/亲友视角、私密和撤回保护、亲友奖励压力阻断、创作完成不能直发成长积分、
/// 无上传/发布/评论/通知/账本/设备副作用，以及内容播放器入口编译。
final class MobileCreativeShowcaseSafetyWorkbenchTests: XCTestCase {

    private func build(
        role: MobileCreativeShowcaseViewerRole,
        draft: CreatorManifestPreviewDraft = .growthPackContentPlayerMock,
        childAssentGranted: Bool = true,
        guardianApproved: Bool = true,
        moderationPassed: Bool = true,
        privateByChild: Bool = false,
        withdrawn: Bool = false,
        relativeRewardPromise: Bool = false
    ) -> MobileCreativeShowcaseSafetyWorkbench {
        MobileCreativeShowcaseSafetyBuilder().build(
            role: role,
            draft: draft,
            childAssentGranted: childAssentGranted,
            guardianApproved: guardianApproved,
            moderationPassed: moderationPassed,
            privateByChild: privateByChild,
            withdrawn: withdrawn,
            relativeRewardPromise: relativeRewardPromise
        )
    }

    func testChildSeesCreativeSelfCheckWithoutUploadOrRewardPressure() {
        let workbench = build(role: .child)
        let showcase = tryUnwrap(workbench.showcases.first)

        XCTAssertEqual(workbench.role, .child)
        XCTAssertEqual(workbench.publicSummary.showcaseCount, 1)
        XCTAssertEqual(workbench.publicSummary.visibleShowcaseCount, 1)
        XCTAssertEqual(showcase.state, .approvedPreview)
        XCTAssertTrue(showcase.visibleToChild)
        XCTAssertFalse(showcase.uploadsMedia)
        XCTAssertFalse(showcase.publishesShowcase)
        XCTAssertFalse(showcase.grantsCredit)
        XCTAssertFalse(showcase.unlocksDevice)
        XCTAssertTrue(workbench.proofs.allSatisfy { $0.verifierLabels == ["家长"] })
        XCTAssertTrue(workbench.findings.allSatisfy(\.visibleToChild))
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(workbench.hasUnsafeDisplayPayload)

        let text = workbench.displayValues.joined(separator: " ")
        XCTAssertFalse(text.contains("20"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("relative reward"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("credit amount"))
    }

    func testGuardianSeesReviewProofVisibilityAndCreditBoundary() {
        let workbench = build(role: .guardian)
        let showcase = tryUnwrap(workbench.showcases.first)

        XCTAssertEqual(workbench.role, .guardian)
        XCTAssertEqual(showcase.state, .approvedPreview)
        XCTAssertTrue(showcase.visibleToGuardian)
        XCTAssertTrue(showcase.visibleToRelative)
        XCTAssertTrue(showcase.childAssentGranted)
        XCTAssertTrue(showcase.guardianApproved)
        XCTAssertTrue(showcase.moderationPassed)
        XCTAssertFalse(showcase.privateByChild)
        XCTAssertFalse(showcase.directCreditBlocked)
        XCTAssertTrue(showcase.creditBoundaryLabel.contains("正式流程"))
        XCTAssertTrue(workbench.proofs.contains { $0.verifierLabels.contains("家长") })
        XCTAssertTrue(workbench.findings.contains { $0.code == .readOnlyReady && !$0.actionRequired })
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
    }

    func testRelativeOnlySeesApprovedNonPrivateSummary() {
        let workbench = build(role: .relative)
        let showcase = tryUnwrap(workbench.showcases.first)

        XCTAssertEqual(workbench.role, .relative)
        XCTAssertEqual(workbench.publicSummary.visibleShowcaseCount, 1)
        XCTAssertEqual(showcase.state, .approvedPreview)
        XCTAssertTrue(showcase.visibleToRelative)
        XCTAssertTrue(workbench.findings.allSatisfy(\.visibleToRelative))
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)

        let text = workbench.displayValues.joined(separator: " ")
        XCTAssertFalse(text.localizedCaseInsensitiveContains("上传"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("解锁"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("账本"))
    }

    func testPrivatePendingWithdrawnOrNoAssentAreHiddenFromRelatives() {
        let privateWorkbench = build(role: .relative, privateByChild: true)
        let pendingWorkbench = build(role: .relative, guardianApproved: false)
        let withdrawnWorkbench = build(role: .relative, withdrawn: true)
        let noAssentWorkbench = build(role: .relative, childAssentGranted: false)
        let moderationWorkbench = build(role: .relative, moderationPassed: false)

        for workbench in [privateWorkbench, pendingWorkbench, withdrawnWorkbench, noAssentWorkbench, moderationWorkbench] {
            XCTAssertTrue(workbench.showcases.isEmpty)
            XCTAssertEqual(workbench.publicSummary.visibleShowcaseCount, 0)
            XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
        }

        let guardian = build(role: .guardian, privateByChild: true)
        XCTAssertTrue(guardian.findings.contains { $0.code == .privacyVisibilityBlocked && $0.actionRequired })
        XCTAssertEqual(guardian.publicSummary.hiddenFromRelativeCount, 1)
    }

    func testRelativeRewardPromiseBlocksShowcase() {
        let relative = build(role: .relative, relativeRewardPromise: true)
        let guardian = build(role: .guardian, relativeRewardPromise: true)

        XCTAssertTrue(relative.showcases.isEmpty)
        XCTAssertEqual(relative.publicSummary.blockedCount, 1)
        XCTAssertTrue(guardian.showcases.contains { $0.rewardPressureBlocked && $0.state == .blocked })
        XCTAssertTrue(guardian.findings.contains { $0.code == .rewardPressureBlocked && $0.actionRequired })
        XCTAssertFalse(guardian.publicSummary.hasTriggeredSideEffect)
    }

    func testCreativeCompletionCannotDirectlyGrantCreditWriteLedgerOrUnlockDevice() {
        var draft = CreatorManifestPreviewDraft.growthPackContentPlayerMock
        draft.creditDrafts.append(
            CreatorManifestCreditDraft(
                creditId: "credit-upload-direct",
                triggerContentId: "c-upload-a",
                amount: 20,
                scopeLabel: "creative_bonus",
                reason: "完成创作后直接发成长积分。",
                requiresGuardianApproval: false,
                writesLedger: true
            )
        )

        let child = build(role: .child, draft: draft)
        let guardian = build(role: .guardian, draft: draft)

        XCTAssertTrue(child.showcases.isEmpty)
        XCTAssertTrue(guardian.showcases.contains { $0.directCreditBlocked && $0.state == .blocked })
        XCTAssertEqual(guardian.publicSummary.directCreditBlockedCount, 1)
        XCTAssertTrue(guardian.findings.contains { $0.code == .creditBoundaryBlocked && $0.actionRequired })
        XCTAssertFalse(guardian.publicSummary.grantsCredit)
        XCTAssertFalse(guardian.publicSummary.writesLedger)
        XCTAssertFalse(guardian.publicSummary.unlocksDevice)
    }

    func testUnsafePayloadFallsBackWithoutEchoingRawMediaOrInternalRefs() {
        var draft = CreatorManifestPreviewDraft.growthPackContentPlayerMock
        let uploadIndex = tryUnwrap(draft.contentBlocks.firstIndex { $0.kind == .creatorUpload })
        draft.contentBlocks[uploadIndex].summary = "http://example.invalid/art child:raw media:private"

        let workbench = build(role: .guardian, draft: draft)

        XCTAssertTrue(workbench.showcases.isEmpty)
        XCTAssertTrue(workbench.proofs.isEmpty)
        XCTAssertEqual(workbench.publicSummary.findingCodes, [.unsafePayloadBlocked])
        let text = workbench.displayValues.joined(separator: " ")
        XCTAssertFalse(text.localizedCaseInsensitiveContains("example.invalid"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("child:raw"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("media:private"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("http://"))
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
    }

    func testNonCredentialCreativeWordsDoNotTriggerFallback() {
        var draft = CreatorManifestPreviewDraft.growthPackContentPlayerMock
        let uploadIndex = tryUnwrap(draft.contentBlocks.firstIndex { $0.kind == .creatorUpload })
        draft.contentBlocks[uploadIndex].summary = "用 token bucket 和 secret base 比喻创作节奏。"

        let workbench = build(role: .guardian, draft: draft)

        XCTAssertEqual(workbench.publicSummary.showcaseCount, 1)
        XCTAssertFalse(workbench.showcases.isEmpty)
        XCTAssertFalse(workbench.publicSummary.findingCodes.contains(.unsafePayloadBlocked))
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
    }

    func testPublicSummaryRowsAndProofsNeverTriggerSideEffects() {
        for role in MobileCreativeShowcaseViewerRole.allCases {
            let workbench = build(role: role)
            let summary = workbench.publicSummary

            XCTAssertFalse(summary.opensCamera)
            XCTAssertFalse(summary.opensPhotoLibrary)
            XCTAssertFalse(summary.opensFilePicker)
            XCTAssertFalse(summary.uploadsMedia)
            XCTAssertFalse(summary.publishesShowcase)
            XCTAssertFalse(summary.approvesComment)
            XCTAssertFalse(summary.sendsComment)
            XCTAssertFalse(summary.sendsNotification)
            XCTAssertFalse(summary.callsNetwork)
            XCTAssertFalse(summary.writesLedger)
            XCTAssertFalse(summary.grantsCredit)
            XCTAssertFalse(summary.unlocksDevice)
            XCTAssertFalse(summary.writesSocialPlatform)
            XCTAssertFalse(summary.hasTriggeredSideEffect)

            XCTAssertTrue(workbench.showcases.allSatisfy { showcase in
                !showcase.opensCamera && !showcase.opensPhotoLibrary && !showcase.opensFilePicker
                    && !showcase.uploadsMedia && !showcase.publishesShowcase && !showcase.approvesComment
                    && !showcase.sendsComment && !showcase.sendsNotification && !showcase.callsNetwork
                    && !showcase.writesLedger && !showcase.grantsCredit && !showcase.unlocksDevice
                    && !showcase.writesSocialPlatform
            })
            XCTAssertTrue(workbench.proofs.allSatisfy { proof in
                !proof.opensFilePicker && !proof.uploadsMedia && !proof.writesLedger && !proof.grantsCredit
            })
        }
    }

    func testDisplayValuesDoNotLeakInternalIdsOrSensitiveMarkers() {
        for role in MobileCreativeShowcaseViewerRole.allCases {
            let text = build(role: role).displayValues.joined(separator: " ")
            for raw in [
                "c-upload-a",
                "p-upload-a",
                "creator-sunrise-a",
                "pack-sunrise-builder-a",
                "manifest-sunrise-a",
                "license-sunrise-a"
            ] {
                XCTAssertFalse(text.contains(raw), "\(role.label) 泄露内部 seed: \(raw)")
            }
            for marker in ["http://", "https://", "file://", "/Users/", "/Volumes/", "192.168.", "token", "media:", "proof:", "credit:"] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "\(role.label) 泄露敏感标记: \(marker)")
            }
        }
    }

    @MainActor
    func testViewInitializersAndContentPlayerEntryCompile() {
        _ = MobileCreativeShowcaseSafetyWorkbenchView()
        _ = MobileCreativeShowcaseSafetyWorkbenchView(initialRole: .child, allowedRoles: [.child])
        _ = MobileCreativeShowcaseSafetyWorkbenchView(initialRole: .guardian, allowedRoles: [.guardian])
        _ = MobileCreativeShowcaseSafetyWorkbenchView(initialRole: .relative, allowedRoles: [.relative])
        _ = GrowthPackContentPlayerWorkbenchView()
    }

    private func tryUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) -> T {
        guard let value else {
            XCTFail("Expected value", file: file, line: line)
            fatalError("Expected value")
        }
        return value
    }
}
