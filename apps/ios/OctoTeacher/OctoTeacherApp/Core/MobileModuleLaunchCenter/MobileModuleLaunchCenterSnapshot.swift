import Foundation

/// iOS 端「模块化能力中心」只读快照。
///
/// 它把手机端已经落地的任务、成长包、家校学习、家庭荣誉、成长积分奖励和质量门
/// 收拢成一个平台式入口。这里不执行模块动作，只说明谁能看到什么、当前状态如何、
/// 下一步应该去哪个能力页继续。
enum MobileModuleLaunchCenterViewerRole: String, CaseIterable, Equatable {
    case child
    case guardian
    case relative
    case teacher
    case operations

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        case .relative: return "亲友"
        case .teacher: return "老师"
        case .operations: return "运营"
        }
    }
}

enum MobileModuleLaunchCenterStatus: String, Equatable {
    case ready
    case active
    case reviewRequired = "review_required"
    case blocked

    var label: String {
        switch self {
        case .ready: return "可使用"
        case .active: return "进行中"
        case .reviewRequired: return "需复核"
        case .blocked: return "已阻断"
        }
    }
}

enum MobileModuleLaunchGroupKind: String, CaseIterable, Equatable {
    case basicTasks = "basic_tasks"
    case growthPacks = "growth_packs"
    case schoolLearning = "school_learning"
    case familyHonor = "family_honor"
    case creditReward = "credit_reward"
    case platformSync = "platform_sync"
    case platformQuality = "platform_quality"

    var title: String {
        switch self {
        case .basicTasks: return "基础任务"
        case .growthPacks: return "成长包"
        case .schoolLearning: return "家校学习"
        case .familyHonor: return "家庭荣誉"
        case .creditReward: return "成长积分奖励"
        case .platformSync: return "同步复核"
        case .platformQuality: return "平台质量门"
        }
    }
}

enum MobileModuleLaunchModuleKey: String, CaseIterable, Equatable {
    case todayTasks = "today_tasks"
    case growthPackRuntime = "growth_pack_runtime"
    case growthPackExecutionHub = "growth_pack_execution_hub"
    case growthPackMarket = "growth_pack_market"
    case schoolHomework = "school_homework"
    case aiHomeworkGuide = "ai_homework_guide"
    case schoolJointApproval = "school_joint_approval"
    case notificationDigestConsent = "notification_digest_consent"
    case familyStoryline = "family_storyline"
    case honorWall = "honor_wall"
    case creditLedger = "credit_ledger"
    case rewardWindow = "reward_window"
    case appSelectionPolicy = "app_selection_policy"
    case rewardStoreFulfillment = "reward_store_fulfillment"
    case reportsPreview = "reports_preview"
    case onboardingGuide = "onboarding_guide"
    case offlineSyncReview = "offline_sync_review"
    case moduleConfigurationDraft = "module_configuration_draft"
    case releaseGate = "release_gate"
    case familySocialFeedbackEmotionalSafety = "family_social_feedback_emotional_safety"

    var title: String {
        switch self {
        case .todayTasks: return "今日基础任务"
        case .growthPackRuntime: return "成长包运行"
        case .growthPackExecutionHub: return "成长包执行中心"
        case .growthPackMarket: return "成长包安装权益"
        case .schoolHomework: return "学校作业"
        case .aiHomeworkGuide: return "AI 引导学习"
        case .schoolJointApproval: return "家校联合审批"
        case .notificationDigestConsent: return "通知摘要同意"
        case .familyStoryline: return "成长故事线"
        case .honorWall: return "荣誉墙与球星卡"
        case .creditLedger: return "成长积分账本"
        case .rewardWindow: return "成长积分兑换窗口"
        case .appSelectionPolicy: return "娱乐 App 策略预览"
        case .rewardStoreFulfillment: return "奖励库存履约"
        case .reportsPreview: return "成长报告预览"
        case .onboardingGuide: return "章鱼老师 入门"
        case .offlineSyncReview: return "离线同步复核台"
        case .moduleConfigurationDraft: return "家长模块配置草稿"
        case .releaseGate: return "移动端发布质量门"
        case .familySocialFeedbackEmotionalSafety: return "情绪安全中心"
        }
    }
}

enum MobileModuleLaunchFindingCode: String, Equatable {
    case centerOK = "MOBILE_MODULE_CENTER_OK"
    case roleVisibilityApplied = "ROLE_VISIBILITY_APPLIED"
    case adultModuleHiddenFromChild = "ADULT_MODULE_HIDDEN_FROM_CHILD"
    case schoolReviewPending = "SCHOOL_REVIEW_PENDING"
    case familyReviewPending = "FAMILY_REVIEW_PENDING"
    case releaseGateReviewRequired = "RELEASE_GATE_REVIEW_REQUIRED"
    case publicSummaryLeak = "PUBLIC_SUMMARY_LEAK"
    case unsafeInputBlocked = "UNSAFE_INPUT_BLOCKED"
}

enum MobileModuleLaunchSeverity: String, Equatable {
    case ok
    case info
    case warning
    case blocker

    var label: String {
        switch self {
        case .ok: return "正常"
        case .info: return "提示"
        case .warning: return "需关注"
        case .blocker: return "阻断"
        }
    }
}

