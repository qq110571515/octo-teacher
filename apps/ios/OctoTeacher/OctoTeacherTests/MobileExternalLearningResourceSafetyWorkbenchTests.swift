import XCTest
@testable import OctoTeacher

/// A90 iOS 外部学习资源安全壳测试。
///
/// 覆盖孩子/家长视角、URL/域名/内部 ref 隐藏、白名单/版权/年龄阻断、
/// 外部完成不能直接发成长积分、无外链/WebView/网络/上传/账本/设备副作用，以及内容播放器入口编译。
final class MobileExternalLearningResourceSafetyWorkbenchTests: XCTestCase {

    private func build(
        role: MobileExternalLearningResourceViewerRole,
        draft: CreatorManifestPreviewDraft = .growthPackContentPlayerMock
    ) -> MobileExternalLearningResourceSafetyWorkbench {
        MobileExternalLearningResourceSafetyBuilder().build(role: role, draft: draft)
    }

    func testChildSeesSafeResourceWithoutRawUrlDomainOrAdultFields() {
        let workbench = build(role: .child)

        XCTAssertEqual(workbench.role, .child)
        XCTAssertEqual(workbench.publicSummary.resourceCount, 1)
        XCTAssertEqual(workbench.resources.count, 1)
        XCTAssertEqual(workbench.resources.first?.state, .guardianReview)
        XCTAssertTrue(workbench.proofs.allSatisfy { $0.verifierLabels == ["家长"] })
        XCTAssertTrue(workbench.findings.allSatisfy(\.visibleToChild))
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(workbench.hasUnsafeDisplayPayload)

        let text = workbench.displayValues.joined(separator: " ")
        for marker in ["http://", "https://", "www.", ".com/", ".cn/", "url:", "domain:", "creator:", "content:", "c-video-a", "p-video-a"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "孩子视角泄露敏感标记: \(marker)")
        }
    }

    func testGuardianSeesSourceLicenseAgeProofAndCreditBoundaries() {
        let workbench = build(role: .guardian)
        let resource = tryUnwrap(workbench.resources.first)

        XCTAssertEqual(workbench.role, .guardian)
        XCTAssertTrue(resource.allowlisted)
        XCTAssertTrue(resource.ageAppropriate)
        XCTAssertTrue(resource.licenseActive)
        XCTAssertTrue(resource.guardianReviewRequired)
        XCTAssertTrue(resource.creditRequiresGuardianApproval)
        XCTAssertFalse(resource.directCreditBlocked)
        XCTAssertTrue(resource.creditBoundaryLabel.contains("成长积分需家长"))
        XCTAssertTrue(workbench.findings.contains { $0.code == .readOnlyReady && !$0.actionRequired })
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
    }

    func testNonAllowlistedOrLicenseBlockedResourceIsHiddenFromChildAndVisibleToGuardianAsBlocked() {
        var draft = CreatorManifestPreviewDraft.growthPackContentPlayerMock
        draft.licenseBoundary.allowsExternalVideo = false

        let child = build(role: .child, draft: draft)
        let guardian = build(role: .guardian, draft: draft)

        XCTAssertTrue(child.resources.isEmpty)
        XCTAssertTrue(child.proofs.isEmpty)
        XCTAssertEqual(child.publicSummary.blockedResourceCount, 1)
        XCTAssertTrue(guardian.resources.contains { $0.state == .blocked && !$0.licenseActive })
        XCTAssertTrue(guardian.findings.contains { $0.code == .allowlistBlocked && $0.actionRequired })
        XCTAssertFalse(guardian.publicSummary.hasTriggeredSideEffect)
    }

    func testAgeMismatchBlocksExternalResource() {
        var draft = CreatorManifestPreviewDraft.growthPackContentPlayerMock
        draft.ageBand = CreatorManifestAgeBandDraft(
            minAge: 3,
            maxAge: 5,
            gradeBand: "幼儿园",
            requiresGuardianConsent: true
        )

        let guardian = build(role: .guardian, draft: draft)

        XCTAssertTrue(guardian.resources.contains { $0.state == .blocked && !$0.ageAppropriate })
        XCTAssertTrue(guardian.findings.contains { $0.code == .ageMismatchBlocked && $0.actionRequired })
        XCTAssertEqual(guardian.publicSummary.blockedResourceCount, 1)
        XCTAssertFalse(guardian.publicSummary.hasTriggeredSideEffect)
    }

    func testExternalCompletionCannotGrantCreditOrWriteLedgerDirectly() {
        var draft = CreatorManifestPreviewDraft.growthPackContentPlayerMock
        draft.creditDrafts.append(
            CreatorManifestCreditDraft(
                creditId: "credit-video-direct",
                triggerContentId: "c-video-a",
                amount: 30,
                scopeLabel: "screen_time",
                reason: "外部视频完成后直接奖励。",
                requiresGuardianApproval: false,
                writesLedger: true
            )
        )

        let child = build(role: .child, draft: draft)
        let guardian = build(role: .guardian, draft: draft)

        XCTAssertTrue(child.resources.isEmpty)
        XCTAssertTrue(guardian.resources.contains { $0.directCreditBlocked && $0.state == .blocked })
        XCTAssertEqual(guardian.publicSummary.directCreditBlockedCount, 1)
        XCTAssertTrue(guardian.findings.contains { $0.code == .creditBoundaryBlocked && $0.actionRequired })
        XCTAssertFalse(guardian.publicSummary.grantsCredit)
        XCTAssertFalse(guardian.publicSummary.writesLedger)
        XCTAssertFalse(guardian.publicSummary.unlocksDevice)
    }

    func testUnsafePayloadFallsBackWithoutEchoingRawUrlOrInternalRefs() {
        var draft = CreatorManifestPreviewDraft.growthPackContentPlayerMock
        let videoIndex = tryUnwrap(draft.contentBlocks.firstIndex { $0.kind == .externalVideo })
        draft.contentBlocks[videoIndex].summary = "https://example.invalid/watch?child=raw resource:private"

        let workbench = build(role: .guardian, draft: draft)

        XCTAssertTrue(workbench.resources.isEmpty)
        XCTAssertTrue(workbench.proofs.isEmpty)
        XCTAssertEqual(workbench.publicSummary.findingCodes, [.unsafePayloadBlocked])
        let text = workbench.displayValues.joined(separator: " ")
        XCTAssertFalse(text.localizedCaseInsensitiveContains("example.invalid"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("resource:private"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("https://"))
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
    }

    func testPublicSummaryAndRowsNeverTriggerExternalActions() {
        for role in MobileExternalLearningResourceViewerRole.allCases {
            let workbench = build(role: role)
            let summary = workbench.publicSummary

            XCTAssertFalse(summary.showsRawURL)
            XCTAssertFalse(summary.showsDomain)
            XCTAssertFalse(summary.opensExternalURL)
            XCTAssertFalse(summary.opensWebView)
            XCTAssertFalse(summary.opensBrowser)
            XCTAssertFalse(summary.downloadsMedia)
            XCTAssertFalse(summary.callsNetwork)
            XCTAssertFalse(summary.callsAIProvider)
            XCTAssertFalse(summary.uploadsProof)
            XCTAssertFalse(summary.writesLedger)
            XCTAssertFalse(summary.grantsCredit)
            XCTAssertFalse(summary.unlocksDevice)
            XCTAssertFalse(summary.writesMarketplace)

            XCTAssertTrue(workbench.resources.allSatisfy { resource in
                !resource.showsRawURL && !resource.showsDomain && !resource.opensExternalURL
                    && !resource.opensWebView && !resource.opensBrowser && !resource.downloadsMedia
                    && !resource.callsNetwork && !resource.uploadsProof && !resource.writesLedger
                    && !resource.grantsCredit && !resource.unlocksDevice && !resource.writesMarketplace
            })
        }
    }

    func testDisplayValuesDoNotLeakInternalIdsOrSensitiveMarkers() {
        for role in MobileExternalLearningResourceViewerRole.allCases {
            let text = build(role: role).displayValues.joined(separator: " ")
            for raw in [
                "c-video-a",
                "p-video-a",
                "manifest-sunrise-a",
                "creator-sunrise-a",
                "pack-sunrise-builder-a",
                "license-sunrise-a"
            ] {
                XCTAssertFalse(text.contains(raw), "\(role.label) 泄露内部 seed: \(raw)")
            }
            for marker in ["http://", "https://", "file://", "/Users/", "/Volumes/", "192.168.", "token", "url:", "domain:"] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "\(role.label) 泄露敏感标记: \(marker)")
            }
        }
    }

    @MainActor
    func testViewInitializersAndContentPlayerEntryCompile() {
        _ = MobileExternalLearningResourceSafetyWorkbenchView()
        _ = MobileExternalLearningResourceSafetyWorkbenchView(initialRole: .child, allowedRoles: [.child])
        _ = MobileExternalLearningResourceSafetyWorkbenchView(initialRole: .guardian, allowedRoles: [.guardian])
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
