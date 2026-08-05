import XCTest
@testable import OctoTeacher

/// A93 iOS 创作者技能包量规与年龄适配安全壳测试。
///
/// 覆盖创作者/家长/孩子视角、年龄匹配、测验量规证据闭环、答案/评分裁剪、
/// 成长积分/设备承诺阻断、徽章/能力卡人工审核边界、市场购买文案阻断和只读副作用。
final class MobileCreatorSkillPackRubricAgeSuitabilityWorkbenchTests: XCTestCase {

    private func build(
        role: MobileCreatorSkillPackRubricViewerRole,
        draft: CreatorManifestPreviewDraft = .mock,
        childAge: Int = 10,
        answerKeyDraft: String? = nil,
        scoringRubricDraft: String? = nil,
        creatorAuditReason: String? = nil,
        directCreditPromise: Bool = false,
        deviceUnlockPromise: Bool = false,
        badgeBeforeEvidence: Bool = false,
        abilityCardBeforeEvidence: Bool = false,
        marketplacePurchaseCopy: String? = nil
    ) -> MobileCreatorSkillPackRubricAgeSuitabilityWorkbench {
        MobileCreatorSkillPackRubricAgeSuitabilityBuilder().build(
            role: role,
            draft: draft,
            childAge: childAge,
            answerKeyDraft: answerKeyDraft,
            scoringRubricDraft: scoringRubricDraft,
            creatorAuditReason: creatorAuditReason,
            directCreditPromise: directCreditPromise,
            deviceUnlockPromise: deviceUnlockPromise,
            badgeBeforeEvidence: badgeBeforeEvidence,
            abilityCardBeforeEvidence: abilityCardBeforeEvidence,
            marketplacePurchaseCopy: marketplacePurchaseCopy
        )
    }

