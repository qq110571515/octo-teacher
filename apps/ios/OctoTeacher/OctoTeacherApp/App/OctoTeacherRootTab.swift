import Foundation

/// iOS 根导航的平台化中文 Tab 纯配置。
///
/// 这是一份只读、可测试的导航壳配置，不持有任务、成长积分、奖励、学校、家庭或设备业务状态，
/// 也不触发网络、AI、LMS、学校系统、账本、通知、支付或设备控制。RootView 仅按这里声明的
/// 顺序与 label/systemImage 渲染顶层 Tab，真正的业务能力仍由各自的页面承载。
enum OctoTeacherRootTab: Int, CaseIterable, Equatable {
    case home
    case modules
    case child
    case parent
    case school
    case family
    case more

    /// 家庭日常模式的顶层 Tab：孩子、家长、家庭、更多。
    ///
    /// 首轮家庭测试聚焦「孩子做任务、家长审核」两条主路径；平台首页、模块能力中心、
    /// 学校作业等预览能力统一收进「更多」，不挤占底部导航。
    static let ordered: [OctoTeacherRootTab] = [
        .child,
        .parent,
        .family,
        .more
    ]

    /// UI 测试 / 模块审计模式的完整 Tab：保留全部平台入口，
    /// 让既有模块点击路径测试可以直达各个能力中心。
    static let auditOrdered: [OctoTeacherRootTab] = [
        .home,
        .modules,
        .child,
        .parent,
        .school,
        .family
    ]

    /// TabView 选择用的稳定 tag，与 rawValue 一致，保证顺序与选中状态稳定。
    var tag: Int { rawValue }

    /// 是否是孩子直接面对的 surface（孩子端/学校作业孩子视角）。
    var isChildFacingSurface: Bool {
        self == .child || self == .school
    }

    /// 当前选中 surface 的统一界面语言：孩子面向页面用当前孩子语言，
    /// 家长/家庭/更多等页面用家长语言。整棵导航（含 Tab bar 四个标题）
    /// 必须一次性使用同一语言，不允许一半英文一半中文。
    static func surfaceLanguage(
        selectedTag: Int,
        parentLanguage: AppInterfaceLanguage,
        activeChildLanguage: AppInterfaceLanguage
    ) -> AppInterfaceLanguage {
        let tab = OctoTeacherRootTab(rawValue: selectedTag) ?? .child
        return tab.isChildFacingSurface ? activeChildLanguage : parentLanguage
    }

    /// 兼容现有审计与测试的默认中文标签。
    var label: String { label(for: .chinese) }

    func label(for language: AppInterfaceLanguage) -> String {
        switch (self, language) {
        case (.home, .chinese): return "首页"
        case (.modules, .chinese): return "模块"
        case (.child, .chinese): return "孩子"
        case (.parent, .chinese): return "家长"
        case (.school, .chinese): return "学校"
        case (.family, .chinese): return "家庭"
        case (.more, .chinese): return "更多"
        case (.home, .english): return "Home"
        case (.modules, .english): return "Modules"
        case (.child, .english): return "Child"
        case (.parent, .english): return "Parent"
        case (.school, .english): return "School"
        case (.family, .english): return "Family"
        case (.more, .english): return "More"
        }
    }

    /// SF Symbol 名称，仅用于 Tab 图标，不含业务语义。
    var systemImage: String {
        switch self {
        case .home: return "house"
        case .modules: return "square.grid.2x2"
        case .child: return "star.circle"
        case .parent: return "person.badge.key"
        case .school: return "book.closed"
        case .family: return "heart.text.square"
        case .more: return "ellipsis.circle"
        }
    }
}
