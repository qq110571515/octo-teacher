import Foundation

/// iOS 端「移动平台总览快照」。
///
/// 对齐控制台 B34 mobile-platform-aggregate-snapshot-contract 的手机消费语义：
/// 把今日任务、成长包、学校成长积分、成长积分/奖励、家庭成就、待审核和离线同步聚合成
/// 一个角色感知、脱敏、无副作用的平台仪表盘快照。
enum MobilePlatformAggregateViewerRole: String, Equatable, CaseIterable {
    case child
    case guardian
    case relative
    case teacher

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        case .relative: return "亲友"
        case .teacher: return "老师"
        }
    }
}

enum MobilePlatformAggregateStatus: String, Equatable {
    case ready
    case reviewRequired = "review_required"
    case offlineConflict = "offline_conflict"
    case blocked
    case privateOnly = "private_only"

    var label: String {
        switch self {
        case .ready: return "可继续"
        case .reviewRequired: return "等待复核"
        case .offlineConflict: return "离线冲突"
        case .blocked: return "已阻断"
        case .privateOnly: return "仅家庭可见"
        }
    }
}

enum MobilePlatformAggregateModuleKind: String, Equatable, CaseIterable {
    case todayTasks = "today_tasks"
    case growthPack = "growth_pack"
    case schoolHomework = "school_homework"
    case creditReward = "credit_reward"
    case familyAchievement = "family_achievement"
    case pendingReview = "pending_review"
    case offlineSync = "offline_sync"
    case risk

    var label: String {
        switch self {
        case .todayTasks: return "今日任务"
        case .growthPack: return "成长包"
        case .schoolHomework: return "学校成长积分"
        case .creditReward: return "成长积分与奖励"
        case .familyAchievement: return "家庭成就"
        case .pendingReview: return "审批收件箱"
        case .offlineSync: return "离线同步"
        case .risk: return "风险"
        }
    }
}

enum MobilePlatformAggregateRiskSource: String, Equatable {
    case growthPack = "growth_pack"
    case schoolHomework = "school_homework"
    case familyAchievement = "family_achievement"
    case creditReward = "credit_reward"
    case offlineSync = "offline_sync"
    case roleBoundary = "role_boundary"

    var label: String {
        switch self {
        case .growthPack: return "成长包"
        case .schoolHomework: return "学校"
        case .familyAchievement: return "家庭成就"
        case .creditReward: return "成长积分奖励"
        case .offlineSync: return "离线同步"
        case .roleBoundary: return "角色边界"
        }
    }
}

enum MobilePlatformAggregateFindingCode: String, Equatable {
    case platformSnapshotOK = "PLATFORM_SNAPSHOT_OK"
    case roleVisibilityApplied = "ROLE_VISIBILITY_APPLIED"
    case upstreamBlocked = "UPSTREAM_BLOCKED"
    case pendingReviewActive = "PENDING_REVIEW_ACTIVE"
    case offlineSyncActive = "OFFLINE_SYNC_ACTIVE"
    case creditRewardNotUsable = "CREDIT_REWARD_NOT_USABLE"
    case publicOrRelativePrivateLeakBlocked = "PUBLIC_OR_RELATIVE_PRIVATE_LEAK_BLOCKED"
    case publicSummaryLeak = "PUBLIC_SUMMARY_LEAK"
}

enum MobilePlatformAggregateSeverity: String, Equatable {
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

struct MobilePlatformAggregateFinding: Identifiable, Equatable {
    var code: MobilePlatformAggregateFindingCode
    var severity: MobilePlatformAggregateSeverity
    var message: String
    var publicRef: String

    var id: String { "\(code.rawValue):\(publicRef)" }
}

struct MobilePlatformAggregateRiskFlag: Identifiable, Equatable {
    var publicRiskRef: String
    var source: MobilePlatformAggregateRiskSource
    var code: String
    var severity: MobilePlatformAggregateSeverity
    var visibleToChild: Bool

    var id: String { publicRiskRef }
}

struct MobilePlatformAggregateHeader: Equatable {
    var viewerRole: MobilePlatformAggregateViewerRole
    var status: MobilePlatformAggregateStatus
    var generatedAt: String
    var childPublicRefs: [String]
}

struct MobilePlatformAggregateTodayTask: Identifiable, Equatable {
    var publicTaskRef: String
    var title: String
    var category: String
    var status: String
    var priority: String
    var actionRequired: Bool
    var visibleToChild: Bool

    var id: String { publicTaskRef }
}

struct MobilePlatformAggregateModuleCard: Identifiable, Equatable {
    var publicCardRef: String
    var kind: MobilePlatformAggregateModuleKind
    var title: String
    var subtitle: String
    var statusLabel: String
    var metricLabel: String
    var actionRequired: Bool
    var visible: Bool

    var id: String { publicCardRef }
}

struct MobilePlatformAggregateGrowthPackSummary: Equatable {
    var visible: Bool
    var status: GrowthPackMobileDetailStatus
    var taskCount: Int
    var proofRequirementCount: Int
    var availableCreditPreviewCount: Int
    var nextActionCount: Int
}

struct MobilePlatformAggregateGrowthPackInstallSummary: Equatable {
    var visible: Bool
    var visiblePackCount: Int
    var installableCount: Int
    var installedCount: Int
    var pendingGuardianCount: Int
    var frozenCount: Int
    var blockedCount: Int
    var needsGuardianAttentionCount: Int

    let chargesPayment = false
    let createsOrder = false
    let writesMarketplace = false
    let writesEntitlement = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let callsCloud = false
    let callsAi = false
    let writesSchoolSystem = false

    static let empty = MobilePlatformAggregateGrowthPackInstallSummary(
        visible: false,
        visiblePackCount: 0,
        installableCount: 0,
        installedCount: 0,
        pendingGuardianCount: 0,
        frozenCount: 0,
        blockedCount: 0,
        needsGuardianAttentionCount: 0
    )
}

struct MobilePlatformAggregateSchoolSummary: Equatable {
    var visible: Bool
    var status: SchoolGrowthCreditSnapshotStatus
    var assignmentCount: Int
    var submittedCount: Int
    var teacherVerifiedCount: Int
    var guardianConfirmedCount: Int
    var usableCreditPreviewCount: Int
    var canSeeTeacherVerification: Bool
    var canSeeGuardianConfirmation: Bool
}

struct MobilePlatformAggregateCreditRewardSummary: Equatable {
    var visible: Bool
    var proposalCount: Int
    var proposedCount: Int
    var reviewRequiredCount: Int
    var blockedCount: Int
    var duplicateCount: Int
    var totalPreviewAmount: Int

    let writesLedger = false
    let unlocksDevice = false
}

struct MobilePlatformAggregateFamilyAchievementSummary: Equatable {
    var visible: Bool
    var status: FamilyAchievementSnapshotStatus
    var achievementCount: Int
    var publicReadyCount: Int
    var reviewRequiredCount: Int
    var relativeParticipationVisible: Bool
    var pendingRelativeCommentCount: Int
}

struct MobilePlatformAggregatePendingReviewSummary: Equatable {
    var visible: Bool
    var actionRequiredCount: Int
    var guardianReviewCount: Int
    var teacherReviewCount: Int
    var relativeReviewCount: Int
    var appealCount: Int
}

struct MobilePlatformAggregateOfflineSyncSummary: Equatable {
    var visible: Bool
    var cardCount: Int
    var urgentCount: Int
    var conflictCount: Int
    var rollbackRequiredCount: Int