struct MobileModuleLaunchCenterVisibility: Equatable {
    var viewerRole: MobileModuleLaunchCenterViewerRole
    var canSeeBasicTasks: Bool
    var canSeeGrowthPacks: Bool
    var canSeeSchoolLearning: Bool
    var canSeeFamilyHonor: Bool
    var canSeeCreditReward: Bool
    var canSeePlatformSync: Bool
    var canSeePlatformQuality: Bool

    var visibleGroups: Set<MobileModuleLaunchGroupKind> {
        var groups: Set<MobileModuleLaunchGroupKind> = []
        if canSeeBasicTasks { groups.insert(.basicTasks) }
        if canSeeGrowthPacks { groups.insert(.growthPacks) }
        if canSeeSchoolLearning { groups.insert(.schoolLearning) }
        if canSeeFamilyHonor { groups.insert(.familyHonor) }
        if canSeeCreditReward { groups.insert(.creditReward) }
        if canSeePlatformSync { groups.insert(.platformSync) }
        if canSeePlatformQuality { groups.insert(.platformQuality) }
        return groups
    }
}

struct MobileModuleLaunchModuleCard: Identifiable, Equatable {
    var publicModuleRef: String
    var key: MobileModuleLaunchModuleKey
    var group: MobileModuleLaunchGroupKind
    var title: String
    var detail: String
    var status: MobileModuleLaunchCenterStatus
    var progress: Int
    var actionRequired: Bool
    var routeHint: String
    var visibleToChild: Bool
    var visibleToGuardian: Bool
    var visibleToRelative: Bool
    var visibleToTeacher: Bool
    var visibleToOperations: Bool

    let callsNetwork = false
    let callsAiProvider = false
    let callsLms = false
    let writesSchoolSystem = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let sendsNotification = false
    let writesEntitlement = false
    let createsOrder = false

    var id: String { publicModuleRef }
}

struct MobileModuleLaunchGroup: Identifiable, Equatable {
    var kind: MobileModuleLaunchGroupKind
    var title: String
    var subtitle: String
    var modules: [MobileModuleLaunchModuleCard]

    var id: String { kind.rawValue }
}

struct MobileModuleLaunchNextAction: Identifiable, Equatable {
    var publicActionRef: String
    var title: String
    var detail: String
    var severity: MobileModuleLaunchSeverity
    var actionRequired: Bool

    let writesSystem = false
    let sendsNotification = false

    var id: String { publicActionRef }
}

struct MobileModuleLaunchFinding: Identifiable, Equatable {
    var code: MobileModuleLaunchFindingCode
    var severity: MobileModuleLaunchSeverity
    var message: String
    var publicRef: String

    var id: String { "\(code.rawValue):\(publicRef)" }
}

struct MobileModuleLaunchPublicSummary: Equatable {
    var generatedAt: String
    var viewerRole: MobileModuleLaunchCenterViewerRole
    var status: MobileModuleLaunchCenterStatus
    var visibleGroupCount: Int
    var visibleModuleCount: Int
    var actionRequiredCount: Int
    var averageProgress: Int
    var hiddenInternalModuleCount: Int
    var findingCodes: [MobileModuleLaunchFindingCode]

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
}

struct MobileModuleLaunchSideEffects: Equatable {
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

    var hasTriggeredSideEffect: Bool {
        callsNetwork || callsAiProvider || callsLocalModel || callsLms || writesSchoolSystem
            || writesLedger || grantsCredit || unlocksDevice || sendsNotification || uploadsMedia
            || writesEntitlement || createsOrder
    }
}

struct MobileModuleLaunchCenterSnapshot: Equatable {
    var generatedAt: String
    var viewerRole: MobileModuleLaunchCenterViewerRole
    var status: MobileModuleLaunchCenterStatus
    var headline: String
    var visibility: MobileModuleLaunchCenterVisibility
    var groups: [MobileModuleLaunchGroup]
    var nextActions: [MobileModuleLaunchNextAction]
    var findings: [MobileModuleLaunchFinding]
    var publicSummary: MobileModuleLaunchPublicSummary
    var sideEffects: MobileModuleLaunchSideEffects

    var modules: [MobileModuleLaunchModuleCard] {
        groups.flatMap(\.modules)
    }

    var displayValues: [String] {
        [generatedAt, viewerRole.rawValue, status.rawValue, headline]
            + groups.flatMap { [$0.kind.rawValue, $0.title, $0.subtitle] }
            + modules.flatMap { [$0.publicModuleRef, $0.key.rawValue, $0.group.rawValue, $0.title, $0.detail, $0.status.rawValue, $0.routeHint] }
            + nextActions.flatMap { [$0.publicActionRef, $0.title, $0.detail, $0.severity.rawValue] }
            + findings.flatMap { [$0.code.rawValue, $0.severity.rawValue, $0.message, $0.publicRef] }
            + publicSummary.findingCodes.map(\.rawValue)
    }
}

struct MobileModuleLaunchCenterBuilder {
    var generatedAt = "2026-06-24T16:10:00Z"
    var redactionSalt = "mobile-module-launch-center-ios-v1"

