import Foundation

/// 模块能力中心「发现筛选与下一步推荐」纯本地配置层。
///
/// 它只在已经由 `MobileModuleLaunchCenterBuilder` 按 roleScope + snapshot 生成、
/// 且已经做过角色可见性裁剪的模块上做二次过滤和排序：搜索关键词、分组筛选、状态筛选，
/// 以及把「需复核 / 进行中 / 低进度但可进入」的模块排到前面的「下一步推荐」排序。
///
/// 它绝不新增任何模块、不改变模块业务语义、不改变路由目的地、不放宽角色可见性，
/// 也不读取任何家庭、学校、账本、设备或网络数据。搜索只匹配已脱敏的展示字段
/// （标题、说明、入口提示、分组标题、状态标签），不匹配 publicModuleRef 等内部引用，
/// 因此既能脱离 SwiftUI 单测，也不会通过搜索泄漏内部 ID 或越权模块。

/// 「下一步推荐」排序模式。
enum MobileModuleLaunchCenterDiscoverySort: String, CaseIterable, Equatable {
    /// 按推荐度排序：需复核、进行中、低进度但可进入优先。
    case recommended
    /// 保留 snapshot 原始分组顺序，不重排。
    case original

    var label: String {
        switch self {
        case .recommended: return "下一步推荐"
        case .original: return "默认顺序"
        }
    }
}

/// 发现层筛选条件。所有字段都是纯本地展示态，默认表示「不过滤、按推荐排序」。
struct MobileModuleLaunchCenterDiscoveryFilter: Equatable {
    /// 搜索关键词；只匹配已脱敏的展示字段。
    var searchText: String
    /// 分组筛选；nil 表示全部分组。
    var group: MobileModuleLaunchGroupKind?
    /// 状态筛选；nil 表示全部状态。
    var status: MobileModuleLaunchCenterStatus?
    /// 排序模式；默认推荐排序。
    var sort: MobileModuleLaunchCenterDiscoverySort

    init(
        searchText: String = "",
        group: MobileModuleLaunchGroupKind? = nil,
        status: MobileModuleLaunchCenterStatus? = nil,
        sort: MobileModuleLaunchCenterDiscoverySort = .recommended
    ) {
        self.searchText = searchText
        self.group = group
        self.status = status
        self.sort = sort
    }

    /// 归一化后的搜索词：去掉首尾空白并小写。
    var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// 是否启用了任何会改变默认全量展示的过滤条件（搜索 / 分组 / 状态）。
    /// 仅切换排序不算「过滤」，默认仍展示全量模块。
    var hasActiveFilter: Bool {
        !normalizedSearch.isEmpty || group != nil || status != nil
    }
}

/// 发现层过滤 + 排序结果。
struct MobileModuleLaunchCenterDiscoveryResult: Equatable {
    /// 过滤并排序后的模块列表。
    var modules: [MobileModuleLaunchModuleCard]
    /// 当前 snapshot 中角色可见的模块总数（过滤前）。
    var totalVisibleCount: Int
    /// snapshot 中出现过的分组（用于构建分组筛选菜单，保持系统分组顺序）。
    var availableGroups: [MobileModuleLaunchGroupKind]
    /// snapshot 中出现过的状态（用于构建状态筛选菜单，保持系统状态顺序）。
    var availableStatuses: [MobileModuleLaunchCenterStatus]
    /// 当前是否启用了过滤条件。
    var hasActiveFilter: Bool

    /// 命中模块数。
    var matchedCount: Int { modules.count }

    /// 是否为空结果。
    var isEmpty: Bool { modules.isEmpty }

    /// 无结果时的安全空状态文案；有结果时为 nil。
    /// 文案只描述过滤动作，不回显搜索原文，避免泄漏潜在敏感输入。
    var emptyStateMessage: String? {
        guard isEmpty else { return nil }
        if totalVisibleCount == 0 {
            return "当前视角暂时没有可进入的模块。"
        }
        if hasActiveFilter {
            return "没有符合当前搜索或筛选的模块，请调整关键词、分组或状态。"
        }
        return "当前视角暂时没有可进入的模块。"
    }
}

/// 发现层纯函数入口。无状态、可重复调用、对相同输入返回相同结果。
enum MobileModuleLaunchCenterDiscovery {