    let sendsNotification = false
    let writesTask = false
    let writesCredit = false
    let writesDevice = false
}

struct MobilePlatformAggregateRoleVisibility: Equatable {
    var viewerRole: MobilePlatformAggregateViewerRole
    var canSeeTodayTasks: Bool
    var canSeeGrowthPack: Bool
    var canSeeSchoolHomework: Bool
    var canSeeCreditRewards: Bool
    var canSeeFamilyAchievements: Bool
    var canSeePendingReview: Bool
    var canSeeOfflineSync: Bool
    var canSeePrivateProof: Bool
    var canSeeAppealDetails: Bool
}

struct MobilePlatformAggregateNextAction: Identifiable, Equatable {
    enum Severity: String, Equatable {
        case info
        case warning
        case urgent

        var label: String {
            switch self {
            case .info: return "提示"
            case .warning: return "需处理"
            case .urgent: return "紧急"
            }
        }
    }

    var publicActionRef: String
    var source: MobilePlatformAggregateRiskSource
    var kind: String
    var title: String
    var severity: Severity
    var actionRequired: Bool
    var visibleToChild: Bool

    var id: String { publicActionRef }
}

struct MobilePlatformAggregatePublicSummary: Equatable {
    var generatedAt: String
    var viewerRole: MobilePlatformAggregateViewerRole
    var status: MobilePlatformAggregateStatus
    var todayTaskCount: Int
    var visibleModuleCount: Int
    var schoolAssignmentCount: Int
    var familyAchievementCount: Int
    var creditProposalCount: Int
    var growthPackInstalledCount: Int
    var growthPackInstallAttentionCount: Int
    var pendingReviewCount: Int
    var offlineConflictCount: Int
    var riskCount: Int
    var findingCodes: [MobilePlatformAggregateFindingCode]

    let writesLedger = false
    let modifiesTaskState = false
    let modifiesHomework = false
    let writesSchoolHomework = false
    let grantsBadge = false
    let updatesAbilityCard = false
    let publishesHonorWall = false
    let sendsNotification = false
    let notifiesRelatives = false
    let unlocksDevice = false
    let createsOrder = false
    let writesMarketplace = false
    let writesEntitlement = false
    let callsCloud = false
    let uploadsMedia = false
    let uploadsAttachment = false
    let callsSchoolSystem = false
    let usesAiToAnswer = false
}

struct MobilePlatformAggregateSnapshot: Equatable {
    var generatedAt: String
    var header: MobilePlatformAggregateHeader
    var todayTasks: [MobilePlatformAggregateTodayTask]
    var moduleCards: [MobilePlatformAggregateModuleCard]
    var growthPack: MobilePlatformAggregateGrowthPackSummary
    var growthPackInstall: MobilePlatformAggregateGrowthPackInstallSummary
    var schoolHomework: MobilePlatformAggregateSchoolSummary
    var creditRewards: MobilePlatformAggregateCreditRewardSummary
    var familyAchievements: MobilePlatformAggregateFamilyAchievementSummary
    var pendingReview: MobilePlatformAggregatePendingReviewSummary
    var offlineSync: MobilePlatformAggregateOfflineSyncSummary
    var roleVisibility: MobilePlatformAggregateRoleVisibility
    var nextActions: [MobilePlatformAggregateNextAction]
    var riskFlags: [MobilePlatformAggregateRiskFlag]
    var findings: [MobilePlatformAggregateFinding]
    var publicSummary: MobilePlatformAggregatePublicSummary
}

struct MobilePlatformAggregateSnapshotBuilder {
    var generatedAt: String = "2026-06-24T08:00:00Z"
    var redactionSalt: String = "mobile-platform-aggregate-ios-v1"

    func build(
        viewerRole: MobilePlatformAggregateViewerRole,
        mobileSnapshot: MobileSyncSnapshot = MobileSyncClient.makeMockOrEmpty().snapshot,
        familyAchievement: FamilyAchievementSnapshotDashboard,
        growthPack: GrowthPackMobileDetailSnapshot,
        schoolCredit: SchoolGrowthCreditSnapshot,
        offlineStatus: MobileOfflinePublicStatus = .clean,
        offlineReport: MobileOfflineReplayReport = .empty,
        creditSettlement: MobileCreditSettlementReport = .empty,
        growthPackInstall: GrowthPackInstallSnapshot? = nil
    ) -> MobilePlatformAggregateSnapshot {
        let visibility = roleVisibility(for: viewerRole)
        let installSnapshot = growthPackInstall ?? GrowthPackInstallEntitlementBuilder().build(viewerRole: installRole(viewerRole))
        if hasUnsafeInput(
            mobileSnapshot: mobileSnapshot,
            familyAchievement: familyAchievement,
            growthPack: growthPack,
            growthPackInstall: installSnapshot,
            schoolCredit: schoolCredit,
            creditSettlement: creditSettlement
        ) {
            return safeFallback(viewerRole: viewerRole, visibility: visibility)
        }

        let tasks = mapTodayTasks(
            viewerRole: viewerRole,
            visibility: visibility,
            mobileSnapshot: mobileSnapshot,
            growthPack: growthPack
        )
        let growthSummary = mapGrowthPack(growthPack, visibility: visibility)
        let growthInstallSummary = mapGrowthPackInstall(installSnapshot, visibility: visibility)
        let schoolSummary = mapSchool(schoolCredit, visibility: visibility)
        let creditSummary = mapCreditRewards(creditSettlement, visibility: visibility)
        let familySummary = mapFamilyAchievement(familyAchievement, viewerRole: viewerRole)
        let pendingSummary = mapPendingReview(
            viewerRole: viewerRole,
            visibility: visibility,
            growthPack: growthPack,
            growthPackInstall: growthInstallSummary,
            schoolCredit: schoolCredit,
            familyAchievement: familyAchievement
        )
        let offlineSummary = mapOffline(
            viewerRole: viewerRole,
            visibility: visibility,
            status: offlineStatus,
            report: offlineReport
        )
        let risks = riskFlags(
            viewerRole: viewerRole,
            visibility: visibility,
            familyAchievement: familyAchievement,
            growthPack: growthPack,
            growthPackInstall: growthInstallSummary,
            schoolCredit: schoolCredit,
            offlineSummary: offlineSummary,
            creditSettlement: creditSettlement
        )
        let aggregateFindings = findings(
            viewerRole: viewerRole,
            risks: risks,
            pendingReview: pendingSummary,
            offline: offlineSummary,
            creditSettlement: creditSettlement,
            visibility: visibility
        )
        let status = statusFor(
            viewerRole: viewerRole,
            risks: risks,
            pendingReview: pendingSummary,
            offline: offlineSummary,
            familySummary: familySummary
        )
        let header = MobilePlatformAggregateHeader(
            viewerRole: viewerRole,
            status: status,
            generatedAt: generatedAt,
            childPublicRefs: childRefs(
                viewerRole: viewerRole,
                visibility: visibility,
                mobileSnapshot: mobileSnapshot,
                growthPack: growthPack,
                growthPackInstall: installSnapshot,
                schoolCredit: schoolCredit,
                familyAchievement: familyAchievement
            )
        )
        let cards = moduleCards(
            growthPack: growthSummary,
            growthPackInstall: growthInstallSummary,
            school: schoolSummary,
            credit: creditSummary,
            family: familySummary,
            pending: pendingSummary,
            offline: offlineSummary,
            todayTaskCount: tasks.count,
            riskCount: risks.count
        )
        let actions = nextActions(
            viewerRole: viewerRole,
            visibility: visibility,
            growthPack: growthPack,
            growthPackInstall: growthInstallSummary,
            schoolCredit: schoolCredit,
            familyAchievement: familyAchievement,
            offline: offlineSummary
        )
        let base = MobilePlatformAggregateSnapshot(
            generatedAt: generatedAt,
            header: header,
            todayTasks: tasks,
            moduleCards: cards,
            growthPack: growthSummary,
            growthPackInstall: growthInstallSummary,
            schoolHomework: schoolSummary,
            creditRewards: creditSummary,
            familyAchievements: familySummary,
            pendingReview: pendingSummary,
            offlineSync: offlineSummary,
            roleVisibility: visibility,
            nextActions: actions,
            riskFlags: risks,
            findings: aggregateFindings,
            publicSummary: publicSummary(
                generatedAt: generatedAt,
                viewerRole: viewerRole,
                status: status,
                todayTasks: tasks,
                cards: cards,
                growthPackInstall: growthInstallSummary,
                school: schoolSummary,
                family: familySummary,
                credit: creditSummary,
                pending: pendingSummary,
                offline: offlineSummary,
                risks: risks,
                findings: aggregateFindings
            )
        )

        return redacts(base) ? base : safeFallback(viewerRole: viewerRole, visibility: visibility)
    }

