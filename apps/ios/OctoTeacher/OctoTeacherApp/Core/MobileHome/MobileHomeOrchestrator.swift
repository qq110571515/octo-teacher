import Foundation

/// 移动平台首页编排器。
///
/// 把三个本地数据源编排成角色感知的首页模型：
/// - `MobileSyncClient`：移动同步 mock snapshot（今日任务、成长积分余额、奖励会话、成长动态）。
/// - `SchoolFamilyStore`：学校作业、家庭成长动态、徽章、荣誉墙、亲友评论（待审核）。
/// - `LocalFamilyStore`：任务包审批闭环、亲友参与摘要、家庭事件流。
///
/// 这是**纯逻辑、可测试**的编排层：给定数据源即可在无 SwiftUI 环境下产出 `MobileHomeViewModel`。
/// 安全边界见 `MobileHomeModels`。编排器只读不写：绝不调用任何会批准任务、发成长积分或开奖励
/// 会话的写方法。
struct MobileHomeOrchestrator {
    let sync: MobileSyncClient
    let schoolFamily: SchoolFamilyStore
    let family: LocalFamilyStore
    let growthPackInstallBuilder: GrowthPackInstallEntitlementBuilder
    let permissionGateway: MobilePlatformPermissionGatewayAdapter
    let growthPackCloudSyncBuilder: GrowthPackCloudSyncMobileBridgeBuilder
    let aiHomeworkInboxBuilder: AIHomeworkFamilySchoolInboxBuilder
    let schoolGrowthCreditBuilder: SchoolGrowthCreditSnapshotBuilder
    let schoolJointApprovalBuilder: SchoolJointApprovalSnapshotBuilder
    let moduleConfigurationDraftBuilder: MobileModuleConfigurationDraftBuilder
    let growthRuntimeReport: GrowthRuntimeSettlementReport

    init(
        sync: MobileSyncClient,
        schoolFamily: SchoolFamilyStore,
        family: LocalFamilyStore,
        growthPackInstallBuilder: GrowthPackInstallEntitlementBuilder = GrowthPackInstallEntitlementBuilder(),
        permissionGateway: MobilePlatformPermissionGatewayAdapter = MobilePlatformPermissionGatewayAdapter(),
        growthPackCloudSyncBuilder: GrowthPackCloudSyncMobileBridgeBuilder = GrowthPackCloudSyncMobileBridgeBuilder(),
        aiHomeworkInboxBuilder: AIHomeworkFamilySchoolInboxBuilder = AIHomeworkFamilySchoolInboxBuilder(),
        schoolGrowthCreditBuilder: SchoolGrowthCreditSnapshotBuilder = SchoolGrowthCreditSnapshotBuilder(),
        schoolJointApprovalBuilder: SchoolJointApprovalSnapshotBuilder = SchoolJointApprovalSnapshotBuilder(),
        moduleConfigurationDraftBuilder: MobileModuleConfigurationDraftBuilder = MobileModuleConfigurationDraftBuilder(),
        growthRuntimeReport: GrowthRuntimeSettlementReport? = nil
    ) {
        self.sync = sync
        self.schoolFamily = schoolFamily
        self.family = family
        self.growthPackInstallBuilder = growthPackInstallBuilder
        self.permissionGateway = permissionGateway
        self.growthPackCloudSyncBuilder = growthPackCloudSyncBuilder
        self.aiHomeworkInboxBuilder = aiHomeworkInboxBuilder
        self.schoolGrowthCreditBuilder = schoolGrowthCreditBuilder
        self.schoolJointApprovalBuilder = schoolJointApprovalBuilder
        self.moduleConfigurationDraftBuilder = moduleConfigurationDraftBuilder
        self.growthRuntimeReport = growthRuntimeReport
            ?? GrowthPackRuntimeStore().refresh(family: family, schoolFamily: schoolFamily)
    }

    private var snapshot: MobileSyncSnapshot { sync.snapshot }

    /// 首页聚焦的主孩子（snapshot 第一个孩子）。
    private var primaryChild: MobileSyncSnapshot.Child? { snapshot.children.first }

    // MARK: - 入口

    func makeViewModel(for perspective: MobileHomePerspective) -> MobileHomeViewModel {
        switch perspective {
        case .child:
            return childViewModel()
        case .parent:
            return parentViewModel()
        }
    }

    // MARK: - 会话与取值

    private func guardianSession() -> MobileSyncSession {
        MobileSyncSession(
            actorPublicRef: "guardian:home",
            actorRole: .guardian,
            familyPublicRef: snapshot.family.publicRef
        )
    }

    private func childSession(_ child: MobileSyncSnapshot.Child) -> MobileSyncSession {
        MobileSyncSession(
            actorPublicRef: child.publicRef,
            actorRole: .child,
            familyPublicRef: child.familyPublicRef,
            childPublicRef: child.publicRef
        )
    }

    private func value<T>(_ result: Result<T, MobileSyncError>) -> T? {
        try? result.get()
    }

    /// 把脱敏 publicRef 解析成可展示昵称；找不到回退到「孩子」，绝不暴露原始 ref。
    private func childName(_ publicRef: String) -> String {
        snapshot.children.first { $0.publicRef == publicRef }?.displayName ?? "孩子"
    }

    // MARK: - 孩子视角

