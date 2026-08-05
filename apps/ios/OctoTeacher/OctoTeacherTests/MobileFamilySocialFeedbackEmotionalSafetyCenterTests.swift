import XCTest
@testable import OctoTeacher

final class MobileFamilySocialFeedbackEmotionalSafetyCenterTests: XCTestCase {

    private func build(
        role: MobileFamilySocialFeedbackEmotionalSafetyCenterRole,
        input: MobileFamilySocialFeedbackEmotionalSafetyCenterInput = .mock
    ) -> MobileFamilySocialFeedbackEmotionalSafetyCenter {
        MobileFamilySocialFeedbackEmotionalSafetyCenterBuilder().build(role: role, input: input)
    }

    func testChildSeesGentleSupportWithoutAdultReasons() {
        let preview = build(role: .child)

        XCTAssertEqual(preview.role, .child)
        XCTAssertEqual(preview.publicSummary.itemCount, 8)
        // 孩子看不到专家 / 家长讨论与亲友越权，所以可见数少于家长。
        XCTAssertEqual(preview.publicSummary.visibleItemCount, 8)
        XCTAssertEqual(preview.publicSummary.findingCodes, [])
        XCTAssertFalse(preview.items.contains { $0.channel == .expertTopicDiscussion })
        XCTAssertFalse(preview.items.contains { $0.channel == .parentTopicDiscussion })
        XCTAssertFalse(preview.items.contains(where: \.relativeOverscope))
        XCTAssertTrue(preview.findings.allSatisfy(\.visibleToChild))

        // 孩子不应看到任何成人内部原因 finding。
        for adultCode in [
            MobileFamilySocialFeedbackEmotionalSafetyCenterFindingCode.guardianConsentMissing,
            .childAssentMissing,
            .moderationRequired,
            .pressureLanguageRisk,
            .rewardPromiseRisk,
            .creditAmountLeakRisk,
            .expertDiscussionLeakRisk,
            .crossChildLeakRisk,
            .relativeOverscope,
            .diaryVlogContinuityGap,
            .notificationEmotionalSafetyRisk,
            .minimalDisclosureRisk,
            .publicSummaryLeak
        ] {
            XCTAssertFalse(preview.findings.contains { $0.code == adultCode }, "\(adultCode)")
        }
        // 孩子看到温和支持与休息 / 继续努力下一步。
        XCTAssertTrue(preview.findings.contains { $0.code == .gentleSupportOnly })
        XCTAssertTrue(preview.findings.contains { $0.code == .restOrKeepGoing })
        XCTAssertTrue(preview.findings.contains { $0.code == .waitingGuardianReview })
        XCTAssertTrue(preview.findings.contains { $0.code == .contentUnderReview })
        XCTAssertTrue(preview.findings.contains { $0.code == .contentRevoked })
        XCTAssertTrue(preview.findings.contains { $0.code == .contentRemoved })
        XCTAssertFalse(preview.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(preview.hasUnsafeDisplayPayload)

        let text = preview.displayValues.joined(separator: " ")
        for forbidden in [
            "答案键", "answer key", "成长积分金额", "账本明细", "设备命令", "家长预算", "复核策略",
            "adultReason", "internalRef", "comment:", "vlog:", "diary:", "proof:", "media:",
            "ledger:", "device:", "provider:", "model:", "transcript", "token",
            "http://", "https://", "/Users/", "192.168."
        ] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(forbidden), forbidden)
        }
    }

    func testNonGuardianSummariesHideInternalRiskCounts() {
        for role in [
            MobileFamilySocialFeedbackEmotionalSafetyCenterRole.child,
            .relative,
            .expert
        ] {
            let preview = build(role: role)

            XCTAssertEqual(preview.publicSummary.itemCount, preview.publicSummary.visibleItemCount, "\(role)")
            XCTAssertEqual(preview.publicSummary.findingCodes, [], "\(role)")
            XCTAssertEqual(preview.publicSummary.moderationRequiredCount, 0, "\(role)")
            XCTAssertEqual(preview.publicSummary.revokedCount, 0, "\(role)")
            XCTAssertEqual(preview.publicSummary.removedCount, 0, "\(role)")
            XCTAssertEqual(preview.publicSummary.blockedCount, 0, "\(role)")
            XCTAssertEqual(preview.publicSummary.guardianConsentMissingCount, 0, "\(role)")
            XCTAssertEqual(preview.publicSummary.childAssentMissingCount, 0, "\(role)")
            XCTAssertEqual(preview.publicSummary.pressureLanguageRiskCount, 0, "\(role)")
            XCTAssertEqual(preview.publicSummary.rewardPromiseRiskCount, 0, "\(role)")
            XCTAssertEqual(preview.publicSummary.creditAmountLeakRiskCount, 0, "\(role)")
            XCTAssertEqual(preview.publicSummary.expertDiscussionLeakRiskCount, 0, "\(role)")
            XCTAssertEqual(preview.publicSummary.crossChildLeakRiskCount, 0, "\(role)")
            XCTAssertEqual(preview.publicSummary.continuityGapCount, 0, "\(role)")
            XCTAssertEqual(preview.publicSummary.notificationRiskCount, 0, "\(role)")
            XCTAssertEqual(preview.publicSummary.minimalDisclosureRiskCount, 0, "\(role)")
            XCTAssertEqual(preview.publicSummary.relativeOverscopeCount, 0, "\(role)")
        }
    }

    func testGuardianSeesEmotionalSafetyAndModerationRisks() {
        let preview = build(role: .guardian)

        XCTAssertEqual(preview.role, .guardian)
        XCTAssertEqual(preview.publicSummary.itemCount, 11)
        XCTAssertEqual(preview.publicSummary.visibleItemCount, 11)
        XCTAssertGreaterThanOrEqual(preview.publicSummary.guardianConsentMissingCount, 1)
        XCTAssertGreaterThanOrEqual(preview.publicSummary.childAssentMissingCount, 1)
        XCTAssertGreaterThanOrEqual(preview.publicSummary.moderationRequiredCount, 1)
        XCTAssertGreaterThanOrEqual(preview.publicSummary.pressureLanguageRiskCount, 1)
        XCTAssertGreaterThanOrEqual(preview.publicSummary.rewardPromiseRiskCount, 1)
        XCTAssertGreaterThanOrEqual(preview.publicSummary.creditAmountLeakRiskCount, 1)
        XCTAssertGreaterThanOrEqual(preview.publicSummary.expertDiscussionLeakRiskCount, 1)
        XCTAssertGreaterThanOrEqual(preview.publicSummary.crossChildLeakRiskCount, 1)
        XCTAssertGreaterThanOrEqual(preview.publicSummary.continuityGapCount, 1)
        XCTAssertGreaterThanOrEqual(preview.publicSummary.notificationRiskCount, 1)
        XCTAssertGreaterThanOrEqual(preview.publicSummary.relativeOverscopeCount, 1)

        for code in [
            MobileFamilySocialFeedbackEmotionalSafetyCenterFindingCode.guardianConsentMissing,
            .childAssentMissing,
            .moderationRequired,
            .pressureLanguageRisk,
            .rewardPromiseRisk,
            .creditAmountLeakRisk,
            .expertDiscussionLeakRisk,
            .crossChildLeakRisk,
            .diaryVlogContinuityGap,
            .notificationEmotionalSafetyRisk,
            .relativeOverscope,
            .minimalDisclosureRisk,
            .publicSummaryLeak
        ] {
            XCTAssertTrue(preview.findings.contains { $0.code == code && $0.actionRequired }, "\(code)")
        }
        XCTAssertFalse(preview.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(preview.hasUnsafeDisplayPayload)
    }

    func testRelativeOnlySeesExpressionGuidanceAndOwnEncouragement() {
        let preview = build(role: .relative)

        XCTAssertEqual(preview.role, .relative)
        // 亲友只看到自己的亲友鼓励（待审核 / 已通过）。
        XCTAssertEqual(preview.publicSummary.visibleItemCount, 2)
        XCTAssertTrue(preview.items.allSatisfy { $0.channel == .relativeEncouragement })
        XCTAssertTrue(preview.items.allSatisfy { $0.status == .waitingReview || $0.status == .relativeVisible })
        XCTAssertTrue(preview.items.allSatisfy(\.visibleToRelative))
        // 亲友看不到孩子私密日记、越权、撤回、删除、审核原因等。
        XCTAssertFalse(preview.items.contains { $0.channel == .diaryVlogContinuity })
        XCTAssertFalse(preview.items.contains { $0.isRevoked || $0.isRemoved || $0.relativeOverscope })
        XCTAssertTrue(preview.findings.allSatisfy(\.visibleToRelative))
        XCTAssertTrue(preview.findings.contains { $0.code == .relativeExpressionGuidance })
        XCTAssertTrue(preview.findings.contains { $0.code == .relativeScopeApplied })
        for adultCode in [
            MobileFamilySocialFeedbackEmotionalSafetyCenterFindingCode.guardianConsentMissing,
            .moderationRequired,
            .pressureLanguageRisk,
            .rewardPromiseRisk,
            .creditAmountLeakRisk,
            .crossChildLeakRisk
        ] {
            XCTAssertFalse(preview.findings.contains { $0.code == adultCode }, "\(adultCode)")
        }
        XCTAssertFalse(preview.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(preview.hasUnsafeDisplayPayload)
    }

    func testExpertOnlySeesGenericTopicBoundary() {
        let preview = build(role: .expert)

        XCTAssertEqual(preview.role, .expert)
        // 专家只看到通用主题建议边界。
        XCTAssertEqual(preview.publicSummary.visibleItemCount, 1)
        XCTAssertTrue(preview.items.allSatisfy { $0.channel == .expertTopicDiscussion })
        XCTAssertTrue(preview.items.allSatisfy { $0.status == .expertBoundary })
        XCTAssertTrue(preview.items.allSatisfy(\.visibleToExpert))
        // 专家看不到孩子私密内容、家长讨论、亲友鼓励、日记 / VLOG、通知等。
        XCTAssertFalse(preview.items.contains { $0.channel == .parentTopicDiscussion })
        XCTAssertFalse(preview.items.contains { $0.channel == .relativeEncouragement })
        XCTAssertFalse(preview.items.contains { $0.channel == .diaryVlogContinuity })
        XCTAssertTrue(preview.findings.allSatisfy(\.visibleToExpert))
        XCTAssertTrue(preview.findings.contains { $0.code == .expertTopicBoundaryApplied })
        // 专家看不到任何家长内部 finding 或孩子温和提示。
        for hiddenCode in [
            MobileFamilySocialFeedbackEmotionalSafetyCenterFindingCode.gentleSupportOnly,
            .restOrKeepGoing,
            .crossChildLeakRisk,
            .expertDiscussionLeakRisk,
            .relativeExpressionGuidance
        ] {
            XCTAssertFalse(preview.findings.contains { $0.code == hiddenCode }, "\(hiddenCode)")
        }
        XCTAssertFalse(preview.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(preview.hasUnsafeDisplayPayload)
    }

    func testChildFacingStatusLabelsStayGentle() {
        let preview = build(role: .child)
        let labels = preview.items.map(\.statusDisplayLabel)

        XCTAssertTrue(labels.contains("等家长看"))
        XCTAssertTrue(labels.contains("先收起来"))

        for harshLabel in ["需审核", "已撤回", "已删除", "先暂停"] {
            XCTAssertFalse(labels.contains(harshLabel), harshLabel)
        }

        let childDisplayText = preview.displayValues.joined(separator: " ")
        for rawMarker in [
            "needs_moderation", "revoked", "removed", "on_hold",
            "CONTENT_REVOKED", "CONTENT_REMOVED", "CONTENT_UNDER_REVIEW", "FEEDBACK_ON_HOLD"
        ] {
            XCTAssertFalse(childDisplayText.localizedCaseInsensitiveContains(rawMarker), rawMarker)
        }
    }

    func testItemsAreDeterministicallySortedAndRefsStablePerRole() {
        let preview = build(role: .guardian)

        let orders = preview.items.map(\.sortOrder)
        XCTAssertEqual(orders, orders.sorted())

        XCTAssertEqual(
            preview.items.map(\.publicPreviewRef),
            build(role: .guardian).items.map(\.publicPreviewRef)
        )
        XCTAssertNotEqual(
            preview.items.map(\.publicPreviewRef),
            build(role: .child).items.map(\.publicPreviewRef)
        )
    }

    func testPublicRefsAreStableAndRedacted() {
        let preview = build(role: .guardian)
        let refs = preview.items.map(\.publicPreviewRef)

        XCTAssertEqual(Set(refs).count, refs.count)
        XCTAssertTrue(preview.items.allSatisfy { $0.publicPreviewRef.hasPrefix("fse-") })
        for value in preview.displayValues {
            for forbidden in [
                "child:", "family:", "school:", "teacher:", "guardian:", "relative:", "expert:",
                "proof:", "media:", "comment:", "vlog:", "diary:", "discussion:", "ledger:",
                "device:", "token", "192.168.", ".local", "/Volumes/"
            ] {
                XCTAssertFalse(value.localizedCaseInsensitiveContains(forbidden), "\(value) contains \(forbidden)")
            }
        }
    }

    func testUnsafePayloadHidesPreviewWithoutEchoingRawValue() {
        let preview = build(
            role: .guardian,
            input: MobileFamilySocialFeedbackEmotionalSafetyCenterInput(
                generatedAt: "2026-06-25T02:00:00.000Z",
                unsafePayload: "comment:raw vlog:raw diary:raw provider:model transcript token http://example.invalid"
            )
        )

        XCTAssertTrue(preview.items.isEmpty)
        XCTAssertEqual(preview.publicSummary.blockedCount, 1)
        XCTAssertEqual(preview.publicSummary.findingCodes, [.unsafePayloadBlocked])
        XCTAssertFalse(preview.displayValues.joined(separator: " ").localizedCaseInsensitiveContains("example.invalid"))
        XCTAssertFalse(preview.publicSummary.hasTriggeredSideEffect)
    }

    func testAdultReasonAndInternalRefsHidePreviewWithoutEchoingRawValue() {
        let preview = build(
            role: .guardian,
            input: MobileFamilySocialFeedbackEmotionalSafetyCenterInput(
                generatedAt: "2026-06-25T02:00:00.000Z",
                unsafePayload: "adultReason=manual review internalRef=ref_secret child_real comment_real"
            )
        )

        XCTAssertTrue(preview.items.isEmpty)
        XCTAssertEqual(preview.publicSummary.findingCodes, [.unsafePayloadBlocked])
        XCTAssertFalse(preview.displayValues.joined(separator: " ").localizedCaseInsensitiveContains("manual review"))
        XCTAssertFalse(preview.displayValues.joined(separator: " ").localizedCaseInsensitiveContains("ref_secret"))
        XCTAssertFalse(preview.publicSummary.hasTriggeredSideEffect)
    }

    func testAllRolesAndItemsRemainReadOnly() {
        for role in MobileFamilySocialFeedbackEmotionalSafetyCenterRole.allCases {
            let preview = build(role: role)

            XCTAssertFalse(preview.publicSummary.callsNetwork)
            XCTAssertFalse(preview.publicSummary.callsAiProvider)
            XCTAssertFalse(preview.publicSummary.callsLocalModel)
            XCTAssertFalse(preview.publicSummary.callsLms)
            XCTAssertFalse(preview.publicSummary.writesSchoolSystem)
            XCTAssertFalse(preview.publicSummary.opensExternalLink)
            XCTAssertFalse(preview.publicSummary.opensCamera)
            XCTAssertFalse(preview.publicSummary.opensPhotoLibrary)
            XCTAssertFalse(preview.publicSummary.opensFilePicker)
            XCTAssertFalse(preview.publicSummary.uploadsMedia)
            XCTAssertFalse(preview.publicSummary.writesLedger)
            XCTAssertFalse(preview.publicSummary.grantsCredit)
            XCTAssertFalse(preview.publicSummary.spendsCredit)
            XCTAssertFalse(preview.publicSummary.fulfillsReward)
            XCTAssertFalse(preview.publicSummary.grantsBadge)
            XCTAssertFalse(preview.publicSummary.publishesHonorWall)
            XCTAssertFalse(preview.publicSummary.publishesContent)
            XCTAssertFalse(preview.publicSummary.postsComment)
            XCTAssertFalse(preview.publicSummary.moderatesContent)
            XCTAssertFalse(preview.publicSummary.approvesStoryline)
            XCTAssertFalse(preview.publicSummary.governsDiscussion)
            XCTAssertFalse(preview.publicSummary.reviewsCreativeWork)
            XCTAssertFalse(preview.publicSummary.notifiesRelatives)
            XCTAssertFalse(preview.publicSummary.notifiesChild)
            XCTAssertFalse(preview.publicSummary.unlocksDevice)
            XCTAssertFalse(preview.publicSummary.controlsScreenTime)
            XCTAssertFalse(preview.publicSummary.sendsNotification)
            XCTAssertFalse(preview.publicSummary.submitsProof)
            XCTAssertFalse(preview.publicSummary.hasTriggeredSideEffect)

            XCTAssertTrue(preview.items.allSatisfy { !$0.hasTriggeredSideEffect })
            XCTAssertFalse(preview.hasUnsafeDisplayPayload)
        }
    }

    @MainActor
    func testViewInitializersCompileWithLockedRoles() {
        _ = MobileFamilySocialFeedbackEmotionalSafetyCenterView()
        _ = MobileFamilySocialFeedbackEmotionalSafetyCenterView(initialRole: .child, allowedRoles: [.child])
        _ = MobileFamilySocialFeedbackEmotionalSafetyCenterView(initialRole: .guardian, allowedRoles: [.guardian, .relative, .expert])
        _ = MobileFamilySocialFeedbackEmotionalSafetyCenterView(initialRole: .relative, allowedRoles: [.relative])
        _ = MobileFamilySocialFeedbackEmotionalSafetyCenterView(initialRole: .expert, allowedRoles: [.expert])
        // 入口由亲友评论安全壳、成长日记 / VLOG 工作台与荣誉墙发布预览承载，只传角色与安全枚举。
        _ = MobileRelativeCreativeCommentSafetyWorkbenchView(initialRole: .child, allowedRoles: [.child])
        _ = GrowthDiaryVlogStorylineWorkbenchView(initialRole: .guardian, allowedRoles: [.guardian])
        _ = MobileHonorWallBadgeStorylinePublicationPreviewView(initialRole: .guardian, allowedRoles: [.guardian, .relative])
    }
}
