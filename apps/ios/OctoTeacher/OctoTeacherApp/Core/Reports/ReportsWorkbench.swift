import Foundation

/// iOS 成长报告 / 周报预览的纯本地只读投影。
///
/// 该层只聚合本地 mock store 中的任务、学校作业、家庭荣誉、成长积分和设备会话摘要：
/// 不生成文件，不导出 PDF，不上传云端，不通知亲友，不写账本，不发成长积分，不解锁设备。
enum ReportsViewerRole: String, CaseIterable, Equatable {
    case child
    case guardian

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        }
    }

    var note: String {
        switch self {
        case .child:
            return "这里回顾本周努力和下一步，不显示家长复核原因或内部记录。"
        case .guardian:
            return "只读查看成长报告草稿、待复核事项和风险边界；正式分享仍需后续授权。"
        }
    }
}

enum ReportsSectionKind: String, Equatable {
    case tasks
    case school
    case growthPack
    case familyHonor
    case creditReward
    case aiCompanion
    case wellbeing

    var title: String {
        switch self {
        case .tasks: return "任务"
        case .school: return "学校"
        case .growthPack: return "成长包"
        case .familyHonor: return "荣誉"
        case .creditReward: return "成长积分"
        case .aiCompanion: return "AI 小伙伴"
        case .wellbeing: return "节奏"
        }
    }
}

enum ReportsStatus: String, Equatable {
    case ready
    case inProgress = "in_progress"
    case reviewRequired = "review_required"
    case blocked

    var label: String {
        switch self {
        case .ready: return "可展示"
        case .inProgress: return "进行中"
        case .reviewRequired: return "需复核"
        case .blocked: return "已阻断"
        }
    }
}

struct ReportsMetric: Identifiable, Equatable {
    var id: String
    var title: String
    var value: Int
    var suffix: String
    var visibleToChild: Bool

    var displayValues: [String] { [id, title, "\(value)", suffix] }
}

struct ReportsSection: Identifiable, Equatable {
    var publicSectionRef: String
    var kind: ReportsSectionKind
    var title: String
    var summary: String
    var status: ReportsStatus
    var progress: Int
    var visibleToChild: Bool
    var actionRequired: Bool

    let writesReportFile = false
    let exportsPdf = false
    let uploadsReport = false
    let sendsNotification = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false

    var id: String { publicSectionRef }

    var displayValues: [String] {
        [
            publicSectionRef,
            kind.rawValue,
            kind.title,
            title,
            summary,
            status.rawValue,
            status.label
        ]
    }
}

struct ReportsFinding: Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var actionRequired: Bool
    var visibleToChild: Bool

    var displayValues: [String] { [id, title, detail] }
}

struct ReportsPublicSummary: Equatable {
    var role: ReportsViewerRole
    var sectionCount: Int
    var metricCount: Int
    var actionRequiredCount: Int
    var completedTaskCount: Int
    var submittedHomeworkCount: Int
    var visibleHonorCount: Int
    var availableCreditMinutes: Int
    var aiCompanionInteractionCount: Int
    var aiCompanionGuardianActionCount: Int
    var openWishCount: Int
    var pendingRewardActionCount: Int
    var averageProgress: Int

    let writesReportFile = false
    let exportsPdf = false
    let uploadsReport = false
    let sendsNotification = false
    let callsNetwork = false
    let callsAiProvider = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let readsHealthKit = false
    let readsScreenTime = false

    var hasTriggeredSideEffect: Bool {
        writesReportFile || exportsPdf || uploadsReport || sendsNotification || callsNetwork
            || callsAiProvider || writesLedger || grantsCredit || unlocksDevice || readsHealthKit
            || readsScreenTime
    }
}

struct ReportsWorkbench: Equatable {
    var role: ReportsViewerRole
    var title: String
    var subtitle: String
    var note: String
    var metrics: [ReportsMetric]
    var sections: [ReportsSection]
    var findings: [ReportsFinding]
    var publicSummary: ReportsPublicSummary