    private static let sensitiveDisplayMarkers = [
        "child:", "family:", "school:", "teacher:", "relative:", "guardian:",
        "task:", "claim:", "proof:", "ledger:", "device:", "order:", "entitlement:",
        "publicref", "provider:", "model:", "transcript", "baseurl", "api_key",
        "apikey", "token", "secret", "qwen", "claude", "openai", "credit amount",
        "成长积分金额", "答案键", "老师私密", "家长私密", "http://", "https://",
        "file://", "/users/", "/volumes/", "192.168."
    ]

    private static let sensitiveDisplayPatterns = [
        #"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"#,
        #"(?i)\b[0-9a-f]{24,}\b"#,
        #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#
    ]

    private static let compactSensitiveMarkers = [
        "apikey", "token", "secret", "sktest", "skproj",
        "publicref", "provider", "model", "transcript", "baseurl",
        "taskid", "claimid", "qwen", "claude", "openai",
        "http", "https", "file", "users", "volumes"
    ]

    func build(
        viewerRole: MobileModuleLaunchCenterViewerRole,
        unsafePayload: [String] = []
    ) -> MobileModuleLaunchCenterSnapshot {
        let visibility = visibility(for: viewerRole)
        if !redacts(unsafePayload) || MobileSyncPayloadGuard.isUnsafe(unsafePayload) {
            return safeFallback(viewerRole: viewerRole, visibility: visibility)
        }

        // These stores and builders are deterministic in-memory fixtures already used
        // by the iOS mock shell. They do not call network, AI, LMS, ledger,
        // notification, device-control, payment, StoreKit, FamilyControls, or cloud
        // runtimes; the module center only reads their already-sanitized summaries.
        let family = LocalFamilyStore()
        let school = SchoolFamilyStore()
        let releaseRole = releaseRole(for: viewerRole)
        let releaseInput = MobileReleaseCandidateGateInput.mock(viewerRole: releaseRole)
        let releaseGate = MobileReleaseCandidateGateBuilder().build(viewerRole: releaseRole, input: releaseInput)
        let familyStorylineReleaseGate = FamilyHonorStorylineConsentBuilder()
            .snapshot(for: familyStorylineRole(for: viewerRole))
            .releaseGate
        let configurationDraft = MobileModuleConfigurationDraftBuilder().build(
            viewerRole: configurationDraftRole(for: viewerRole),
            family: family,
            schoolFamily: school
        )

        let allCards = moduleCards(
            viewerRole: viewerRole,
            visibility: visibility,
            family: family,
            school: school,
            configurationDraft: configurationDraft,
            releaseGate: releaseGate,
            familyStorylineReleaseGate: familyStorylineReleaseGate
        )
        let visibleCards = allCards.filter { isVisible($0, to: viewerRole) }
        let groups = MobileModuleLaunchGroupKind.allCases.compactMap { kind -> MobileModuleLaunchGroup? in
            let modules = visibleCards.filter { $0.group == kind }
            guard !modules.isEmpty else { return nil }
            return MobileModuleLaunchGroup(
                kind: kind,
                title: kind.title,
                subtitle: subtitle(for: kind, viewerRole: viewerRole),
                modules: modules
            )
        }
        let findings = findings(
            viewerRole: viewerRole,
            visibleCards: visibleCards,
            allCards: allCards,
            releaseGate: releaseGate,
            school: school
        )
        let actions = nextActions(from: visibleCards, viewerRole: viewerRole)
        let status = status(cards: visibleCards, findings: findings)
        let snapshot = MobileModuleLaunchCenterSnapshot(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            status: status,
            headline: headline(for: viewerRole, status: status, visibleCards: visibleCards),
            visibility: visibility,
            groups: groups,
            nextActions: actions,
            findings: findings,
            publicSummary: MobileModuleLaunchPublicSummary(
                generatedAt: generatedAt,
                viewerRole: viewerRole,
                status: status,
                visibleGroupCount: groups.count,
                visibleModuleCount: visibleCards.count,
                actionRequiredCount: visibleCards.filter(\.actionRequired).count,
                averageProgress: averageProgress(visibleCards),
                hiddenInternalModuleCount: allCards.count - visibleCards.count,
                findingCodes: findings.map(\.code)
            ),
            sideEffects: MobileModuleLaunchSideEffects()
        )

        return redacts(snapshot.displayValues) ? snapshot : safeFallback(viewerRole: viewerRole, visibility: visibility)
    }

