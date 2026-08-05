import XCTest

@MainActor
final class OctoTeacherModuleClickPathUITests: XCTestCase {
    private var app: XCUIApplication!
    private var currentRole = "孩子"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testChildVisibleModulesCanOpenFromModuleCenter() {
        assertVisibleModulesCanOpen(
            role: "孩子",
            modules: [
                "今日基础任务",
                "成长包运行",
                "成长包执行中心",
                "成长包安装权益",
                "学校作业",
                "AI 引导学习",
                "家校联合审批",
                "通知摘要同意",
                "成长故事线",
                "荣誉墙与球星卡",
                "成长积分账本",
                "成长积分兑换窗口",
                "娱乐 App 策略预览",
                "奖励库存履约",
                "成长报告预览",
                "章鱼老师 入门",
                "离线同步复核台",
                "情绪安全中心"
            ]
        )
    }

    func testGuardianVisibleModulesCanOpenFromModuleCenter() {
        assertVisibleModulesCanOpen(
            role: "家长",
            modules: [
                "今日基础任务",
                "成长包运行",
                "成长包执行中心",
                "成长包安装权益",
                "学校作业",
                "AI 引导学习",
                "家校联合审批",
                "通知摘要同意",
                "成长故事线",
                "荣誉墙与球星卡",
                "成长积分账本",
                "成长积分兑换窗口",
                "娱乐 App 策略预览",
                "奖励库存履约",
                "成长报告预览",
                "章鱼老师 入门",
                "离线同步复核台",
                "家长模块配置草稿",
                "移动端发布质量门",
                "情绪安全中心"
            ]
        )
    }

    func testRelativeVisibleModulesCanOpenFromModuleCenter() {
        assertVisibleModulesCanOpen(
            role: "亲友",
            modules: [
                "通知摘要同意",
                "成长故事线",
                "荣誉墙与球星卡",
                "情绪安全中心"
            ]
        )
    }

    func testTeacherVisibleModulesCanOpenFromModuleCenter() {
        assertVisibleModulesCanOpen(
            role: "老师",
            modules: [
                "学校作业",
                "AI 引导学习",
                "家校联合审批",
                "通知摘要同意"
            ]
        )
    }

    func testOperationsVisibleModulesCanOpenFromModuleCenter() {
        assertVisibleModulesCanOpen(
            role: "运营",
            modules: [
                "成长包运行",
                "成长包执行中心",
                "成长包安装权益",
                "学校作业",
                "AI 引导学习",
                "家校联合审批",
                "通知摘要同意",
                "成长故事线",
                "荣誉墙与球星卡",
                "娱乐 App 策略预览",
                "奖励库存履约",
                "章鱼老师 入门",
                "离线同步复核台",
                "家长模块配置草稿",
                "移动端发布质量门",
                "情绪安全中心"
            ]
        )
    }

