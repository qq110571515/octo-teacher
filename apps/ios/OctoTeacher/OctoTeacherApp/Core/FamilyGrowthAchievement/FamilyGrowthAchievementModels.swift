import Foundation

/// 家庭成长动态「荣誉卡片视图」本地模型。
///
/// 这是 `family-growth-feed-mobile-contract`（console 纯领域契约）在 iOS 本地壳的落地：
/// 把成长日记、徽章、成长球星卡、荣誉墙、亲友鼓励、成长视频日记和故事线摘要，统一成一种
/// 「荣誉卡片」，并按查看者角色（孩子 / 家长 / 亲友）做权限不同的可见性裁决。
///
/// 安全边界（对齐 CLAUDE.md 与任务禁止项）：
/// - 纯本地展示：不发布动态、不通知亲友、不发成长积分、不授徽章、不上传媒体、不接真实社交/学校/云端。
/// - 默认私密：`private` 内容只有孩子与家长可见，亲友永远看不到。
/// - 待审核 / 已撤回 / 已阻断内容**不**作为正式荣誉展示，也不对亲友展示。
/// - 所有对外引用都经稳定脱敏（`publicRef`），绝不暴露真实 child/family/relative/badge/honor
///   /journal/vlog/proof/event ID、token、路径、局域网地址、taskId 或 claimId。

// MARK: - 可见范围

/// 成长卡片可见范围（对齐契约 private / family / selected_relatives / public）。
enum FamilyGrowthCardVisibility: String, Codable, CaseIterable, Equatable {
    /// 私密：仅孩子与家长可见（默认）。
    case privateOnly
    /// 家庭圈：家庭成员与被授权亲友可见。
    case family
    /// 亲友可见：仅被家长授权的亲友可见。
    case relatives
    /// 公开：需家长显式批准后才可能公开（脱敏摘要）。
    case publicShare

    var label: String {
        switch self {
        case .privateOnly: return "私密"
        case .family: return "家庭可见"
        case .relatives: return "亲友可见"
        case .publicShare: return "公开"
        }
    }

    var systemImage: String {
        switch self {
        case .privateOnly: return "lock"
        case .family: return "house"
        case .relatives: return "person.2"
        case .publicShare: return "globe"
        }
    }
}

// MARK: - 查看者角色

/// 查看成长荣誉卡片的角色，权限不同。
enum FamilyGrowthViewerRole: String, CaseIterable, Equatable {
    /// 孩子本人：看自己的成长记录（含私密与待处理状态），但只见鼓励式文案。
    case child
    /// 家长：家庭管理者，可见全部内容与全部状态（含待审核/已撤回/已阻断）。
    case guardian
    /// 亲友：只读，只能看到已通过且对亲友开放的内容，永远看不到私密、待审核、已撤回、已阻断。
    case relative

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        case .relative: return "亲友"
        }
    }

    /// 是否属于家庭内部视角（孩子 / 家长）。
    var isHousehold: Bool { self != .relative }

    var audienceNote: String {
        switch self {
        case .child:
            return "这是你的成长记录。私密内容只有你和家长能看到，亲友看不到。"
        case .guardian:
            return "家长可见全部内容与状态，包括待审核、已撤回和已阻断，用于把关。"
        case .relative:
            return "亲友只读：仅能看到家长通过并对亲友开放的内容，看不到私密或待处理内容。"
        }
    }
}

// MARK: - 内容生命周期状态

/// 卡片生命周期状态。只有 `published` 才是正式荣誉。
enum FamilyGrowthLifecycle: String, Codable, CaseIterable, Equatable {
    /// 已通过、可作为正式荣誉展示。
    case published
    /// 待审核：等家长把关，尚未成为正式荣誉。
    case pending
    /// 已撤回：内容被撤下，不再作为荣誉展示。
    case withdrawn
    /// 已阻断：内容审核命中风险被拦截，仅展示脱敏说明。
    case blocked

    var label: String {
        switch self {
        case .published: return "已通过"
        case .pending: return "待审核"
        case .withdrawn: return "已撤回"
        case .blocked: return "已阻断"
        }
    }

    /// 是否可作为正式荣誉展示（只有已通过算）。
    var isFormalHonor: Bool { self == .published }

    var systemImage: String {
        switch self {
        case .published: return "checkmark.seal"
        case .pending: return "clock"
        case .withdrawn: return "arrow.uturn.backward"
        case .blocked: return "exclamationmark.shield"
        }
    }
}

// MARK: - 卡片来源种类

/// 荣誉卡片来源种类。
enum FamilyGrowthCardKind: String, Codable, CaseIterable, Equatable {
    case journal
    case badge
    case growthCard
    case honorWall
    case relativeComment
    case vlogPlaceholder
    case storyline

    var label: String {
        switch self {
        case .journal: return "成长日记"
        case .badge: return "徽章"
        case .growthCard: return "成长球星卡"
        case .honorWall: return "荣誉墙"
        case .relativeComment: return "亲友鼓励"
        case .vlogPlaceholder: return "成长视频日记"
        case .storyline: return "故事线"
        }
    }

    var systemImage: String {
        switch self {
        case .journal: return "book"
        case .badge: return "rosette"
        case .growthCard: return "person.text.rectangle"
        case .honorWall: return "trophy"
        case .relativeComment: return "bubble.left.and.bubble.right"
        case .vlogPlaceholder: return "film"
        case .storyline: return "sparkles"
        }
    }
}

// MARK: - 荣誉卡片