    private func childViewModel() -> MobileHomeViewModel {
        guard let child = primaryChild else {
            return MobileHomeViewModel(
                perspective: .child,
                greeting: "你好",
                headline: "暂时还没有今天的安排",
                metrics: [],
                sections: []
            )
        }

        let session = childSession(child)
        let tasks = value(sync.todayTasks(session: session)) ?? []
        let balance = value(sync.creditBalance(session: session))
        let rewards = value(sync.rewardSessions(session: session)) ?? []
        let openHomeworks = schoolFamily.openHomeworks
        let feed = schoolFamily.visibleFeed(for: .household)
        let activeRewards = rewards.filter { $0.status == .active }
        let growthPackInstall = growthPackInstallBuilder.build(viewerRole: .child)
        let growthPackNeedsGuardian = growthPackInstall.publicSummary.gatedCount + growthPackInstall.publicSummary.blockedCount
        let cloudSync = growthPackCloudSyncBuilder.build(viewerRole: .child)
        let cloudSyncState = Self.visibleGrowthPackCloudSyncState(cloudSync)
        let homeworkInbox = aiHomeworkInboxBuilder.build(viewerRole: .child, homeworks: schoolFamily.homeworks)
        let homeworkInboxStatus = Self.visibleAIHomeworkInboxStatus(homeworkInbox)
        let childSchoolCredit = schoolGrowthCreditBuilder.build(viewerRole: .child, homeworks: schoolFamily.homeworks)
        let jointApproval = schoolJointApprovalBuilder.build(
            viewerRole: .child,
            homeworks: schoolFamily.homeworks,
            schoolCredit: childSchoolCredit
        )
        let jointApprovalStatus = Self.visibleSchoolJointApprovalStatus(jointApproval)
        let configurationDraft = moduleConfigurationDraftBuilder.build(
            viewerRole: .child,
            family: family,
            schoolFamily: schoolFamily
        )
        assert(!configurationDraft.sideEffects.hasTriggeredSideEffect)
        let configurationDraftStatus = Self.visibleModuleConfigurationDraftStatus(configurationDraft)
        let growthRuntime = Self.visibleGrowthRuntimeReport(growthRuntimeReport)
        let growthRuntimeAttentionCount = Self.childGrowthRuntimeAttentionCount(growthRuntime)

        let actionableTasks = tasks.filter { Self.isActionable($0.status) }
        let awaitingTasks = tasks.filter { $0.status == .submitted }

        let headline: String
        if actionableTasks.isEmpty && openHomeworks.isEmpty {
            headline = "今天的任务和作业都完成啦，真棒！"
        } else {
            headline = "今天还有 \(actionableTasks.count) 个任务、\(openHomeworks.count) 份作业要处理"
        }

        var metrics: [MobileHomeMetric] = [
            MobileHomeMetric(
                id: "today-tasks",
                title: "今日任务",
                value: "\(actionableTasks.count)",
                caption: actionableTasks.isEmpty ? "已完成" : "待完成",
                tone: actionableTasks.isEmpty ? .positive : .attention
            ),
            MobileHomeMetric(
                id: "credits",
                title: "可用积分",
                value: "\(balance?.availableCredits ?? 0)",
                caption: "完成任务积累",
                tone: .neutral
            ),
            MobileHomeMetric(
                id: "reward",
                title: "进行中奖励",
                value: "\(activeRewards.count)",
                caption: activeRewards.isEmpty ? "未开启" : "家长已开启",
                tone: activeRewards.isEmpty ? .neutral : .positive
            ),
            MobileHomeMetric(
                id: "growth-pack-entitlements",
                title: "成长包",
                value: "\(growthPackInstall.publicSummary.installedCount)",
                caption: growthPackNeedsGuardian == 0 ? "可继续挑战" : "\(growthPackNeedsGuardian) 个待家长确认",
                tone: growthPackInstall.publicSummary.installedCount > 0 ? .positive : .neutral
            ),
            MobileHomeMetric(
                id: "growth-pack-cloud-sync",
                title: "成长包云同步",
                value: cloudSyncState == .ready ? "正常" : "待确认",
                caption: Self.childGrowthPackCloudSyncHomeDetail(cloudSyncState),
                tone: Self.growthPackCloudSyncTone(cloudSyncState)
            ),
            MobileHomeMetric(
                id: "ai-homework-inbox",
                title: "家校作业",
                value: "\(homeworkInbox.publicSummary.homeworkCount)",
                caption: Self.childAIHomeworkInboxHomeDetail(homeworkInboxStatus),
                tone: Self.aiHomeworkInboxTone(homeworkInboxStatus)
            ),
            MobileHomeMetric(
                id: "school-joint-approval",
                title: "家校确认",
                value: "\(jointApproval.publicSummary.visibleItemCount)",
                caption: Self.childSchoolJointApprovalHomeDetail(jointApprovalStatus),
                tone: Self.schoolJointApprovalTone(jointApprovalStatus)
            ),
            MobileHomeMetric(
                id: "module-configuration-draft",
                title: "模块安排",
                value: "\(configurationDraft.publicSummary.visibleItemCount)",
                caption: Self.childModuleConfigurationDraftHomeDetail(configurationDraftStatus),
                tone: Self.moduleConfigurationDraftTone(configurationDraftStatus)
            ),
            MobileHomeMetric(
                id: "growth-runtime-actions",
                title: "成长闭环",
                value: "\(growthRuntime.publicSummary.stepCount)",
                caption: Self.childGrowthRuntimeHomeDetail(growthRuntime),
                tone: Self.growthRuntimeTone(growthRuntime)
            )
        ]
        if let balance, balance.heldCredits > 0 {
            metrics.append(
                MobileHomeMetric(
                    id: "held",
                    title: "锁定积分",
                    value: "\(balance.heldCredits)",
                    caption: "用于奖励会话",
                    tone: .neutral
                )
            )
        }

        var sections: [MobileHomeSection] = []

        // 今日任务
        sections.append(
            MobileHomeSection(
                id: "today",
                title: "今日任务",
                subtitle: awaitingTasks.isEmpty ? nil : "\(awaitingTasks.count) 个已提交，正在等家长验证",
                items: tasks.map { task in
                    MobileHomeItem(
                        id: "task-\(task.id)",
                        title: task.title,
                        detail: Self.taskDetail(task),
                        systemImage: Self.categoryIcon(task.category),
                        tone: Self.taskTone(task.status),
                        badge: Self.taskStatusLabel(task.status)
                    )
                },
                emptyText: "今天没有安排任务"
            )
        )

        // 学校作业
        sections.append(
            MobileHomeSection(
                id: "homework",
                title: "学校作业",
                subtitle: "AI 只给引导提示，不给答案；提交后进入待验证",
                items: openHomeworks.map { homework in
                    MobileHomeItem(
                        id: "hw-\(homework.id)",
                        title: homework.title,
                        detail: "\(homework.subject.label) · \(homework.dueLabel)",
                        systemImage: homework.subject.systemImage,
                        tone: homework.status == .returned ? .attention : .neutral,
                        badge: homework.status.label
                    )
                },
                emptyText: "暂时没有待处理的作业"
            )
        )
        sections.append(
            MobileHomeSection(
                id: "ai-homework-inbox",
                title: "家校作业收件箱",
                subtitle: "只显示安全下一步；不会调用 AI、写学校系统或发成长积分",
                items: [
                    MobileHomeItem(
                        id: "ai-homework-inbox-next",
                        title: "作业下一步",
                        detail: Self.childAIHomeworkInboxHomeDetail(homeworkInboxStatus),
                        systemImage: Self.aiHomeworkInboxIcon(homeworkInboxStatus),
                        tone: Self.aiHomeworkInboxTone(homeworkInboxStatus),
                        badge: homeworkInboxStatus.label,
                        destination: .aiHomeworkInbox
                    )
                ],
                emptyText: "暂时没有家校作业提示"
            )
        )
        let childJointItems = jointApproval.items.prefix(3).map { item in
            MobileHomeItem(
                id: "school-joint-\(item.stage.rawValue)-\(item.subjectLabel)",
                title: item.headline,
                detail: item.childSafeCopy,
                systemImage: Self.schoolJointApprovalIcon(jointApprovalStatus),
                tone: Self.schoolJointApprovalTone(jointApprovalStatus),
                badge: item.stage.label,
                destination: .schoolJointApproval
            )
        }
        sections.append(
            MobileHomeSection(
                id: "school-joint-approval",
                title: "学校联合审批",
                subtitle: "只显示安全进度；不会验证老师、确认家长、写学校或发成长积分",
                items: childJointItems,
                emptyText: Self.childSchoolJointApprovalHomeDetail(jointApprovalStatus)
            )
        )

        // 成长动态（家庭私密视角，孩子可见自己的全部）
        sections.append(
            MobileHomeSection(
                id: "growth",
                title: "成长动态",
                subtitle: "家庭私密内容默认不外传，亲友需家长放开才可见",
                items: feed.prefix(3).map { entry in
                    MobileHomeItem(
                        id: "feed-\(entry.id)",
                        title: entry.title,
                        detail: entry.summary,
                        systemImage: "sparkles",
                        tone: .positive,
                        badge: entry.visibility.label
                    )
                },
                emptyText: "还没有成长动态"
            )
        )

        sections.append(
            MobileHomeSection(
                id: "growth-pack-entitlements",
                title: "成长包权益",
                subtitle: "孩子端只显示可运行摘要；购买、退款和权益由家长确认",
                items: growthPackInstall.decisions.prefix(4).map { decision in
                    MobileHomeItem(
                        id: "growth-pack-\(decision.packPublicRef)",
                        title: Self.growthPackDisplayText(decision.title, fallback: "成长包"),
                        detail: Self.childGrowthPackHomeDetail(decision.state),
                        systemImage: Self.growthPackIcon(decision.state),
                        tone: Self.growthPackTone(decision.state),
                        badge: decision.state.label,
                        destination: .growthPackEntitlements
                    )
                },
                emptyText: "等待家长选择成长包"
            )
        )
        sections.append(
            MobileHomeSection(
                id: "growth-pack-cloud-sync",
                title: "成长包云同步",
                subtitle: "只显示下一步提示；不会购买、发成长积分或解锁设备",
                items: [
                    MobileHomeItem(
                        id: "growth-pack-cloud-sync-next",
                        title: "同步状态",
                        detail: Self.childGrowthPackCloudSyncHomeDetail(cloudSyncState),
                        systemImage: Self.growthPackCloudSyncIcon(cloudSyncState),
                        tone: Self.growthPackCloudSyncTone(cloudSyncState),
                        badge: cloudSyncState.label,
                        destination: .growthPackCloudSync
                    )
                ],
                emptyText: "暂时没有成长包同步提示"
            )
        )
        sections.append(
            MobileHomeSection(
                id: "growth-pack-execution-hub",
                title: "成长包执行中心",
                subtitle: "把作业、测验、资源、创作和奖励下一步放在一起；这里只读，不会自动完成",
                items: [
                    MobileHomeItem(
                        id: "growth-pack-execution-hub-entry",
                        title: "今天的成长包步骤",
                        detail: "查看今天能做什么、下一步和安全提示；完成后仍要等家长或老师确认。",
                        systemImage: "square.stack.3d.up",
                        tone: .attention,
                        badge: "只读",
                        destination: .growthPackExecutionHub
                    )
                ],
                emptyText: "暂时没有成长包执行提示"
            )
        )
        var runtimeItems = growthRuntime.steps
            .filter { Self.childGrowthRuntimeShouldShow($0) }
            .prefix(4)
            .enumerated()
            .map { index, step in
                MobileHomeItem(
                    id: "growth-runtime-child-\(index + 1)",
                    title: Self.growthRuntimeDisplayText(step.title, fallback: step.kindLabel),
                    detail: Self.childGrowthRuntimeStepDetail(step),
                    systemImage: Self.growthRuntimeIcon(step.status),
                    tone: Self.growthRuntimeTone(step.status),
                    badge: step.statusLabel,
                    destination: .growthPackExecutionHub
                )
            }
        if runtimeItems.isEmpty {
            runtimeItems.append(
                MobileHomeItem(
                    id: "growth-runtime-child-summary",
                    title: "成长包下一步",
                    detail: "暂时没有需要你处理的成长包步骤，可以继续看今天任务。",
                    systemImage: "square.stack.3d.up",
                    tone: .neutral,
                    badge: "只读",
                    destination: .growthPackExecutionHub
                )
            )
        }
        sections.append(
            MobileHomeSection(
                id: "growth-runtime-actions",
                title: "成长包闭环下一步",
                subtitle: "只展示安全下一步；不会发成长积分、授徽章、改能力卡或解锁设备",
                items: runtimeItems,
                emptyText: "暂时没有成长包闭环提示"
            )
        )
        sections.append(
            MobileHomeSection(
                id: "module-configuration-draft",
                title: "模块配置草稿",
                subtitle: "只显示今天的安全安排；不会配置模块、发放积分或解锁设备",
                items: [
                    MobileHomeItem(
                        id: "module-configuration-draft-summary",
                        title: "今日安排预览",
                        detail: Self.childModuleConfigurationDraftHomeDetail(configurationDraftStatus),
                        systemImage: Self.moduleConfigurationDraftIcon(configurationDraftStatus),
                        tone: Self.moduleConfigurationDraftTone(configurationDraftStatus),
                        badge: configurationDraftStatus.label
                    )
                ],
                emptyText: "暂时没有模块安排预览"
            )
        )

        // 成长积分与奖励状态
        var creditItems: [MobileHomeItem] = []
        if let balance {
            creditItems.append(
                MobileHomeItem(
                    id: "credit-available",
                    title: "可用积分 \(balance.availableCredits)",
                    detail: "累计获得 \(balance.totalEarnedCredits) · 已使用 \(balance.spentCredits)",
                    systemImage: "star.circle",
                    tone: .neutral,
                    destination: .rewardRedemption
                )
            )
        }
        for reward in activeRewards {
            creditItems.append(
                MobileHomeItem(
                    id: "reward-\(reward.id)",
                    title: "\(Self.rewardLabel(reward.rewardType)) \(reward.plannedMinutes) 分钟",
                    detail: "家长已开启的奖励会话",
                    systemImage: "timer",
                    tone: .positive,
                    badge: "进行中",
                    destination: .rewardRedemption
                )
            )
        }
        creditItems.append(
            MobileHomeItem(
                id: "reward-guard",
                title: "奖励要先攒够积分，再请家长开启",
                detail: "孩子不能自行解锁设备；任务验证和成长积分发放由家长流程处理",
                systemImage: "lock.shield",
                tone: .neutral,
                destination: .rewardRedemption
            )
        )
        sections.append(
            MobileHomeSection(id: "credit", title: "成长积分与奖励", items: creditItems)
        )

        // 家庭社交反馈情绪安全中心入口（只读）。孩子端只看温和鼓励、等待家长查看和
        // 情绪安全提示，不展示审核原因、评分、成长积分、设备命令、成人讨论或私密内容。
        sections.append(
            MobileHomeSection(
                id: "family-social-feedback-safety",
                title: "情绪安全中心",
                subtitle: "只看温和鼓励和等待家长查看的提示；不会比较表现、不会发积分、不会开启娱乐时间",
                items: [
                    MobileHomeItem(
                        id: "family-social-feedback-safety-entry",
                        title: "看看亲友的温和鼓励",
                        detail: "这里只显示安全鼓励和下一步；难处理的留言会先请家长看一看。",
                        systemImage: "heart.text.square",
                        tone: .neutral,
                        badge: "只读",
                        destination: .familySocialFeedbackEmotionalSafety
                    )
                ]
            )
        )

        // 奖励商店库存履约入口（只读）。孩子端只看奖励能不能换、还剩多少与下一步，
        // 不暴露订单、库存内部 ID、地址、退款原因、账本明细或设备命令；进入页锁定孩子视角，
        // 孩子无法切到家长复核页。本页不真实兑换、不扣成长积分、不发货、不解锁设备。
        sections.append(
            MobileHomeSection(
                id: "reward-store-fulfillment",
                title: "奖励商店",
                subtitle: "只看奖励还能不能换、还剩多少；不会真的兑换、不会扣成长积分、不会改娱乐时间",
                items: [
                    MobileHomeItem(
                        id: "reward-store-fulfillment-entry",
                        title: "奖励商店",
                        detail: "看奖励能不能换、还剩多少；想换什么先告诉家长，本页不会真的兑换。",
                        systemImage: "gift",
                        tone: .neutral,
                        badge: "只读",
                        destination: .rewardStoreFulfillment
                    )
                ]
            )
        )

        // 离线同步本地复核台入口（只读）。孩子端只看安全同步状态与下一步。
        sections.append(
            MobileHomeSection(
                id: "offline-sync-review",
                title: "同步复核台",
                subtitle: "只看安全的同步状态和下一步；不会发积分、不会解锁设备",
                items: [
                    MobileHomeItem(
                        id: "offline-sync-review-entry",
                        title: "同步复核台",
                        detail: "看任务、作业有没有同步好；不会发积分、不会解锁设备",
                        systemImage: "arrow.triangle.2.circlepath",
                        tone: .neutral,
                        badge: "只读",
                        destination: .offlineSyncReview
                    )
                ]
            )
        )

        let childPermissionHome = MobileHomeViewModel(
            perspective: .child,
            greeting: "你好，\(child.displayName)",
            headline: headline,
            metrics: metrics,
            sections: sections
        )
        sections.append(
            permissionGatewaySection(
                viewerRole: .child,
                subtitle: "本地只读状态；不会发成长积分或解锁设备",
                home: childPermissionHome
            )
        )

        // 下一步行动
        var nextSteps: [MobileHomeItem] = []
        if !actionableTasks.isEmpty {
            nextSteps.append(
                MobileHomeItem(
                    id: "next-task",
                    title: "完成今天剩下的 \(actionableTasks.count) 个任务",
                    detail: actionableTasks.first.map { "从「\($0.title)」开始" },
                    systemImage: "checklist",
                    tone: .attention
                )
            )
        }
        if !openHomeworks.isEmpty {
            nextSteps.append(
                MobileHomeItem(
                    id: "next-homework",
                    title: "提交 \(openHomeworks.count) 份作业证明，等待验证",
                    detail: "在「School」标签里查看引导与自检清单",
                    systemImage: "tray.and.arrow.up",
                    tone: .attention
                )
            )
        }
        if !awaitingTasks.isEmpty {
            nextSteps.append(
                MobileHomeItem(
                    id: "next-await",
                    title: "\(awaitingTasks.count) 个任务已提交，等家长验证",
                    detail: "通过后会自动发放积分",
                    systemImage: "hourglass",
                    tone: .neutral
                )
            )
        }
        if growthRuntimeAttentionCount > 0 {
            nextSteps.append(
                MobileHomeItem(
                    id: "next-growth-runtime",
                    title: "查看 \(growthRuntimeAttentionCount) 个成长包下一步",
                    detail: "先按提示补证明、等验证或继续已开放步骤。",
                    systemImage: "square.stack.3d.up",
                    tone: Self.growthRuntimeTone(growthRuntime),
                    destination: .growthPackExecutionHub
                )
            )
        }
        if nextSteps.isEmpty {
            nextSteps.append(
                MobileHomeItem(
                    id: "next-done",
                    title: "今天都完成了，去记录一条成长动态吧",
                    systemImage: "hand.thumbsup",
                    tone: .positive
                )
            )
        }
        sections.append(
            MobileHomeSection(id: "next", title: "下一步", items: nextSteps)
        )

        return MobileHomeViewModel(
            perspective: .child,
            greeting: "你好，\(child.displayName)",
            headline: headline,
            metrics: metrics,
            sections: sections
        )
    }

