import Foundation

/// 移动平台首页编排层的视图模型。
///
/// 这一层把 MobileSync mock snapshot、SchoolFamilyStore、LocalFamilyStore 里分散的
/// 今日任务、学校作业、家庭成长动态、成长积分余额、奖励会话和家长审批/亲友审核摘要，
/// 编排成一个**角色感知**的手机首页/工作台模型。设计约束（与 CLAUDE.md 一致）：
///
/// - 纯展示模型：只读聚合本地 mock/store，绝不接真实网络、云 API、数据库、登录、
///   支付、AI、推送、HealthKit、FamilyControls 或真实设备控制。
/// - 脱敏：展示文本只用昵称与人类可读摘要，绝不写真实孩子/家庭/学校/亲友标识、
///   token、本地路径、局域网地址或内部 publicRef。
/// - 权限边界由数据源裁决：首页只汇总与引导，不在此处批准任务、不发成长积分、不解锁设备；
///   孩子视角看不到任何审批/发成长积分入口，亲友能力恒为只读。

/// 首页视角。决定首页按孩子还是家长重新编排。
enum MobileHomePerspective: String, CaseIterable, Identifiable, Equatable {
    /// 孩子视角：今日任务、学校作业、成长动态、成长积分/奖励状态与下一步行动。
    case child
    /// 家长视角：待审批、家庭成长亮点、亲友待审核摘要、成长积分/奖励风险提示。
    case parent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .child: return "孩子"
        case .parent: return "家长"
        }
    }

    var systemImage: String {
        switch self {
        case .child: return "star.circle"
        case .parent: return "person.badge.key"
        }
    }
}

/// 首页条目的语气，用于在 UI 上做颜色/图标区分，但不携带任何敏感数据。
enum MobileHomeTone: String, Equatable {
    /// 中性信息。
    case neutral
    /// 正向/已完成。
    case positive
    /// 需要注意（待办、待审批）。
    case attention
    /// 风险提示（积分将过期、奖励进行中等需家长关注）。
    case risk
}

/// 首页条目的本地快捷目的地。
///
/// 这里只放安全的、已存在的本地页面入口，不携带 publicRef、任务 ID、账本 ID、
/// 网络地址或任何可写动作。首页是否展示入口由编排层按角色裁剪。
/// 每个 destination 通过 `allowedPerspectives` 声明允许哪些视角进入。
enum MobileHomeDestination: String, Equatable {
    case moduleConfigurationDraft = "module_configuration_draft"
    case aiHomeworkInbox = "ai_homework_inbox"
    case schoolJointApproval = "school_joint_approval"
    case rewardRedemption = "reward_redemption"
    case rewardStatus = "reward_status"
    /// 奖励商店库存履约安全壳（孩子 .child 视角，家长 .guardian 视角）。
    case rewardStoreFulfillment = "reward_store_fulfillment"
    case growthPackExecutionHub = "growth_pack_execution_hub"
    case growthPackEntitlements = "growth_pack_access"
    case growthPackCloudSync = "growth_pack_sync"
    case creditLedgerReview = "credit_review"
    case releaseGate = "release_gate"
    case familyStorylineConsent = "family_storyline_consent"
    /// 家庭社交反馈情绪安全中心（孩子/家长均可进入，只读）。
    case familySocialFeedbackEmotionalSafety = "family_social_feedback_safety"
    /// 离线同步本地复核台（孩子/家长均可进入，只读）。
    case offlineSyncReview = "offline_sync_review"

    /// 允许跳入该页面的视角集合。
    var allowedPerspectives: Set<MobileHomePerspective> {
        switch self {
        case .moduleConfigurationDraft:
            return [.parent]
        case .aiHomeworkInbox:
            return [.child, .parent]
        case .schoolJointApproval:
            return [.child, .parent]
        case .growthPackExecutionHub:
            return [.child, .parent]
        case .rewardRedemption:
            return [.child]
        case .rewardStatus:
            return [.parent]
        case .rewardStoreFulfillment:
            // 孩子进只读奖励库存视角，家长进库存履约复核视角；视角由进入页按 perspective 锁定。
            return [.child, .parent]
        case .growthPackEntitlements:
            return [.child, .parent]
        case .growthPackCloudSync:
            return [.child, .parent]
        case .creditLedgerReview:
            return [.parent]
        case .releaseGate:
            return [.parent]
        case .familyStorylineConsent:
            return [.parent]
        case .familySocialFeedbackEmotionalSafety:
            return [.child, .parent]
        case .offlineSyncReview:
            return [.child, .parent]
        }
    }
}

/// 首页顶部的指标卡。
struct MobileHomeMetric: Identifiable, Equatable {
    var id: String
    var title: String
    var value: String
    var caption: String?
    var tone: MobileHomeTone
}

/// 首页里的一条编排条目。
struct MobileHomeItem: Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String?
    var systemImage: String
    var tone: MobileHomeTone
    /// 状态徽标展示文本（如「待验证」「待审核」「进行中」）。
    var badge: String?
    /// 可选本地快捷入口；nil 表示普通展示行。
    var destination: MobileHomeDestination?

    init(
        id: String,
        title: String,
        detail: String? = nil,
        systemImage: String,
        tone: MobileHomeTone = .neutral,
        badge: String? = nil,
        destination: MobileHomeDestination? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.tone = tone
        self.badge = badge
        self.destination = destination
    }
}

/// 首页里的一个分区。
struct MobileHomeSection: Identifiable, Equatable {
    var id: String
    var title: String
    var subtitle: String?
    var items: [MobileHomeItem]
    /// 分区为空时的占位文案。
    var emptyText: String?

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        items: [MobileHomeItem],
        emptyText: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.items = items
        self.emptyText = emptyText
    }
}

/// 一个角色视角下完整的首页编排结果。
struct MobileHomeViewModel: Equatable {
    var perspective: MobileHomePerspective
    /// 顶部问候（脱敏昵称或工作台标题）。
    var greeting: String
    /// 一句话总览。
    var headline: String
    var metrics: [MobileHomeMetric]
    var sections: [MobileHomeSection]
}