    func redacts(_ snapshot: MobilePlatformAggregateSnapshot) -> Bool {
        let values = displayValues(snapshot)
        if MobileSyncPayloadGuard.isUnsafe(values) { return false }
        return !containsAggregateSensitivePayload(values)
    }

    // MARK: - Visibility

    private func installRole(_ role: MobilePlatformAggregateViewerRole) -> GrowthPackInstallViewerRole {
        switch role {
        case .child:
            return .child
        case .guardian:
            return .guardian
        case .relative, .teacher:
            return .relative
        }
    }

    private func roleVisibility(for role: MobilePlatformAggregateViewerRole) -> MobilePlatformAggregateRoleVisibility {
        switch role {
        case .child:
            return MobilePlatformAggregateRoleVisibility(
                viewerRole: role,
                canSeeTodayTasks: true,
                canSeeGrowthPack: true,
                canSeeSchoolHomework: true,
                canSeeCreditRewards: false,
                canSeeFamilyAchievements: true,
                canSeePendingReview: false,
                canSeeOfflineSync: true,
                canSeePrivateProof: false,
                canSeeAppealDetails: false
            )
        case .guardian:
            return MobilePlatformAggregateRoleVisibility(
                viewerRole: role,
                canSeeTodayTasks: true,
                canSeeGrowthPack: true,
                canSeeSchoolHomework: true,
                canSeeCreditRewards: true,
                canSeeFamilyAchievements: true,
                canSeePendingReview: true,
                canSeeOfflineSync: true,
                canSeePrivateProof: true,
                canSeeAppealDetails: true
            )
        case .relative:
            return MobilePlatformAggregateRoleVisibility(
                viewerRole: role,
                canSeeTodayTasks: false,
                canSeeGrowthPack: false,
                canSeeSchoolHomework: false,
                canSeeCreditRewards: false,
                canSeeFamilyAchievements: true,
                canSeePendingReview: false,
                canSeeOfflineSync: false,
                canSeePrivateProof: false,
                canSeeAppealDetails: false
            )
        case .teacher:
            return MobilePlatformAggregateRoleVisibility(
                viewerRole: role,
                canSeeTodayTasks: true,
                canSeeGrowthPack: true,
                canSeeSchoolHomework: true,
                canSeeCreditRewards: false,
                canSeeFamilyAchievements: false,
                canSeePendingReview: true,
                canSeeOfflineSync: false,
                canSeePrivateProof: false,
                canSeeAppealDetails: true
            )
        }
    }

    // MARK: - Mapping

    private func mapTodayTasks(
        viewerRole: MobilePlatformAggregateViewerRole,
        visibility: MobilePlatformAggregateRoleVisibility,
        mobileSnapshot: MobileSyncSnapshot,
        growthPack: GrowthPackMobileDetailSnapshot
    ) -> [MobilePlatformAggregateTodayTask] {
        guard visibility.canSeeTodayTasks else { return [] }
        if viewerRole == .child || viewerRole == .guardian {
            let plannedDate = String(mobileSnapshot.generatedAt.prefix(10))
            return mobileSnapshot.tasks
                .filter { $0.plannedFor == plannedDate }
                .map { task in
                    MobilePlatformAggregateTodayTask(
                        publicTaskRef: publicRef("mpa-task", task.clientTaskRef),
                        title: task.title,
                        category: categoryLabel(task.category),
                        status: taskStatusLabel(task.status),
                        priority: priorityLabel(task.priority),
                        actionRequired: isActionable(task.status),
                        visibleToChild: true
                    )
                }
        }

        return growthPack.tasks.prefix(6).map { task in
            MobilePlatformAggregateTodayTask(
                publicTaskRef: publicRef("mpa-task", task.publicTaskRef),
                title: task.title,
                category: task.category,
                status: task.status.label,
                priority: "\(task.priority)",
                actionRequired: task.status == .waitingReview && viewerRole == .teacher,
                visibleToChild: true
            )
        }
    }

    private func mapGrowthPack(
        _ snapshot: GrowthPackMobileDetailSnapshot,
        visibility: MobilePlatformAggregateRoleVisibility
    ) -> MobilePlatformAggregateGrowthPackSummary {
        guard visibility.canSeeGrowthPack else {
            return MobilePlatformAggregateGrowthPackSummary(
                visible: false,
                status: snapshot.header.status,
                taskCount: 0,
                proofRequirementCount: 0,
                availableCreditPreviewCount: 0,
                nextActionCount: 0
            )
        }
        return MobilePlatformAggregateGrowthPackSummary(
            visible: true,
            status: snapshot.header.status,
            taskCount: snapshot.tasks.count,
            proofRequirementCount: visibility.canSeePrivateProof ? snapshot.proofRequirements.count : 0,
            availableCreditPreviewCount: visibility.canSeeCreditRewards ? snapshot.publicSummary.availableCreditPreviewCount : 0,
            nextActionCount: snapshot.nextActions.filter { visibility.viewerRole != .child || $0.visibleToChild }.count
        )
    }

    private func mapGrowthPackInstall(
        _ snapshot: GrowthPackInstallSnapshot,
        visibility: MobilePlatformAggregateRoleVisibility
    ) -> MobilePlatformAggregateGrowthPackInstallSummary {
        guard visibility.canSeeGrowthPack, visibility.viewerRole == .child || visibility.viewerRole == .guardian else {
            return .empty
        }

        let decisions = snapshot.decisions.filter { $0.state != .hidden }
        let pending = decisions.filter { $0.state == .pendingGuardianConfirmation }.count
        let frozen = decisions.filter { $0.state == .frozen }.count
        let blocked = decisions.filter { $0.state == .blocked }.count
        return MobilePlatformAggregateGrowthPackInstallSummary(
            visible: true,
            visiblePackCount: decisions.count,
            installableCount: decisions.filter { $0.state == .installable }.count,
            installedCount: decisions.filter { $0.state == .installed }.count,
            pendingGuardianCount: pending,
            frozenCount: frozen,
            blockedCount: blocked,
            needsGuardianAttentionCount: pending + frozen + blocked
        )
    }

