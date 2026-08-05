import XCTest
@testable import OctoTeacher

/// A92 iOS 亲友创作评论/鼓励安全壳测试。
final class MobileRelativeCreativeCommentSafetyWorkbenchTests: XCTestCase {

    private func build(
        role: MobileRelativeCreativeCommentViewerRole,
        drafts: [MobileRelativeCreativeCommentDraft] = .mobileRelativeCreativeCommentMock
    ) -> MobileRelativeCreativeCommentSafetyWorkbench {
        MobileRelativeCreativeCommentSafetyBuilder().build(role: role, drafts: drafts)
    }

    func testChildSeesApprovedEncouragementWithoutRawCommentRewardCreditOrDevice() {
        let workbench = build(role: .child)
        let comment = tryUnwrap(workbench.comments.first)

        XCTAssertEqual(workbench.role, .child)
        XCTAssertEqual(workbench.publicSummary.visibleCommentCount, 1)
        XCTAssertEqual(comment.state, .approvedEncouragement)
        XCTAssertTrue(comment.visibleToChild)
        XCTAssertFalse(comment.publishesComment)
        XCTAssertFalse(comment.sendsNotification)
        XCTAssertFalse(comment.grantsCredit)
        XCTAssertFalse(comment.unlocksDevice)
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)

        let text = workbench.displayValues.joined(separator: " ")
        for marker in ["原文", "奖励承诺", "成长积分金额", "设备命令", "解锁", "comment-encourage-a", "showcase-art-a"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "孩子视角泄露: \(marker)")
        }
    }

    func testGuardianSeesRelationshipReviewAndBoundarySignals() {
        let workbench = build(role: .guardian)
        let comment = tryUnwrap(workbench.comments.first)

        XCTAssertEqual(workbench.role, .guardian)
        XCTAssertEqual(comment.authorLabel, "亲友")
        XCTAssertTrue(comment.relationshipAuthorized)
        XCTAssertTrue(comment.guardianApproved)
        XCTAssertTrue(comment.moderationPassed)
        XCTAssertFalse(comment.rewardPressureBlocked)
        XCTAssertFalse(comment.roleBoundaryBlocked)
        XCTAssertTrue(workbench.findings.contains { $0.code == .readOnlyReady && !$0.actionRequired })
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
    }

    func testRelativeSeesExpressionGuideWithoutPublishing() {
        let workbench = build(role: .relative)
        let comment = tryUnwrap(workbench.comments.first)

        XCTAssertEqual(workbench.role, .relative)
        XCTAssertEqual(comment.title, "支持性表达指引")
        XCTAssertTrue(comment.visibleToRelative)
        XCTAssertFalse(comment.publishesComment)
        XCTAssertFalse(comment.approvesComment)
        XCTAssertFalse(comment.sendsNotification)
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)

        let text = workbench.displayValues.joined(separator: " ")
        for marker in ["成长积分金额", "解锁设备", "账本"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "亲友视角泄露: \(marker)")
        }
    }

    func testPendingPrivateWithdrawnNoAssentDeletionOrAppealHiddenFromChild() {
        let cases: [[MobileRelativeCreativeCommentDraft]] = [
            [.mock(guardianApproved: false)],
            [.mock(childAssentActive: false)],
            [.mock(showcasePrivate: true)],
            [.mock(showcaseWithdrawn: true)],
            [.mock(deletionRequested: true)],
            [.mock(appealOpen: true)]
        ]

        for drafts in cases {
            let child = build(role: .child, drafts: drafts)
            XCTAssertTrue(child.comments.isEmpty)
            XCTAssertEqual(child.publicSummary.visibleCommentCount, 0)
            XCTAssertFalse(child.publicSummary.hasTriggeredSideEffect)
        }

        let guardian = build(role: .guardian, drafts: [.mock(deletionRequested: true)])
        XCTAssertTrue(guardian.findings.contains { $0.code == .removalAppealBlocked && $0.actionRequired })
    }

    func testRewardPromiseDeviceLanguageAndSchoolDetailAreBlocked() {
        let drafts: [MobileRelativeCreativeCommentDraft] = [
            .mock(rewardPromise: true),
            .mock(deviceUnlockLanguage: true),
            .mock(schoolDetailMentioned: true)
        ]

        let guardian = build(role: .guardian, drafts: drafts)
        let child = build(role: .child, drafts: drafts)

        XCTAssertTrue(child.comments.isEmpty)
        XCTAssertEqual(guardian.publicSummary.blockedCount, 3)
        XCTAssertTrue(guardian.findings.contains { $0.code == .rewardPressureBlocked && $0.actionRequired })
        XCTAssertFalse(guardian.publicSummary.grantsCredit)
        XCTAssertFalse(guardian.publicSummary.unlocksDevice)
    }

    func testExpertOrUnauthorizedRelativeCannotMasqueradeAsFamilyEncouragement() {
        let guardian = build(role: .guardian, drafts: [
            .mock(authorRole: .expert),
            .mock(relationshipAuthorized: false)
        ])

        XCTAssertEqual(guardian.publicSummary.blockedCount, 2)
        XCTAssertTrue(guardian.comments.allSatisfy(\.roleBoundaryBlocked))
        XCTAssertTrue(guardian.findings.contains { $0.code == .roleBoundaryBlocked && $0.actionRequired })
    }

    func testUnsafePayloadFallsBackWithoutEchoingRawCommentOrRefs() {
        let workbench = build(role: .guardian, drafts: [
            .mock(supportiveSummary: "http://example.invalid child:raw comment:private")
        ])

        XCTAssertTrue(workbench.comments.isEmpty)
        XCTAssertEqual(workbench.publicSummary.findingCodes, [.unsafePayloadBlocked])
        let text = workbench.displayValues.joined(separator: " ")
        XCTAssertFalse(text.localizedCaseInsensitiveContains("example.invalid"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("child:raw"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("comment:private"))
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
    }

    func testPublicSummaryAndRowsNeverTriggerSideEffects() {
        for role in MobileRelativeCreativeCommentViewerRole.allCases {
            let workbench = build(role: role)
            let summary = workbench.publicSummary

            XCTAssertFalse(summary.publishesComment)
            XCTAssertFalse(summary.approvesComment)
            XCTAssertFalse(summary.sendsNotification)
            XCTAssertFalse(summary.opensCamera)
            XCTAssertFalse(summary.opensPhotoLibrary)
            XCTAssertFalse(summary.opensFilePicker)
            XCTAssertFalse(summary.uploadsMedia)
            XCTAssertFalse(summary.callsNetwork)
            XCTAssertFalse(summary.writesLedger)
            XCTAssertFalse(summary.grantsCredit)
            XCTAssertFalse(summary.unlocksDevice)
            XCTAssertFalse(summary.writesSocialPlatform)
            XCTAssertFalse(summary.hasTriggeredSideEffect)

            XCTAssertTrue(workbench.comments.allSatisfy { row in
                !row.publishesComment && !row.approvesComment && !row.sendsNotification
                    && !row.opensCamera && !row.opensPhotoLibrary && !row.opensFilePicker
                    && !row.uploadsMedia && !row.callsNetwork && !row.writesLedger
                    && !row.grantsCredit && !row.unlocksDevice && !row.writesSocialPlatform
            })
        }
    }

    func testDisplayValuesDoNotLeakInternalIdsOrSensitiveMarkers() {
        for role in MobileRelativeCreativeCommentViewerRole.allCases {
            let text = build(role: role).displayValues.joined(separator: " ")
            for raw in ["comment-encourage-a", "showcase-art-a"] {
                XCTAssertFalse(text.contains(raw), "\(role.label) 泄露内部 seed: \(raw)")
            }
            for marker in ["http://", "https://", "file://", "/Users/", "/Volumes/", "192.168.", "token", "comment:", "credit:"] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "\(role.label) 泄露敏感标记: \(marker)")
            }
        }
    }

    @MainActor
    func testViewInitializersAndCreativeShowcaseEntryCompile() {
        _ = MobileRelativeCreativeCommentSafetyWorkbenchView()
        _ = MobileRelativeCreativeCommentSafetyWorkbenchView(initialRole: .child, allowedRoles: [.child])
        _ = MobileRelativeCreativeCommentSafetyWorkbenchView(initialRole: .guardian, allowedRoles: [.guardian])
        _ = MobileRelativeCreativeCommentSafetyWorkbenchView(initialRole: .relative, allowedRoles: [.relative])
        _ = MobileCreativeShowcaseSafetyWorkbenchView()
    }

    private func tryUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) -> T {
        guard let value else {
            XCTFail("Expected value", file: file, line: line)
            fatalError("Expected value")
        }
        return value
    }
}

