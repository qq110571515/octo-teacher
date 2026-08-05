import Foundation

/// 模块能力中心「入口级角色范围锁定」的纯配置值类型。
///
/// 它只负责把调用方传入的 initialRole 与 allowedRoles 归一化成：可在 Picker 中展示的
/// availableRoles、归一化后的 initialRole，以及该入口是否允许切换视角。
/// 这里不读取任何家庭、学校、账本或设备数据，也不触发任何副作用，只做范围裁剪，
/// 因此可以脱离 SwiftUI 单独单测。它不改变任何模块的业务语义或路由目标，只限制
/// 入口可切换的 viewerRole 范围。
struct MobileModuleLaunchCenterRoleScope: Equatable {
    /// 归一化后的初始视角；保证一定落在 availableRoles 内。
    let initialRole: MobileModuleLaunchCenterViewerRole
    /// 入口允许展示和切换的视角集合（已去重、按系统视角顺序排序、且非空）。
    let availableRoles: [MobileModuleLaunchCenterViewerRole]

    init(
        initialRole: MobileModuleLaunchCenterViewerRole = .child,
        allowedRoles: [MobileModuleLaunchCenterViewerRole] = MobileModuleLaunchCenterViewerRole.allCases
    ) {
        let safeRoles = Self.normalized(allowedRoles)
        self.availableRoles = safeRoles
        // 非法 initialRole（不在 allowedRoles 内）回退到第一个允许角色，避免入口停在越权视角。
        self.initialRole = safeRoles.contains(initialRole) ? initialRole : safeRoles[0]
    }

    /// 多于一个角色时才允许在入口内切换视角；单角色时入口锁定当前视角。
    var allowsRoleSwitching: Bool {
        availableRoles.count > 1
    }

    /// 是否已锁定为单一视角入口。
    var isLocked: Bool {
        !allowsRoleSwitching
    }

    /// 锁定的视角；仅在单角色锁定时有意义，多角色可切换时为 nil。
    var lockedRole: MobileModuleLaunchCenterViewerRole? {
        isLocked ? availableRoles[0] : nil
    }

    private static func normalized(
        _ allowedRoles: [MobileModuleLaunchCenterViewerRole]
    ) -> [MobileModuleLaunchCenterViewerRole] {
        let requested = Set(allowedRoles)
        let ordered = MobileModuleLaunchCenterViewerRole.allCases.filter { requested.contains($0) }
        return ordered.isEmpty ? MobileModuleLaunchCenterViewerRole.allCases : ordered
    }
}
