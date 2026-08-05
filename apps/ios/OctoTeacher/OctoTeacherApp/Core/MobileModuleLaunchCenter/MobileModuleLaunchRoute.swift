import Foundation

/// 模块能力中心的本地只读路由。
///
/// 路由只回答“这个模块卡片应该打开哪个本地页面或安全预览”。它不持有真实 ID，
/// 不触发网络、AI、学校系统、账本、通知、支付、设备控制或云端写入。
enum MobileModuleLaunchRouteDestinationKind: String, Equatable, CaseIterable {
    case childTaskList = "child_task_list"
    case basicHabitCheckin = "basic_habit_checkin"
    case guardianTaskReview = "guardian_task_review"
    case growthPackDetail = "growth_pack_detail"
    case growthPackExecutionHub = "growth_pack_execution_hub"
    case growthPackEntitlement = "growth_pack_entitlement"
    case schoolHomework = "school_homework"
    case aiHomeworkInbox = "ai_homework_inbox"
    case schoolJointApproval = "school_joint_approval"
    case notificationDigestConsent = "notification_digest_consent"
    case familyStorylineConsent = "family_storyline_consent"
    case growthDiaryVlogStoryline = "growth_diary_vlog_storyline"
    case familyAchievementDashboard = "family_achievement_dashboard"
    case creditLedgerReview = "credit_ledger_review"
    case rewardRedemption = "reward_redemption"
    case rewardStatus = "reward_status"
    case appSelectionWorkbench = "app_selection_workbench"
    case rewardStoreFulfillment = "reward_store_fulfillment"
    case reportsWorkbench = "reports_workbench"
    case onboardingGuide = "onboarding_guide"
    case offlineSyncReview = "offline_sync_review"
    case moduleConfigurationDraft = "module_configuration_draft"
    case releaseGate = "release_gate"
    case familySocialFeedbackEmotionalSafetyCenter = "family_social_feedback_emotional_safety_center"
    case safePreview = "safe_preview"
}

struct MobileModuleLaunchRoute: Identifiable, Equatable {
    var publicRouteRef: String
    var moduleKey: MobileModuleLaunchModuleKey
    var viewerRole: MobileModuleLaunchCenterViewerRole
    var destinationKind: MobileModuleLaunchRouteDestinationKind
    var title: String
    var subtitle: String
    var allowedRoles: Set<MobileModuleLaunchCenterViewerRole>
    var opensExistingPage: Bool

    let callsNetwork = false
    let callsAiProvider = false
    let callsLocalModel = false
    let callsLms = false
    let writesSchoolSystem = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let sendsNotification = false
    let uploadsMedia = false
    let writesEntitlement = false
    let createsOrder = false

    var id: String { publicRouteRef }

    var hasTriggeredSideEffect: Bool {
        callsNetwork || callsAiProvider || callsLocalModel || callsLms || writesSchoolSystem
            || writesLedger || grantsCredit || unlocksDevice || sendsNotification || uploadsMedia
            || writesEntitlement || createsOrder
    }

    /// 目标页自身是否有角色切换器。
    ///
    /// 从模块能力中心跳入这些页面时应锁定到 `viewerRole` 映射出的单一目标角色，
    /// 避免孩子、亲友或老师在详情页切换到家长/运营视角。
    var supportsDestinationRoleSwitching: Bool {
        switch destinationKind {
        case .growthPackEntitlement,
             .aiHomeworkInbox,
             .schoolJointApproval,
             .notificationDigestConsent,
             .familyStorylineConsent,
             .growthDiaryVlogStoryline,
             .familyAchievementDashboard,
             .appSelectionWorkbench,
             .reportsWorkbench,
             .onboardingGuide,
             .releaseGate,
             .familySocialFeedbackEmotionalSafetyCenter:
            return true
        case .childTaskList,
             .basicHabitCheckin,
             .guardianTaskReview,
             .growthPackDetail,
             .growthPackExecutionHub,
             .schoolHomework,
             .creditLedgerReview,
             .rewardRedemption,
             .rewardStatus,
             .rewardStoreFulfillment,
             .offlineSyncReview,
             .moduleConfigurationDraft,
             .safePreview:
            return false
        }
    }

