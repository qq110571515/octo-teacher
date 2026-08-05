import Foundation

/// 亲友留下鼓励/建议。仅写入建议占位，绝不发成长积分、不改任务、不解锁设备。
struct RelativeSuggestUseCase {
    let store: LocalFamilyStore

    @discardableResult
    func callAsFunction(from relative: FamilyRelative, message: String) -> Bool {
        store.relativeSuggest(from: relative, message: message)
    }
}

/// 亲友请求解锁设备：永远被拒绝。
///
/// 亲友没有设备控制能力（`canUnlockDevice` 恒为 false），因此本用例永远返回 false，
/// 并且不会触碰 `MockScreenTimeController`，从用例层再加一道护栏，保证亲友无法越权解锁设备。
struct RelativeDeviceUnlockRequestUseCase {
    let screenTimeController: MockScreenTimeController

    @discardableResult
    func callAsFunction(from relative: FamilyRelative, minutes: Int) -> Bool {
        guard relative.capability.canUnlockDevice else { return false }
        // 不可达分支：模型保证亲友无解锁能力，此处仅为完整性保留。
        screenTimeController.unshield(for: minutes)
        return true
    }
}