private extension MobileRelativeCreativeCommentDraft {
    static func mock(
        authorRole: MobileRelativeCreativeCommentAuthorRole = .relative,
        supportiveSummary: String = "亲友给出温和鼓励，肯定孩子坚持完成创作。",
        relationshipAuthorized: Bool = true,
        guardianApproved: Bool = true,
        moderationPassed: Bool = true,
        childAssentActive: Bool = true,
        showcasePrivate: Bool = false,
        showcaseWithdrawn: Bool = false,
        deletionRequested: Bool = false,
        appealOpen: Bool = false,
        rewardPromise: Bool = false,
        deviceUnlockLanguage: Bool = false,
        schoolDetailMentioned: Bool = false
    ) -> MobileRelativeCreativeCommentDraft {
        MobileRelativeCreativeCommentDraft(
            commentId: "comment-encourage-a",
            showcaseId: "showcase-art-a",
            authorRole: authorRole,
            supportiveSummary: supportiveSummary,
            relationshipAuthorized: relationshipAuthorized,
            guardianApproved: guardianApproved,
            moderationPassed: moderationPassed,
            childAssentActive: childAssentActive,
            showcasePrivate: showcasePrivate,
            showcaseWithdrawn: showcaseWithdrawn,
            deletionRequested: deletionRequested,
            appealOpen: appealOpen,
            rewardPromise: rewardPromise,
            deviceUnlockLanguage: deviceUnlockLanguage,
            schoolDetailMentioned: schoolDetailMentioned
        )
    }
}
