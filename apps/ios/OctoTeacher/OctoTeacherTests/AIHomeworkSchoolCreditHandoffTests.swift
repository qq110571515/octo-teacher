import XCTest
@testable import OctoTeacher

final class AIHomeworkSchoolCreditHandoffTests: XCTestCase {
    private let builder = AIHomeworkSchoolCreditHandoffBuilder()

    private func homework(_ status: HomeworkStatus? = nil) -> SchoolHomework {
        let homeworks = SchoolFamilyStore().homeworks
        if let status, let match = homeworks.first(where: { $0.status == status }) {
            return match
        }
        return homeworks.first { $0.subject == .math }!
    }

    private func snapshot(
        role: AIHomeworkSchoolCreditHandoffViewerRole,
        homework: SchoolHomework? = nil,
        messages: [AIHomeworkSessionMessage] = []
    ) -> AIHomeworkSchoolCreditHandoffSnapshot {
        builder.build(
            viewerRole: role,
            homework: homework ?? self.homework(),
            messages: messages
        )
    }

    // MARK: - 角色边界

    func testChildSeesGuidanceAndNextStepButNoAdultOrCreditDetails() {
        let child = snapshot(role: .child, messages: [.init(preset: .whereToStart)])

        XCTAssertTrue(child.visibility.canSeeGuidanceFacts)
        XCTAssertFalse(child.visibility.canSeeAdultReviewDetail)
        XCTAssertFalse(child.visibility.canSeeCreditDetail)
        XCTAssertFalse(child.visibility.canSeeCareSummary)
        XCTAssertNil(child.careSummary)
        XCTAssertFalse(child.guidance.showsFinalAnswer)
        XCTAssertFalse(child.guidance.showsAnswerKey)
        XCTAssertFalse(child.credit.showsAmountToChild)
        XCTAssertFalse(child.credit.writesLedger)
        XCTAssertFalse(child.childNextStep.showsCreditAmount)
        XCTAssertTrue(child.findings.contains { $0.code == .childVisibilityRedacted })
    }

    func testCareTeamGetsSummaryWithoutRawTranscript() {
        let guardian = snapshot(role: .guardian, messages: [.init(preset: .whereToStart)])

        XCTAssertTrue(guardian.visibility.canSeeCareSummary)
        XCTAssertNotNil(guardian.careSummary)
        XCTAssertFalse(guardian.careSummary?.exposesRawTranscript ?? true)
        XCTAssertFalse(guardian.careSummary?.exposesChildAnswer ?? true)
        XCTAssertFalse(guardian.careSummary?.exposesCreditAmount ?? true)
        XCTAssertFalse(guardian.careSummary?.exposesModelOrProvider ?? true)
        XCTAssertGreaterThan(guardian.guidance.referenceHintCount, 0)
        XCTAssertGreaterThan(guardian.guidance.selfCheckCount, 0)
    }

    func testTeacherCannotSeeCreditDetail() {
        let teacher = snapshot(role: .teacher, messages: [.init(preset: .howToCheck)])

        XCTAssertTrue(teacher.visibility.canSeeAdultReviewDetail)
        XCTAssertTrue(teacher.visibility.canSeeCareSummary)
        XCTAssertFalse(teacher.visibility.canSeeCreditDetail)
        XCTAssertFalse(teacher.credit.showsAmountToCareTeam)
        XCTAssertFalse(teacher.publicSummary.showsCreditAmount)
    }

    func testChildSnapshotRedactsAdultAndCreditFieldsEvenWhenUnderlyingHomeworkNeedsGuardianReview() {
        let verified = homework(.verified)
        let guardian = snapshot(role: .guardian, homework: verified, messages: [.init(preset: .howToCheck)])
        let child = snapshot(role: .child, homework: verified, messages: [.init(preset: .howToCheck)])

        XCTAssertTrue(guardian.adultReview.guardianConfirmationRequired)
        XCTAssertTrue(guardian.visibility.canSeeCreditDetail)
        XCTAssertFalse(child.visibility.canSeeAdultReviewDetail)
        XCTAssertFalse(child.adultReview.teacherReviewRequired)
        XCTAssertFalse(child.adultReview.guardianConfirmationRequired)
        XCTAssertEqual(child.adultReview.confirmedCount, 0)
        XCTAssertFalse(child.publicSummary.teacherReviewRequired)
        XCTAssertFalse(child.publicSummary.guardianConfirmationRequired)
        XCTAssertEqual(child.credit.settleableCount, 0)
        XCTAssertEqual(child.credit.frozenCount, 0)
        XCTAssertEqual(child.credit.reviewRequiredCount, 0)
        XCTAssertEqual(child.credit.conflictCount, 0)
    }