    private func mapSchool(
        _ snapshot: SchoolGrowthCreditSnapshot,
        visibility: MobilePlatformAggregateRoleVisibility
    ) -> MobilePlatformAggregateSchoolSummary {
        guard visibility.canSeeSchoolHomework else {
            return MobilePlatformAggregateSchoolSummary(
                visible: false,
                status: snapshot.header.status,
                assignmentCount: 0,
                submittedCount: 0,
                teacherVerifiedCount: 0,
                guardianConfirmedCount: 0,
                usableCreditPreviewCount: 0,
                canSeeTeacherVerification: false,
                canSeeGuardianConfirmation: false
            )
        }
        let canSeeTeacher = visibility.viewerRole == .guardian || visibility.viewerRole == .teacher
        let canSeeGuardian = visibility.viewerRole == .guardian
        return MobilePlatformAggregateSchoolSummary(
            visible: true,
            status: snapshot.header.status,
            assignmentCount: snapshot.assignments.count,
            submittedCount: snapshot.assignments.filter { $0.status != .assigned }.count,
            teacherVerifiedCount: canSeeTeacher
                ? snapshot.assignments.filter { $0.status == .teacherVerified || $0.status == .guardianConfirmed }.count
                : 0,
            guardianConfirmedCount: canSeeGuardian
                ? snapshot.assignments.filter { $0.status == .guardianConfirmed }.count
                : 0,
            usableCreditPreviewCount: visibility.canSeeCreditRewards ? snapshot.publicSummary.usableCreditPreviewCount : 0,
            canSeeTeacherVerification: canSeeTeacher,
            canSeeGuardianConfirmation: canSeeGuardian
        )
    }

    private func mapCreditRewards(
        _ report: MobileCreditSettlementReport,
        visibility: MobilePlatformAggregateRoleVisibility
    ) -> MobilePlatformAggregateCreditRewardSummary {
        guard visibility.canSeeCreditRewards else {
            return MobilePlatformAggregateCreditRewardSummary(
                visible: false,
                proposalCount: 0,
                proposedCount: 0,
                reviewRequiredCount: 0,
                blockedCount: 0,
                duplicateCount: 0,
                totalPreviewAmount: 0
            )
        }
        return MobilePlatformAggregateCreditRewardSummary(
            visible: true,
            proposalCount: report.publicSummary.proposalCount,
            proposedCount: report.publicSummary.proposedCount,
            reviewRequiredCount: report.publicSummary.reviewRequiredCount,
            blockedCount: report.publicSummary.blockedCount,
            duplicateCount: report.publicSummary.duplicateCount,
            totalPreviewAmount: report.publicSummary.totalProposedAmount
        )
    }

    private func mapFamilyAchievement(
        _ dashboard: FamilyAchievementSnapshotDashboard,
        viewerRole: MobilePlatformAggregateViewerRole
    ) -> MobilePlatformAggregateFamilyAchievementSummary {
        if viewerRole == .teacher {
            return MobilePlatformAggregateFamilyAchievementSummary(
                visible: false,
                status: dashboard.status,
                achievementCount: 0,
                publicReadyCount: 0,
                reviewRequiredCount: 0,
                relativeParticipationVisible: false,
                pendingRelativeCommentCount: 0
            )
        }
        let isGuardian = viewerRole == .guardian
        let isRelative = viewerRole == .relative
        let achievementCount: Int
        if isGuardian {
            achievementCount = dashboard.publicSummary.achievementCount
        } else if isRelative {
            achievementCount = dashboard.publicSummary.publicReadyCount + dashboard.relativeParticipation.approvedCommentCount
        } else {
            achievementCount = dashboard.publicSummary.achievementCount
        }
        return MobilePlatformAggregateFamilyAchievementSummary(
            visible: true,
            status: dashboard.status,
            achievementCount: max(achievementCount, 0),
            publicReadyCount: dashboard.publicSummary.publicReadyCount,
            reviewRequiredCount: isGuardian ? dashboard.publicSummary.reviewRequiredCount : 0,
            relativeParticipationVisible: isGuardian || isRelative,
            pendingRelativeCommentCount: isGuardian ? dashboard.relativeParticipation.pendingCommentCount : 0
        )
    }

    private func mapPendingReview(
        viewerRole: MobilePlatformAggregateViewerRole,
        visibility: MobilePlatformAggregateRoleVisibility,
        growthPack: GrowthPackMobileDetailSnapshot,
        growthPackInstall: MobilePlatformAggregateGrowthPackInstallSummary,
        schoolCredit: SchoolGrowthCreditSnapshot,
        familyAchievement: FamilyAchievementSnapshotDashboard
    ) -> MobilePlatformAggregatePendingReviewSummary {
        guard visibility.canSeePendingReview else {
            return MobilePlatformAggregatePendingReviewSummary(
                visible: false,
                actionRequiredCount: 0,
                guardianReviewCount: 0,
                teacherReviewCount: 0,
                relativeReviewCount: 0,
                appealCount: 0
            )
        }
        let growthActions = growthPack.nextActions.filter(\.actionRequired)
        let schoolActions = schoolCredit.nextActions.filter(\.actionRequired)
        let familyActions = viewerRole == .guardian ? familyAchievement.nextActions.filter(\.actionRequired) : []
        let installReviewCount = viewerRole == .guardian ? growthPackInstall.needsGuardianAttentionCount : 0
        let guardianReview = viewerRole == .guardian
            ? growthActions.filter { $0.kind == .guardianReview || $0.kind == .appealReview }.count
                + schoolActions.filter { $0.kind == .guardianConfirm || $0.kind == .resolveAppeal }.count
                + familyActions.count
                + installReviewCount
            : 0
        let teacherReview = growthActions.filter { $0.kind == .teacherReview }.count
            + schoolActions.filter { $0.kind == .teacherVerify }.count
        let appeal = visibility.canSeeAppealDetails
            ? growthPack.publicSummary.appealCount + schoolCredit.publicSummary.appealCount
            : 0
        return MobilePlatformAggregatePendingReviewSummary(
            visible: true,
            actionRequiredCount: growthActions.count + schoolActions.count + familyActions.count + installReviewCount,
            guardianReviewCount: guardianReview,
            teacherReviewCount: teacherReview,
            relativeReviewCount: viewerRole == .guardian ? familyAchievement.relativeParticipation.pendingCommentCount : 0,
            appealCount: appeal
        )
    }

    private func mapOffline(
        viewerRole: MobilePlatformAggregateViewerRole,
        visibility: MobilePlatformAggregateRoleVisibility,
        status: MobileOfflinePublicStatus,
        report: MobileOfflineReplayReport
    ) -> MobilePlatformAggregateOfflineSyncSummary {
        guard visibility.canSeeOfflineSync else {
            return MobilePlatformAggregateOfflineSyncSummary(
                visible: false,
                cardCount: 0,
                urgentCount: 0,
                conflictCount: 0,
                rollbackRequiredCount: 0
            )
        }
        if viewerRole == .child {
            return MobilePlatformAggregateOfflineSyncSummary(
                visible: true,
                cardCount: status.pendingCount,
                urgentCount: 0,
                conflictCount: 0,
                rollbackRequiredCount: 0
            )
        }
        let conflictCount = max(status.conflictCount, report.conflictCount)
        let rollbackCount = max(status.rolledBackCount, report.rolledBackCount)
        return MobilePlatformAggregateOfflineSyncSummary(
            visible: true,
            cardCount: status.pendingCount + status.conflictCount + status.rolledBackCount,
            urgentCount: conflictCount + rollbackCount,
            conflictCount: conflictCount,
            rollbackRequiredCount: rollbackCount
        )
    }