    /// 首页权限闸门分区：改用 A50 共享 ReadModel 驱动。
    ///
    /// 分区 id 仍保持 `permission-gateway`，UI 入口不变；条目改为共享模块键
    /// （`permission-module-*`），孩子端会自动隐藏 marketplace/credit consent 等敏感模块。
    /// 仍是纯本地只读：`buildReadModel` 不触发任何网络、云、AI、LMS、设备或账本写操作。
    private func permissionGatewaySection(
        viewerRole: MobilePlatformPermissionGatewayViewerRole,
        subtitle: String,
        home: MobileHomeViewModel
    ) -> MobileHomeSection {
        let report = permissionGateway.buildReadModel(viewerRole: viewerRole, home: home)
        assert(!report.sideEffects.hasTriggeredSideEffect)
        return MobileHomeSection(
            id: "permission-gateway",
            title: "平台权限闸门",
            subtitle: subtitle,
            items: permissionGateway.homeItems(from: report),
            emptyText: "暂无对当前角色开放的平台模块"
        )
    }

    // MARK: - 家长视角

    private func parentViewModel() -> MobileHomeViewModel {
        let session = guardianSession()

        // 待审批：跨三个数据源汇总。
        var approvalItems: [MobileHomeItem] = []

        // 1) 移动同步待验证提交（status == submitted）。
        let syncSubmissions = snapshot.submissions.filter { $0.status == "submitted" }
        for submission in syncSubmissions {
            let taskTitle = snapshot.tasks.first { $0.clientTaskRef == submission.clientTaskRef }?.title ?? "任务证明"
            approvalItems.append(
                MobileHomeItem(
                    id: "approve-sync-\(submission.id)",
                    title: taskTitle,
                    detail: "\(childName(submission.childPublicRef)) · \(submission.evidenceSummaryPreview)",
                    systemImage: "doc.badge.clock",
                    tone: .attention,
                    badge: "同步任务待验证"
                )
            )
        }

        // 2) 任务包审批闭环里已提交待批准的任务。
        let pendingAssignments = family.assignments.filter { $0.status == .submitted }
        for assignment in pendingAssignments {
            approvalItems.append(
                MobileHomeItem(
                    id: "approve-pack-\(assignment.id)",
                    title: assignment.task.title,
                    detail: "奖励 \(assignment.task.rewardMinutes) 成长积分 · 在「Parent」标签批准",
                    systemImage: "checkmark.seal",
                    tone: .attention,
                    badge: "任务包待批准"
                )
            )
        }

        // 3) 学校作业已提交待验证。
        let submittedHomeworks = schoolFamily.homeworks.filter { $0.status == .submitted }
        for homework in submittedHomeworks {
            approvalItems.append(
                MobileHomeItem(
                    id: "approve-hw-\(homework.id)",
                    title: homework.title,
                    detail: "\(homework.subject.label) · 等待老师/家长验证",
                    systemImage: "graduationcap",
                    tone: .attention,
                    badge: "作业待验证"
                )
            )
        }

        // 亲友待审核摘要。
        let pendingComments = schoolFamily.relativeComments.filter { $0.status == .pending }
        let pendingHonors = schoolFamily.honorWall.filter { $0.approval == .pending }
        let relativeSummary = family.relativeParticipationSummary
        let relativePendingCount = pendingComments.count + pendingHonors.count
        let growthPackInstall = growthPackInstallBuilder.build(viewerRole: .guardian)
        let growthPackNeedsReview = growthPackInstall.decisions.filter {
            switch $0.state {
            case .pendingGuardianConfirmation, .frozen, .blocked:
                return true
            case .installable, .installed, .hidden:
                return false
            }
        }
        let cloudSync = growthPackCloudSyncBuilder.build(viewerRole: .guardian)
        let cloudSyncState = Self.visibleGrowthPackCloudSyncState(cloudSync)
        let homeworkInbox = aiHomeworkInboxBuilder.build(viewerRole: .guardian, homeworks: schoolFamily.homeworks)
        let homeworkInboxStatus = Self.visibleAIHomeworkInboxStatus(homeworkInbox)
        let guardianSchoolCredit = schoolGrowthCreditBuilder.build(viewerRole: .guardian, homeworks: schoolFamily.homeworks)
        let jointApproval = schoolJointApprovalBuilder.build(
            viewerRole: .guardian,
            homeworks: schoolFamily.homeworks,
            schoolCredit: guardianSchoolCredit
        )
        let jointApprovalStatus = Self.visibleSchoolJointApprovalStatus(jointApproval)
        let jointApprovalActionCount = Self.parentSchoolJointApprovalActionCount(jointApproval)
        let configurationDraft = moduleConfigurationDraftBuilder.build(
            viewerRole: .guardian,
            family: family,
            schoolFamily: schoolFamily
        )
        assert(!configurationDraft.sideEffects.hasTriggeredSideEffect)
        let configurationDraftStatus = Self.visibleModuleConfigurationDraftStatus(configurationDraft)
        let configurationDraftActionCount = Self.parentModuleConfigurationDraftActionCount(configurationDraft)
        let configurationDraftBlockingActionCount = Self.parentModuleConfigurationDraftBlockingActionCount(configurationDraft)
        let growthRuntime = Self.visibleGrowthRuntimeReport(growthRuntimeReport)
        let growthRuntimeActionCount = Self.parentGrowthRuntimeActionCount(growthRuntime)

        // 成长积分 / 奖励风险。
        var riskItems: [MobileHomeItem] = []
        for child in snapshot.children {
            guard let balance = value(sync.creditBalance(session: session, childPublicRef: child.publicRef)) else { continue }
            if balance.expiringSoonCredits > 0 {
                riskItems.append(
                    MobileHomeItem(
                        id: "risk-expire-\(child.id)",
                        title: "\(child.displayName) 有 \(balance.expiringSoonCredits) 积分即将过期",
                        detail: "可提醒孩子尽快兑换或安排奖励",
                        systemImage: "exclamationmark.triangle",
                        tone: .risk,
                        badge: "即将过期",
                        destination: .rewardStatus
                    )
                )
            }
            if balance.heldCredits > 0 {
                riskItems.append(
                    MobileHomeItem(
                        id: "risk-held-\(child.id)",
                        title: "\(child.displayName) 有 \(balance.heldCredits) 积分锁定在奖励会话",
                        detail: "奖励结束或失败会自动退回",
                        systemImage: "lock",
                        tone: .neutral,
                        badge: "锁定中",
                        destination: .rewardStatus
                    )
                )
            }
            let active = (value(sync.rewardSessions(session: session, childPublicRef: child.publicRef)) ?? [])
                .filter { $0.status == .active }
            for reward in active {
                riskItems.append(
                    MobileHomeItem(
                        id: "risk-reward-\(reward.id)",
                        title: "\(child.displayName) 正在进行 \(reward.plannedMinutes) 分钟\(Self.rewardLabel(reward.rewardType))",
                        detail: reward.deviceCommandQueued ? "设备命令已排队（未真正解锁设备）" : "等待设备命令",
                        systemImage: "timer",
                        tone: .attention,
                        badge: "奖励进行中",
                        destination: .rewardStatus
                    )
                )
            }
        }
        // 越权防线：亲友若被错误标记成可发成长积分/可解锁，要在风险区高亮（正常应恒为 false）。
        if relativeSummary.anyRelativeCanGrantCredit || relativeSummary.anyRelativeCanUnlockDevice {
            riskItems.append(
                MobileHomeItem(
                    id: "risk-relative-power",
                    title: "检测到亲友被授予越权能力，请立即收回",
                    detail: "亲友不应能发成长积分或解锁设备",
                    systemImage: "exclamationmark.octagon",
                    tone: .risk,
                    badge: "越权"
                )
            )
        }

        let pendingTotal = approvalItems.count
        let headline = pendingTotal == 0
            ? "暂无待审批，一切顺利"
            : "有 \(pendingTotal) 项待你审批"

        let metrics: [MobileHomeMetric] = [
            MobileHomeMetric(
                id: "pending",
                title: "待审批",
                value: "\(pendingTotal)",
                caption: "任务与作业",
                tone: pendingTotal == 0 ? .positive : .attention
            ),
            MobileHomeMetric(
                id: "relative-review",
                title: "亲友待审核",
                value: "\(relativePendingCount)",
                caption: "评论与荣誉",
                tone: relativePendingCount == 0 ? .positive : .attention
            ),
            MobileHomeMetric(
                id: "risk",
                title: "风险提示",
                value: "\(riskItems.count)",
                caption: riskItems.isEmpty ? "无" : "需关注",
                tone: riskItems.contains { $0.tone == .risk } ? .risk : (riskItems.isEmpty ? .positive : .attention)
            ),
            MobileHomeMetric(
                id: "growth-pack-entitlements",
                title: "成长包需关注",
                value: "\(growthPackNeedsReview.count)",
                caption: "确认/异常",
                tone: growthPackNeedsReview.contains { $0.state == .blocked || $0.state == .frozen } ? .risk : (growthPackNeedsReview.isEmpty ? .positive : .attention)
            ),
            MobileHomeMetric(
                id: "growth-pack-cloud-sync",
                title: "云同步复核",
                value: "\(cloudSync.publicSummary.actionRequiredCount)",
                caption: cloudSync.publicSummary.actionRequiredCount == 0 ? "正常" : "待处理",
                tone: Self.growthPackCloudSyncTone(cloudSyncState)
            ),
            MobileHomeMetric(
                id: "ai-homework-inbox",
                title: "家校复核",
                value: "\(homeworkInbox.publicSummary.actionRequiredCount)",
                caption: homeworkInbox.publicSummary.actionRequiredCount == 0 ? "正常" : "待处理",
                tone: Self.aiHomeworkInboxTone(homeworkInboxStatus)
            ),
            MobileHomeMetric(
                id: "school-joint-approval",
                title: "联合审批",
                value: "\(jointApprovalActionCount)",
                caption: jointApprovalActionCount == 0 ? "正常" : "待处理",
                tone: Self.schoolJointApprovalTone(jointApprovalStatus)
            ),
            MobileHomeMetric(
                id: "module-configuration-draft",
                title: "配置草稿",
                value: "\(configurationDraftActionCount)",
                caption: configurationDraftActionCount == 0 ? "正常" : "待复核",
                tone: Self.moduleConfigurationDraftTone(configurationDraftStatus)
            ),
            MobileHomeMetric(
                id: "growth-runtime-actions",
                title: "成长闭环复核",
                value: "\(growthRuntimeActionCount)",
                caption: growthRuntimeActionCount == 0 ? "正常" : "待处理",
                tone: Self.growthRuntimeTone(growthRuntime)
            )
        ]

        var sections: [MobileHomeSection] = []

        sections.append(
            MobileHomeSection(
                id: "approvals",
                title: "待审批",
                subtitle: "在对应标签里逐项批准；批准前不会发放任何成长积分",
                items: approvalItems,
                emptyText: "没有待审批的任务或作业"
            )
        )
        var homeworkInboxItems = [
            MobileHomeItem(
                id: "ai-homework-inbox-summary",
                title: "家校复核状态",
                detail: Self.parentAIHomeworkInboxHomeDetail(homeworkInboxStatus),
                systemImage: Self.aiHomeworkInboxIcon(homeworkInboxStatus),
                tone: Self.aiHomeworkInboxTone(homeworkInboxStatus),
                badge: homeworkInboxStatus.label,
                destination: .aiHomeworkInbox
            )
        ]
        if homeworkInbox.publicSummary.teacherReviewCount > 0 {
            homeworkInboxItems.append(
                MobileHomeItem(
                    id: "ai-homework-inbox-teacher-review",
                    title: "老师复核 \(homeworkInbox.publicSummary.teacherReviewCount) 项",
                    detail: "只显示学校作业复核状态；首页不写回学校系统。",
                    systemImage: "graduationcap",
                    tone: .attention,
                    badge: "老师"
                )
            )
        }
        if homeworkInbox.publicSummary.guardianReviewCount > 0 {
            homeworkInboxItems.append(
                MobileHomeItem(
                    id: "ai-homework-inbox-guardian-review",
                    title: "家长复核 \(homeworkInbox.publicSummary.guardianReviewCount) 项",
                    detail: "只生成复核提醒；首页不批准作业、不发成长积分。",
                    systemImage: "person.badge.clock",
                    tone: .attention,
                    badge: "家长"
                )
            )
        }
        if homeworkInbox.publicSummary.lmsBlockedCount > 0 {
            homeworkInboxItems.append(
                MobileHomeItem(
                    id: "ai-homework-inbox-lms-blocked",
                    title: "学校边界阻断",
                    detail: "AI 或学校边界已阻断，需走人工复核。",
                    systemImage: "shield.slash",
                    tone: .risk,
                    badge: "阻断"
                )
            )
        }
        if homeworkInbox.publicSummary.actionRequiredCount > 0 {
            homeworkInboxItems.append(
                MobileHomeItem(
                    id: "ai-homework-inbox-review",
                    title: "需要复核 \(homeworkInbox.publicSummary.actionRequiredCount) 项",
                    detail: "首页只汇总状态，不调用模型、不写账本、不解锁设备。",
                    systemImage: "tray.full",
                    tone: Self.aiHomeworkInboxTone(homeworkInboxStatus),
                    badge: "只读"
                )
            )
        }
        sections.append(
            MobileHomeSection(
                id: "ai-homework-inbox",
                title: "AI作业家校收件箱",
                subtitle: "首页只读提示；AI 引导、学校验证、成长积分建议和设备奖励仍走专属流程",
                items: homeworkInboxItems,
                emptyText: "暂无家校作业复核提示"
            )
        )
        var jointApprovalItems = [
            MobileHomeItem(
                id: "school-joint-approval-summary",
                title: "联合审批状态",
                detail: Self.parentSchoolJointApprovalHomeDetail(jointApprovalStatus),
                systemImage: Self.schoolJointApprovalIcon(jointApprovalStatus),
                tone: Self.schoolJointApprovalTone(jointApprovalStatus),
                badge: jointApprovalStatus.label,
                destination: .schoolJointApproval
            )
        ]
        if jointApproval.publicSummary.awaitingTeacherCount > 0 {
            jointApprovalItems.append(
                MobileHomeItem(
                    id: "school-joint-awaiting-teacher",
                    title: "等老师验证 \(jointApproval.publicSummary.awaitingTeacherCount) 项",
                    detail: "只显示学校验证状态；首页不写回学校系统或 LMS。",
                    systemImage: "graduationcap",
                    tone: .attention,
                    badge: "老师"
                )
            )
        }
        if jointApproval.publicSummary.awaitingGuardianCount > 0 {
            jointApprovalItems.append(
                MobileHomeItem(
                    id: "school-joint-awaiting-guardian",
                    title: "等家长确认 \(jointApproval.publicSummary.awaitingGuardianCount) 项",
                    detail: "确认仍需到专属流程；首页不确认作业、不发成长积分。",
                    systemImage: "person.badge.clock",
                    tone: .attention,
                    badge: "家长"
                )
            )
        }
        if jointApproval.publicSummary.returnedCount > 0 {
            jointApprovalItems.append(
                MobileHomeItem(
                    id: "school-joint-returned",
                    title: "退回重做 \(jointApproval.publicSummary.returnedCount) 项",
                    detail: "退回作业不进入成长积分建议，等待重新提交。",
                    systemImage: "arrow.uturn.backward.circle",
                    tone: .attention,
                    badge: "退回"
                )
            )
        }
        if jointApproval.publicSummary.appealFrozenCount > 0 {
            jointApprovalItems.append(
                MobileHomeItem(
                    id: "school-joint-appeal-frozen",
                    title: "申诉冻结 \(jointApproval.publicSummary.appealFrozenCount) 项",
                    detail: "冻结只显示复核提醒；首页不冻结成长积分或写账本。",
                    systemImage: "pause.circle",
                    tone: .risk,
                    badge: "冻结"
                )
            )
        }
        if jointApproval.publicSummary.offlineRollbackCount > 0 {
            jointApprovalItems.append(
                MobileHomeItem(
                    id: "school-joint-offline-rollback",
                    title: "离线回滚 \(jointApproval.publicSummary.offlineRollbackCount) 项",
                    detail: "离线问题需专属页面复核；首页不应用回滚。",
                    systemImage: "arrow.triangle.2.circlepath",
                    tone: .attention,
                    badge: "离线"
                )
            )
        }
        if jointApproval.publicSummary.creditNoteCount > 0 {
            jointApprovalItems.append(
                MobileHomeItem(
                    id: "school-joint-credit-notes",
                    title: "成长积分建议 \(jointApproval.publicSummary.creditNoteCount) 条",
                    detail: "只读显示建议数量；首页不写账本、不发成长积分、不解锁设备。",
                    systemImage: "star.circle",
                    tone: .attention,
                    badge: "只读"
                )
            )
        }
        sections.append(
            MobileHomeSection(
                id: "school-joint-approval",
                title: "学校联合审批",
                subtitle: "首页只读提示；老师验证、家长确认、成长积分建议和设备奖励仍走专属流程",
                items: jointApprovalItems,
                emptyText: "暂无联合审批复核提示"
            )
        )

        sections.append(
            MobileHomeSection(
                id: "growth-pack-entitlements",
                title: "成长包安装权益",
                subtitle: "首页只做只读提醒；真实购买、退款和权益写入仍需云端权限闸门",
                items: growthPackInstall.decisions.map { decision in
                    MobileHomeItem(
                        id: "growth-pack-\(decision.packPublicRef)",
                        title: Self.growthPackDisplayText(decision.title, fallback: "成长包"),
                        detail: Self.parentGrowthPackHomeDetail(decision.state),
                        systemImage: Self.growthPackIcon(decision.state),
                        tone: Self.growthPackTone(decision.state),
                        badge: decision.state.label,
                        destination: .growthPackEntitlements
                    )
                },
                emptyText: "暂无成长包权益状态"
            )
        )
        var cloudSyncItems = [
            MobileHomeItem(
                id: "growth-pack-cloud-sync-summary",
                title: "复核状态",
                detail: Self.parentGrowthPackCloudSyncHomeDetail(cloudSyncState),
                systemImage: Self.growthPackCloudSyncIcon(cloudSyncState),
                tone: Self.growthPackCloudSyncTone(cloudSyncState),
                badge: cloudSyncState.label,
                destination: .growthPackCloudSync
            )
        ]
        if cloudSync.publicSummary.offlineAttentionCount > 0 {
            cloudSyncItems.append(
                MobileHomeItem(
                    id: "growth-pack-cloud-sync-offline",
                    title: "离线同步待复核",
                    detail: "有 \(cloudSync.publicSummary.offlineAttentionCount) 个离线同步问题，先到专属页面复核。",
                    systemImage: "arrow.triangle.2.circlepath",
                    tone: .attention,
                    badge: "离线",
                    destination: .growthPackCloudSync
                )
            )
        }
        if cloudSync.publicSummary.actionRequiredCount > 0 {
            cloudSyncItems.append(
                MobileHomeItem(
                    id: "growth-pack-cloud-sync-review",
                    title: "需要复核 \(cloudSync.publicSummary.actionRequiredCount) 项",
                    detail: "退款、撤权、同意和冻结只生成提示；首页不自动修复或发成长积分。",
                    systemImage: "person.badge.clock",
                    tone: Self.growthPackCloudSyncTone(cloudSyncState),
                    badge: "只读",
                    destination: .growthPackCloudSync
                )
            )
        }
        sections.append(
            MobileHomeSection(
                id: "growth-pack-cloud-sync",
                title: "成长包云同步",
                subtitle: "首页只读提示；真实修复、退款、权益写入和成长积分结算仍走专属流程",
                items: cloudSyncItems,
                emptyText: "暂无云同步复核提示"
            )
        )
        sections.append(
            MobileHomeSection(
                id: "growth-pack-execution-hub",
                title: "成长包执行复核中心",
                subtitle: "首页只读入口；真实批准、发成长积分、发布作品、履约奖励和设备动作仍走专属流程",
                items: [
                    MobileHomeItem(
                        id: "growth-pack-execution-hub-entry",
                        title: "成长包执行复核",
                        detail: "复核作业、测验、外部资源、创作展示、量规、荣誉和奖励履约风险；首页不写账本、不发成长积分、不解锁设备。",
                        systemImage: "square.stack.3d.up",
                        tone: .attention,
                        badge: "只读",
                        destination: .growthPackExecutionHub
                    )
                ],
                emptyText: "暂无成长包执行复核提示"
            )
        )
        var runtimeReviewItems = [
            MobileHomeItem(
                id: "growth-runtime-parent-summary",
                title: "成长包运行结算投影",
                detail: Self.parentGrowthRuntimeHomeDetail(growthRuntime),
                systemImage: "square.stack.3d.up",
                tone: Self.growthRuntimeTone(growthRuntime),
                badge: "只读",
                destination: .growthPackExecutionHub
            )
        ]
        if growthRuntime.publicSummary.creditSuggestedCount > 0 {
            runtimeReviewItems.append(
                MobileHomeItem(
                    id: "growth-runtime-parent-credit-suggested",
                    title: "可建议结算 \(growthRuntime.publicSummary.creditSuggestedCount) 条",
                    detail: "共 \(growthRuntime.publicSummary.totalSuggestedCredit) 成长积分建议；首页不写账本、不发成长积分、不解锁设备。",
                    systemImage: "lightbulb",
                    tone: .attention,
                    badge: "建议",
                    destination: .growthPackExecutionHub
                )
            )
        }
        if growthRuntime.publicSummary.reviewRequiredCount > 0 {
            runtimeReviewItems.append(
                MobileHomeItem(
                    id: "growth-runtime-parent-review",
                    title: "待复核 \(growthRuntime.publicSummary.reviewRequiredCount) 条",
                    detail: "证明、内容或验证仍需成人确认；首页只读汇总。",
                    systemImage: "person.badge.clock",
                    tone: .attention,
                    badge: "复核",
                    destination: .growthPackExecutionHub
                )
            )
        }
        if growthRuntime.publicSummary.appealingCount > 0 {
            runtimeReviewItems.append(
                MobileHomeItem(
                    id: "growth-runtime-parent-appeal",
                    title: "申诉中 \(growthRuntime.publicSummary.appealingCount) 条",
                    detail: "申诉未结论前保持冻结复核；首页不冻结成长积分或写状态。",
                    systemImage: "exclamationmark.bubble",
                    tone: .risk,
                    badge: "申诉",
                    destination: .growthPackExecutionHub
                )
            )
        }
        if growthRuntime.publicSummary.blockedCount > 0 {
            runtimeReviewItems.append(
                MobileHomeItem(
                    id: "growth-runtime-parent-blocked",
                    title: "已阻断 \(growthRuntime.publicSummary.blockedCount) 条",
                    detail: "缺证明、退回、测验未通过或脱敏异常需专属流程处理。",
                    systemImage: "nosign",
                    tone: .risk,
                    badge: "阻断",
                    destination: .growthPackExecutionHub
                )
            )
        }
        sections.append(
            MobileHomeSection(
                id: "growth-runtime-actions",
                title: "成长包闭环复核",
                subtitle: "首页只读投影；真实批准、发成长积分、授徽章、改能力卡和设备奖励仍走专属流程",
                items: runtimeReviewItems,
                emptyText: "暂无成长包闭环复核提示"
            )
        )
        var configurationDraftItems = [
            MobileHomeItem(
                id: "module-configuration-draft-summary",
                title: "草稿状态",
                detail: Self.parentModuleConfigurationDraftHomeDetail(configurationDraftStatus),
                systemImage: Self.moduleConfigurationDraftIcon(configurationDraftStatus),
                tone: Self.moduleConfigurationDraftTone(configurationDraftStatus),
                badge: configurationDraftStatus.label,
                destination: .moduleConfigurationDraft
            ),
            MobileHomeItem(
                id: "module-configuration-draft-visible-items",
                title: "已编排 \(configurationDraft.publicSummary.visibleItemCount) 个模块安排",
                detail: "预计 \(configurationDraft.publicSummary.estimatedMinutesTotal) 分钟；首页只读，不写入任务。",
                systemImage: "rectangle.grid.2x2",
                tone: .neutral,
                badge: "草稿"
            )
        ]
        if let creditPreviewTotal = configurationDraft.publicSummary.creditPreviewTotal {
            configurationDraftItems.append(
                MobileHomeItem(
                    id: "module-configuration-draft-credit-preview",
                    title: "成长积分预估 \(creditPreviewTotal)",
                    detail: "单位是成长积分，只是家长复核前的预算提醒；积分之后可按家庭规则兑换屏幕时间、零花钱或愿望；首页不写账本、不发成长积分、不解锁设备。",
                    systemImage: "star.circle",
                    tone: creditPreviewTotal > family.child.dailyLimitMinutes ? .attention : .neutral,
                    badge: "只读"
                )
            )
        }
        if configurationDraftActionCount > 0 {
            configurationDraftItems.append(
                MobileHomeItem(
                    id: "module-configuration-draft-review-actions",
                    title: "待复核行动 \(configurationDraftActionCount)",
                    detail: "来自草稿行动队列；首页只汇总，不发布配置。",
                    systemImage: "person.badge.clock",
                    tone: configurationDraftBlockingActionCount > 0 ? .attention : .neutral,
                    badge: "行动",
                    destination: .moduleConfigurationDraft
                )
            )
        }
        if configurationDraftBlockingActionCount > 0 {
            configurationDraftItems.append(
                MobileHomeItem(
                    id: "module-configuration-draft-blocking-actions",
                    title: "复核前阻断 \(configurationDraftBlockingActionCount)",
                    detail: "学校作业、奖励窗口或排序提醒需要先确认；首页不写任务、不发成长积分。",
                    systemImage: "lock.shield",
                    tone: .attention,
                    badge: "阻断",
                    destination: .moduleConfigurationDraft
                )
            )
        }
        for (index, action) in configurationDraft.reviewActions.prefix(3).enumerated() {
            configurationDraftItems.append(
                MobileHomeItem(
                    id: "module-configuration-draft-action-\(index + 1)",
                    title: Self.moduleConfigurationDraftReviewActionTitle(action),
                    detail: Self.moduleConfigurationDraftReviewActionDetail(action),
                    systemImage: action.blockedUntilReviewed ? "lock" : "checkmark.circle",
                    tone: action.blockedUntilReviewed ? .attention : .neutral,
                    badge: action.priority.label,
                    destination: .moduleConfigurationDraft
                )
            )
        }
        for (index, finding) in configurationDraft.findings.filter({ $0.severity != .ok }).prefix(3).enumerated() {
            configurationDraftItems.append(
                MobileHomeItem(
                    id: "module-configuration-draft-finding-\(index + 1)",
                    title: finding.severity.label,
                    detail: Self.moduleConfigurationDraftFindingDetail(finding.code),
                    systemImage: finding.severity == .blocker ? "xmark.octagon" : "exclamationmark.triangle",
                    tone: finding.severity == .blocker ? .risk : .attention,
                    badge: "复核"
                )
            )
        }
        sections.append(
            MobileHomeSection(
                id: "module-configuration-draft",
                title: "模块配置草稿",
                subtitle: "首页只读提示；发布、写任务、发成长积分、通知和设备动作仍走专属流程",
                items: configurationDraftItems,
                emptyText: "暂无模块配置草稿提示"
            )
        )

        // 家庭成长亮点：已批准的动态 + 已获徽章 + 已上墙荣誉。
        var highlightItems: [MobileHomeItem] = []
        for entry in schoolFamily.feed.filter({ $0.approval == .approved }).prefix(3) {
            highlightItems.append(
                MobileHomeItem(
                    id: "highlight-feed-\(entry.id)",
                    title: entry.title,
                    detail: entry.summary,
                    systemImage: "sparkles",
                    tone: .positive,
                    badge: entry.visibility.label
                )
            )
        }
        for badge in schoolFamily.badges.prefix(3) {
            highlightItems.append(
                MobileHomeItem(
                    id: "highlight-badge-\(badge.id)",
                    title: badge.name,
                    detail: badge.earnedLabel,
                    systemImage: badge.systemImage,
                    tone: .positive,
                    badge: "徽章"
                )
            )
        }
        sections.append(
            MobileHomeSection(
                id: "highlights",
                title: "家庭成长亮点",
                items: highlightItems,
                emptyText: "还没有可展示的成长亮点"
            )
        )

        // 亲友待审核摘要。
        let storylineConsentSnapshot = FamilyHonorStorylineConsentBuilder().snapshot(for: .guardian)
        let storylineReleaseGate = storylineConsentSnapshot.releaseGate
        var relativeItems: [MobileHomeItem] = [
            MobileHomeItem(
                id: "family-storyline-release-gate",
                title: "故事线发布门禁",
                detail: "\(storylineReleaseGate.status.label)：\(storylineReleaseGate.primaryReason.label)；候选 \(storylineReleaseGate.publishCandidateCount) · 待处理 \(storylineReleaseGate.manualGateCount) · 阻断 \(storylineReleaseGate.blockedCount)。只读预览，不发布、不通知、不发成长积分、不解锁设备",
                systemImage: "lock.shield",
                tone: storylineReleaseGate.status == .ready ? .positive : storylineReleaseGate.status == .manualGate ? .attention : .risk,
                badge: "只读",
                destination: .familyStorylineConsent
            ),
            MobileHomeItem(
                id: "relative-overview",
                title: "家庭圈亲友 \(relativeSummary.relativeCount) 位",
                detail: "亲友只读：不能批准任务、不能发成长积分、不能解锁设备",
                systemImage: "person.2",
                tone: .neutral
            )
        ]
        for comment in pendingComments.prefix(5) {
            relativeItems.append(
                MobileHomeItem(
                    id: "relative-comment-\(comment.id)",
                    title: "\(comment.relativeNickname)：\(comment.message)",
                    detail: "在「Family」标签审核后才会对亲友展示",
                    systemImage: "text.bubble",
                    tone: .attention,
                    badge: "待审核"
                )
            )
        }
        for honor in pendingHonors.prefix(5) {
            relativeItems.append(
                MobileHomeItem(
                    id: "relative-honor-\(honor.id)",
                    title: "荣誉待上墙：\(honor.title)",
                    detail: "\(honor.category) · 批准后才上荣誉墙",
                    systemImage: "rosette",
                    tone: .attention,
                    badge: "待审核"
                )
            )
        }
        relativeItems.insert(
            MobileHomeItem(
                id: "family-social-feedback-safety-entry",
                title: "情绪安全复核中心",
                detail: "只读复核亲友鼓励、荣誉墙反馈、日记 / VLOG 连续性和通知预览；不发布、不通知、不写账本、不发成长积分、不解锁设备。",
                systemImage: "heart.text.square",
                tone: .neutral,
                badge: "只读",
                destination: .familySocialFeedbackEmotionalSafety
            ),
            at: min(1, relativeItems.count)
        )
        sections.append(
            MobileHomeSection(
                id: "relatives",
                title: "亲友待审核摘要",
                items: relativeItems
            )
        )

        // 成长积分 / 奖励风险提示。
        // 通用入口：成长积分账本复核台。只读复核台，不发放成长积分、不扣成长积分、不解锁设备，
        // 始终展示在风险区顶部，但不计入上面的「风险提示」计数（riskItems）。
        let creditLedgerReviewEntry = MobileHomeItem(
            id: "credit-ledger-review",
            title: "成长积分账本复核台",
            detail: "只读复核成长积分余额与逐条记录；首页不发放成长积分、不扣成长积分、不解锁设备",
            systemImage: "list.bullet.rectangle",
            tone: .neutral,
            badge: "只读",
            destination: .creditLedgerReview
        )
        sections.append(
            MobileHomeSection(
                id: "risk",
                title: "成长积分与兑换风险提示",
                items: [creditLedgerReviewEntry] + riskItems,
                emptyText: "暂无成长积分或兑换风险"
            )
        )

        // 奖励商店库存履约复核入口（只读）。家长端进入库存履约复核视角，只读复核库存
        // 售罄/超卖、兑换预留、重复扣成长积分、履约失败、退款取消回滚建议、实物地址确认、
        // 设备时长上限和离线回放；首页不真实兑换、不扣成长积分、不发货、不写账本/订单/库存、
        // 不退款、不通知、不解锁设备。入口文案不携带任何内部 ID、地址、金额或原始引用。
        sections.append(
            MobileHomeSection(
                id: "reward-store-fulfillment",
                title: "奖励库存履约复核",
                subtitle: "首页只读入口；真实兑换、扣成长积分、发货、退款、回滚和设备解锁仍走专属流程",
                items: [
                    MobileHomeItem(
                        id: "reward-store-fulfillment-entry",
                        title: "奖励库存履约复核",
                        detail: "只读复核库存售罄、兑换预留、履约失败和退款回滚建议；首页不真实兑换、不扣成长积分、不发货、不解锁设备。",
                        systemImage: "shippingbox.and.arrow.backward",
                        tone: .neutral,
                        badge: "只读",
                        destination: .rewardStoreFulfillment
                    )
                ]
            )
        )

        // 离线同步本地复核台入口（只读）。家长端可进入查看冲突与回滚摘要，并可手动重放，
        // 但本地重放不落定：不写账本、不发成长积分、不扣成长积分、不解锁设备。
        sections.append(
            MobileHomeSection(
                id: "offline-sync-review",
                title: "离线同步复核台",
                subtitle: "首页只读入口；可本地重放，但不落定、不写账本、不发成长积分、不解锁设备",
                items: [
                    MobileHomeItem(
                        id: "offline-sync-review-entry",
                        title: "离线同步复核台",
                        detail: "复核待同步、冲突与回滚摘要；本地重放仅作预览，不写账本、不发成长积分、不解锁设备",
                        systemImage: "arrow.triangle.2.circlepath",
                        tone: .neutral,
                        badge: "只读",
                        destination: .offlineSyncReview
                    )
                ]
            )
        )

        // 平台质量：iOS 端移动发布质量门。仅家长视角的只读本地快照，
        // 首页不发布、不写账本、不解锁设备，也不调用真实网络/云/AI/LMS/通知。
        // 孩子视角的编排层从不产出该目的地。
        let releaseGateSnapshot = MobileReleaseCandidateGateBuilder().build(viewerRole: .guardian)
        let releaseGateSummary = releaseGateSnapshot.publicSummary
        let releaseGateEntry = MobileHomeItem(
            id: "mobile-release-gate",
            title: "移动发布质量门",
            detail: "状态：\(releaseGateSnapshot.status.label)；阻断 \(releaseGateSummary.blockerCount) · 复核 \(releaseGateSummary.warningCount) · 待办 \(releaseGateSummary.actionRequiredCount)。只读复核，不发布、不写账本、不解锁设备",
            systemImage: "checkmark.shield",
            tone: .neutral,
            badge: "只读",
            destination: .releaseGate
        )
        sections.append(
            MobileHomeSection(
                id: "release-quality",
                title: "平台发布质量门",
                items: [releaseGateEntry],
                emptyText: "暂无发布质量门提示"
            )
        )

        let guardianPermissionHome = MobileHomeViewModel(
            perspective: .parent,
            greeting: "家长工作台",
            headline: headline,
            metrics: metrics,
            sections: sections
        )
        sections.append(
            permissionGatewaySection(
                viewerRole: .guardian,
                subtitle: "首页只读预览；真实授权仍走专属流程",
                home: guardianPermissionHome
            )
        )

        return MobileHomeViewModel(
            perspective: .parent,
            greeting: "家长工作台",
            headline: headline,
            metrics: metrics,
            sections: sections
        )
    }

