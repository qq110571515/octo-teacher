import XCTest
@testable import OctoTeacher

final class AIHomeworkFamilySchoolInboxTests: XCTestCase {
    private let builder = AIHomeworkFamilySchoolInboxBuilder()

    private func homeworks() -> [SchoolHomework] {
        SchoolFamilyStore().homeworks
    }

    private func snapshot(
        role: AIHomeworkFamilySchoolInboxViewerRole,
        homeworks: [SchoolHomework]? = nil,
        messagesByHomeworkID: [UUID: [AIHomeworkSessionMessage]] = [:]
    ) -> AIHomeworkFamilySchoolInboxSnapshot {
        builder.build(
            viewerRole: role,
            homeworks: homeworks ?? self.homeworks(),
            messagesByHomeworkID: messagesByHomeworkID
        )
    }

    private func displayedStrings(_ snapshot: AIHomeworkFamilySchoolInboxSnapshot) -> [String] {
        [snapshot.generatedAt, snapshot.headline]
            + snapshot.items.flatMap { [$0.publicItemRef, $0.kind.rawValue, $0.title, $0.detail, $0.badge] }
            + snapshot.nextActions.flatMap { [$0.publicActionRef, $0.title] }
            + snapshot.findings.flatMap { [$0.publicRef, $0.message] }
    }