    func testPrimaryTaskApprovalCreditRewardPathCanBeClicked() {
        launchModuleAudit(role: "孩子")
        selectRole("孩子")
        openModule(named: "今日基础任务")
        tapIfExists("开始第一个可打卡任务")

        let proofField = app.descendants(matching: .any)["task-detail-proof-text"].firstMatch
        XCTAssertTrue(scrollToElement(identifier: "task-detail-proof-text", attempts: 8))
        XCTAssertTrue(
            app.descendants(matching: .any)["task-detail-submit-disabled-reason"].waitForExistence(timeout: 3),
            "Task detail should explain why submit is disabled before proof is ready"
        )
        proofField.tap()
        proofField.typeText("完成今日阅读")
        XCTAssertTrue(app.descendants(matching: .any)["task-detail-submit-ready"].waitForExistence(timeout: 3))
        app.buttons["task-detail-submit-for-approval"].tap()
        let submittedStatus = app.descendants(matching: .any)["task-detail-submitted-status"]
        XCTAssertTrue(
            submittedStatus.waitForExistence(timeout: 3),
            "Child should see a clear submitted state after handing in proof"
        )
        XCTAssertTrue(
            submittedStatus.label.contains("成长积分"),
            "Submitted state should explain that growth points are pending adult confirmation"
        )
        XCTAssertTrue(
            scrollToElement(identifier: "task-detail-offline-hint", attempts: 8),
            "Submission should also show the local outbox note, whether queued or deduplicated"
        )

        navigateBackToModuleCenter()
        openTab(named: "家长")

        let pinField = app.secureTextFields["输入家长 PIN"].firstMatch
        XCTAssertTrue(pinField.waitForExistence(timeout: 3))
        pinField.tap()
        pinField.typeText("1234")
        app.buttons["parent-mode-unlock"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["parent-mode-today-summary-message"].waitForExistence(timeout: 3),
            "Parent mode should explain the next action before showing deep modules"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["parent-mode-today-pending"].waitForExistence(timeout: 3),
            "Parent mode should summarize pending approvals at the top"
        )
        XCTAssertTrue(tapScrollableButton(identifier: "parent-mode-advanced-tools", attempts: 12), "Missing parent advanced tools entry")
        XCTAssertTrue(tapScrollableButton(identifier: "parent-mode-quick-access-creditLedgerReview", attempts: 12), "Missing parent growth point ledger quick access")
        XCTAssertTrue(app.navigationBars["成长积分账本复核台"].waitForExistence(timeout: 3), "Missing parent growth point ledger quick access destination")
        navigateBackToTitle("更多功能与预览")
        navigateBackToTitle("家长工作台")
        XCTAssertTrue(tapScrollableButton(prefix: "parent-mode-approve-"), "Missing pending approval action")

        openTab(named: "模块")
        openModule(named: "成长积分账本")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "成长积分")).firstMatch.waitForExistence(timeout: 3))
        navigateBackToModuleCenter()

        openModule(named: "成长积分兑换窗口")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "可用", "成长积分")).firstMatch.waitForExistence(timeout: 3))
        navigateBackToModuleCenter()
    }

    func testParentModeRejectReasonCanQueueOfflineDraft() {
        launchModuleAudit(role: "孩子")
        selectRole("孩子")
        openModule(named: "今日基础任务")
        tapIfExists("开始第一个可打卡任务")

        let proofField = app.descendants(matching: .any)["task-detail-proof-text"].firstMatch
        XCTAssertTrue(scrollToElement(identifier: "task-detail-proof-text", attempts: 8))
        proofField.tap()
        proofField.typeText("还需要修改的证明")
        app.buttons["task-detail-submit-for-approval"].tap()
        XCTAssertTrue(scrollToElement(identifier: "task-detail-submitted-status", attempts: 8))

        navigateBackToModuleCenter()
        openTab(named: "家长")

        let pinField = app.secureTextFields["输入家长 PIN"].firstMatch
        XCTAssertTrue(pinField.waitForExistence(timeout: 3))
        pinField.tap()
        pinField.typeText("1234")
        app.buttons["parent-mode-unlock"].tap()

        XCTAssertTrue(
            tapScrollableButton(identifier: "parent-mode-return-menu", attempts: 8),
            "Missing return-for-more-proof menu"
        )
        _ = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "parent-mode-reject-")).firstMatch.waitForExistence(timeout: 1)
        let reasonButton = app.buttons["证明看不清楚"].firstMatch
        XCTAssertTrue(reasonButton.waitForExistence(timeout: 3), "Missing reject reason")
        reasonButton.tap()
        XCTAssertTrue(scrollToElement(identifier: "parent-mode-offline-hint", attempts: 6), "Missing reject offline feedback")
    }

    func testParentCreatorManifestRubricLinkCanRoundTrip() {
        launchDefaultApp(initialTab: "parent", expectedTitle: "家长工作台")

        let pinField = app.secureTextFields["输入家长 PIN"].firstMatch
        XCTAssertTrue(pinField.waitForExistence(timeout: 3), "Missing parent PIN field")
        pinField.tap()
        pinField.typeText("1234")
        app.buttons["parent-mode-unlock"].tap()

        XCTAssertTrue(tapScrollableButton(identifier: "parent-mode-advanced-tools", attempts: 12), "Missing parent advanced tools entry")
        XCTAssertTrue(
            tapScrollableButton(identifier: "parent-mode-planning-tools-toggle", attempts: 8),
            "Missing planning and publishing checks group"
        )
        XCTAssertTrue(tapScrollableButton(identifier: "parent-mode-quick-access-creatorManifestPreview", attempts: 12), "Missing creator manifest quick access")
        XCTAssertTrue(app.navigationBars["Manifest 预览"].waitForExistence(timeout: 3), "Missing creator manifest page")
        XCTAssertTrue(tapScrollableButton(identifier: "creator-manifest-rubric-age-link", attempts: 12), "Missing creator manifest rubric link")
        XCTAssertTrue(app.navigationBars["量规适龄"].waitForExistence(timeout: 3), "Missing creator manifest rubric destination")
    }

    func testRepresentativeNestedActionsHaveVisibleFeedback() {
        launchModuleAudit(role: "孩子")
        selectRole("孩子")
        openModule(named: "成长积分兑换窗口")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "成长积分", "今日任务")).firstMatch.waitForExistence(timeout: 3))
        navigateBackToModuleCenter()

        openModule(named: "奖励库存履约")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "库存", "奖励")).firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 3))
        navigateBackToModuleCenter()

        openModule(named: "章鱼老师 入门")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ OR label CONTAINS %@",
            "Octo Teacher",
            "章鱼老师"
        )).firstMatch.waitForExistence(timeout: 3))
        navigateBackToModuleCenter()

        openModule(named: "离线同步复核台")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "同步", "离线")).firstMatch.waitForExistence(timeout: 3))
        navigateBackToModuleCenter()
    }

    func testModuleCenterDiscoveryFiltersCanNarrowAndClear() {
        launchModuleAudit(role: "孩子")

        XCTAssertTrue(tapScrollableButton(identifier: "module-center-filter-group-menu"), "Missing module group filter menu")
        XCTAssertTrue(tapScrollableButton(identifier: "module-center-filter-group-school_learning"), "Missing school-learning group filter")
        XCTAssertTrue(scrollToElement(identifier: "module-center-module-school_homework"), "Filtered module list missing school homework")
        XCTAssertFalse(app.buttons["module-center-module-reward_window"].exists, "Group filter did not narrow unrelated reward module")

        XCTAssertTrue(tapScrollableButton(identifier: "module-center-filter-status-menu"), "Missing module status filter menu")
        XCTAssertTrue(tapScrollableButton(identifier: "module-center-filter-status-active"), "Missing active status filter")
        XCTAssertTrue(tapScrollableButton(identifier: "module-center-filter-status-menu"), "Missing module status filter menu after active filter")
        XCTAssertTrue(tapScrollableButton(identifier: "module-center-filter-status-all"), "Missing all-status filter")
        XCTAssertTrue(tapScrollableButton(identifier: "module-center-filter-group-menu"), "Missing module group filter menu after status reset")
        XCTAssertTrue(tapScrollableButton(identifier: "module-center-filter-group-all"), "Missing all-group filter")
        XCTAssertTrue(tapScrollableButton(identifier: "module-center-filter-group-menu"), "Missing module group filter menu after all-group reset")
        XCTAssertTrue(tapScrollableButton(identifier: "module-center-filter-group-school_learning"), "Missing school-learning group filter after reset")
        XCTAssertTrue(scrollToElement(identifier: "module-center-filter-clear"), "Missing clear filter button")
        XCTAssertTrue(tapScrollableButton(identifier: "module-center-filter-clear"), "Could not clear module filters")
        XCTAssertTrue(scrollToElement(identifier: "module-center-module-reward_window"), "Clearing filters did not restore reward module")
    }

    func testMobileHomePrimaryLinksAndFirstActionCanOpen() {
        launchDefaultApp()

        XCTAssertTrue(tapScrollableButton(identifier: "mobile-home-module-center-link"), "Missing home module center link")
        XCTAssertTrue(app.navigationBars["模块能力中心"].waitForExistence(timeout: 3), "Missing module center from home")
        navigateBackToTitle("章鱼老师")

        XCTAssertTrue(tapScrollableButton(identifier: "mobile-home-platform-dashboard-link"), "Missing home platform dashboard link")
        XCTAssertTrue(app.navigationBars["平台总览"].waitForExistence(timeout: 3), "Missing platform dashboard from home")
        XCTAssertTrue(tapScrollableButton(identifier: "mobile-platform-release-gate-link"), "Missing platform release gate link")
        XCTAssertTrue(app.navigationBars["发布质量门"].waitForExistence(timeout: 3), "Missing platform release gate destination")
        navigateBackToTitle("平台总览")
        navigateBackToTitle("章鱼老师")

        XCTAssertTrue(tapScrollableButton(prefix: "mobile-home-item-", attempts: 10), "Missing home action link")
        XCTAssertFalse(app.navigationBars["章鱼老师"].waitForExistence(timeout: 1), "Home action did not navigate away")
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 3), "Missing home action destination")
        navigateBackToTitle("章鱼老师")
    }

    func testOnboardingGuideRoleScopedChecklistAndBoundariesCanOpen() {
        launchModuleAudit(role: "孩子")
        openModule(named: "章鱼老师 入门")
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 3), "Missing child onboarding")
        XCTAssertTrue(scrollToElement(identifier: "onboarding-title"), "Child missing OctoTeacher title")
        XCTAssertTrue(scrollToElement(identifier: "onboarding-subtitle"), "Child missing onboarding subtitle")
        XCTAssertTrue(scrollToElement(identifier: "onboarding-role-child"), "Child onboarding did not lock child role")
        XCTAssertTrue(scrollToElement(identifier: "onboarding-ready-summary"), "Child missing ready summary")
        XCTAssertTrue(scrollToElement(identifier: "onboarding-step-role"), "Child missing role step")
        XCTAssertTrue(scrollToElement(identifier: "onboarding-step-tasks"), "Child missing tasks step")
        XCTAssertTrue(scrollToElement(identifier: "onboarding-step-school"), "Child missing school step")
        XCTAssertTrue(scrollToElement(identifier: "onboarding-step-credit"), "Child missing credit step")
        XCTAssertTrue(scrollToElement(identifier: "onboarding-boundary-local-only", attempts: 12), "Child missing local-only boundary")
        XCTAssertTrue(scrollToElement(identifier: "onboarding-boundary-no-credit", attempts: 12), "Child missing no-credit boundary")
        XCTAssertTrue(scrollToElement(identifier: "onboarding-boundary-ledger-device", attempts: 12), "Child missing ledger/device execution boundary")
        XCTAssertFalse(app.descendants(matching: .any)["onboarding-step-reports"].exists, "Child leaked adult reports step")
        XCTAssertFalse(app.descendants(matching: .any)["onboarding-step-privacy"].exists, "Child leaked adult privacy step")
        XCTAssertFalse(app.descendants(matching: .any)["onboarding-boundary-no-permission"].exists, "Child leaked adult permission boundary")
        navigateBackToModuleCenter()

        launchModuleAudit(role: "家长")
        openModule(named: "章鱼老师 入门")
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 3), "Missing guardian onboarding")
        XCTAssertTrue(scrollToElement(identifier: "onboarding-title"), "Guardian missing OctoTeacher title")
        XCTAssertTrue(scrollToElement(identifier: "onboarding-subtitle"), "Guardian missing onboarding subtitle")
        XCTAssertTrue(scrollToElement(identifier: "onboarding-role-guardian"), "Guardian onboarding did not lock guardian role")
        XCTAssertTrue(scrollToElement(identifier: "onboarding-ready-summary"), "Guardian missing ready summary")
        XCTAssertTrue(scrollToElement(identifier: "onboarding-step-reports", attempts: 10), "Guardian missing reports step")
        XCTAssertTrue(scrollToElement(identifier: "onboarding-step-privacy", attempts: 10), "Guardian missing privacy step")
        XCTAssertTrue(scrollToElement(identifier: "onboarding-boundary-no-permission", attempts: 12), "Guardian missing permission boundary")
        XCTAssertTrue(scrollToElement(identifier: "onboarding-boundary-role-crop", attempts: 12), "Guardian missing role crop boundary")
        XCTAssertTrue(scrollToElement(identifier: "onboarding-boundary-login-family", attempts: 12), "Guardian missing login/family execution boundary")
        XCTAssertTrue(scrollToElement(identifier: "onboarding-boundary-network-notification", attempts: 12), "Guardian missing network/notification execution boundary")
        navigateBackToModuleCenter()
    }

    func testCreditLedgerWalletAndGuardianReviewRoleScopedSectionsCanOpen() {
        launchModuleAudit(role: "孩子")
        openModule(named: "成长积分兑换窗口")
        XCTAssertTrue(app.navigationBars["我的奖励"].waitForExistence(timeout: 3), "Missing child reward wallet")
        XCTAssertTrue(scrollToElement(identifier: "child-credit-wallet-balance"), "Child missing wallet balance")
        XCTAssertTrue(scrollToElement(identifier: "child-credit-wallet-metric-today-package"), "Child missing today package metric")
        XCTAssertTrue(scrollToElement(identifier: "child-credit-wallet-session-locked"), "Child missing locked session state")
        XCTAssertTrue(scrollToElement(identifier: "child-credit-wallet-session-receipt"), "Child missing latest receipt summary")
        XCTAssertTrue(scrollToElement(identifier: "child-credit-wallet-action-earn_today"), "Child missing earn-today action")
        XCTAssertTrue(scrollToElement(identifier: "child-credit-wallet-finding-CHILD_CREDIT_WALLET_NO_AVAILABLE_CREDIT", attempts: 12), "Child missing no-available-credit finding")
        XCTAssertFalse(app.descendants(matching: .any)["credit-ledger-review-balance-available"].exists, "Child leaked guardian ledger balance")
        navigateBackToModuleCenter()

        launchModuleAudit(role: "家长")
        openModule(named: "成长积分账本")
        XCTAssertTrue(app.navigationBars["成长积分账本复核台"].waitForExistence(timeout: 3), "Missing guardian growth point ledger review")
        XCTAssertTrue(tapScrollableButton(identifier: "credit-ledger-review-refresh"), "Guardian missing refresh action")
        XCTAssertTrue(scrollToElement(identifier: "credit-ledger-review-status"), "Guardian missing review status")
        XCTAssertTrue(scrollToElement(identifier: "credit-ledger-review-balance-available"), "Guardian missing available balance")
        XCTAssertTrue(scrollToElement(identifier: "credit-ledger-review-balance-frozen"), "Guardian missing frozen balance")
        XCTAssertTrue(scrollToElement(identifier: "credit-ledger-review-row-proposable", attempts: 12), "Guardian missing proposable review row")
        XCTAssertTrue(scrollToElement(identifier: "credit-ledger-review-row-frozen", attempts: 12), "Guardian missing frozen review row")
        XCTAssertTrue(scrollToElement(identifier: "credit-ledger-review-row-blockedOrIgnored", attempts: 12), "Guardian missing blocked review row")
        XCTAssertTrue(scrollToElement(identifier: "credit-ledger-review-finding-BLOCKED_PRESENT", attempts: 12), "Guardian missing blocked-present finding")
        XCTAssertFalse(app.descendants(matching: .any)["child-credit-wallet-action-earn_today"].exists, "Guardian leaked child wallet action")
        navigateBackToModuleCenter()
    }

    func testGrowthPackRuntimeRoleScopedDetailAndOperationsPreviewCanOpen() {
        launchModuleAudit(role: "孩子")
        openModule(named: "成长包运行")
        XCTAssertTrue(app.navigationBars["成长包详情"].waitForExistence(timeout: 3), "Missing child growth pack detail")
        XCTAssertTrue(scrollToElement(identifier: "growth-pack-detail-role-child"), "Child route did not lock child detail role")
        XCTAssertTrue(scrollToElement(identifier: "growth-pack-detail-status"), "Child missing growth pack status")
        XCTAssertTrue(scrollToElement(identifier: "growth-pack-detail-summary-steps"), "Child missing step summary")
        XCTAssertTrue(scrollToElement(identifier: "growth-pack-detail-content-player-child"), "Child missing content player link")
        XCTAssertTrue(tapScrollableButton(identifier: "growth-pack-detail-content-player-child"), "Child could not open content player")
        XCTAssertTrue(app.navigationBars["内容播放器"].waitForExistence(timeout: 3), "Missing child content player destination")
        let contentLinks: [(identifier: String, title: String)] = [
            ("content-player-item-quizPractice", "测验自检"),
            ("content-player-item-externalVideoReference", "外部资源")
        ]
        for link in contentLinks {
            XCTAssertTrue(tapScrollableButton(identifier: link.identifier, attempts: 12), "Missing content player link \(link.identifier)")
            XCTAssertTrue(app.navigationBars[link.title].waitForExistence(timeout: 3), "Missing content player destination \(link.title)")
            navigateBackToTitle("内容播放器")
        }
        navigateBackToTitle("成长包详情")
        XCTAssertTrue(scrollToElement(identifier: "growth-pack-detail-step-0", attempts: 10), "Child missing first growth pack step")
        XCTAssertTrue(scrollToElement(identifier: "growth-pack-detail-reward-credit-preview-count", attempts: 12), "Child missing reward preview count")
        XCTAssertFalse(app.descendants(matching: .any)["growth-pack-detail-role-guardian"].exists, "Child route leaked guardian role")
        navigateBackToModuleCenter()

        launchModuleAudit(role: "家长")
        openModule(named: "成长包运行")
        XCTAssertTrue(app.navigationBars["成长包详情"].waitForExistence(timeout: 3), "Missing guardian growth pack detail")
        XCTAssertTrue(scrollToElement(identifier: "growth-pack-detail-role-guardian"), "Guardian route did not lock guardian detail role")
        XCTAssertTrue(scrollToElement(identifier: "growth-pack-detail-summary-credit"), "Guardian missing credit summary")
        XCTAssertTrue(scrollToElement(identifier: "growth-pack-detail-content-player-guardian"), "Guardian missing content player link")
        XCTAssertTrue(tapScrollableButton(identifier: "growth-pack-detail-content-player-guardian"), "Guardian could not open content player")
        XCTAssertTrue(app.navigationBars["内容播放器"].waitForExistence(timeout: 3), "Missing guardian content player destination")
        let guardianContentLinks: [(identifier: String, title: String)] = [
            ("content-player-item-schoolHook", "作业联动"),
            ("content-player-item-uploadPlaceholder", "创作展示")
        ]
        for link in guardianContentLinks {
            XCTAssertTrue(tapScrollableButton(identifier: link.identifier, attempts: 12), "Missing guardian content player link \(link.identifier)")
            XCTAssertTrue(app.navigationBars[link.title].waitForExistence(timeout: 3), "Missing guardian content player destination \(link.title)")
            navigateBackToTitle("内容播放器")
        }
        navigateBackToTitle("成长包详情")
        XCTAssertTrue(scrollToElement(identifier: "growth-pack-detail-proof-0", attempts: 12), "Guardian missing proof requirement")
        XCTAssertTrue(scrollToElement(identifier: "growth-pack-detail-reward-available-credit", attempts: 12), "Guardian missing available credit preview")
        XCTAssertTrue(scrollToElement(identifier: "growth-pack-detail-evidence-appeal-conflict", attempts: 14), "Guardian missing evidence appeal summary")
        XCTAssertTrue(scrollToElement(identifier: "growth-pack-detail-finding-ROLE_VISIBILITY_APPLIED", attempts: 14), "Guardian missing role visibility finding")
        XCTAssertFalse(app.descendants(matching: .any)["growth-pack-detail-role-child"].exists, "Guardian route leaked child role")
        navigateBackToModuleCenter()

        launchModuleAudit(role: "运营")
        openModule(named: "成长包运行")
        XCTAssertTrue(app.navigationBars["模块安全预览"].waitForExistence(timeout: 3), "Operations should open safe preview")
        XCTAssertTrue(scrollToElement(identifier: "module-route-preview-title"), "Operations missing preview title")
        XCTAssertTrue(scrollToElement(identifier: "module-route-preview-role-operations"), "Operations preview did not lock operations role")
        XCTAssertTrue(scrollToElement(identifier: "module-route-preview-guardrail"), "Operations preview missing guardrail")
        XCTAssertTrue(scrollToElement(identifier: "module-route-preview-effect-ledger-credit", attempts: 10), "Operations preview missing ledger/credit boundary")
        XCTAssertFalse(app.descendants(matching: .any)["growth-pack-detail-role-child"].exists, "Operations leaked internal growth pack detail")
        navigateBackToModuleCenter()
    }

    func testGuardianModuleConfigurationDraftReviewAndTrialLinkCanRoundTrip() {
        launchModuleAudit(role: "家长")
        openModule(named: "家长模块配置草稿")
        XCTAssertTrue(app.navigationBars["模块配置草稿"].waitForExistence(timeout: 3), "Missing module configuration draft")
        XCTAssertTrue(scrollToElement(identifier: "module-configuration-draft-role-guardian"), "Guardian draft did not lock guardian role")
        XCTAssertTrue(scrollToElement(identifier: "module-configuration-draft-status"), "Guardian missing draft status")
        XCTAssertTrue(scrollToElement(identifier: "module-configuration-draft-credit-preview"), "Guardian missing credit preview")
        XCTAssertTrue(scrollToElement(identifier: "module-configuration-draft-review-action-count"), "Guardian missing review count")
        XCTAssertTrue(tapScrollableButton(identifier: "module-configuration-draft-link-preinstall-trial"), "Guardian missing preinstall trial link")
        XCTAssertTrue(app.navigationBars["安装前试运行"].waitForExistence(timeout: 3), "Missing preinstall trial destination")
        XCTAssertTrue(scrollToElement(identifier: "preinstall-trial-metric-guardian-review"), "Trial destination missing guardian review metric")
        navigateBackToTitle("模块配置草稿")

        XCTAssertTrue(scrollToElement(identifier: "module-configuration-draft-item-school_homework-after_school", attempts: 12), "Guardian missing school homework draft item")
        XCTAssertTrue(scrollToElement(identifier: "module-configuration-draft-review-action-school_homework", attempts: 12), "Guardian missing school review action")
        XCTAssertTrue(scrollToElement(identifier: "module-configuration-draft-review-action-reward_window", attempts: 12), "Guardian missing reward window review action")
        XCTAssertTrue(scrollToElement(identifier: "module-configuration-draft-finding-SCHOOL_PRIORITY", attempts: 12), "Guardian missing school priority finding")
        XCTAssertTrue(scrollToElement(identifier: "module-configuration-draft-boundary-credit-device", attempts: 12), "Guardian missing credit/device boundary")
        XCTAssertTrue(scrollToElement(identifier: "module-configuration-draft-boundary-school-lms", attempts: 12), "Guardian missing school/LMS boundary")
        navigateBackToModuleCenter()
    }

    func testAppSelectionPolicyRoleScopedSafetyBoundariesCanOpen() {
        launchModuleAudit(role: "孩子")
        openModule(named: "娱乐 App 策略预览")
        XCTAssertTrue(app.navigationBars["娱乐 App"].waitForExistence(timeout: 3), "Missing child app selection page")
        XCTAssertTrue(scrollToElement(identifier: "app-selection-role-child"), "Child app selection did not lock child role")
        XCTAssertTrue(scrollToElement(identifier: "app-selection-metric-candidates"), "Child missing candidate metric")
        XCTAssertTrue(scrollToElement(identifier: "app-selection-candidate-asw-game-arcade"), "Child missing selected game candidate")
        XCTAssertTrue(scrollToElement(identifier: "app-selection-candidate-asw-social-chat"), "Child missing blocked social candidate")
        XCTAssertTrue(scrollToElement(identifier: "app-selection-policy-mock-device-boundary", attempts: 12), "Child missing mock device boundary step")
        XCTAssertTrue(scrollToElement(identifier: "app-selection-finding-child-no-direct-unlock", attempts: 12), "Child missing no-direct-unlock finding")
        XCTAssertFalse(app.descendants(matching: .any)["app-selection-metric-pending"].exists, "Child leaked guardian pending metric")
        XCTAssertFalse(app.descendants(matching: .any)["app-selection-candidate-asw-learning-video"].exists, "Child leaked unselected learning candidate")
        navigateBackToModuleCenter()

        launchModuleAudit(role: "家长")
        openModule(named: "娱乐 App 策略预览")
        XCTAssertTrue(app.navigationBars["娱乐 App"].waitForExistence(timeout: 3), "Missing guardian app selection page")
        XCTAssertTrue(scrollToElement(identifier: "app-selection-role-guardian"), "Guardian app selection did not lock guardian role")
        XCTAssertTrue(scrollToElement(identifier: "app-selection-metric-pending"), "Guardian missing pending metric")
        XCTAssertTrue(scrollToElement(identifier: "app-selection-metric-high-risk"), "Guardian missing high risk metric")
        XCTAssertTrue(scrollToElement(identifier: "app-selection-candidate-asw-learning-video"), "Guardian missing unselected learning candidate")
        XCTAssertTrue(scrollToElement(identifier: "app-selection-policy-guardian-approval", attempts: 12), "Guardian missing approval policy step")
        XCTAssertTrue(scrollToElement(identifier: "app-selection-finding-guardian-approval-required", attempts: 12), "Guardian missing approval finding")
        XCTAssertTrue(scrollToElement(identifier: "app-selection-finding-age-gate-blocked", attempts: 12), "Guardian missing age gate finding")
        XCTAssertTrue(scrollToElement(identifier: "app-selection-boundary-family-controls", attempts: 12), "Guardian missing FamilyControls boundary")
        XCTAssertTrue(scrollToElement(identifier: "app-selection-boundary-ledger-credit-device", attempts: 12), "Guardian missing ledger/credit/device boundary")
        navigateBackToModuleCenter()
    }

    func testReleaseGateGuardianAndOperationsReadOnlyChecksCanOpen() {
        launchModuleAudit(role: "家长")
        openModule(named: "移动端发布质量门")
        XCTAssertTrue(app.navigationBars["发布质量门"].waitForExistence(timeout: 3), "Missing guardian release gate")
        XCTAssertTrue(scrollToElement(identifier: "release-gate-role-guardian"), "Guardian release gate did not lock guardian role")
        XCTAssertTrue(scrollToElement(identifier: "release-gate-status"), "Guardian missing release gate status")
        XCTAssertTrue(scrollToElement(identifier: "release-gate-metric-actions"), "Guardian missing action metric")
        XCTAssertTrue(scrollToElement(identifier: "release-gate-check-module_keys", attempts: 12), "Guardian missing module key check")
        XCTAssertTrue(scrollToElement(identifier: "release-gate-check-permission_gateway", attempts: 12), "Guardian missing permission gateway check")
        XCTAssertTrue(scrollToElement(identifier: "release-gate-check-rollback_gate", attempts: 12), "Guardian missing rollback gate check")
        XCTAssertTrue(scrollToElement(identifier: "release-gate-boundary-ledger", attempts: 14), "Guardian missing ledger guardrail")
        XCTAssertTrue(scrollToElement(identifier: "release-gate-boundary-ai-cloud", attempts: 14), "Guardian missing AI/cloud guardrail")
        XCTAssertFalse(app.descendants(matching: .any)["release-gate-role-operations"].exists, "Guardian route leaked operations role")
        navigateBackToModuleCenter()

        launchModuleAudit(role: "运营")
        openModule(named: "移动端发布质量门")
        XCTAssertTrue(app.navigationBars["发布质量门"].waitForExistence(timeout: 3), "Missing operations release gate")
        XCTAssertTrue(scrollToElement(identifier: "release-gate-role-operations"), "Operations release gate did not lock operations role")
        XCTAssertTrue(scrollToElement(identifier: "release-gate-status"), "Operations missing release gate status")
        XCTAssertTrue(scrollToElement(identifier: "release-gate-metric-warnings"), "Operations missing warning metric")
        XCTAssertTrue(scrollToElement(identifier: "release-gate-check-offline_sync", attempts: 12), "Operations missing offline sync check")
        XCTAssertTrue(scrollToElement(identifier: "release-gate-check-homework_inbox", attempts: 12), "Operations missing homework inbox check")
        XCTAssertTrue(scrollToElement(identifier: "release-gate-boundary-school-lms", attempts: 14), "Operations missing school/LMS guardrail")
        XCTAssertTrue(scrollToElement(identifier: "release-gate-boundary-entitlement-order", attempts: 14), "Operations missing entitlement/order guardrail")
        XCTAssertFalse(app.descendants(matching: .any)["release-gate-role-guardian"].exists, "Operations route leaked guardian role")
        navigateBackToModuleCenter()
    }

    func testAIHomeworkGuideInboxRoleScopedReadOnlyItemsCanOpen() {
        launchModuleAudit(role: "孩子")
        openModule(named: "AI 引导学习")
        XCTAssertTrue(app.navigationBars["家校作业收件箱"].waitForExistence(timeout: 3), "Missing child AI homework inbox")
        XCTAssertTrue(scrollToElement(identifier: "ai-homework-inbox-role-child"), "Child AI inbox did not lock child role")
        XCTAssertTrue(scrollToElement(identifier: "ai-homework-inbox-status"), "Child missing AI inbox status")
        XCTAssertTrue(scrollToElement(identifier: "ai-homework-inbox-item-homework_status-0"), "Child missing homework status item")
        XCTAssertTrue(scrollToElement(identifier: "ai-homework-inbox-item-ai_guidance-1"), "Child missing AI guidance item")
        XCTAssertTrue(scrollToElement(identifier: "ai-homework-inbox-finding-CHILD_SENSITIVE_FIELDS_HIDDEN", attempts: 12), "Child missing sensitive-field redaction finding")
        XCTAssertTrue(scrollToElement(identifier: "ai-homework-inbox-boundary-ai-lms", attempts: 14), "Child missing AI/LMS guardrail")
        XCTAssertFalse(app.descendants(matching: .any)["ai-homework-inbox-item-guardian_review-0"].exists, "Child leaked guardian review item")
        XCTAssertFalse(app.descendants(matching: .any)["ai-homework-inbox-item-credit_review-1"].exists, "Child leaked credit review item")
        navigateBackToModuleCenter()

        launchModuleAudit(role: "家长")
        openModule(named: "AI 引导学习")
        XCTAssertTrue(app.navigationBars["家校作业收件箱"].waitForExistence(timeout: 3), "Missing guardian AI homework inbox")
        XCTAssertTrue(scrollToElement(identifier: "ai-homework-inbox-role-guardian"), "Guardian AI inbox did not lock guardian role")
        XCTAssertTrue(scrollToElement(identifier: "ai-homework-inbox-visible-count"), "Guardian missing visible count")
        XCTAssertTrue(scrollToElement(identifier: "ai-homework-inbox-item-guardian_review-0"), "Guardian missing review item")
        XCTAssertTrue(scrollToElement(identifier: "ai-homework-inbox-item-credit_review-1"), "Guardian missing credit review item")
        XCTAssertTrue(scrollToElement(identifier: "ai-homework-inbox-finding-MANUAL_REVIEW_REQUIRED", attempts: 12), "Guardian missing manual review finding")
        XCTAssertTrue(scrollToElement(identifier: "ai-homework-inbox-boundary-ledger-credit", attempts: 14), "Guardian missing ledger/credit guardrail")
        navigateBackToModuleCenter()

        launchModuleAudit(role: "老师")
        openModule(named: "AI 引导学习")
        XCTAssertTrue(app.navigationBars["家校作业收件箱"].waitForExistence(timeout: 3), "Missing teacher AI homework inbox")
        XCTAssertTrue(scrollToElement(identifier: "ai-homework-inbox-role-teacher"), "Teacher AI inbox did not lock teacher role")
        XCTAssertTrue(scrollToElement(identifier: "ai-homework-inbox-item-teacher_review-0"), "Teacher missing teacher review item")
        XCTAssertTrue(scrollToElement(identifier: "ai-homework-inbox-finding-ROLE_VISIBILITY_APPLIED", attempts: 12), "Teacher missing role visibility finding")
        XCTAssertFalse(app.descendants(matching: .any)["ai-homework-inbox-item-credit_review-1"].exists, "Teacher leaked credit review item")
        navigateBackToModuleCenter()

        launchModuleAudit(role: "运营")
        openModule(named: "AI 引导学习")
        XCTAssertTrue(app.navigationBars["家校作业收件箱"].waitForExistence(timeout: 3), "Missing operations AI homework inbox")
        XCTAssertTrue(scrollToElement(identifier: "ai-homework-inbox-role-operations"), "Operations AI inbox did not lock operations role")
        XCTAssertTrue(scrollToElement(identifier: "ai-homework-inbox-item-operations_summary-0"), "Operations missing redacted summary item")
        XCTAssertTrue(scrollToElement(identifier: "ai-homework-inbox-finding-ROLE_VISIBILITY_APPLIED", attempts: 12), "Operations missing role visibility finding")
        XCTAssertTrue(scrollToElement(identifier: "ai-homework-inbox-boundary-school-notification", attempts: 14), "Operations missing school/notification guardrail")
        XCTAssertFalse(app.descendants(matching: .any)["ai-homework-inbox-item-homework_status-0"].exists, "Operations leaked child homework item")
        navigateBackToModuleCenter()
    }

    func testOfflineSyncReplayRoleScopedResultsCanOpen() {
        let matrix: [(role: String, expectedIds: [String], hiddenIds: [String])] = [
            (
                "孩子",
                [
                    "offline-sync-review-headline",
                    "offline-sync-review-count-pending",
                    "offline-sync-review-replay-button",
                    "offline-sync-review-result-confirmed",
                    "offline-sync-review-result-needs_guardian_review"
                ],
                [
                    "offline-sync-review-count-conflict",
                    "offline-sync-review-count-rolledBack",
                    "offline-sync-review-result-conflict",
                    "offline-sync-review-result-rolled_back",
                    "offline-sync-review-conflict-conflict",
                    "offline-sync-review-conflict-rolledBack"
                ]
            ),
            (
                "家长",
                [
                    "offline-sync-review-headline",
                    "offline-sync-review-count-pending",
                    "offline-sync-review-count-conflict",
                    "offline-sync-review-count-rolledBack",
                    "offline-sync-review-replay-button",
                    "offline-sync-review-replay-headline",
                    "offline-sync-review-result-confirmed",
                    "offline-sync-review-result-needs_guardian_review",
                    "offline-sync-review-result-conflict",
                    "offline-sync-review-result-rolled_back",
                    "offline-sync-review-conflict-conflict",
                    "offline-sync-review-conflict-rolledBack"
                ],
                []
            )
        ]

        for entry in matrix {
            launchModuleAudit(role: entry.role)
            openModule(named: "离线同步复核台")
            XCTAssertTrue(app.navigationBars["离线同步复核台"].waitForExistence(timeout: 3), "\(entry.role) missing offline sync page")

            XCTAssertTrue(scrollToElement(identifier: "offline-sync-review-headline"), "\(entry.role) missing offline headline")
            XCTAssertTrue(scrollToElement(identifier: "offline-sync-review-count-pending"), "\(entry.role) missing pending count")
            XCTAssertTrue(tapScrollableButton(identifier: "offline-sync-review-replay-button"), "\(entry.role) missing replay button")

            for identifier in entry.expectedIds {
                XCTAssertTrue(scrollToElement(identifier: identifier, attempts: 12), "\(entry.role) missing offline sync item \(identifier)")
            }

            app.swipeDown()
            app.swipeDown()
            for identifier in entry.hiddenIds {
                XCTAssertFalse(scrollToElement(identifier: identifier, attempts: 6), "\(entry.role) leaked offline sync item \(identifier)")
            }

            navigateBackToModuleCenter()
        }
    }

    func testRewardRedemptionCanStartAndEndWithoutDuplicateOfflineControls() {
        launchModuleAudit(role: "孩子")
        selectRole("孩子")
        openModule(named: "今日基础任务")
        tapIfExists("开始第一个可打卡任务")

        let proofField = app.descendants(matching: .any)["task-detail-proof-text"].firstMatch
        XCTAssertTrue(scrollToElement(identifier: "task-detail-proof-text", attempts: 8))
        proofField.tap()
        proofField.typeText("完成奖励兑换前置任务")
        app.buttons["task-detail-submit-for-approval"].tap()
        XCTAssertTrue(scrollToElement(identifier: "task-detail-submitted-status", attempts: 8))

        navigateBackToModuleCenter()
        openTab(named: "家长")

        let pinField = app.secureTextFields["输入家长 PIN"].firstMatch
        XCTAssertTrue(pinField.waitForExistence(timeout: 3))
        pinField.tap()
        pinField.typeText("1234")
        app.buttons["parent-mode-unlock"].tap()
        XCTAssertTrue(tapScrollableButton(prefix: "parent-mode-approve-"), "Missing pending approval action")

        openTab(named: "模块")
        openModule(named: "成长积分兑换窗口")
        XCTAssertTrue(scrollToElement(identifier: "child-credit-wallet-balance"), "Missing child wallet balance")
        XCTAssertTrue(tapScrollableButton(identifier: "child-credit-wallet-action-open_redemption"), "Missing wallet redemption action")

        XCTAssertTrue(scrollToElement(identifier: "reward-redemption-balance"), "Missing reward balance")
        XCTAssertTrue(tapScrollableButton(identifier: "reward-redemption-use-15"), "Missing direct reward start button")
        XCTAssertTrue(
            scrollToElementBothWays(identifier: "reward-redemption-status-active", upAttempts: 2, downAttempts: 8),
            "Missing active reward status"
        )
        XCTAssertTrue(scrollToElement(identifier: "reward-redemption-result-started"), "Missing redemption result")
        XCTAssertTrue(tapScrollableButton(identifier: "reward-redemption-end-session"), "Missing direct reward end button")
        XCTAssertTrue(scrollToElement(identifier: "reward-redemption-balance"), "Reward balance should remain visible after ending")
        XCTAssertFalse(app.buttons["reward-redemption-offline-request-15"].exists, "Duplicate offline request action should stay hidden")
        navigateBackToModuleCenter()
    }

    func testRewardStatusSessionAndInventoryReviewCanRoundTrip() {
        launchModuleAudit(role: "孩子")
        selectRole("孩子")
        openModule(named: "今日基础任务")
        tapIfExists("开始第一个可打卡任务")

        let proofField = app.descendants(matching: .any)["task-detail-proof-text"].firstMatch
        XCTAssertTrue(scrollToElement(identifier: "task-detail-proof-text", attempts: 8))
        proofField.tap()
        proofField.typeText("完成奖励状态页前置任务")
        app.buttons["task-detail-submit-for-approval"].tap()
        XCTAssertTrue(scrollToElement(identifier: "task-detail-submitted-status", attempts: 8))

        navigateBackToModuleCenter()
        openTab(named: "家长")

        let pinField = app.secureTextFields["输入家长 PIN"].firstMatch
        XCTAssertTrue(pinField.waitForExistence(timeout: 3))
        pinField.tap()
        pinField.typeText("1234")
        app.buttons["parent-mode-unlock"].tap()
        XCTAssertTrue(tapScrollableButton(prefix: "parent-mode-approve-"), "Missing pending approval action")

        openTab(named: "模块")
        selectRole("家长")
        openModule(named: "成长积分兑换窗口")
        XCTAssertTrue(scrollToElement(identifier: "reward-status-balance"), "Missing reward status balance")
        XCTAssertTrue(scrollToElement(identifier: "reward-status-state-locked"), "Missing locked reward status")
        XCTAssertTrue(scrollToElement(identifier: "reward-status-real-device-readiness"), "Missing reward status real device readiness")
        XCTAssertTrue(tapScrollableButton(identifier: "reward-status-use-15"), "Missing reward status start button")
        XCTAssertTrue(
            scrollToElementBothWays(identifier: "reward-status-state-active", upAttempts: 2, downAttempts: 8),
            "Missing active reward status"
        )
        XCTAssertTrue(scrollToElement(identifier: "reward-status-result-started"), "Missing reward status redemption result")
        XCTAssertTrue(scrollToElement(identifier: "reward-status-device-command-receipt"), "Missing reward status device command receipt")
        XCTAssertTrue(tapScrollableButton(identifier: "reward-status-end-session"), "Missing reward status end button")
        XCTAssertTrue(scrollToElement(identifier: "reward-status-latest-receipt"), "Missing reward status receipt")
        XCTAssertTrue(tapScrollableButton(identifier: "credit-settlement-refresh", attempts: 12), "Missing reward status credit settlement refresh")

        XCTAssertTrue(tapScrollableButton(identifier: "reward-status-inventory-link"), "Missing reward status inventory link")
        XCTAssertTrue(app.navigationBars["库存履约复核"].waitForExistence(timeout: 3), "Missing guardian inventory review")
        XCTAssertTrue(scrollToElement(identifier: "reward-store-fulfillment-title"), "Missing inventory review title")
        navigateBack()
        navigateBackToModuleCenter()
    }

    func testRewardStoreFulfillmentRoleScopedReadOnlySectionsCanOpen() {
        let matrix: [(role: String, navigationTitle: String, expectedIds: [String], hiddenIds: [String])] = [
            (
                "孩子",
                "奖励商店",
                [
                    "reward-store-fulfillment-title",
                    "reward-store-fulfillment-metric-redeemable",
                    "reward-store-fulfillment-metric-needs-parent",
                    "reward-store-fulfillment-row-redeemable",
                    "reward-store-fulfillment-row-reserved",
                    "reward-store-fulfillment-row-needsParent",
                    "reward-store-fulfillment-row-unavailable",
                    "reward-store-fulfillment-finding-READ_ONLY_READY",
                    "reward-store-fulfillment-guardrail-real-redemption",
                    "reward-store-fulfillment-guardrail-credit-deduction",
                    "reward-store-fulfillment-guardrail-network-notification"
                ],
                [
                    "reward-store-fulfillment-finding-DUPLICATE_CREDIT_DEDUCTION",
                    "reward-store-fulfillment-guardrail-redemption-order-inventory"
                ]
            ),
            (
                "家长",
                "库存履约复核",
                [
                    "reward-store-fulfillment-title",
                    "reward-store-fulfillment-metric-needs-parent",
                    "reward-store-fulfillment-metric-unavailable",
                    "reward-store-fulfillment-row-reserved",
                    "reward-store-fulfillment-row-needsParent",
                    "reward-store-fulfillment-row-unavailable",
                    "reward-store-fulfillment-finding-INVENTORY_SOLD_OUT_OR_OVERSOLD",
                    "reward-store-fulfillment-finding-DUPLICATE_CREDIT_DEDUCTION",
                    "reward-store-fulfillment-finding-PHYSICAL_ADDRESS_CONFIRMATION",
                    "reward-store-fulfillment-finding-DEVICE_TIME_CAP_REVIEW",
                    "reward-store-fulfillment-finding-OFFLINE_REPLAY_PENDING",
                    "reward-store-fulfillment-guardrail-redemption-order-inventory",
                    "reward-store-fulfillment-guardrail-credit-ledger",
                    "reward-store-fulfillment-guardrail-network-ai-school-notification"
                ],
                [
                    "reward-store-fulfillment-guardrail-real-redemption"
                ]
            )
        ]

        for entry in matrix {
            launchModuleAudit(role: entry.role)
            openModule(named: "奖励库存履约")
            XCTAssertTrue(app.navigationBars[entry.navigationTitle].waitForExistence(timeout: 3), "\(entry.role) missing reward fulfillment page")

            for identifier in entry.expectedIds {
                XCTAssertTrue(scrollToElement(identifier: identifier, attempts: 14), "\(entry.role) missing reward fulfillment item \(identifier)")
            }

            app.swipeDown()
            app.swipeDown()
            for identifier in entry.hiddenIds {
                XCTAssertFalse(app.descendants(matching: .any)[identifier].exists, "\(entry.role) leaked reward fulfillment item \(identifier)")
            }

            navigateBackToModuleCenter()
        }
    }

    func testGrowthPackExecutionHubDeepLinksCanRoundTrip() {
        launchModuleAudit(role: "孩子")
        selectRole("孩子")
        openModule(named: "成长包执行中心")
        XCTAssertTrue(app.navigationBars["成长包执行"].waitForExistence(timeout: 3))

        let overviewLinks: [(identifier: String, title: String)] = [
            ("growth-pack-execution-link-adaptive-schedule", "今日计划"),
            ("growth-pack-execution-link-proof-preparation", "准备证明"),
            ("growth-pack-execution-link-evidence-timeline", "证据时间线"),
            ("growth-pack-execution-link-achievement-card-preview", "徽章能力卡预览"),
            ("growth-pack-execution-link-honor-wall-publication-preview", "荣誉墙发布预览")
        ]

        for link in overviewLinks {
            XCTAssertTrue(tapScrollableButton(identifier: link.identifier), "Missing execution hub link \(link.identifier)")
            XCTAssertTrue(app.navigationBars[link.title].waitForExistence(timeout: 3), "Missing destination \(link.title)")
            navigateBackToTitle("成长包执行")
        }

        XCTAssertTrue(tapScrollableButton(identifier: "growth-pack-execution-link-achievement-card-preview"), "Missing achievement card preview link")
        XCTAssertTrue(app.navigationBars["徽章能力卡预览"].waitForExistence(timeout: 3), "Missing achievement card preview page")
        XCTAssertTrue(scrollToElement(identifier: "achievement-card-metric-candidates"), "Child missing achievement candidate metric")
        XCTAssertTrue(scrollToElement(identifier: "achievement-card-candidate-badge_candidate-needs_more_evidence"), "Child missing badge candidate row")
        XCTAssertTrue(scrollToElement(identifier: "achievement-card-ability-learning"), "Child missing learning ability hint")
        XCTAssertTrue(scrollToElement(identifier: "achievement-card-finding-PREVIEW_ON_HOLD", attempts: 12), "Child missing preview hold finding")
        XCTAssertFalse(app.descendants(matching: .any)["achievement-card-metric-ability-jump"].exists, "Child leaked guardian ability jump metric")

        XCTAssertTrue(tapScrollableButton(identifier: "achievement-card-link-honor-wall-publication"), "Missing nested honor wall publication link")
        XCTAssertTrue(app.navigationBars["荣誉墙发布预览"].waitForExistence(timeout: 3), "Missing honor publication preview page")
        XCTAssertTrue(scrollToElement(identifier: "honor-publication-metric-visible"), "Child missing honor publication visible metric")
        XCTAssertTrue(scrollToElement(identifier: "honor-publication-candidate-badge_candidate-waiting_consent"), "Child missing honor badge candidate row")
        XCTAssertTrue(tapScrollableButton(identifier: "honor-publication-link-emotional-safety", attempts: 12), "Missing honor publication emotional safety link")
        XCTAssertTrue(app.navigationBars["情绪安全中心"].waitForExistence(timeout: 3), "Missing honor publication emotional safety destination")
        navigateBackToTitle("荣誉墙发布预览")
        XCTAssertTrue(scrollToElement(identifier: "honor-publication-finding-WAITING_CONFIRMATION", attempts: 12), "Child missing waiting confirmation finding")
        XCTAssertTrue(scrollToElement(identifier: "honor-publication-boundary-publication", attempts: 12), "Child missing publication boundary")
        XCTAssertTrue(scrollToElement(identifier: "honor-publication-boundary-ledger-device", attempts: 12), "Child missing ledger/device boundary")
        XCTAssertFalse(app.descendants(matching: .any)["honor-publication-metric-guardian-consent"].exists, "Child leaked guardian consent metric")
        XCTAssertFalse(app.descendants(matching: .any)["honor-publication-metric-summary-leak"].exists, "Child leaked summary leak metric")
        navigateBackToTitle("徽章能力卡预览")
        XCTAssertTrue(tapScrollableButton(identifier: "achievement-card-link-regression-appeal", attempts: 12), "Missing achievement regression appeal link")
        XCTAssertTrue(app.navigationBars["回退申诉解释"].waitForExistence(timeout: 3), "Missing regression appeal destination")
        navigateBackToTitle("徽章能力卡预览")
        navigateBackToTitle("成长包执行")

        let stepLinks: [(identifier: String, title: String)] = [
            ("growth-pack-execution-step-school_homework", "作业联动"),
            ("growth-pack-execution-step-quiz_self_check", "测验自检"),
            ("growth-pack-execution-step-external_resource", "外部资源"),
            ("growth-pack-execution-step-creative_showcase", "创作展示"),
            ("growth-pack-execution-step-creator_rubric", "量规适龄"),
            ("growth-pack-execution-step-reward_fulfillment", "奖励商店"),
            ("growth-pack-execution-step-family_honor", "成就快照")
        ]

        for link in stepLinks {
            XCTAssertTrue(tapScrollableButton(identifier: link.identifier), "Missing execution step \(link.identifier)")
            XCTAssertTrue(app.navigationBars[link.title].waitForExistence(timeout: 3), "Missing step destination \(link.title)")
            navigateBackToTitle("成长包执行")
        }

        navigateBackToModuleCenter()
    }

    func testCreativeShowcaseRelativeCommentSafetyAndEmotionalCenterCanRoundTrip() {
        launchModuleAudit(role: "孩子")
        openModule(named: "成长包执行中心")
        XCTAssertTrue(app.navigationBars["成长包执行"].waitForExistence(timeout: 3))

        XCTAssertTrue(tapScrollableButton(identifier: "growth-pack-execution-step-creative_showcase"), "Missing creative showcase step")
        XCTAssertTrue(app.navigationBars["创作展示"].waitForExistence(timeout: 3), "Missing creative showcase page")
        XCTAssertTrue(scrollToElement(identifier: "creative-showcase-item-approvedPreview"), "Child missing approved creative showcase")
        XCTAssertTrue(tapScrollableButton(identifier: "creative-showcase-link-relative-comment-safety"), "Missing relative comment safety link")

        XCTAssertTrue(app.navigationBars["亲友鼓励"].waitForExistence(timeout: 3), "Missing relative comment safety page")
        XCTAssertTrue(scrollToElement(identifier: "relative-comment-metric-visible"), "Child missing relative comment visible metric")
        XCTAssertTrue(scrollToElement(identifier: "relative-comment-row-approvedEncouragement"), "Child missing approved encouragement row")
        XCTAssertTrue(scrollToElement(identifier: "relative-comment-finding-READ_ONLY_READY"), "Child missing read-only finding")
        XCTAssertFalse(app.descendants(matching: .any)["relative-comment-metric-waiting-review"].exists, "Child leaked guardian review metric")
        XCTAssertFalse(app.descendants(matching: .any)["relative-comment-metric-reward-pressure"].exists, "Child leaked reward pressure metric")

        XCTAssertTrue(tapScrollableButton(identifier: "relative-comment-link-emotional-safety"), "Missing emotional safety link")
        XCTAssertTrue(app.navigationBars["情绪安全中心"].waitForExistence(timeout: 3), "Missing emotional safety center")
        XCTAssertTrue(scrollToElement(identifier: "emotional-safety-metric-gentle-support"), "Child missing gentle support metric")
        XCTAssertTrue(scrollToElement(identifier: "emotional-safety-finding-GENTLE_SUPPORT_ONLY", attempts: 14), "Child missing gentle support finding")
        XCTAssertTrue(scrollToElement(identifier: "emotional-safety-finding-WAITING_GUARDIAN_REVIEW", attempts: 14), "Child missing waiting guardian review finding")
        XCTAssertFalse(app.descendants(matching: .any)["emotional-safety-metric-pressure"].exists, "Child leaked pressure metric")
        XCTAssertFalse(app.descendants(matching: .any)["emotional-safety-metric-reward-promise"].exists, "Child leaked reward promise metric")

        navigateBackToModuleCenter()
    }

    func testGrowthPackInstallEntitlementLinksCanRoundTrip() {
        launchModuleAudit(role: "孩子")
        openModule(named: "成长包安装权益")
        XCTAssertTrue(app.navigationBars["成长包安装权益"].waitForExistence(timeout: 3), "Missing child install entitlement page")
        XCTAssertTrue(tapScrollableButton(identifier: "growth-pack-install-link-preinstall-trial"), "Child missing preinstall trial link")
        XCTAssertTrue(app.navigationBars["安装前试运行"].waitForExistence(timeout: 3), "Child missing preinstall trial page")
        XCTAssertTrue(scrollToElement(identifier: "preinstall-trial-metric-visible"), "Child missing preinstall visible metric")
        XCTAssertTrue(scrollToElement(identifier: "preinstall-trial-row-needsGuardianReview"), "Child missing preinstall review row")
        XCTAssertTrue(scrollToElement(identifier: "preinstall-trial-finding-GUARDIAN_REVIEW_REQUIRED"), "Child missing guardian review safety hint")
        XCTAssertFalse(app.descendants(matching: .any)["preinstall-trial-metric-credit-boundary"].exists, "Child leaked credit boundary metric")
        XCTAssertFalse(app.descendants(matching: .any)["preinstall-trial-metric-school-priority"].exists, "Child leaked school priority metric")
        navigateBackToTitle("成长包安装权益")

        XCTAssertTrue(tapScrollableButton(identifier: "growth-pack-install-link-refund-dispute"), "Child missing safe handling link")
        XCTAssertTrue(app.navigationBars["安全处理"].waitForExistence(timeout: 3), "Child missing safe handling page")
        navigateBackToTitle("成长包安装权益")

        XCTAssertTrue(scrollToElement(identifier: "growth-pack-install-decision-installed"), "Child missing installed pack state")
        XCTAssertTrue(scrollToElement(identifier: "growth-pack-install-decision-blocked"), "Child missing blocked pack state")
        XCTAssertTrue(scrollToElement(identifier: "growth-pack-install-guardrail-payment-order"), "Child missing payment guardrail")
        navigateBackToModuleCenter()

        launchModuleAudit(role: "家长")
        openModule(named: "成长包安装权益")
        XCTAssertTrue(app.navigationBars["成长包安装权益"].waitForExistence(timeout: 3), "Missing guardian install entitlement page")

        XCTAssertTrue(tapScrollableButton(identifier: "growth-pack-install-link-cloud-sync"), "Guardian missing cloud sync link")
        XCTAssertTrue(app.navigationBars["成长包云同步"].waitForExistence(timeout: 3), "Guardian missing cloud sync page")
        XCTAssertTrue(tapScrollableButton(identifier: "growth-pack-cloud-sync-refund-dispute-link", attempts: 12), "Guardian missing cloud sync refund dispute link")
        XCTAssertTrue(app.navigationBars["售后复核"].waitForExistence(timeout: 3), "Guardian missing cloud sync refund dispute destination")
        navigateBackToTitle("成长包云同步")
        navigateBackToTitle("成长包安装权益")

        XCTAssertTrue(tapScrollableButton(identifier: "growth-pack-install-link-preinstall-trial"), "Guardian missing preinstall trial link")
        XCTAssertTrue(app.navigationBars["安装前试运行"].waitForExistence(timeout: 3), "Guardian missing preinstall trial page")
        XCTAssertTrue(scrollToElement(identifier: "preinstall-trial-metric-guardian-review"), "Guardian missing trial review metric")
        XCTAssertTrue(scrollToElement(identifier: "preinstall-trial-metric-school-priority"), "Guardian missing school priority metric")
        XCTAssertTrue(scrollToElement(identifier: "preinstall-trial-metric-credit-boundary"), "Guardian missing credit boundary metric")
        XCTAssertTrue(scrollToElement(identifier: "preinstall-trial-row-needsGuardianReview"), "Guardian missing review row")
        XCTAssertTrue(scrollToElement(identifier: "preinstall-trial-row-frozen"), "Guardian missing frozen row")
        XCTAssertTrue(scrollToElement(identifier: "preinstall-trial-finding-SCHOOL_PRIORITY_CONFLICT", attempts: 12), "Guardian missing school priority finding")
        XCTAssertTrue(scrollToElement(identifier: "preinstall-trial-finding-CREDIT_BOUNDARY_REVIEW", attempts: 12), "Guardian missing credit boundary finding")
        XCTAssertTrue(scrollToElement(identifier: "preinstall-trial-boundary-install", attempts: 12), "Guardian missing install boundary")
        XCTAssertTrue(scrollToElement(identifier: "preinstall-trial-boundary-ledger-device", attempts: 12), "Guardian missing ledger/device boundary")
        navigateBackToTitle("成长包安装权益")

        XCTAssertTrue(tapScrollableButton(identifier: "growth-pack-install-link-refund-dispute"), "Guardian missing refund dispute link")
        XCTAssertTrue(app.navigationBars["售后复核"].waitForExistence(timeout: 3), "Guardian missing refund dispute page")
        navigateBackToTitle("成长包安装权益")

        for state in ["installable", "installed", "frozen", "blocked"] {
            XCTAssertTrue(scrollToElement(identifier: "growth-pack-install-decision-\(state)"), "Guardian missing pack state \(state)")
        }
        XCTAssertTrue(scrollToElement(identifier: "growth-pack-install-finding-ENTITLEMENT_REFUNDED_OR_REVOKED", attempts: 12), "Guardian missing refund finding")
        XCTAssertTrue(scrollToElement(identifier: "growth-pack-install-finding-PERMISSION_POLICY_BLOCKED", attempts: 12), "Guardian missing permission finding")
        XCTAssertTrue(scrollToElement(identifier: "growth-pack-install-guardrail-cloud-cdn-notification", attempts: 12), "Guardian missing cloud guardrail")

        navigateBackToModuleCenter()
    }

    func testSchoolHomeworkDetailAiAndReviewLinksCanRoundTrip() {
        launchModuleAudit(role: "孩子")
        selectRole("孩子")
        openModule(named: "学校作业")
        XCTAssertTrue(app.navigationBars["作业联动"].waitForExistence(timeout: 3))
        XCTAssertTrue(tapScrollableButton(identifier: "school-homework-linkage-school-homework-list"), "Missing school homework list link")
        XCTAssertTrue(tapScrollableButton(identifier: "school-homework-link-growth-pack-linkage"), "Missing homework linkage return link")
        XCTAssertTrue(app.navigationBars["作业联动"].waitForExistence(timeout: 3), "Missing homework linkage destination")
        XCTAssertTrue(tapScrollableButton(identifier: "school-homework-linkage-joint-approval"), "Missing homework linkage joint approval link")
        XCTAssertTrue(app.navigationBars["联合审批台"].waitForExistence(timeout: 3), "Missing joint approval destination")
        navigateBackToTitle("作业联动")
        XCTAssertTrue(tapScrollableButton(identifier: "school-homework-linkage-content-player"), "Missing homework linkage content player link")
        XCTAssertTrue(app.navigationBars["内容播放器"].waitForExistence(timeout: 3), "Missing content player destination")
        navigateBackToTitle("作业联动")
        navigateBackToTitle("学校作业")

        XCTAssertTrue(tapScrollableButton(identifier: "school-homework-link-credit-snapshot"), "Missing school credit snapshot link")
        XCTAssertTrue(app.navigationBars["学校成长快照"].waitForExistence(timeout: 3), "Missing school growth snapshot destination")
        navigateBackToTitle("学校作业")

        XCTAssertTrue(tapScrollableButton(prefix: "school-homework-settled-row-"), "Missing settled school homework row")
        XCTAssertTrue(app.navigationBars["作业详情"].waitForExistence(timeout: 3), "Missing settled homework detail")
        navigateBackToTitle("学校作业")

        XCTAssertTrue(tapScrollableButton(identifier: "school-homework-open-row-0"), "Missing first open homework row")
        XCTAssertTrue(app.navigationBars["作业详情"].waitForExistence(timeout: 3))

        XCTAssertTrue(tapScrollableButton(identifier: "school-homework-detail-ai-guidance"), "Missing AI guidance link")
        XCTAssertTrue(app.navigationBars["AI 作业引导"].waitForExistence(timeout: 3))
        XCTAssertTrue(tapScrollableButton(identifier: "ai-homework-preset-where_to_start"), "Missing AI preset question")
        XCTAssertTrue(scrollToStaticText(containing: "你问的是", direction: .down), "Missing AI guidance feedback")
        XCTAssertTrue(tapScrollableButton(identifier: "ai-homework-followup-0"), "Missing AI follow-up question")
        XCTAssertTrue(scrollToStaticText(containing: "你问的是", direction: .down), "Missing AI follow-up feedback")
        XCTAssertTrue(scrollToElement(identifier: "ai-homework-free-text"), "Missing AI free text field")
        let aiFreeText = app.descendants(matching: .any)["ai-homework-free-text"].firstMatch
        XCTAssertTrue(aiFreeText.waitForExistence(timeout: 3), "Missing AI free text field")
        aiFreeText.tap()
        aiFreeText.typeText("我还卡在第一步")
        XCTAssertTrue(tapScrollableButton(identifier: "ai-homework-send-free-text"), "Missing AI free text send button")
        XCTAssertTrue(scrollToStaticText(containing: "你问的是", direction: .down), "Missing AI free text feedback")
        navigateBackToTitle("作业详情")

        let detailLinks: [(identifier: String, title: String)] = [
            ("school-homework-detail-credit-handoff", "作业交接复核"),
            ("school-homework-detail-family-school-inbox", "家校作业收件箱"),
            ("school-homework-detail-lms-boundary", "作业 AI 安全边界"),
            ("mobile-offline-sync-review-link-child", "离线同步复核台")
        ]

        for link in detailLinks {
            XCTAssertTrue(tapScrollableButton(identifier: link.identifier), "Missing homework detail link \(link.identifier)")
            XCTAssertTrue(app.navigationBars[link.title].waitForExistence(timeout: 3), "Missing homework detail destination \(link.title)")
            if link.identifier == "school-homework-detail-lms-boundary" {
                XCTAssertTrue(scrollToElement(identifier: "ai-lms-boundary-headline"), "Missing AI/LMS boundary headline")
                XCTAssertTrue(scrollToElement(identifier: "ai-lms-boundary-provider-details-hidden"), "Child missing provider redaction")
                XCTAssertTrue(scrollToElement(identifier: "ai-lms-boundary-provider-no-direct-answer"), "Child missing no-direct-answer boundary")
                XCTAssertTrue(scrollToElement(identifier: "ai-lms-boundary-lms-read-only"), "Child missing LMS read-only row")
                XCTAssertTrue(scrollToElement(identifier: "ai-lms-boundary-consent-details-hidden"), "Child missing consent redaction")
                XCTAssertTrue(scrollToElement(identifier: "ai-lms-boundary-transcript-stores-raw", attempts: 12), "Child missing transcript raw boundary")
                XCTAssertTrue(scrollToElement(identifier: "ai-lms-boundary-audit-writes-external", attempts: 12), "Child missing audit external-write boundary")
                XCTAssertTrue(scrollToElement(identifier: "ai-lms-boundary-finding-CHILD_VISIBILITY_REDACTED", attempts: 12), "Child missing visibility finding")
                XCTAssertTrue(scrollToElement(identifier: "ai-lms-boundary-finding-LMS_READ_ONLY", attempts: 12), "Child missing LMS read-only finding")
                XCTAssertTrue(scrollToElement(identifier: "ai-lms-boundary-guardrail-ai-qwen", attempts: 12), "Child missing AI/QWEN guardrail")
                XCTAssertTrue(scrollToElement(identifier: "ai-lms-boundary-guardrail-school-ledger", attempts: 12), "Child missing school/ledger guardrail")
            }
            navigateBackToTitle("作业详情")
        }

        navigateBackToTitle("学校作业")
        XCTAssertTrue(tapScrollableButton(identifier: "school-homework-open-row-1"), "Missing text-proof homework row")
        XCTAssertTrue(app.navigationBars["作业详情"].waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToElement(identifier: "school-homework-detail-proof-text", attempts: 12), "Missing homework proof field")
        let proofText = app.descendants(matching: .any)["school-homework-detail-proof-text"].firstMatch
        proofText.tap()
        proofText.typeText("我完成了作业并整理了步骤")
        XCTAssertTrue(tapScrollableButton(identifier: "school-homework-detail-submit-proof", attempts: 8), "Missing homework proof submit")
        XCTAssertTrue(scrollToElement(identifier: "school-homework-detail-offline-hint", attempts: 8), "Missing homework offline submit feedback")
        XCTAssertTrue(scrollToElement(identifier: "school-homework-detail-status-submitted", attempts: 8), "Missing submitted homework status")
        XCTAssertTrue(scrollToElement(identifier: "school-homework-detail-submitted-proof", attempts: 8), "Missing submitted homework proof")

        navigateBackToModuleCenter()
    }

    func testSchoolJointApprovalRoleScopedReadOnlySectionsCanOpen() {
        let matrix: [(role: String, expectedIds: [String], hiddenIds: [String])] = [
            (
                "孩子",
                [
                    "school-joint-approval-status",
                    "school-joint-approval-stage-summary",
                    "school-joint-approval-item-returned",
                    "school-joint-approval-finding-ROLE_VISIBILITY_APPLIED",
                    "school-joint-approval-guardrail-teacher-guardian",
                    "school-joint-approval-guardrail-school-lms"
                ],
                [
                    "school-joint-approval-credit-note-action",
                    "school-joint-approval-credit-note-preview",
                    "school-joint-approval-finding-CREDIT_SUGGESTION_REVIEW"
                ]
            ),
            (
                "家长",
                [
                    "school-joint-approval-status",
                    "school-joint-approval-stage-summary",
                    "school-joint-approval-item-returned",
                    "school-joint-approval-credit-note-action",
                    "school-joint-approval-finding-HOMEWORK_RETURNED",
                    "school-joint-approval-finding-CREDIT_SUGGESTION_REVIEW",
                    "school-joint-approval-guardrail-credit-ledger",
                    "school-joint-approval-guardrail-notification-device"
                ],
                []
            ),
            (
                "老师",
                [
                    "school-joint-approval-status",
                    "school-joint-approval-stage-summary",
                    "school-joint-approval-item-returned",
                    "school-joint-approval-finding-ROLE_VISIBILITY_APPLIED",
                    "school-joint-approval-guardrail-teacher-guardian",
                    "school-joint-approval-guardrail-school-lms"
                ],
                [
                    "school-joint-approval-credit-note-action",
                    "school-joint-approval-credit-note-preview",
                    "school-joint-approval-finding-CREDIT_SUGGESTION_REVIEW"
                ]
            )
        ]

        for entry in matrix {
            launchModuleAudit(role: entry.role)
            openModule(named: "家校联合审批")
            XCTAssertTrue(app.navigationBars["联合审批台"].waitForExistence(timeout: 3), "\(entry.role) missing joint approval page")

            for identifier in entry.expectedIds {
                XCTAssertTrue(scrollToElement(identifier: identifier, attempts: 14), "\(entry.role) missing joint approval item \(identifier)")
            }

            app.swipeDown()
            app.swipeDown()
            for identifier in entry.hiddenIds {
                XCTAssertFalse(scrollToElement(identifier: identifier, attempts: 6), "\(entry.role) leaked joint approval item \(identifier)")
            }

            navigateBackToModuleCenter()
        }
    }

    func testNotificationDigestRoleScopedCardsCanOpen() {
        let matrix: [(role: String, visibleCards: [String], hiddenCards: [String])] = [
            (
                "家长",
                ["guardian_review", "child_homework", "teacher_school", "relative_family", "quiet_window", "event_evidence"],
                []
            ),
            (
                "孩子",
                ["child_homework", "quiet_window"],
                ["guardian_review", "teacher_school", "relative_family", "event_evidence"]
            ),
            (
                "老师",
                ["teacher_school", "quiet_window", "event_evidence"],
                ["guardian_review", "child_homework", "relative_family"]
            ),
            (
                "亲友",
                ["relative_family", "quiet_window"],
                ["guardian_review", "child_homework", "teacher_school", "event_evidence"]
            )
        ]

        for entry in matrix {
            launchModuleAudit(role: entry.role)
            openModule(named: "通知摘要同意")
            XCTAssertTrue(app.navigationBars["通知摘要同意"].waitForExistence(timeout: 3), "Missing notification digest for \(entry.role)")
            XCTAssertTrue(scrollToStaticText(containing: "条"), "Missing digest count for \(entry.role)")

            for card in entry.visibleCards {
                XCTAssertTrue(scrollToElement(identifier: "notification-digest-card-\(card)"), "\(entry.role) missing card \(card)")
            }

            app.swipeDown()
            app.swipeDown()
            for card in entry.hiddenCards {
                XCTAssertFalse(app.otherElements["notification-digest-card-\(card)"].exists, "\(entry.role) leaked hidden card \(card)")
            }

            XCTAssertTrue(scrollToElement(identifier: "notification-digest-finding-FAMILY_SCHOOL_DIGEST_CENTER_OK"), "\(entry.role) missing digest finding")
            XCTAssertTrue(scrollToStaticText(containing: "通知/队列"), "\(entry.role) missing read-only guardrail")
            XCTAssertTrue(scrollToStaticText(containing: "不会"), "\(entry.role) missing side-effect boundary")

            navigateBackToModuleCenter()
        }
    }

    func testReportsPreviewRoleScopedReadOnlySectionsCanOpen() {
        launchModuleAudit(role: "孩子")
        openModule(named: "成长报告预览")
        XCTAssertTrue(app.navigationBars["成长报告"].waitForExistence(timeout: 3), "Missing child reports page")
        XCTAssertTrue(scrollToElement(identifier: "reports-metric-task-approved"), "Child missing completed task metric")
        XCTAssertTrue(scrollToElement(identifier: "reports-section-reports-tasks"), "Child missing task report section")
        XCTAssertTrue(scrollToElement(identifier: "reports-section-reports-school"), "Child missing school report section")
        XCTAssertTrue(scrollToElement(identifier: "reports-finding-child-report-read-only"), "Child missing read-only finding")
        XCTAssertTrue(scrollToElement(identifier: "reports-boundary-file-pdf-upload"), "Child missing report export boundary")
        navigateBackToModuleCenter()

        launchModuleAudit(role: "家长")
        openModule(named: "成长报告预览")
        XCTAssertTrue(app.navigationBars["成长报告"].waitForExistence(timeout: 3), "Missing guardian reports page")
        XCTAssertTrue(scrollToElement(identifier: "reports-metric-credit-available"), "Guardian missing credit preview metric")
        XCTAssertTrue(scrollToElement(identifier: "reports-metric-review-pending"), "Guardian missing pending review metric")
        XCTAssertTrue(scrollToElement(identifier: "reports-section-reports-credit"), "Guardian missing credit report section")
        XCTAssertTrue(scrollToElement(identifier: "reports-section-reports-wellbeing"), "Guardian missing wellbeing report section")
        XCTAssertTrue(scrollToElement(identifier: "reports-finding-no-export"), "Guardian missing no-export finding")
        XCTAssertTrue(scrollToElement(identifier: "reports-finding-relative-comments-pending"), "Guardian missing relative comment finding")
        XCTAssertTrue(scrollToElement(identifier: "reports-boundary-ledger-credit-device"), "Guardian missing ledger boundary")
        navigateBackToModuleCenter()
    }

    func testHonorWallAchievementDashboardRoleScopedSectionsCanOpen() {
        let matrix: [(role: String, expectedIds: [String])] = [
            (
                "孩子",
                [
                    "family-achievement-status",
                    "family-achievement-evidence-visible",
                    "family-achievement-summary-badge",
                    "family-achievement-summary-ability-card",
                    "family-achievement-relative-visible"
                ]
            ),
            (
                "家长",
                [
                    "family-achievement-status",
                    "family-achievement-evidence-review-required",
                    "family-achievement-relative-pending-comments",
                    "family-achievement-summary-honor",
                    "family-achievement-action-approveRelativeComment"
                ]
            ),
            (
                "亲友",
                [
                    "family-achievement-status",
                    "family-achievement-evidence-visible",
                    "family-achievement-relative-visible",
                    "family-achievement-relative-ref",
                    "family-achievement-summary-storyline"
                ]
            )
        ]

        for entry in matrix {
            launchModuleAudit(role: entry.role)
            openModule(named: "荣誉墙与球星卡")
            XCTAssertTrue(app.navigationBars["成就快照"].waitForExistence(timeout: 3), "\(entry.role) missing achievement dashboard")

            for identifier in entry.expectedIds {
                XCTAssertTrue(scrollToElement(identifier: identifier, attempts: 12), "\(entry.role) missing honor dashboard item \(identifier)")
            }

            navigateBackToModuleCenter()
        }
    }

    func testFamilyGrowthTabDeepLinksCanRoundTrip() {
        launchDefaultApp(initialTab: "family", expectedTitle: "家庭成长")
        XCTAssertTrue(app.navigationBars["家庭成长"].waitForExistence(timeout: 3), "Missing family growth tab")
        XCTAssertTrue(
            app.staticTexts["family-growth-real-task-records"].waitForExistence(timeout: 3),
            "Family growth should label local task records before preview-only areas"
        )
        let rewardText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "完成后奖励")).firstMatch
        XCTAssertTrue(
            rewardText.waitForExistence(timeout: 3),
            "Family growth should show local task reward context before preview-only areas"
        )
        let relativeSegment = app.buttons["亲友视角"].firstMatch
        XCTAssertTrue(relativeSegment.waitForExistence(timeout: 3), "Missing relative audience switch")
        relativeSegment.tap()
        XCTAssertTrue(
            app.staticTexts["family-growth-real-task-relative-boundary"].waitForExistence(timeout: 3),
            "Relative audience should not see local task details"
        )
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "完成后奖励")).firstMatch.exists,
            "Relative audience should hide real task reward rows"
        )
        app.buttons["家庭视角"].firstMatch.tap()

        let links: [(identifier: String, title: String)] = [
            ("family-growth-link-mobile-detail", "成长包详情"),
            ("family-growth-link-install-entitlement", "成长包安装权益"),
            ("family-growth-link-achievement-dashboard", "成就快照"),
            ("family-growth-link-relative-participation", "亲友参与"),
            ("family-growth-link-achievement-cards", "荣誉卡片"),
            ("family-growth-link-storyline-consent", "荣誉同意")
        ]

        for link in links {
            XCTAssertTrue(tapScrollableButton(identifier: link.identifier, attempts: 12), "Missing family growth link \(link.identifier)")
            XCTAssertTrue(app.navigationBars[link.title].waitForExistence(timeout: 3), "Missing family growth destination \(link.title)")
            navigateBack()
            XCTAssertTrue(
                app.buttons[link.identifier].waitForExistence(timeout: 3) || scrollToElement(identifier: link.identifier, attempts: 4),
                "Did not return to family growth list after \(link.identifier)"
            )
        }
    }

    func testRelativeFamilyParticipationCommentCanQueueForReview() {
        launchDefaultApp(initialTab: "family", expectedTitle: "家庭成长")
        XCTAssertTrue(tapScrollableButton(identifier: "family-growth-link-relative-participation"), "Missing relative participation link")
        XCTAssertTrue(app.navigationBars["亲友参与"].waitForExistence(timeout: 3), "Missing relative participation page")

        XCTAssertTrue(scrollToElement(identifier: "relative-family-compose-field", attempts: 14), "Missing relative comment field")
        let textField = app.textFields["relative-family-compose-field"].firstMatch
        let textView = app.textViews["relative-family-compose-field"].firstMatch
        let composeField = textField.exists ? textField : textView
        XCTAssertTrue(composeField.waitForExistence(timeout: 3), "Missing relative comment input")
        composeField.tap()
        composeField.typeText("继续加油")

        XCTAssertTrue(tapScrollableButton(identifier: "relative-family-compose-submit", attempts: 8), "Missing relative comment submit")
        XCTAssertTrue(scrollToElement(identifier: "relative-family-compose-feedback", attempts: 6), "Missing relative comment queue feedback")
    }

    /// 运行结算 / 证据链等审计视图已从孩子首页移除（产品决策：孩子端不展示技术区块），
    /// 家长端统一收进「更多功能与预览」，这里验证该路径仍可刷新。
    func testParentEvidenceTimelineRefreshCanRunFromAdvancedTools() {
        launchDefaultApp(initialTab: "parent", expectedTitle: "家长工作台")
        let pinField = app.secureTextFields["输入家长 PIN"].firstMatch
        XCTAssertTrue(pinField.waitForExistence(timeout: 3), "Missing parent PIN field")
        pinField.tap()
        pinField.typeText("1234")
        app.buttons["parent-mode-unlock"].tap()
        XCTAssertTrue(tapScrollableButton(identifier: "parent-mode-advanced-tools", attempts: 12), "Missing parent advanced tools entry")
        XCTAssertTrue(
            tapScrollableButton(identifier: "parent-mode-audit-tools-toggle", attempts: 8),
            "Missing system audit and testing group"
        )
        XCTAssertTrue(tapScrollableButton(identifier: "growth-pack-runtime-parent-refresh", attempts: 16), "Parent missing growth pack runtime refresh")
        XCTAssertTrue(tapScrollableButton(identifier: "growth-evidence-timeline-parent-refresh", attempts: 16), "Parent missing evidence timeline refresh")
        XCTAssertTrue(scrollToStaticText(containing: "成长积分状态", attempts: 8), "Parent missing evidence timeline growth point summary after refresh")
    }

    func testParentAICompanionOverviewShowsCloudBoundary() {
        launchDefaultApp(initialTab: "parent", expectedTitle: "家长工作台")
        let pinField = app.secureTextFields["输入家长 PIN"].firstMatch
        XCTAssertTrue(pinField.waitForExistence(timeout: 3), "Missing parent PIN field")
        pinField.tap()
        pinField.typeText("1234")
        app.buttons["parent-mode-unlock"].tap()

        XCTAssertTrue(tapScrollableButton(identifier: "parent-mode-advanced-tools", attempts: 12), "Missing parent advanced tools entry")
        XCTAssertTrue(tapScrollableButton(identifier: "parent-mode-ai-companion-overview", attempts: 12), "Missing AI companion overview entry")
        XCTAssertTrue(app.navigationBars["家长 AI 中心"].waitForExistence(timeout: 3), "Missing parent AI center page")
        XCTAssertTrue(app.buttons["parent-family-ai-generate-plan"].waitForExistence(timeout: 3), "Family AI center should be the default mode")
        let chatSegment = app.segmentedControls.buttons["聊天"].firstMatch
        XCTAssertTrue(chatSegment.waitForExistence(timeout: 3), "Missing AI chat mode")
        chatSegment.tap()
        XCTAssertTrue(scrollToElement(identifier: "parent-ai-coach-local-mode", attempts: 8), "Parent coach should show local guidance when AI is not configured")
        XCTAssertTrue(tapScrollableButton(identifier: "parent-ai-coach-open-ai-settings", attempts: 8), "Parent coach should link to AI provider settings")
        XCTAssertTrue(app.navigationBars["软件设置"].waitForExistence(timeout: 3), "Missing unified software settings from AI companion overview")
    }

    func testParentWebsiteSafetyCanAddCustomDomain() {
        launchDefaultApp(initialTab: "parent", expectedTitle: "家长工作台")
        let pinField = app.secureTextFields["输入家长 PIN"].firstMatch
        XCTAssertTrue(pinField.waitForExistence(timeout: 3), "Missing parent PIN field")
        pinField.tap()
        pinField.typeText("1234")
        app.buttons["parent-mode-unlock"].tap()

        XCTAssertTrue(tapScrollableButton(identifier: "parent-mode-advanced-tools", attempts: 12))
        XCTAssertTrue(tapScrollableButton(identifier: "parent-mode-website-safety", attempts: 8))
        XCTAssertTrue(app.navigationBars["网站安全中心"].waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToElement(identifier: "website-safety-automatic-filter", attempts: 6))

        let domainField = app.textFields["website-safety-domain-input"].firstMatch
        XCTAssertTrue(domainField.waitForExistence(timeout: 3))
        domainField.tap()
        domainField.typeText("example.org")
        app.buttons["website-safety-add-domain"].tap()
        XCTAssertTrue(app.staticTexts["example.org"].waitForExistence(timeout: 3))

        navigateBackToTitle("更多功能与预览")
        XCTAssertTrue(tapScrollableButton(identifier: "parent-mode-emergency-unlocks", attempts: 8))
        XCTAssertTrue(app.navigationBars["紧急解锁审批"].waitForExistence(timeout: 3))
    }

    func testEmergencyUnlockRequestCanReachParentApproval() {
        launchModuleAudit(role: "孩子", extraArguments: ["-OctoTeacherUITestSchoolEmergencyFlow"])
        selectRole("孩子")
        openModule(named: "成长积分兑换窗口")
        XCTAssertTrue(scrollToElement(identifier: "child-credit-wallet-balance"))
        XCTAssertTrue(
            tapScrollableButton(identifier: "child-credit-wallet-pathway-screenTime"),
            "Child could not open the Screen Time pathway"
        )
        XCTAssertTrue(
            tapScrollableButton(identifier: "emergency-unlock-request", attempts: 10),
            "Child could not submit an emergency unlock request"
        )
        XCTAssertTrue(
            scrollToElement(identifier: "emergency-unlock-requested", attempts: 10),
            "Emergency unlock request did not reach its synced waiting state"
        )

        navigateBackToModuleCenter()
        openTab(named: "家长")
        let pinField = app.secureTextFields["输入家长 PIN"].firstMatch
        XCTAssertTrue(pinField.waitForExistence(timeout: 3), "Missing parent PIN field")
        pinField.tap()
        pinField.typeText("1234")
        app.buttons["parent-mode-unlock"].tap()

        XCTAssertTrue(
            tapScrollableButton(identifier: "parent-mode-emergency-unlock-entry", attempts: 8),
            "Parent could not open emergency unlock approvals"
        )
        XCTAssertTrue(app.navigationBars["紧急解锁审批"].waitForExistence(timeout: 3))
        let approve = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "emergency-unlock-approve-")
        ).firstMatch
        let deny = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "emergency-unlock-deny-")
        ).firstMatch
        XCTAssertTrue(approve.waitForExistence(timeout: 3), "Emergency approval button is missing")
        XCTAssertTrue(deny.exists, "Emergency denial button is missing")
        approve.tap()

        navigateBackToTitle("家长工作台")
        openTab(named: "模块")
        selectRole("孩子")
        openModule(named: "成长积分兑换窗口")
        XCTAssertTrue(
            tapScrollableButton(identifier: "child-credit-wallet-pathway-screenTime"),
            "Child could not reopen the Screen Time pathway after approval"
        )
        XCTAssertTrue(
            scrollToElement(identifier: "emergency-unlock-start-approved", attempts: 10),
            "Approved emergency access did not return to the child"
        )
        XCTAssertFalse(
            app.buttons["reward-redemption-app-choice"].exists,
            "Simulator tests must not fabricate a real FamilyControls app token"
        )
    }

    func testParentScreenTimeEntryUsesGuardianControlPlane() {
        launchDefaultApp(initialTab: "parent", expectedTitle: "家长工作台")
        let pinField = app.secureTextFields["输入家长 PIN"].firstMatch
        XCTAssertTrue(pinField.waitForExistence(timeout: 3), "Missing parent PIN field")
        pinField.tap()
        pinField.typeText("1234")
        app.buttons["parent-mode-unlock"].tap()

        XCTAssertTrue(tapScrollableButton(identifier: "parent-mode-advanced-tools", attempts: 12), "Missing parent advanced tools entry")
        XCTAssertTrue(tapScrollableButton(identifier: "parent-mode-screen-time-debug", attempts: 4), "Missing Screen Time debug entry")
        XCTAssertTrue(app.navigationBars["屏幕时间管控"].waitForExistence(timeout: 3), "Missing Screen Time controls page")
        XCTAssertTrue(app.staticTexts["孩子设备"].waitForExistence(timeout: 3), "Screen Time should start from the selected child device")
        XCTAssertTrue(app.staticTexts["先启用多手机家庭"].waitForExistence(timeout: 3), "Unlinked guardian should be routed to family setup")
        XCTAssertFalse(app.buttons["立即锁定所选 App"].exists, "Guardian phone must never expose a local shield action")
    }

    func testParentSchoolModeCanOpenManualAndMailPlanning() {
        launchDefaultApp(initialTab: "parent", expectedTitle: "家长工作台")
        let pinField = app.secureTextFields["输入家长 PIN"].firstMatch
        XCTAssertTrue(pinField.waitForExistence(timeout: 3))
        pinField.tap()
        pinField.typeText("1234")
        app.buttons["parent-mode-unlock"].tap()

        XCTAssertTrue(tapScrollableButton(identifier: "parent-mode-advanced-tools", attempts: 12))
        XCTAssertTrue(tapScrollableButton(identifier: "parent-mode-school-mode", attempts: 4))
        XCTAssertTrue(app.navigationBars["学校模式与时间表"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.switches["school-mode-enabled"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["每周上学日"].exists)

        XCTAssertTrue(scrollToElement(identifier: "school-mode-mail-explorer", attempts: 8))
        XCTAssertTrue(tapScrollableButton(identifier: "school-mode-mail-explorer", attempts: 8))
        XCTAssertTrue(app.navigationBars["学校邮件洞察"].waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToElement(identifier: "school-mail-connect-gmail", attempts: 4))
        XCTAssertTrue(scrollToElement(identifier: "school-mail-batch-text", attempts: 8))
    }

    func testChildHomeQuickAccessAndTaskCardCanOpen() {
        let childHomeTitle = "孩子的成长计划"
        launchDefaultApp(initialTab: "child", expectedTitle: childHomeTitle)
        XCTAssertTrue(
            app.descendants(matching: .any)["child-home-next-step-action"].waitForExistence(timeout: 3),
            "Child home should show a clear first action hint"
        )
        let taskStatusBadge = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "child-home-task-status-"))
            .firstMatch
        XCTAssertTrue(
            taskStatusBadge.waitForExistence(timeout: 3),
            "Child home should show a visible task status badge"
        )
        XCTAssertTrue(tapScrollableButton(identifier: "child-home-next-step", attempts: 4), "Child missing top next-step action")
        XCTAssertTrue(app.navigationBars["任务详情"].waitForExistence(timeout: 3), "Missing task detail from child top action")
        XCTAssertTrue(
            scrollToElement(identifier: "task-detail-start-reading", attempts: 2),
            "Reading task detail should put Start Reading in the first screen"
        )
        XCTAssertTrue(
            scrollToElement(identifier: "task-detail-reading-help", attempts: 2),
            "Reading instructions and AI help should remain available through progressive disclosure"
        )
        navigateBackToTitle(childHomeTitle)

        XCTAssertTrue(tapScrollableButton(identifier: "child-home-quick-access-creditWallet"), "Child missing credit wallet quick access")
        XCTAssertTrue(app.navigationBars["我的奖励"].waitForExistence(timeout: 3), "Missing reward wallet destination")
        navigateBackToTitle(childHomeTitle)

        XCTAssertTrue(tapScrollableButton(identifier: "child-home-reward-redemption"), "Child missing reward redemption shortcut")
        let redemptionOpened = app.navigationBars["玩一会儿"].waitForExistence(timeout: 3)
        let walletOpened = app.navigationBars["我的奖励"].waitForExistence(timeout: 1)
        XCTAssertTrue(redemptionOpened || walletOpened, "Missing growth point redemption or earn-credit wallet destination")
        navigateBackToTitle(childHomeTitle)

        XCTAssertTrue(tapScrollableButton(identifier: "child-home-quick-access-basicHabitChore"), "Child missing basic habit quick access")
        XCTAssertTrue(app.navigationBars["个人独立性与家务打卡"].waitForExistence(timeout: 3), "Missing independence and chore destination")
        XCTAssertTrue(tapScrollableButton(identifier: "basic-habit-primary-action"), "Child missing basic habit primary action")
        XCTAssertTrue(app.navigationBars["任务详情"].waitForExistence(timeout: 3), "Missing basic habit task detail destination")
        navigateBackToTitle("个人独立性与家务打卡")
        XCTAssertTrue(tapScrollableButton(prefix: "basic-habit-item-", attempts: 12), "Child missing basic habit item action")
        XCTAssertTrue(app.navigationBars["任务详情"].waitForExistence(timeout: 3), "Missing basic habit item detail destination")
        navigateBackToTitle("个人独立性与家务打卡")
        navigateBackToTitle(childHomeTitle)

        let taskButton = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND NOT identifier BEGINSWITH %@ AND NOT identifier BEGINSWITH %@",
            "child-home-task-",
            "child-home-task-section-",
            "child-home-task-status-"
        )).firstMatch
        if !taskButton.waitForExistence(timeout: 1) {
            XCTAssertTrue(
                tapScrollableButton(
                    app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "学习")).firstMatch,
                    attempts: 12
                ),
                "Child missing the learning task category"
            )
        }
        XCTAssertTrue(tapScrollableButton(taskButton, attempts: 12), "Child missing today task card")
        XCTAssertTrue(app.navigationBars["任务详情"].waitForExistence(timeout: 3), "Missing task detail destination")
        let taskTitle = app.staticTexts["task-detail-title"].firstMatch
        XCTAssertTrue(taskTitle.waitForExistence(timeout: 3), "Task detail should expose the selected task title")
        let selectedTaskTitle = taskTitle.label
        let readingHelp = app.descendants(matching: .any)["task-detail-reading-help"].firstMatch
        if readingHelp.waitForExistence(timeout: 1) {
            XCTAssertTrue(
                scrollToElementBothWays(identifier: "task-detail-reading-help", upAttempts: 4, downAttempts: 4),
                "Reading task should expose its progressive help disclosure"
            )
        }
        XCTAssertTrue(
            tapScrollableButton(identifier: "task-detail-ask-ai-companion", attempts: 8)
                || tapScrollableButton(app.buttons["问 AI 小伙伴拆下一步"].firstMatch, attempts: 8),
            "Task detail should offer AI companion help"
        )
        XCTAssertTrue(app.navigationBars["AI 章鱼老师"].waitForExistence(timeout: 3), "Task detail should navigate to the child's companion")
        XCTAssertTrue(scrollToElement(identifier: "ai-companion-current-task", attempts: 6), "AI companion should keep the task context from task detail")
        let focusedTaskCard = app.descendants(matching: .any)["ai-companion-current-task"].firstMatch
        XCTAssertTrue(
            focusedTaskCard.label.contains(selectedTaskTitle),
            "AI companion should keep the same task selected from detail"
        )
    }

    func testChildHomeEmptyTaskStateCanOpenAICompanion() {
        let childHomeTitle = "孩子的成长计划"
        launchDefaultApp(
            initialTab: "child",
            expectedTitle: childHomeTitle,
            extraArguments: ["-OctoTeacherUITestEmptyChildTasks"]
        )

        XCTAssertTrue(
            app.descendants(matching: .any)["child-home-next-step-empty"].waitForExistence(timeout: 3),
            "Child home should explain the empty next-step state"
        )
        XCTAssertTrue(
            scrollToElement(identifier: "child-home-empty-tasks-ai", attempts: 4),
            "Child home should show a useful empty task section"
        )
        XCTAssertTrue(
            tapScrollableButton(identifier: "child-home-empty-tasks-ai", attempts: 4),
            "Child empty task state should offer AI companion guidance"
        )
        XCTAssertTrue(app.navigationBars["AI 章鱼老师"].waitForExistence(timeout: 3), "Missing AI companion from empty task state")
    }

    func testChildAICompanionLocalModeGivesFeedbackAfterMessage() {
        let childHomeTitle = "孩子的成长计划"
        launchDefaultApp(initialTab: "child", expectedTitle: childHomeTitle)

        XCTAssertTrue(tapScrollableButton(identifier: "child-home-ai-companion", attempts: 8), "Child missing AI companion entry")
        XCTAssertTrue(app.navigationBars["AI 章鱼老师"].waitForExistence(timeout: 3), "Missing AI companion page")
        XCTAssertTrue(
            app.descendants(matching: .any)["ai-companion-chat-window"].waitForExistence(timeout: 3),
            "AI companion should open with a chat window first"
        )
        XCTAssertTrue(scrollToElement(identifier: "ai-companion-starter-prompt-help", attempts: 3), "AI companion should explain how to start")
        XCTAssertTrue(scrollToElement(identifier: "ai-companion-quick-reply-0", attempts: 3), "AI companion should show starter prompt chips")
        // 默认 UI 测试种子必须保留至少一条 open/rejected 任务，孩子才有可直达的当前任务。
        XCTAssertTrue(scrollToElement(identifier: "ai-companion-current-task", attempts: 6), "AI companion should show the current actionable task")
        XCTAssertTrue(tapScrollableButton(identifier: "ai-companion-open-current-task", attempts: 4), "AI companion current task should open task detail")
        XCTAssertTrue(app.navigationBars["任务详情"].waitForExistence(timeout: 3), "AI companion current task should navigate to task detail")
        navigateBackToTitle("AI 章鱼老师")
        XCTAssertTrue(scrollToElement(identifier: "ai-companion-cloud-mode-local", attempts: 6), "AI companion should default to local mode in UI tests")

        XCTAssertTrue(
            scrollToElementBothWays(identifier: "ai-companion-free-text", upAttempts: 8, downAttempts: 8),
            "Missing AI companion free text field"
        )
        let textField = app.textFields["ai-companion-free-text"].firstMatch
        let textView = app.textViews["ai-companion-free-text"].firstMatch
        let composeField = textField.exists ? textField : textView
        XCTAssertTrue(composeField.waitForExistence(timeout: 3), "Missing AI companion compose field")
        composeField.tap()
        composeField.typeText("我作业不会")
        XCTAssertTrue(tapScrollableButton(identifier: "ai-companion-send-free-text", attempts: 4), "Missing AI companion send button")
        // 键盘若不收起，会挡住下半屏按钮并吃掉后续合成点击（模式切换/quick reply 会点到键盘上）。
        dismissKeyboardIfNeeded()

        var foundFeedback = scrollToElementBothWays(identifier: "ai-companion-local-feedback", upAttempts: 2, downAttempts: 5)
        XCTAssertTrue(foundFeedback, "AI companion should give local fallback feedback after a message")

        XCTAssertTrue(tapScrollableButton(identifier: "ai-companion-mode-homework", attempts: 8), "AI companion mode switch should reset local feedback before starter prompt")
        XCTAssertFalse(
            app.descendants(matching: .any)["ai-companion-local-feedback"].firstMatch.waitForExistence(timeout: 1),
            "AI companion feedback should clear after switching mode"
        )
        XCTAssertTrue(tapScrollableButton(identifier: "ai-companion-quick-reply-0", attempts: 8), "AI companion starter prompt should be tappable")
        foundFeedback = scrollToElementBothWays(identifier: "ai-companion-local-feedback", upAttempts: 4, downAttempts: 5)
        XCTAssertTrue(foundFeedback, "AI companion starter prompt should also give local fallback feedback")
    }

    /// 家庭真实模式的核心闭环：家长设置 PIN → 布置新任务 → 孩子提交 → 家长批准。
    /// 不带 UI 测试参数时 App 是 4 Tab（孩子/家长/家庭/更多），这里用 UI 测试模式
    /// 验证等价路径：布置任务表单可用、新任务出现在孩子端。
    func testParentCanComposeNewTaskAndChildSeesIt() {
        launchDefaultApp(initialTab: "parent", expectedTitle: "家长工作台")
        let pinField = app.secureTextFields["输入家长 PIN"].firstMatch
        XCTAssertTrue(pinField.waitForExistence(timeout: 3), "Missing parent PIN field")
        pinField.tap()
        pinField.typeText("1234")
        app.buttons["parent-mode-unlock"].tap()

        XCTAssertTrue(
            tapScrollableButton(identifier: "parent-mode-today-compose-task", attempts: 10),
            "Missing primary compose task button"
        )
        let titleField = app.textFields["task-composer-title"].firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 3), "Missing task composer title field")
        titleField.tap()
        titleField.typeText("给花浇水")
        XCTAssertTrue(
            scrollToElement(identifier: "task-composer-quality-guidance", attempts: 6),
            "Task composer should show local quality guidance before saving"
        )
        XCTAssertTrue(
            scrollToStaticText(containing: "再补一句怎么做", attempts: 4),
            "Task composer should nudge parents to write actionable instructions"
        )
        XCTAssertTrue(
            tapScrollableButton(identifier: "task-composer-apply-starter-template", attempts: 6),
            "Task composer should offer a starter template when parents do not know how to phrase a task"
        )
        XCTAssertTrue(
            scrollToStaticText(containing: "说明已经写到孩子能照着开始", attempts: 4),
            "Starter template should fill actionable instructions"
        )
        XCTAssertTrue(
            scrollToStaticText(containing: "孩子首页会看到：整理书桌", attempts: 4),
            "Starter template should update the child-facing preview"
        )
        XCTAssertTrue(
            scrollToElement(identifier: "task-composer-child-preview", attempts: 6),
            "Missing child-facing preview before saving a parent task"
        )
        XCTAssertTrue(tapScrollableButton(identifier: "task-composer-save", attempts: 6), "Missing task composer save button")
        XCTAssertTrue(
            app.navigationBars["家长工作台"].waitForExistence(timeout: 10),
            "Saving a new task should return to the parent workbench before continuing"
        )

        // 保存后先从任务管理顶部的稳定入口进入编辑，再验证列表与孩子端同步。
        var openedEditor = tapScrollableButton(identifier: "parent-mode-edit-current-task", attempts: 12)
        if !openedEditor,
           tapScrollableButton(
               app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "家务")).firstMatch,
               attempts: 12
           ) {
            openedEditor = tapScrollableButton(identifier: "parent-mode-edit-latest-task", attempts: 8)
                || tapScrollableElement(identifier: "parent-mode-latest-task-row", attempts: 8)
        }
        XCTAssertTrue(openedEditor, "New task should expose a visible edit path in daily focus or its expanded task category")
        let editingTitleField = app.textFields["task-composer-title"].firstMatch
        XCTAssertTrue(editingTitleField.waitForExistence(timeout: 5), "Visible edit button should open the task editor")
        XCTAssertTrue(
            app.navigationBars["编辑任务"].exists || app.staticTexts["编辑任务"].exists,
            "Task editor should identify itself as edit mode"
        )
        XCTAssertEqual(editingTitleField.value as? String, "整理书桌", "Daily focus edit button should open the newest task")
        XCTAssertTrue(tapScrollableButton(identifier: "task-composer-save", attempts: 6), "Missing save button while editing a parent task")
        XCTAssertTrue(scrollToStaticText(containing: "整理书桌", attempts: 8), "Edited task missing from parent task list")

        // 切到孩子 Tab，新任务在今日任务里可见。
        openTab(named: "孩子")
        XCTAssertTrue(
            tapScrollableButton(
                app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "家务")).firstMatch,
                attempts: 10
            ),
            "New household task should make its child category available"
        )
        XCTAssertTrue(scrollToStaticText(containing: "整理书桌", attempts: 10), "New task missing from child home")
    }

    func testParentTrainingMarketplaceCanPreviewAndInstallPack() {
        launchDefaultApp(initialTab: "parent", expectedTitle: "家长工作台")
        let pinField = app.secureTextFields["输入家长 PIN"].firstMatch
        XCTAssertTrue(pinField.waitForExistence(timeout: 3), "Missing parent PIN field")
        pinField.tap()
        pinField.typeText("1234")
        app.buttons["parent-mode-unlock"].tap()

        XCTAssertTrue(
            tapScrollableButton(identifier: "parent-mode-training-marketplace", attempts: 8),
            "Missing parent training marketplace quick action"
        )
        XCTAssertTrue(app.navigationBars["培训市场"].waitForExistence(timeout: 4))
        XCTAssertTrue(
            tapScrollableButton(identifier: "training-marketplace-listing-independence-week", attempts: 8),
            "Missing independence pack listing"
        )
        XCTAssertTrue(app.navigationBars["我的事情我来做"].waitForExistence(timeout: 4))
        XCTAssertTrue(
            tapScrollableButton(identifier: "training-marketplace-install", attempts: 12),
            "Missing local install action"
        )
        XCTAssertTrue(app.buttons["确认安装"].waitForExistence(timeout: 3))
        app.buttons["确认安装"].tap()
        XCTAssertTrue(app.buttons["知道了"].waitForExistence(timeout: 3))
        app.buttons["知道了"].tap()
        XCTAssertTrue(
            scrollToElement(identifier: "training-marketplace-installed", attempts: 8),
            "Installed receipt should be visible after confirmation"
        )
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "training-marketplace-installed"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFamilyStorylineDiaryConsentAndSafetyLinksCanRoundTrip() {
        let matrix: [(role: String, visibleItems: [String], hiddenItems: [String], consentNodes: [String], findings: [String])] = [
            (
                "孩子",
                [
                    "growth-diary-vlog-item-diary-savedPrivate",
                    "growth-diary-vlog-item-vlogDraft-savedPrivate",
                    "growth-diary-vlog-item-storyline-familyVisible"
                ],
                [],
                [
                    "family-storyline-consent-node-privateFamily-blocked",
                    "family-storyline-consent-node-relativeVisible-needsGuardianConsent"
                ],
                ["family-storyline-consent-finding-childFriendlyCopyApplied"]
            ),
            (
                "家长",
                [
                    "growth-diary-vlog-item-diary-withdrawn",
                    "growth-diary-vlog-item-diary-blocked",
                    "growth-diary-vlog-item-encouragement-pendingGuardianReview"
                ],
                [],
                [
                    "family-storyline-consent-node-privateFamily-blocked",
                    "family-storyline-consent-node-relativeVisible-needsGuardianConsent"
                ],
                [
                    "family-storyline-consent-finding-guardianConsentRequired",
                    "family-storyline-consent-finding-withdrawalPropagated"
                ]
            ),
            (
                "亲友",
                ["growth-diary-vlog-item-encouragement-relativeVisible"],
                [
                    "growth-diary-vlog-item-diary-savedPrivate",
                    "growth-diary-vlog-item-vlogDraft-savedPrivate"
                ],
                ["family-storyline-consent-node-relativeVisible-ready"],
                ["family-storyline-consent-finding-relativeBoundaryApplied"]
            )
        ]

        for entry in matrix {
            launchModuleAudit(role: entry.role)
            openModule(named: "成长故事线")
            XCTAssertTrue(app.navigationBars["成长日记"].waitForExistence(timeout: 3), "Missing growth diary for \(entry.role)")

            for item in entry.visibleItems {
                XCTAssertTrue(scrollToElement(identifier: item), "\(entry.role) missing storyline item \(item)")
            }

            app.swipeDown()
            app.swipeDown()
            for item in entry.hiddenItems {
                XCTAssertFalse(app.descendants(matching: .any)[item].exists, "\(entry.role) leaked hidden storyline item \(item)")
            }

            XCTAssertTrue(tapScrollableButton(identifier: "growth-diary-vlog-link-consent-boundary"), "\(entry.role) missing consent boundary link")
            XCTAssertTrue(app.navigationBars["荣誉同意"].waitForExistence(timeout: 3), "\(entry.role) missing consent destination")
            XCTAssertTrue(tapScrollableButton(identifier: "family-storyline-consent-policy-link"), "\(entry.role) missing consent policy link")
            XCTAssertTrue(app.navigationBars["同意策略"].waitForExistence(timeout: 3), "\(entry.role) missing policy destination")
            navigateBackToTitle("荣誉同意")

            XCTAssertTrue(scrollToElement(identifier: "family-storyline-release-gate-blocked"), "\(entry.role) missing release gate")

            for node in entry.consentNodes {
                XCTAssertTrue(scrollToElement(identifier: node, attempts: 16), "\(entry.role) missing consent node \(node)")
            }
            for finding in entry.findings {
                XCTAssertTrue(scrollToElement(identifier: finding, attempts: 16), "\(entry.role) missing consent finding \(finding)")
            }
            XCTAssertTrue(scrollToElement(identifier: "family-storyline-boundary-network-ai", attempts: 16), "\(entry.role) missing no-side-effect boundary")

            navigateBackToTitle("成长日记")

            XCTAssertTrue(tapScrollableButton(identifier: "growth-diary-vlog-link-emotional-safety"), "\(entry.role) missing emotional safety link")
            XCTAssertTrue(app.navigationBars["情绪安全中心"].waitForExistence(timeout: 3), "\(entry.role) missing emotional safety destination")

            navigateBackToModuleCenter()
        }
    }

    private func launchModuleAudit(role: String, extraArguments: [String] = []) {
        if app != nil {
            app.terminate()
        }
        app = XCUIApplication()
        app.launchArguments = [
            "-OctoTeacherUITestModuleAudit",
            "-OctoTeacherUITestAllRoles",
            "-OctoTeacherUITestModuleRole",
            roleKey(for: role)
        ] + extraArguments
        app.launch()
        currentRole = role
        XCTAssertTrue(app.navigationBars["模块能力中心"].waitForExistence(timeout: 8))
    }

    private func assertVisibleModulesCanOpen(role: String, modules: [String]) {
        launchModuleAudit(role: role)
        for module in modules {
            openModule(named: module)
            XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 3), "\(role) / \(module) did not open a destination")
            navigateBackToModuleCenter()
        }
    }

    private func launchDefaultApp(
        initialTab: String? = nil,
        expectedTitle: String = "章鱼老师",
        extraArguments: [String] = []
    ) {
        if app != nil {
            app.terminate()
        }
        app = XCUIApplication()
        var launchArguments = ["-OctoTeacherUITest"]
        launchArguments.append(contentsOf: extraArguments)
        if let initialTab {
            launchArguments.append(contentsOf: [
                "-OctoTeacherUITestInitialTab",
                initialTab
            ])
        }
        app.launchArguments = launchArguments
        app.launch()
        currentRole = "孩子"
        XCTAssertTrue(app.navigationBars[expectedTitle].waitForExistence(timeout: 8))
    }

    private func openTab(named title: String) {
        dismissKeyboardIfNeeded()
        let tab = app.tabBars.buttons[title].firstMatch
        if tab.waitForExistence(timeout: 3) {
            if tab.isHittable {
                tab.tap()
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: tabXPosition(for: title), dy: 0.96)).tap()
            }
            return
        }

        let moreTab = firstExistingTabBarButton(identifiers: ["More", "更多"])
        XCTAssertTrue(moreTab.waitForExistence(timeout: 3), "Missing tab \(title) and More overflow")
        moreTab.tap()

        let overflowTab = app.buttons[title].firstMatch
        XCTAssertTrue(overflowTab.waitForExistence(timeout: 3), "Missing overflow tab \(title)")
        overflowTab.tap()
    }

    private func firstExistingTabBarButton(identifiers: [String]) -> XCUIElement {
        for identifier in identifiers {
            let button = app.tabBars.buttons[identifier].firstMatch
            if button.exists {
                return button
            }
        }
        return app.tabBars.buttons[identifiers[0]].firstMatch
    }

    private func selectRole(_ role: String) {
        if currentRole == role {
            return
        }

        resetSearchIfNeeded()
        app.swipeDown()
        app.swipeDown()

        let roleButton = firstExistingButton(
            identifiers: [
                "module-center-role-\(roleKey(for: role))",
                role
            ]
        )
        XCTAssertTrue(roleButton.waitForExistence(timeout: 3), "Missing role \(role)")
        roleButton.tap()
        currentRole = role
    }

    private func openModule(named title: String) {
        resetSearchIfNeeded()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3), "Missing module center search field")
        search.tap()
        search.typeText(title)

        let module = app.buttons["module-center-module-\(moduleKey(for: title))"].firstMatch
        XCTAssertTrue(module.waitForExistence(timeout: 3), "Missing module \(title)")
        module.tap()
    }

    private func resetSearchIfNeeded() {
        if app.navigationBars["模块能力中心"].exists {
            let search = app.searchFields.firstMatch
            if search.exists {
                search.tap()
                if app.buttons["Clear text"].exists {
                    app.buttons["Clear text"].tap()
                } else if app.buttons["清除文本"].exists {
                    app.buttons["清除文本"].tap()
                }
                app.keyboards.buttons["Search"].tapIfExists()
                app.keyboards.buttons["Done"].tapIfExists()
                app.keyboards.buttons["Return"].tapIfExists()
                app.buttons["Cancel"].tapIfExists()
                app.buttons["取消"].tapIfExists()
            }
        }
    }

    private func dismissKeyboardIfNeeded() {
        app.keyboards.buttons["Done"].tapIfExists()
        app.keyboards.buttons["Search"].tapIfExists()
        app.keyboards.buttons["Return"].tapIfExists()
        app.buttons["Cancel"].tapIfExists()
        app.buttons["取消"].tapIfExists()
        if app.keyboards.firstMatch.exists {
            app.swipeDown()
        }
    }

    private func tabXPosition(for title: String) -> CGFloat {
        switch title {
        case "首页": return 1.0 / 12.0
        case "模块": return 3.0 / 12.0
        case "孩子": return 5.0 / 12.0
        case "家长": return 7.0 / 12.0
        case "学校": return 9.0 / 12.0
        case "家庭": return 11.0 / 12.0
        default: return 0.5
        }
    }

    private func roleKey(for role: String) -> String {
        switch role {
        case "孩子": return "child"
        case "家长": return "guardian"
        case "亲友": return "relative"
        case "老师": return "teacher"
        case "运营": return "operations"
        default: return role
        }
    }

    private func moduleKey(for title: String) -> String {
        switch title {
        case "今日基础任务": return "today_tasks"
        case "成长包运行": return "growth_pack_runtime"
        case "成长包执行中心": return "growth_pack_execution_hub"
        case "成长包安装权益": return "growth_pack_market"
        case "学校作业": return "school_homework"
        case "AI 引导学习": return "ai_homework_guide"
        case "家校联合审批": return "school_joint_approval"
        case "通知摘要同意": return "notification_digest_consent"
        case "成长故事线": return "family_storyline"
        case "荣誉墙与球星卡": return "honor_wall"
        case "成长积分账本": return "credit_ledger"
        case "成长积分兑换窗口": return "reward_window"
        case "娱乐 App 策略预览": return "app_selection_policy"
        case "奖励库存履约": return "reward_store_fulfillment"
        case "成长报告预览": return "reports_preview"
        case "章鱼老师 入门": return "onboarding_guide"
        case "离线同步复核台": return "offline_sync_review"
        case "家长模块配置草稿": return "module_configuration_draft"
        case "移动端发布质量门": return "release_gate"
        case "情绪安全中心": return "family_social_feedback_emotional_safety"
        default: return title
        }
    }

    private func firstExistingButton(identifiers: [String]) -> XCUIElement {
        for identifier in identifiers {
            let button = app.buttons[identifier].firstMatch
            if button.exists {
                return button
            }
        }
        return app.buttons[identifiers[0]].firstMatch
    }

    private func navigateBackToModuleCenter() {
        for _ in 0..<4 where !app.navigationBars["模块能力中心"].exists {
            navigateBack()
        }
        XCTAssertTrue(app.navigationBars["模块能力中心"].waitForExistence(timeout: 3))
    }

    private func navigateBack() {
        let navBars = app.navigationBars
        if navBars.buttons["模块能力中心"].exists {
            navBars.buttons["模块能力中心"].tap()
            return
        }
        for title in ["家庭成长", "OctoTeacher", "孩子", "家长", "学校"] {
            if navBars.buttons[title].exists {
                navBars.buttons[title].tap()
                return
            }
        }
        let firstBack = navBars.buttons.element(boundBy: 0)
        if firstBack.exists {
            firstBack.tap()
        }
    }

    private func tapIfExists(_ label: String) {
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 3), "Missing button \(label)")
        button.tap()
    }

    private func scrollToButton(_ label: String, attempts: Int = 6) -> Bool {
        let button = app.buttons[label].firstMatch
        if button.waitForExistence(timeout: 1) {
            return true
        }
        for _ in 0..<attempts {
            app.swipeUp()
            if button.waitForExistence(timeout: 1) {
                return true
            }
        }
        return false
    }

    private func tapScrollableButton(identifier: String, attempts: Int = 8) -> Bool {
        tapScrollableButton(app.buttons[identifier].firstMatch, attempts: attempts)
    }

    private func tapScrollableButton(prefix: String, attempts: Int = 8) -> Bool {
        tapScrollableButton(
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch,
            attempts: attempts
        )
    }

    private func tapScrollableElement(identifier: String, attempts: Int = 8) -> Bool {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        if element.waitForExistence(timeout: 1), element.isHittable {
            element.tap()
            return true
        }
        for _ in 0..<attempts {
            app.swipeUp()
            if element.waitForExistence(timeout: 1), element.isHittable {
                element.tap()
                return true
            }
        }
        for _ in 0..<attempts {
            app.swipeDown()
            if element.waitForExistence(timeout: 1), element.isHittable {
                element.tap()
                return true
            }
        }
        return false
    }

    /// 先向下滚动查找；找不到再向上滚回查找（List 惰性渲染，目标可能在当前视口上方）。
    private func tapScrollableButton(_ button: XCUIElement, attempts: Int) -> Bool {
        if button.waitForExistence(timeout: 1), button.isHittable {
            button.tap()
            return true
        }
        for _ in 0..<attempts {
            app.swipeUp()
            if button.waitForExistence(timeout: 1), button.isHittable {
                button.tap()
                return true
            }
        }
        for _ in 0..<attempts {
            app.swipeDown()
            if button.waitForExistence(timeout: 1), button.isHittable {
                button.tap()
                return true
            }
        }
        return false
    }

    private func scrollToElement(identifier: String, attempts: Int = 8) -> Bool {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        if element.waitForExistence(timeout: 1) {
            return true
        }
        for _ in 0..<attempts {
            app.swipeUp()
            if element.waitForExistence(timeout: 1) {
                return true
            }
        }
        return false
    }

    /// List 惰性渲染下目标可能在视口上方或下方：先向下滚动查找，冲过头再向上滚回查找。
    private func scrollToElementBothWays(identifier: String, upAttempts: Int = 4, downAttempts: Int = 5) -> Bool {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        if element.waitForExistence(timeout: 1) {
            return true
        }
        for _ in 0..<upAttempts {
            app.swipeUp()
            if element.waitForExistence(timeout: 1) {
                return true
            }
        }
        for _ in 0..<downAttempts {
            app.swipeDown()
            if element.waitForExistence(timeout: 1) {
                return true
            }
        }
        return false
    }

    private func navigateBackToTitle(_ title: String) {
        for _ in 0..<3 where !app.navigationBars[title].exists {
            navigateBack()
        }
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3))
    }

    private func scrollToStaticText(containing text: String, direction: ScrollDirection = .up, attempts: Int = 6) -> Bool {
        let element = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        if element.waitForExistence(timeout: 1) {
            return true
        }
        for _ in 0..<attempts {
            switch direction {
            case .up:
                app.swipeUp()
            case .down:
                app.swipeDown()
            }
            if element.waitForExistence(timeout: 1) {
                return true
            }
        }
        return false
    }
}

private enum ScrollDirection {
    case up
    case down
}

private extension XCUIElement {
    func tapIfExists() {
        if exists && isEnabled && isHittable {
            tap()
        }
    }
}