    // MARK: - 展示映射

    static func isActionable(_ status: MobileSyncTaskStatus) -> Bool {
        switch status {
        case .scheduled, .available, .inProgress:
            return true
        case .submitted, .verified, .missed:
            return false
        }
    }

    static func taskStatusLabel(_ status: MobileSyncTaskStatus) -> String {
        switch status {
        case .scheduled: return "待开始"
        case .available: return "可开始"
        case .inProgress: return "进行中"
        case .submitted: return "待验证"
        case .verified: return "已完成"
        case .missed: return "已错过"
        }
    }

    static func taskTone(_ status: MobileSyncTaskStatus) -> MobileHomeTone {
        switch status {
        case .verified: return .positive
        case .submitted: return .neutral
        case .missed: return .risk
        case .scheduled, .available, .inProgress: return .attention
        }
    }

    static func taskDetail(_ task: MobileSyncTask) -> String {
        let priority: String
        switch task.priority {
        case .mustDo: priority = "必做"
        case .recommended: priority = "推荐"
        case .optional: priority = "可选"
        case .bonus: priority = "加分"
        }
        let evidence = task.requiresEvidence ? "需要提交证明" : "无需证明"
        return "\(priority) · \(evidence)"
    }

    static func categoryIcon(_ category: MobileSyncTaskCategory) -> String {
        switch category {
        case .homework: return "pencil.and.ruler"
        case .learning: return "book"
        case .exercise: return "figure.run"
        case .routine: return "sun.max"
        case .chore: return "house"
        case .creative: return "paintpalette"
        case .socialEmotional: return "heart"
        case .family: return "person.3"
        }
    }