    // MARK: - Risks, actions, findings

    private func riskFlags(
        viewerRole: MobilePlatformAggregateViewerRole,
        visibility: MobilePlatformAggregateRoleVisibility,
        familyAchievement: FamilyAchievementSnapshotDashboard,
        growthPack: GrowthPackMobileDetailSnapshot,
        growthPackInstall: MobilePlatformAggregateGrowthPackInstallSummary,
        schoolCredit: SchoolGrowthCreditSnapshot,
        offlineSummary: MobilePlatformAggregateOfflineSyncSummary,
        creditSettlement: MobileCreditSettlementReport
    ) -> [MobilePlatformAggregateRiskFlag] {
        var risks: [MobilePlatformAggregateRiskFlag] = []

        if visibility.canSeeGrowthPack {
            for finding in growthPack.findings where finding.severity != .ok && finding.code != .roleVisibilityApplied {
                if viewerRole == .child && finding.code == .offlineSyncActionRequired { continue }
                risks.append(risk(.growthPack, finding.code.rawValue, severity: severity(finding.severity), seed: finding.publicRef, visibleToChild: finding.severity != .blocker))
            }
        }
        if viewerRole == .guardian, growthPackInstall.needsGuardianAttentionCount > 0 {
            let severity: MobilePlatformAggregateSeverity = growthPackInstall.blockedCount + growthPackInstall.frozenCount > 0 ? .warning : .info
            risks.append(risk(.growthPack, "GROWTH_PACK_INSTALL_ATTENTION", severity: severity, seed: "growth-install", visibleToChild: false))
        }
        if visibility.canSeeSchoolHomework {
            for finding in schoolCredit.findings where finding.severity != .ok && finding.code != .roleVisibilityApplied {
                if viewerRole == .child && finding.code == .offlineConflictActive { continue }
                risks.append(risk(.schoolHomework, finding.code.rawValue, severity: severity(finding.severity), seed: finding.publicRef, visibleToChild: viewerRole == .child))
            }
        }
        if viewerRole == .guardian {
            for flag in familyAchievement.riskFlags {
                let severity: MobilePlatformAggregateSeverity = flag.severity == .blocker ? .blocker : .warning
                risks.append(risk(.familyAchievement, flag.source.rawValue, severity: severity, seed: flag.id, visibleToChild: false))
            }
            for finding in creditSettlement.findings {
                risks.append(risk(.creditReward, finding.code.rawValue, severity: severity(finding.severity), seed: finding.publicRef, visibleToChild: false))
            }
        }
        if offlineSummary.conflictCount > 0 || offlineSummary.rollbackRequiredCount > 0 {
            risks.append(risk(.offlineSync, "OFFLINE_SYNC_ACTIVE", severity: .warning, seed: "offline-active", visibleToChild: false))
        }
        if viewerRole == .relative && (familyAchievement.relativeParticipation.pendingCommentCount > 0 || familyAchievement.publicSummary.reviewRequiredCount > 0) {
            risks.append(risk(.roleBoundary, "RELATIVE_PRIVATE_REVIEW_HIDDEN", severity: .info, seed: "relative-hidden", visibleToChild: false))
        }
        return uniqueRisks(risks)
    }

    private func nextActions(
        viewerRole: MobilePlatformAggregateViewerRole,
        visibility: MobilePlatformAggregateRoleVisibility,
        growthPack: GrowthPackMobileDetailSnapshot,
        growthPackInstall: MobilePlatformAggregateGrowthPackInstallSummary,
        schoolCredit: SchoolGrowthCreditSnapshot,
        familyAchievement: FamilyAchievementSnapshotDashboard,
        offline: MobilePlatformAggregateOfflineSyncSummary
    ) -> [MobilePlatformAggregateNextAction] {
        var actions: [MobilePlatformAggregateNextAction] = []
        if visibility.canSeeGrowthPack {
            for action in growthPack.nextActions {
                actions.append(next(
                    source: .growthPack,
                    kind: action.kind.rawValue,
                    title: action.title,
                    severity: severity(action.severity),
                    actionRequired: action.actionRequired,
                    visibleToChild: action.visibleToChild,
                    seed: action.publicActionRef
                ))
            }
        }
        if growthPackInstall.visible && growthPackInstall.needsGuardianAttentionCount > 0 {
            if viewerRole == .guardian {
                actions.append(next(
                    source: .growthPack,
                    kind: "install_entitlement_review",
                    title: "复核成长包安装权益的待确认、冻结或阻断项。",
                    severity: growthPackInstall.blockedCount + growthPackInstall.frozenCount > 0 ? .warning : .info,
                    actionRequired: true,
                    visibleToChild: false,
                    seed: "growth-install-review"
                ))
            } else if viewerRole == .child {
                actions.append(next(
                    source: .growthPack,
                    kind: "install_entitlement_wait",
                    title: "等待家长确认成长包安装后继续挑战。",
                    severity: .info,
                    actionRequired: false,
                    visibleToChild: true,
                    seed: "growth-install-wait"
                ))
            }
        }
        if visibility.canSeeSchoolHomework {
            for action in schoolCredit.nextActions {
                actions.append(next(
                    source: .schoolHomework,
                    kind: action.kind.rawValue,
                    title: action.title,
                    severity: severity(action.severity),
                    actionRequired: action.actionRequired,
                    visibleToChild: action.visibleToChild,
                    seed: action.publicActionRef
                ))
            }
        }
        if viewerRole == .guardian {
            for action in familyAchievement.nextActions {
                actions.append(next(
                    source: .familyAchievement,
                    kind: action.kind.rawValue,
                    title: action.title,
                    severity: severity(action.severity),
                    actionRequired: action.actionRequired,
                    visibleToChild: false,
                    seed: action.id
                ))
            }
        }
        if visibility.canSeeOfflineSync && offline.urgentCount > 0 {
            actions.append(next(
                source: .offlineSync,
                kind: "resolve_offline",
                title: "处理离线同步冲突或回滚，避免重复发成长积分。",
                severity: .urgent,
                actionRequired: viewerRole == .guardian,
                visibleToChild: false,
                seed: "offline"
            ))
        }

        let filtered = actions.filter { action in
            switch viewerRole {
            case .guardian:
                return true
            case .child:
                return action.visibleToChild && action.source != .creditReward
            case .teacher:
                return action.source == .schoolHomework || action.source == .growthPack
            case .relative:
                return !action.actionRequired && action.kind == "read_only"
            }
        }
        if !filtered.isEmpty { return uniqueActions(filtered) }
        return [
            next(
                source: .roleBoundary,
                kind: "read_only",
                title: "当前角色只读查看平台总览。",
                severity: .info,
                actionRequired: false,
                visibleToChild: viewerRole == .child,
                seed: "\(viewerRole.rawValue)-read-only"
            )
        ]
    }

