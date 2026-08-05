import SwiftUI

struct MobileModuleLaunchCenterView: View {
    @State private var viewerRole: MobileModuleLaunchCenterViewerRole
    @State private var familyAchievementStore = FamilyGrowthAchievementStore()
    @State private var searchText = ""
    @State private var groupFilter: MobileModuleLaunchGroupKind?
    @State private var statusFilter: MobileModuleLaunchCenterStatus?
    @State private var sort: MobileModuleLaunchCenterDiscoverySort = .recommended

    private let builder = MobileModuleLaunchCenterBuilder()
    private let routeResolver = MobileModuleLaunchRouteResolver()
    private let roleScope: MobileModuleLaunchCenterRoleScope

    /// 允许调用方指定入口视角范围；仅设置本地展示视角，不改变任何业务语义。
    /// 默认保留全角色调试入口，首页和根 Tab 会传入单角色范围锁定。
    init(
        initialRole: MobileModuleLaunchCenterViewerRole = .child,
        allowedRoles: [MobileModuleLaunchCenterViewerRole] = MobileModuleLaunchCenterViewerRole.allCases
    ) {
        let scope = MobileModuleLaunchCenterRoleScope(initialRole: initialRole, allowedRoles: allowedRoles)
        self.roleScope = scope
        _viewerRole = State(initialValue: scope.initialRole)
    }

    private var snapshot: MobileModuleLaunchCenterSnapshot {
        builder.build(viewerRole: viewerRole)
    }

    private var filter: MobileModuleLaunchCenterDiscoveryFilter {
        MobileModuleLaunchCenterDiscoveryFilter(
            searchText: searchText,
            group: groupFilter,
            status: statusFilter,
            sort: sort
        )
    }

    private func discovery(_ snapshot: MobileModuleLaunchCenterSnapshot) -> MobileModuleLaunchCenterDiscoveryResult {
        MobileModuleLaunchCenterDiscovery.apply(filter, to: snapshot)
    }

