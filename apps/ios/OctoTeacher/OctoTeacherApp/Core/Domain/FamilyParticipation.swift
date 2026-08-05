import Foundation

/// 亲友在家庭圈里的角色。仅作展示分类，不代表任何额外权限。
/// 默认只做私密家庭圈，不接真实通讯录、账号或公开广场。
enum RelativeRole: String, Codable, CaseIterable {
    case grandparent
    case auntUncle
    case sibling
    case familyFriend

    var label: String {
        switch self {
        case .grandparent: return "祖辈"
        case .auntUncle: return "叔叔阿姨"
        case .sibling: return "哥哥姐姐"
        case .familyFriend: return "家庭朋友"
        }
    }
}

/// 亲友能力边界：默认只读 + 建议。
/// 批准任务、发放成长积分、解锁设备三项能力对亲友恒为 false，且不可通过构造放开，
/// 以此从模型层保证亲友无法越权。
struct RelativeCapability: Codable, Equatable {
    /// 可查看脱敏后的家庭参与摘要。
    var canViewSummary: Bool
    /// 可留鼓励/建议占位文字（不发成长积分、不改任务状态）。
    var canSuggest: Bool

    /// 以下三项是安全边界，只读常量，永远为 false。
    var canApproveTasks: Bool { false }
    var canGrantCredit: Bool { false }
    var canUnlockDevice: Bool { false }

    /// 标准亲友能力：只读 + 建议。
    static let readOnlySuggest = RelativeCapability(canViewSummary: true, canSuggest: true)

    /// 受限亲友能力：仅可查看摘要，连建议都不可留。
    static let viewOnly = RelativeCapability(canViewSummary: true, canSuggest: false)
}

/// 家庭圈里的一位亲友。displayName 使用脱敏昵称，不存真实姓名、联系方式或地址。
struct FamilyRelative: Identifiable, Codable, Equatable {
    let id: UUID
    var displayName: String
    var role: RelativeRole
    var capability: RelativeCapability
}

/// 亲友留下的鼓励/建议占位。仅本地 mock，不发成长积分、不解锁设备、不改任务状态。
struct RelativeSuggestion: Identifiable, Codable, Equatable {
    let id: UUID
    var relativeId: UUID
    var message: String
    var createdAt: Date
}

/// 家庭参与台的事件类型，用于审批后的事件摘要与最近成长记录。
enum FamilyEventKind: String, Codable {
    case taskApproved
    case taskRejected
    case relativeSuggested
    /// 家长布置了新任务。
    case taskAssigned
    /// 孩子或家长撤销了尚未结算的任务。
    case taskCancelled
}

/// 家庭参与台的一条事件记录。不含原始证明文本，只保留脱敏后的摘要信息。
struct FamilyEvent: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: FamilyEventKind
    var title: String
    var detail: String
    /// 仅批准事件携带发放的成长积分。
    var minutes: Int?
    var createdAt: Date
}

/// 亲友参与摘要：供家长查看，亲友本身只读。
struct RelativeParticipationSummary: Equatable {
    var relativeCount: Int
    var suggestionCount: Int
    /// 是否存在任何可越权发成长积分的亲友；按安全边界应恒为 false。
    var anyRelativeCanGrantCredit: Bool
    /// 是否存在任何可越权解锁设备的亲友；按安全边界应恒为 false。
    var anyRelativeCanUnlockDevice: Bool
}