    static func rewardLabel(_ type: MobileSyncRewardType) -> String {
        switch type {
        case .screenTime: return "屏幕时间"
        case .appUnlock: return "应用解锁"
        case .familyReward: return "家庭奖励"
        case .badgeBonus: return "徽章奖励"
        case .creatorPackBonus: return "成长包奖励"
        }
    }

    static func growthPackTone(_ state: GrowthPackInstallDecisionState) -> MobileHomeTone {
        switch state {
        case .installable, .pendingGuardianConfirmation:
            return .attention
        case .installed:
            return .positive
        case .frozen, .blocked:
            return .risk
        case .hidden:
            return .neutral
        }
    }

    static func growthPackIcon(_ state: GrowthPackInstallDecisionState) -> String {
        switch state {
        case .installable:
            return "square.and.arrow.down"
        case .installed:
            return "checkmark.seal"
        case .pendingGuardianConfirmation:
            return "person.badge.clock"
        case .frozen:
            return "pause.circle"
        case .blocked:
            return "xmark.octagon"
        case .hidden:
            return "eye.slash"
        }
    }

    static func childGrowthPackHomeDetail(_ state: GrowthPackInstallDecisionState) -> String {
        switch state {
        case .installable, .pendingGuardianConfirmation:
            return "等待家长确认后，成长包会进入你的任务计划。"
        case .installed:
            return "这个成长包可以继续挑战。"
        case .frozen:
            return "这个成长包已暂停，先完成其它任务。"
        case .blocked:
            return "这个成长包暂时不开放。"
        case .hidden:
            return "成长包状态已隐藏。"
        }
    }