/// 一张家庭成长荣誉卡片（已是脱敏后的展示态）。
struct FamilyGrowthCard: Identifiable, Equatable {
    let id: UUID
    /// 仅用于派生脱敏 `publicRef` 的稳定 seed，**绝不直接展示**。
    let internalSeed: String
    var kind: FamilyGrowthCardKind
    var title: String
    /// 已脱敏摘要文本。
    var summary: String
    /// 发生时间展示文本（脱敏，不含精确日期/位置）。
    var occurredLabel: String
    var visibility: FamilyGrowthCardVisibility
    var lifecycle: FamilyGrowthLifecycle
    /// 支持性文案：鼓励式、非攀比、非施压。
    var supportiveCopy: String
    /// 下一步建议（引导式，不承诺奖励、不发成长积分）。
    var nextStep: String
    var tags: [String]
    /// 是否在家长授权的亲友名单内（用于 `relatives` 可见性裁决）。
    var allowsRelative: Bool
    var reactionCount: Int
    /// 已通过审核的鼓励留言数（待审核留言不计入）。
    var approvedCommentCount: Int
    /// 成长球星卡的能力维度评分（仅 `growthCard` 使用）。
    var ratings: [AbilityDimension: Int]?

    /// 稳定脱敏引用，对齐 console 契约的 djb2 折叠；同一 seed 恒定，不可逆推真实 ID。
    var publicRef: String {
        FamilyGrowthRedaction.publicRef(prefix: "card", source: internalSeed)
    }

    /// 是否为正式荣誉（已通过）。
    var isFormalHonor: Bool { lifecycle.isFormalHonor }

    /// 综合评分（仅成长球星卡），各维度平均封顶 1–99。
    var overallRating: Int? {
        guard let ratings, !ratings.isEmpty else { return nil }
        let sum = ratings.values.reduce(0, +)
        return min(99, max(1, sum / ratings.count))
    }

    /// 当前角色是否可见这张卡片。
    ///
    /// 裁决规则（与 `family-growth-feed-mobile-contract.canViewerSee` 同义）：
    /// - 亲友：只能看到 `published` 且可见性为 `family` 或（`relatives` 且在授权名单内）的卡片；
    ///   私密、公开、待审核、已撤回、已阻断一律不可见。
    /// - 孩子 / 家长（家庭内部）：可见全部内容与状态（已阻断仅展示脱敏说明）。
    func isVisible(to role: FamilyGrowthViewerRole) -> Bool {
        switch role {
        case .child, .guardian:
            return true
        case .relative:
            guard lifecycle == .published else { return false }
            switch visibility {
            case .family:
                return true
            case .relatives:
                return allowsRelative
            case .privateOnly, .publicShare:
                return false
            }
        }
    }

    /// 给当前角色的状态说明（非正式荣誉时解释原因；正式荣誉返回 nil）。
    func statusNote(for role: FamilyGrowthViewerRole) -> String? {
        switch lifecycle {
        case .published:
            return nil
        case .pending:
            return role.isHousehold ? "待家长审核，暂不作为正式荣誉展示，亲友看不到。" : nil
        case .withdrawn:
            return role.isHousehold ? "内容已撤回，不再作为荣誉展示。" : nil
        case .blocked:
            return role.isHousehold ? "内容审核命中风险已被阻断，仅展示脱敏说明，不会公开。" : nil
        }
    }

    /// 面向当前角色的安全摘要：已阻断内容只给脱敏说明，绝不展示原文。
    func displaySummary(for role: FamilyGrowthViewerRole) -> String {
        if lifecycle == .blocked {
            return "（内容已阻断，仅保留脱敏说明）"
        }
        return summary
    }
}

// MARK: - 视角汇总

/// 某个查看角色看到的荣誉卡片汇总（已完成可见性裁决与脱敏）。
struct FamilyGrowthViewerSummary: Equatable {
    let role: FamilyGrowthViewerRole
    /// 脱敏家庭引用。
    let familyPublicRef: String
    /// 脱敏孩子引用。
    let childPublicRef: String
    /// 当前角色可见的卡片（按来源种类与生命周期排序）。
    let cards: [FamilyGrowthCard]
    /// 各来源种类计数。
    let kindCounts: [FamilyGrowthCardKind: Int]
    /// 各可见范围计数。
    let visibilityCounts: [FamilyGrowthCardVisibility: Int]

    /// 正式荣誉数量（已通过）。
    var formalHonorCount: Int {
        cards.filter(\.isFormalHonor).count
    }

    /// 待处理数量（待审核 + 已撤回 + 已阻断），仅家庭内部角色会看到。
    var pendingCount: Int {
        cards.filter { !$0.isFormalHonor }.count
    }
}

// MARK: - 脱敏工具

/// 稳定脱敏引用工具，复刻 console `family-growth-feed-mobile-contract` 的 djb2 折叠，
/// 保证 iOS 与 console 对同一 seed 产出可比的公开引用，且不可逆推真实 ID。
enum FamilyGrowthRedaction {
    static let salt = "family-growth-card"

    static func publicRef(prefix: String, source: String) -> String {
        var hash: UInt32 = 5381
        for scalar in "\(salt):\(source)".unicodeScalars {
            hash = (hash &* 33) ^ (scalar.value & 0xFFFF)
        }
        let folded = String(hash, radix: 36)
        let padded = String(repeating: "0", count: max(0, 7 - folded.count)) + folded
        return "\(prefix):\(padded)"
    }
}
