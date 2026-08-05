import XCTest
@testable import OctoTeacher

final class MobileAbilityCardRegressionAppealExplanationPreviewTests: XCTestCase {

    private func build(
        role: MobileAbilityCardRegressionAppealExplanationPreviewRole,
        input: MobileAbilityCardRegressionAppealExplanationPreviewInput = .mock
    ) -> MobileAbilityCardRegressionAppealExplanationPreview {
        MobileAbilityCardRegressionAppealExplanationPreviewBuilder().build(role: role, input: input)
    }

    func testChildSeesGentleExplanationAndNextStepsWithoutAdultDetails() {
        let preview = build(role: .child)

        XCTAssertEqual(preview.role, .child)
        XCTAssertEqual(preview.publicSummary.entryCount, 11)
        // 孩子只看温和解释、申诉中 / 等待复核 / 继续努力 / 稳定优势。
        XCTAssertEqual(preview.publicSummary.visibleEntryCount, 5)
        XCTAssertEqual(preview.publicSummary.appealInProgressCount, 1)
        XCTAssertEqual(preview.publicSummary.waitingReviewCount, 1)
        XCTAssertEqual(preview.publicSummary.stableStrengthCount, 2)

        let visibleCategories = Set(preview.entries.map(\.category))
        XCTAssertTrue(visibleCategories.contains(.abilityRegression))
        XCTAssertTrue(visibleCategories.contains(.abilityCardFrozen))
        XCTAssertTrue(visibleCategories.contains(.appealReview))
        XCTAssertTrue(visibleCategories.contains(.stableStrength))
        // 孩子看不到成人审计类内容。
        XCTAssertFalse(visibleCategories.contains(.evidenceRevoked))
        XCTAssertFalse(visibleCategories.contains(.schoolHomeworkReturn))
        XCTAssertFalse(visibleCategories.contains(.wearableAnomaly))
        XCTAssertFalse(visibleCategories.contains(.creationRevoked))
        XCTAssertFalse(visibleCategories.contains(.visibilityBoundary))
        XCTAssertFalse(visibleCategories.contains(.sensitiveSummaryRisk))

        XCTAssertTrue(preview.findings.allSatisfy(\.visibleToChild))
        XCTAssertTrue(preview.findings.contains { $0.code == .appealInProgress })
        XCTAssertTrue(preview.findings.contains { $0.code == .waitingReview })
        XCTAssertTrue(preview.findings.contains { $0.code == .keepGoingEncouragement })
        // 孩子不应看到任何成人原因 finding。
        for forbiddenCode in [
            MobileAbilityCardRegressionAppealExplanationPreviewFindingCode.abilityReverted,
            .abilityCardFrozen, .evidenceRevoked, .homeworkReturned, .wearableAnomaly,
            .creationRevoked, .visibilityBoundary, .sensitiveSummaryRisk
        ] {
            XCTAssertFalse(preview.findings.contains { $0.code == forbiddenCode }, "\(forbiddenCode)")
        }

        XCTAssertFalse(preview.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(preview.hasUnsafeDisplayPayload)

        let text = preview.displayValues.joined(separator: " ")
        for forbidden in [
            "答案键", "answer key", "成长积分金额", "账本明细", "设备命令", "能力评分", "评分算法",
            "回退算法", "adultReason", "internalRef", "appeal:", "card:", "ability:", "proof:",
            "media:", "ledger:", "device:", "provider:", "model:", "transcript", "token",
            "http://", "https://", "/Users/"
        ] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(forbidden), forbidden)
        }
    }

    func testGuardianSeesFullRegressionAndAppealAudit() {
        let preview = build(role: .guardian)

        XCTAssertEqual(preview.role, .guardian)
        XCTAssertEqual(preview.publicSummary.visibleEntryCount, 11)
        XCTAssertEqual(preview.publicSummary.revertedCount, 1)
        XCTAssertEqual(preview.publicSummary.frozenCount, 1)
        XCTAssertEqual(preview.publicSummary.appealInProgressCount, 1)
        XCTAssertEqual(preview.publicSummary.evidenceRevokedCount, 1)
        XCTAssertEqual(preview.publicSummary.homeworkReturnCount, 1)
        XCTAssertEqual(preview.publicSummary.wearableAnomalyCount, 1)
        XCTAssertEqual(preview.publicSummary.creationRevokedCount, 1)
        XCTAssertEqual(preview.publicSummary.leakRiskCount, 1)

        for code in [
            MobileAbilityCardRegressionAppealExplanationPreviewFindingCode.abilityReverted,
            .abilityCardFrozen, .appealInProgress, .evidenceRevoked, .homeworkReturned,
            .wearableAnomaly, .creationRevoked, .visibilityBoundary, .sensitiveSummaryRisk
        ] {
            XCTAssertTrue(preview.findings.contains { $0.code == code && $0.actionRequired }, "\(code)")
        }
        // 家长不需要孩子专属鼓励 finding。
        XCTAssertFalse(preview.findings.contains { $0.code == .keepGoingEncouragement })
        XCTAssertFalse(preview.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(preview.hasUnsafeDisplayPayload)
    }

    func testRelativeSeesOnlyStableStrengthAndConsentedGrowth() {
        let preview = build(role: .relative)

        XCTAssertEqual(preview.publicSummary.visibleEntryCount, 2)
        let categories = Set(preview.entries.map(\.category))
        XCTAssertEqual(categories, [.stableStrength, .consentedPublicGrowth])
        // 亲友看不到任何回退 / 申诉 / 学校 / 家庭内部内容。
        XCTAssertFalse(preview.entries.contains { $0.isReverted || $0.isFrozen || $0.isAppealing })
        XCTAssertFalse(preview.entries.contains { $0.evidenceRevoked || $0.homeworkReturned || $0.wearableAnomaly || $0.creationRevoked || $0.leakRisk })
        // 亲友只看到只读说明，不看回退原因 finding。
        XCTAssertEqual(preview.findings.map(\.code), [.readOnlyPreview])
        let relativeFindingText = preview.findings.map(\.message).joined(separator: " ")
        for forbidden in ["回退", "冻结", "申诉", "学校", "作业", "家庭内部", "成长积分", "设备"] {
            XCTAssertFalse(relativeFindingText.localizedCaseInsensitiveContains(forbidden), forbidden)
        }
        XCTAssertFalse(preview.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(preview.hasUnsafeDisplayPayload)
    }

    func testTeacherSeesOnlySchoolHomeworkReturn() {
        let preview = build(role: .teacher)

        XCTAssertEqual(preview.publicSummary.visibleEntryCount, 1)
        XCTAssertEqual(preview.entries.map(\.category), [.schoolHomeworkReturn])
        XCTAssertEqual(preview.publicSummary.homeworkReturnCount, 1)
        // 老师看不到家庭成长积分 / 设备 / 亲友 / 回退 / 申诉内容。
        XCTAssertFalse(preview.entries.contains { $0.isReverted || $0.isFrozen || $0.isAppealing || $0.creationRevoked })
        XCTAssertEqual(preview.findings.map(\.code), [.readOnlyPreview])
        let teacherFindingText = preview.findings.map(\.message).joined(separator: " ")
        for forbidden in ["能力卡回退", "冻结", "申诉", "亲友", "成长积分", "设备"] {
            XCTAssertFalse(teacherFindingText.localizedCaseInsensitiveContains(forbidden), forbidden)
        }
        XCTAssertFalse(preview.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(preview.hasUnsafeDisplayPayload)
    }

    func testEntriesAreDeterministicallySortedAndRoleScopedRefs() {
        let preview = build(role: .guardian)
        let orders = preview.entries.map(\.sortOrder)
        XCTAssertEqual(orders, orders.sorted())

        // 同一角色重复构建结果稳定，不同角色 ref 不同。
        XCTAssertEqual(preview.entries.map(\.publicPreviewRef), build(role: .guardian).entries.map(\.publicPreviewRef))
        XCTAssertNotEqual(
            Set(preview.entries.map(\.publicPreviewRef)),
            Set(build(role: .child).entries.map(\.publicPreviewRef))
        )
    }

    func testPublicRefsAreStableAndRedacted() {
        let preview = build(role: .guardian)
        let refs = preview.entries.map(\.publicPreviewRef)

        XCTAssertEqual(Set(refs).count, refs.count)
        XCTAssertTrue(preview.entries.allSatisfy { $0.publicPreviewRef.hasPrefix("acr-") })
        for value in preview.displayValues {
            for forbidden in ["child:", "family:", "school:", "teacher:", "guardian:", "relative:", "proof:", "media:", "card:", "ability:", "appeal:", "ledger:", "device:", "token", "192.168.", ".local", "/Volumes/"] {
                XCTAssertFalse(value.localizedCaseInsensitiveContains(forbidden), "\(value) contains \(forbidden)")
            }
        }
    }

    func testUnsafePayloadHidesPreviewWithoutEchoingRawValue() {
        let preview = build(
            role: .guardian,
            input: MobileAbilityCardRegressionAppealExplanationPreviewInput(
                generatedAt: "2026-06-25T03:00:00.000Z",
                unsafePayload: "card:raw ability:score appeal:raw proof:raw provider:model transcript token http://example.invalid"
            )
        )

        XCTAssertTrue(preview.entries.isEmpty)
        XCTAssertEqual(preview.publicSummary.findingCodes, [.unsafePayloadBlocked])
        XCTAssertFalse(preview.displayValues.joined(separator: " ").localizedCaseInsensitiveContains("example.invalid"))
        XCTAssertFalse(preview.publicSummary.hasTriggeredSideEffect)
    }

    func testAdultReasonAndInternalRefsHidePreviewWithoutEchoingRawValue() {
        let preview = build(
            role: .guardian,
            input: MobileAbilityCardRegressionAppealExplanationPreviewInput(
                generatedAt: "2026-06-25T03:00:00.000Z",
                unsafePayload: "adultReason=manual regression internalRef=ref_secret child_real appeal_real"
            )
        )

        XCTAssertTrue(preview.entries.isEmpty)
        XCTAssertEqual(preview.publicSummary.findingCodes, [.unsafePayloadBlocked])
        XCTAssertFalse(preview.displayValues.joined(separator: " ").localizedCaseInsensitiveContains("manual regression"))
        XCTAssertFalse(preview.displayValues.joined(separator: " ").localizedCaseInsensitiveContains("ref_secret"))
        XCTAssertFalse(preview.publicSummary.hasTriggeredSideEffect)
    }

    func testAllRolesRemainReadOnly() {
        for role in MobileAbilityCardRegressionAppealExplanationPreviewRole.allCases {
            let preview = build(role: role)

            XCTAssertFalse(preview.publicSummary.callsNetwork)
            XCTAssertFalse(preview.publicSummary.callsAiProvider)
            XCTAssertFalse(preview.publicSummary.callsLocalModel)
            XCTAssertFalse(preview.publicSummary.callsLms)
            XCTAssertFalse(preview.publicSummary.writesSchoolSystem)
            XCTAssertFalse(preview.publicSummary.revertsAbilityCard)
            XCTAssertFalse(preview.publicSummary.lowersAbilityScore)
            XCTAssertFalse(preview.publicSummary.processesAppeal)
            XCTAssertFalse(preview.publicSummary.revokesEvidence)
            XCTAssertFalse(preview.publicSummary.returnsHomework)
            XCTAssertFalse(preview.publicSummary.verifiesTeacher)
            XCTAssertFalse(preview.publicSummary.confirmsGuardian)
            XCTAssertFalse(preview.publicSummary.notifiesRelative)
            XCTAssertFalse(preview.publicSummary.writesLedger)
            XCTAssertFalse(preview.publicSummary.grantsCredit)
            XCTAssertFalse(preview.publicSummary.spendsCredit)
            XCTAssertFalse(preview.publicSummary.fulfillsReward)
            XCTAssertFalse(preview.publicSummary.controlsScreenTime)
            XCTAssertFalse(preview.publicSummary.unlocksDevice)
            XCTAssertFalse(preview.publicSummary.publishesContent)
            XCTAssertFalse(preview.publicSummary.sendsNotification)
            XCTAssertFalse(preview.publicSummary.submitsProof)
            XCTAssertFalse(preview.publicSummary.hasTriggeredSideEffect)

            XCTAssertTrue(preview.entries.allSatisfy { !$0.hasTriggeredSideEffect })
        }
    }

    @MainActor
    func testViewInitializersCompileWithLockedRoles() {
        _ = MobileAbilityCardRegressionAppealExplanationPreviewView()
        _ = MobileAbilityCardRegressionAppealExplanationPreviewView(initialRole: .child, allowedRoles: [.child])
        _ = MobileAbilityCardRegressionAppealExplanationPreviewView(initialRole: .guardian, allowedRoles: [.guardian, .relative, .teacher])
        _ = MobileAbilityCardRegressionAppealExplanationPreviewView(initialRole: .teacher, allowedRoles: [.teacher])
        // 入口仍由成就卡预览承载，且只传角色与安全枚举，不触发任何副作用。
        _ = MobileGrowthPackAchievementCardPreviewView(initialRole: .child, allowedRoles: [.child])
        _ = MobileGrowthPackAchievementCardPreviewView(initialRole: .guardian, allowedRoles: [.guardian])
    }
}
