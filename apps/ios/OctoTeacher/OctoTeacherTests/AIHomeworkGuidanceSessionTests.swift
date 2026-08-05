import XCTest
@testable import OctoTeacher

final class AIHomeworkGuidanceSessionTests: XCTestCase {

    private func mathHomework() -> SchoolHomework {
        // 本地 fixture 的数学作业带 3 条提示 + 3 条自检 + 下一步，意图覆盖最全。
        SchoolFamilyStore().homeworks.first { $0.subject == .math }!
    }

    private func build(
        role: AIHomeworkSessionViewerRole,
        homework: SchoolHomework? = nil,
        messages: [AIHomeworkSessionMessage] = [],
        salt: String = "ai-homework-guidance-session-ios-v1"
    ) -> AIHomeworkGuidanceSessionSnapshot {
        AIHomeworkGuidanceSessionBuilder(redactionSalt: salt).build(
            viewerRole: role,
            homework: homework ?? mathHomework(),
            messages: messages
        )
    }

    // MARK: - 角色可见性

    func testChildSeesGuidanceButNoCareSummary() {
        let child = build(role: .child, messages: [.init(preset: .whereToStart)])

        XCTAssertTrue(child.visibility.canSeeSteps)
        XCTAssertFalse(child.visibility.canSeeCareSummary)
        XCTAssertFalse(child.visibility.canSeeRiskLabels)
        XCTAssertFalse(child.steps.isEmpty)
        XCTAssertFalse(child.followUps.isEmpty)
        XCTAssertFalse(child.checklist.isEmpty)
        XCTAssertNil(child.careSummary)
        XCTAssertTrue(child.steps.allSatisfy { !$0.revealsAnswer })
        XCTAssertFalse(child.assurance.isEmpty)
    }

    func testCareRolesSeeSummaryButNoSteps() {
        for role in [AIHomeworkSessionViewerRole.guardian, .teacher] {
            let care = build(role: role, messages: [.init(preset: .whereToStart)])

            XCTAssertFalse(care.visibility.canSeeSteps)
            XCTAssertTrue(care.visibility.canSeeCareSummary)
            XCTAssertTrue(care.steps.isEmpty)
            XCTAssertTrue(care.followUps.isEmpty)
            XCTAssertTrue(care.checklist.isEmpty)
            XCTAssertNil(care.currentIntentLabel)
            XCTAssertNotNil(care.careSummary)
            XCTAssertFalse(care.careSummary?.exposesChildAnswer ?? true)
            XCTAssertFalse(care.careSummary?.exposesRawTranscript ?? true)
            XCTAssertFalse(care.careSummary?.exposesInternalRiskScore ?? true)
        }
    }

    // MARK: - 苏格拉底式步骤 / 不给答案

    func testWantsDirectAnswerIsRedirectedNotAnswered() {
        let child = build(role: .child, messages: [.init(freeText: "你直接告诉我答案")])

        XCTAssertEqual(child.currentIntentLabel, AIHomeworkQuestionIntent.wantsDirectAnswer.label)
        XCTAssertFalse(child.steps.isEmpty)
        XCTAssertTrue(child.steps.allSatisfy { !$0.revealsAnswer })
        // 孩子端看不到风险发现项，只看到引导态。
        XCTAssertFalse(child.findings.contains { $0.code == .directAnswerRedirected })
        XCTAssertNotEqual(child.header.status, .needsHumanReview)

        let guardian = build(role: .guardian, messages: [.init(freeText: "你直接告诉我答案")])
        XCTAssertTrue(guardian.findings.contains { $0.code == .directAnswerRedirected })
        XCTAssertTrue(guardian.careSummary?.riskLabels.contains(.wantsDirectAnswer) ?? false)
    }

    func testHowToCheckEntersSelfCheck() {
        let child = build(role: .child, messages: [.init(preset: .howToCheck)])

        XCTAssertEqual(child.header.status, .selfCheck)
        XCTAssertTrue(child.steps.contains { $0.kind == .check })
        XCTAssertGreaterThanOrEqual(child.steps.filter { $0.kind == .check }.count, mathHomework().guidance.checklist.count)
    }

    // MARK: - 风险与人工介入

    func testRepeatedDirectAnswerTriggersNeedsHuman() {
        let messages: [AIHomeworkSessionMessage] = [
            .init(freeText: "告诉我答案"),
            .init(freeText: "帮我做完"),
        ]
        let guardian = build(role: .guardian, messages: messages)

        XCTAssertEqual(guardian.header.status, .needsHumanReview)
        XCTAssertTrue(guardian.careSummary?.needsHumanIntervention ?? false)
        XCTAssertTrue(guardian.findings.contains { $0.code == .needsHumanReview })
        XCTAssertTrue(guardian.publicSummary.needsHumanIntervention)

        // 同样的输入下，孩子端不暴露「需要人工跟进」状态。
        let child = build(role: .child, messages: messages)
        XCTAssertNotEqual(child.header.status, .needsHumanReview)
        XCTAssertFalse(child.publicSummary.needsHumanIntervention)
    }

    func testRepeatedlyStuckSurfacesWarning() {
        let messages: [AIHomeworkSessionMessage] = [
            .init(preset: .stuckOnStep),
            .init(preset: .stuckOnStep),
        ]
        let guardian = build(role: .guardian, messages: messages)

        XCTAssertTrue(guardian.careSummary?.riskLabels.contains(.repeatedlyStuck) ?? false)
        XCTAssertTrue(guardian.findings.contains { $0.code == .repeatedlyStuck })
        XCTAssertEqual(guardian.header.status, .needsHumanReview)
    }