    var displayValues: [String] {
        [role.rawValue, title, subtitle, note]
            + metrics.flatMap(\.displayValues)
            + sections.flatMap(\.displayValues)
            + findings.flatMap(\.displayValues)
    }

    var hasUnsafeDisplayPayload: Bool {
        ReportsWorkbenchBuilder.hasUnsafeDisplayPayload(displayValues)
    }
}

struct ReportsWorkbenchBuilder {
    private static let sensitiveMarkers = [
        "child:", "family:", "guardian:", "teacher:", "school:",
        "task:", "proof:", "ledger:", "device:", "session:", "token",
        "secret", "api_key", "apikey", "http://", "https://", "file://",
        "/users/", "/volumes/", "192.168.", "baseurl", "provider:", "model:"
    ]

    func build(
        role: ReportsViewerRole,
        family: LocalFamilyStore = LocalFamilyStore(),
        schoolFamily: SchoolFamilyStore = SchoolFamilyStore(),
        screenTime: MockScreenTimeController = MockScreenTimeController(),
        aiCompanionSessions: [AICompanionSessionRecord] = [],
        now: Date = Date(),
        unsafePayload: [String] = []
    ) -> ReportsWorkbench {
        if Self.hasUnsafeDisplayPayload(unsafePayload) {
            return blockedShell(role: role)
        }

        let activeAssignments = family.assignments.filter { $0.status != .cancelled }
        let approvedTasks = activeAssignments.filter { $0.status == .approved }.count
        let submittedTasks = activeAssignments.filter { $0.status == .submitted }.count
        let taskCount = activeAssignments.count
        let submittedHomeworks = schoolFamily.homeworks.filter { $0.status == .submitted }.count
        let settledHomeworks = schoolFamily.settledHomeworks.count
        let visibleHonor = schoolFamily.visibleHonorWall(for: .household).count
        let pendingRelativeComments = schoolFamily.relativeComments.filter { $0.status == .pending }.count
        let credit = family.creditBalance
        let aiDigest = aiCompanionDigest(
            childId: family.activeChildId,
            sessions: aiCompanionSessions,
            now: now
        )
        let rewardDigest = rewardDigest(family: family, childId: family.activeChildId)

        let sections = visibleSections(
            role: role,
            approvedTasks: approvedTasks,
            submittedTasks: submittedTasks,
            taskCount: taskCount,
            submittedHomeworks: submittedHomeworks,
            settledHomeworks: settledHomeworks,
            homeworkCount: schoolFamily.homeworks.count,
            visibleHonor: visibleHonor,
            pendingRelativeComments: pendingRelativeComments,
            credit: credit,
            aiInteractionCount: aiDigest.interactionCount,
            aiGuardianActionCount: aiDigest.guardianActionCount,
            openWishCount: rewardDigest.openWishCount,
            pendingRewardActionCount: rewardDigest.pendingActionCount,
            screenTime: screenTime
        )
        let metrics = visibleMetrics(
            role: role,
            approvedTasks: approvedTasks,
            submittedTasks: submittedTasks,
            submittedHomeworks: submittedHomeworks,
            visibleHonor: visibleHonor,
            credit: credit,
            aiInteractionCount: aiDigest.interactionCount,
            aiGuardianActionCount: aiDigest.guardianActionCount,
            openWishCount: rewardDigest.openWishCount,
            pendingRewardActionCount: rewardDigest.pendingActionCount
        )
        let findings = visibleFindings(
            role: role,
            submittedTasks: submittedTasks,
            submittedHomeworks: submittedHomeworks,
            pendingRelativeComments: pendingRelativeComments,
            aiGuardianActionCount: aiDigest.guardianActionCount,
            pendingRewardActionCount: rewardDigest.pendingActionCount,
            screenTime: screenTime
        )
        let summary = ReportsPublicSummary(
            role: role,
            sectionCount: sections.count,
            metricCount: metrics.count,
            actionRequiredCount: sections.filter(\.actionRequired).count + findings.filter(\.actionRequired).count,
            completedTaskCount: approvedTasks,
            submittedHomeworkCount: submittedHomeworks,
            visibleHonorCount: visibleHonor,
            availableCreditMinutes: role == .guardian ? credit.availableMinutes : 0,
            aiCompanionInteractionCount: aiDigest.interactionCount,
            aiCompanionGuardianActionCount: role == .guardian ? aiDigest.guardianActionCount : 0,
            openWishCount: rewardDigest.openWishCount,
            pendingRewardActionCount: role == .guardian ? rewardDigest.pendingActionCount : 0,
            averageProgress: averageProgress(sections)
        )
        let workbench = ReportsWorkbench(
            role: role,
            title: "成长报告",
            subtitle: "本周只读预览",
            note: role.note,
            metrics: metrics,
            sections: sections,
            findings: findings,
            publicSummary: summary
        )
        return workbench.hasUnsafeDisplayPayload ? blockedShell(role: role) : workbench
    }

