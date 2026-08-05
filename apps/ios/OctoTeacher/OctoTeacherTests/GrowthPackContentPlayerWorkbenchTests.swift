import XCTest
@testable import OctoTeacher

/// A87 成长包内容播放器 / 证明工作台测试。
///
/// 覆盖文本、图片观察、外部视频引用、测验练习、通关截图证明、孩子/家长裁剪、
/// 以及所有外链、媒体、上传、判分、成长积分、设备和学校系统副作用恒为 false。
final class GrowthPackContentPlayerWorkbenchTests: XCTestCase {

    private func build(
        role: GrowthPackContentPlayerViewerRole,
        draft: CreatorManifestPreviewDraft = .growthPackContentPlayerMock
    ) -> GrowthPackContentPlayerWorkbench {
        GrowthPackContentPlayerWorkbenchBuilder().build(role: role, draft: draft)
    }

    func testChildSeesPlayableContentButNoSchoolHookOrAdultRisk() {
        let workbench = build(role: .child)

        XCTAssertEqual(workbench.role, .child)
        XCTAssertTrue(workbench.items.contains { $0.mode == .textLesson })
        XCTAssertTrue(workbench.items.contains { $0.mode == .imagePlaceholder })
        XCTAssertTrue(workbench.items.contains { $0.mode == .externalVideoReference })
        XCTAssertTrue(workbench.items.contains { $0.mode == .quizPractice })
        XCTAssertTrue(workbench.items.contains { $0.mode == .screenshotProof })
        XCTAssertFalse(workbench.items.contains { $0.mode == .schoolHook })
        XCTAssertTrue(workbench.risks.isEmpty)
        XCTAssertTrue(workbench.items.allSatisfy(\.visibleToChild))
        XCTAssertTrue(workbench.proofs.allSatisfy(\.visibleToChild))
        XCTAssertTrue(workbench.proofs.allSatisfy { $0.verifierLabels == ["家长"] })
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(workbench.hasUnsafeDisplayPayload)
    }

    func testGuardianSeesRisksHiddenContentAndReviewCounts() {
        let workbench = build(role: .guardian)

        XCTAssertEqual(workbench.role, .guardian)
        XCTAssertTrue(workbench.items.contains { $0.mode == .schoolHook })
        XCTAssertGreaterThan(workbench.publicSummary.hiddenItemCount, 0)
        XCTAssertGreaterThan(workbench.publicSummary.guardianReviewCount, 0)
        XCTAssertGreaterThan(workbench.risks.count, 0)
        XCTAssertTrue(workbench.risks.contains { $0.id == "external-video" && $0.actionRequired })
        XCTAssertTrue(workbench.risks.contains { $0.id == "asset" && $0.actionRequired })
        XCTAssertTrue(workbench.risks.contains { $0.id == "screenshot" && $0.actionRequired })
        XCTAssertTrue(workbench.items.contains { $0.guardianReviewRequired })
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
    }

    func testExternalVideoImageQuizAndScreenshotRemainSafeReadOnlyPreviews() {
        let workbench = build(role: .child)
        let video = tryUnwrap(workbench.items.first { $0.mode == .externalVideoReference })
        let image = tryUnwrap(workbench.items.first { $0.mode == .imagePlaceholder })
        let quiz = tryUnwrap(workbench.items.first { $0.mode == .quizPractice })
        let screenshot = tryUnwrap(workbench.items.first { $0.mode == .screenshotProof })

        XCTAssertFalse(video.opensExternalURL)
        XCTAssertFalse(video.opensWebView)
        XCTAssertFalse(video.downloadsMedia)
        XCTAssertTrue(video.safetyNote.contains("不打开外链"))
        XCTAssertFalse(image.downloadsMedia)
        XCTAssertTrue(image.safetyNote.contains("不下载"))
        XCTAssertFalse(quiz.autoGradesQuiz)
        XCTAssertTrue(quiz.safetyNote.contains("不自动判分"))
        XCTAssertFalse(screenshot.opensPhotoLibrary)
        XCTAssertFalse(screenshot.opensFilePicker)
        XCTAssertFalse(screenshot.uploadsProof)
        XCTAssertTrue(screenshot.safetyNote.contains("不打开相册"))
    }