    /// 模块中心进入目标页时是否必须锁定角色。
    var shouldLockDestinationRole: Bool {
        supportsDestinationRoleSwitching
    }

    var displayValues: [String] {
        [
            publicRouteRef,
            moduleKey.rawValue,
            viewerRole.rawValue,
            destinationKind.rawValue,
            title,
            subtitle
        ] + allowedRoles.map(\.rawValue).sorted()
    }
}

struct MobileModuleLaunchRouteResolver {
    private static let redactionSalt = "mobile-module-launch-route-ios-v1"

    private static let sensitiveMarkers = [
        "child:", "family:", "school:", "teacher:", "relative:", "guardian:",
        "task:", "claim:", "proof:", "ledger:", "device:", "order:", "entitlement:",
        "publicref", "provider:", "model:", "transcript", "baseurl", "api_key",
        "apikey", "token", "secret", "qwen", "claude", "openai", "credit amount",
        "成长积分金额", "答案键", "老师私密", "家长私密", "http://", "https://",
        "file://", "/users/", "/volumes/", "192.168."
    ]

    func routes(for snapshot: MobileModuleLaunchCenterSnapshot) -> [MobileModuleLaunchRoute] {
        snapshot.modules.compactMap { route(for: $0, viewerRole: snapshot.viewerRole) }
    }

    func route(
        for card: MobileModuleLaunchModuleCard,
        viewerRole: MobileModuleLaunchCenterViewerRole
    ) -> MobileModuleLaunchRoute? {
        guard isVisible(card, to: viewerRole) else { return nil }
        return route(for: card.key, viewerRole: viewerRole)
    }

    func route(
        for key: MobileModuleLaunchModuleKey,
        viewerRole: MobileModuleLaunchCenterViewerRole
    ) -> MobileModuleLaunchRoute? {
        guard let config = config(for: key, viewerRole: viewerRole) else { return nil }
        return MobileModuleLaunchRoute(
            publicRouteRef: publicRef("route:\(key.rawValue):\(viewerRole.rawValue):\(config.kind.rawValue)"),
            moduleKey: key,
            viewerRole: viewerRole,
            destinationKind: config.kind,
            title: config.title,
            subtitle: config.subtitle,
            allowedRoles: allowedRoles(for: key),
            opensExistingPage: config.kind != .safePreview
        )
    }

    func redacts(_ routes: [MobileModuleLaunchRoute]) -> Bool {
        let joined = routes.flatMap(\.displayValues).joined(separator: " ").lowercased()
        return !Self.sensitiveMarkers.contains { joined.contains($0) }
    }