    var body: some View {
        let snapshot = snapshot
        let discovery = discovery(snapshot)

        return List {
            roleSection(snapshot)
            headerSection(snapshot)
            progressSection(snapshot)
            discoveryFilterSection(discovery)

            if filter.hasActiveFilter {
                discoveryResultSection(discovery)
            } else {
                if sort == .recommended {
                    recommendedPreviewSection(discovery)
                }
                groupedModulesSection(snapshot)
            }

            if !snapshot.nextActions.isEmpty {
                Section("下一步") {
                    ForEach(snapshot.nextActions) { action in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: icon(for: action.severity))
                                .foregroundStyle(color(for: action.severity))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(action.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(action.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if viewerRole != .child && !snapshot.findings.isEmpty {
                Section("护栏") {
                    ForEach(snapshot.findings) { finding in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: icon(for: finding.severity))
                                .foregroundStyle(color(for: finding.severity))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(finding.severity.label)
                                    .font(.subheadline.weight(.semibold))
                                Text(finding.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("无副作用") {
                LabeledContent("调用网络 / AI", value: (snapshot.publicSummary.callsNetwork || snapshot.publicSummary.callsAiProvider || snapshot.publicSummary.callsLocalModel) ? "会" : "不会")
                LabeledContent("写学校 / LMS", value: (snapshot.publicSummary.writesSchoolSystem || snapshot.publicSummary.callsLms) ? "会" : "不会")
                LabeledContent("写账本 / 发成长积分", value: (snapshot.publicSummary.writesLedger || snapshot.publicSummary.grantsCredit) ? "会" : "不会")
                LabeledContent("通知 / 解锁设备", value: (snapshot.publicSummary.sendsNotification || snapshot.publicSummary.unlocksDevice) ? "会" : "不会")
                LabeledContent("购买 / 写权益", value: (snapshot.publicSummary.createsOrder || snapshot.publicSummary.writesEntitlement) ? "会" : "不会")
            }
        }
        .navigationTitle("模块能力中心")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "搜索模块、状态或入口")
    }

    private func discoveryFilterSection(_ discovery: MobileModuleLaunchCenterDiscoveryResult) -> some View {
        Section {
            Picker("排序", selection: $sort) {
                ForEach(MobileModuleLaunchCenterDiscoverySort.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                Menu {
                    Button("全部分组") { groupFilter = nil }
                        .accessibilityIdentifier("module-center-filter-group-all")
                    ForEach(discovery.availableGroups, id: \.self) { group in
                        Button(group.title) { groupFilter = group }
                            .accessibilityIdentifier("module-center-filter-group-\(group.rawValue)")
                    }
                } label: {
                    filterChip(title: "分组", value: groupFilter?.title ?? "全部", active: groupFilter != nil)
                }
                .accessibilityIdentifier("module-center-filter-group-menu")

                Menu {
                    Button("全部状态") { statusFilter = nil }
                        .accessibilityIdentifier("module-center-filter-status-all")
                    ForEach(discovery.availableStatuses, id: \.self) { status in
                        Button(status.label) { statusFilter = status }
                            .accessibilityIdentifier("module-center-filter-status-\(status.rawValue)")
                    }
                } label: {
                    filterChip(title: "状态", value: statusFilter?.label ?? "全部", active: statusFilter != nil)
                }
                .accessibilityIdentifier("module-center-filter-status-menu")
            }

            if filter.hasActiveFilter {
                Button("清除筛选") {
                    searchText = ""
                    groupFilter = nil
                    statusFilter = nil
                }
                .font(.caption.weight(.medium))
                .accessibilityIdentifier("module-center-filter-clear")
            }
        } header: {
            Text("发现")
        } footer: {
            Text(filter.hasActiveFilter
                 ? "已按搜索 / 分组 / 状态过滤当前视角可见模块，发现层不会新增模块或放宽角色可见性。"
                 : "默认展示全部可见模块；切换「下一步推荐」会把需复核、进行中、低进度可进入的模块排到前面。")
        }
    }

    private func filterChip(title: String, value: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(active ? Color.blue : Color.primary)
            Image(systemName: "chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func discoveryResultSection(_ discovery: MobileModuleLaunchCenterDiscoveryResult) -> some View {
        if let message = discovery.emptyStateMessage {
            Section("发现结果") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("没有匹配的模块", systemImage: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        } else {
            Section {
                ForEach(discovery.modules) { module in
                    moduleRow(module)
                }
            } header: {
                Text("发现结果")
            } footer: {
                Text("命中 \(discovery.matchedCount) / \(discovery.totalVisibleCount) 个可见模块。")
            }
        }
    }

    @ViewBuilder
    private func recommendedPreviewSection(_ discovery: MobileModuleLaunchCenterDiscoveryResult) -> some View {
        let modules = Array(discovery.modules.prefix(4))

        if !modules.isEmpty {
            Section {
                ForEach(modules) { module in
                    moduleRow(module)
                }
            } header: {
                Text("下一步推荐")
            } footer: {
                Text("只从当前视角可见模块中推荐，不新增模块或放宽角色可见性。")
            }
        }
    }

    @ViewBuilder
    private func groupedModulesSection(_ snapshot: MobileModuleLaunchCenterSnapshot) -> some View {
        ForEach(snapshot.groups) { group in
            Section {
                ForEach(group.modules) { module in
                    moduleRow(module)
                }
            } header: {
                Text(group.title)
            } footer: {
                Text(group.subtitle)
            }
        }
    }

    private func roleSection(_ snapshot: MobileModuleLaunchCenterSnapshot) -> some View {
        Section {
            if roleScope.allowsRoleSwitching {
                Picker("视角", selection: $viewerRole) {
                    ForEach(roleScope.availableRoles, id: \.self) { role in
                        Text(role.label).tag(role)
                            .accessibilityIdentifier("module-center-role-\(role.rawValue)")
                    }
                }
                .pickerStyle(.segmented)
            } else {
                LabeledContent("视角", value: roleScope.initialRole.label)
            }
        } footer: {
            Text(roleScope.allowsRoleSwitching ? "模块中心只负责入口和状态，不在这里批准任务、发成长积分、通知或解锁设备。" : "当前入口已锁定为\(roleScope.initialRole.label)视角；模块中心仍只负责入口和状态，不在这里批准任务、发成长积分、通知或解锁设备。")
        }
    }

    private func headerSection(_ snapshot: MobileModuleLaunchCenterSnapshot) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(snapshot.status.label, systemImage: icon(for: snapshot.status))
                        .font(.headline)
                        .foregroundStyle(color(for: snapshot.status))
                    Spacer()
                    Text("\(snapshot.publicSummary.visibleModuleCount) 个模块")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(snapshot.headline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func progressSection(_ snapshot: MobileModuleLaunchCenterSnapshot) -> some View {
        Section {
            HStack(spacing: 12) {
                metric("分组", "\(snapshot.publicSummary.visibleGroupCount)")
                metric("模块", "\(snapshot.publicSummary.visibleModuleCount)")
                metric("待处理", "\(snapshot.publicSummary.actionRequiredCount)")
                metric("均值", "\(snapshot.publicSummary.averageProgress)%")
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func moduleRow(_ module: MobileModuleLaunchModuleCard) -> some View {
        if let route = routeResolver.route(for: module, viewerRole: viewerRole) {
            NavigationLink {
                destination(for: route)
            } label: {
                moduleRowContent(module, route: route)
            }
            .accessibilityIdentifier("module-center-module-\(module.key.rawValue)")
        } else {
            moduleRowContent(module, route: nil)
                .accessibilityIdentifier("module-center-module-\(module.key.rawValue)")
        }
    }

    private func moduleRowContent(
        _ module: MobileModuleLaunchModuleCard,
        route: MobileModuleLaunchRoute?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon(for: module.group))
                    .foregroundStyle(color(for: module.status))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(module.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(module.status.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(color(for: module.status))
                    }
                    Text(module.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(module.routeHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let route {
                        Label(route.title, systemImage: "arrow.forward.circle")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.blue)
                    }
                }
            }

            ProgressView(value: Double(module.progress), total: 100)
                .tint(color(for: module.status))
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func destination(for route: MobileModuleLaunchRoute) -> some View {
        switch route.destinationKind {
        case .childTaskList:
            ChildHomeView()
        case .basicHabitCheckin:
            BasicHabitChoreCheckinWorkbenchView(
                initialRole: basicHabitRole(for: route.viewerRole),
                allowedRoles: [basicHabitRole(for: route.viewerRole)]
            )
        case .guardianTaskReview:
            ParentModeView()
        case .growthPackDetail:
            let role = growthPackDetailRole(for: route.viewerRole)
            GrowthPackMobileDetailView(initialRole: role, allowedRoles: [role])
        case .growthPackExecutionHub:
            let role = growthPackExecutionHubRole(for: route.viewerRole)
            MobileGrowthPackExecutionHubView(initialRole: role, allowedRoles: [role])
        case .growthPackEntitlement:
            GrowthPackInstallEntitlementView(
                initialRole: growthPackInstallRole(for: route.viewerRole),
                allowsRoleSwitching: !route.shouldLockDestinationRole
            )
        case .schoolHomework:
            let role = schoolHomeworkLinkageRole(for: route.viewerRole)
            MobileSchoolHomeworkGrowthPackLinkageWorkbenchView(
                initialRole: role,
                allowedRoles: [role]
            )
        case .aiHomeworkInbox:
            let role = aiInboxRole(for: route.viewerRole)
            AIHomeworkFamilySchoolInboxView(initialRole: role, allowedRoles: [role])
        case .schoolJointApproval:
            let role = schoolJointApprovalRole(for: route.viewerRole)
            SchoolJointApprovalBoardView(initialRole: role, allowedRoles: [role])
        case .notificationDigestConsent:
            let role = notificationDigestRole(for: route.viewerRole)
            FamilySchoolNotificationDigestCenterView(initialRole: role, allowedRoles: [role])
        case .familyStorylineConsent:
            FamilyHonorStorylineConsentView(
                store: familyAchievementStore,
                initialRole: familyHonorRole(for: route.viewerRole),
                allowsRoleSwitching: !route.shouldLockDestinationRole
            )
        case .growthDiaryVlogStoryline:
            let role = growthDiaryVlogRole(for: route.viewerRole)
            GrowthDiaryVlogStorylineWorkbenchView(
                store: familyAchievementStore,
                initialRole: role,
                allowedRoles: [role]
            )
        case .familyAchievementDashboard:
            FamilyAchievementSnapshotDashboardView(
                store: familyAchievementStore,
                initialRole: familyGrowthRole(for: route.viewerRole),
                allowsRoleSwitching: !route.shouldLockDestinationRole
            )
        case .creditLedgerReview:
            CreditLedgerReviewView(viewerRole: creditLedgerRole(for: route.viewerRole))
        case .rewardRedemption:
            ChildCreditWalletView()
        case .rewardStatus:
            RewardStatusView()
        case .appSelectionWorkbench:
            let role = appSelectionRole(for: route.viewerRole)
            AppSelectionWorkbenchView(initialRole: role, allowedRoles: [role])
        case .rewardStoreFulfillment:
            let role = rewardStoreFulfillmentRole(for: route.viewerRole)
            MobileRewardStoreInventoryFulfillmentWorkbenchView(initialRole: role, allowedRoles: [role])
        case .reportsWorkbench:
            let role = reportsRole(for: route.viewerRole)
            ReportsWorkbenchView(initialRole: role, allowedRoles: [role])
        case .onboardingGuide:
            let role = onboardingRole(for: route.viewerRole)
            OnboardingWorkbenchView(initialRole: role, allowedRoles: [role])
        case .offlineSyncReview:
            MobileOfflineSyncReviewView(perspective: offlineSyncReviewPerspective(for: route.viewerRole))
        case .moduleConfigurationDraft:
            let role = moduleConfigurationDraftRole(for: route.viewerRole)
            MobileModuleConfigurationDraftView(initialRole: role, allowedRoles: [role])
        case .releaseGate:
            MobileReleaseCandidateGateView(
                initialRole: releaseGateRole(for: route.viewerRole),
                allowsRoleSwitching: !route.shouldLockDestinationRole
            )
        case .familySocialFeedbackEmotionalSafetyCenter:
            let role = emotionalSafetyRole(for: route.viewerRole)
            MobileFamilySocialFeedbackEmotionalSafetyCenterView(initialRole: role, allowedRoles: [role])
        case .safePreview:
            MobileModuleLaunchRoutePreviewView(route: route)
        }
    }

    private func growthPackInstallRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> GrowthPackInstallViewerRole {
        switch role {
        case .child: return .child
        case .guardian: return .guardian
        case .relative: return .relative
        case .teacher: return .guardian
        case .operations: return .creator
        }
    }

    private func basicHabitRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> MobileBasicHabitChoreViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .relative, .teacher, .operations: return .guardian
        }
    }

    private func growthPackDetailRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> GrowthPackMobileDetailViewerRole {
        switch role {
        case .child, .operations:
            return .child
        case .guardian:
            return .guardian
        case .relative:
            return .relative
        case .teacher:
            return .teacher
        }
    }

    private func growthPackExecutionHubRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> MobileGrowthPackExecutionHubRole {
        switch role {
        case .child: return .child
        case .guardian, .relative, .teacher, .operations: return .guardian
        }
    }

    private func aiInboxRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> AIHomeworkFamilySchoolInboxViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .relative: return .guardian
        case .teacher: return .teacher
        case .operations: return .operations
        }
    }

    private func schoolJointApprovalRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> SchoolJointApprovalViewerRole {
        switch role {
        case .child, .relative, .operations: return .child
        case .guardian: return .guardian
        case .teacher: return .teacher
        }
    }

    private func schoolHomeworkLinkageRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> MobileSchoolHomeworkGrowthPackLinkageViewerRole {
        switch role {
        case .child, .relative, .operations: return .child
        case .guardian: return .guardian
        case .teacher: return .teacher
        }
    }

    private func notificationDigestRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> MobileFamilySchoolNotificationDigestViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .operations: return .guardian
        case .teacher: return .teacher
        case .relative: return .relative
        }
    }

    private func familyHonorRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> FamilyHonorStorylineConsentViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .teacher, .operations: return .guardian
        case .relative: return .relative
        }
    }

    private func growthDiaryVlogRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> MobileGrowthDiaryVlogViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .teacher, .operations: return .guardian
        case .relative: return .relative
        }
    }

    private func familyGrowthRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> FamilyGrowthViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .teacher, .operations: return .guardian
        case .relative: return .relative
        }
    }

    private func creditLedgerRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> CreditLedgerReviewViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .operations: return .guardian
        case .relative: return .relative
        case .teacher: return .teacher
        }
    }

    private func rewardStoreFulfillmentRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> MobileRewardStoreFulfillmentRole {
        switch role {
        case .child: return .child
        // operations 走 safePreview，不会到这里；其它角色统一进家长复核视角。
        case .guardian, .relative, .teacher, .operations: return .guardian
        }
    }

    private func appSelectionRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> AppSelectionViewerRole {
        switch role {
        case .child: return .child
        // operations 走 safePreview，不会到这里；其它角色统一进最小成人边界。
        case .guardian, .relative, .teacher, .operations: return .guardian
        }
    }

    private func reportsRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> ReportsViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .relative, .teacher, .operations: return .guardian
        }
    }

    private func onboardingRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> OnboardingViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .relative, .teacher, .operations: return .guardian
        }
    }

    private func offlineSyncReviewPerspective(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> MobileHomePerspective {
        switch role {
        case .child: return .child
        case .guardian, .relative, .teacher, .operations: return .parent
        }
    }

    private func moduleConfigurationDraftRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> MobileModuleConfigurationDraftViewerRole {
        switch role {
        case .guardian: return .guardian
        // 非家长角色正常不会到这里；兜底保持受限孩子视角，避免未来直接路由时越权。
        case .child, .relative, .teacher, .operations: return .child
        }
    }

    private func emotionalSafetyRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> MobileFamilySocialFeedbackEmotionalSafetyCenterRole {
        switch role {
        case .child: return .child
        case .guardian: return .guardian
        case .relative: return .relative
        // 运营在此入口代表平台专家视角：只看通用主题边界，不看孩子私密内容或家庭规则。
        case .operations: return .expert
        // teacher 不在该模块 allowedRoles 内，不会到达；兜底回到最受限的专家边界视角。
        case .teacher: return .expert
        }
    }

    private func releaseGateRole(
        for role: MobileModuleLaunchCenterViewerRole
    ) -> MobileReleaseCandidateGateViewerRole {
        switch role {
        case .guardian: return .guardian
        case .operations: return .operations
        case .child, .relative, .teacher: return .child
        }
    }

    private func icon(for status: MobileModuleLaunchCenterStatus) -> String {
        switch status {
        case .ready: return "checkmark.circle"
        case .active: return "play.circle"
        case .reviewRequired: return "exclamationmark.circle"
        case .blocked: return "xmark.octagon"
        }
    }

    private func color(for status: MobileModuleLaunchCenterStatus) -> Color {
        switch status {
        case .ready: return .green
        case .active: return .blue
        case .reviewRequired: return .orange
        case .blocked: return .red
        }
    }

    private func icon(for severity: MobileModuleLaunchSeverity) -> String {
        switch severity {
        case .ok: return "checkmark.circle"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .blocker: return "xmark.octagon"
        }
    }

    private func color(for severity: MobileModuleLaunchSeverity) -> Color {
        switch severity {
        case .ok: return .green
        case .info: return .blue
        case .warning: return .orange
        case .blocker: return .red
        }
    }

    private func icon(for group: MobileModuleLaunchGroupKind) -> String {
        switch group {
        case .basicTasks: return "checklist"
        case .growthPacks: return "shippingbox"
        case .schoolLearning: return "graduationcap"
        case .familyHonor: return "heart.text.square"
        case .creditReward: return "timer"
        case .platformSync: return "arrow.triangle.2.circlepath"
        case .platformQuality: return "checkmark.shield"
        }
    }
}

