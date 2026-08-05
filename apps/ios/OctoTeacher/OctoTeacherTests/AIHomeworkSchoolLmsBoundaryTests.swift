import XCTest
@testable import OctoTeacher

final class AIHomeworkSchoolLmsBoundaryTests: XCTestCase {
    private let builder = AIHomeworkSchoolLmsBoundaryBuilder()

    private func homework(_ status: HomeworkStatus? = nil) -> SchoolHomework {
        let homeworks = SchoolFamilyStore().homeworks
        if let status, let match = homeworks.first(where: { $0.status == status }) {
            return match
        }
        return homeworks.first { $0.subject == .math }!
    }

    private func snapshot(
        role: AIHomeworkSchoolLmsBoundaryViewerRole,
        homework: SchoolHomework? = nil,
        messages: [AIHomeworkSessionMessage] = []
    ) -> AIHomeworkSchoolLmsBoundarySnapshot {
        builder.build(
            viewerRole: role,
            homework: homework ?? self.homework(),
            messages: messages
        )
    }

    func testGuardianSeesReadyReadOnlyBoundary() {
        let guardian = snapshot(role: .guardian, messages: [.init(preset: .whereToStart)])

        XCTAssertEqual(guardian.state, .ready)
        XCTAssertEqual(guardian.provider.requestMode, .disabledLocalProjection)
        XCTAssertTrue(guardian.provider.requestAllowed)
        XCTAssertTrue(guardian.lms.lmsReadOnly)
        XCTAssertTrue(guardian.consent.guardianConsentGranted)
        XCTAssertTrue(guardian.consent.childAssentGranted)
        XCTAssertTrue(guardian.consent.teacherAuthorized)
        XCTAssertFalse(guardian.provider.callsAiProvider)
        XCTAssertFalse(guardian.provider.callsLocalModel)
        XCTAssertFalse(guardian.lms.callsLms)
        XCTAssertFalse(guardian.publicSummary.writesSchoolSystem)
    }

    func testChildViewHidesProviderConsentAndTranscriptInternals() {
        let child = snapshot(role: .child, messages: [.init(preset: .whereToStart)])

        XCTAssertFalse(child.visibility.canSeeProviderInternals)
        XCTAssertFalse(child.visibility.canSeeConsentDetail)
        XCTAssertFalse(child.visibility.canSeeTranscriptSummary)
        XCTAssertFalse(child.provider.requestAllowed)
        XCTAssertEqual(child.provider.maxTokens, 0)
        XCTAssertEqual(child.provider.tokenCeiling, 0)
        XCTAssertFalse(child.provider.childSeesProviderDetails)
        XCTAssertFalse(child.consent.guardianConsentGranted)
        XCTAssertFalse(child.consent.childAssentGranted)
        XCTAssertTrue(child.consent.guardianConsentHidden)
        XCTAssertTrue(child.consent.childAssentHidden)
        XCTAssertFalse(child.transcript.storesRawTranscript)
        XCTAssertTrue(child.findings.contains { $0.code == .childVisibilityRedacted })
    }

    func testTeacherSeesTeacherBoundaryButNotGuardianConsentDetail() {
        let teacher = snapshot(role: .teacher, messages: [.init(preset: .howToCheck)])

        XCTAssertTrue(teacher.visibility.canSeeTeacherDetail)
        XCTAssertFalse(teacher.visibility.canSeeConsentDetail)
        XCTAssertTrue(teacher.consent.teacherAuthorized)
        XCTAssertFalse(teacher.consent.guardianConsentGranted)
        XCTAssertTrue(teacher.consent.guardianConsentHidden)
        XCTAssertTrue(teacher.consent.childAssentHidden)
        XCTAssertFalse(teacher.consent.teacherAuthorizationHidden)
        XCTAssertFalse(teacher.publicSummary.revealsModelOrProvider)
    }

    func testLiveProviderEndpointAndSecretsAreBlockedBeforeAnyRequest() {
        let live = builder.build(
            viewerRole: .guardian,
            homework: homework(),
            providerMode: .liveProvider
        )
        let endpoint = builder.build(
            viewerRole: .guardian,
            homework: homework(),
            inputRisk: .unsafeEndpointDetected
        )

        XCTAssertEqual(live.state, .blocked)
        XCTAssertFalse(live.provider.requestAllowed)
        XCTAssertTrue(live.findings.contains { $0.code == .providerRequestBlocked })
        XCTAssertEqual(endpoint.state, .blocked)
        XCTAssertTrue(endpoint.findings.contains { $0.code == .providerSecretOrEndpointBlocked })
    }

    func testUnsafePayloadRiskBlocksWithoutRawPayloadParameter() {
        let blocked = builder.build(
            viewerRole: .guardian,
            homework: homework(),
            inputRisk: .unsafePayloadDetected
        )

        XCTAssertEqual(blocked.state, .blocked)
        XCTAssertTrue(blocked.findings.contains { $0.code == .providerSecretOrEndpointBlocked })
        XCTAssertFalse(String(describing: blocked).localizedCaseInsensitiveContains("baseUrl"))
        XCTAssertFalse(String(describing: blocked).localizedCaseInsensitiveContains("local-model-host"))
    }