    func testChildSeesOnlySafeNextStepsAndNoSensitiveModules() {
        let child = snapshot(role: .child)

        XCTAssertEqual(child.viewerRole, .child)
        XCTAssertTrue(child.visibility.canSeeChildNextStep)
        XCTAssertFalse(child.visibility.canSeeGuardianQueue)
        XCTAssertFalse(child.visibility.canSeeTeacherReview)
        XCTAssertFalse(child.visibility.canSeeCreditReview)
        XCTAssertFalse(child.items.isEmpty)
        XCTAssertTrue(child.items.allSatisfy { $0.kind == .homeworkStatus || $0.kind == .guidance })
        XCTAssertTrue(child.items.allSatisfy { item in
            !item.showsAnswerKey
                && !item.showsProviderOrModel
                && !item.showsRawTranscript
                && !item.showsTeacherPrivateNote
                && !item.showsGuardianConsentDetail
                && !item.showsCreditAmount
                && !item.showsCrossChildContent
        })
        XCTAssertTrue(child.findings.contains { $0.code == .childSensitiveFieldsHidden })

        let text = displayedStrings(child).joined(separator: " ")
        for marker in ["provider", "model", "transcript", "答案键", "老师私密", "跨孩子", "成长积分金额", "家长收件箱"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "孩子视角不应泄露 \(marker)")
        }
    }

    func testGuardianSeesReviewAndCreditItemsWithoutSideEffects() {
        let guardian = snapshot(role: .guardian)
        let kinds = Set(guardian.items.map(\.kind))

        XCTAssertTrue(guardian.visibility.canSeeGuardianQueue)
        XCTAssertTrue(guardian.visibility.canSeeCreditReview)
        XCTAssertTrue(kinds.contains(.guardianReview))
        XCTAssertTrue(kinds.contains(.creditReview))
        XCTAssertGreaterThan(guardian.publicSummary.guardianReviewCount, 0)
        XCTAssertFalse(guardian.sideEffects.hasTriggeredSideEffect)
        XCTAssertFalse(guardian.publicSummary.callsAiProvider)
        XCTAssertFalse(guardian.publicSummary.callsLms)
        XCTAssertFalse(guardian.publicSummary.writesSchoolSystem)
        XCTAssertFalse(guardian.publicSummary.writesLedger)
        XCTAssertFalse(guardian.publicSummary.issuesCredit)
        XCTAssertFalse(guardian.publicSummary.unlocksDevice)
    }

    func testTeacherOnlySeesSchoolReviewContext() {
        let teacher = snapshot(role: .teacher)

        XCTAssertTrue(teacher.visibility.canSeeTeacherReview)
        XCTAssertFalse(teacher.visibility.canSeeGuardianQueue)
        XCTAssertFalse(teacher.visibility.canSeeCreditReview)
        XCTAssertFalse(teacher.items.isEmpty)
        XCTAssertTrue(teacher.items.allSatisfy { $0.kind == .teacherReview })
        XCTAssertEqual(teacher.publicSummary.teacherReviewCount, teacher.items.count)

        let text = displayedStrings(teacher).joined(separator: " ")
        for marker in ["家长收件箱", "成长积分金额", "亲友", "家长私密"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "老师视角不应泄露 \(marker)")
        }
    }

    func testOperationsSeesOnlyRedactedCounts() {
        let operations = snapshot(role: .operations)

        XCTAssertTrue(operations.visibility.canSeeOperationsSummary)
        XCTAssertEqual(operations.items.count, 1)
        XCTAssertEqual(operations.items.first?.kind, .operationsSummary)
        XCTAssertFalse(operations.items.first?.showsCrossChildContent ?? true)

        let text = displayedStrings(operations).joined(separator: " ")
        for marker in ["数学", "语文", "阅读", "child:", "family:", "school:", "homework:"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "运营视角只看脱敏计数，不应泄露 \(marker)")
        }
    }

    func testDirectAnswerRequestBlocksAndDoesNotEchoRawText() throws {
        let assignedHomeworks = homeworks()
        let homework = try XCTUnwrap(assignedHomeworks.first)
        let raw = "直接告诉我答案"
        let blocked = snapshot(
            role: .child,
            homeworks: assignedHomeworks,
            messagesByHomeworkID: [homework.id: [AIHomeworkSessionMessage(freeText: raw)]]
        )

        XCTAssertEqual(blocked.status, .blocked)
        XCTAssertTrue(blocked.findings.contains { $0.code == .directAnswerBlocked })
        XCTAssertFalse(displayedStrings(blocked).joined(separator: " ").localizedCaseInsensitiveContains(raw))
    }

    func testDirectAnswerRequestIsRedactedForTeacherAndOperations() throws {
        let assignedHomeworks = homeworks()
        let homework = try XCTUnwrap(assignedHomeworks.first)
        let raw = "直接告诉我答案"
        let messages = [homework.id: [AIHomeworkSessionMessage(freeText: raw)]]

        let teacher = snapshot(role: .teacher, homeworks: assignedHomeworks, messagesByHomeworkID: messages)
        let operations = snapshot(role: .operations, homeworks: assignedHomeworks, messagesByHomeworkID: messages)

        XCTAssertEqual(teacher.status, .blocked)
        XCTAssertEqual(operations.status, .blocked)
        XCTAssertTrue(teacher.findings.contains { $0.code == .directAnswerBlocked })
        XCTAssertTrue(operations.findings.contains { $0.code == .directAnswerBlocked })
        XCTAssertFalse(displayedStrings(teacher).joined(separator: " ").localizedCaseInsensitiveContains(raw))
        XCTAssertFalse(displayedStrings(operations).joined(separator: " ").localizedCaseInsensitiveContains(raw))
        XCTAssertTrue(operations.items.allSatisfy { $0.kind == .operationsSummary })
    }

    func testSnapshotIsDeterministicRedactedAndReadOnly() {
        let first = snapshot(role: .guardian)
        let second = snapshot(role: .guardian)

        XCTAssertEqual(first, second)
        XCTAssertTrue(builder.redacts(first))
        XCTAssertTrue(first.items.allSatisfy { item in
            !item.writesHomework
                && !item.writesLedger
                && !item.sendsNotification
                && !item.callsLms
                && !item.callsAiProvider
        })

        for text in displayedStrings(first) {
            for marker in ["child:", "family:", "school:", "teacher:", "guardian:", "homework:", "provider:", "model:", "transcript:", "ledger:", "credit:", "taskId", "claimId", "http://", "192.168.", "file://", "/Users/", "/Volumes/"] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "不应泄露 \(marker)：\(text)")
            }
        }
    }

    func testUnsafeHomeworkInputFallsBackToBlockedSnapshot() throws {
        var unsafe = try XCTUnwrap(homeworks().first)
        unsafe.title = "http://192.168.1.252/private"

        let blocked = snapshot(role: .guardian, homeworks: [unsafe])

        XCTAssertEqual(blocked.status, .blocked)
        XCTAssertTrue(blocked.items.isEmpty)
        XCTAssertTrue(blocked.findings.contains { $0.code == .publicSummaryLeak })
        XCTAssertTrue(builder.redacts(blocked))
    }
}