    private func findings(
        viewerRole: MobilePlatformAggregateViewerRole,
        risks: [MobilePlatformAggregateRiskFlag],
        pendingReview: MobilePlatformAggregatePendingReviewSummary,
        offline: MobilePlatformAggregateOfflineSyncSummary,
        creditSettlement: MobileCreditSettlementReport,
        visibility: MobilePlatformAggregateRoleVisibility
    ) -> [MobilePlatformAggregateFinding] {
        var result: [MobilePlatformAggregateFinding] = []
        if risks.contains(where: { $0.severity == .blocker }) {
            result.append(finding(.upstreamBlocked, .blocker, "上游移动快照存在阻断风险。", "upstream"))
        }
        if pendingReview.actionRequiredCount > 0 || pendingReview.relativeReviewCount > 0 || pendingReview.appealCount > 0 {
            result.append(finding(.pendingReviewActive, .warning, "存在待授权角色处理的审批或申诉。", "review"))
        }
        if offline.conflictCount > 0 || offline.rollbackRequiredCount > 0 {
            result.append(finding(.offlineSyncActive, .warning, "离线同步存在冲突或回滚，需要对账。", "offline"))
        }
        if visibility.canSeeCreditRewards && creditSettlement.proposals.contains(where: { $0.status != .proposed }) {
            result.append(finding(.creditRewardNotUsable, .warning, "部分成长积分或奖励建议不能展示为可用。", "credit"))
        }
        if viewerRole == .relative && (pendingReview.actionRequiredCount > 0 || pendingReview.appealCount > 0) {
            result.append(finding(.publicOrRelativePrivateLeakBlocked, .blocker, "亲友视图禁止暴露审批或申诉细节。", "relative"))
        }
        result.append(finding(.roleVisibilityApplied, .info, "已按 \(viewerRole.label) 视角裁剪平台总览。", viewerRole.rawValue))
        if !result.contains(where: { $0.severity == .warning || $0.severity == .blocker }) {
            result.append(finding(.platformSnapshotOK, .ok, "移动平台总览快照只读、脱敏且无副作用。", "ok"))
        }
        return uniqueFindings(result)
    }

    private func statusFor(
        viewerRole: MobilePlatformAggregateViewerRole,
        risks: [MobilePlatformAggregateRiskFlag],
        pendingReview: MobilePlatformAggregatePendingReviewSummary,
        offline: MobilePlatformAggregateOfflineSyncSummary,
        familySummary: MobilePlatformAggregateFamilyAchievementSummary
    ) -> MobilePlatformAggregateStatus {
        if risks.contains(where: { $0.severity == .blocker }) { return .blocked }
        if offline.conflictCount > 0 || offline.rollbackRequiredCount > 0 { return .offlineConflict }
        if pendingReview.actionRequiredCount > 0 || pendingReview.relativeReviewCount > 0 || pendingReview.appealCount > 0 {
            return .reviewRequired
        }
        if viewerRole == .relative && familySummary.achievementCount == 0 { return .privateOnly }
        return .ready
    }

    private func moduleCards(
        growthPack: MobilePlatformAggregateGrowthPackSummary,
        growthPackInstall: MobilePlatformAggregateGrowthPackInstallSummary,
        school: MobilePlatformAggregateSchoolSummary,
        credit: MobilePlatformAggregateCreditRewardSummary,
        family: MobilePlatformAggregateFamilyAchievementSummary,
        pending: MobilePlatformAggregatePendingReviewSummary,
        offline: MobilePlatformAggregateOfflineSyncSummary,
        todayTaskCount: Int,
        riskCount: Int
    ) -> [MobilePlatformAggregateModuleCard] {
        let growthSubtitle = growthPackInstall.visible
            ? "\(growthPack.taskCount) 个任务 · \(growthPack.nextActionCount) 个下一步 · \(growthPackInstall.installedCount) 个已安装"
            : "\(growthPack.taskCount) 个任务 · \(growthPack.nextActionCount) 个下一步"
        let growthMetric = growthPackInstall.visible && growthPackInstall.needsGuardianAttentionCount > 0
            ? "\(growthPackInstall.needsGuardianAttentionCount) 需关注"
            : growthPack.status.label
        let cards = [
            card(.todayTasks, "今日任务", "\(todayTaskCount) 项可见安排", "\(todayTaskCount)", todayTaskCount > 0, true, "today"),
            card(.growthPack, "成长包", growthSubtitle, growthMetric, growthPack.nextActionCount > 0 || growthPackInstall.needsGuardianAttentionCount > 0, growthPack.visible || growthPackInstall.visible, "growth"),
            card(.schoolHomework, "学校成长积分", "\(school.assignmentCount) 份作业 · \(school.submittedCount) 份已提交", school.status.label, school.submittedCount > 0, school.visible, "school"),
            card(.creditReward, "成长积分与奖励", "\(credit.proposedCount) 条可建议 · \(credit.reviewRequiredCount) 条待审核", "\(credit.totalPreviewAmount)", credit.reviewRequiredCount > 0 || credit.blockedCount > 0, credit.visible, "credit"),
            card(.familyAchievement, "家庭成就", "\(family.achievementCount) 条成长记录 · \(family.publicReadyCount) 条可公开", family.status.label, family.reviewRequiredCount > 0, family.visible, "family"),
            card(.pendingReview, "审批收件箱", "\(pending.actionRequiredCount) 个待处理 · \(pending.appealCount) 个申诉", "\(pending.actionRequiredCount)", pending.actionRequiredCount > 0, pending.visible, "review"),
            card(.offlineSync, "离线同步", "\(offline.cardCount) 条同步卡片 · \(offline.conflictCount) 个冲突", "\(offline.urgentCount)", offline.urgentCount > 0, offline.visible, "offline"),
            card(.risk, "风险提示", "\(riskCount) 个角色可见风险", "\(riskCount)", riskCount > 0, true, "risk")
        ]
        return cards.filter(\.visible)
    }

    private func childRefs(
        viewerRole: MobilePlatformAggregateViewerRole,
        visibility: MobilePlatformAggregateRoleVisibility,
        mobileSnapshot: MobileSyncSnapshot,
        growthPack: GrowthPackMobileDetailSnapshot,
        growthPackInstall: GrowthPackInstallSnapshot,
        schoolCredit: SchoolGrowthCreditSnapshot,
        familyAchievement: FamilyAchievementSnapshotDashboard
    ) -> [String] {
        var refs = Set<String>()
        if visibility.canSeeTodayTasks {
            mobileSnapshot.children.forEach { refs.insert(publicRef("mpa-kid", $0.publicRef)) }
        }
        if visibility.canSeeGrowthPack {
            growthPack.tasks.forEach { refs.insert(publicRef("mpa-kid", $0.childPublicRef)) }
        }
        if visibility.canSeeGrowthPack, viewerRole == .child || viewerRole == .guardian {
            refs.insert(publicRef("mpa-kid", growthPackInstall.publicSummary.childPublicRef))
        }
        if visibility.canSeeSchoolHomework {
            schoolCredit.assignments.forEach { refs.insert(publicRef("mpa-kid", $0.childPublicRef)) }
        }
        if viewerRole == .guardian || viewerRole == .child || viewerRole == .relative {
            refs.insert(publicRef("mpa-kid", familyAchievement.childPublicRef))
        }
        return refs.sorted()
    }

