import XCTest
@testable import OctoTeacher

final class AICompanionPrivacyGatewayTests: XCTestCase {
    private let builder = AICompanionSnapshotBuilder()
    private let gateway = AICompanionPrivacyGateway()

    private func input(
        childName: String = "乐乐",
        mode: AICompanionMode = .nextStep,
        nextTaskTitle: String? = "完成英文阅读",
        messages: [AICompanionMessage]
    ) -> AICompanionInput {
        AICompanionInput(
            childName: childName,
            mode: mode,
            nextTaskTitle: nextTaskTitle,
            messages: messages
        )
    }

    private func guardianSnapshot(_ input: AICompanionInput) -> AICompanionSnapshot {
        builder.build(viewerRole: .guardian, input: input)
    }

    func testDraftContainsOnlyIntentAndPolicyNotRawChildTextOrName() {
        let rawText = "我今天很难过，想让乐乐这个名字别出现"
        let requestInput = input(
            childName: "乐乐",
            mode: .emotion,
            messages: [AICompanionMessage(freeText: rawText)]
        )

        let draft = gateway.makeDraft(input: requestInput, snapshot: guardianSnapshot(requestInput))
        let rendered = draft.systemPrompt + "\n" + draft.userPrompt

        XCTAssertTrue(draft.isProviderRequestAllowed)
        XCTAssertTrue(draft.publicSummary.wouldCallAiProvider)
        XCTAssertFalse(draft.publicSummary.callsNetwork)
        XCTAssertFalse(draft.publicSummary.storesRawTranscript)
        XCTAssertFalse(draft.publicSummary.includesChildName)
        XCTAssertFalse(draft.publicSummary.includesApiKey)
        XCTAssertFalse(draft.publicSummary.givesFinalAnswer)
        XCTAssertFalse(rendered.contains(rawText))
        XCTAssertFalse(rendered.contains("乐乐"))
        XCTAssertFalse(rendered.contains("完成英文阅读"))
        XCTAssertFalse(rendered.localizedCaseInsensitiveContains("transcript"))
    }

    func testDirectAnswerRequestIsAllowedOnlyAsSocraticGuidance() {
        let requestInput = input(
            mode: .homework,
            messages: [AICompanionMessage(freeText: "直接告诉我答案")]
        )

        let draft = gateway.makeDraft(input: requestInput, snapshot: guardianSnapshot(requestInput))
        let rendered = draft.systemPrompt + "\n" + draft.userPrompt

        XCTAssertTrue(draft.isProviderRequestAllowed)
        XCTAssertTrue(draft.riskLabels.contains(.directAnswer))
        XCTAssertTrue(draft.publicSummary.findingCodes.contains(.directAnswerRedirected))
        XCTAssertTrue(rendered.contains("never provide final homework answers"))
        XCTAssertTrue(rendered.contains("Do not solve the work"))
        XCTAssertFalse(rendered.contains("直接告诉我答案"))
    }

    func testHighRiskIsBlockedBeforeProvider() {
        let requestInput = input(
            mode: .emotion,
            messages: [AICompanionMessage(freeText: "我被欺负了，不想活")]
        )

        let draft = gateway.makeDraft(input: requestInput, snapshot: guardianSnapshot(requestInput))

        XCTAssertFalse(draft.isProviderRequestAllowed)
        XCTAssertTrue(draft.publicSummary.blockedBeforeProvider)
        XCTAssertFalse(draft.publicSummary.wouldCallAiProvider)
        XCTAssertEqual(draft.systemPrompt, "")
        XCTAssertEqual(draft.userPrompt, "")
        XCTAssertTrue(draft.riskLabels.contains(.highRisk))
        XCTAssertTrue(draft.publicSummary.findingCodes.contains(.trustedAdultNeeded))
        XCTAssertTrue(draft.blockReason?.contains("可信大人") ?? false)
    }

    func testHighRiskEarlierInConversationBlocksEvenWhenLatestLooksNormal() {
        let requestInput = input(
            mode: .homework,
            messages: [
                AICompanionMessage(freeText: "我不想活"),
                AICompanionMessage(freeText: "我现在只是作业不会")
            ]
        )

        let draft = gateway.makeDraft(input: requestInput, snapshot: guardianSnapshot(requestInput))

        XCTAssertFalse(draft.isProviderRequestAllowed)
        XCTAssertTrue(draft.riskLabels.contains(.highRisk))
        XCTAssertTrue(draft.publicSummary.findingCodes.contains(.trustedAdultNeeded))
        XCTAssertTrue(draft.blockReason?.contains("可信大人") ?? false)
    }

    func testTrustedAdultRequestUsesAdultInterventionBlockReason() {
        let requestInput = input(
            messages: [AICompanionMessage(freeText: "我想找妈妈帮忙")]
        )

        let draft = gateway.makeDraft(input: requestInput, snapshot: guardianSnapshot(requestInput))

        XCTAssertFalse(draft.isProviderRequestAllowed)
        XCTAssertTrue(draft.blockReason?.contains("可信大人") ?? false)
    }

    func testCommonEnglishNameDoesNotTriggerFalsePrivacyBlock() {
        let requestInput = input(
            childName: "Chinese",
            mode: .emotion,
            messages: [AICompanionMessage(freeText: "我今天很难过")]
        )

        let draft = gateway.makeDraft(input: requestInput, snapshot: guardianSnapshot(requestInput))
        let rendered = draft.systemPrompt + "\n" + draft.userPrompt

        XCTAssertTrue(draft.isProviderRequestAllowed)
        XCTAssertFalse(rendered.contains("Chinese"))
    }

    func testUnsafeInputWithSecretOrURLIsBlockedBeforeProvider() {
        let requestInput = input(
            messages: [
                AICompanionMessage(freeText: "帮我看看 api_key sk-test-secret 和 https://school.example.com")
            ]
        )

        let draft = gateway.makeDraft(input: requestInput, snapshot: guardianSnapshot(requestInput))

        XCTAssertFalse(draft.isProviderRequestAllowed)
        XCTAssertTrue(draft.publicSummary.blockedBeforeProvider)
        XCTAssertEqual(draft.systemPrompt, "")
        XCTAssertEqual(draft.userPrompt, "")
        XCTAssertTrue(draft.publicSummary.findingCodes.contains(.redactionFallback))
    }
}
