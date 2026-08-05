import XCTest
@testable import OctoTeacher

/// iOS 娱乐 App 选择 / 锁定策略预览测试。
///
/// 覆盖孩子/家长视角、系统标识脱敏、无 FamilyControls/ManagedSettings/DeviceActivity
/// 副作用、待家长确认、年龄门禁、unsafe fallback 和视图初始化。
final class AppSelectionWorkbenchTests: XCTestCase {

    private func build(
        role: AppSelectionViewerRole,
        candidates: [AppSelectionCandidate] = AppSelectionWorkbenchBuilder.mockCandidates,
        unsafePayload: [String] = []
    ) -> AppSelectionWorkbench {
        AppSelectionWorkbenchBuilder().build(
            role: role,
            candidates: candidates,
            unsafePayload: unsafePayload
        )
    }

    func testChildSeesSelectedEntertainmentWithoutSystemIdentifiers() {
        let workbench = build(role: .child)

        XCTAssertEqual(workbench.role, .child)
        XCTAssertFalse(workbench.candidates.isEmpty)
        XCTAssertTrue(workbench.candidates.allSatisfy(\.selectedForShield))
        XCTAssertTrue(workbench.candidates.allSatisfy { $0.internalBundleIdentifier == nil })
        XCTAssertEqual(workbench.findings.filter(\.visibleToChild).map(\.id), ["child-no-direct-unlock"])
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(workbench.hasUnsafeDisplayPayload)
    }

    func testGuardianSeesPendingApprovalAgeGateAndHighRiskCounts() {
        let workbench = build(role: .guardian)

        XCTAssertEqual(workbench.role, .guardian)
        XCTAssertEqual(workbench.publicSummary.candidateCount, AppSelectionWorkbenchBuilder.mockCandidates.count)
        XCTAssertEqual(workbench.publicSummary.selectedCount, 3)
        XCTAssertEqual(workbench.publicSummary.approvedSelectedCount, 1)
        XCTAssertEqual(workbench.publicSummary.pendingGuardianCount, 1)
        XCTAssertEqual(workbench.publicSummary.blockedCount, 1)
        XCTAssertEqual(workbench.publicSummary.highRiskSelectedCount, 1)
        XCTAssertTrue(workbench.findings.contains { $0.id == "guardian-approval-required" && $0.actionRequired })
        XCTAssertTrue(workbench.findings.contains { $0.id == "age-gate-blocked" && $0.actionRequired })
        XCTAssertTrue(workbench.findings.contains { $0.id == "high-risk-selected" && $0.actionRequired })
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
    }

    func testPublicSummaryAndCandidatesNeverTriggerScreenTimeOrLedgerSideEffects() {
        for role in AppSelectionViewerRole.allCases {
            let workbench = build(role: role)
            let summary = workbench.publicSummary

            XCTAssertFalse(summary.callsFamilyControls, role.label)
            XCTAssertFalse(summary.callsManagedSettings, role.label)
            XCTAssertFalse(summary.callsDeviceActivity, role.label)
            XCTAssertFalse(summary.writesShieldPolicy, role.label)
            XCTAssertFalse(summary.readsInstalledApplications, role.label)
            XCTAssertFalse(summary.storesBundleIdentifiers, role.label)
            XCTAssertFalse(summary.writesLedger, role.label)
            XCTAssertFalse(summary.grantsCredit, role.label)
            XCTAssertFalse(summary.unlocksDevice, role.label)
            XCTAssertFalse(summary.callsNetwork, role.label)

            XCTAssertTrue(workbench.candidates.allSatisfy { candidate in
                !candidate.callsFamilyControls
                    && !candidate.callsManagedSettings
                    && !candidate.callsDeviceActivity
                    && !candidate.writesShieldPolicy
                    && !candidate.writesLedger
                    && !candidate.grantsCredit
                    && !candidate.unlocksDevice
            }, role.label)
        }
    }

    func testDisplayValuesDoNotLeakBundleIdentifiersOrSystemFrameworkMarkers() {
        for role in AppSelectionViewerRole.allCases {
            let workbench = build(role: role)
            let displayed = workbench.displayValues.joined(separator: " ")

            for marker in [
                "com.example",
                "bundle",
                "FamilyControls",
                "ManagedSettings",
                "DeviceActivity",
                "ApplicationToken",
                "FamilyActivitySelection",
                "shield:",
                "device:",
                "ledger:",
                "credit:",
                "http://",
                "https://",
                "/Users/",
                "/Volumes/"
            ] {
                XCTAssertFalse(displayed.localizedCaseInsensitiveContains(marker), "\(role.label) leaked \(marker)")
            }
            XCTAssertTrue(workbench.candidates.allSatisfy { $0.publicAppRef.hasPrefix("asw-") })
        }
    }

    func testUnsafePayloadFallsBackWithoutEchoingRawText() {
        let workbench = build(
            role: .guardian,
            unsafePayload: [
                "FamilyActivitySelection bundle com.apple.private token sk-test http://192.168.1.252/v1"
            ]
        )

        XCTAssertTrue(workbench.candidates.isEmpty)
        XCTAssertTrue(workbench.findings.contains { $0.id == "unsafe" })
        XCTAssertEqual(workbench.publicSummary.blockedCount, AppSelectionWorkbenchBuilder.mockCandidates.count)
        let displayed = workbench.displayValues.joined(separator: " ")
        XCTAssertFalse(displayed.localizedCaseInsensitiveContains("FamilyActivitySelection"))
        XCTAssertFalse(displayed.localizedCaseInsensitiveContains("com.apple.private"))
        XCTAssertFalse(displayed.localizedCaseInsensitiveContains("sk-test"))
        XCTAssertFalse(displayed.localizedCaseInsensitiveContains("192.168.1.252"))
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
    }

    func testCandidateWithUnsafeDisplayFallsBackBeforeShowingSystemIdentifier() {
        var candidates = AppSelectionWorkbenchBuilder.mockCandidates
        candidates[0].displayName = "bundle com.apple.private"

        let workbench = build(role: .guardian, candidates: candidates)

        XCTAssertTrue(workbench.candidates.isEmpty)
        XCTAssertTrue(workbench.findings.contains { $0.id == "unsafe" })
        let displayed = workbench.displayValues.joined(separator: " ")
        XCTAssertFalse(displayed.localizedCaseInsensitiveContains("com.apple.private"))
    }

    @MainActor
    func testEmptyAllowedRolesFallbackViewInitializersCompile() {
        _ = AppSelectionWorkbenchView()
        _ = AppSelectionWorkbenchView(initialRole: .child, allowedRoles: [.child])
        _ = AppSelectionWorkbenchView(initialRole: .guardian, allowedRoles: [.guardian])
        _ = AppSelectionWorkbenchView(initialRole: .guardian, allowedRoles: [])
    }
}