    static func hasUnsafeDisplayPayload(_ values: [String]) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        let joined = values.joined(separator: " ").lowercased()
        return sensitiveMarkers.contains { joined.contains($0) }
    }

    private func visibleMetrics(
        role: ReportsViewerRole,
        approvedTasks: Int,
        submittedTasks: Int,
        submittedHomeworks: Int,
        visibleHonor: Int,
        credit: CreditBalance,
        aiInteractionCount: Int,
        aiGuardianActionCount: Int,
        openWishCount: Int,
        pendingRewardActionCount: Int
    ) -> [ReportsMetric] {
        [
            ReportsMetric(id: "task-approved", title: "完成任务", value: approvedTasks, suffix: "项", visibleToChild: true),
            ReportsMetric(id: "homework-submitted", title: "提交作业", value: submittedHomeworks, suffix: "份", visibleToChild: true),
            ReportsMetric(id: "honor-visible", title: "荣誉记录", value: visibleHonor, suffix: "条", visibleToChild: true),
            ReportsMetric(id: "ai-companion-interactions", title: "小伙伴陪伴", value: aiInteractionCount, suffix: "次", visibleToChild: true),
            ReportsMetric(id: "wish-list-open", title: "我的愿望", value: openWishCount, suffix: "个", visibleToChild: true),
            ReportsMetric(id: "credit-available", title: "可用成长积分", value: credit.availableMinutes, suffix: "积分", visibleToChild: false),
            ReportsMetric(id: "ai-companion-guardian-actions", title: "小伙伴提醒", value: aiGuardianActionCount, suffix: "项", visibleToChild: false),
            ReportsMetric(id: "reward-guardian-actions", title: "奖励待办", value: pendingRewardActionCount, suffix: "项", visibleToChild: false),
            ReportsMetric(id: "review-pending", title: "待复核", value: submittedTasks + credit.pendingMinutes, suffix: "项", visibleToChild: false)
        ].filter { role == .guardian || $0.visibleToChild }
    }

    private func visibleSections(
        role: ReportsViewerRole,
        approvedTasks: Int,
        submittedTasks: Int,
        taskCount: Int,
        submittedHomeworks: Int,
        settledHomeworks: Int,
        homeworkCount: Int,
        visibleHonor: Int,
        pendingRelativeComments: Int,
        credit: CreditBalance,
        aiInteractionCount: Int,
        aiGuardianActionCount: Int,
        openWishCount: Int,
        pendingRewardActionCount: Int,
        screenTime: MockScreenTimeController
    ) -> [ReportsSection] {
        [
            section(
                "reports-tasks",
                .tasks,
                "今日任务表现",
                "已完成 \(approvedTasks) / \(taskCount) 项，\(submittedTasks) 项等待复核。",
                submittedTasks > 0 ? .reviewRequired : .inProgress,
                percent(approvedTasks, of: taskCount),
                true,
                role == .guardian && submittedTasks > 0
            ),
            section(
                "reports-school",
                .school,
                "学校作业进展",
                "已提交或完成 \(settledHomeworks) / \(homeworkCount) 份，\(submittedHomeworks) 份等待老师或家长确认。",
                submittedHomeworks > 0 ? .reviewRequired : .inProgress,
                percent(settledHomeworks, of: homeworkCount),
                true,
                role == .guardian && submittedHomeworks > 0
            ),
            section(
                "reports-growth-pack",
                .growthPack,
                "成长包节奏",
                "成长包按任务顺序推进，报告只展示进度，不自动结算。",
                .inProgress,
                68,
                true,
                false
            ),
            section(
                "reports-honor",
                .familyHonor,
                "荣誉与家庭鼓励",
                "已有 \(visibleHonor) 条荣誉记录，\(pendingRelativeComments) 条亲友鼓励等待家长审核。",
                pendingRelativeComments > 0 ? .reviewRequired : .ready,
                visibleHonor > 0 ? 76 : 50,
                true,
                role == .guardian && pendingRelativeComments > 0
            ),
            section(
                "reports-credit",
                .creditReward,
                role == .child ? "成长积分与奖励节奏" : "成长积分与奖励复核",
                role == .child
                    ? "你有 \(openWishCount) 个愿望在清单里，报告只回顾奖励节奏。"
                    : "可用 \(credit.availableMinutes) 成长积分，待确认 \(credit.pendingMinutes) 成长积分；另有 \(pendingRewardActionCount) 项愿望/零花钱待办。",
                credit.pendingMinutes + pendingRewardActionCount > 0 ? .reviewRequired : .ready,
                credit.availableMinutes > 0 ? 82 : 58,
                true,
                role == .guardian && credit.pendingMinutes + pendingRewardActionCount > 0
            ),
            section(
                "reports-ai-companion",
                .aiCompanion,
                role == .child ? "AI 小伙伴陪伴" : "AI 小伙伴互动概览",
                role == .child
                    ? "小伙伴本周陪你聊了 \(aiInteractionCount) 次，会鼓励你一步一步来。"
                    : "本周有 \(aiInteractionCount) 次脱敏互动，\(aiGuardianActionCount) 项需要家长留意；报告不展示原始聊天。",
                aiGuardianActionCount > 0 ? .reviewRequired : (aiInteractionCount > 0 ? .ready : .inProgress),
                aiInteractionCount > 0 ? min(100, 45 + aiInteractionCount * 8) : 30,
                true,
                role == .guardian && aiGuardianActionCount > 0
            ),
            section(
                "reports-wellbeing",
                .wellbeing,
                "设备会话节奏",
                screenTime.sessionStatus == .active ? "当前有进行中的本地奖励会话。" : "当前没有进行中的奖励会话。",
                screenTime.sessionStatus == .active ? .inProgress : .ready,
                screenTime.sessionStatus == .active ? 60 : 100,
                role == .guardian,
                false
            )
        ].filter { role == .guardian || $0.visibleToChild }
    }

    private func visibleFindings(
        role: ReportsViewerRole,
        submittedTasks: Int,
        submittedHomeworks: Int,
        pendingRelativeComments: Int,
        aiGuardianActionCount: Int,
        pendingRewardActionCount: Int,
        screenTime: MockScreenTimeController
    ) -> [ReportsFinding] {
        if role == .child {
            return [
                ReportsFinding(
                    id: "child-report-read-only",
                    title: "报告只读",
                    detail: "报告只帮你回顾努力，不会自动发成长积分或解锁设备。",
                    actionRequired: false,
                    visibleToChild: true
                )
            ]
        }

        var rows: [ReportsFinding] = [
            ReportsFinding(
                id: "no-export",
                title: "分享未启用",
                detail: "当前不生成文件、不上传云端、不通知亲友。",
                actionRequired: false,
                visibleToChild: false
            )
        ]
        if submittedTasks + submittedHomeworks > 0 {
            rows.append(
                ReportsFinding(
                    id: "review-required",
                    title: "仍有待复核项",
                    detail: "\(submittedTasks) 项任务和 \(submittedHomeworks) 份作业仍需人工确认。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        if pendingRelativeComments > 0 {
            rows.append(
                ReportsFinding(
                    id: "relative-comments-pending",
                    title: "亲友鼓励待审核",
                    detail: "\(pendingRelativeComments) 条亲友内容还不能进入报告展示。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        if aiGuardianActionCount > 0 {
            rows.append(
                ReportsFinding(
                    id: "ai-companion-follow-up",
                    title: "小伙伴提醒待查看",
                    detail: "\(aiGuardianActionCount) 条 AI 小伙伴脱敏摘要建议家长跟进。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        if pendingRewardActionCount > 0 {
            rows.append(
                ReportsFinding(
                    id: "reward-pathway-follow-up",
                    title: "奖励兑换待处理",
                    detail: "\(pendingRewardActionCount) 项愿望或零花钱事项需要家长线下确认。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        if screenTime.sessionStatus == .active {
            rows.append(
                ReportsFinding(
                    id: "mock-session-active",
                    title: "奖励会话进行中",
                    detail: "报告只显示状态，不结束或延长设备会话。",
                    actionRequired: false,
                    visibleToChild: false
                )
            )
        }
        return rows
    }

    private func aiCompanionDigest(
        childId: UUID,
        sessions: [AICompanionSessionRecord],
        now: Date
    ) -> (interactionCount: Int, guardianActionCount: Int) {
        let weekStart = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let recent = sessions.filter { record in
            record.childId == childId
                && record.createdAt >= weekStart
                && record.createdAt <= now
        }
        return (
            interactionCount: recent.count,
            guardianActionCount: recent.filter(\.needsGuardianAction).count
        )
    }

    private func rewardDigest(
        family: LocalFamilyStore,
        childId: UUID
    ) -> (openWishCount: Int, pendingActionCount: Int) {
        let wishes = family.wishes.filter { $0.childId == childId }
        let openWishCount = wishes.filter { wish in
            wish.status == .proposed || wish.status == .priced || wish.status == .redeemed
        }.count
        let pendingWishActions = wishes.filter { wish in
            wish.status == .proposed || wish.status == .redeemed
        }.count
        let pendingMoneyActions = family.moneyLedger.filter { entry in
            entry.childId == childId
                && (entry.status == .awaitingApproval || entry.status == .pendingPayout)
        }.count
        return (openWishCount, pendingWishActions + pendingMoneyActions)
    }

    private func section(
        _ publicRef: String,
        _ kind: ReportsSectionKind,
        _ title: String,
        _ summary: String,
        _ status: ReportsStatus,
        _ progress: Int,
        _ visibleToChild: Bool,
        _ actionRequired: Bool
    ) -> ReportsSection {
        ReportsSection(
            publicSectionRef: publicRef,
            kind: kind,
            title: title,
            summary: summary,
            status: status,
            progress: max(0, min(100, progress)),
            visibleToChild: visibleToChild,
            actionRequired: actionRequired
        )
    }

    private func percent(_ value: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        return max(0, min(100, Int((Double(value) / Double(total) * 100).rounded())))
    }

    private func averageProgress(_ sections: [ReportsSection]) -> Int {
        guard !sections.isEmpty else { return 0 }
        return sections.reduce(0) { $0 + $1.progress } / sections.count
    }

    private func blockedShell(role: ReportsViewerRole) -> ReportsWorkbench {
        ReportsWorkbench(
            role: role,
            title: "成长报告",
            subtitle: "输入已被安全壳阻断",
            note: role.note,
            metrics: [],
            sections: [],
            findings: [
                ReportsFinding(
                    id: "unsafe",
                    title: "报告内容被拦截",
                    detail: "发现不适合展示的内部信息，已隐藏报告草稿。",
                    actionRequired: true,
                    visibleToChild: role == .child
                )
            ],
            publicSummary: ReportsPublicSummary(
                role: role,
                sectionCount: 0,
                metricCount: 0,
                actionRequiredCount: 1,
                completedTaskCount: 0,
                submittedHomeworkCount: 0,
                visibleHonorCount: 0,
                availableCreditMinutes: 0,
                aiCompanionInteractionCount: 0,
                aiCompanionGuardianActionCount: 0,
                openWishCount: 0,
                pendingRewardActionCount: 0,
                averageProgress: 0
            )
        )
    }
}
