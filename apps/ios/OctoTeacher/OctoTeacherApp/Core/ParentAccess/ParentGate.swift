import Foundation
import Observation

/// 家长模式门禁：管理家长 PIN 的设置与验证。
///
/// - 首次使用：没有 PIN 时引导家长设置 4–6 位数字 PIN。
/// - 之后进入家长模式需输入 PIN；App 重启后需要重新验证。
/// - PIN 只存本机 UserDefaults，不上传。忘记 PIN 时删除重装 App 可重置。
/// - UI 测试模式（任何 -章鱼老师UITest 前缀启动参数）预置 PIN "1234"
///   且不落盘，保证测试确定性。
@Observable
final class ParentGate {
    private static let pinKey = "octoteacher.parent.pin"

    @ObservationIgnored
    private let defaults: UserDefaults?
    /// UI 测试模式下的内存 PIN；真实模式恒为 nil。
    @ObservationIgnored
    private var ephemeralPin: String?

    /// 本次运行是否已通过验证。切换 Tab 保持解锁，App 重启后重新验证。
    private(set) var isUnlocked = false

    init(defaults: UserDefaults? = .standard, processInfo: ProcessInfo = .processInfo) {
        let isUITest = processInfo.arguments.contains { $0.hasPrefix("-OctoTeacherUITest") }
        if isUITest {
            self.defaults = nil
            self.ephemeralPin = "1234"
        } else {
            self.defaults = defaults
        }
    }

    /// 是否已设置过家长 PIN。
    var hasPin: Bool {
        storedPin != nil
    }

    private var storedPin: String? {
        if let ephemeralPin { return ephemeralPin }
        return defaults?.string(forKey: Self.pinKey)
    }

    /// PIN 合法性：4–6 位纯数字。
    static func isValidPin(_ pin: String) -> Bool {
        (4...6).contains(pin.count) && pin.allSatisfy(\.isNumber)
    }

    /// 首次设置（或重设）家长 PIN。设置成功后直接进入解锁态。
    @discardableResult
    func setPin(_ pin: String) -> Bool {
        guard Self.isValidPin(pin) else { return false }
        if defaults != nil {
            defaults?.set(pin, forKey: Self.pinKey)
        } else {
            ephemeralPin = pin
        }
        isUnlocked = true
        return true
    }

    /// 输入 PIN 验证解锁。
    @discardableResult
    func unlock(with pin: String) -> Bool {
        guard let storedPin, pin == storedPin else { return false }
        isUnlocked = true
        return true
    }

    /// 手动锁定家长模式（例如把手机交回孩子前）。
    func lock() {
        isUnlocked = false
    }
}
