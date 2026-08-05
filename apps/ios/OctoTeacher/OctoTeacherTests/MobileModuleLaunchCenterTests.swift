import XCTest
import SwiftUI
@testable import OctoTeacher

final class MobileModuleLaunchCenterTests: XCTestCase {

    private let builder = MobileModuleLaunchCenterBuilder()
    private let routeResolver = MobileModuleLaunchRouteResolver()

    func testRoleScopeDefaultsToAllRoles() {
        let scope = MobileModuleLaunchCenterRoleScope(initialRole: .guardian)

        XCTAssertEqual(scope.initialRole, .guardian)
        XCTAssertEqual(scope.availableRoles, MobileModuleLaunchCenterViewerRole.allCases)
        XCTAssertTrue(scope.allowsRoleSwitching)
    }

    func testRoleScopeLocksSingleRoleEntry() {
        let scope = MobileModuleLaunchCenterRoleScope(initialRole: .child, allowedRoles: [.child])

        XCTAssertEqual(scope.initialRole, .child)
        XCTAssertEqual(scope.availableRoles, [.child])
        XCTAssertFalse(scope.allowsRoleSwitching)
    }

    func testRoleScopeKeepsOrderedMultiRoleSwitching() {
        let scope = MobileModuleLaunchCenterRoleScope(
            initialRole: .guardian,
            allowedRoles: [.operations, .child, .guardian, .child]
        )

        XCTAssertEqual(scope.initialRole, .guardian)
        XCTAssertEqual(scope.availableRoles, [.child, .guardian, .operations])
        XCTAssertTrue(scope.allowsRoleSwitching)
    }

    func testRoleScopeFallsBackWhenInitialRoleIsOutsideAllowedRoles() {
        let scope = MobileModuleLaunchCenterRoleScope(
            initialRole: .operations,
            allowedRoles: [.child, .guardian]
        )

        XCTAssertEqual(scope.initialRole, .child)
        XCTAssertEqual(scope.availableRoles, [.child, .guardian])
        XCTAssertTrue(scope.allowsRoleSwitching)
    }

    func testRoleScopeEmptyAllowedRolesFallsBackToDefaultRoles() {
        let scope = MobileModuleLaunchCenterRoleScope(initialRole: .teacher, allowedRoles: [])

        XCTAssertEqual(scope.initialRole, .teacher)
        XCTAssertEqual(scope.availableRoles, MobileModuleLaunchCenterViewerRole.allCases)
        XCTAssertTrue(scope.allowsRoleSwitching)
    }

    @MainActor
    func testRoleScopedViewInitializersCompile() {
        _ = MobileModuleLaunchCenterView()
        _ = MobileModuleLaunchCenterView(initialRole: .child, allowedRoles: [.child])
        _ = MobileModuleLaunchCenterView(initialRole: .guardian, allowedRoles: [.guardian])
    }

    func testChildSeesGrowthModulesButNoAdultQualityGate() {
        let snapshot = builder.build(viewerRole: .child)

        XCTAssertEqual(snapshot.viewerRole, .child)
        XCTAssertFalse(snapshot.modules.isEmpty)
        XCTAssertTrue(snapshot.modules.contains { $0.group == .basicTasks })
        XCTAssertTrue(snapshot.modules.contains { $0.group == .growthPacks })
        XCTAssertTrue(snapshot.modules.contains { $0.group == .schoolLearning })
        XCTAssertTrue(snapshot.modules.contains { $0.key == .schoolJointApproval })
        XCTAssertTrue(snapshot.modules.contains { $0.group == .familyHonor })
        XCTAssertTrue(snapshot.modules.contains { $0.group == .creditReward })
        XCTAssertFalse(snapshot.modules.contains { $0.group == .platformQuality })
        XCTAssertFalse(snapshot.modules.contains { $0.key == .moduleConfigurationDraft })
        XCTAssertFalse(snapshot.modules.contains { $0.key == .releaseGate })
        XCTAssertTrue(snapshot.findings.contains { $0.code == .adultModuleHiddenFromChild })
        XCTAssertGreaterThan(snapshot.publicSummary.hiddenInternalModuleCount, 0)
    }

    func testGuardianSeesReviewAndReleaseGateModules() {
        let snapshot = builder.build(viewerRole: .guardian)

        XCTAssertEqual(snapshot.viewerRole, .guardian)
        XCTAssertTrue(snapshot.modules.contains { $0.key == .moduleConfigurationDraft })
        XCTAssertTrue(snapshot.modules.contains { $0.key == .releaseGate })
        XCTAssertTrue(snapshot.groups.contains { $0.kind == .platformQuality })
        XCTAssertTrue(snapshot.publicSummary.visibleGroupCount >= 6)
        XCTAssertTrue(snapshot.publicSummary.visibleModuleCount >= 12)
        XCTAssertTrue(snapshot.nextActions.allSatisfy { !$0.writesSystem && !$0.sendsNotification })
    }

    func testRelativeAndTeacherViewsAreScoped() {
        let relative = builder.build(viewerRole: .relative)
        let teacher = builder.build(viewerRole: .teacher)

        XCTAssertTrue(relative.modules.contains { $0.group == .familyHonor })
        XCTAssertTrue(relative.modules.contains { $0.key == .notificationDigestConsent && $0.group == .schoolLearning })
        XCTAssertFalse(relative.modules.contains { $0.group == .growthPacks })
        XCTAssertFalse(relative.modules.contains { $0.group == .creditReward })
        XCTAssertFalse(relative.modules.contains { $0.key == .schoolHomework })
        XCTAssertFalse(relative.modules.contains { $0.key == .aiHomeworkGuide })
        XCTAssertFalse(relative.modules.contains { $0.key == .schoolJointApproval })
        XCTAssertFalse(relative.modules.contains { $0.group == .platformQuality })
        XCTAssertFalse(relative.modules.contains { $0.key == .moduleConfigurationDraft })

        XCTAssertTrue(teacher.modules.allSatisfy { $0.group == .schoolLearning })
        XCTAssertTrue(teacher.modules.contains { $0.key == .schoolJointApproval })
        XCTAssertTrue(teacher.modules.contains { $0.key == .notificationDigestConsent })
        XCTAssertFalse(teacher.modules.contains { $0.group == .creditReward })
        XCTAssertFalse(teacher.modules.contains { $0.group == .familyHonor })
        XCTAssertFalse(teacher.modules.contains { $0.group == .platformQuality })
        XCTAssertFalse(teacher.modules.contains { $0.key == .moduleConfigurationDraft })
    }

    func testPublicSummaryAndCardsAreReadOnly() {
        let snapshot = builder.build(viewerRole: .guardian)
        let summary = snapshot.publicSummary

        XCTAssertFalse(snapshot.sideEffects.hasTriggeredSideEffect)
        XCTAssertFalse(summary.callsNetwork)
        XCTAssertFalse(summary.callsAiProvider)
        XCTAssertFalse(summary.callsLocalModel)
        XCTAssertFalse(summary.callsLms)
        XCTAssertFalse(summary.writesSchoolSystem)
        XCTAssertFalse(summary.writesLedger)
        XCTAssertFalse(summary.grantsCredit)
        XCTAssertFalse(summary.unlocksDevice)
        XCTAssertFalse(summary.sendsNotification)
        XCTAssertFalse(summary.uploadsMedia)
        XCTAssertFalse(summary.writesEntitlement)
        XCTAssertFalse(summary.createsOrder)

        XCTAssertTrue(snapshot.modules.allSatisfy { module in
            !module.callsNetwork
                && !module.callsAiProvider
                && !module.callsLms
                && !module.writesSchoolSystem
                && !module.writesLedger
                && !module.grantsCredit
                && !module.unlocksDevice
                && !module.sendsNotification
                && !module.writesEntitlement
                && !module.createsOrder
        })
    }