    func testChildSeesAgeAppropriateLearningGoalsWithoutAdultRubricCreditOrMarketplaceCopy() {
        let workbench = build(role: .child)

        XCTAssertEqual(workbench.role, .child)
        XCTAssertFalse(workbench.rows.isEmpty)
        XCTAssertTrue(workbench.rows.allSatisfy(\.visibleToChild))
        XCTAssertTrue(workbench.findings.allSatisfy(\.visibleToChild))
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(workbench.hasUnsafeDisplayPayload)

        let text = workbench.displayValues.joined(separator: " ")
        for marker in [
            "15",
            "20",
            "答案",
            "answer",
            "评分细则",
            "审核原因",
            "成长积分金额",
            "购买",
            "市场发布",
            "设备命令",
            "解锁"
        ] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "孩子视角泄露: \(marker)")
        }
    }

    func testGuardianAndCreatorSeeReviewBoundariesWithoutSideEffects() {
        let guardian = build(role: .guardian)
        let creator = build(role: .creator)

        XCTAssertEqual(guardian.role, .guardian)
        XCTAssertEqual(creator.role, .creator)
        XCTAssertGreaterThan(guardian.publicSummary.visibleModuleCount, 0)
        XCTAssertGreaterThan(creator.publicSummary.visibleModuleCount, 0)
        XCTAssertTrue(guardian.findings.contains { $0.code == .readOnlyReady && !$0.actionRequired })
        XCTAssertTrue(creator.findings.contains { $0.code == .readOnlyReady && !$0.actionRequired })
        XCTAssertFalse(guardian.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(creator.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(guardian.publicSummary.writesLedger)
        XCTAssertFalse(creator.publicSummary.publishesMarketplace)
    }

    func testAgeTooYoungOrTooOldBlocksChildViewAndFlagsGuardianReview() {
        let tooYoungChild = build(role: .child, childAge: 6)
        let tooOldChild = build(role: .child, childAge: 14)
        let guardian = build(role: .guardian, childAge: 14)

        XCTAssertTrue(tooYoungChild.rows.isEmpty)
        XCTAssertTrue(tooOldChild.rows.isEmpty)
        XCTAssertEqual(tooYoungChild.publicSummary.visibleModuleCount, 0)
        XCTAssertGreaterThan(guardian.publicSummary.ageBlockedCount, 0)
        XCTAssertTrue(guardian.findings.contains { $0.code == .ageBandBlocked && $0.actionRequired })
        XCTAssertFalse(guardian.publicSummary.hasTriggeredSideEffect)
    }

    func testQuizRubricMissingEvidenceIsBlockedBeforePractice() {
        var draft = CreatorManifestPreviewDraft.mock
        let quizProofIndex = tryUnwrap(draft.proofRequirements.firstIndex { $0.proofId == "p-quiz-a" })
        draft.proofRequirements[quizProofIndex].evidenceRefsOnly = false

        let guardian = build(role: .guardian, draft: draft)
        let child = build(role: .child, draft: draft)

        XCTAssertGreaterThan(guardian.publicSummary.rubricEvidenceMissingCount, 0)
        XCTAssertTrue(guardian.findings.contains { $0.code == .rubricEvidenceMissing && $0.actionRequired })
        XCTAssertFalse(child.rows.contains { $0.title == "知识小测" })
        XCTAssertFalse(guardian.publicSummary.hasTriggeredSideEffect)
    }

    func testAnswerKeyScoringRubricAndCreatorAuditReasonNeverReachChildDisplay() {
        let child = build(
            role: .child,
            answerKeyDraft: "A equals photosynthesis",
            scoringRubricDraft: "five point internal scoring ladder",
            creatorAuditReason: "内部审核理由：需要修正题目"
        )
        let guardian = build(
            role: .guardian,
            answerKeyDraft: "A equals photosynthesis",
            scoringRubricDraft: "five point internal scoring ladder",
            creatorAuditReason: "内部审核理由：需要修正题目"
        )

        XCTAssertTrue(child.rows.isEmpty)
        XCTAssertTrue(guardian.findings.contains { $0.code == .answerAndScoringHidden && $0.actionRequired })

        let childText = child.displayValues.joined(separator: " ")
        for raw in ["photosynthesis", "five point", "内部审核理由", "需要修正题目"] {
            XCTAssertFalse(childText.localizedCaseInsensitiveContains(raw), "孩子视角泄露原始草稿: \(raw)")
        }
        XCTAssertFalse(guardian.publicSummary.hasTriggeredSideEffect)
    }

    func testDirectCreditLedgerOrDevicePromiseIsBlocked() {
        var draft = CreatorManifestPreviewDraft.mock
        draft.creditDrafts[0].requiresGuardianApproval = false
        draft.creditDrafts[0].writesLedger = true

        let guardian = build(
            role: .guardian,
            draft: draft,
            directCreditPromise: true,
            deviceUnlockPromise: true
        )
        let child = build(
            role: .child,
            draft: draft,
            directCreditPromise: true,
            deviceUnlockPromise: true
        )

        XCTAssertTrue(child.rows.isEmpty)
        XCTAssertGreaterThan(guardian.publicSummary.creditDevicePromiseBlockedCount, 0)
        XCTAssertTrue(guardian.findings.contains { $0.code == .creditDevicePromiseBlocked && $0.actionRequired })
        XCTAssertFalse(guardian.publicSummary.writesLedger)
        XCTAssertFalse(guardian.publicSummary.grantsCredit)
        XCTAssertFalse(guardian.publicSummary.unlocksDevice)
    }

    func testBadgeAndAbilityCardBeforeEvidenceAreBlockedAsDraftOnly() {
        let guardian = build(
            role: .guardian,
            badgeBeforeEvidence: true,
            abilityCardBeforeEvidence: true
        )

        XCTAssertGreaterThan(guardian.publicSummary.badgeAbilityEvidenceBlockedCount, 0)
        XCTAssertTrue(guardian.findings.contains { $0.code == .badgeAbilityEvidenceBlocked && $0.actionRequired })
        XCTAssertFalse(guardian.publicSummary.grantsBadge)
        XCTAssertFalse(guardian.publicSummary.mutatesAbilityCard)
        XCTAssertFalse(guardian.publicSummary.hasTriggeredSideEffect)
    }

    func testMarketplacePurchaseCopyIsBlockedWithoutPublishingOrCharging() {
        let creator = build(
            role: .creator,
            marketplacePurchaseCopy: "升级专属版后展示更多案例"
        )
        let child = build(
            role: .child,
            marketplacePurchaseCopy: "升级专属版后展示更多案例"
        )

        XCTAssertTrue(child.rows.isEmpty)
        XCTAssertGreaterThan(creator.publicSummary.marketplaceBlockedCount, 0)
        XCTAssertTrue(creator.findings.contains { $0.code == .marketplaceCopyBlocked && $0.actionRequired })
        XCTAssertFalse(creator.publicSummary.publishesMarketplace)
        XCTAssertFalse(creator.publicSummary.chargesPayment)

        let text = child.displayValues.joined(separator: " ")
        XCTAssertFalse(text.localizedCaseInsensitiveContains("专属版"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("案例"))
    }

    func testUnsafePayloadFallsBackWithoutEchoingRawManifestOrNetworkData() {
        var draft = CreatorManifestPreviewDraft.mock
        draft.contentBlocks[0].summary = "http://192.168.1.252 child:raw answerkey: secret"

        let workbench = build(role: .guardian, draft: draft)

        XCTAssertTrue(workbench.rows.isEmpty)
        XCTAssertEqual(workbench.publicSummary.findingCodes, [.unsafePayloadBlocked])
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)

        let text = workbench.displayValues.joined(separator: " ")
        for raw in ["192.168.1.252", "child:raw", "answerkey", "secret"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(raw), "fallback 泄露原文: \(raw)")
        }
    }

    func testPublicSummaryRowsNeverTriggerSideEffects() {
        for role in MobileCreatorSkillPackRubricViewerRole.allCases {
            let workbench = build(role: role)
            let summary = workbench.publicSummary

            XCTAssertFalse(summary.submitsReview)
            XCTAssertFalse(summary.publishesMarketplace)
            XCTAssertFalse(summary.chargesPayment)
            XCTAssertFalse(summary.writesEntitlement)
            XCTAssertFalse(summary.callsNetwork)
            XCTAssertFalse(summary.callsAI)
            XCTAssertFalse(summary.opensWebView)
            XCTAssertFalse(summary.writesLedger)
            XCTAssertFalse(summary.grantsCredit)
            XCTAssertFalse(summary.grantsBadge)
            XCTAssertFalse(summary.mutatesAbilityCard)
            XCTAssertFalse(summary.unlocksDevice)
            XCTAssertFalse(summary.hasTriggeredSideEffect)

            XCTAssertTrue(workbench.rows.allSatisfy { row in
                !row.submitsReview && !row.publishesMarketplace && !row.chargesPayment
                    && !row.writesEntitlement && !row.callsNetwork && !row.callsAI
                    && !row.opensWebView && !row.writesLedger && !row.grantsCredit
                    && !row.grantsBadge && !row.mutatesAbilityCard && !row.unlocksDevice
            })
        }
    }

    func testDisplayValuesDoNotLeakRawIdsOrSensitiveMarkers() {
        for role in MobileCreatorSkillPackRubricViewerRole.allCases {
            let text = build(role: role).displayValues.joined(separator: " ")
            for raw in [
                "manifest-sunrise-a",
                "creator-sunrise-a",
                "pack-sunrise-builder-a",
                "c-quiz-a",
                "p-quiz-a",
                "credit-quiz-a",
                "badge-science-a",
                "ability-creative-a"
            ] {
                XCTAssertFalse(text.contains(raw), "\(role.label) 泄露内部 seed: \(raw)")
            }
            for marker in ["http://", "https://", "file://", "/Users/", "/Volumes/", "192.168.", "child:", "rubric:", "quiz:", "credit:", "device:"] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "\(role.label) 泄露敏感标记: \(marker)")
            }
        }
    }

    @MainActor
    func testViewInitializersAndManifestPreviewEntryCompile() {
        _ = MobileCreatorSkillPackRubricAgeSuitabilityWorkbenchView()
        _ = MobileCreatorSkillPackRubricAgeSuitabilityWorkbenchView(initialRole: .child, allowedRoles: [.child])
        _ = MobileCreatorSkillPackRubricAgeSuitabilityWorkbenchView(initialRole: .guardian, allowedRoles: [.guardian])
        _ = MobileCreatorSkillPackRubricAgeSuitabilityWorkbenchView(initialRole: .creator, allowedRoles: [.creator])
        _ = CreatorManifestPreviewView()
    }

    private func tryUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) -> T {
        guard let value else {
            XCTFail("Expected value", file: file, line: line)
            fatalError("Expected value")
        }
        return value
    }
}
