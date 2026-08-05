import XCTest
@testable import OctoTeacher

/// iOS 成长报告 / 周报预览测试。
///
/// 覆盖孩子/家长视角、报告只读边界、敏感内容 fallback、设备会话只读展示和视图初始化。
final class ReportsWorkbenchTests: XCTestCase {

    private func build(
        role: ReportsViewerRole,
        family: LocalFamilyStore = LocalFamilyStore(),
        schoolFamily: SchoolFamilyStore = SchoolFamilyStore(),
        screenTime: MockScreenTimeController = MockScreenTimeController(),
        aiCompanionSessions: [AICompanionSessionRecord] = [],
        now: Date = Date(timeIntervalSince1970: 1_000),
        unsafePayload: [String] = []
    ) -> ReportsWorkbench {
        ReportsWorkbenchBuilder().build(
            role: role,
            family: family,
            schoolFamily: schoolFamily,
            screenTime: screenTime,
            aiCompanionSessions: aiCompanionSessions,
            now: now,
            unsafePayload: unsafePayload
        )
    }

    private func aiSession(
        childId: UUID,
        createdAt: Date,
        needsGuardianAction: Bool = false
    ) -> AICompanionSessionRecord {
        AICompanionSessionRecord(
            id: UUID(),
            childId: childId,
            createdAt: createdAt,
            mode: needsGuardianAction ? .emotion : .nextStep,
            status: needsGuardianAction ? .needsTrustedAdult : .guiding,
            latestIntent: needsGuardianAction ? .askTrustedAdult : .findNextStep,
            intentLabels: needsGuardianAction ? ["想找可信大人"] : ["需要下一步"],
            riskLabels: needsGuardianAction ? [.emotionalDistress] : [],
            needsGuardianAction: needsGuardianAction,
            suggestedGuardianAction: needsGuardianAction ? "今晚主动问孩子需要哪种帮助。" : "当前无需介入。",
            findingCodes: needsGuardianAction ? [.trustedAdultNeeded] : [.nextStepSuggested]
        )
    }