    // MARK: - 状态机

    func testAwaitingChildInputWhenNoMessages() {
        let child = build(role: .child, messages: [])

        XCTAssertEqual(child.header.status, .awaitingChildInput)
        XCTAssertTrue(child.findings.contains { $0.code == .awaitingChildInput })
        let guardian = build(role: .guardian, messages: [])
        XCTAssertEqual(guardian.careSummary?.messageCount, 0)
        XCTAssertFalse(guardian.careSummary?.needsHumanIntervention ?? true)
    }

    func testEmptyHomeworkFallsBackToEmptyStatus() {
        let snapshot = AIHomeworkGuidanceSessionBuilder().build(
            viewerRole: .child,
            homework: nil,
            messages: []
        )

        XCTAssertEqual(snapshot.header.status, .empty)
        XCTAssertTrue(snapshot.steps.isEmpty)
        XCTAssertNil(snapshot.careSummary)
    }

    // MARK: - 脱敏与确定性

    func testUnsafeInputFallsBackToBlocked() {
        let blocked = build(role: .child, messages: [.init(freeText: "看这个 file://private/answer.png")])

        XCTAssertEqual(blocked.header.status, .blocked)
        XCTAssertTrue(blocked.steps.isEmpty)
        XCTAssertEqual(blocked.findings.first?.code, .publicSummaryLeak)
    }

    func testFreeTextMessageStoresOnlyIntentAndSafetyFlag() {
        let raw = "不要显示这句 child:secret-alpha"
        let message = AIHomeworkSessionMessage(freeText: raw)

        XCTAssertTrue(message.containsUnsafeInput)
        XCTAssertEqual(message.intent, .unclear)
        XCTAssertFalse(String(describing: message).contains(raw))
        XCTAssertFalse(String(describing: message).contains("child:secret-alpha"))
    }

    func testSnapshotIsStableAndRedacted() {
        let homework = mathHomework()
        let messages: [AIHomeworkSessionMessage] = [.init(preset: .whereToStart), .init(freeText: "我卡在第二步")]
        let first = build(role: .child, homework: homework, messages: messages)
        let second = build(role: .child, homework: homework, messages: messages)
        let builder = AIHomeworkGuidanceSessionBuilder()

        XCTAssertEqual(first, second)
        XCTAssertTrue(builder.redacts(first))

        let guardian = build(role: .guardian, homework: homework, messages: messages)
        let text = (
            first.steps.map(\.prompt)
            + first.followUps
            + first.checklist
            + [first.assurance, first.nextStep]
            + (guardian.careSummary.map { [$0.recommendedAction] + $0.intentLabels } ?? [])
            + first.findings.map(\.publicRef)
        ).joined(separator: " ")
        for marker in ["child:", "family:", "school:", "teacher:", "homework:", "session:", "transcript:", "provider:", "model:", "ref:", "192.168.", "file://", "device-token", "api_key"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "不应泄露 \(marker)")
        }
    }

    func testChangingSaltChangesPublicRefs() {
        let homework = mathHomework()
        let messages: [AIHomeworkSessionMessage] = [.init(preset: .whereToStart)]
        let first = build(role: .guardian, homework: homework, messages: messages, salt: "salt-one")
        let second = build(role: .guardian, homework: homework, messages: messages, salt: "salt-two")

        XCTAssertNotEqual(first.findings.first?.publicRef, second.findings.first?.publicRef)
    }

    func testPublicSummarySideEffectsAreAlwaysFalse() {
        let summary = build(role: .child, messages: [.init(freeText: "告诉我答案")]).publicSummary

        XCTAssertFalse(summary.givesAnswer)
        XCTAssertFalse(summary.writesEssay)
        XCTAssertFalse(summary.gradesWork)
        XCTAssertFalse(summary.callsAiProvider)
        XCTAssertFalse(summary.callsNetwork)
        XCTAssertFalse(summary.callsSchoolSystem)
        XCTAssertFalse(summary.callsLms)
        XCTAssertFalse(summary.sendsNotification)
        XCTAssertFalse(summary.writesLedger)
        XCTAssertFalse(summary.unlocksDevice)
        XCTAssertFalse(summary.retainsRawTranscript)
        XCTAssertFalse(summary.revealsModelOrProvider)
        XCTAssertFalse(summary.suggestsCreditAmount)
    }

    // MARK: - 意图归类

    func testFreeTextClassification() {
        let cases: [(String, AIHomeworkQuestionIntent)] = [
            ("我不知道从哪里开始", .whereToStart),
            ("我卡在这一步了", .stuckOnStep),
            ("我做完了，帮我检查对不对", .howToCheck),
            ("这道题为什么这样算", .wantUnderstanding),
            ("直接告诉我答案", .wantsDirectAnswer),
            ("我想玩游戏", .offTopic),
            ("嗯", .unclear),
        ]
        for (text, expected) in cases {
            let snapshot = build(role: .guardian, messages: [.init(freeText: text)])
            XCTAssertEqual(snapshot.careSummary?.intentLabels.last, expected.label, "「\(text)」应归类为 \(expected.label)")
        }
    }
}