    func testPublicSummaryAndItemsNeverTriggerExternalActions() {
        for role in GrowthPackContentPlayerViewerRole.allCases {
            let workbench = build(role: role)
            let summary = workbench.publicSummary

            XCTAssertFalse(summary.opensExternalURL)
            XCTAssertFalse(summary.opensWebView)
            XCTAssertFalse(summary.downloadsMedia)
            XCTAssertFalse(summary.opensCamera)
            XCTAssertFalse(summary.opensPhotoLibrary)
            XCTAssertFalse(summary.opensFilePicker)
            XCTAssertFalse(summary.uploadsMedia)
            XCTAssertFalse(summary.uploadsProof)
            XCTAssertFalse(summary.autoGradesQuiz)
            XCTAssertFalse(summary.callsNetwork)
            XCTAssertFalse(summary.callsAIProvider)
            XCTAssertFalse(summary.writesLedger)
            XCTAssertFalse(summary.grantsCredit)
            XCTAssertFalse(summary.unlocksDevice)
            XCTAssertFalse(summary.writesSchoolSystem)

            XCTAssertTrue(workbench.items.allSatisfy { item in
                !item.opensExternalURL && !item.opensWebView && !item.downloadsMedia
                    && !item.opensCamera && !item.opensPhotoLibrary && !item.opensFilePicker
                    && !item.uploadsProof && !item.autoGradesQuiz && !item.writesLedger
                    && !item.grantsCredit && !item.unlocksDevice
            })
        }
    }

    func testUnsafeDraftFallsBackWithoutEchoingRawPayload() {
        var draft = CreatorManifestPreviewDraft.growthPackContentPlayerMock
        draft.contentBlocks[0].summary = "http://example.invalid child:raw-ref"

        let workbench = build(role: .guardian, draft: draft)

        XCTAssertTrue(workbench.items.isEmpty)
        XCTAssertTrue(workbench.proofs.isEmpty)
        XCTAssertEqual(workbench.publicSummary.visibleItemCount, 0)
        XCTAssertEqual(workbench.publicSummary.hiddenItemCount, draft.contentBlocks.count)
        XCTAssertTrue(workbench.risks.contains { $0.id == "unsafe" })
        XCTAssertFalse(workbench.displayValues.joined(separator: " ").contains("example.invalid"))
        XCTAssertFalse(workbench.displayValues.joined(separator: " ").contains("child:raw-ref"))
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
    }

    func testBlockedContentDoesNotEnterChildLearningSurface() {
        var draft = CreatorManifestPreviewDraft.growthPackContentPlayerMock
        draft.contentBlocks[0].containsDirectAnswer = true

        let child = build(role: .child, draft: draft)
        let guardian = build(role: .guardian, draft: draft)

        XCTAssertTrue(child.items.isEmpty)
        XCTAssertTrue(guardian.items.isEmpty)
        XCTAssertTrue(guardian.risks.contains { $0.id == "unsafe" })
        XCTAssertFalse(guardian.publicSummary.hasTriggeredSideEffect)
    }

    func testDisplayValuesDoNotLeakInternalIdsOrSensitiveMarkers() {
        for role in GrowthPackContentPlayerViewerRole.allCases {
            let text = build(role: role).displayValues.joined(separator: " ")
            for raw in [
                "c-video-a",
                "c-game-proof-a",
                "p-game-proof-a",
                "manifest-sunrise-a",
                "creator-sunrise-a",
                "pack-sunrise-builder-a"
            ] {
                XCTAssertFalse(text.contains(raw), "\(role.label) 泄露内部 seed: \(raw)")
            }
            for marker in ["http://", "https://", "file://", "/Users/", "/Volumes/", "192.168.", "Bearer "] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "\(role.label) 泄露敏感标记: \(marker)")
            }
        }
    }

    @MainActor
    func testViewInitializersCompile() {
        _ = GrowthPackContentPlayerWorkbenchView()
        _ = GrowthPackContentPlayerWorkbenchView(initialRole: .child, allowedRoles: [.child])
        _ = GrowthPackContentPlayerWorkbenchView(initialRole: .guardian, allowedRoles: [.guardian])
        _ = GrowthPackMobileDetailView()
    }

    private func tryUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) -> T {
        guard let value else {
            XCTFail("Expected value", file: file, line: line)
            fatalError("Expected value")
        }
        return value
    }
}