    func redacts(_ values: [String]) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe(values) { return false }
        let joined = values.joined(separator: " ").lowercased()
        if Self.sensitiveDisplayMarkers.contains(where: { joined.contains($0) }) { return false }
        let compact = joined.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
        if Self.compactSensitiveMarkers.contains(where: { compact.contains($0) }) { return false }
        return !Self.sensitiveDisplayPatterns.contains { pattern in
            joined.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func visibility(for role: MobileModuleLaunchCenterViewerRole) -> MobileModuleLaunchCenterVisibility {
        switch role {
        case .child:
            return MobileModuleLaunchCenterVisibility(
                viewerRole: role,
                canSeeBasicTasks: true,
                canSeeGrowthPacks: true,
                canSeeSchoolLearning: true,
                canSeeFamilyHonor: true,
                canSeeCreditReward: true,
                canSeePlatformSync: true,
                canSeePlatformQuality: false
            )
        case .guardian:
            return MobileModuleLaunchCenterVisibility(
                viewerRole: role,
                canSeeBasicTasks: true,
                canSeeGrowthPacks: true,
                canSeeSchoolLearning: true,
                canSeeFamilyHonor: true,
                canSeeCreditReward: true,
                canSeePlatformSync: true,
                canSeePlatformQuality: true
            )
        case .relative:
            return MobileModuleLaunchCenterVisibility(
                viewerRole: role,
                canSeeBasicTasks: false,
                canSeeGrowthPacks: false,
                canSeeSchoolLearning: false,
                canSeeFamilyHonor: true,
                canSeeCreditReward: false,
                canSeePlatformSync: false,
                canSeePlatformQuality: false
            )
        case .teacher:
            return MobileModuleLaunchCenterVisibility(
                viewerRole: role,
                canSeeBasicTasks: false,
                canSeeGrowthPacks: false,
                canSeeSchoolLearning: true,
                canSeeFamilyHonor: false,
                canSeeCreditReward: false,
                canSeePlatformSync: false,
                canSeePlatformQuality: false
            )
        case .operations:
            return MobileModuleLaunchCenterVisibility(
                viewerRole: role,
                canSeeBasicTasks: false,
                canSeeGrowthPacks: true,
                canSeeSchoolLearning: true,
                canSeeFamilyHonor: true,
                // 运营仅能看到奖励库存履约的脱敏安全预览（creditReward 组内），
                // 不进入家庭兑换页，也看不到 creditLedger/rewardWindow 等其它成长积分奖励模块。
                canSeeCreditReward: true,
                canSeePlatformSync: true,
                canSeePlatformQuality: true
            )
        }
    }

    private func moduleCards(
        viewerRole: MobileModuleLaunchCenterViewerRole,
        visibility: MobileModuleLaunchCenterVisibility,
        family: LocalFamilyStore,
        school: SchoolFamilyStore,
        configurationDraft: MobileModuleConfigurationDraftSnapshot,
        releaseGate: MobileReleaseCandidateGateSnapshot,
        familyStorylineReleaseGate: FamilyStorylineReleaseGate
    ) -> [MobileModuleLaunchModuleCard] {
        let activeAssignments = family.assignments.filter { $0.status != .cancelled }
        let approvedTasks = activeAssignments.filter { $0.status == .approved }.count
        let submittedTasks = activeAssignments.filter { $0.status == .submitted }.count
        let taskCount = activeAssignments.count
        let openHomeworks = school.openHomeworks.count
        let settledHomeworks = school.settledHomeworks.count
        let pendingFamily = school.relativeComments.filter { $0.status == .pending }.count
        let honorVisible = school.honorWall.filter { $0.approval == .approved }.count
        let credit = family.creditBalance

        return [
            card(
                .todayTasks,
                group: .basicTasks,
                detail: "今天 \(taskCount) 个基础任务，\(approvedTasks) 个已完成，\(submittedTasks) 个等家长确认。",
                status: submittedTasks > 0 ? .reviewRequired : .active,
                progress: percent(approvedTasks, of: taskCount),
                actionRequired: submittedTasks > 0 && viewerRole == .guardian,
                routeHint: viewerRole == .child ? "去今日任务提交证明" : "去家长端复核任务",
                visible: [.child, .guardian]
            ),
            card(
                .growthPackRuntime,
                group: .growthPacks,
                detail: "成长包按步骤运行，完成后只进入成长积分建议，不自动发放。",
                status: .active,
                progress: percent(family.growthPack.steps.filter { family.progress(for: $0) != .locked }.count, of: family.growthPack.steps.count),
                actionRequired: false,
                routeHint: "查看成长包步骤和证明链",
                visible: [.child, .guardian, .operations]
            ),
            card(
                .growthPackExecutionHub,
                group: .growthPacks,
                detail: viewerRole == .child
                    ? "把作业、测验、资源、创作和奖励下一步放在一起；这里只读，不会自动完成。"
                    : (viewerRole == .operations
                        ? "脱敏执行中心状态：只读说明，不进入家庭内部执行页面。"
                        : "复核作业、测验、资源、创作、量规、荣誉和奖励履约边界。"),
                status: .reviewRequired,
                progress: 74,
                actionRequired: viewerRole == .guardian,
                routeHint: viewerRole == .operations ? "查看执行中心安全预览" : "进入成长包执行中心",
                visible: [.child, .guardian, .operations]
            ),
            card(
                .growthPackMarket,
                group: .growthPacks,
                detail: viewerRole == .child ? "可看到等待家长确认的成长包，不显示价格和权益细节。" : "查看安装授权、退款撤权、年龄门禁和云同步只读状态。",
                status: .reviewRequired,
                progress: 72,
                actionRequired: viewerRole == .guardian || viewerRole == .operations,
                routeHint: "查看成长包权益和云同步桥接",
                visible: [.child, .guardian, .operations]
            ),
            card(
                .schoolHomework,
                group: .schoolLearning,
                detail: "学校作业 \(school.homeworks.count) 份，\(openHomeworks) 份还需孩子处理，\(settledHomeworks) 份已提交或完成。",
                status: openHomeworks > 0 ? .active : .ready,
                progress: percent(settledHomeworks, of: school.homeworks.count),
                actionRequired: openHomeworks > 0 && viewerRole == .child,
                routeHint: viewerRole == .teacher ? "查看老师复核状态" : "查看学校作业",
                visible: [.child, .guardian, .teacher, .operations]
            ),
            card(
                .aiHomeworkGuide,
                group: .schoolLearning,
                detail: viewerRole == .child ? "只给提示、追问和自检清单，不直接给答案。" : "查看 AI 引导、人工复核、LMS 边界和家校收件箱。",
                status: .reviewRequired,
                progress: 76,
                actionRequired: viewerRole == .guardian || viewerRole == .teacher || viewerRole == .operations,
                routeHint: "进入 AI 作业家校收件箱",
                visible: [.child, .guardian, .teacher, .operations]
            ),
            card(
                .schoolJointApproval,
                group: .schoolLearning,
                detail: viewerRole == .child
                    ? "查看老师验证、家长确认和退回重做的安全进度。"
                    : "查看老师验证、家长确认、申诉冻结、离线回滚和成长积分建议的只读联合流程。",
                status: school.homeworks.contains(where: { $0.status == .submitted }) ? .reviewRequired : .active,
                progress: percent(school.settledHomeworks.count, of: school.homeworks.count),
                actionRequired: viewerRole == .guardian || viewerRole == .teacher,
                routeHint: viewerRole == .operations ? "查看联合审批安全预览" : "进入家校联合审批台",
                visible: [.child, .guardian, .teacher, .operations]
            ),
            card(
                .notificationDigestConsent,
                group: .schoolLearning,
                detail: viewerRole == .relative
                    ? "亲友只看家长开放的通知摘要和荣誉提醒，不展示作业答案、原始对话、成长积分或预算。"
                    : "查看家校亲友通知摘要、同意状态、安静窗口和只读证据，不发送通知或写队列。",
                status: pendingFamily > 0 || openHomeworks > 0 ? .reviewRequired : .ready,
                progress: 64,
                actionRequired: (viewerRole == .guardian && pendingFamily > 0) || (viewerRole == .teacher && openHomeworks > 0),
                routeHint: viewerRole == .operations ? "查看通知摘要安全预览" : "进入通知摘要同意中心",
                visible: [.child, .guardian, .relative, .teacher, .operations]
            ),
            card(
                .familyStoryline,
                group: .familyHonor,
                detail: "故事线门禁为\(familyStorylineReleaseGate.status.label)：\(familyStorylineReleaseGate.primaryReason.label)，候选 \(familyStorylineReleaseGate.publishCandidateCount) · 待处理 \(familyStorylineReleaseGate.manualGateCount) · 阻断 \(familyStorylineReleaseGate.blockedCount)。只读预览，不发布、不通知、不发成长积分。",
                status: familyStorylineStatus(familyStorylineReleaseGate.status),
                progress: familyStorylineProgress(familyStorylineReleaseGate.status),
                actionRequired: familyStorylineReleaseGate.status != .ready && viewerRole == .guardian,
                routeHint: "查看成长故事线和同意边界",
                visible: [.child, .guardian, .relative, .operations]
            ),
            card(
                .honorWall,
                group: .familyHonor,
                detail: "荣誉墙已有 \(honorVisible) 个可展示条目，亲友评论先等家长审核。",
                status: pendingFamily > 0 ? .reviewRequired : .ready,
                progress: 70,
                actionRequired: pendingFamily > 0 && viewerRole == .guardian,
                routeHint: "查看荣誉墙、徽章和球星卡",
                visible: [.child, .guardian, .relative, .operations]
            ),
            card(
                .familySocialFeedbackEmotionalSafety,
                group: .familyHonor,
                detail: viewerRole == .child
                    ? "看看亲友的温和鼓励和等家长看的留言；这里只读，不显示审核原因或评分。"
                    : (viewerRole == .relative
                        ? "查看支持性表达指引和待审核 / 已通过的鼓励，不展示孩子私密内容或家庭规则。"
                        : (viewerRole == .operations
                            ? "只看通用主题建议边界，不进入孩子私密内容、家庭规则或审核原因。"
                            : "只读复核亲友鼓励、荣誉墙反馈、日记 / VLOG 连续性和讨论的情绪安全与审核状态。")),
                status: pendingFamily > 0 ? .reviewRequired : .ready,
                progress: 66,
                actionRequired: pendingFamily > 0 && viewerRole == .guardian,
                routeHint: viewerRole == .child ? "看看亲友的鼓励" : "查看情绪安全与审核状态",
                visible: [.child, .guardian, .relative, .operations]
            ),
            card(
                .creditLedger,
                group: .creditReward,
                detail: viewerRole == .child ? "只显示可用和待确认成长积分，不展示账本内部原因。" : "查看成长积分建议、冻结、阻断和退款回滚只读状态。",
                status: credit.pendingMinutes > 0 ? .reviewRequired : .active,
                progress: credit.availableMinutes > 0 ? 82 : 60,
                actionRequired: credit.pendingMinutes > 0 && viewerRole == .guardian,
                routeHint: "查看成长积分账本复核",
                visible: [.child, .guardian]
            ),
            card(
                .rewardWindow,
                group: .creditReward,
                detail: "奖励兑换必须先冻结成长积分，设备失败会释放，不自动保持解锁。",
                status: .ready,
                progress: 80,
                actionRequired: false,
                routeHint: viewerRole == .child ? "去兑换成长积分" : "查看奖励会话状态",
                visible: [.child, .guardian]
            ),
            card(
                .appSelectionPolicy,
                group: .creditReward,
                detail: viewerRole == .child
                    ? "只看哪些娱乐类别会进入奖励窗口；不显示系统标识，也不会直接解锁。"
                    : (viewerRole == .operations
                        ? "脱敏娱乐 App 策略状态：只读查看，不进入家庭内部选择页，也不提交系统策略。"
                        : "只读预览娱乐 App 分组、审批原因和设备控制边界；真实选择仍需 Apple 家长授权。"),
                status: .reviewRequired,
                progress: 72,
                actionRequired: viewerRole == .guardian,
                routeHint: viewerRole == .operations ? "查看娱乐 App 策略安全预览" : "打开娱乐 App 策略预览",
                visible: [.child, .guardian, .operations]
            ),
            card(
                .rewardStoreFulfillment,
                group: .creditReward,
                detail: viewerRole == .child
                    ? "看奖励能不能换、还剩多少；不会真的兑换、不会扣成长积分、不会改娱乐时间。"
                    : (viewerRole == .operations
                        ? "脱敏奖励库存履约状态：只读复核，不进入家庭兑换页面，也不在模块中心兑换。"
                        : "只读复核库存售罄超卖、兑换预留、履约失败和退款回滚建议；不真实兑换、不扣成长积分、不发货、不解锁设备。"),
                status: .reviewRequired,
                progress: 76,
                actionRequired: false,
                routeHint: viewerRole == .child
                    ? "看看奖励商店"
                    : (viewerRole == .operations ? "查看奖励履约安全预览" : "复核奖励库存履约"),
                visible: [.child, .guardian, .operations]
            ),
            card(
                .reportsPreview,
                group: .familyHonor,
                detail: viewerRole == .child
                    ? "回顾本周努力和下一步，不显示家长复核原因或内部记录。"
                    : "只读查看成长报告草稿、待复核事项和风险边界；正式分享仍需后续授权。",
                status: .ready,
                progress: 78,
                actionRequired: false,
                routeHint: "打开成长报告预览",
                visible: [.child, .guardian]
            ),
            card(
                .onboardingGuide,
                group: .platformSync,
                detail: viewerRole == .child
                    ? "快速理解 章鱼老师 今天能做什么；不登录、不申请权限、不写家庭资料。"
                    : (viewerRole == .operations
                        ? "脱敏入门边界预览：只看入口准备状态，不进入家庭内部页面。"
                        : "查看 章鱼老师 入门清单、角色边界和隐私护栏；不创建账号、不请求权限。"),
                status: .ready,
                progress: 84,
                actionRequired: false,
                routeHint: viewerRole == .operations ? "查看入门安全预览" : "打开 章鱼老师 入门",
                visible: [.child, .guardian, .operations]
            ),
            card(
                .offlineSyncReview,
                group: .platformSync,
                detail: viewerRole == .child
                    ? "查看离线动作同步进度；已收到不代表已完成，仍要等家长或老师处理。"
                    : (viewerRole == .operations
                        ? "脱敏入口说明：离线同步复核台只读，不在模块中心重放或落定。"
                        : "查看离线同步状态、逐条结果与冲突回滚摘要；不自动重放、不落定、不写账本、不发成长积分。"),
                status: .active,
                progress: 78,
                actionRequired: false,
                routeHint: viewerRole == .child
                    ? "查看同步进度"
                    : (viewerRole == .operations ? "查看离线同步安全预览" : "进入离线同步复核台"),
                visible: [.child, .guardian, .operations]
            ),
            card(
                .moduleConfigurationDraft,
                group: .platformQuality,
                detail: viewerRole == .operations
                    ? "脱敏模块配置草稿状态：\(configurationDraft.publicSummary.visibleItemCount) 个可见草稿项，只用于发布前检查。"
                    : "预览今日模块组合、时段、学校作业优先级和成长积分预算提醒，不创建任务或发成长积分。",
                status: launchStatus(for: configurationDraft.status),
                progress: configurationDraft.status == .ready ? 82 : 68,
                actionRequired: viewerRole == .guardian && configurationDraft.status != .ready,
                routeHint: viewerRole == .operations ? "查看脱敏草稿安全预览" : "打开家长模块配置草稿",
                visible: [.guardian, .operations]
            ),
            card(
                .releaseGate,
                group: .platformQuality,
                detail: "发布质量门当前为\(releaseGate.status.label)，检查 \(releaseGate.publicSummary.visibleCheckCount) 项，只读不发布。",
                status: releaseGate.status == .blocked ? .blocked : releaseGate.status == .warning ? .reviewRequired : .ready,
                progress: releaseProgress(releaseGate.status),
                actionRequired: releaseGate.publicSummary.actionRequiredCount > 0,
                routeHint: "查看移动端发布质量门",
                visible: [.guardian, .operations]
            )
        ]
    }

    private func card(
        _ key: MobileModuleLaunchModuleKey,
        group: MobileModuleLaunchGroupKind,
        detail: String,
        status: MobileModuleLaunchCenterStatus,
        progress: Int,
        actionRequired: Bool,
        routeHint: String,
        visible: Set<MobileModuleLaunchCenterViewerRole>
    ) -> MobileModuleLaunchModuleCard {
        MobileModuleLaunchModuleCard(
            publicModuleRef: publicRef("module:\(key.rawValue)"),
            key: key,
            group: group,
            title: key.title,
            detail: detail,
            status: status,
            progress: min(100, max(0, progress)),
            actionRequired: actionRequired,
            routeHint: routeHint,
            visibleToChild: visible.contains(.child),
            visibleToGuardian: visible.contains(.guardian),
            visibleToRelative: visible.contains(.relative),
            visibleToTeacher: visible.contains(.teacher),
            visibleToOperations: visible.contains(.operations)
        )
    }

    private func isVisible(_ card: MobileModuleLaunchModuleCard, to role: MobileModuleLaunchCenterViewerRole) -> Bool {
        switch role {
        case .child: return card.visibleToChild
        case .guardian: return card.visibleToGuardian
        case .relative: return card.visibleToRelative
        case .teacher: return card.visibleToTeacher
        case .operations: return card.visibleToOperations
        }
    }

    private func findings(
        viewerRole: MobileModuleLaunchCenterViewerRole,
        visibleCards: [MobileModuleLaunchModuleCard],
        allCards: [MobileModuleLaunchModuleCard],
        releaseGate: MobileReleaseCandidateGateSnapshot,
        school: SchoolFamilyStore
    ) -> [MobileModuleLaunchFinding] {
        var findings: [MobileModuleLaunchFinding] = [
            finding(.centerOK, .ok, "模块中心已按当前视角生成只读入口。")
        ]
        if allCards.count != visibleCards.count {
            findings.append(finding(.roleVisibilityApplied, .info, "已按角色隐藏不应展示的模块。"))
        }
        if viewerRole == .child && !visibleCards.contains(where: { $0.key == .releaseGate }) {
            findings.append(finding(.adultModuleHiddenFromChild, .info, "平台质量门和成人复核模块已从孩子视角隐藏。"))
        }
        if school.homeworks.contains(where: { $0.status == .submitted }) {
            findings.append(finding(.schoolReviewPending, .warning, "存在已提交作业，仍需老师或家长确认。"))
        }
        if school.relativeComments.contains(where: { $0.status == .pending }) {
            findings.append(finding(.familyReviewPending, .warning, "存在亲友评论或荣誉内容等待家长审核。"))
        }
        if releaseGate.status != .ready && (viewerRole == .guardian || viewerRole == .operations) {
            findings.append(finding(.releaseGateReviewRequired, .warning, "移动端发布质量门仍有复核事项。"))
        }
        return findings
    }

    private func nextActions(
        from cards: [MobileModuleLaunchModuleCard],
        viewerRole: MobileModuleLaunchCenterViewerRole
    ) -> [MobileModuleLaunchNextAction] {
        let required = cards.filter(\.actionRequired)
        if required.isEmpty {
            return [
                MobileModuleLaunchNextAction(
                    publicActionRef: publicRef("action:continue"),
                    title: viewerRole == .child ? "继续完成今天的成长任务" : "继续查看模块状态",
                    detail: "所有入口都是只读导航，不会在模块中心直接写系统。",
                    severity: .info,
                    actionRequired: false
                )
            ]
        }
        return required.prefix(4).map { card in
            MobileModuleLaunchNextAction(
                publicActionRef: publicRef("action:\(card.key.rawValue)"),
                title: card.routeHint,
                detail: "\(card.title) 当前为\(card.status.label)，需要在对应模块继续处理。",
                severity: card.status == .blocked ? .blocker : .warning,
                actionRequired: true
            )
        }
    }

    private func status(
        cards: [MobileModuleLaunchModuleCard],
        findings: [MobileModuleLaunchFinding]
    ) -> MobileModuleLaunchCenterStatus {
        if findings.contains(where: { $0.severity == .blocker }) || cards.contains(where: { $0.status == .blocked }) {
            return .blocked
        }
        if cards.contains(where: { $0.actionRequired || $0.status == .reviewRequired }) {
            return .reviewRequired
        }
        if cards.contains(where: { $0.status == .active }) {
            return .active
        }
        return .ready
    }

    private func headline(
        for role: MobileModuleLaunchCenterViewerRole,
        status: MobileModuleLaunchCenterStatus,
        visibleCards: [MobileModuleLaunchModuleCard]
    ) -> String {
        switch role {
        case .child:
            return "这里是你的成长模块地图，\(visibleCards.count) 个入口可继续。"
        case .guardian:
            return "这里是家庭成长平台的模块地图，当前状态：\(status.label)。"
        case .relative:
            return "这里展示亲友可参与和见证的成长模块。"
        case .teacher:
            return "这里展示老师可见的家校学习模块。"
        case .operations:
            return "这里展示运营可复核的脱敏模块状态。"
        }
    }

    private func subtitle(
        for kind: MobileModuleLaunchGroupKind,
        viewerRole: MobileModuleLaunchCenterViewerRole
    ) -> String {
        switch kind {
        case .basicTasks: return "习惯、家务、阅读和运动等基础成长任务。"
        case .growthPacks: return "成长包可学习、练习、证明和等待家长确认。"
        case .schoolLearning: return "学校作业、通知摘要和 AI 引导学习只给提示，不直接给答案。"
        case .familyHonor: return "徽章、球星卡、荣誉墙和故事线先按同意边界展示。"
        case .creditReward: return "成长积分建议和奖励兑换分开处理，模块中心不发放成长积分。"
        case .platformSync:
            return viewerRole == .operations
                ? "脱敏离线同步状态入口，只读不重放、不落定。"
                : "离线动作同步进度和复核入口，不自动重放、不落定。"
        case .platformQuality:
            return viewerRole == .operations ? "脱敏发布候选状态和回滚门禁。" : "家长可查看只读发布质量门。"
        }
    }

    private func releaseRole(for role: MobileModuleLaunchCenterViewerRole) -> MobileReleaseCandidateGateViewerRole {
        switch role {
        case .child, .relative, .teacher: return .child
        case .guardian: return .guardian
        case .operations: return .operations
        }
    }

    private func familyStorylineRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> FamilyHonorStorylineConsentViewerRole {
        switch role {
        case .child: return .child
        case .guardian: return .guardian
        case .relative: return .relative
        case .teacher, .operations: return .publicViewer
        }
    }

    private func configurationDraftRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> MobileModuleConfigurationDraftViewerRole {
        switch role {
        case .child, .relative, .teacher: return .child
        case .guardian: return .guardian
        case .operations: return .operations
        }
    }

    private func launchStatus(
        for draftStatus: MobileModuleConfigurationDraftStatus
    ) -> MobileModuleLaunchCenterStatus {
        switch draftStatus {
        case .ready: return .ready
        case .reviewRequired: return .reviewRequired
        case .blocked: return .blocked
        }
    }

    private func familyStorylineStatus(
        _ status: FamilyStorylineReleaseGateStatus
    ) -> MobileModuleLaunchCenterStatus {
        switch status {
        case .ready: return .ready
        case .manualGate: return .reviewRequired
        case .blocked: return .blocked
        }
    }

    private func safeFallback(
        viewerRole: MobileModuleLaunchCenterViewerRole,
        visibility: MobileModuleLaunchCenterVisibility
    ) -> MobileModuleLaunchCenterSnapshot {
        let finding = finding(.unsafeInputBlocked, .blocker, "模块中心输入包含不安全展示内容，已切换为安全阻断视图。")
        return MobileModuleLaunchCenterSnapshot(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            status: .blocked,
            headline: "模块中心暂时不可展示",
            visibility: visibility,
            groups: [],
            nextActions: [
                MobileModuleLaunchNextAction(
                    publicActionRef: publicRef("action:safe-fallback"),
                    title: "请家长或主控复核模块中心输入",
                    detail: "当前视图未展示任何原始内容。",
                    severity: .blocker,
                    actionRequired: true
                )
            ],
            findings: [finding],
            publicSummary: MobileModuleLaunchPublicSummary(
                generatedAt: generatedAt,
                viewerRole: viewerRole,
                status: .blocked,
                visibleGroupCount: 0,
                visibleModuleCount: 0,
                actionRequiredCount: 1,
                averageProgress: 0,
                hiddenInternalModuleCount: 0,
                findingCodes: [.unsafeInputBlocked]
            ),
            sideEffects: MobileModuleLaunchSideEffects()
        )
    }

    private func finding(
        _ code: MobileModuleLaunchFindingCode,
        _ severity: MobileModuleLaunchSeverity,
        _ message: String
    ) -> MobileModuleLaunchFinding {
        MobileModuleLaunchFinding(
            code: code,
            severity: severity,
            message: message,
            publicRef: publicRef("finding:\(code.rawValue):\(message)")
        )
    }

    private func averageProgress(_ cards: [MobileModuleLaunchModuleCard]) -> Int {
        guard !cards.isEmpty else { return 0 }
        return cards.reduce(0) { $0 + $1.progress } / cards.count
    }

    private func percent(_ done: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(done) / Double(total) * 100).rounded())
    }

    private func releaseProgress(_ status: MobileReleaseCandidateGateStatus) -> Int {
        switch status {
        case .ready: return 100
        case .warning: return 74
        case .blocked: return 20
        }
    }

    private func familyStorylineProgress(_ status: FamilyStorylineReleaseGateStatus) -> Int {
        switch status {
        case .ready: return 94
        case .manualGate: return 82
        case .blocked: return 55
        }
    }

    private func publicRef(_ seed: String) -> String {
        "mlc-\(Self.stableHash("\(redactionSalt):\(seed)"))"
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