    static func parentGrowthPackHomeDetail(_ state: GrowthPackInstallDecisionState) -> String {
        switch state {
        case .installable:
            return "可在成长包页面确认安装；首页不触发购买或授权。"
        case .pendingGuardianConfirmation:
            return "等待家长确认安装；首页只显示提醒。"
        case .installed:
            return "孩子端可运行；首页不写入权益或成长积分。"
        case .frozen:
            return "权益相关状态已冻结，请到专属页面复核。"
        case .blocked:
            return "安装条件未通过，请到专属页面查看阻断项。"
        case .hidden:
            return "该成长包对当前视角隐藏。"
        }
    }

    static func visibleGrowthPackCloudSyncState(
        _ snapshot: GrowthPackCloudSyncMobileBridgeSnapshot
    ) -> GrowthPackCloudSyncMobileBridgeState {
        snapshot.sideEffects.hasTriggeredSideEffect ? .blocked : snapshot.state
    }

    static func growthPackCloudSyncTone(_ state: GrowthPackCloudSyncMobileBridgeState) -> MobileHomeTone {
        switch state {
        case .ready:
            return .positive
        case .reviewRequired, .conflict:
            return .attention
        case .frozen, .revoked, .blocked:
            return .risk
        }
    }

    static func growthPackCloudSyncIcon(_ state: GrowthPackCloudSyncMobileBridgeState) -> String {
        switch state {
        case .ready:
            return "icloud.and.arrow.down"
        case .reviewRequired:
            return "person.badge.clock"
        case .conflict:
            return "arrow.triangle.2.circlepath"
        case .frozen:
            return "pause.circle"
        case .revoked:
            return "arrow.uturn.backward.circle"
        case .blocked:
            return "xmark.octagon"
        }
    }

