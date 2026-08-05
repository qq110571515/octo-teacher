import XCTest
@testable import OctoTeacher

/// A89 学校作业与成长包任务联动工作台测试。
///
/// 覆盖学校作业、成长包运行、联合验证、成长积分建议边界和角色裁剪。
/// 工作台必须保持只读：不提交作业、不验证老师/家长、不接 LMS/AI/网络、不写账本、不解锁设备。
final class MobileSchoolHomeworkGrowthPackLinkageWorkbenchTests: XCTestCase {

    private func sourceHomeworks() -> [SchoolHomework] {
        SchoolFamilyStore().homeworks
    }

    private func build(
        role: MobileSchoolHomeworkGrowthPackLinkageViewerRole,
        homeworks: [SchoolHomework]? = nil,
        runtimeReport: GrowthRuntimeSettlementReport = .empty
    ) -> MobileSchoolHomeworkGrowthPackLinkageWorkbench {
        MobileSchoolHomeworkGrowthPackLinkageBuilder().build(
            role: role,
            homeworks: homeworks ?? sourceHomeworks(),
            runtimeReport: runtimeReport
        )
    }

    func testChildSeesHomeworkGrowthPackLinkageWithoutAdultReasonsOrCreditDetails() {
        let workbench = build(role: .child)

        XCTAssertEqual(workbench.role, .child)
        XCTAssertFalse(workbench.items.isEmpty)
        XCTAssertEqual(workbench.publicSummary.guardianCreditSuggestionCount, 0)
        XCTAssertEqual(workbench.publicSummary.childVisibleAdultReasonCount, 0)
        XCTAssertTrue(workbench.items.allSatisfy(\.visibleToChild))
        XCTAssertTrue(workbench.items.allSatisfy { !$0.canSuggestCreditToGuardian })
        XCTAssertTrue(workbench.findings.allSatisfy(\.visibleToChild))
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(workbench.hasUnsafeDisplayPayload)

        let displayed = workbench.displayValues.joined(separator: " ")
        XCTAssertFalse(displayed.localizedCaseInsensitiveContains("成长积分金额"))
        XCTAssertFalse(displayed.localizedCaseInsensitiveContains("adult reason"))
        XCTAssertFalse(displayed.localizedCaseInsensitiveContains("transcript"))
    }

    func testGuardianSeesCreditBoundaryButReturnedHomeworkBlocksSuggestion() {
        let workbench = build(role: .guardian)

        XCTAssertEqual(workbench.role, .guardian)
        XCTAssertGreaterThan(workbench.publicSummary.guardianCreditSuggestionCount, 0)
        XCTAssertTrue(workbench.findings.contains { $0.code == .guardianConfirmationRequired })
        XCTAssertTrue(workbench.findings.contains { $0.code == .returnedBlocksCredit })

        let returned = tryUnwrap(workbench.items.first { $0.title.contains("课外阅读") })
        XCTAssertEqual(returned.status, .returned)
        XCTAssertTrue(returned.returnedOrBlocked)
        XCTAssertFalse(returned.canSuggestCreditToGuardian)
        XCTAssertTrue(returned.creditBoundaryLabel.contains("不能进入"))
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
    }

    func testTeacherCannotSeeFamilyRewardDetailsOrGuardianConfirmation() {
        let workbench = build(role: .teacher)

        XCTAssertEqual(workbench.role, .teacher)
        XCTAssertFalse(workbench.items.isEmpty)
        XCTAssertEqual(workbench.publicSummary.teacherVisibleCreditDetailCount, 0)
        XCTAssertTrue(workbench.items.allSatisfy { !$0.canSuggestCreditToGuardian })
        XCTAssertTrue(workbench.findings.contains { $0.code == .teacherCreditHidden })
        XCTAssertFalse(workbench.displayValues.joined(separator: " ").contains("家长确认后的成长积分建议"))
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
    }

    func testPublicSummaryAndItemsNeverTriggerSideEffects() {
        for role in MobileSchoolHomeworkGrowthPackLinkageViewerRole.allCases {
            let workbench = build(role: role)
            let summary = workbench.publicSummary

            XCTAssertFalse(summary.submitsHomework)
            XCTAssertFalse(summary.verifiesTeacher)
            XCTAssertFalse(summary.confirmsGuardian)
            XCTAssertFalse(summary.writesSchoolSystem)
            XCTAssertFalse(summary.callsLms)
            XCTAssertFalse(summary.callsAIProvider)
            XCTAssertFalse(summary.callsNetwork)
            XCTAssertFalse(summary.uploadsAttachment)
            XCTAssertFalse(summary.writesLedger)
            XCTAssertFalse(summary.grantsCredit)
            XCTAssertFalse(summary.unlocksDevice)
            XCTAssertFalse(summary.sendsNotification)

            XCTAssertTrue(workbench.items.allSatisfy { item in
                !item.submitsHomework && !item.verifiesTeacher && !item.confirmsGuardian
                    && !item.writesSchoolSystem && !item.callsLms && !item.callsAIProvider
                    && !item.callsNetwork && !item.uploadsAttachment && !item.writesLedger
                    && !item.grantsCredit && !item.unlocksDevice && !item.sendsNotification
            })
        }
    }

