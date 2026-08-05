import XCTest
@testable import OctoTeacher

final class AICompanionSnapshotTests: XCTestCase {
    private let builder = AICompanionSnapshotBuilder()

    private func input(
        mode: AICompanionMode = .nextStep,
        messages: [AICompanionMessage] = []
    ) -> AICompanionInput {
        AICompanionInput(
            childName: "孩子",
            mode: mode,
            nextTaskTitle: "完成英文阅读",
            messages: messages
        )
    }

    func testChildCompanionSuggestsNextStepWithoutSideEffects() {
        let snapshot = builder.build(viewerRole: .child, input: input())

        XCTAssertEqual(snapshot.status, .awaitingChildInput)
        XCTAssertFalse(snapshot.childSteps.isEmpty)
        XCTAssertNil(snapshot.careSummary)
        XCTAssertTrue(snapshot.childSteps.allSatisfy { !$0.givesFinalAnswer })
        XCTAssertFalse(snapshot.publicSummary.callsAiProvider)
        XCTAssertFalse(snapshot.publicSummary.callsNetwork)
        XCTAssertFalse(snapshot.publicSummary.storesRawTranscript)
        XCTAssertFalse(snapshot.publicSummary.givesFinalAnswer)
        XCTAssertFalse(snapshot.publicSummary.sendsNotification)
        XCTAssertFalse(snapshot.publicSummary.writesLedger)
        XCTAssertFalse(snapshot.publicSummary.unlocksDevice)
    }

    func testChildCompanionAlwaysOffersStarterReplies() {
        for mode in AICompanionMode.allCases {
            let snapshot = builder.build(viewerRole: .child, input: input(mode: mode))
            XCTAssertFalse(snapshot.quickReplies.isEmpty, mode.label)
        }

        let risky = builder.build(
            viewerRole: .child,
            input: input(messages: [AICompanionMessage(freeText: "看看这个 file://private/photo.png")])
        )
        XCTAssertFalse(risky.quickReplies.isEmpty)
    }

    func testGuardianSeesOnlyRedactedSummary() {
        let snapshot = builder.build(
            viewerRole: .guardian,
            input: input(messages: [
                AICompanionMessage(freeText: "我今天很难过")
            ])
        )

        XCTAssertTrue(snapshot.childSteps.isEmpty)
        XCTAssertNotNil(snapshot.careSummary)
        XCTAssertNil(snapshot.currentIntentLabel)
        XCTAssertFalse(snapshot.careSummary?.exposesRawTranscript ?? true)
        XCTAssertFalse(snapshot.careSummary?.exposesChildPrivateJournal ?? true)
        XCTAssertFalse(snapshot.careSummary?.exposesModelOrProvider ?? true)
        XCTAssertFalse(String(describing: snapshot).contains("我今天很难过"))
    }

    func testDirectAnswerIsRedirectedNotAnswered() {
        let snapshot = builder.build(
            viewerRole: .child,
            input: input(mode: .homework, messages: [
                AICompanionMessage(freeText: "直接告诉我答案")
            ])
        )

        XCTAssertEqual(snapshot.currentIntentLabel, AICompanionIntent.wantsDirectAnswer.label)
        XCTAssertTrue(snapshot.findings.contains(.directAnswerRedirected))
        XCTAssertTrue(snapshot.childSteps.allSatisfy { !$0.givesFinalAnswer })
        XCTAssertTrue(snapshot.childSteps.contains { $0.detail.contains("不要直接给答案") })
        XCTAssertTrue(snapshot.childSteps.contains { $0.detail.contains("最后答案由你自己写") })
        XCTAssertTrue(snapshot.quickReplies.contains("只给我一个提示，不要给答案。"))
        XCTAssertTrue(snapshot.quickReplies.contains("帮我列检查清单。"))
        XCTAssertFalse(snapshot.publicSummary.givesFinalAnswer)

        XCTAssertEqual(AICompanionMessage(freeText: "只给我一个提示，不要给答案。").intent, .homeworkStuck)
        XCTAssertEqual(AICompanionMessage(freeText: "帮我列检查清单。").intent, .homeworkStuck)
        XCTAssertEqual(AICompanionMessage(freeText: "我先说我的想法。").intent, .homeworkStuck)
    }

    func testHighRiskRoutesToTrustedAdultWithoutRawTranscript() {
        let child = builder.build(
            viewerRole: .child,
            input: input(mode: .emotion, messages: [
                AICompanionMessage(freeText: "我被欺负了，不想活")
            ])
        )
        let guardian = builder.build(
            viewerRole: .guardian,
            input: input(mode: .emotion, messages: [
                AICompanionMessage(freeText: "我被欺负了，不想活")
            ])
        )

        XCTAssertEqual(child.status, .needsTrustedAdult)
        XCTAssertTrue(child.findings.contains(.trustedAdultNeeded))
        XCTAssertEqual(guardian.status, .needsTrustedAdult)
        XCTAssertTrue(guardian.careSummary?.riskLabels.contains(.highRisk) ?? false)
        XCTAssertTrue(guardian.careSummary?.needsGuardianAction ?? false)
        XCTAssertFalse(String(describing: child).contains("不想活"))
        XCTAssertFalse(String(describing: guardian).contains("被欺负"))
    }

    func testFreeTextMessageStoresOnlyIntentAndSafetyFlag() {
        let raw = "不要保存这一句 child:secret-alpha"
        let message = AICompanionMessage(freeText: raw)

        XCTAssertTrue(message.containsUnsafeInput)
        XCTAssertEqual(message.intent, .unclear)
        XCTAssertFalse(String(describing: message).contains(raw))
        XCTAssertFalse(String(describing: message).contains("child:secret-alpha"))
    }

    func testUnclearGuidanceAvoidsDemoWording() {
        let snapshot = builder.build(
            viewerRole: .child,
            input: input(messages: [AICompanionMessage(freeText: "嗯嗯嗯")])
        )

        XCTAssertEqual(snapshot.currentIntentLabel, AICompanionIntent.unclear.label)
        XCTAssertFalse(snapshot.subtitle.contains("示例"))
        XCTAssertTrue(snapshot.subtitle.contains("点一句开始"))
        XCTAssertTrue(snapshot.childSteps.allSatisfy {
            !$0.title.contains("示例") && !$0.detail.contains("示例")
        })
    }

    func testUnsafeInputFallsBackToBlocked() {
        let snapshot = builder.build(
            viewerRole: .guardian,
            input: input(messages: [
                AICompanionMessage(freeText: "看看这个 file://private/photo.png")
            ])
        )

        XCTAssertEqual(snapshot.status, .blocked)
        XCTAssertTrue(snapshot.findings.contains(.unsafeInputBlocked))
        XCTAssertTrue(snapshot.publicSummary.needsGuardianAction)
        XCTAssertTrue(builder.redacts(snapshot))
    }
}