    static func childGrowthPackCloudSyncHomeDetail(_ state: GrowthPackCloudSyncMobileBridgeState) -> String {
        switch state {
        case .ready:
            return "可以继续看已开放的成长包下一步。"
        case .reviewRequired, .conflict:
            return "等待家长确认同步状态后再继续。"
        case .frozen:
            return "这个成长包已暂停，先完成其它任务。"
        case .revoked, .blocked:
            return "这个成长包暂时不开放。"
        }
    }

    static func parentGrowthPackCloudSyncHomeDetail(_ state: GrowthPackCloudSyncMobileBridgeState) -> String {
        switch state {
        case .ready:
            return "同步只读状态正常；首页不触发购买、成长积分或设备动作。"
        case .reviewRequired:
            return "有同步状态需要家长复核；首页只显示提醒。"
        case .conflict:
            return "离线同步存在冲突，请到专属页面复核。"
        case .frozen:
            return "权益或成长积分相关状态已冻结，请到专属页面复核。"
        case .revoked:
            return "权益已撤回，请确认孩子端不再运行对应成长包。"
        case .blocked:
            return "同步已阻断，请先处理权限、下架或同意问题。"
        }
    }

    static func visibleAIHomeworkInboxStatus(
        _ snapshot: AIHomeworkFamilySchoolInboxSnapshot
    ) -> AIHomeworkFamilySchoolInboxStatus {
        snapshot.sideEffects.hasTriggeredSideEffect ? .blocked : snapshot.status
    }

    static func aiHomeworkInboxTone(_ status: AIHomeworkFamilySchoolInboxStatus) -> MobileHomeTone {
        switch status {
        case .ready:
            return .positive
        case .empty:
            return .neutral
        case .reviewRequired:
            return .attention
        case .blocked:
            return .risk
        }
    }

    static func aiHomeworkInboxIcon(_ status: AIHomeworkFamilySchoolInboxStatus) -> String {
        switch status {
        case .ready:
            return "checkmark.seal"
        case .empty:
            return "tray"
        case .reviewRequired:
            return "tray.full"
        case .blocked:
            return "shield.slash"
        }
    }

    static func childAIHomeworkInboxHomeDetail(_ status: AIHomeworkFamilySchoolInboxStatus) -> String {
        switch status {
        case .ready:
            return "按提示和自检继续完成作业。"
        case .empty:
            return "暂时没有需要处理的作业。"
        case .reviewRequired:
            return "提交证明后，等待老师或家长验证。"
        case .blocked:
            return "先回到提示和自检，不要直接要答案。"
        }
    }

    static func parentAIHomeworkInboxHomeDetail(_ status: AIHomeworkFamilySchoolInboxStatus) -> String {
        switch status {
        case .ready:
            return "家校作业只读状态正常；首页不调用模型或写账本。"
        case .empty:
            return "暂时没有家校作业复核事项。"
        case .reviewRequired:
            return "有作业、老师或成长积分建议需要复核；首页只显示提醒。"
        case .blocked:
            return "AI 或学校边界已阻断，请先走人工复核。"
        }
    }

    static func visibleSchoolJointApprovalStatus(
        _ snapshot: SchoolJointApprovalSnapshot
    ) -> SchoolJointApprovalBoardStatus {
        let summary = snapshot.publicSummary
        let hasUnexpectedSideEffect = summary.verifiesTeacher
            || summary.confirmsGuardian
            || summary.returnsHomework
            || summary.freezesCredit
            || summary.writesLedger
            || summary.writesSchoolHomework
            || summary.sendsNotification
            || summary.unlocksDevice
            || summary.callsSchoolSystem
            || summary.callsLms
            || summary.usesAiToAnswer
        return hasUnexpectedSideEffect ? .blocked : summary.status
    }

    static func parentSchoolJointApprovalActionCount(_ snapshot: SchoolJointApprovalSnapshot) -> Int {
        let summary = snapshot.publicSummary
        return summary.awaitingTeacherCount
            + summary.awaitingGuardianCount
            + summary.returnedCount
            + summary.appealFrozenCount
            + summary.offlineRollbackCount
            + summary.creditNoteCount
    }

    static func schoolJointApprovalTone(_ status: SchoolJointApprovalBoardStatus) -> MobileHomeTone {
        switch status {
        case .ready:
            return .positive
        case .empty:
            return .neutral
        case .awaitingTeacher, .awaitingGuardian:
            return .attention
        case .appealFrozen, .offlineRollback, .blocked:
            return .risk
        }
    }

    static func schoolJointApprovalIcon(_ status: SchoolJointApprovalBoardStatus) -> String {
        switch status {
        case .ready:
            return "checkmark.seal"
        case .empty:
            return "tray"
        case .awaitingTeacher:
            return "graduationcap"
        case .awaitingGuardian:
            return "person.badge.clock"
        case .appealFrozen:
            return "pause.circle"
        case .offlineRollback:
            return "arrow.triangle.2.circlepath"
        case .blocked:
            return "xmark.octagon"
        }
    }

    static func childSchoolJointApprovalHomeDetail(_ status: SchoolJointApprovalBoardStatus) -> String {
        switch status {
        case .ready:
            return "老师和家长的确认进度正常。"
        case .empty:
            return "暂时没有需要确认的学校作业。"
        case .awaitingTeacher:
            return "作业已提交，正在等老师看看。"
        case .awaitingGuardian:
            return "老师看过啦，正在等家长确认。"
        case .appealFrozen:
            return "这条作业正在复核中，请稍等。"
        case .offlineRollback:
            return "正在同步最新进度，请稍候。"
        case .blocked:
            return "这条作业暂时不能继续，等大人看看。"
        }
    }