    func testUnsafePayloadFallsBackWithoutEchoingRawContent() {
        var homeworks = sourceHomeworks()
        homeworks[0].instructions = "http://192.168.1.252 child:raw transcript token"

        let workbench = build(role: .guardian, homeworks: homeworks)

        XCTAssertTrue(workbench.items.isEmpty)
        XCTAssertEqual(workbench.publicSummary.findingCodes, [.unsafePayloadBlocked])
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)

        let displayed = workbench.displayValues.joined(separator: " ")
        XCTAssertFalse(displayed.localizedCaseInsensitiveContains("192.168.1.252"))
        XCTAssertFalse(displayed.localizedCaseInsensitiveContains("child:raw"))
        XCTAssertFalse(displayed.localizedCaseInsensitiveContains("transcript"))
        XCTAssertFalse(displayed.localizedCaseInsensitiveContains("token"))
    }

    func testAnswerKeyMarkerFallsBackWithoutEchoingRawContent() {
        var homeworks = sourceHomeworks()
        homeworks[0].instructions = "answerkey: final solution"

        let workbench = build(role: .child, homeworks: homeworks)

        XCTAssertTrue(workbench.items.isEmpty)
        XCTAssertEqual(workbench.publicSummary.findingCodes, [.unsafePayloadBlocked])
        XCTAssertFalse(workbench.displayValues.joined(separator: " ").localizedCaseInsensitiveContains("answerkey"))
        XCTAssertFalse(workbench.publicSummary.hasTriggeredSideEffect)
    }

    func testEmptyHomeworksRemainReadOnlyAndDeterministic() {
        let child = build(role: .child, homeworks: [])
        let guardian = build(role: .guardian, homeworks: [])

        XCTAssertTrue(child.items.isEmpty)
        XCTAssertTrue(guardian.items.isEmpty)
        XCTAssertEqual(child.publicSummary.linkedHomeworkCount, 0)
        XCTAssertEqual(guardian.publicSummary.linkedHomeworkCount, 0)
        XCTAssertTrue(child.findings.contains { $0.code == .readOnlyReady })
        XCTAssertTrue(guardian.findings.contains { $0.code == .readOnlyReady })
        XCTAssertFalse(child.publicSummary.hasTriggeredSideEffect)
        XCTAssertEqual(child, build(role: .child, homeworks: []))
    }

    func testDisplayValuesDoNotLeakRawHomeworkIdsOrSensitiveMarkers() {
        let homeworks = sourceHomeworks()
        let displayed = build(role: .guardian, homeworks: homeworks).displayValues.joined(separator: " ")

        for homework in homeworks {
            XCTAssertFalse(displayed.contains(homework.id.uuidString))
        }
        for marker in ["homework:", "teacher:", "ledger:", "device:", "http://", "https://", "/Users/", "/Volumes/", "192.168."] {
            XCTAssertFalse(displayed.localizedCaseInsensitiveContains(marker), "leaked \(marker)")
        }
    }

    func testModuleCenterSchoolHomeworkRouteOpensLinkageWorkbenchBoundary() {
        let resolver = MobileModuleLaunchRouteResolver()
        let childRoute = resolver.route(for: .schoolHomework, viewerRole: .child)
        let guardianRoute = resolver.route(for: .schoolHomework, viewerRole: .guardian)
        let teacherRoute = resolver.route(for: .schoolHomework, viewerRole: .teacher)

        XCTAssertEqual(childRoute?.destinationKind, .schoolHomework)
        XCTAssertEqual(guardianRoute?.destinationKind, .schoolHomework)
        XCTAssertEqual(teacherRoute?.destinationKind, .schoolHomework)
        XCTAssertEqual(childRoute?.title, "打开作业成长包联动")
        XCTAssertTrue([childRoute, guardianRoute, teacherRoute].compactMap { $0 }.allSatisfy {
            !$0.hasTriggeredSideEffect
        })
        XCTAssertTrue(resolver.redacts([childRoute, guardianRoute, teacherRoute].compactMap { $0 }))
    }

    @MainActor
    func testViewInitializersCompile() {
        _ = MobileSchoolHomeworkGrowthPackLinkageWorkbenchView()
        _ = MobileSchoolHomeworkGrowthPackLinkageWorkbenchView(initialRole: .child, allowedRoles: [.child])
        _ = MobileSchoolHomeworkGrowthPackLinkageWorkbenchView(initialRole: .guardian, allowedRoles: [.guardian])
        _ = MobileSchoolHomeworkGrowthPackLinkageWorkbenchView(initialRole: .teacher, allowedRoles: [.teacher])
        _ = SchoolHomeworkView()
        _ = GrowthPackContentPlayerWorkbenchView()
        _ = MobileModuleLaunchCenterView()
    }

    private func tryUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) -> T {
        guard let value else {
            XCTFail("Expected value", file: file, line: line)
            fatalError("Expected value")
        }
        return value
    }
}