    private func publicSummary(
        generatedAt: String,
        viewerRole: MobilePlatformAggregateViewerRole,
        status: MobilePlatformAggregateStatus,
        todayTasks: [MobilePlatformAggregateTodayTask],
        cards: [MobilePlatformAggregateModuleCard],
        growthPackInstall: MobilePlatformAggregateGrowthPackInstallSummary,
        school: MobilePlatformAggregateSchoolSummary,
        family: MobilePlatformAggregateFamilyAchievementSummary,
        credit: MobilePlatformAggregateCreditRewardSummary,
        pending: MobilePlatformAggregatePendingReviewSummary,
        offline: MobilePlatformAggregateOfflineSyncSummary,
        risks: [MobilePlatformAggregateRiskFlag],
        findings: [MobilePlatformAggregateFinding]
    ) -> MobilePlatformAggregatePublicSummary {
        MobilePlatformAggregatePublicSummary(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            status: status,
            todayTaskCount: todayTasks.count,
            visibleModuleCount: cards.count,
            schoolAssignmentCount: school.assignmentCount,
            familyAchievementCount: family.achievementCount,
            creditProposalCount: credit.proposalCount,
            growthPackInstalledCount: growthPackInstall.visible ? growthPackInstall.installedCount : 0,
            growthPackInstallAttentionCount: growthPackInstall.visible ? growthPackInstall.needsGuardianAttentionCount : 0,
            pendingReviewCount: pending.visible ? pending.actionRequiredCount + pending.relativeReviewCount : 0,
            offlineConflictCount: offline.visible ? offline.conflictCount : 0,
            riskCount: risks.count,
            findingCodes: findings.map(\.code)
        )
    }

    // MARK: - Redaction