    static func parentSchoolJointApprovalHomeDetail(_ status: SchoolJointApprovalBoardStatus) -> String {
        switch status {
        case .ready:
            return "联合审批只读状态正常；首页不验证、不确认、不写账本。"
        case .empty:
            return "暂时没有联合审批复核事项。"
        case .awaitingTeacher:
            return "有作业等待老师验证；首页只显示提醒。"
        case .awaitingGuardian:
            return "有作业等待家长确认；首页不执行确认。"
        case .appealFrozen:
            return "申诉或冻结正在复核；首页不冻结成长积分或写账本。"
        case .offlineRollback:
            return "离线回滚需要复核；首页不应用回滚。"
        case .blocked:
            return "学校联合审批已阻断，请先走人工复核。"
        }
    }

    static func visibleModuleConfigurationDraftStatus(
        _ snapshot: MobileModuleConfigurationDraftSnapshot
    ) -> MobileModuleConfigurationDraftStatus {
        snapshot.sideEffects.hasTriggeredSideEffect ? .blocked : snapshot.status
    }

    static func parentModuleConfigurationDraftActionCount(
        _ snapshot: MobileModuleConfigurationDraftSnapshot
    ) -> Int {
        snapshot.reviewActions.count
    }

    static func parentModuleConfigurationDraftBlockingActionCount(
        _ snapshot: MobileModuleConfigurationDraftSnapshot
    ) -> Int {
        snapshot.reviewActions.filter(\.blockedUntilReviewed).count
    }

    static func moduleConfigurationDraftTone(
        _ status: MobileModuleConfigurationDraftStatus
    ) -> MobileHomeTone {
        switch status {
        case .ready:
            return .positive
        case .reviewRequired:
            return .attention
        case .blocked:
            return .risk
        }
    }

    static func moduleConfigurationDraftIcon(
        _ status: MobileModuleConfigurationDraftStatus
    ) -> String {
        switch status {
        case .ready:
            return "rectangle.grid.2x2"
        case .reviewRequired:
            return "person.badge.clock"
        case .blocked:
            return "xmark.octagon"
        }
    }

    static func childModuleConfigurationDraftHomeDetail(
        _ status: MobileModuleConfigurationDraftStatus
    ) -> String {
        switch status {
        case .ready:
            return "可以看看今天的成长安排，完成后等家长确认。"
        case .reviewRequired:
            return "今天的安排需要家长先调整，先完成已开放任务。"
        case .blocked:
            return "今天的安排暂时不可展示，等家长看看。"
        }
    }

    static func parentModuleConfigurationDraftHomeDetail(
        _ status: MobileModuleConfigurationDraftStatus
    ) -> String {
        switch status {
        case .ready:
            return "模块配置草稿只读状态正常；首页不发布、不写任务。"
        case .reviewRequired:
            return "草稿存在预算或排序提醒；首页只显示复核摘要。"
        case .blocked:
            return "模块配置草稿已阻断，请先走人工复核。"
        }
    }

    static func moduleConfigurationDraftReviewActionDetail(
        _ action: MobileModuleConfigurationReviewAction
    ) -> String {
        if action.blockedUntilReviewed {
            return "家长需先确认该模块的顺序、时长和证明要求；复核前不发布配置。"
        }
        return "该模块需要家长确认；首页不写任务、不发积分。"
    }

    static func moduleConfigurationDraftReviewActionTitle(
        _ action: MobileModuleConfigurationReviewAction
    ) -> String {
        "\(action.moduleKey.title)复核"
    }

    static func moduleConfigurationDraftFindingDetail(
        _ code: MobileModuleConfigurationFindingCode
    ) -> String {
        switch code {
        case .draftReady:
            return "草稿已生成，仍需在专属流程发布。"
        case .creditBudgetReview:
            return "积分预算需要家长复核；首页不写账本。"
        case .schoolPriority:
            return "学校作业优先级需要关注；首页不改作业。"
        case .childControlsHidden:
            return "孩子视角已隐藏配置控制。"
        case .operationsRedacted:
            return "运营视角只看脱敏计数。"
        case .unsafeInputBlocked:
            return "输入已被安全阻断。"
        }
    }

    static func visibleGrowthRuntimeReport(
        _ report: GrowthRuntimeSettlementReport
    ) -> GrowthRuntimeSettlementReport {
        GrowthPackRuntimeSettlementEngine.reportLeaks(report) ? .empty : report
    }

    static func childGrowthRuntimeAttentionCount(_ report: GrowthRuntimeSettlementReport) -> Int {
        report.steps.filter(childGrowthRuntimeShouldShow).count
    }

    static func parentGrowthRuntimeActionCount(_ report: GrowthRuntimeSettlementReport) -> Int {
        report.publicSummary.creditSuggestedCount
            + report.publicSummary.reviewRequiredCount
            + report.publicSummary.appealingCount
            + report.publicSummary.blockedCount
    }

    static func childGrowthRuntimeShouldShow(_ step: GrowthRuntimeStepProjection) -> Bool {
        switch step.status {
        case .planned, .reviewRequired, .creditSuggested, .blocked:
            return true
        case .duplicate, .alreadyCredited, .voided:
            return false
        }
    }

    static func childGrowthRuntimeHomeDetail(_ report: GrowthRuntimeSettlementReport) -> String {
        if report.isEmpty { return "暂时没有成长包闭环步骤。" }
        if report.publicSummary.reviewRequiredCount > 0 {
            return "\(report.publicSummary.reviewRequiredCount) 步正在等验证。"
        }
        if report.publicSummary.creditSuggestedCount > 0 {
            return "\(report.publicSummary.creditSuggestedCount) 步已完成，等家长确认。"
        }
        if report.publicSummary.plannedCount > 0 {
            return "\(report.publicSummary.plannedCount) 步可以继续安排。"
        }
        if report.publicSummary.blockedCount > 0 || report.publicSummary.appealingCount > 0 {
            return "有步骤需要大人复核。"
        }
        return "成长包闭环进度正常。"
    }

    static func parentGrowthRuntimeHomeDetail(_ report: GrowthRuntimeSettlementReport) -> String {
        if report.isEmpty { return "暂无成长包闭环投影；首页不写账本、不发成长积分、不解锁设备。" }
        return "步骤 \(report.publicSummary.stepCount) · 可建议 \(report.publicSummary.creditSuggestedCount) · 待复核 \(report.publicSummary.reviewRequiredCount) · 阻断 \(report.publicSummary.blockedCount)。首页不写账本、不发成长积分、不解锁设备。"
    }

    static func childGrowthRuntimeStepDetail(_ step: GrowthRuntimeStepProjection) -> String {
        switch step.status {
        case .planned:
            return "按计划完成并提交证明。"
        case .reviewRequired:
            return "已经提交，等待家长或老师验证。"
        case .creditSuggested:
            return "已完成，等待家长确认后进入成长积分流程。"
        case .blocked:
            return "暂时不能继续，按提示补证明或等待大人复核。"
        case .duplicate:
            return "重复提交已忽略。"
        case .alreadyCredited:
            return "这一步已经结算过。"
        case .voided:
            return "这一步已经作废。"
        }
    }

    static func growthRuntimeTone(_ report: GrowthRuntimeSettlementReport) -> MobileHomeTone {
        if report.publicSummary.blockedCount > 0 || report.publicSummary.appealingCount > 0 {
            return .risk
        }
        if report.publicSummary.reviewRequiredCount > 0 || report.publicSummary.creditSuggestedCount > 0 {
            return .attention
        }
        if report.publicSummary.stepCount > 0 {
            return .positive
        }
        return .neutral
    }

    static func growthRuntimeTone(_ status: GrowthRuntimeProjectionStatus) -> MobileHomeTone {
        switch status {
        case .creditSuggested, .alreadyCredited:
            return .positive
        case .planned, .reviewRequired:
            return .attention
        case .blocked:
            return .risk
        case .duplicate, .voided:
            return .neutral
        }
    }

    static func growthRuntimeIcon(_ status: GrowthRuntimeProjectionStatus) -> String {
        switch status {
        case .planned:
            return "calendar"
        case .reviewRequired:
            return "person.badge.clock"
        case .creditSuggested:
            return "lightbulb"
        case .blocked:
            return "nosign"
        case .duplicate:
            return "doc.on.doc"
        case .alreadyCredited:
            return "checkmark.seal"
        case .voided:
            return "xmark.circle"
        }
    }

    static func growthRuntimeDisplayText(_ text: String, fallback: String) -> String {
        growthPackDisplayText(text, fallback: fallback)
    }

    static func growthPackDetailText(_ parts: [String], fallback: String) -> String {
        let cleaned = parts.map { growthPackDisplayText($0, fallback: fallback) }
        if cleaned.contains(fallback) { return fallback }
        let joined = cleaned.joined(separator: " · ").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? fallback : joined
    }

    static func growthPackDisplayText(_ text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        if MobileSyncPayloadGuard.isUnsafe(trimmed) { return fallback }
        if containsGrowthPackSensitiveMarker(trimmed) { return fallback }
        return trimmed
    }

    private static func containsGrowthPackSensitiveMarker(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let blockedMarkers = [
            "child:", "family:", "task:", "proof:", "decision:", "hold:",
            "reward:", "feed:", "guardian:", "teacher:", "pack:", "creator:",
            "order:", "entitlement:", "refund:", "ledger:", "credit:", "cloud:",
            "taskid", "claimid", "gpcm-", "gpi-pack", "gpi-creator", "gpi-order",
            "gpi-ent", "gpi-catalog", "gpi-child", "gpi-family", "gpi-find",
            "http://", "https://", "file://", "/users/", "/volumes/",
            "baseurl", "api_key", "apikey", "token", "secret"
        ]
        if blockedMarkers.contains(where: { lowercased.contains($0) }) { return true }

        let blockedPatterns = [
            #"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"#,
            #"(?i)\b[0-9a-f]{24,}\b"#,
            #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#
        ]
        return blockedPatterns.contains { pattern in
            text.range(of: pattern, options: .regularExpression) != nil
        }
    }
}
