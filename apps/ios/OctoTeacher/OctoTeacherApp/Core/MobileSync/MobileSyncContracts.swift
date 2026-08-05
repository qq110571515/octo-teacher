import Foundation

/// 移动同步客户端消费壳的本地契约模型。
///
/// 这些类型把平台共享契约 B16-B20（mobile-cloud-contracts / mobile-sync-api 的
/// view 语义）映射成 iOS 本地可消费、可测试的脱敏模型。设计约束：
///
/// - 客户端只认「公开引用」（publicRef，形如 `kind:token`），绝不持有真实
///   childRef、familyRef、taskRef、proofRef、token、设备标识、局域网地址或本地路径。
/// - 这是一个**本地消费壳**，不是生产同步协议：所有数据来自本地 mock snapshot，
///   不接真实网络、云 API、数据库、登录或推送。
/// - 设备控制只用 `deviceCommandQueued` 标志表达「已排队」，绝不在此真正解锁设备。

// MARK: - 角色与会话

/// 移动同步会话角色。只暴露移动端实际会出现的三种角色。
enum MobileSyncActorRole: String, Codable, Equatable, CaseIterable {
    case child
    case guardian
    case teacher
}

/// 一次移动同步请求的会话上下文。只携带公开引用，权限在客户端本地裁决。
struct MobileSyncSession: Equatable {
    var actorPublicRef: String
    var actorRole: MobileSyncActorRole
    var familyPublicRef: String
    /// 孩子角色绑定的孩子公开引用。
    var childPublicRef: String?
    /// 家长/老师被授权访问的孩子公开引用；空数组表示家庭内全部孩子。
    var authorizedChildPublicRefs: [String]

    init(
        actorPublicRef: String,
        actorRole: MobileSyncActorRole,
        familyPublicRef: String,
        childPublicRef: String? = nil,
        authorizedChildPublicRefs: [String] = []
    ) {
        self.actorPublicRef = actorPublicRef
        self.actorRole = actorRole
        self.familyPublicRef = familyPublicRef
        self.childPublicRef = childPublicRef
        self.authorizedChildPublicRefs = authorizedChildPublicRefs
    }
}

// MARK: - 错误

/// 与 mobile-sync-api 的 `MobileSyncApiErrorCode` 对齐的本地错误码。
enum MobileSyncError: String, Error, Equatable {
    case contractInvalid = "contract_invalid"
    case permissionDenied = "permission_denied"
    case childNotFound = "child_not_found"
    case taskNotFound = "task_not_found"
    case proofNotFound = "proof_not_found"
    case duplicateSubmission = "duplicate_submission"
    case duplicateApproval = "duplicate_approval"
    case evidenceRequired = "evidence_required"
    case unsafePayload = "unsafe_payload"
    case insufficientCredit = "insufficient_credit"
}

// MARK: - 任务枚举（映射 TaskAssignment）

enum MobileSyncTaskCategory: String, Codable, Equatable, CaseIterable {
    case routine
    case learning
    case homework
    case exercise
    case chore
    case creative
    case socialEmotional = "social_emotional"
    case family
}

enum MobileSyncTaskStatus: String, Codable, Equatable {
    case scheduled
    case available
    case inProgress = "in_progress"
    case submitted
    case verified
    case missed
}

enum MobileSyncEvidenceKind: String, Codable, Equatable {
    case none
    case photoRef = "photo_ref"
    case textSummary = "text_summary"
    case quizResult = "quiz_result"
    case deviceSignalRef = "device_signal_ref"
    case parentCheck = "parent_check"
}

enum MobileSyncTaskPriority: String, Codable, Equatable {
    case mustDo = "must_do"
    case recommended
    case optional
    case bonus
}

// MARK: - 其他枚举

enum MobileSyncVisibility: String, Codable, Equatable {
    case `private`
    case family
    case careTeam = "care_team"
    case `public`
}

enum MobileSyncRewardType: String, Codable, Equatable {
    case screenTime = "screen_time"
    case appUnlock = "app_unlock"
    case familyReward = "family_reward"
    case badgeBonus = "badge_bonus"
    case creatorPackBonus = "creator_pack_bonus"
}

/// 奖励会话运行态，映射共享契约 RewardSession.status。
/// 注意：`active` 之外的任何状态对真实/模拟设备都表现为锁定，本壳不在 active 之外解锁。
enum MobileSyncRewardSessionStatus: String, Codable, Equatable {
    case pending
    case active
    case ended
    case failed
    case forceClosed = "force_closed"
}

enum MobileSyncApprovalDecision: String, Codable, Equatable {
    case approved
    case rejected
    case needsRevision = "needs_revision"
}

// MARK: - 视图模型（映射 mobile-sync-api 的 *View）

/// 今日任务视图。
struct MobileSyncTask: Identifiable, Codable, Equatable {
    var clientTaskRef: String
    var childPublicRef: String
    var title: String
    var category: MobileSyncTaskCategory
    var status: MobileSyncTaskStatus
    var plannedFor: String
    var dueAt: String?
    var evidenceRequired: [MobileSyncEvidenceKind]
    var priority: MobileSyncTaskPriority
    var hasSubmittedProof: Bool

    var id: String { clientTaskRef }

    /// 是否需要证据才能提交。
    var requiresEvidence: Bool { !evidenceRequired.contains(.none) }
}

/// 任务提交回执视图。
struct MobileSyncSubmission: Identifiable, Codable, Equatable {
    var clientProofRef: String
    var clientTaskRef: String
    var childPublicRef: String
    var status: String
    var submittedAt: String
    var evidenceSummaryPreview: String

    var id: String { clientProofRef }
}

/// 家长审批结果视图。
struct MobileSyncApproval: Identifiable, Codable, Equatable {
    var clientDecisionRef: String
    var clientProofRef: String
    var clientTaskRef: String
    var childPublicRef: String
    var decision: MobileSyncApprovalDecision
    var reasonCode: String
    var decidedAt: String
    var creditGrantSuggested: Int

    var id: String { clientDecisionRef }
}

/// 成长积分余额快照视图。
struct MobileSyncCreditBalance: Codable, Equatable {
    var childPublicRef: String
    var availableCredits: Int
    var heldCredits: Int
    var spentCredits: Int
    var totalEarnedCredits: Int
    var expiringSoonCredits: Int
    var usableScopes: [String]
    var capturedAt: String
}

/// 奖励会话视图。`deviceCommandQueued` 仅是「命令已排队」标志，不代表真实解锁。
struct MobileSyncRewardSession: Identifiable, Codable, Equatable {
    var clientRewardSessionRef: String
    var childPublicRef: String
    var rewardType: MobileSyncRewardType
    var plannedMinutes: Int
    var status: MobileSyncRewardSessionStatus
    var creditHoldPublicRef: String?
    var deviceCommandQueued: Bool

    var id: String { clientRewardSessionRef }
}

/// 家庭成长动态视图。
struct MobileSyncGrowthFeedItem: Identifiable, Codable, Equatable {
    var clientFeedItemRef: String
    var childPublicRef: String
    var title: String
    var summary: String
    var visibility: MobileSyncVisibility
    var occurredAt: String
    var tags: [String]

    var id: String { clientFeedItemRef }
}