    private func config(
        for key: MobileModuleLaunchModuleKey,
        viewerRole: MobileModuleLaunchCenterViewerRole
    ) -> (kind: MobileModuleLaunchRouteDestinationKind, title: String, subtitle: String)? {
        guard allowedRoles(for: key).contains(viewerRole) else { return nil }
        switch key {
        case .todayTasks:
            return viewerRole == .guardian
                ? (.guardianTaskReview, "打开家长批准台", "输入家长 PIN 后处理待确认证明、批准或驳回今日任务。")
                : (.basicHabitCheckin, "打开基础习惯打卡", "查看今日习惯、证明要求、连续天数和离线提示。")
        case .growthPackRuntime:
            if viewerRole == .operations {
                return (.safePreview, "打开成长包运行安全预览", "运营只看脱敏运行说明，不进入家庭内部成长包详情。")
            }
            return (.growthPackDetail, "打开成长包详情", "查看步骤、证明、成长积分预览和申诉时间线。")
        case .growthPackExecutionHub:
            if viewerRole == .operations {
                return (.safePreview, "打开成长包执行中心安全预览", "运营只看脱敏说明，不进入家庭内部执行中心页面。")
            }
            return viewerRole == .guardian
                ? (.growthPackExecutionHub, "打开成长包执行复核中心", "复核作业、测验、资源、创作、量规、荣誉和奖励履约边界。")
                : (.growthPackExecutionHub, "打开成长包执行中心", "查看今天能做什么、下一步和安全提示；不会自动完成任务。")
        case .growthPackMarket:
            return (.growthPackEntitlement, "打开成长包安装权益", "查看市场、安装、退款撤权和云同步只读状态。")
        case .schoolHomework:
            return (.schoolHomework, "打开作业成长包联动", "查看学校作业、成长包任务、联合验证和成长积分建议边界。")
        case .aiHomeworkGuide:
            return (.aiHomeworkInbox, "打开家校作业收件箱", "查看 AI 引导、人工复核和 LMS 边界，不直接给答案。")
        case .schoolJointApproval:
            if viewerRole == .operations {
                return (.safePreview, "打开联合审批安全预览", "运营只看脱敏说明，不进入家庭内部联合审批页面。")
            }
            return (.schoolJointApproval, "打开家校联合审批", "查看老师验证、家长确认、退回、申诉冻结和离线回滚只读流程。")
        case .notificationDigestConsent:
            if viewerRole == .operations {
                return (.safePreview, "打开通知摘要安全预览", "运营只看脱敏说明，不进入家庭内部通知摘要页面。")
            }
            return (.notificationDigestConsent, "打开通知摘要同意中心", "查看家校亲友通知摘要、同意状态、安静窗口和只读证据。")
        case .familyStoryline:
            if viewerRole == .operations {
                return (.safePreview, "打开故事线安全预览", "运营只看脱敏说明，不进入家庭内部故事线页面。")
            }
            return (.growthDiaryVlogStoryline, "打开成长日记与视频故事", "查看日记草稿、成长视频故事、亲友可见片段和家长复核状态。")
        case .honorWall:
            if viewerRole == .operations {
                return (.safePreview, "打开荣誉墙安全预览", "运营只看脱敏说明，不进入家庭内部成就页面。")
            }
            return (.familyAchievementDashboard, "打开荣誉墙与球星卡", "查看徽章、成长球星卡、荣誉墙和亲友参与边界。")
        case .creditLedger:
            return (.creditLedgerReview, "打开成长积分账本复核", "查看成长积分建议、冻结、阻断和退款回滚只读状态。")
        case .rewardWindow:
            return viewerRole == .guardian
                ? (.rewardStatus, "打开奖励会话状态", "查看奖励窗口、冻结和设备回执状态。")
                : (.rewardRedemption, "打开奖励兑换", "孩子可查看兑换入口；设备控制仍由本地奖励会话保护。")
        case .appSelectionPolicy:
            if viewerRole == .operations {
                return (.safePreview, "打开娱乐 App 策略安全预览", "运营只看脱敏说明，不进入家庭内部选择页，也不提交系统策略。")
            }
            return (.appSelectionWorkbench, "打开娱乐 App 策略预览", "查看娱乐类别、家长确认、年龄边界和系统控制未接入状态。")
        case .rewardStoreFulfillment:
            if viewerRole == .operations {
                return (.safePreview, "打开奖励库存履约安全预览", "运营只看脱敏库存履约状态，不进入家庭兑换页面。")
            }
            return viewerRole == .guardian
                ? (.rewardStoreFulfillment, "打开奖励库存履约复核", "只读复核库存售罄超卖、兑换预留、履约失败和退款回滚建议。")
                : (.rewardStoreFulfillment, "打开奖励商店", "看奖励能不能换、还剩多少；不会真的兑换或扣成长积分。")
        case .reportsPreview:
            return (.reportsWorkbench, "打开成长报告预览", "查看任务、学校、荣誉、成长积分和节奏的本地只读报告。")
        case .onboardingGuide:
            if viewerRole == .operations {
                return (.safePreview, "打开入门边界安全预览", "运营只看脱敏入口说明，不进入家庭内部入门页。")
            }
            return (.onboardingGuide, "打开 章鱼老师 入门", "查看角色入口、准备清单和隐私护栏；不登录、不申请权限。")
        case .offlineSyncReview:
            if viewerRole == .operations {
                return (.safePreview, "打开离线同步安全预览", "运营只看脱敏说明，不进入离线同步复核台。")
            }
            return viewerRole == .guardian
                ? (.offlineSyncReview, "打开离线同步复核台", "查看同步状态、逐条结果与冲突回滚摘要；不自动重放、不落定。")
                : (.offlineSyncReview, "打开同步进度", "查看离线动作同步进度；已收到不代表已完成，仍要等家长或老师处理。")
        case .moduleConfigurationDraft:
            if viewerRole == .operations {
                return (.safePreview, "打开模块配置草稿安全预览", "运营只看脱敏草稿状态，不进入家庭内部配置页面。")
            }
            return (.moduleConfigurationDraft, "打开家长模块配置草稿", "预览今日模块组合、时段、学校作业优先级和成长积分预算提醒。")
        case .releaseGate:
            return (.releaseGate, "打开移动端发布质量门", "查看本地发布候选检查和回滚门禁。")
        case .familySocialFeedbackEmotionalSafety:
            switch viewerRole {
            case .child:
                return (.familySocialFeedbackEmotionalSafetyCenter, "打开情绪安全中心", "看看亲友的温和鼓励和等家长看的留言；不显示审核原因或评分。")
            case .relative:
                return (.familySocialFeedbackEmotionalSafetyCenter, "打开情绪安全表达指引", "查看支持性表达指引和待审核 / 已通过的鼓励，不看孩子私密内容或家庭规则。")
            case .operations:
                return (.familySocialFeedbackEmotionalSafetyCenter, "打开情绪安全主题边界", "只看通用主题建议边界，不进入孩子私密内容、家庭规则或审核原因。")
            case .guardian, .teacher:
                return (.familySocialFeedbackEmotionalSafetyCenter, "打开情绪安全复核中心", "只读复核亲友鼓励、荣誉墙反馈、日记 / VLOG 连续性和讨论的情绪安全与审核状态。")
            }
        }
    }