    // MARK: - 交接阻断

    func testDirectAnswerGuidanceBlocksHandoff() {
        let child = snapshot(role: .child, messages: [.init(freeText: "你直接告诉我答案")])

        XCTAssertEqual(child.state, .blocked)
        XCTAssertEqual(child.childNextStep.kind, .removeAnswerMaterial)
        XCTAssertFalse(child.guidance.guidanceAccepted)
        XCTAssertFalse(child.guidance.noDirectAnswer)
        XCTAssertTrue(child.findings.contains { $0.code == .guidanceDirectAnswerBlocked })
        XCTAssertEqual(child.credit.state, .blocked)
    }

    func testReturnedHomeworkBlocksAssignmentHandoff() {
        let returned = snapshot(
            role: .guardian,
            homework: homework(.returned),
            messages: [.init(preset: .stuckOnStep)]
        )

        XCTAssertEqual(returned.state, .blocked)
        XCTAssertFalse(returned.assignment.accepted)
        XCTAssertTrue(returned.assignment.needsRedo)
        XCTAssertTrue(returned.adultReview.blocked)
        XCTAssertTrue(returned.findings.contains { $0.code == .schoolAssignmentReturned })
        XCTAssertTrue(returned.findings.contains { $0.code == .schoolAssignmentBlocked })
        XCTAssertEqual(returned.credit.state, .blocked)
    }

    func testUnsafeInputFallsBackToBlockedWithoutRawText() {
        let raw = "不要保存这句 child:secret-alpha"
        let blocked = snapshot(role: .guardian, messages: [.init(freeText: raw)])

        XCTAssertEqual(blocked.state, .blocked)
        XCTAssertTrue(blocked.findings.contains { $0.code == .publicSummaryLeak })
        XCTAssertFalse(String(describing: blocked).localizedCaseInsensitiveContains(raw))
        XCTAssertFalse(String(describing: blocked).localizedCaseInsensitiveContains("child:secret-alpha"))
    }

    // MARK: - 空态 / 脱敏 / 副作用

    func testEmptyHomeworkYieldsEmptyReadOnlySnapshot() {
        let empty = builder.build(viewerRole: .child, homework: nil)

        XCTAssertEqual(empty.state, .empty)
        XCTAssertFalse(empty.assignment.accepted)
        XCTAssertNil(empty.careSummary)
        XCTAssertEqual(empty.childNextStep.kind, .readOnly)
        XCTAssertFalse(empty.publicSummary.callsNetwork)
        XCTAssertFalse(empty.publicSummary.writesLedger)
    }

    func testSnapshotIsStableAndRedacted() {
        let math = homework()
        let messages: [AIHomeworkSessionMessage] = [.init(preset: .whereToStart), .init(preset: .howToCheck)]
        let first = snapshot(role: .guardian, homework: math, messages: messages)
        let second = snapshot(role: .guardian, homework: math, messages: messages)

        XCTAssertEqual(first, second)
        XCTAssertTrue(builder.redacts(first))

        let text = (
            [first.headline, first.assignment.subjectLabel, first.adultReview.childVisibleMessage, first.credit.childVisibleCopy, first.childNextStep.publicActionRef]
            + first.findings.flatMap { [$0.publicRef, $0.message] }
            + (first.careSummary.map { [$0.headline, $0.recommendedAction] + $0.intentLabels + $0.riskLabels } ?? [])
        ).joined(separator: " ")

        for marker in ["child:", "family:", "school:", "teacher:", "guardian:", "homework:", "proof:", "ledger:", "credit:", "session:", "transcript:", "provider:", "model:", "ref:", "192.168.", "file://", "/Users/", "/Volumes/", "taskId", "claimId"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "不应泄露 \(marker)")
        }
    }

    func testPublicSummarySideEffectsAreAlwaysFalse() {
        let summary = snapshot(role: .child, messages: [.init(preset: .whereToStart)]).publicSummary

        XCTAssertFalse(summary.callsAiProvider)
        XCTAssertFalse(summary.callsNetwork)
        XCTAssertFalse(summary.writesDatabase)
        XCTAssertFalse(summary.writesSchoolSystem)
        XCTAssertFalse(summary.callsLms)
        XCTAssertFalse(summary.sendsNotification)
        XCTAssertFalse(summary.writesLedger)
        XCTAssertFalse(summary.issuesCredit)
        XCTAssertFalse(summary.freezesCredit)
        XCTAssertFalse(summary.createsScore)
        XCTAssertFalse(summary.storesRawTranscript)
        XCTAssertFalse(summary.revealsModelOrProvider)
        XCTAssertFalse(summary.showsCreditAmount)
        XCTAssertFalse(summary.unlocksDevice)
    }
}
