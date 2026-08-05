import XCTest
@testable import OctoTeacher

final class MobileHonorWallBadgeStorylinePublicationPreviewTests: XCTestCase {

    private func build(
        role: MobileHonorWallBadgeStorylinePublicationPreviewRole,
        input: MobileHonorWallBadgeStorylinePublicationPreviewInput = .mock
    ) -> MobileHonorWallBadgeStorylinePublicationPreview {
        MobileHonorWallBadgeStorylinePublicationPreviewBuilder().build(role: role, input: input)
    }

    func testChildSeesGentleStatusesWithoutAdultReasons() {
        let preview = build(role: .child)

        XCTAssertEqual(preview.role, .child)
        XCTAssertEqual(preview.publicSummary.candidateCount, 8)
        // 孩子看不到亲友越权候选，所以可见数比家长少。
        XCTAssertEqual(preview.publicSummary.visibleCandidateCount, 7)
        XCTAssertFalse(preview.candidates.contains { $0.relativeOverscope })
        XCTAssertTrue(preview.findings.allSatisfy(\.visibleToChild))
        // 孩子不应看到任何成人内部原因 finding。
        for adultCode in [
            MobileHonorWallBadgeStorylinePublicationPreviewFindingCode.guardianConsentMissing,
            .childAssentMissing,
            .moderationRequired,
            .revokedStillVisible,
            .deletedNotRolledBack,
            .relativeOverscope,
            .storylineSensitiveLeak,
            .publicSummaryLeak,
            .duplicateNotCollapsed
        ] {
            XCTAssertFalse(preview.findings.contains { $0.code == adultCode }, "\(adultCode)")
        }
        // 孩子能看到温和的状态提示。
        XCTAssertTrue(preview.findings.contains { $0.code == .waitingConfirmation })
        XCTAssertTrue(preview.findings.contains { $0.code == .contentUnderReview })
        XCTAssertTrue(preview.findings.contains { $0.code == .contentRevoked })
        XCTAssertTrue(preview.findings.contains { $0.code == .contentTakenDown })
        XCTAssertTrue(preview.findings.contains { $0.code == .publicationOnHold })
        XCTAssertFalse(preview.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(preview.hasUnsafeDisplayPayload)

        let text = preview.displayValues.joined(separator: " ")
        for forbidden in [
            "答案键", "answer key", "成长积分金额", "账本明细", "设备命令", "家长预算", "复核策略",
            "adultReason", "internalRef", "badge:", "card:", "story:", "proof:", "media:",
            "ledger:", "device:", "provider:", "model:", "transcript", "token",
            "http://", "https://", "/Users/", "192.168."
        ] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(forbidden), forbidden)
        }
    }

    func testGuardianSeesGapsConsentModerationRollbackAndLeakRisks() {
        let preview = build(role: .guardian)

        XCTAssertEqual(preview.role, .guardian)
        XCTAssertEqual(preview.publicSummary.visibleCandidateCount, 8)
        XCTAssertGreaterThanOrEqual(preview.publicSummary.guardianConsentMissingCount, 1)
        XCTAssertGreaterThanOrEqual(preview.publicSummary.childAssentMissingCount, 1)
        XCTAssertGreaterThanOrEqual(preview.publicSummary.moderationRequiredCount, 1)
        XCTAssertGreaterThanOrEqual(preview.publicSummary.relativeOverscopeCount, 1)
        XCTAssertGreaterThanOrEqual(preview.publicSummary.storylineLeakRiskCount, 1)
        XCTAssertGreaterThanOrEqual(preview.publicSummary.publicSummaryLeakRiskCount, 1)

        for code in [
            MobileHonorWallBadgeStorylinePublicationPreviewFindingCode.guardianConsentMissing,
            .childAssentMissing,
            .moderationRequired,
            .revokedStillVisible,
            .deletedNotRolledBack,
            .relativeOverscope,
            .storylineSensitiveLeak,
            .publicSummaryLeak,
            .duplicateNotCollapsed
        ] {
            XCTAssertTrue(preview.findings.contains { $0.code == code && $0.actionRequired }, "\(code)")
        }
        XCTAssertFalse(preview.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(preview.hasUnsafeDisplayPayload)
    }

    func testRelativeOnlySeesConsentedInScopeEncouragement() {
        let preview = build(role: .relative)

        XCTAssertEqual(preview.role, .relative)
        // 亲友只看到已同意且授权范围内的鼓励候选。
        XCTAssertEqual(preview.publicSummary.visibleCandidateCount, 1)
        XCTAssertTrue(preview.candidates.allSatisfy { $0.sourceKind == .relativeEncouragement })
        XCTAssertTrue(preview.candidates.allSatisfy { $0.status == .relativeVisible })
        XCTAssertTrue(preview.candidates.allSatisfy(\.visibleToRelative))
        // 亲友看不到任何缺口、越权、撤回、下架或审核中的候选。
        XCTAssertFalse(preview.candidates.contains { $0.guardianConsentMissing || $0.childAssentMissing })
        XCTAssertFalse(preview.candidates.contains { $0.moderationRequired || $0.isRevoked || $0.isTakenDown })
        XCTAssertFalse(preview.candidates.contains(where: \.relativeOverscope))
        // 亲友只看到只读说明 + 授权范围提示，不看到任何成人内部 finding。
        XCTAssertTrue(preview.findings.allSatisfy(\.visibleToRelative))
        XCTAssertTrue(preview.findings.contains { $0.code == .relativeScopeApplied })
        for adultCode in [
            MobileHonorWallBadgeStorylinePublicationPreviewFindingCode.guardianConsentMissing,
            .childAssentMissing,
            .relativeOverscope,
            .storylineSensitiveLeak,
            .publicSummaryLeak
        ] {
            XCTAssertFalse(preview.findings.contains { $0.code == adultCode }, "\(adultCode)")
        }
        XCTAssertFalse(preview.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(preview.hasUnsafeDisplayPayload)
    }

    func testCandidatesAreDeterministicallySortedAndRefsStablePerRole() {
        let preview = build(role: .guardian)

        let orders = preview.candidates.map(\.sortOrder)
        XCTAssertEqual(orders, orders.sorted())

        // 同角色重复构建稳定，不同角色 ref 不同。
        XCTAssertEqual(
            preview.candidates.map(\.publicPreviewRef),
            build(role: .guardian).candidates.map(\.publicPreviewRef)
        )
        XCTAssertNotEqual(
            preview.candidates.map(\.publicPreviewRef),
            build(role: .child).candidates.map(\.publicPreviewRef)
        )
    }

    func testPublicRefsAreStableAndRedacted() {
        let preview = build(role: .guardian)
        let refs = preview.candidates.map(\.publicPreviewRef)

        XCTAssertEqual(Set(refs).count, refs.count)
        XCTAssertTrue(preview.candidates.allSatisfy { $0.publicPreviewRef.hasPrefix("hwp-") })
        for value in preview.displayValues {
            for forbidden in [
                "child:", "family:", "school:", "teacher:", "guardian:", "relative:",
                "proof:", "media:", "badge:", "card:", "story:", "honor:", "ledger:",
                "device:", "token", "192.168.", ".local", "/Volumes/"
            ] {
                XCTAssertFalse(value.localizedCaseInsensitiveContains(forbidden), "\(value) contains \(forbidden)")
            }
        }
    }

    func testUnsafePayloadHidesPreviewWithoutEchoingRawValue() {
        let preview = build(
            role: .guardian,
            input: MobileHonorWallBadgeStorylinePublicationPreviewInput(
                generatedAt: "2026-06-25T02:00:00.000Z",
                unsafePayload: "badge:raw story:raw proof:raw provider:model transcript token http://example.invalid"
            )
        )

        XCTAssertTrue(preview.candidates.isEmpty)
        XCTAssertEqual(preview.publicSummary.blockedCount, 1)
        XCTAssertEqual(preview.publicSummary.findingCodes, [.unsafePayloadBlocked])
        XCTAssertFalse(preview.displayValues.joined(separator: " ").localizedCaseInsensitiveContains("example.invalid"))
        XCTAssertFalse(preview.publicSummary.hasTriggeredSideEffect)
    }

    func testAdultReasonAndInternalRefsHidePreviewWithoutEchoingRawValue() {
        let preview = build(
            role: .guardian,
            input: MobileHonorWallBadgeStorylinePublicationPreviewInput(
                generatedAt: "2026-06-25T02:00:00.000Z",
                unsafePayload: "adultReason=manual review internalRef=ref_secret child_real story_real"
            )
        )

        XCTAssertTrue(preview.candidates.isEmpty)
        XCTAssertEqual(preview.publicSummary.findingCodes, [.unsafePayloadBlocked])
        XCTAssertFalse(preview.displayValues.joined(separator: " ").localizedCaseInsensitiveContains("manual review"))
        XCTAssertFalse(preview.displayValues.joined(separator: " ").localizedCaseInsensitiveContains("ref_secret"))
        XCTAssertFalse(preview.publicSummary.hasTriggeredSideEffect)
    }

    func testAllRolesAndCandidatesRemainReadOnly() {
        for role in MobileHonorWallBadgeStorylinePublicationPreviewRole.allCases {
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
            XCTAssertFalse(preview.publicSummary.updatesAbilityCard)
            XCTAssertFalse(preview.publicSummary.publishesHonorWall)
            XCTAssertFalse(preview.publicSummary.publishesContent)
            XCTAssertFalse(preview.publicSummary.reviewsCreativeWork)
            XCTAssertFalse(preview.publicSummary.notifiesRelatives)
            XCTAssertFalse(preview.publicSummary.unlocksDevice)
            XCTAssertFalse(preview.publicSummary.controlsScreenTime)
            XCTAssertFalse(preview.publicSummary.sendsNotification)
            XCTAssertFalse(preview.publicSummary.submitsProof)
            XCTAssertFalse(preview.publicSummary.hasTriggeredSideEffect)

            XCTAssertTrue(preview.candidates.allSatisfy { !$0.hasTriggeredSideEffect })
            XCTAssertFalse(preview.hasUnsafeDisplayPayload)
        }
    }

    @MainActor
    func testViewInitializersCompileWithLockedRoles() {
        _ = MobileHonorWallBadgeStorylinePublicationPreviewView()
        _ = MobileHonorWallBadgeStorylinePublicationPreviewView(initialRole: .child, allowedRoles: [.child])
        _ = MobileHonorWallBadgeStorylinePublicationPreviewView(initialRole: .guardian, allowedRoles: [.guardian, .relative])
        _ = MobileHonorWallBadgeStorylinePublicationPreviewView(initialRole: .relative, allowedRoles: [.relative])
        // 入口由徽章能力卡预览与执行中心承载，只传角色与安全枚举，不触发任何副作用。
        _ = MobileGrowthPackAchievementCardPreviewView(initialRole: .child, allowedRoles: [.child])
        _ = MobileGrowthPackExecutionHubView(initialRole: .guardian, allowedRoles: [.guardian])
    }
}