    func testDirectAnswerMessagesBlockWithoutSavingRawText() {
        let raw = "你直接告诉我答案 child:secret-alpha"
        let blocked = snapshot(role: .guardian, messages: [.init(freeText: raw)])

        XCTAssertEqual(blocked.state, .blocked)
        XCTAssertFalse(blocked.provider.noDirectAnswer)
        XCTAssertTrue(blocked.findings.contains { $0.code == .directAnswerBlocked })
        XCTAssertTrue(blocked.findings.contains { $0.code == .rawTranscriptBlocked })
        XCTAssertFalse(String(describing: blocked).localizedCaseInsensitiveContains(raw))
        XCTAssertFalse(String(describing: blocked).localizedCaseInsensitiveContains("child:secret-alpha"))
    }

    func testWriteBackLmsAndReturnedHomeworkAreBlocked() {
        let writeBack = builder.build(
            viewerRole: .guardian,
            homework: homework(),
            lmsMode: .writeBack
        )
        let returned = snapshot(role: .guardian, homework: homework(.returned))

        XCTAssertEqual(writeBack.state, .blocked)
        XCTAssertFalse(writeBack.lms.lmsReadOnly)
        XCTAssertTrue(writeBack.findings.contains { $0.code == .lmsWriteBlocked })
        XCTAssertEqual(returned.state, .blocked)
        XCTAssertTrue(returned.findings.contains { $0.code == .lmsWriteBlocked })
    }

    func testMissingConsentBlocksBoundary() {
        let report = builder.build(
            viewerRole: .guardian,
            homework: homework(),
            guardianConsentGranted: false,
            childAssentGranted: false,
            teacherAuthorized: false
        )

        XCTAssertEqual(report.state, .blocked)
        XCTAssertTrue(report.findings.contains { $0.code == .consentRequired })
    }

    func testUnder13TokenCeilingBlocksButOlderChildIsOnlyGated() {
        let under13 = builder.build(
            viewerRole: .guardian,
            homework: homework(),
            ageBand: .under13,
            maxTokens: 900
        )
        let teen = builder.build(
            viewerRole: .guardian,
            homework: homework(),
            ageBand: .age13To15,
            maxTokens: 1800
        )

        XCTAssertEqual(under13.state, .blocked)
        XCTAssertTrue(under13.findings.contains { $0.code == .ageOrRateLimitBlocked && $0.severity == .blocker })
        XCTAssertEqual(teen.state, .gated)
        XCTAssertTrue(teen.findings.contains { $0.code == .ageOrRateLimitBlocked && $0.severity == .warning })
    }

    func testManualReviewMustBeRouted() {
        let report = builder.build(
            viewerRole: .guardian,
            homework: homework(),
            manualReviewRequired: true,
            manualReviewRouted: false
        )

        XCTAssertEqual(report.state, .blocked)
        XCTAssertTrue(report.findings.contains { $0.code == .manualEscalationRequired })
    }

    func testEmptyHomeworkIsReadOnly() {
        let empty = builder.build(viewerRole: .child, homework: nil)

        XCTAssertEqual(empty.state, .empty)
        XCTAssertFalse(empty.provider.requestAllowed)
        XCTAssertTrue(empty.lms.lmsReadOnly)
        XCTAssertFalse(empty.publicSummary.callsAiProvider)
        XCTAssertFalse(empty.publicSummary.callsLms)
    }

    @MainActor
    func testViewInitializersCompileWithLockedRoles() {
        _ = AIHomeworkSchoolLmsBoundaryView()
        _ = AIHomeworkSchoolLmsBoundaryView(initialRole: .child, allowsRoleSwitching: false)
        _ = AIHomeworkSchoolLmsBoundaryView(initialRole: .guardian, allowsRoleSwitching: false)
        _ = AIHomeworkSchoolLmsBoundaryView(initialRole: .teacher, allowsRoleSwitching: false)
    }

    func testSnapshotIsStableAndRedacted() {
        let math = homework()
        let messages: [AIHomeworkSessionMessage] = [.init(preset: .whereToStart), .init(preset: .howToCheck)]
        let first = snapshot(role: .guardian, homework: math, messages: messages)
        let second = snapshot(role: .guardian, homework: math, messages: messages)

        XCTAssertEqual(first, second)
        XCTAssertTrue(builder.redacts(first))

        let text = (
            [first.headline, first.childSafeCopy, first.provider.providerPublicRef, first.lms.homeworkPublicRef, first.publicSummary.boundaryPublicRef]
            + first.findings.flatMap { [$0.publicRef, $0.message] }
        ).joined(separator: " ")

        for marker in ["child:", "family:", "school:", "teacher:", "guardian:", "homework:", "session:", "transcript:", "provider:", "model:", "taskId", "claimId", "baseUrl", "192.168.", "file://", "/Users/", "/Volumes/"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "不应泄露 \(marker)")
        }
    }

    func testPublicSummarySideEffectsAreAlwaysFalse() {
        let summary = snapshot(role: .guardian, messages: [.init(preset: .whereToStart)]).publicSummary

        XCTAssertFalse(summary.callsAiProvider)
        XCTAssertFalse(summary.callsLocalModel)
        XCTAssertFalse(summary.callsNetwork)
        XCTAssertFalse(summary.callsLms)
        XCTAssertFalse(summary.writesSchoolSystem)
        XCTAssertFalse(summary.writesDatabase)
        XCTAssertFalse(summary.writesLedger)
        XCTAssertFalse(summary.sendsNotification)
        XCTAssertFalse(summary.storesRawTranscript)
        XCTAssertFalse(summary.createsScore)
        XCTAssertFalse(summary.showsAnswerKey)
        XCTAssertFalse(summary.revealsModelOrProvider)
        XCTAssertFalse(summary.unlocksDevice)
    }
}