    func testSnapshotIsStableAndProgressBounded() {
        let first = builder.build(viewerRole: .guardian)
        let second = builder.build(viewerRole: .guardian)

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.modules.allSatisfy { (0...100).contains($0.progress) })
        XCTAssertTrue((0...100).contains(first.publicSummary.averageProgress))
    }

    func testUnsafeInputFallsBackWithoutEchoingRawPayload() {
        let snapshot = builder.build(
            viewerRole: .guardian,
            unsafePayload: [
                "provider:model:qwen http://192.168.1.252/v1 token sk-test s.k-t.e.s.t /Users/developer/private task:raw claim:raw"
            ]
        )

        XCTAssertEqual(snapshot.status, .blocked)
        XCTAssertTrue(snapshot.groups.isEmpty)
        XCTAssertEqual(snapshot.publicSummary.findingCodes, [.unsafeInputBlocked])
        XCTAssertFalse(displayedText(snapshot).localizedCaseInsensitiveContains("192.168.1.252"))
        XCTAssertFalse(displayedText(snapshot).localizedCaseInsensitiveContains("sk-test"))
        XCTAssertFalse(displayedText(snapshot).localizedCaseInsensitiveContains("/Users/developer"))
        XCTAssertFalse(displayedText(snapshot).localizedCaseInsensitiveContains("task:raw"))
        XCTAssertFalse(displayedText(snapshot).localizedCaseInsensitiveContains("claim:raw"))
    }

    func testOutputDoesNotLeakSensitiveMarkers() {
        for role in MobileModuleLaunchCenterViewerRole.allCases {
            let snapshot = builder.build(viewerRole: role)
            let text = displayedText(snapshot)
            for marker in [
                "publicRef",
                "provider:",
                "model:",
                "transcript",
                "答案键",
                "成长积分金额",
                "task:",
                "claim:",
                "ledger:",
                "order:",
                "entitlement:",
                "http://",
                "https://",
                "192.168.",
                "/Users/",
                "/Volumes/"
            ] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "\(role.label) leaked \(marker)")
            }
        }
    }

    func testRoutesMatchVisibleModulesForEveryRole() {
        for role in MobileModuleLaunchCenterViewerRole.allCases {
            let snapshot = builder.build(viewerRole: role)
            let routes = routeResolver.routes(for: snapshot)

            XCTAssertEqual(routes.map(\.moduleKey).sorted(by: { $0.rawValue < $1.rawValue }),
                           snapshot.modules.map(\.key).sorted(by: { $0.rawValue < $1.rawValue }),
                           "\(role.label) route mismatch")
            XCTAssertTrue(routes.allSatisfy { $0.viewerRole == role })
            XCTAssertTrue(routes.allSatisfy { $0.allowedRoles.contains(role) })
        }
    }

    func testDestinationKindsDeclareWhetherModuleCenterMustLockRole() {
        let lockedKinds: Set<MobileModuleLaunchRouteDestinationKind> = [
            .growthPackEntitlement,
            .aiHomeworkInbox,
            .schoolJointApproval,
            .notificationDigestConsent,
            .familyStorylineConsent,
            .growthDiaryVlogStoryline,
            .familyAchievementDashboard,
            .appSelectionWorkbench,
            .reportsWorkbench,
            .onboardingGuide,
            .releaseGate,
            .familySocialFeedbackEmotionalSafetyCenter
        ]

        for kind in MobileModuleLaunchRouteDestinationKind.allCases {
            let route = MobileModuleLaunchRoute(
                publicRouteRef: "mlr-test-\(kind.rawValue)",
                moduleKey: .todayTasks,
                viewerRole: .child,
                destinationKind: kind,
                title: "安全路由",
                subtitle: "本地只读入口",
                allowedRoles: [.child],
                opensExistingPage: kind != .safePreview
            )

            XCTAssertEqual(route.supportsDestinationRoleSwitching, lockedKinds.contains(kind), kind.rawValue)
            XCTAssertEqual(route.shouldLockDestinationRole, lockedKinds.contains(kind), kind.rawValue)
            XCTAssertTrue(routeResolver.redacts([route]), kind.rawValue)
        }
    }

    func testResolvedRoutesLockRoleSwitchingTargets() {
        let lockedKinds: Set<MobileModuleLaunchRouteDestinationKind> = [
            .growthPackEntitlement,
            .aiHomeworkInbox,
            .schoolJointApproval,
            .notificationDigestConsent,
            .familyStorylineConsent,
            .growthDiaryVlogStoryline,
            .familyAchievementDashboard,
            .appSelectionWorkbench,
            .reportsWorkbench,
            .onboardingGuide,
            .releaseGate,
            .familySocialFeedbackEmotionalSafetyCenter
        ]

        for role in MobileModuleLaunchCenterViewerRole.allCases {
            let routes = routeResolver.routes(for: builder.build(viewerRole: role))

            XCTAssertTrue(routes.allSatisfy { $0.allowedRoles.contains($0.viewerRole) }, role.label)
            XCTAssertTrue(routes.allSatisfy { route in
                route.shouldLockDestinationRole == lockedKinds.contains(route.destinationKind)
            }, role.label)
            XCTAssertTrue(routes.filter(\.shouldLockDestinationRole).allSatisfy {
                lockedKinds.contains($0.destinationKind)
            }, role.label)
        }
    }

    @MainActor
    func testAllResolvedRouteDestinationsHaveInstantiableViews() {
        let familyAchievementStore = FamilyGrowthAchievementStore()

        for role in MobileModuleLaunchCenterViewerRole.allCases {
            let routes = routeResolver.routes(for: builder.build(viewerRole: role))
            XCTAssertFalse(routes.isEmpty, role.label)

            for route in routes {
                XCTAssertNoThrow(
                    _ = destinationProbe(for: route, familyAchievementStore: familyAchievementStore),
                    "\(role.label) \(route.moduleKey.rawValue) -> \(route.destinationKind.rawValue)"
                )
            }
        }
    }

    func testTodayTasksRoutesToChildCheckinAndGuardianApprovalWorkbench() {
        let childRoute = routeResolver.route(for: .todayTasks, viewerRole: .child)
        let guardianRoute = routeResolver.route(for: .todayTasks, viewerRole: .guardian)

        XCTAssertEqual(childRoute?.destinationKind, .basicHabitCheckin)
        XCTAssertEqual(guardianRoute?.destinationKind, .guardianTaskReview)
        XCTAssertEqual(guardianRoute?.title, "打开家长批准台")
        XCTAssertFalse(childRoute?.shouldLockDestinationRole ?? true)
        XCTAssertFalse(guardianRoute?.shouldLockDestinationRole ?? true)
        XCTAssertFalse(childRoute?.hasTriggeredSideEffect ?? true)
        XCTAssertFalse(guardianRoute?.hasTriggeredSideEffect ?? true)
    }

    func testPrimaryPhoneTrialRouteChainIsConnectedWithoutRouteSideEffects() throws {
        let childSubmit = try XCTUnwrap(routeResolver.route(for: .todayTasks, viewerRole: .child))
        let guardianApprove = try XCTUnwrap(routeResolver.route(for: .todayTasks, viewerRole: .guardian))
        let guardianCredit = try XCTUnwrap(routeResolver.route(for: .creditLedger, viewerRole: .guardian))
        let childReward = try XCTUnwrap(routeResolver.route(for: .rewardWindow, viewerRole: .child))
        let guardianRewardStatus = try XCTUnwrap(routeResolver.route(for: .rewardWindow, viewerRole: .guardian))
        let childRewardStore = try XCTUnwrap(routeResolver.route(for: .rewardStoreFulfillment, viewerRole: .child))

        XCTAssertEqual(childSubmit.destinationKind, .basicHabitCheckin)
        XCTAssertEqual(guardianApprove.destinationKind, .guardianTaskReview)
        XCTAssertEqual(guardianCredit.destinationKind, .creditLedgerReview)
        XCTAssertEqual(childReward.destinationKind, .rewardRedemption)
        XCTAssertEqual(guardianRewardStatus.destinationKind, .rewardStatus)
        XCTAssertEqual(childRewardStore.destinationKind, .rewardStoreFulfillment)

        for route in [childSubmit, guardianApprove, guardianCredit, childReward, guardianRewardStatus, childRewardStore] {
            XCTAssertTrue(route.opensExistingPage, route.moduleKey.rawValue)
            XCTAssertFalse(route.hasTriggeredSideEffect, route.moduleKey.rawValue)
        }
    }

    func testUnreachableDestinationKindsAreExplicitlyDocumented() {
        let producedKinds = Set(
            MobileModuleLaunchCenterViewerRole.allCases.flatMap { role in
                routeResolver.routes(for: builder.build(viewerRole: role)).map(\.destinationKind)
            }
        )

        XCTAssertEqual(
            Set(MobileModuleLaunchRouteDestinationKind.allCases).subtracting(producedKinds),
            [.childTaskList, .familyStorylineConsent]
        )
    }

    func testRoleScopedRoutesStayInsideModuleBoundaries() {
        let childRoutes = routeResolver.routes(for: builder.build(viewerRole: .child))
        let guardianRoutes = routeResolver.routes(for: builder.build(viewerRole: .guardian))
        let relativeRoutes = routeResolver.routes(for: builder.build(viewerRole: .relative))
        let teacherRoutes = routeResolver.routes(for: builder.build(viewerRole: .teacher))
        let operationsRoutes = routeResolver.routes(for: builder.build(viewerRole: .operations))

        XCTAssertFalse(childRoutes.contains { $0.moduleKey == .releaseGate })
        XCTAssertFalse(childRoutes.contains { $0.moduleKey == .moduleConfigurationDraft })
        XCTAssertTrue(guardianRoutes.contains { $0.destinationKind == .releaseGate })
        XCTAssertTrue(guardianRoutes.contains { $0.moduleKey == .moduleConfigurationDraft && $0.destinationKind == .moduleConfigurationDraft })
        XCTAssertEqual(Set(relativeRoutes.map(\.moduleKey)), [.notificationDigestConsent, .familyStoryline, .honorWall, .familySocialFeedbackEmotionalSafety])
        XCTAssertEqual(Set(teacherRoutes.map(\.moduleKey)), [.schoolHomework, .aiHomeworkGuide, .schoolJointApproval, .notificationDigestConsent])
        XCTAssertTrue(operationsRoutes.contains { $0.moduleKey == .releaseGate && $0.destinationKind == .releaseGate })
        XCTAssertTrue(operationsRoutes.contains { $0.moduleKey == .moduleConfigurationDraft && $0.destinationKind == .safePreview })
        XCTAssertTrue(operationsRoutes.contains { $0.moduleKey == .schoolJointApproval && $0.destinationKind == .safePreview })
        XCTAssertTrue(operationsRoutes.contains { $0.moduleKey == .notificationDigestConsent && $0.destinationKind == .safePreview })
        XCTAssertTrue(operationsRoutes.contains { $0.moduleKey == .familyStoryline && $0.destinationKind == .safePreview })
        XCTAssertTrue(operationsRoutes.contains { $0.moduleKey == .honorWall && $0.destinationKind == .safePreview })
        XCTAssertTrue(operationsRoutes.contains { $0.moduleKey == .appSelectionPolicy && $0.destinationKind == .safePreview })
        XCTAssertTrue(operationsRoutes.contains { $0.moduleKey == .onboardingGuide && $0.destinationKind == .safePreview })
        XCTAssertTrue(operationsRoutes.contains { $0.moduleKey == .growthPackRuntime && $0.destinationKind == .safePreview })
        XCTAssertTrue(childRoutes.contains { $0.moduleKey == .growthPackRuntime && $0.destinationKind == .growthPackDetail })
        XCTAssertTrue(guardianRoutes.contains { $0.moduleKey == .growthPackRuntime && $0.destinationKind == .growthPackDetail })
    }

    func testNewLocalWorkbenchesAreDiscoverableFromModuleCenter() {
        let child = builder.build(viewerRole: .child)
        let guardian = builder.build(viewerRole: .guardian)
        let operations = builder.build(viewerRole: .operations)

        XCTAssertTrue(child.modules.contains { $0.key == .appSelectionPolicy && $0.group == .creditReward })
        XCTAssertTrue(child.modules.contains { $0.key == .reportsPreview && $0.group == .familyHonor })
        XCTAssertTrue(child.modules.contains { $0.key == .onboardingGuide && $0.group == .platformSync })

        XCTAssertTrue(guardian.modules.contains { $0.key == .appSelectionPolicy && $0.group == .creditReward })
        XCTAssertTrue(guardian.modules.contains { $0.key == .reportsPreview && $0.group == .familyHonor })
        XCTAssertTrue(guardian.modules.contains { $0.key == .onboardingGuide && $0.group == .platformSync })

        XCTAssertTrue(operations.modules.contains { $0.key == .appSelectionPolicy && $0.group == .creditReward })
        XCTAssertFalse(operations.modules.contains { $0.key == .reportsPreview })
        XCTAssertTrue(operations.modules.contains { $0.key == .onboardingGuide && $0.group == .platformSync })
    }

    func testFamilyStorylineCardSurfacesReleaseGateState() throws {
        let guardian = builder.build(viewerRole: .guardian)
        let relative = builder.build(viewerRole: .relative)
        let guardianCard = try XCTUnwrap(guardian.modules.first { $0.key == .familyStoryline })
        let relativeCard = try XCTUnwrap(relative.modules.first { $0.key == .familyStoryline })

        XCTAssertEqual(guardianCard.group, .familyHonor)
        XCTAssertTrue(guardianCard.detail.contains("故事线门禁"))
        XCTAssertTrue(guardianCard.detail.contains("候选"))
        XCTAssertTrue(guardianCard.detail.contains("待处理"))
        XCTAssertTrue(guardianCard.detail.contains("阻断"))
        XCTAssertTrue(guardianCard.detail.contains("只读预览"))
        XCTAssertTrue(guardianCard.detail.contains("不发布"))
        XCTAssertTrue(guardianCard.detail.contains("不通知"))
        XCTAssertTrue(guardianCard.detail.contains("不发成长积分"))
        XCTAssertGreaterThanOrEqual(guardianCard.progress, 55)
        XCTAssertLessThanOrEqual(guardianCard.progress, 94)

        XCTAssertTrue(relativeCard.detail.contains("故事线门禁"))
        XCTAssertFalse(relativeCard.actionRequired, "亲友视角只能看到只读故事线门禁状态，不能形成处理入口")
    }

    func testNewLocalWorkbenchRoutesAreRoleScopedReadOnlyAndRedacted() {
        let childAppSelection = routeResolver.route(for: .appSelectionPolicy, viewerRole: .child)
        let guardianAppSelection = routeResolver.route(for: .appSelectionPolicy, viewerRole: .guardian)
        let operationsAppSelection = routeResolver.route(for: .appSelectionPolicy, viewerRole: .operations)
        let childReports = routeResolver.route(for: .reportsPreview, viewerRole: .child)
        let guardianReports = routeResolver.route(for: .reportsPreview, viewerRole: .guardian)
        let operationsReports = routeResolver.route(for: .reportsPreview, viewerRole: .operations)
        let childOnboarding = routeResolver.route(for: .onboardingGuide, viewerRole: .child)
        let guardianOnboarding = routeResolver.route(for: .onboardingGuide, viewerRole: .guardian)
        let operationsOnboarding = routeResolver.route(for: .onboardingGuide, viewerRole: .operations)

        XCTAssertEqual(MobileModuleLaunchModuleKey.appSelectionPolicy.rawValue, "app_selection_policy")
        XCTAssertEqual(MobileModuleLaunchRouteDestinationKind.appSelectionWorkbench.rawValue, "app_selection_workbench")
        XCTAssertEqual(childAppSelection?.destinationKind, .appSelectionWorkbench)
        XCTAssertEqual(guardianAppSelection?.destinationKind, .appSelectionWorkbench)
        XCTAssertEqual(operationsAppSelection?.destinationKind, .safePreview)

        XCTAssertEqual(MobileModuleLaunchModuleKey.reportsPreview.rawValue, "reports_preview")
        XCTAssertEqual(MobileModuleLaunchRouteDestinationKind.reportsWorkbench.rawValue, "reports_workbench")
        XCTAssertEqual(childReports?.destinationKind, .reportsWorkbench)
        XCTAssertEqual(guardianReports?.destinationKind, .reportsWorkbench)
        XCTAssertNil(operationsReports)

        XCTAssertEqual(MobileModuleLaunchModuleKey.onboardingGuide.rawValue, "onboarding_guide")
        XCTAssertEqual(MobileModuleLaunchRouteDestinationKind.onboardingGuide.rawValue, "onboarding_guide")
        XCTAssertEqual(childOnboarding?.destinationKind, .onboardingGuide)
        XCTAssertEqual(guardianOnboarding?.destinationKind, .onboardingGuide)
        XCTAssertEqual(operationsOnboarding?.destinationKind, .safePreview)

        let existingPageRoutes = [
            childAppSelection,
            guardianAppSelection,
            childReports,
            guardianReports,
            childOnboarding,
            guardianOnboarding
        ].compactMap { $0 }
        XCTAssertTrue(existingPageRoutes.allSatisfy(\.opensExistingPage))
        XCTAssertTrue(existingPageRoutes.allSatisfy(\.shouldLockDestinationRole))
        XCTAssertTrue(routeResolver.redacts(existingPageRoutes + [operationsAppSelection, operationsOnboarding].compactMap { $0 }))
        XCTAssertTrue((existingPageRoutes + [operationsAppSelection, operationsOnboarding].compactMap { $0 }).allSatisfy { !$0.hasTriggeredSideEffect })
    }

    func testFamilyStorylineRoutesToGrowthDiaryVlogWorkbench() {
        let childRoute = routeResolver.route(for: .familyStoryline, viewerRole: .child)
        let guardianRoute = routeResolver.route(for: .familyStoryline, viewerRole: .guardian)
        let relativeRoute = routeResolver.route(for: .familyStoryline, viewerRole: .relative)
        let operationsRoute = routeResolver.route(for: .familyStoryline, viewerRole: .operations)

        XCTAssertEqual(MobileModuleLaunchRouteDestinationKind.growthDiaryVlogStoryline.rawValue, "growth_diary_vlog_storyline")
        XCTAssertEqual(childRoute?.destinationKind, .growthDiaryVlogStoryline)
        XCTAssertEqual(guardianRoute?.destinationKind, .growthDiaryVlogStoryline)
        XCTAssertEqual(relativeRoute?.destinationKind, .growthDiaryVlogStoryline)
        XCTAssertEqual(operationsRoute?.destinationKind, .safePreview)
        XCTAssertTrue([childRoute, guardianRoute, relativeRoute].compactMap { $0 }.allSatisfy(\.shouldLockDestinationRole))
        XCTAssertTrue(routeResolver.redacts([childRoute, guardianRoute, relativeRoute, operationsRoute].compactMap { $0 }))
        XCTAssertFalse(childRoute?.hasTriggeredSideEffect ?? true)
        XCTAssertFalse(guardianRoute?.hasTriggeredSideEffect ?? true)
        XCTAssertFalse(relativeRoute?.hasTriggeredSideEffect ?? true)
    }

    func testEmotionalSafetyCenterRouteIsScopedAcrossFamilyExpertRoles() {
        let childRoute = routeResolver.route(for: .familySocialFeedbackEmotionalSafety, viewerRole: .child)
        let guardianRoute = routeResolver.route(for: .familySocialFeedbackEmotionalSafety, viewerRole: .guardian)
        let relativeRoute = routeResolver.route(for: .familySocialFeedbackEmotionalSafety, viewerRole: .relative)
        let operationsRoute = routeResolver.route(for: .familySocialFeedbackEmotionalSafety, viewerRole: .operations)
        let teacherRoute = routeResolver.route(for: .familySocialFeedbackEmotionalSafety, viewerRole: .teacher)

        XCTAssertEqual(MobileModuleLaunchModuleKey.familySocialFeedbackEmotionalSafety.rawValue, "family_social_feedback_emotional_safety")
        XCTAssertEqual(MobileModuleLaunchRouteDestinationKind.familySocialFeedbackEmotionalSafetyCenter.rawValue, "family_social_feedback_emotional_safety_center")
        // 孩子 / 家长 / 亲友 / 专家（运营视角）都进入情绪安全中心视图，老师不在 allowedRoles 内。
        XCTAssertEqual(childRoute?.destinationKind, .familySocialFeedbackEmotionalSafetyCenter)
        XCTAssertEqual(guardianRoute?.destinationKind, .familySocialFeedbackEmotionalSafetyCenter)
        XCTAssertEqual(relativeRoute?.destinationKind, .familySocialFeedbackEmotionalSafetyCenter)
        XCTAssertEqual(operationsRoute?.destinationKind, .familySocialFeedbackEmotionalSafetyCenter)
        XCTAssertNil(teacherRoute)
        // 该目标页自带视角切换器，从模块中心进入必须锁定单一角色，避免越权切视角。
        XCTAssertTrue([childRoute, guardianRoute, relativeRoute, operationsRoute].compactMap { $0 }.allSatisfy(\.shouldLockDestinationRole))
        XCTAssertTrue([childRoute, guardianRoute, relativeRoute, operationsRoute].compactMap { $0 }.allSatisfy { $0.opensExistingPage })
        XCTAssertTrue(routeResolver.redacts([childRoute, guardianRoute, relativeRoute, operationsRoute].compactMap { $0 }))
        XCTAssertFalse(childRoute?.hasTriggeredSideEffect ?? true)
        XCTAssertFalse(guardianRoute?.hasTriggeredSideEffect ?? true)
        XCTAssertFalse(relativeRoute?.hasTriggeredSideEffect ?? true)
        XCTAssertFalse(operationsRoute?.hasTriggeredSideEffect ?? true)
    }

    func testNotificationDigestConsentRouteIsScopedAcrossFamilySchoolRoles() {
        let childRoute = routeResolver.route(for: .notificationDigestConsent, viewerRole: .child)
        let guardianRoute = routeResolver.route(for: .notificationDigestConsent, viewerRole: .guardian)
        let relativeRoute = routeResolver.route(for: .notificationDigestConsent, viewerRole: .relative)
        let teacherRoute = routeResolver.route(for: .notificationDigestConsent, viewerRole: .teacher)
        let operationsRoute = routeResolver.route(for: .notificationDigestConsent, viewerRole: .operations)

        XCTAssertEqual(MobileModuleLaunchModuleKey.notificationDigestConsent.rawValue, "notification_digest_consent")
        XCTAssertEqual(MobileModuleLaunchRouteDestinationKind.notificationDigestConsent.rawValue, "notification_digest_consent")
        XCTAssertEqual(childRoute?.destinationKind, .notificationDigestConsent)
        XCTAssertEqual(guardianRoute?.destinationKind, .notificationDigestConsent)
        XCTAssertEqual(relativeRoute?.destinationKind, .notificationDigestConsent)
        XCTAssertEqual(teacherRoute?.destinationKind, .notificationDigestConsent)
        XCTAssertEqual(operationsRoute?.destinationKind, .safePreview)
        XCTAssertEqual(operationsRoute?.opensExistingPage, false)
        XCTAssertTrue([childRoute, guardianRoute, relativeRoute, teacherRoute].compactMap { $0 }.allSatisfy(\.shouldLockDestinationRole))
        XCTAssertTrue(routeResolver.redacts([childRoute, guardianRoute, relativeRoute, teacherRoute, operationsRoute].compactMap { $0 }))
    }

    func testSchoolJointApprovalRouteIsScopedToSchoolRoles() {
        let childRoute = routeResolver.route(for: .schoolJointApproval, viewerRole: .child)
        let guardianRoute = routeResolver.route(for: .schoolJointApproval, viewerRole: .guardian)
        let teacherRoute = routeResolver.route(for: .schoolJointApproval, viewerRole: .teacher)
        let operationsRoute = routeResolver.route(for: .schoolJointApproval, viewerRole: .operations)

        XCTAssertEqual(childRoute?.destinationKind, .schoolJointApproval)
        XCTAssertEqual(guardianRoute?.destinationKind, .schoolJointApproval)
        XCTAssertEqual(teacherRoute?.destinationKind, .schoolJointApproval)
        XCTAssertEqual(operationsRoute?.destinationKind, .safePreview)
        XCTAssertEqual(operationsRoute?.opensExistingPage, false)
        XCTAssertNil(routeResolver.route(for: .schoolJointApproval, viewerRole: .relative))
        XCTAssertTrue([childRoute, guardianRoute, teacherRoute].compactMap { $0 }.allSatisfy(\.shouldLockDestinationRole))
        XCTAssertTrue(routeResolver.redacts([childRoute, guardianRoute, teacherRoute, operationsRoute].compactMap { $0 }))
    }

    func testConfigurationDraftRouteIsGuardianOnlyWithOperationsSafePreview() {
        let guardianRoute = routeResolver.routes(for: builder.build(viewerRole: .guardian))
            .first { $0.moduleKey == .moduleConfigurationDraft }
        let operationsRoute = routeResolver.routes(for: builder.build(viewerRole: .operations))
            .first { $0.moduleKey == .moduleConfigurationDraft }

        XCTAssertEqual(guardianRoute?.destinationKind, .moduleConfigurationDraft)
        XCTAssertEqual(guardianRoute?.allowedRoles, [.guardian, .operations])
        XCTAssertEqual(operationsRoute?.destinationKind, .safePreview)
        XCTAssertEqual(operationsRoute?.opensExistingPage, false)
        XCTAssertNil(routeResolver.route(for: .moduleConfigurationDraft, viewerRole: .child))
        XCTAssertNil(routeResolver.route(for: .moduleConfigurationDraft, viewerRole: .relative))
        XCTAssertNil(routeResolver.route(for: .moduleConfigurationDraft, viewerRole: .teacher))
    }

    func testRoutesAreReadOnlyAndRedacted() {
        for role in MobileModuleLaunchCenterViewerRole.allCases {
            let routes = routeResolver.routes(for: builder.build(viewerRole: role))

            XCTAssertFalse(routes.isEmpty, "\(role.label) routes should not be empty")
            XCTAssertTrue(routeResolver.redacts(routes), "\(role.label) route text leaked")
            XCTAssertTrue(routes.allSatisfy { route in
                !route.hasTriggeredSideEffect
                    && !route.callsNetwork
                    && !route.callsAiProvider
                    && !route.callsLocalModel
                    && !route.callsLms
                    && !route.writesSchoolSystem
                    && !route.writesLedger
                    && !route.grantsCredit
                    && !route.unlocksDevice
                    && !route.sendsNotification
                    && !route.uploadsMedia
                    && !route.writesEntitlement
                    && !route.createsOrder
            })
        }
    }

    func testRoutePublicRefsAreStableAcrossResolverInstances() {
        let snapshot = builder.build(viewerRole: .guardian)
        let first = MobileModuleLaunchRouteResolver().routes(for: snapshot)
        let second = MobileModuleLaunchRouteResolver().routes(for: snapshot)

        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first.map(\.publicRouteRef), second.map(\.publicRouteRef))
        XCTAssertTrue(first.allSatisfy { $0.publicRouteRef.hasPrefix("mlr-") })
    }

    func testOfflineSyncReviewVisibleToChildAndGuardianInSyncGroup() {
        let child = builder.build(viewerRole: .child)
        let guardian = builder.build(viewerRole: .guardian)

        XCTAssertTrue(child.modules.contains { $0.key == .offlineSyncReview && $0.group == .platformSync })
        XCTAssertTrue(guardian.modules.contains { $0.key == .offlineSyncReview && $0.group == .platformSync })
        XCTAssertTrue(child.groups.contains { $0.kind == .platformSync })
        XCTAssertTrue(guardian.groups.contains { $0.kind == .platformSync })
        // 同步复核归入独立分组，孩子可见但不暴露成人平台质量门。
        XCTAssertFalse(child.modules.contains { $0.group == .platformQuality })
    }

    func testOfflineSyncReviewHiddenFromRelativeAndTeacher() {
        let relative = builder.build(viewerRole: .relative)
        let teacher = builder.build(viewerRole: .teacher)

        XCTAssertFalse(relative.modules.contains { $0.key == .offlineSyncReview })
        XCTAssertFalse(teacher.modules.contains { $0.key == .offlineSyncReview })
        XCTAssertNil(routeResolver.route(for: .offlineSyncReview, viewerRole: .relative))
        XCTAssertNil(routeResolver.route(for: .offlineSyncReview, viewerRole: .teacher))
    }

    func testOfflineSyncReviewRouteDestinationsByRole() {
        let childRoute = routeResolver.route(for: .offlineSyncReview, viewerRole: .child)
        let guardianRoute = routeResolver.route(for: .offlineSyncReview, viewerRole: .guardian)
        let operationsRoute = routeResolver.route(for: .offlineSyncReview, viewerRole: .operations)

        XCTAssertEqual(childRoute?.destinationKind, .offlineSyncReview)
        XCTAssertEqual(childRoute?.viewerRole, .child)
        XCTAssertEqual(childRoute?.opensExistingPage, true)
        XCTAssertEqual(guardianRoute?.destinationKind, .offlineSyncReview)
        XCTAssertEqual(guardianRoute?.viewerRole, .guardian)
        XCTAssertEqual(guardianRoute?.opensExistingPage, true)
        // 运营如需只看脱敏安全预览，不进入家庭内部复核台。
        XCTAssertEqual(operationsRoute?.destinationKind, .safePreview)
        XCTAssertEqual(operationsRoute?.opensExistingPage, false)
        XCTAssertEqual(childRoute?.allowedRoles, [.child, .guardian, .operations])

        // 复核台自身按 perspective 锁定，模块中心不强加额外角色锁。
        XCTAssertFalse(childRoute?.shouldLockDestinationRole ?? true)
        XCTAssertFalse(guardianRoute?.shouldLockDestinationRole ?? true)
    }

    func testOfflineSyncReviewRawValuesAndRedaction() {
        XCTAssertEqual(MobileModuleLaunchModuleKey.offlineSyncReview.rawValue, "offline_sync_review")
        XCTAssertEqual(MobileModuleLaunchRouteDestinationKind.offlineSyncReview.rawValue, "offline_sync_review")
        XCTAssertEqual(MobileModuleLaunchGroupKind.platformSync.rawValue, "platform_sync")

        for role in MobileModuleLaunchCenterViewerRole.allCases {
            guard let route = routeResolver.route(for: .offlineSyncReview, viewerRole: role) else { continue }
            XCTAssertTrue(routeResolver.redacts([route]), role.label)
            XCTAssertFalse(route.hasTriggeredSideEffect, role.label)
        }
    }

    func testOfflineSyncReviewCardHasNoSideEffects() {
        for role in [MobileModuleLaunchCenterViewerRole.child, .guardian, .operations] {
            let snapshot = builder.build(viewerRole: role)
            guard let card = snapshot.modules.first(where: { $0.key == .offlineSyncReview }) else {
                XCTFail("\(role.label) 缺少离线同步复核模块")
                continue
            }
            XCTAssertFalse(card.actionRequired, role.label)
            XCTAssertFalse(
                card.callsNetwork || card.callsAiProvider || card.callsLms || card.writesSchoolSystem
                    || card.writesLedger || card.grantsCredit || card.unlocksDevice || card.sendsNotification
                    || card.writesEntitlement || card.createsOrder,
                role.label
            )
        }
    }

    // MARK: - 发现筛选与下一步推荐

    func testDiscoveryDefaultFilterShowsAllVisibleModules() {
        for role in MobileModuleLaunchCenterViewerRole.allCases {
            let snapshot = builder.build(viewerRole: role)
            let result = MobileModuleLaunchCenterDiscovery.apply(
                MobileModuleLaunchCenterDiscoveryFilter(),
                to: snapshot
            )

            XCTAssertFalse(result.hasActiveFilter, role.label)
            XCTAssertEqual(result.matchedCount, snapshot.modules.count, role.label)
            XCTAssertEqual(
                Set(result.modules.map(\.key)),
                Set(snapshot.modules.map(\.key)),
                role.label
            )
            XCTAssertEqual(result.totalVisibleCount, snapshot.modules.count, role.label)
            XCTAssertNil(result.emptyStateMessage, role.label)
        }
    }

    func testDiscoveryGroupFilterKeepsOnlyChosenGroup() {
        let snapshot = builder.build(viewerRole: .guardian)
        let filter = MobileModuleLaunchCenterDiscoveryFilter(group: .creditReward)
        let result = MobileModuleLaunchCenterDiscovery.apply(filter, to: snapshot)

        XCTAssertTrue(result.hasActiveFilter)
        XCTAssertFalse(result.modules.isEmpty)
        XCTAssertTrue(result.modules.allSatisfy { $0.group == .creditReward })
        XCTAssertTrue(result.availableGroups.contains(.creditReward))
        // 分组筛选只缩小可见模块，不引入 snapshot 之外的模块。
        XCTAssertTrue(result.modules.allSatisfy { module in
            snapshot.modules.contains { $0.key == module.key }
        })
    }

    func testChildCreditLedgerModuleUsesGrowthCreditUnitCopy() throws {
        let snapshot = builder.build(viewerRole: .child)
        let module = try XCTUnwrap(snapshot.modules.first { $0.key == .creditLedger })

        XCTAssertTrue(module.detail.contains("成长积分"))
        XCTAssertFalse(module.detail.contains("待确认分钟"))
    }

    func testDiscoveryStatusFilterKeepsOnlyChosenStatus() {
        let snapshot = builder.build(viewerRole: .guardian)
        guard let status = snapshot.modules.first(where: { $0.status == .reviewRequired })?.status else {
            return XCTFail("家长视角应至少有一个需复核模块")
        }
        let result = MobileModuleLaunchCenterDiscovery.apply(
            MobileModuleLaunchCenterDiscoveryFilter(status: status),
            to: snapshot
        )

        XCTAssertFalse(result.modules.isEmpty)
        XCTAssertTrue(result.modules.allSatisfy { $0.status == status })
    }

    func testDiscoverySearchMatchesSafeDisplayFieldsOnly() {
        let snapshot = builder.build(viewerRole: .guardian)
        guard let target = snapshot.modules.first(where: { $0.key == .creditLedger }) else {
            return XCTFail("家长视角应包含成长积分账本模块")
        }

        // 用标题中的安全词可以搜到目标模块。
        let byTitle = MobileModuleLaunchCenterDiscovery.apply(
            MobileModuleLaunchCenterDiscoveryFilter(searchText: "成长积分账本"),
            to: snapshot
        )
        XCTAssertTrue(byTitle.modules.contains { $0.key == target.key })
        XCTAssertTrue(byTitle.modules.allSatisfy { module in
            snapshot.modules.contains { $0.key == module.key }
        })
    }

    func testDiscoverySearchDoesNotMatchInternalRefsOrKeys() {
        let snapshot = builder.build(viewerRole: .guardian)
        guard let target = snapshot.modules.first else {
            return XCTFail("家长视角应有模块")
        }

        // 用内部 publicModuleRef 搜索不应命中任何模块（脱敏：搜索不暴露内部引用）。
        let byRef = MobileModuleLaunchCenterDiscovery.apply(
            MobileModuleLaunchCenterDiscoveryFilter(searchText: target.publicModuleRef),
            to: snapshot
        )
        XCTAssertTrue(byRef.isEmpty)
        XCTAssertEqual(byRef.emptyStateMessage, "没有符合当前搜索或筛选的模块，请调整关键词、分组或状态。")

        // 用原始 key（如 credit_ledger）搜索也不应命中。
        let byKey = MobileModuleLaunchCenterDiscovery.apply(
            MobileModuleLaunchCenterDiscoveryFilter(searchText: target.key.rawValue),
            to: snapshot
        )
        XCTAssertTrue(byKey.isEmpty)
    }

    func testDiscoverySearchIgnoresUnsafeDisplayFieldIfUpstreamIsPolluted() {
        let polluted = MobileModuleLaunchModuleCard(
            publicModuleRef: "mlc-test-polluted",
            key: .todayTasks,
            group: .basicTasks,
            title: "安全标题",
            detail: "http://192.168.1.252 token sk-test /Users/developer/private",
            status: .ready,
            progress: 20,
            actionRequired: false,
            routeHint: "provider:qwen task:raw claim:raw",
            visibleToChild: true,
            visibleToGuardian: true,
            visibleToRelative: true,
            visibleToTeacher: true,
            visibleToOperations: true
        )

        for keyword in ["192.168.1.252", "sk-test", "/Users/developer", "provider:qwen", "task:raw"] {
            let result = MobileModuleLaunchCenterDiscovery.apply(
                MobileModuleLaunchCenterDiscoveryFilter(searchText: keyword),
                to: [polluted]
            )
            XCTAssertTrue(result.isEmpty, keyword)
        }

        let safeTitle = MobileModuleLaunchCenterDiscovery.apply(
            MobileModuleLaunchCenterDiscoveryFilter(searchText: "安全标题"),
            to: [polluted]
        )
        XCTAssertEqual(safeTitle.modules.map(\.key), [.todayTasks])
    }

    func testDiscoverySearchResultDoesNotLeakSensitiveMarkers() {
        let snapshot = builder.build(viewerRole: .guardian)
        let result = MobileModuleLaunchCenterDiscovery.apply(
            MobileModuleLaunchCenterDiscoveryFilter(searchText: "进行"),
            to: snapshot
        )
        let text = result.modules
            .flatMap { [$0.title, $0.detail, $0.routeHint, $0.status.label, $0.group.title] }
            .joined(separator: " ")
        for marker in ["task:", "claim:", "ledger:", "http://", "192.168.", "/Users/", "token", "publicRef"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), marker)
        }
    }

    func testDiscoveryRecommendedSortPrioritizesActionAndReview() {
        let snapshot = builder.build(viewerRole: .guardian)
        let result = MobileModuleLaunchCenterDiscovery.apply(
            MobileModuleLaunchCenterDiscoveryFilter(sort: .recommended),
            to: snapshot
        )

        XCTAssertFalse(result.modules.isEmpty)
        // 推荐分应单调不增（从前到后递减）。
        let scores = result.modules.map(MobileModuleLaunchCenterDiscovery.recommendationScore)
        XCTAssertEqual(scores, scores.sorted(by: >))
        // 待处理模块应排在不需处理模块之前。
        if let firstNonAction = result.modules.firstIndex(where: { !$0.actionRequired }) {
            let actionTail = result.modules[firstNonAction...].contains { $0.actionRequired }
            XCTAssertFalse(actionTail, "需处理模块应集中在前部")
        }
    }

    func testDiscoveryRecommendedSortFavorsLowerProgressWithinSameStatus() {
        let low = card(key: .todayTasks, group: .basicTasks, status: .active, progress: 20, actionRequired: false)
        let high = card(key: .schoolHomework, group: .schoolLearning, status: .active, progress: 90, actionRequired: false)
        let result = MobileModuleLaunchCenterDiscovery.apply(
            MobileModuleLaunchCenterDiscoveryFilter(sort: .recommended),
            to: [high, low]
        )

        XCTAssertEqual(result.modules.map(\.key), [.todayTasks, .schoolHomework])
    }

    func testDiscoveryOriginalSortKeepsInputOrder() {
        let snapshot = builder.build(viewerRole: .guardian)
        let result = MobileModuleLaunchCenterDiscovery.apply(
            MobileModuleLaunchCenterDiscoveryFilter(sort: .original),
            to: snapshot
        )
        XCTAssertEqual(result.modules.map(\.key), snapshot.modules.map(\.key))
    }

    func testDiscoveryIsDeterministic() {
        let snapshot = builder.build(viewerRole: .guardian)
        let filter = MobileModuleLaunchCenterDiscoveryFilter(searchText: "查看", sort: .recommended)
        let first = MobileModuleLaunchCenterDiscovery.apply(filter, to: snapshot)
        let second = MobileModuleLaunchCenterDiscovery.apply(filter, to: snapshot)
        XCTAssertEqual(first, second)
    }

    func testDiscoveryDoesNotEscalateChildVisibility() {
        let snapshot = builder.build(viewerRole: .child)
        // 即使搜索成人模块名，孩子视角也搜不到（因为它本就不在可见集合里）。
        for keyword in ["发布质量门", "配置草稿", "releaseGate", "module_configuration_draft"] {
            let result = MobileModuleLaunchCenterDiscovery.apply(
                MobileModuleLaunchCenterDiscoveryFilter(searchText: keyword),
                to: snapshot
            )
            XCTAssertFalse(result.modules.contains { $0.key == .releaseGate }, keyword)
            XCTAssertFalse(result.modules.contains { $0.key == .moduleConfigurationDraft }, keyword)
            XCTAssertFalse(result.modules.contains { $0.group == .platformQuality }, keyword)
        }
        // 任何过滤组合都不会让结果超出 snapshot 已可见模块集合。
        let everything = MobileModuleLaunchCenterDiscovery.apply(
            MobileModuleLaunchCenterDiscoveryFilter(),
            to: snapshot
        )
        XCTAssertTrue(everything.modules.allSatisfy { module in
            snapshot.modules.contains { $0.key == module.key }
        })
    }

    func testDiscoveryEmptyStateMessagesAreSafe() {
        let snapshot = builder.build(viewerRole: .guardian)
        let filtered = MobileModuleLaunchCenterDiscovery.apply(
            MobileModuleLaunchCenterDiscoveryFilter(searchText: "不存在的模块关键词zzz"),
            to: snapshot
        )
        XCTAssertTrue(filtered.isEmpty)
        XCTAssertEqual(filtered.emptyStateMessage, "没有符合当前搜索或筛选的模块，请调整关键词、分组或状态。")
        // 空状态文案不回显搜索原文。
        XCTAssertFalse(filtered.emptyStateMessage?.contains("zzz") ?? false)

        // 角色无任何可见模块时给出安全空状态（用空输入集模拟）。
        let noModules = MobileModuleLaunchCenterDiscovery.apply(
            MobileModuleLaunchCenterDiscoveryFilter(),
            to: []
        )
        XCTAssertTrue(noModules.isEmpty)
        XCTAssertEqual(noModules.emptyStateMessage, "当前视角暂时没有可进入的模块。")
    }

    func testDiscoveryAvailableGroupsAndStatusesComeFromSnapshot() {
        let snapshot = builder.build(viewerRole: .guardian)
        let result = MobileModuleLaunchCenterDiscovery.apply(
            MobileModuleLaunchCenterDiscoveryFilter(),
            to: snapshot
        )
        XCTAssertEqual(Set(result.availableGroups), Set(snapshot.modules.map(\.group)))
        XCTAssertEqual(Set(result.availableStatuses), Set(snapshot.modules.map(\.status)))
        // 保持系统分组顺序。
        XCTAssertEqual(result.availableGroups, MobileModuleLaunchGroupKind.allCases.filter { kind in
            snapshot.modules.contains { $0.group == kind }
        })
    }

    func testDiscoveryHasNoSideEffectsOnModules() {
        let snapshot = builder.build(viewerRole: .guardian)
        let result = MobileModuleLaunchCenterDiscovery.apply(
            MobileModuleLaunchCenterDiscoveryFilter(searchText: "查看", sort: .recommended),
            to: snapshot
        )
        XCTAssertTrue(result.modules.allSatisfy { module in
            !module.callsNetwork && !module.callsAiProvider && !module.callsLms
                && !module.writesSchoolSystem && !module.writesLedger && !module.grantsCredit
                && !module.unlocksDevice && !module.sendsNotification
                && !module.writesEntitlement && !module.createsOrder
        })
    }

    // MARK: - 奖励商店库存履约路由（A97）

    func testRewardStoreFulfillmentVisibleToChildGuardianOperationsInCreditRewardGroup() {
        let child = builder.build(viewerRole: .child)
        let guardian = builder.build(viewerRole: .guardian)
        let operations = builder.build(viewerRole: .operations)

        XCTAssertTrue(child.modules.contains { $0.key == .rewardStoreFulfillment && $0.group == .creditReward })
        XCTAssertTrue(guardian.modules.contains { $0.key == .rewardStoreFulfillment && $0.group == .creditReward })
        XCTAssertTrue(operations.modules.contains { $0.key == .rewardStoreFulfillment && $0.group == .creditReward })
        // 运营仅能在成长积分奖励组看到奖励库存履约（安全预览），看不到其它成长积分奖励模块。
        XCTAssertFalse(operations.modules.contains { $0.key == .creditLedger })
        XCTAssertFalse(operations.modules.contains { $0.key == .rewardWindow })
    }

    func testRewardStoreFulfillmentHiddenFromRelativeAndTeacher() {
        let relative = builder.build(viewerRole: .relative)
        let teacher = builder.build(viewerRole: .teacher)

        XCTAssertFalse(relative.modules.contains { $0.key == .rewardStoreFulfillment })
        XCTAssertFalse(teacher.modules.contains { $0.key == .rewardStoreFulfillment })
        XCTAssertNil(routeResolver.route(for: .rewardStoreFulfillment, viewerRole: .relative))
        XCTAssertNil(routeResolver.route(for: .rewardStoreFulfillment, viewerRole: .teacher))
    }

    func testRewardStoreFulfillmentRouteDestinationsByRole() {
        let childRoute = routeResolver.route(for: .rewardStoreFulfillment, viewerRole: .child)
        let guardianRoute = routeResolver.route(for: .rewardStoreFulfillment, viewerRole: .guardian)
        let operationsRoute = routeResolver.route(for: .rewardStoreFulfillment, viewerRole: .operations)

        // 孩子/家长进入真实安全壳页，运营只看脱敏安全预览。
        XCTAssertEqual(childRoute?.destinationKind, .rewardStoreFulfillment)
        XCTAssertEqual(childRoute?.viewerRole, .child)
        XCTAssertEqual(childRoute?.opensExistingPage, true)
        XCTAssertEqual(guardianRoute?.destinationKind, .rewardStoreFulfillment)
        XCTAssertEqual(guardianRoute?.viewerRole, .guardian)
        XCTAssertEqual(guardianRoute?.opensExistingPage, true)
        XCTAssertEqual(operationsRoute?.destinationKind, .safePreview)
        XCTAssertEqual(operationsRoute?.opensExistingPage, false)
        XCTAssertEqual(childRoute?.allowedRoles, [.child, .guardian, .operations])

        // 安全壳页自身按 allowedRoles 锁定角色，模块中心不强加额外角色锁。
        XCTAssertFalse(childRoute?.shouldLockDestinationRole ?? true)
        XCTAssertFalse(guardianRoute?.shouldLockDestinationRole ?? true)

        // 孩子拿到的路由锁在 child 视角，无法切到家长复核页。
        XCTAssertNotEqual(childRoute?.viewerRole, .guardian)
    }

    func testRewardStoreFulfillmentRawValuesAndRedaction() {
        XCTAssertEqual(MobileModuleLaunchModuleKey.rewardStoreFulfillment.rawValue, "reward_store_fulfillment")
        XCTAssertEqual(MobileModuleLaunchRouteDestinationKind.rewardStoreFulfillment.rawValue, "reward_store_fulfillment")

        for role in MobileModuleLaunchCenterViewerRole.allCases {
            guard let route = routeResolver.route(for: .rewardStoreFulfillment, viewerRole: role) else { continue }
            XCTAssertTrue(routeResolver.redacts([route]), role.label)
            XCTAssertFalse(route.hasTriggeredSideEffect, role.label)
            // route rawValue 与展示文本脱敏：不泄露 order/inventory/redemption/address/ledger 等。
            let joined = route.displayValues.joined(separator: " ").lowercased()
            for marker in ["order:", "inventory:", "redemption:", "address:", "ledger:", "device:", "gift:", "http://", "192.168.", "/users/", "token", "publicref"] {
                XCTAssertFalse(joined.contains(marker), "\(role.label) 泄露 \(marker)")
            }
        }
    }

    func testRewardStoreFulfillmentCardHasNoSideEffects() {
        for role in [MobileModuleLaunchCenterViewerRole.child, .guardian, .operations] {
            let snapshot = builder.build(viewerRole: role)
            guard let card = snapshot.modules.first(where: { $0.key == .rewardStoreFulfillment }) else {
                XCTFail("\(role.label) 缺少奖励库存履约模块")
                continue
            }
            XCTAssertFalse(card.actionRequired, role.label)
            XCTAssertFalse(
                card.callsNetwork || card.callsAiProvider || card.callsLms || card.writesSchoolSystem
                    || card.writesLedger || card.grantsCredit || card.unlocksDevice || card.sendsNotification
                    || card.writesEntitlement || card.createsOrder,
                role.label
            )
        }
    }

    /// 既有 rewardWindow -> rewardRedemption/rewardStatus 路由不回归。
    func testRewardWindowRoutesStillResolveAlongsideFulfillment() {
        let childWindow = routeResolver.route(for: .rewardWindow, viewerRole: .child)
        let guardianWindow = routeResolver.route(for: .rewardWindow, viewerRole: .guardian)

        XCTAssertEqual(childWindow?.destinationKind, .rewardRedemption)
        XCTAssertEqual(guardianWindow?.destinationKind, .rewardStatus)
        XCTAssertFalse(childWindow?.hasTriggeredSideEffect ?? true)
        XCTAssertFalse(guardianWindow?.hasTriggeredSideEffect ?? true)

        // rewardWindow 与 rewardStoreFulfillment 是两个独立模块，互不夺路由。
        let guardianRoutes = routeResolver.routes(for: builder.build(viewerRole: .guardian))
        XCTAssertTrue(guardianRoutes.contains { $0.moduleKey == .rewardWindow && $0.destinationKind == .rewardStatus })
        XCTAssertTrue(guardianRoutes.contains { $0.moduleKey == .rewardStoreFulfillment && $0.destinationKind == .rewardStoreFulfillment })
    }

    @MainActor
    private func destinationProbe(
        for route: MobileModuleLaunchRoute,
        familyAchievementStore: FamilyGrowthAchievementStore
    ) -> AnyView {
        switch route.destinationKind {
        case .childTaskList:
            return AnyView(ChildHomeView())
        case .basicHabitCheckin:
            let role = basicHabitRole(for: route.viewerRole)
            return AnyView(BasicHabitChoreCheckinWorkbenchView(initialRole: role, allowedRoles: [role]))
        case .guardianTaskReview:
            return AnyView(ParentModeView())
        case .growthPackDetail:
            let role = growthPackDetailRole(for: route.viewerRole)
            return AnyView(GrowthPackMobileDetailView(initialRole: role, allowedRoles: [role]))
        case .growthPackExecutionHub:
            let role = growthPackExecutionHubRole(for: route.viewerRole)
            return AnyView(MobileGrowthPackExecutionHubView(initialRole: role, allowedRoles: [role]))
        case .growthPackEntitlement:
            return AnyView(
                GrowthPackInstallEntitlementView(
                    initialRole: growthPackInstallRole(for: route.viewerRole),
                    allowsRoleSwitching: !route.shouldLockDestinationRole
                )
            )
        case .schoolHomework:
            let role = schoolHomeworkLinkageRole(for: route.viewerRole)
            return AnyView(MobileSchoolHomeworkGrowthPackLinkageWorkbenchView(initialRole: role, allowedRoles: [role]))
        case .aiHomeworkInbox:
            let role = aiInboxRole(for: route.viewerRole)
            return AnyView(AIHomeworkFamilySchoolInboxView(initialRole: role, allowedRoles: [role]))
        case .schoolJointApproval:
            let role = schoolJointApprovalRole(for: route.viewerRole)
            return AnyView(SchoolJointApprovalBoardView(initialRole: role, allowedRoles: [role]))
        case .notificationDigestConsent:
            let role = notificationDigestRole(for: route.viewerRole)
            return AnyView(FamilySchoolNotificationDigestCenterView(initialRole: role, allowedRoles: [role]))
        case .familyStorylineConsent:
            return AnyView(
                FamilyHonorStorylineConsentView(
                    store: familyAchievementStore,
                    initialRole: familyHonorRole(for: route.viewerRole),
                    allowsRoleSwitching: !route.shouldLockDestinationRole
                )
            )
        case .growthDiaryVlogStoryline:
            let role = growthDiaryVlogRole(for: route.viewerRole)
            return AnyView(
                GrowthDiaryVlogStorylineWorkbenchView(
                    store: familyAchievementStore,
                    initialRole: role,
                    allowedRoles: [role]
                )
            )
        case .familyAchievementDashboard:
            return AnyView(
                FamilyAchievementSnapshotDashboardView(
                    store: familyAchievementStore,
                    initialRole: familyGrowthRole(for: route.viewerRole),
                    allowsRoleSwitching: !route.shouldLockDestinationRole
                )
            )
        case .creditLedgerReview:
            return AnyView(CreditLedgerReviewView(viewerRole: creditLedgerRole(for: route.viewerRole)))
        case .rewardRedemption:
            return AnyView(ChildCreditWalletView())
        case .rewardStatus:
            return AnyView(RewardStatusView())
        case .appSelectionWorkbench:
            let role = appSelectionRole(for: route.viewerRole)
            return AnyView(AppSelectionWorkbenchView(initialRole: role, allowedRoles: [role]))
        case .rewardStoreFulfillment:
            let role = rewardStoreFulfillmentRole(for: route.viewerRole)
            return AnyView(MobileRewardStoreInventoryFulfillmentWorkbenchView(initialRole: role, allowedRoles: [role]))
        case .reportsWorkbench:
            let role = reportsRole(for: route.viewerRole)
            return AnyView(ReportsWorkbenchView(initialRole: role, allowedRoles: [role]))
        case .onboardingGuide:
            let role = onboardingRole(for: route.viewerRole)
            return AnyView(OnboardingWorkbenchView(initialRole: role, allowedRoles: [role]))
        case .offlineSyncReview:
            return AnyView(MobileOfflineSyncReviewView(perspective: offlineSyncReviewPerspective(for: route.viewerRole)))
        case .moduleConfigurationDraft:
            return AnyView(MobileModuleConfigurationDraftView())
        case .releaseGate:
            return AnyView(
                MobileReleaseCandidateGateView(
                    initialRole: releaseGateRole(for: route.viewerRole),
                    allowsRoleSwitching: !route.shouldLockDestinationRole
                )
            )
        case .familySocialFeedbackEmotionalSafetyCenter:
            let role = emotionalSafetyRole(for: route.viewerRole)
            return AnyView(MobileFamilySocialFeedbackEmotionalSafetyCenterView(initialRole: role, allowedRoles: [role]))
        case .safePreview:
            return AnyView(MobileModuleLaunchCenterView(initialRole: route.viewerRole, allowedRoles: [route.viewerRole]))
        }
    }

    private func growthPackInstallRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> GrowthPackInstallViewerRole {
        switch role {
        case .child: return .child
        case .guardian: return .guardian
        case .relative: return .relative
        case .teacher: return .guardian
        case .operations: return .creator
        }
    }

    private func basicHabitRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> MobileBasicHabitChoreViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .relative, .teacher, .operations: return .guardian
        }
    }

    private func growthPackDetailRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> GrowthPackMobileDetailViewerRole {
        switch role {
        case .child, .operations:
            return .child
        case .guardian:
            return .guardian
        case .relative:
            return .relative
        case .teacher:
            return .teacher
        }
    }

    private func growthPackExecutionHubRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> MobileGrowthPackExecutionHubRole {
        switch role {
        case .child: return .child
        case .guardian, .relative, .teacher, .operations: return .guardian
        }
    }

    private func aiInboxRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> AIHomeworkFamilySchoolInboxViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .relative: return .guardian
        case .teacher: return .teacher
        case .operations: return .operations
        }
    }

    private func schoolJointApprovalRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> SchoolJointApprovalViewerRole {
        switch role {
        case .child, .relative, .operations: return .child
        case .guardian: return .guardian
        case .teacher: return .teacher
        }
    }

    private func schoolHomeworkLinkageRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> MobileSchoolHomeworkGrowthPackLinkageViewerRole {
        switch role {
        case .child, .relative, .operations: return .child
        case .guardian: return .guardian
        case .teacher: return .teacher
        }
    }

    private func notificationDigestRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> MobileFamilySchoolNotificationDigestViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .operations: return .guardian
        case .teacher: return .teacher
        case .relative: return .relative
        }
    }

    private func familyHonorRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> FamilyHonorStorylineConsentViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .teacher, .operations: return .guardian
        case .relative: return .relative
        }
    }

    private func growthDiaryVlogRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> MobileGrowthDiaryVlogViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .teacher, .operations: return .guardian
        case .relative: return .relative
        }
    }

    private func familyGrowthRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> FamilyGrowthViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .teacher, .operations: return .guardian
        case .relative: return .relative
        }
    }

    private func creditLedgerRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> CreditLedgerReviewViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .operations: return .guardian
        case .relative: return .relative
        case .teacher: return .teacher
        }
    }

    private func rewardStoreFulfillmentRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> MobileRewardStoreFulfillmentRole {
        switch role {
        case .child: return .child
        case .guardian, .relative, .teacher, .operations: return .guardian
        }
    }

    private func appSelectionRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> AppSelectionViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .relative, .teacher, .operations: return .guardian
        }
    }

    private func reportsRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> ReportsViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .relative, .teacher, .operations: return .guardian
        }
    }

    private func onboardingRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> OnboardingViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .relative, .teacher, .operations: return .guardian
        }
    }

    private func offlineSyncReviewPerspective(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> MobileHomePerspective {
        switch role {
        case .child: return .child
        case .guardian, .relative, .teacher, .operations: return .parent
        }
    }

    private func emotionalSafetyRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> MobileFamilySocialFeedbackEmotionalSafetyCenterRole {
        switch role {
        case .child: return .child
        case .guardian: return .guardian
        case .relative: return .relative
        case .operations, .teacher: return .expert
        }
    }

    private func releaseGateRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> MobileReleaseCandidateGateViewerRole {
        switch role {
        case .guardian: return .guardian
        case .operations: return .operations
        case .child, .relative, .teacher: return .child
        }
    }

    private func card(
        key: MobileModuleLaunchModuleKey,
        group: MobileModuleLaunchGroupKind,
        status: MobileModuleLaunchCenterStatus,
        progress: Int,
        actionRequired: Bool
    ) -> MobileModuleLaunchModuleCard {
        MobileModuleLaunchModuleCard(
            publicModuleRef: "mlc-test-\(key.rawValue)",
            key: key,
            group: group,
            title: key.title,
            detail: "本地测试模块说明",
            status: status,
            progress: progress,
            actionRequired: actionRequired,
            routeHint: "查看\(key.title)",
            visibleToChild: true,
            visibleToGuardian: true,
            visibleToRelative: true,
            visibleToTeacher: true,
            visibleToOperations: true
        )
    }

    private func displayedText(_ snapshot: MobileModuleLaunchCenterSnapshot) -> String {
        snapshot.displayValues.joined(separator: " ")
    }
}
