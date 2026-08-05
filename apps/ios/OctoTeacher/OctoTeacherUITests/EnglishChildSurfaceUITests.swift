import XCTest

/// 英文孩子 surface 的第二轮回归：
/// 1) 英文幼儿首页可见卡片全英文，小喇叭 accessibilityLabel 为 "Read aloud"；
/// 2) 英文奖励（换屏幕）与愿望（零花钱）关键入口页无中文标题/关键文案。
/// 全部使用 UI 测试种子数据（-OctoTeacherUITest 内存 store），不依赖真机数据。
@MainActor
final class EnglishChildSurfaceUITests: XCTestCase {

    private func launchEnglishPreReader() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-OctoTeacherUITest",
            "-OctoTeacherUITestEnglishPreReaderChild",
            "-OctoTeacherUITestInitialTab", "child"
        ]
        app.launch()
        return app
    }

    func testEnglishPreReaderHomeCardsAndSpeakerLabelsHaveNoChinese() {
        let app = launchEnglishPreReader()

        // AI 入口留在首屏；低频入口默认折叠，展开后仍必须完整可达且全英文。
        XCTAssertTrue(app.staticTexts["AI Octo Teacher"].waitForExistence(timeout: 10), "英文幼儿首页应显示 AI Octo Teacher 卡片")
        XCTAssertTrue(scrollToIdentifier(app: app, identifier: "pre-reader-tools-toggle"))
        let toolsToggle = app.buttons["pre-reader-tools-toggle"].firstMatch
        XCTAssertEqual(toolsToggle.value as? String, "collapsed")
        toolsToggle.tap()
        XCTAssertEqual(toolsToggle.value as? String, "expanded")

        for entry in [
            ("pre-reader-screen-button", "Play Time"),
            ("pre-reader-wish-button", "My Wish"),
            ("pre-reader-creative-button", "Create"),
            ("pre-reader-badge-button", "Badges")
        ] {
            XCTAssertTrue(scrollToIdentifier(app: app, identifier: entry.0), "英文幼儿首页应显示 \(entry.1) 卡片")
            XCTAssertTrue(app.staticTexts[entry.1].exists, "英文幼儿首页应显示 \(entry.1) 标题")
        }

        // 对应中文卡片标题与常见中文壳文案不允许出现。
        for chinese in ["愿望", "换屏幕", "创作", "徽章", "小伙伴", "今日任务", "完成回看"] {
            XCTAssertFalse(app.staticTexts[chinese].exists, "英文幼儿首页出现中文：\(chinese)")
        }

        // 小喇叭：幼儿模式自动开启朗读，accessibilityLabel 必须是 Read aloud。
        XCTAssertTrue(app.buttons["Read aloud"].firstMatch.exists, "英文幼儿首页小喇叭标签应为 Read aloud")
        XCTAssertFalse(app.buttons["读给我听"].exists, "英文幼儿首页不允许出现中文小喇叭标签")
    }

    private func scrollTo(app: XCUIApplication, staticText: String) -> Bool {
        let element = app.staticTexts[staticText].firstMatch
        for _ in 0..<8 {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    func testEnglishWishAndRewardEntriesHaveNoChinese() {
        let app = launchEnglishPreReader()

        XCTAssertTrue(scrollToIdentifier(app: app, identifier: "pre-reader-tools-toggle"))
        let toolsToggle = app.buttons["pre-reader-tools-toggle"].firstMatch
        XCTAssertEqual(toolsToggle.value as? String, "collapsed")
        toolsToggle.tap()
        XCTAssertEqual(toolsToggle.value as? String, "expanded")

        // 愿望入口 → 零花钱和愿望页。
        XCTAssertTrue(scrollToIdentifier(app: app, identifier: "pre-reader-wish-button"))
        app.buttons["pre-reader-wish-button"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Money & Wishes"].waitForExistence(timeout: 8), "英文愿望入口应显示英文标题")
        XCTAssertFalse(app.navigationBars["零花钱和愿望"].exists)
        XCTAssertFalse(app.staticTexts["等大人定价"].exists, "英文愿望页不允许出现中文状态")
        app.navigationBars.buttons.firstMatch.tap()

        // 换屏幕入口 → 成长积分兑换或成长积分钱包（两个目的地都必须是英文标题）。
        XCTAssertTrue(scrollToIdentifier(app: app, identifier: "pre-reader-screen-button"))
        app.buttons["pre-reader-screen-button"].firstMatch.tap()
        let exchangeTitle = app.navigationBars["Play Time"]
        let walletTitle = app.navigationBars["My Rewards"]
        let earnTitle = app.navigationBars["Earn Growth Points"]
        let anyEnglishRewardTitle = exchangeTitle.waitForExistence(timeout: 8)
            || walletTitle.exists || earnTitle.exists
        XCTAssertTrue(anyEnglishRewardTitle, "英文换屏幕入口应显示英文标题")
        XCTAssertFalse(app.navigationBars["成长积分兑换"].exists)
        XCTAssertFalse(app.navigationBars["成长积分钱包"].exists)
        XCTAssertFalse(app.navigationBars["去赚成长积分"].exists)
    }

    func testEnglishPreReaderTaskDetailHasOneClearProofAndSubmitPath() {
        let app = launchEnglishPreReader()

        let taskCard = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND identifier != %@",
                "pre-reader-task-",
                "pre-reader-task-list-toggle"
            ))
            .firstMatch
        XCTAssertTrue(taskCard.waitForExistence(timeout: 10), "英文幼儿首页应有可执行任务卡片")
        taskCard.tap()

        XCTAssertTrue(app.navigationBars["Task Details"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            scrollToIdentifier(
                app: app,
                identifier: "task-detail-proof-guide",
                requiresHittable: false
            )
        )
        XCTAssertTrue(scrollToIdentifier(app: app, identifier: "task-detail-submit-for-approval"))
        XCTAssertTrue(app.buttons["task-detail-submit-for-approval"].exists)
        XCTAssertTrue(scrollToIdentifier(app: app, identifier: "task-detail-options"))
        XCTAssertFalse(app.staticTexts["提交给大人确认"].exists)
        XCTAssertFalse(app.staticTexts["任务选项"].exists)
    }

    func testPreReaderHomeCanScrollToBottomBackToTopAndDownAgain() {
        let app = launchEnglishPreReader()
        let top = app.descendants(matching: .any)["pre-reader-home-top"].firstMatch
        let bottom = app.descendants(matching: .any)["pre-reader-tools-toggle"].firstMatch

        XCTAssertTrue(top.waitForExistence(timeout: 10), "Pre-reader home should start at its header")
        XCTAssertTrue(scrollToIdentifier(app: app, identifier: "pre-reader-tools-toggle"), "Pre-reader home should reach its bottom actions")

        for _ in 0..<10 where !top.isHittable {
            app.swipeDown()
        }
        XCTAssertTrue(top.exists && top.isHittable, "Pre-reader home should scroll back to its visible header")

        for _ in 0..<10 where !bottom.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(bottom.exists && bottom.isHittable, "Pre-reader home should visibly reach its bottom again")
    }

    private func scrollToIdentifier(
        app: XCUIApplication,
        identifier: String,
        requiresHittable: Bool = true
    ) -> Bool {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        for _ in 0..<10 {
            if element.exists && (!requiresHittable || element.isHittable) { return true }
            app.swipeUp()
        }
        return element.exists && (!requiresHittable || element.isHittable)
    }
}
