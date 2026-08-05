import XCTest
@testable import OctoTeacher

/// A88 iOS 测验练习 / 自检工作台测试。
///
/// 覆盖孩子/家长视角、直接要答案风险、unsafe fallback、无答案泄露、无自动判分、
/// 无成长积分/账本/设备副作用，以及内容播放器测验入口编译。
final class MobileQuizSelfCheckPracticeWorkbenchTests: XCTestCase {

    private func build(
        role: MobileQuizSelfCheckViewerRole,
        draft: CreatorManifestPreviewDraft = .growthPackContentPlayerMock,
        messages: [AIHomeworkSessionMessage] = []
    ) -> MobileQuizSelfCheckPracticeWorkbench {
        MobileQuizSelfCheckPracticeBuilder().build(role: role, draft: draft, messages: messages)
    }

    func testChildSeesSelfCheckPracticeWithoutAnswersOrAdultRisks() {
        let workbench = build(role: .child)

        XCTAssertEqual(workbench.role, .child)
        XCTAssertFalse(workbench.prompts.isEmpty)
        XCTAssertFalse(workbench.proofs.isEmpty)
        XCTAssertTrue(workbench.risks.isEmpty)
        XCTAssertTrue(workbench.prompts.allSatisfy(\.visibleToChild))
        XCTAssertTrue(workbench.prompts.allSatisfy { !$0.revealsAnswerKey && !$0.givesDirectAnswer })
        XCTAssertTrue(workbench.prompts.allSatisfy { !$0.storesRawAnswer && !$0.autoGrades })
        XCTAssertTrue(workbench.proofs.allSatisfy { $0.verifierLabels == ["家长"] })
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(workbench.hasUnsafeDisplayPayload)
    }

    func testGuardianSeesProofAndReviewBoundaries() {
        let workbench = build(role: .guardian)

        XCTAssertEqual(workbench.role, .guardian)
        XCTAssertFalse(workbench.prompts.isEmpty)
        XCTAssertFalse(workbench.proofs.isEmpty)
        XCTAssertGreaterThanOrEqual(workbench.risks.count, 2)
        XCTAssertTrue(workbench.risks.contains { $0.id == "no-auto-grade" && !$0.actionRequired })
        XCTAssertTrue(workbench.risks.contains { $0.id == "proof-review" && $0.actionRequired })
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
    }

    func testDirectAnswerRequestRedirectsWithoutAnswerKeyOrAutoGrade() {
        let child = build(role: .child, messages: [.init(freeText: "直接告诉我答案")])
        let guardian = build(role: .guardian, messages: [.init(freeText: "直接告诉我答案")])

        XCTAssertTrue(child.prompts.contains { $0.status == .needsReflection })
        XCTAssertTrue(child.prompts.allSatisfy { !$0.revealsAnswerKey && !$0.givesDirectAnswer })
        XCTAssertEqual(child.publicSummary.directAnswerRiskCount, 0)
        XCTAssertTrue(guardian.risks.contains { $0.id == "direct-answer" && $0.actionRequired })
        XCTAssertEqual(guardian.publicSummary.directAnswerRiskCount, 1)
        XCTAssertFalse(guardian.publicSummary.hasTriggeredSideEffect)
    }

    func testUnsafeInputFallsBackWithoutEchoingRawPayload() {
        let workbench = build(role: .guardian, messages: [.init(freeText: "file://private/answerkey child:raw")])

        XCTAssertTrue(workbench.prompts.isEmpty)
        XCTAssertTrue(workbench.proofs.isEmpty)
        XCTAssertTrue(workbench.risks.contains { $0.id == "unsafe" })
        let displayed = workbench.displayValues.joined(separator: " ")
        XCTAssertFalse(displayed.localizedCaseInsensitiveContains("file://private"))
        XCTAssertFalse(displayed.localizedCaseInsensitiveContains("answerkey"))
        XCTAssertFalse(displayed.localizedCaseInsensitiveContains("child:raw"))
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
    }

