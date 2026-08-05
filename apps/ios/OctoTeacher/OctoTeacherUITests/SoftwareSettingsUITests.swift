import XCTest

@MainActor
final class SoftwareSettingsUITests: XCTestCase {
    /// 家长中文 + 孩子英文：
    /// 1) 家长 surface 上整条 Tab bar 全中文（不允许一半英文一半中文）；
    /// 2) 切到孩子 Tab 后整条 Tab bar 全英文，英文孩子首页关键动态文案无中文；
    /// 3) 家长切英文后设置页立即用英文完整显示。
    func testParentAndChildInterfacesCanUseDifferentLanguages() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-OctoTeacherUITest",
            "-OctoTeacherUITestFamilyTabs",
            "-OctoTeacherUITestEnglishChildName",
            "-OctoTeacherUITestInitialTab", "more"
        ]
        app.launch()

        XCTAssertTrue(scrollTo(app: app, identifier: "more-tab-software-settings"))
        app.buttons["more-tab-software-settings"].tap()

        let pin = app.secureTextFields["输入家长 PIN"].firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 8))
        pin.tap()
        pin.typeText("1234")
        app.buttons["parent-mode-unlock"].tap()

        // 家长中文时，设置页标题与分区标题必须是中文，不允许被 en.lproj 覆盖。
        XCTAssertTrue(app.navigationBars["软件设置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["地区"].exists, "家长中文设置页地区分区标题必须是中文")
        XCTAssertTrue(app.staticTexts["语言"].exists, "家长中文设置页语言分区标题必须是中文")
        XCTAssertFalse(app.staticTexts["Region"].exists, "家长中文设置页不允许出现英文分区标题")
        XCTAssertFalse(app.staticTexts["Language"].exists, "家长中文设置页不允许出现英文分区标题")

        // 把当前孩子界面改成英文。
        let childLanguage = app.buttons["software-settings-child-language"].firstMatch
        XCTAssertTrue(childLanguage.waitForExistence(timeout: 5))
        childLanguage.tap()
        let childEnglish = app.buttons["English"]
        XCTAssertTrue(childEnglish.waitForExistence(timeout: 3))
        childEnglish.tap()

        // 仍在家长 surface：Tab bar 必须整条保持中文（all-or-nothing）。
        XCTAssertTrue(app.tabBars.buttons["家长"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["孩子"].exists, "家长 surface 上孩子 Tab 标题仍是中文")
        XCTAssertFalse(app.tabBars.buttons["Child"].exists, "家长 surface 上不允许混英文 Tab 标题")

        // 切到孩子 Tab：整条 Tab bar 全英文。
        app.tabBars.buttons["孩子"].tap()
        XCTAssertTrue(app.tabBars.buttons["Child"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Parent"].exists, "孩子 surface 上家长 Tab 也必须是英文")
        XCTAssertFalse(app.tabBars.buttons["家长"].exists, "孩子 surface 上不允许混中文 Tab 标题")

        // 英文孩子首页关键动态文案无中文：分区标题与种子任务标题都应是英文。
        XCTAssertFalse(app.staticTexts["今日任务"].exists, "英文孩子首页不允许出现中文分区标题")
        XCTAssertFalse(app.staticTexts["我的成长积分"].exists, "英文孩子首页不允许出现中文分区标题")
        XCTAssertFalse(app.staticTexts["今日成长计划"].exists, "英文孩子首页不允许出现中文分区标题")
        XCTAssertFalse(app.staticTexts["阅读 15 分钟"].exists, "内置中文任务必须映射为英文")
        XCTAssertFalse(app.staticTexts["整理书桌"].exists, "内置中文任务必须映射为英文")

        // 回到更多 surface（此时显示英文标题 More），设置页仍在该 Tab 的导航栈里。
        app.tabBars.buttons["More"].tap()
        XCTAssertTrue(app.tabBars.buttons["更多"].waitForExistence(timeout: 5), "回到更多 surface 后 Tab bar 恢复中文")

        // 家长界面切英文：设置页立即用英文完整显示，Tab bar 全英文。
        let parentLanguage = app.buttons["software-settings-parent-language"].firstMatch
        XCTAssertTrue(parentLanguage.waitForExistence(timeout: 5))
        parentLanguage.tap()
        let parentEnglish = app.buttons["English"]
        XCTAssertTrue(parentEnglish.waitForExistence(timeout: 3))
        parentEnglish.tap()
        XCTAssertTrue(app.navigationBars["Software Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Region"].exists, "家长英文设置页应显示英文分区标题")
        XCTAssertFalse(app.staticTexts["地区"].exists, "家长英文设置页不允许残留中文分区标题")
        XCTAssertTrue(app.tabBars.buttons["Parent"].exists)
        XCTAssertFalse(app.tabBars.buttons["家长"].exists)
        assertNoVisibleCJK(in: app, context: "English parent settings")
    }

    /// 独立巡检夹具确保英文家庭启动后，父母与孩子首页的可见 UI 都不残留中文。
    func testEnglishFamilyPrimarySurfacesContainNoVisibleChinese() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-OctoTeacherUITest",
            "-OctoTeacherUITestEnglishFamily",
            "-OctoTeacherUITestFamilyTabs",
            "-OctoTeacherUITestInitialTab", "child"
        ]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Child"].waitForExistence(timeout: 8))
        assertNoVisibleCJK(in: app, context: "English child home")

        app.tabBars.buttons["Parent"].tap()
        let pin = app.secureTextFields["Enter Parent PIN"].firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 8))
        pin.tap()
        pin.typeText("1234")
        app.buttons["parent-mode-unlock"].tap()
        XCTAssertTrue(app.navigationBars["Parent Workspace"].waitForExistence(timeout: 8))
        assertNoVisibleCJK(in: app, context: "English parent workspace")

        XCTAssertTrue(scrollTo(app: app, identifier: "parent-mode-quick-task-group"))
        XCTAssertEqual(app.buttons["parent-mode-compose-task"].label, "Assign Today's First Task")
        XCTAssertEqual(app.buttons["parent-mode-quick-task-presets"].label, "Quick Start by Scenario")
        assertNoVisibleCJK(in: app, context: "English quick task planning")

        XCTAssertTrue(tap(app: app, identifier: "parent-mode-task-planning-group"))
        XCTAssertTrue(scrollTo(app: app, identifier: "parent-mode-ai-reading"))
        XCTAssertEqual(app.buttons["parent-mode-ai-reading"].label, "Plan Reading with AI")
        XCTAssertEqual(app.buttons["parent-mode-ai-video"].label, "Assign Video Learning")
        assertNoVisibleCJK(in: app, context: "English AI task planning")

        XCTAssertTrue(tap(app: app, identifier: "parent-mode-family-management-group"))
        XCTAssertTrue(scrollTo(app: app, identifier: "parent-mode-children-manager"))
        XCTAssertEqual(app.buttons["parent-mode-children-manager"].label, "Children")
        XCTAssertEqual(app.buttons["parent-mode-pocket-money"].label, "Allowance & Wishes")
        assertNoVisibleCJK(in: app, context: "English family management")

        app.terminate()
        app.launchArguments = [
            "-OctoTeacherUITest",
            "-OctoTeacherUITestEnglishFamily",
            "-OctoTeacherUITestFamilyTabs",
            "-OctoTeacherUITestInitialTab", "more"
        ]
        app.launch()
        XCTAssertTrue(app.navigationBars["More"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["more-tab-family-account"].exists)
        XCTAssertTrue(app.buttons["more-tab-software-settings"].exists)
        XCTAssertFalse(app.buttons["more-tab-school"].exists, "Preview school work must not leak into the family settings surface")
        XCTAssertTrue(app.descendants(matching: .any)["more-tab-privacy-summary"].exists)
        assertNoVisibleCJK(in: app, context: "English more and account surface")
    }

    private func scrollTo(app: XCUIApplication, identifier: String) -> Bool {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        for _ in 0..<12 {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    private func tap(app: XCUIApplication, identifier: String) -> Bool {
        guard scrollTo(app: app, identifier: identifier) else { return false }
        app.descendants(matching: .any)[identifier].firstMatch.tap()
        return true
    }

    private func assertNoVisibleCJK(
        in app: XCUIApplication,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let appFrame = app.frame
        let leaked = app.descendants(matching: .any).allElementsBoundByIndex.compactMap { element -> String? in
            guard element.exists,
                  !element.label.isEmpty,
                  element.frame.intersects(appFrame),
                  element.label.range(of: #"[\p{Han}]"#, options: .regularExpression) != nil
            else { return nil }
            return element.label
        }
        let systemAccessibilityLabels: Set<String> = [
            "个人收藏", "主页", "更多", "标签页栏", "网格2x2"
        ]
        let appLeaks = leaked.filter {
            !systemAccessibilityLabels.contains($0)
                && !$0.hasPrefix("垂直滚动条")
        }
        XCTAssertTrue(
            appLeaks.isEmpty,
            "\(context) contains visible Chinese labels: \(Array(Set(appLeaks)).sorted())",
            file: file,
            line: line
        )
    }
}