    /// 在 snapshot 已可见模块上应用过滤与排序。
    ///
    /// 只读取 snapshot.modules（已按 roleScope + 可见性裁剪），不接触原始 builder、
    /// 不重新生成模块、不放宽可见性，因此无法引入任何越权模块。
    static func apply(
        _ filter: MobileModuleLaunchCenterDiscoveryFilter,
        to snapshot: MobileModuleLaunchCenterSnapshot
    ) -> MobileModuleLaunchCenterDiscoveryResult {
        apply(filter, to: snapshot.modules)
    }

    /// 直接在一组已可见模块上应用过滤与排序的底层实现。
    static func apply(
        _ filter: MobileModuleLaunchCenterDiscoveryFilter,
        to visibleModules: [MobileModuleLaunchModuleCard]
    ) -> MobileModuleLaunchCenterDiscoveryResult {
        let availableGroups = MobileModuleLaunchGroupKind.allCases.filter { kind in
            visibleModules.contains { $0.group == kind }
        }
        let availableStatuses = orderedStatuses.filter { status in
            visibleModules.contains { $0.status == status }
        }

        let filtered = visibleModules.filter { matches($0, filter: filter) }
        let sorted = sort(filtered, by: filter.sort)

        return MobileModuleLaunchCenterDiscoveryResult(
            modules: sorted,
            totalVisibleCount: visibleModules.count,
            availableGroups: availableGroups,
            availableStatuses: availableStatuses,
            hasActiveFilter: filter.hasActiveFilter
        )
    }

    /// 系统状态展示顺序，用于筛选菜单与排序的确定性。
    private static let orderedStatuses: [MobileModuleLaunchCenterStatus] = [
        .reviewRequired, .active, .ready, .blocked
    ]

    private static func matches(
        _ card: MobileModuleLaunchModuleCard,
        filter: MobileModuleLaunchCenterDiscoveryFilter
    ) -> Bool {
        if let group = filter.group, card.group != group { return false }
        if let status = filter.status, card.status != status { return false }

        let keyword = filter.normalizedSearch
        guard !keyword.isEmpty else { return true }
        // 只匹配已脱敏的展示字段；故意不匹配 publicModuleRef / key.rawValue，
        // 避免用内部引用或原始 key 搜出本不该靠搜索暴露的内部标识。
        let haystack = [
            card.title,
            card.detail,
            card.routeHint,
            card.group.title,
            card.status.label
        ]
        .map(safeSearchField)
        .joined(separator: " ")
        .lowercased()
        return haystack.contains(keyword)
    }

    private static func safeSearchField(_ value: String) -> String {
        containsSensitiveSearchMarker(value) ? "" : value
    }

    private static func containsSensitiveSearchMarker(_ value: String) -> Bool {
        let lowered = value.lowercased()
        return [
            "publicref",
            "provider:",
            "model:",
            "transcript",
            "token",
            "sk-",
            "task:",
            "claim:",
            "ledger:",
            "order:",
            "entitlement:",
            "http://",
            "https://",
            "192.168.",
            "/users/",
            "/volumes/"
        ].contains { lowered.contains($0) }
    }

    private static func sort(
        _ cards: [MobileModuleLaunchModuleCard],
        by sort: MobileModuleLaunchCenterDiscoverySort
    ) -> [MobileModuleLaunchModuleCard] {
        switch sort {
        case .original:
            return cards
        case .recommended:
            // 确定性排序：先按推荐分降序，分数相同再按 key.rawValue 升序，
            // 保证相同输入稳定可复现，不依赖 Swift sort 的稳定性。
            return cards.sorted { lhs, rhs in
                let lScore = recommendationScore(lhs)
                let rScore = recommendationScore(rhs)
                if lScore != rScore { return lScore > rScore }
                return lhs.key.rawValue < rhs.key.rawValue
            }
        }
    }

    /// 推荐分：需复核 / 待处理 > 进行中 > 可使用 > 已阻断；
    /// 同档内「低进度但可进入」的模块排更前（已阻断不参与低进度加权）。
    static func recommendationScore(_ card: MobileModuleLaunchModuleCard) -> Int {
        var score = 0
        if card.actionRequired { score += 10_000 }
        switch card.status {
        case .reviewRequired: score += 3_000
        case .active: score += 2_000
        case .ready: score += 1_000
        case .blocked: score += 0
        }
        if card.status != .blocked {
            let progress = min(100, max(0, card.progress))
            score += (100 - progress)
        }
        return score
    }
}