    private func containsAggregateSensitivePayload(_ values: [String]) -> Bool {
        let joined = values.joined(separator: " ").lowercased()
        let blockedMarkers = [
            "child:", "family:", "school:", "class:", "teacher:", "relative:",
            "pack:", "creator:", "order:", "entitlement:", "homework:", "proof:",
            "ledger:", "device:", "task:", "claim:", "gpi-order", "gpi-ent",
            "http://", "https://", "file://", "/users/", "/volumes/", "192.168.",
            "baseurl", "api_key", "apikey", "token", "secret"
        ]
        if blockedMarkers.contains(where: { joined.contains($0) }) { return true }

        let blockedPatterns = [
            #"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"#,
            #"(?i)\b[0-9a-f]{24,}\b"#,
            #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#
        ]
        return blockedPatterns.contains { pattern in
            joined.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func hasUnsafeInput(
        mobileSnapshot: MobileSyncSnapshot,
        familyAchievement: FamilyAchievementSnapshotDashboard,
        growthPack: GrowthPackMobileDetailSnapshot,
        growthPackInstall: GrowthPackInstallSnapshot,
        schoolCredit: SchoolGrowthCreditSnapshot,
        creditSettlement: MobileCreditSettlementReport
    ) -> Bool {
        if GrowthPackInstallEntitlementBuilder.reportLeaks(growthPackInstall) { return true }
        var values: [String] = []
        values.append(mobileSnapshot.family.displayName)
        values.append(contentsOf: mobileSnapshot.children.map(\.displayName))
        values.append(contentsOf: mobileSnapshot.tasks.map(\.title))
        values.append(contentsOf: growthPack.tasks.map(\.title))
        values.append(contentsOf: growthPack.steps.flatMap { [$0.title, $0.reason, $0.nextStep] })
        values.append(contentsOf: growthPackInstall.decisions.flatMap { [$0.title, $0.summary, $0.reason, $0.nextAction] })
        values.append(contentsOf: schoolCredit.assignments.map(\.title))
        values.append(familyAchievement.publicSummary.status.rawValue)
        values.append(contentsOf: familyAchievement.riskFlags.map(\.title))
        values.append(contentsOf: creditSettlement.proposals.map(\.reason))
        return MobileSyncPayloadGuard.isUnsafe(values) || containsAggregateSensitivePayload(values)
    }

    private func displayValues(_ snapshot: MobilePlatformAggregateSnapshot) -> [String] {
        var values: [String] = [
            snapshot.generatedAt,
            snapshot.header.generatedAt
        ]
        values.append(contentsOf: snapshot.header.childPublicRefs)
        values.append(contentsOf: snapshot.todayTasks.flatMap { [$0.publicTaskRef, $0.title, $0.category, $0.status, $0.priority] })
        values.append(contentsOf: snapshot.moduleCards.flatMap { [$0.publicCardRef, $0.title, $0.subtitle, $0.statusLabel, $0.metricLabel] })
        values.append(contentsOf: snapshot.nextActions.flatMap { [$0.publicActionRef, $0.kind, $0.title] })
        values.append(contentsOf: snapshot.riskFlags.flatMap { [$0.publicRiskRef, $0.source.rawValue, $0.code] })
        values.append(contentsOf: snapshot.findings.flatMap { [$0.publicRef, $0.message] })
        return values
    }

    private func safeFallback(
        viewerRole: MobilePlatformAggregateViewerRole,
        visibility: MobilePlatformAggregateRoleVisibility
    ) -> MobilePlatformAggregateSnapshot {
        let fallbackFinding = finding(
            .publicSummaryLeak,
            .blocker,
            "移动平台总览快照未通过公开脱敏检查，已进入安全降级模式。",
            "fallback"
        )
        let header = MobilePlatformAggregateHeader(
            viewerRole: viewerRole,
            status: .blocked,
            generatedAt: generatedAt,
            childPublicRefs: []
        )
        let emptyGrowth = MobilePlatformAggregateGrowthPackSummary(
            visible: false,
            status: .blocked,
            taskCount: 0,
            proofRequirementCount: 0,
            availableCreditPreviewCount: 0,
            nextActionCount: 0
        )
        let emptyGrowthInstall = MobilePlatformAggregateGrowthPackInstallSummary.empty
        let emptySchool = MobilePlatformAggregateSchoolSummary(
            visible: false,
            status: .blocked,
            assignmentCount: 0,
            submittedCount: 0,
            teacherVerifiedCount: 0,
            guardianConfirmedCount: 0,
            usableCreditPreviewCount: 0,
            canSeeTeacherVerification: false,
            canSeeGuardianConfirmation: false
        )
        let emptyCredit = MobilePlatformAggregateCreditRewardSummary(
            visible: false,
            proposalCount: 0,
            proposedCount: 0,
            reviewRequiredCount: 0,
            blockedCount: 0,
            duplicateCount: 0,
            totalPreviewAmount: 0
        )
        let emptyFamily = MobilePlatformAggregateFamilyAchievementSummary(
            visible: false,
            status: .blocked,
            achievementCount: 0,
            publicReadyCount: 0,
            reviewRequiredCount: 0,
            relativeParticipationVisible: false,
            pendingRelativeCommentCount: 0
        )
        let emptyPending = MobilePlatformAggregatePendingReviewSummary(
            visible: false,
            actionRequiredCount: 0,
            guardianReviewCount: 0,
            teacherReviewCount: 0,
            relativeReviewCount: 0,
            appealCount: 0
        )
        let emptyOffline = MobilePlatformAggregateOfflineSyncSummary(
            visible: false,
            cardCount: 0,
            urgentCount: 0,
            conflictCount: 0,
            rollbackRequiredCount: 0
        )
        return MobilePlatformAggregateSnapshot(
            generatedAt: generatedAt,
            header: header,
            todayTasks: [],
            moduleCards: [],
            growthPack: emptyGrowth,
            growthPackInstall: emptyGrowthInstall,
            schoolHomework: emptySchool,
            creditRewards: emptyCredit,
            familyAchievements: emptyFamily,
            pendingReview: emptyPending,
            offlineSync: emptyOffline,
            roleVisibility: visibility,
            nextActions: [],
            riskFlags: [],
            findings: [fallbackFinding],
            publicSummary: MobilePlatformAggregatePublicSummary(
                generatedAt: generatedAt,
                viewerRole: viewerRole,
                status: .blocked,
                todayTaskCount: 0,
                visibleModuleCount: 0,
                schoolAssignmentCount: 0,
                familyAchievementCount: 0,
                creditProposalCount: 0,
                growthPackInstalledCount: 0,
                growthPackInstallAttentionCount: 0,
                pendingReviewCount: 0,
                offlineConflictCount: 0,
                riskCount: 0,
                findingCodes: [.publicSummaryLeak]
            )
        )
    }

    // MARK: - Helpers

    private func publicRef(_ prefix: String, _ source: String) -> String {
        Self.stablePublicRef(prefix: prefix, source: source, salt: redactionSalt)
    }

    static func stablePublicRef(prefix: String, source: String, salt: String = "mobile-platform-aggregate-ios-v1") -> String {
        var hash: UInt32 = 5381
        for scalar in "\(salt):\(source)".unicodeScalars {
            hash = (hash &* 33) ^ UInt32(scalar.value)
        }
        let body = String(hash, radix: 36)
        let padded = body.count >= 7 ? body : String(repeating: "0", count: 7 - body.count) + body
        return "\(prefix)-\(padded)"
    }

    private func card(
        _ kind: MobilePlatformAggregateModuleKind,
        _ title: String,
        _ subtitle: String,
        _ metric: String,
        _ actionRequired: Bool,
        _ visible: Bool,
        _ seed: String
    ) -> MobilePlatformAggregateModuleCard {
        MobilePlatformAggregateModuleCard(
            publicCardRef: publicRef("mpa-card", seed),
            kind: kind,
            title: title,
            subtitle: subtitle,
            statusLabel: kind.label,
            metricLabel: metric,
            actionRequired: actionRequired,
            visible: visible
        )
    }

    private func finding(
        _ code: MobilePlatformAggregateFindingCode,
        _ severity: MobilePlatformAggregateSeverity,
        _ message: String,
        _ seed: String
    ) -> MobilePlatformAggregateFinding {
        MobilePlatformAggregateFinding(
            code: code,
            severity: severity,
            message: message,
            publicRef: publicRef("mpa-finding", "\(code.rawValue):\(seed)")
        )
    }

    private func risk(
        _ source: MobilePlatformAggregateRiskSource,
        _ code: String,
        severity: MobilePlatformAggregateSeverity,
        seed: String,
        visibleToChild: Bool
    ) -> MobilePlatformAggregateRiskFlag {
        MobilePlatformAggregateRiskFlag(
            publicRiskRef: publicRef("mpa-risk", "\(source.rawValue):\(code):\(seed)"),
            source: source,
            code: code,
            severity: severity,
            visibleToChild: visibleToChild
        )
    }

    private func next(
        source: MobilePlatformAggregateRiskSource,
        kind: String,
        title: String,
        severity: MobilePlatformAggregateNextAction.Severity,
        actionRequired: Bool,
        visibleToChild: Bool,
        seed: String
    ) -> MobilePlatformAggregateNextAction {
        MobilePlatformAggregateNextAction(
            publicActionRef: publicRef("mpa-action", "\(source.rawValue):\(kind):\(seed)"),
            source: source,
            kind: kind,
            title: title,
            severity: severity,
            actionRequired: actionRequired,
            visibleToChild: visibleToChild
        )
    }

    private func severity(_ value: GrowthPackMobileDetailSeverity) -> MobilePlatformAggregateSeverity {
        switch value {
        case .ok: return .ok
        case .info: return .info
        case .warning: return .warning
        case .blocker: return .blocker
        }
    }

    private func severity(_ value: SchoolGrowthCreditSeverity) -> MobilePlatformAggregateSeverity {
        switch value {
        case .ok: return .ok
        case .info: return .info
        case .warning: return .warning
        case .blocker: return .blocker
        }
    }

    private func severity(_ value: MobileCreditSettlementSeverity) -> MobilePlatformAggregateSeverity {
        switch value {
        case .info: return .info
        case .warning: return .warning
        case .blocker: return .blocker
        }
    }

    private func severity(_ value: GrowthPackMobileDetailNextAction.Severity) -> MobilePlatformAggregateNextAction.Severity {
        switch value {
        case .info: return .info
        case .warning: return .warning
        case .urgent: return .urgent
        }
    }

    private func severity(_ value: SchoolGrowthCreditNextAction.Severity) -> MobilePlatformAggregateNextAction.Severity {
        switch value {
        case .info: return .info
        case .warning: return .warning
        case .urgent: return .urgent
        }
    }

    private func severity(_ value: FamilyAchievementRiskSeverity) -> MobilePlatformAggregateNextAction.Severity {
        switch value {
        case .info: return .info
        case .warning: return .warning
        case .blocker: return .urgent
        }
    }

    private func uniqueRisks(_ risks: [MobilePlatformAggregateRiskFlag]) -> [MobilePlatformAggregateRiskFlag] {
        var seen = Set<String>()
        return risks.filter { risk in
            let key = "\(risk.source.rawValue):\(risk.code):\(risk.severity.rawValue)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private func uniqueActions(_ actions: [MobilePlatformAggregateNextAction]) -> [MobilePlatformAggregateNextAction] {
        var seen = Set<String>()
        return actions.filter { action in
            let key = "\(action.source.rawValue):\(action.kind):\(action.title)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private func uniqueFindings(_ findings: [MobilePlatformAggregateFinding]) -> [MobilePlatformAggregateFinding] {
        var seen = Set<String>()
        return findings.filter { finding in
            let key = "\(finding.code.rawValue):\(finding.severity.rawValue)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private func isActionable(_ status: MobileSyncTaskStatus) -> Bool {
        switch status {
        case .scheduled, .available, .inProgress:
            return true
        case .submitted, .verified, .missed:
            return false
        }
    }

    private func taskStatusLabel(_ status: MobileSyncTaskStatus) -> String {
        switch status {
        case .scheduled: return "待开始"
        case .available: return "可开始"
        case .inProgress: return "进行中"
        case .submitted: return "待验证"
        case .verified: return "已完成"
        case .missed: return "已错过"
        }
    }

    private func priorityLabel(_ priority: MobileSyncTaskPriority) -> String {
        switch priority {
        case .mustDo: return "必做"
        case .recommended: return "推荐"
        case .optional: return "可选"
        case .bonus: return "加分"
        }
    }

    private func categoryLabel(_ category: MobileSyncTaskCategory) -> String {
        switch category {
        case .homework: return "作业"
        case .learning: return "学习"
        case .exercise: return "运动"
        case .routine: return "习惯"
        case .chore: return "家务"
        case .creative: return "创作"
        case .socialEmotional: return "心智"
        case .family: return "家庭"
        }
    }
}
