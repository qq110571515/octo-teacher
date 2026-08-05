import Foundation

/// 成长内容可见范围。
///
/// 安全边界：默认家庭私密（`privateFamily`）。任何成长内容在没有家长显式放开可见性
/// 之前，亲友（只读/待审核）都看不到。`public` 不在本地壳里使用，亲友最多只能看到
/// 被批准且范围为 `family` 或 `careTeam` 的内容。
enum FamilyFeedVisibility: String, Codable, CaseIterable, Equatable {
    /// 仅孩子与家长可见（默认）。
    case privateFamily
    /// 家庭圈内（含被授权亲友）可见。
    case family
    /// 关护团队（如被授权的老师/专家摘要）可见。
    case careTeam

    var label: String {
        switch self {
        case .privateFamily: return "仅家庭私密"
        case .family: return "家庭圈可见"
        case .careTeam: return "关护团队可见"
        }
    }
}

/// 内容审核/批准状态。家长批准前默认 `pending`，亲友内容亦同。
enum FamilyApprovalState: String, Codable, Equatable {
    case pending
    case approved
    case rejected

    var label: String {
        switch self {
        case .pending: return "待审核"
        case .approved: return "已通过"
        case .rejected: return "已退回"
        }
    }
}

/// 查看动态的受众。用于在 store 层做可见性裁决。
enum FamilyFeedAudience: Hashable {
    /// 孩子或家长：家庭内部，可见全部（含私密、待审核）。
    case household
    /// 亲友：只读，只能看到已批准且非私密的内容。
    case relative
}

/// 一条家庭成长动态。默认私密，批准后才可能对亲友可见。
struct GrowthFeedEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var summary: String
    var visibility: FamilyFeedVisibility
    var approval: FamilyApprovalState
    /// 发生时间展示文本（脱敏，不含精确日期/位置）。
    var occurredLabel: String
    var tags: [String]

    /// 是否对指定受众可见。
    func isVisible(to audience: FamilyFeedAudience) -> Bool {
        switch audience {
        case .household:
            return true
        case .relative:
            return approval == .approved && visibility != .privateFamily
        }
    }
}

/// 成长徽章。仅展示用，脱敏。
struct GrowthBadge: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var systemImage: String
    /// 获得说明展示文本。
    var earnedLabel: String
}

/// 能力维度，用于成长球星卡的雷达式数值。
enum AbilityDimension: String, Codable, CaseIterable, Equatable {
    case knowledge
    case habit
    case creativity
    case social
    case health

    var label: String {
        switch self {
        case .knowledge: return "学识"
        case .habit: return "习惯"
        case .creativity: return "创造"
        case .social: return "社交"
        case .health: return "健康"
        }
    }
}

/// 成长球星卡：把任务、成长积分、徽章沉淀成能力维度的快照评分。
/// 评分仅本地推导展示，范围 1–99，不代表对孩子的任何真实评判或外部排名。
struct GrowthStarCard: Identifiable, Codable, Equatable {
    let id: UUID
    /// 孩子脱敏昵称。
    var childNickname: String
    /// 赛季/阶段展示文本（如「本月」）。
    var seasonLabel: String
    var ratings: [AbilityDimension: Int]
    var visibility: FamilyFeedVisibility

    /// 综合评分：各维度平均，封顶 1–99。
    var overall: Int {
        guard !ratings.isEmpty else { return 0 }
        let sum = ratings.values.reduce(0, +)
        return min(99, max(1, sum / ratings.count))
    }

    /// 取某维度评分（缺失记 0）。
    func rating(for dimension: AbilityDimension) -> Int {
        ratings[dimension] ?? 0
    }
}

/// 荣誉墙条目。默认 `pending`，需家长批准后才上墙、才可能对亲友可见。
struct HonorWallItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    /// 荣誉分类展示文本（如「阅读之星」）。
    var category: String
    var approval: FamilyApprovalState
    var visibility: FamilyFeedVisibility

    func isVisible(to audience: FamilyFeedAudience) -> Bool {
        switch audience {
        case .household:
            return approval != .rejected
        case .relative:
            return approval == .approved && visibility != .privateFamily
        }
    }
}

/// 亲友评论/鼓励。
///
/// 安全边界：亲友只读 + 待审核。亲友留下的评论默认 `pending`，必须经家长审核
/// 才会对其他亲友展示；亲友绝不能批准、不能发成长积分、不能给孩子施压式催促。
struct RelativeFeedComment: Identifiable, Codable, Equatable {
    let id: UUID
    /// 亲友脱敏昵称。
    var relativeNickname: String
    var message: String
    var status: FamilyApprovalState
    var createdLabel: String

    func isVisible(to audience: FamilyFeedAudience) -> Bool {
        switch audience {
        case .household:
            return true
        case .relative:
            return status == .approved
        }
    }
}

/// 成长视频日记条目（暂不持有媒体）。
///
/// 安全边界：当前**不接入**真实视频、相册、相机、网络上传或云存储，
/// 只保存标题 + 时长展示 + 状态说明，绝不持有真实媒体数据或路径。
struct GrowthVLOGPlaceholder: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    /// 计划时长展示文本（如「约 1 分钟」）。
    var durationLabel: String
    var visibility: FamilyFeedVisibility
    /// 状态说明展示文本（如「待家长开启记录」）。提示当前尚未持有真实视频。
    var placeholderNote: String

    func isVisible(to audience: FamilyFeedAudience) -> Bool {
        switch audience {
        case .household:
            return true
        case .relative:
            return visibility != .privateFamily
        }
    }
}

/// 励志故事线里程碑。
struct StorylineMilestone: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var summary: String
    var occurredLabel: String
}

/// 励志故事线摘要：把成长里程碑串成一条鼓励式时间线。
struct StorylineSummary: Codable, Equatable {
    /// 摘要标题（鼓励式）。
    var headline: String
    var milestones: [StorylineMilestone]
}