private struct MobileModuleLaunchRoutePreviewView: View {
    let route: MobileModuleLaunchRoute

    var body: some View {
        List {
            Section {
                Label(route.title, systemImage: "eye")
                    .font(.headline)
                    .accessibilityIdentifier("module-route-preview-title")
                Text(route.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("module-route-preview-subtitle")
                LabeledContent("模块") {
                    Text(route.moduleKey.title)
                }
                .accessibilityIdentifier("module-route-preview-module")
                LabeledContent("视角") {
                    Text(route.viewerRole.label)
                }
                .accessibilityIdentifier("module-route-preview-role-\(route.viewerRole.rawValue)")
                LabeledContent("公开路由") {
                    Text(route.publicRouteRef)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("module-route-preview-public-ref")
            } footer: {
                Text("这是脱敏安全预览，不进入家庭内部详情，不调用网络、不写系统、不发成长积分、不通知、不解锁设备。")
                    .accessibilityIdentifier("module-route-preview-guardrail")
            }

            Section("无副作用") {
                LabeledContent("调用网络 / AI", value: (route.callsNetwork || route.callsAiProvider || route.callsLocalModel) ? "会" : "不会")
                    .accessibilityIdentifier("module-route-preview-effect-network-ai")
                LabeledContent("学校 / LMS", value: (route.writesSchoolSystem || route.callsLms) ? "会" : "不会")
                    .accessibilityIdentifier("module-route-preview-effect-school-lms")
                LabeledContent("账本 / 成长积分", value: (route.writesLedger || route.grantsCredit) ? "会" : "不会")
                    .accessibilityIdentifier("module-route-preview-effect-ledger-credit")
                LabeledContent("通知 / 设备", value: (route.sendsNotification || route.unlocksDevice) ? "会" : "不会")
                    .accessibilityIdentifier("module-route-preview-effect-notification-device")
                LabeledContent("支付 / 权益", value: (route.createsOrder || route.writesEntitlement) ? "会" : "不会")
                    .accessibilityIdentifier("module-route-preview-effect-order-entitlement")
            }
        }
        .navigationTitle("模块安全预览")
        .navigationBarTitleDisplayMode(.inline)
    }
}
