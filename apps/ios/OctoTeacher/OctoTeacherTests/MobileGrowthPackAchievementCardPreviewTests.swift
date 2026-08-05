import XCTest
@testable import OctoTeacher

final class MobileGrowthPackAchievementCardPreviewTests: XCTestCase {

    private func build(
        role: MobileGrowthPackExecutionHubRole,
        input: MobileGrowthPackAchievementCardPreviewInput = .mock
    ) -> MobileGrowthPackAchievementCardPreview {
        MobileGrowthPackAchievementCardPreviewBuilder().build(role: role, input: input)
    }

    func testChildSeesSafeCandidatesWithoutAdultSensitiveDetails() {
        let preview = build(role: .child)

        XCTAssertEqual(preview.role, .child)
        XCTAssertEqual(preview.publicSummary.candidateCount, 7)
        // 孩子看不到家长边界候选，所以可见数比家长少。
        XCTAssertEqual(preview.publicSummary.visibleCandidateCount, 6)
        XCTAssertFalse(preview.candidates.contains { $0.category == .guardianBoundary })
        XCTAssertTrue(preview.candidates.contains { $0.category == .badge })
        XCTAssertTrue(preview.candidates.contains { $0.category == .abilityCard })
        XCTAssertTrue(preview.candidates.contains { $0.category == .honorWall })
        XCTAssertTrue(preview.findings.allSatisfy(\.visibleToChild))
        // 孩子不应看到成人内部原因相关的 finding。
        XCTAssertFalse(preview.findings.contains { $0.code == .achievementFrozen })
        XCTAssertFalse(preview.findings.contains { $0.code == .appealPending })
        XCTAssertFalse(preview.findings.contains { $0.code == .accessRevoked })
        XCTAssertFalse(preview.findings.contains { $0.code == .abilityJumpRisk })
        XCTAssertFalse(preview.findings.contains { $0.code == .moderationRequired })
        XCTAssertFalse(preview.findings.contains { $0.code == .honorWallPrecondition })
        XCTAssertFalse(preview.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(preview.hasUnsafeDisplayPayload)

        let text = preview.displayValues.joined(separator: " ")
        for forbidden in [
            "答案键",
            "answer key",
            "成长积分金额",
            "账本明细",
            "设备命令",
            "能力评分",
            "adultReason",
            "internalRef",
            "badge:",
            "card:",
            "ability:",
            "proof:",
            "media:",
            "order:",
            "ledger:",
            "device:",
            "provider:",
            "model:",
            "transcript",
            "token",
            "http://",
            "https://",
            "/Users/"
        ] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(forbidden), forbidden)
        }
    }

    func testGuardianSeesCandidatesGapsAndBoundaries() {
        let preview = build(role: .guardian)

        XCTAssertEqual(preview.role, .guardian)
        XCTAssertEqual(preview.publicSummary.visibleCandidateCount, 7)
        XCTAssertTrue(preview.candidates.contains { $0.category == .guardianBoundary })
        XCTAssertGreaterThanOrEqual(preview.publicSummary.verificationRequiredCount, 1)
        XCTAssertGreaterThanOrEqual(preview.publicSummary.consentRequiredCount, 1)
        XCTAssertGreaterThanOrEqual(preview.publicSummary.moderationRequiredCount, 1)
        XCTAssertGreaterThanOrEqual(preview.publicSummary.abilityJumpRiskCount, 1)
        // 家长能看到冻结/申诉/撤权/审核/跳变/荣誉墙前置等阻断提示。
        XCTAssertTrue(preview.findings.contains { $0.code == .achievementFrozen && $0.actionRequired })
        XCTAssertTrue(preview.findings.contains { $0.code == .appealPending && $0.actionRequired })
        XCTAssertTrue(preview.findings.contains { $0.code == .accessRevoked && $0.actionRequired })
        XCTAssertTrue(preview.findings.contains { $0.code == .moderationRequired && $0.actionRequired })
        XCTAssertTrue(preview.findings.contains { $0.code == .abilityJumpRisk && $0.actionRequired })
        XCTAssertTrue(preview.findings.contains { $0.code == .honorWallPrecondition && $0.actionRequired })
        XCTAssertTrue(preview.findings.contains { $0.code == .verificationRequired })
        XCTAssertTrue(preview.findings.contains { $0.code == .consentRequired })
        XCTAssertFalse(preview.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(preview.hasUnsafeDisplayPayload)
    }

    func testCandidatesAndAbilityHintsAreDeterministicallySorted() {
        let preview = build(role: .guardian)

        let candidateOrders = preview.candidates.map(\.sortOrder)
        XCTAssertEqual(candidateOrders, candidateOrders.sorted())

        let hintOrders = preview.abilityHints.map(\.sortOrder)
        XCTAssertEqual(hintOrders, hintOrders.sorted())
        XCTAssertEqual(
            preview.abilityHints.map(\.dimension),
            MobileGrowthPackAchievementCardPreviewAbilityDimension.allCases
                .sorted { $0.sortOrder < $1.sortOrder }
        )

        // 同一角色重复构建结果稳定，不同角色 ref 不同。
        XCTAssertEqual(preview.candidates.map(\.publicPreviewRef), build(role: .guardian).candidates.map(\.publicPreviewRef))
        XCTAssertNotEqual(preview.candidates.map(\.publicPreviewRef), build(role: .child).candidates.map(\.publicPreviewRef))
    }

    func testBlockedStatesSurfaceHoldFindings() {
        let childPreview = build(role: .child)
        // 冻结的能力卡与撤权的亲友分享都应被孩子视为“先暂停”。
        XCTAssertGreaterThanOrEqual(childPreview.publicSummary.blockedCount, 1)
        XCTAssertTrue(childPreview.findings.contains { $0.code == .previewOnHold && $0.actionRequired })
        XCTAssertTrue(childPreview.findings.contains { $0.code == .verificationRequired })
        XCTAssertTrue(childPreview.findings.contains { $0.code == .consentRequired })
        XCTAssertTrue(childPreview.candidates.contains { $0.category == .abilityCard && $0.isFrozen && $0.isBlocked })
        XCTAssertTrue(childPreview.candidates.contains { $0.category == .relativeShare && $0.accessRevoked && $0.isBlocked })
    }

    func testUnsafePayloadHidesPreviewWithoutEchoingRawValue() {
        let preview = build(
            role: .guardian,
            input: MobileGrowthPackAchievementCardPreviewInput(
                generatedAt: "2026-06-25T02:00:00.000Z",
                unsafePayload: "badge:raw card:raw ability:score proof:raw provider:model transcript token http://example.invalid"
            )
        )

        XCTAssertTrue(preview.candidates.isEmpty)
        XCTAssertTrue(preview.abilityHints.isEmpty)
        XCTAssertEqual(preview.publicSummary.blockedCount, 1)
        XCTAssertEqual(preview.publicSummary.findingCodes, [.unsafePayloadBlocked])
        XCTAssertFalse(preview.displayValues.joined(separator: " ").localizedCaseInsensitiveContains("example.invalid"))
        XCTAssertFalse(preview.publicSummary.hasTriggeredSideEffect)
    }

    func testAdultReasonAndInternalRefsHidePreviewWithoutEchoingRawValue() {
        let preview = build(
            role: .guardian,
            input: MobileGrowthPackAchievementCardPreviewInput(
                generatedAt: "2026-06-25T02:00:00.000Z",
                unsafePayload: "adultReason=manual review internalRef=ref_secret child_real family_real"
            )
        )

        XCTAssertTrue(preview.candidates.isEmpty)
        XCTAssertTrue(preview.abilityHints.isEmpty)
        XCTAssertEqual(preview.publicSummary.findingCodes, [.unsafePayloadBlocked])
        XCTAssertFalse(preview.displayValues.joined(separator: " ").localizedCaseInsensitiveContains("manual review"))
        XCTAssertFalse(preview.displayValues.joined(separator: " ").localizedCaseInsensitiveContains("ref_secret"))
        XCTAssertFalse(preview.publicSummary.hasTriggeredSideEffect)
    }

    func testPublicRefsAndDisplayValuesAreStableAndRedacted() {
        let preview = build(role: .guardian)
        let refs = preview.candidates.map(\.publicPreviewRef) + preview.abilityHints.map(\.publicPreviewRef)

        XCTAssertEqual(Set(refs).count, refs.count)
        XCTAssertTrue(preview.candidates.allSatisfy { $0.publicPreviewRef.hasPrefix("gpa-") })
        XCTAssertTrue(preview.abilityHints.allSatisfy { $0.publicPreviewRef.hasPrefix("gpa-") })
        for value in preview.displayValues {
            for forbidden in ["child:", "family:", "school:", "teacher:", "guardian:", "proof:", "media:", "badge:", "card:", "ability:", "ledger:", "device:", "token", "192.168.", ".local", "/Volumes/"] {
                XCTAssertFalse(value.localizedCaseInsensitiveContains(forbidden), "\(value) contains \(forbidden)")
            }
        }
    }

    func testVisibleCopyDoesNotSoundLikeDemoData() {
        let visibleText = MobileGrowthPackExecutionHubRole.allCases
            .flatMap { build(role: $0).displayValues }
            .joined(separator: " ")

        XCTAssertFalse(visibleText.contains("示例"))
    }

    func testAllCandidatesHintsAndSummaryRemainReadOnly() {
        for role in MobileGrowthPackExecutionHubRole.allCases {
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
            XCTAssertFalse(preview.publicSummary.unlocksDevice)
            XCTAssertFalse(preview.publicSummary.controlsScreenTime)
            XCTAssertFalse(preview.publicSummary.sendsNotification)
            XCTAssertFalse(preview.publicSummary.submitsProof)
            XCTAssertFalse(preview.publicSummary.hasTriggeredSideEffect)

            XCTAssertTrue(preview.candidates.allSatisfy { !$0.hasTriggeredSideEffect })
            XCTAssertTrue(preview.abilityHints.allSatisfy { !$0.hasTriggeredSideEffect })
        }
    }

    @MainActor
    func testViewInitializersCompileWithLockedRoles() {
        _ = MobileGrowthPackAchievementCardPreviewView()
        _ = MobileGrowthPackAchievementCardPreviewView(initialRole: .child, allowedRoles: [.child])
        _ = MobileGrowthPackAchievementCardPreviewView(initialRole: .guardian, allowedRoles: [.guardian])
        // 入口仍由执行中心承载，且只传角色与安全枚举，不触发任何副作用。
        _ = MobileGrowthPackExecutionHubView(initialRole: .child, allowedRoles: [.child])
        _ = MobileGrowthPackExecutionHubView(initialRole: .guardian, allowedRoles: [.guardian])
    }
}
