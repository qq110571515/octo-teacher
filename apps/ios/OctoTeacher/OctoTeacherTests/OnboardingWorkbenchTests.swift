import XCTest
@testable import OctoTeacher

/// iOS 章鱼老师 入门页测试。
///
/// 覆盖品牌名、孩子/家长视角裁剪、无登录/权限/网络/账本/设备副作用和 unsafe fallback。
final class OnboardingWorkbenchTests: XCTestCase {

    private func build(
        role: OnboardingViewerRole,
        unsafePayload: [String] = []
    ) -> OnboardingWorkbench {
        OnboardingWorkbenchBuilder().build(role: role, unsafePayload: unsafePayload)
    }

    func testBrandStaysConsistentForEveryRole() {
        for role in OnboardingViewerRole.allCases {
            let workbench = build(role: role)

            XCTAssertEqual(workbench.title, BrandIdentity.systemName)
            XCTAssertTrue(workbench.displayValues.contains(BrandIdentity.systemName))
        }
    }

    func testChildOnboardingHidesAdultOnlySetupSteps() {
        let workbench = build(role: .child)

        XCTAssertEqual(workbench.role, .child)
        XCTAssertFalse(workbench.steps.isEmpty)
        XCTAssertTrue(workbench.steps.allSatisfy(\.visibleToChild))
        XCTAssertTrue(workbench.boundaries.allSatisfy(\.visibleToChild))
        XCTAssertFalse(workbench.steps.contains { $0.kind == .reports })
        XCTAssertFalse(workbench.steps.contains { $0.kind == .privacy })
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
    }

    func testGuardianOnboardingShowsFullBoundaryChecklist() {
        let workbench = build(role: .guardian)

        XCTAssertEqual(workbench.role, .guardian)
        XCTAssertGreaterThan(workbench.steps.count, build(role: .child).steps.count)
        XCTAssertTrue(workbench.steps.contains { $0.kind == .reports })
        XCTAssertTrue(workbench.steps.contains { $0.kind == .privacy })
        XCTAssertTrue(workbench.boundaries.contains { $0.id == "no-permission" })
        XCTAssertEqual(workbench.publicSummary.visibleStepCount, workbench.steps.count)
        XCTAssertEqual(workbench.publicSummary.readyStepCount, workbench.steps.count)
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
    }

    func testRewardTimeCopyAvoidsLegacyCreditWording() {
        for role in OnboardingViewerRole.allCases {
            let text = build(role: role).displayValues.joined(separator: " ")

            XCTAssertTrue(text.contains("成长积分"), role.label)
            XCTAssertFalse(text.contains("成长积分奖励"), role.label)
            XCTAssertFalse(text.contains("不发成长积分"), role.label)
            XCTAssertFalse(text.contains("成长积分建议"), role.label)
        }
    }

    func testStepsAndSummaryNeverTriggerSideEffects() {
        for role in OnboardingViewerRole.allCases {
            let workbench = build(role: role)
            let summary = workbench.publicSummary

            XCTAssertFalse(summary.startsLogin, role.label)
            XCTAssertFalse(summary.createsAccount, role.label)
            XCTAssertFalse(summary.requestsApplePermission, role.label)
            XCTAssertFalse(summary.callsNetwork, role.label)
            XCTAssertFalse(summary.writesFamily, role.label)
            XCTAssertFalse(summary.writesLedger, role.label)
            XCTAssertFalse(summary.unlocksDevice, role.label)
            XCTAssertFalse(summary.sendsNotification, role.label)

            XCTAssertTrue(workbench.steps.allSatisfy { step in
                !step.startsLogin
                    && !step.createsAccount
                    && !step.requestsApplePermission
                    && !step.callsNetwork
                    && !step.writesFamily
                    && !step.writesLedger
                    && !step.unlocksDevice
            }, role.label)
        }
    }

    func testUnsafePayloadFallsBackWithoutEchoingRawText() {
        let workbench = build(
            role: .guardian,
            unsafePayload: ["family:raw token sk-test http://192.168.1.252/v1"]
        )

        XCTAssertEqual(workbench.title, BrandIdentity.systemName)
        XCTAssertTrue(workbench.steps.isEmpty)
        XCTAssertTrue(workbench.boundaries.contains { $0.id == "unsafe" })
        let displayed = workbench.displayValues.joined(separator: " ")
        XCTAssertFalse(displayed.localizedCaseInsensitiveContains("family:raw"))
        XCTAssertFalse(displayed.localizedCaseInsensitiveContains("sk-test"))
        XCTAssertFalse(displayed.localizedCaseInsensitiveContains("192.168.1.252"))
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
    }

    func testDisplayValuesDoNotLeakSensitiveMarkers() {
        for role in OnboardingViewerRole.allCases {
            let text = build(role: role).displayValues.joined(separator: " ")
            for marker in [
                "child:",
                "family:",
                "guardian:",
                "teacher:",
                "school:",
                "token",
                "secret",
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
        _ = OnboardingWorkbenchView()
        _ = OnboardingWorkbenchView(initialRole: .child, allowedRoles: [.child])
        _ = OnboardingWorkbenchView(initialRole: .guardian, allowedRoles: [.guardian])
        _ = OnboardingWorkbenchView(initialRole: .guardian, allowedRoles: [])
    }
}