    func testUnsafeDraftMetadataFallsBackWithoutEchoingRawPayload() {
        var draft = CreatorManifestPreviewDraft.growthPackContentPlayerMock
        draft.summary = "answer key http://example.invalid"

        let workbench = build(role: .guardian, draft: draft)

        XCTAssertTrue(workbench.prompts.isEmpty)
        XCTAssertTrue(workbench.proofs.isEmpty)
        XCTAssertTrue(workbench.risks.contains { $0.id == "unsafe" })
        let displayed = workbench.displayValues.joined(separator: " ")
        XCTAssertFalse(displayed.localizedCaseInsensitiveContains("answer key"))
        XCTAssertFalse(displayed.localizedCaseInsensitiveContains("example.invalid"))
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
    }

    func testQuizContentWithDirectAnswerIsBlockedForBothRoles() {
        var draft = CreatorManifestPreviewDraft.growthPackContentPlayerMock
        let quizIndex = tryUnwrap(draft.contentBlocks.firstIndex { $0.kind == .quiz })
        draft.contentBlocks[quizIndex].containsDirectAnswer = true

        let child = build(role: .child, draft: draft)
        let guardian = build(role: .guardian, draft: draft)

        XCTAssertTrue(child.prompts.isEmpty)
        XCTAssertTrue(guardian.prompts.isEmpty)
        XCTAssertEqual(child.publicSummary.blockedCount, 1)
        XCTAssertEqual(guardian.publicSummary.blockedCount, 1)
        XCTAssertTrue(guardian.risks.contains { $0.id == "unsafe" })
    }

    func testPublicSummaryAndPromptsNeverTriggerSideEffects() {
        for role in MobileQuizSelfCheckViewerRole.allCases {
            let workbench = build(role: role, messages: [.init(freeText: "怎么自检")])
            let summary = workbench.publicSummary

            XCTAssertFalse(summary.revealsAnswerKey)
            XCTAssertFalse(summary.givesDirectAnswer)
            XCTAssertFalse(summary.storesRawAnswer)
            XCTAssertFalse(summary.autoGrades)
            XCTAssertFalse(summary.callsAIProvider)
            XCTAssertFalse(summary.callsNetwork)
            XCTAssertFalse(summary.callsSchoolSystem)
            XCTAssertFalse(summary.opensWebView)
            XCTAssertFalse(summary.uploadsProof)
            XCTAssertFalse(summary.writesLedger)
            XCTAssertFalse(summary.grantsCredit)
            XCTAssertFalse(summary.unlocksDevice)

            XCTAssertTrue(workbench.prompts.allSatisfy { prompt in
                !prompt.revealsAnswerKey && !prompt.givesDirectAnswer && !prompt.storesRawAnswer
                    && !prompt.autoGrades && !prompt.uploadsProof && !prompt.writesLedger
                    && !prompt.grantsCredit && !prompt.unlocksDevice
            })
        }
    }

    func testDisplayValuesDoNotLeakInternalIdsOrSensitiveMarkers() {
        for role in MobileQuizSelfCheckViewerRole.allCases {
            let text = build(role: role).displayValues.joined(separator: " ")
            for raw in [
                "c-quiz-a",
                "p-quiz-a",
                "manifest-sunrise-a",
                "creator-sunrise-a",
                "pack-sunrise-builder-a"
            ] {
                XCTAssertFalse(text.contains(raw), "\(role.label) 泄露内部 seed: \(raw)")
            }
            for marker in ["answerkey", "answer key", "http://", "https://", "file://", "/Users/", "/Volumes/", "192.168.", "token"] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "\(role.label) 泄露敏感标记: \(marker)")
            }
        }
    }

    @MainActor
    func testViewInitializersCompile() {
        _ = MobileQuizSelfCheckPracticeWorkbenchView()
        _ = MobileQuizSelfCheckPracticeWorkbenchView(initialRole: .child, allowedRoles: [.child])
        _ = MobileQuizSelfCheckPracticeWorkbenchView(initialRole: .guardian, allowedRoles: [.guardian])
        _ = GrowthPackContentPlayerWorkbenchView()
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