    private func allowedRoles(for key: MobileModuleLaunchModuleKey) -> Set<MobileModuleLaunchCenterViewerRole> {
        switch key {
        case .todayTasks:
            return [.child, .guardian]
        case .growthPackRuntime, .growthPackExecutionHub, .growthPackMarket:
            return [.child, .guardian, .operations]
        case .schoolHomework, .aiHomeworkGuide, .schoolJointApproval:
            return [.child, .guardian, .teacher, .operations]
        case .notificationDigestConsent:
            return [.child, .guardian, .relative, .teacher, .operations]
        case .familyStoryline, .honorWall:
            return [.child, .guardian, .relative, .operations]
        case .familySocialFeedbackEmotionalSafety:
            // 孩子 / 家长 / 亲友 / 专家（由运营视角代表平台专家）可发现情绪安全中心；
            // 老师属于学校侧，不进入家庭社交反馈情绪安全入口。
            return [.child, .guardian, .relative, .operations]
        case .creditLedger, .rewardWindow:
            return [.child, .guardian]
        case .appSelectionPolicy:
            return [.child, .guardian, .operations]
        case .rewardStoreFulfillment:
            return [.child, .guardian, .operations]
        case .reportsPreview:
            return [.child, .guardian]
        case .onboardingGuide:
            return [.child, .guardian, .operations]
        case .offlineSyncReview:
            return [.child, .guardian, .operations]
        case .moduleConfigurationDraft, .releaseGate:
            return [.guardian, .operations]
        }
    }

    private func isVisible(
        _ card: MobileModuleLaunchModuleCard,
        to role: MobileModuleLaunchCenterViewerRole
    ) -> Bool {
        switch role {
        case .child: return card.visibleToChild
        case .guardian: return card.visibleToGuardian
        case .relative: return card.visibleToRelative
        case .teacher: return card.visibleToTeacher
        case .operations: return card.visibleToOperations
        }
    }

    private func publicRef(_ seed: String) -> String {
        "mlr-\(Self.stableHash("\(Self.redactionSalt):\(seed)"))"
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
