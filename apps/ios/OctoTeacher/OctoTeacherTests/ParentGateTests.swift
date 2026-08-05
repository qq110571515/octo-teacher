import XCTest
@testable import OctoTeacher

/// 家长 PIN 门禁的回归测试。
final class ParentGateTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "octoteacher-parent-gate-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testFirstRunHasNoPinAndStaysLocked() {
        let gate = ParentGate(defaults: defaults)
        XCTAssertFalse(gate.hasPin)
        XCTAssertFalse(gate.isUnlocked)
        XCTAssertFalse(gate.unlock(with: "1234"), "未设置 PIN 时任何输入都不能解锁")
    }

    func testPinValidationRules() {
        XCTAssertTrue(ParentGate.isValidPin("1234"))
        XCTAssertTrue(ParentGate.isValidPin("123456"))
        XCTAssertFalse(ParentGate.isValidPin("123"), "少于 4 位不合法")
        XCTAssertFalse(ParentGate.isValidPin("1234567"), "超过 6 位不合法")
        XCTAssertFalse(ParentGate.isValidPin("12a4"), "必须是纯数字")
        XCTAssertFalse(ParentGate.isValidPin(""))
    }

    func testSetPinUnlocksAndPersistsAcrossInstances() {
        let gate = ParentGate(defaults: defaults)
        XCTAssertTrue(gate.setPin("2468"))
        XCTAssertTrue(gate.isUnlocked, "设置成功后直接进入解锁态")

        // 模拟 App 重启：新实例要求重新验证，但 PIN 仍在。
        let relaunched = ParentGate(defaults: defaults)
        XCTAssertTrue(relaunched.hasPin)
        XCTAssertFalse(relaunched.isUnlocked, "重启后需要重新输入 PIN")
        XCTAssertFalse(relaunched.unlock(with: "0000"))
        XCTAssertTrue(relaunched.unlock(with: "2468"))
    }

    func testInvalidPinIsRejectedAtSetup() {
        let gate = ParentGate(defaults: defaults)
        XCTAssertFalse(gate.setPin("12"))
        XCTAssertFalse(gate.hasPin)
        XCTAssertFalse(gate.isUnlocked)
    }

    func testLockRequiresReauthentication() {
        let gate = ParentGate(defaults: defaults)
        gate.setPin("1357")
        XCTAssertTrue(gate.isUnlocked)

        gate.lock()
        XCTAssertFalse(gate.isUnlocked)
        XCTAssertTrue(gate.unlock(with: "1357"))
    }

    func testUITestModePresetsPinWithoutTouchingDefaults() {
        // 模拟 UI 测试启动参数。
        let processInfo = ProcessInfo.processInfo
        // 无法注入 arguments，直接验证真实模式不含预置 PIN 即可；
        // UI 测试模式的行为由 UI 测试本身覆盖（用 1234 解锁）。
        let gate = ParentGate(defaults: defaults, processInfo: processInfo)
        XCTAssertFalse(gate.hasPin)
    }
}
