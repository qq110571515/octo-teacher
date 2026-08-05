import XCTest

/// 家庭真实模式（非 UI 测试模式）的首启路径验证。
///
/// 只带 `-OctoTeacherResetForFirstRunTest`（清数据，不改变模式判定），
/// App 走真实用户路径：首次设置 → 4 Tab → 家长设置 PIN → 布置任务入口。
/// 这是家长拿到手机的第一条体验路径，必须始终可用。
@MainActor
final class OctoTeacherFirstRunRealModeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testFirstRunSetupThenFamilyTabsThenParentPinSetup() {
        app = XCUIApplication()
        app.launchArguments = [
            "-OctoTeacherResetForFirstRunTest",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN"
        ]
        app.launch()

        // 1. 首次设置页出现，由家长填写。
        XCTAssertTrue(app.navigationBars["开始之前"].waitForExistence(timeout: 8), "Missing first-run setup page")
        XCTAssertTrue(app.staticTexts["欢迎使用章鱼老师"].waitForExistence(timeout: 3), "首次设置页应使用正式中文品牌章鱼老师")
        XCTAssertFalse(app.staticTexts["欢迎使用 OctoTeacher"].exists, "首次设置页不得再显示工程内部标识符")
        let nameField = app.textFields["family-setup-child-name"].firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 3), "Missing child name field")
        nameField.tap()
        nameField.typeText("Leo")
        if app.keyboards.buttons["return"].exists {
            app.keyboards.buttons["return"].tap()
        }

        let finishButton = app.buttons["family-setup-finish"].firstMatch
        XCTAssertTrue(finishButton.waitForExistence(timeout: 3), "Missing setup finish button")
        finishButton.tap()

        // 2. 家庭真实模式只有 4 个 Tab：孩子 / 家长 / 家庭 / 更多。
        for label in ["孩子", "家长", "家庭", "更多"] {
            XCTAssertTrue(app.tabBars.buttons[label].waitForExistence(timeout: 5), "Missing family tab \(label)")
        }
        for hidden in ["首页", "模块", "学校"] {
            XCTAssertFalse(app.tabBars.buttons[hidden].exists, "Platform tab \(hidden) should stay out of family mode")
        }

        // 3. 孩子首页已进入成长计划，并给出下一步。
        let growthPlanTitle = app.navigationBars.matching(
            NSPredicate(format: "identifier CONTAINS %@", "成长计划")
        ).firstMatch
        XCTAssertTrue(
            growthPlanTitle.waitForExistence(timeout: 5),
            "Missing child growth-plan title"
        )

        // 4. 家长 Tab 首次进入是设置 PIN，不是硬编码验证。
        app.tabBars.buttons["家长"].tap()
        let pinField = app.secureTextFields["parent-mode-setup-pin"].firstMatch
        XCTAssertTrue(pinField.waitForExistence(timeout: 5), "Missing parent PIN setup field")
        pinField.tap()
        pinField.typeText("2580")
        let confirmField = app.secureTextFields["parent-mode-setup-pin-confirm"].firstMatch
        confirmField.tap()
        confirmField.typeText("2580")
        app.buttons["parent-mode-setup-confirm"].tap()

        // 5. 解锁后第一屏同时给出家庭注册和今日布置入口，关键动作不能藏在设置深处。
        XCTAssertTrue(app.buttons["parent-mode-family-account"].waitForExistence(timeout: 5), "Missing first-screen family account entry")
        XCTAssertTrue(app.buttons["parent-mode-today-compose-task"].waitForExistence(timeout: 5), "Missing first-screen compose task entry after PIN setup")
    }
}