    func testChildReportHidesAdultReviewAndCreditBalance() {
        let report = build(role: .child)

        XCTAssertEqual(report.role, .child)
        XCTAssertFalse(report.sections.isEmpty)
        XCTAssertTrue(report.sections.allSatisfy(\.visibleToChild))
        XCTAssertTrue(report.metrics.allSatisfy(\.visibleToChild))
        XCTAssertEqual(report.publicSummary.availableCreditMinutes, 0)
        XCTAssertEqual(report.publicSummary.aiCompanionGuardianActionCount, 0)
        XCTAssertEqual(report.publicSummary.pendingRewardActionCount, 0)
        XCTAssertEqual(report.findings.filter(\.visibleToChild).map(\.id), ["child-report-read-only"])
        XCTAssertFalse(report.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(report.hasUnsafeDisplayPayload)
    }

    func testGuardianReportShowsReviewWorkAndCreditPreviewWithoutWriting() {
        let report = build(role: .guardian)

        XCTAssertEqual(report.role, .guardian)
        XCTAssertGreaterThanOrEqual(report.sections.count, 6)
        XCTAssertTrue(report.metrics.contains { $0.id == "credit-available" })
        XCTAssertTrue(report.metrics.contains { $0.id == "review-pending" })
        XCTAssertTrue(report.sections.contains { $0.kind == .wellbeing })
        XCTAssertGreaterThan(report.publicSummary.actionRequiredCount, 0)
        XCTAssertGreaterThanOrEqual(report.publicSummary.availableCreditMinutes, 0)
        XCTAssertFalse(report.publicSummary.hasTriggeredSideEffect)
    }

    func testReportsShowRewardPathwayBacklogWithoutWishDetails() throws {
        let family = LocalFamilyStore()
        family.child.rewardBalanceMinutes = 120
        let proposedWish = try XCTUnwrap(family.submitWish(title: "滑板课", childId: family.activeChildId))
        XCTAssertEqual(proposedWish.status, .proposed)
        let redeemedWish = try XCTUnwrap(family.submitWish(title: "恐龙图鉴", childId: family.activeChildId))
        XCTAssertTrue(family.priceWish(redeemedWish.id, points: 30))
        XCTAssertTrue(family.redeemWish(redeemedWish.id))
        _ = try XCTUnwrap(family.requestPocketMoneyExchange(points: 20, childId: family.activeChildId))

        let guardianReport = build(role: .guardian, family: family)

        XCTAssertEqual(guardianReport.publicSummary.openWishCount, 2)
        XCTAssertEqual(guardianReport.publicSummary.pendingRewardActionCount, 3)
        XCTAssertTrue(guardianReport.metrics.contains { $0.id == "wish-list-open" && $0.value == 2 })
        XCTAssertTrue(guardianReport.metrics.contains { $0.id == "reward-guardian-actions" && $0.value == 3 })
        XCTAssertTrue(guardianReport.sections.contains { $0.kind == .creditReward && $0.actionRequired })
        XCTAssertTrue(guardianReport.findings.contains { $0.id == "reward-pathway-follow-up" && $0.actionRequired })
        let guardianText = guardianReport.displayValues.joined(separator: " ")
        XCTAssertFalse(guardianText.contains("滑板课"))
        XCTAssertFalse(guardianText.contains("恐龙图鉴"))

        let childReport = build(role: .child, family: family)

        XCTAssertEqual(childReport.publicSummary.openWishCount, 2)
        XCTAssertEqual(childReport.publicSummary.pendingRewardActionCount, 0)
        XCTAssertTrue(childReport.metrics.contains { $0.id == "wish-list-open" && $0.visibleToChild })
        XCTAssertFalse(childReport.metrics.contains { $0.id == "reward-guardian-actions" })
        XCTAssertFalse(childReport.findings.contains { $0.id == "reward-pathway-follow-up" })
        XCTAssertFalse(childReport.hasUnsafeDisplayPayload)
    }

    func testReportsShowAICompanionDigestWithoutRawTranscript() {
        let family = LocalFamilyStore()
        let now = Date(timeIntervalSince1970: 10_000)
        let otherChild = UUID()
        let sessions = [
            aiSession(childId: family.activeChildId, createdAt: now.addingTimeInterval(-60)),
            aiSession(childId: family.activeChildId, createdAt: now.addingTimeInterval(-120), needsGuardianAction: true),
            aiSession(childId: family.activeChildId, createdAt: now.addingTimeInterval(-9 * 24 * 60 * 60), needsGuardianAction: true),
            aiSession(childId: otherChild, createdAt: now.addingTimeInterval(-30), needsGuardianAction: true)
        ]

        let report = build(
            role: .guardian,
            family: family,
            aiCompanionSessions: sessions,
            now: now
        )

        XCTAssertEqual(report.publicSummary.aiCompanionInteractionCount, 2)
        XCTAssertEqual(report.publicSummary.aiCompanionGuardianActionCount, 1)
        XCTAssertTrue(report.metrics.contains { $0.id == "ai-companion-interactions" && $0.value == 2 })
        XCTAssertTrue(report.metrics.contains { $0.id == "ai-companion-guardian-actions" && $0.value == 1 })
        XCTAssertTrue(report.sections.contains { $0.kind == .aiCompanion && $0.actionRequired })
        XCTAssertTrue(report.findings.contains { $0.id == "ai-companion-follow-up" && $0.actionRequired })
        XCTAssertFalse(report.displayValues.joined(separator: " ").localizedCaseInsensitiveContains("今晚主动问孩子"))
        XCTAssertFalse(report.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(report.hasUnsafeDisplayPayload)
    }

    func testChildReportShowsCompanionCountButHidesGuardianFollowUp() {
        let family = LocalFamilyStore()
        let now = Date(timeIntervalSince1970: 10_000)
        let sessions = [
            aiSession(childId: family.activeChildId, createdAt: now.addingTimeInterval(-60), needsGuardianAction: true)
        ]

        let report = build(
            role: .child,
            family: family,
            aiCompanionSessions: sessions,
            now: now
        )

        XCTAssertEqual(report.publicSummary.aiCompanionInteractionCount, 1)
        XCTAssertEqual(report.publicSummary.aiCompanionGuardianActionCount, 0)
        XCTAssertTrue(report.metrics.contains { $0.id == "ai-companion-interactions" && $0.visibleToChild })
        XCTAssertFalse(report.metrics.contains { $0.id == "ai-companion-guardian-actions" })
        XCTAssertFalse(report.findings.contains { $0.id == "ai-companion-follow-up" })
        XCTAssertTrue(report.sections.contains { $0.kind == .aiCompanion && $0.visibleToChild })
        XCTAssertFalse(report.hasUnsafeDisplayPayload)
    }

    func testActiveMockSessionIsReportedButNotChanged() throws {
        let screenTime = MockScreenTimeController()
        try screenTime.startSession(minutes: 15, now: Date(timeIntervalSince1970: 0))

        let report = build(role: .guardian, screenTime: screenTime)

        XCTAssertTrue(report.sections.contains { $0.kind == .wellbeing && $0.status == .inProgress })
        XCTAssertTrue(report.findings.contains { $0.id == "mock-session-active" && !$0.actionRequired })
        XCTAssertEqual(screenTime.sessionStatus, .active)
        XCTAssertFalse(report.publicSummary.unlocksDevice)
        XCTAssertFalse(report.publicSummary.readsScreenTime)
    }

    func testPublicSummaryAndSectionsNeverTriggerSideEffects() {
        for role in ReportsViewerRole.allCases {
            let report = build(role: role)
            let summary = report.publicSummary

            XCTAssertFalse(summary.writesReportFile, role.label)
            XCTAssertFalse(summary.exportsPdf, role.label)
            XCTAssertFalse(summary.uploadsReport, role.label)
            XCTAssertFalse(summary.sendsNotification, role.label)
            XCTAssertFalse(summary.callsNetwork, role.label)
            XCTAssertFalse(summary.callsAiProvider, role.label)
            XCTAssertFalse(summary.writesLedger, role.label)
            XCTAssertFalse(summary.grantsCredit, role.label)
            XCTAssertFalse(summary.unlocksDevice, role.label)
            XCTAssertFalse(summary.readsHealthKit, role.label)
            XCTAssertFalse(summary.readsScreenTime, role.label)

            XCTAssertTrue(report.sections.allSatisfy { section in
                !section.writesReportFile
                    && !section.exportsPdf
                    && !section.uploadsReport
                    && !section.sendsNotification
                    && !section.writesLedger
                    && !section.grantsCredit
                    && !section.unlocksDevice
            }, role.label)
        }
    }

    func testUnsafePayloadFallsBackWithoutEchoingRawText() {
        let report = build(
            role: .guardian,
            unsafePayload: ["guardian:raw ledger:raw token sk-test http://192.168.1.252/v1"]
        )

        XCTAssertTrue(report.sections.isEmpty)
        XCTAssertTrue(report.metrics.isEmpty)
        XCTAssertTrue(report.findings.contains { $0.id == "unsafe" })
        let displayed = report.displayValues.joined(separator: " ")
        XCTAssertFalse(displayed.localizedCaseInsensitiveContains("guardian:raw"))
        XCTAssertFalse(displayed.localizedCaseInsensitiveContains("ledger:raw"))
        XCTAssertFalse(displayed.localizedCaseInsensitiveContains("sk-test"))
        XCTAssertFalse(displayed.localizedCaseInsensitiveContains("192.168.1.252"))
        XCTAssertFalse(report.publicSummary.hasTriggeredSideEffect)
    }

    func testDisplayValuesDoNotLeakSensitiveMarkers() {
        for role in ReportsViewerRole.allCases {
            let text = build(role: role).displayValues.joined(separator: " ")
            for marker in [
                "child:",
                "family:",
                "guardian:",
                "teacher:",
                "task:",
                "proof:",
                "ledger:",
                "device:",
                "session:",
                "provider:",
                "model:",
                "token",
                "http://",
                "https://",
                "/Users/",
                "/Volumes/",
                "192.168."
            ] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "\(role.label) leaked \(marker)")
            }
        }
    }

    @MainActor
    func testViewInitializersCompile() {
        _ = ReportsWorkbenchView()
        _ = ReportsWorkbenchView(initialRole: .child, allowedRoles: [.child])
        _ = ReportsWorkbenchView(initialRole: .guardian, allowedRoles: [.guardian])
        _ = ReportsWorkbenchView(initialRole: .guardian, allowedRoles: [])
    }
}
