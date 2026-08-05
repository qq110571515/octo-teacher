import SwiftUI

/// 移动平台首页 / 工作台。
///
/// App 启动后的第一屏：一个角色感知的手机首页，把今日任务、学校作业、家庭成长动态、
/// 成长积分/奖励状态和家长审批/亲友审核摘要编排到一起。可在「孩子 / 家长」视角间切换。
///
/// 这是工作台而非营销落地页：第一屏即可使用，所有数据来自本地 mock/store，
/// 首页本身不提供批准/发成长积分/解锁设备入口，写操作仍在对应的 Parent / Family 标签内完成。
struct MobileHomeView: View {
    @Environment(LocalFamilyStore.self) private var family
    @Environment(SchoolFamilyStore.self) private var schoolFamily
    @Environment(MockScreenTimeController.self) private var screenTime
    @Environment(MobileOfflineOutboxStore.self) private var offlineOutbox
    @Environment(MobileOfflineReplayStore.self) private var offlineReplay
    @Environment(MobileCreditSettlementStore.self) private var creditSettlement
    @Environment(GrowthPackRuntimeStore.self) private var growthRuntime
    /// 移动同步 mock 客户端：只读消费内置 snapshot，不接网络。
    @State private var sync = MobileSyncClient.makeMockOrEmpty()
    @State private var perspective: MobileHomePerspective = .child

    private var brandLanguage: AppInterfaceLanguage {
        perspective == .child
            ? family.activeChildInterfaceLanguage
            : family.settings.resolvedParentInterfaceLanguage
    }

    private var viewModel: MobileHomeViewModel {
        MobileHomeOrchestrator(
            sync: sync,
            schoolFamily: schoolFamily,
            family: family,
            growthRuntimeReport: growthRuntime.report
        )
            .makeViewModel(for: perspective)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("视角", selection: $perspective) {
                        ForEach(MobileHomePerspective.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(alignment: .center, spacing: 12) {
                        Image(BrandIdentity.logoAssetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .accessibilityLabel(BrandIdentity.name(for: brandLanguage))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(BrandIdentity.name(for: brandLanguage))
                                .font(.title2.bold())
                            Text(BrandIdentity.tagline(for: brandLanguage))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(viewModel.greeting)
                                .font(.headline)
                            Text(viewModel.headline)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)

                    if !viewModel.metrics.isEmpty {
                        MetricStrip(metrics: viewModel.metrics)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12))
                    }

                    FirstStepCard(perspective: perspective)

                    NavigationLink {
                        let role = moduleLaunchRole(for: perspective)
                        MobileModuleLaunchCenterView(initialRole: role, allowedRoles: [role])
                    } label: {
                        Label("模块能力中心", systemImage: "rectangle.grid.2x2")
                    }
                    .accessibilityIdentifier("mobile-home-module-center-link")

                    NavigationLink {
                        MobilePlatformAggregateDashboardView()
                    } label: {
                        Label("平台总览驾驶舱", systemImage: "square.grid.2x2")
                    }
                    .accessibilityIdentifier("mobile-home-platform-dashboard-link")
                }

                Section {
                    OfflineSyncStatusRow(status: offlineOutbox.publicStatus)
                    ForEach(offlineOutbox.conflictHints.prefix(3)) { hint in
                        OfflineConflictHintRow(hint: hint)
                    }
                } header: {
                    Text("同步状态")
                } footer: {
                    Text("离线动作只进入本地队列，联网后仍需家长、老师或服务端流程确认。")
                }

                MobileOfflineReplaySummarySection(report: offlineReplay.report) {
                    offlineReplay.replay(outbox: offlineOutbox)
                    refreshSettlement()
                }

                MobileCreditSettlementSummarySection(report: creditSettlement.report) {
                    refreshSettlement()
                }

                ForEach(viewModel.sections) { section in
                    Section {
                        if section.items.isEmpty {
                            Text(section.emptyText ?? "暂无内容")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(section.items) { item in
                                homeItemRow(item)
                            }
                        }
                    } header: {
                        Text(section.title)
                    } footer: {
                        if let subtitle = section.subtitle {
                            Text(subtitle)
                        }
                    }
                }
            }
            .navigationTitle(BrandIdentity.name(for: brandLanguage))
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            // 首屏即跑一次本地确定性重放，让同步结果可见；用户可再手动重放。
            if !offlineReplay.hasReplayed {
                offlineReplay.replay(outbox: offlineOutbox)
            }
            // 基于重放结果与本地 store 生成一次结算建议（账本中立）。
            refreshSettlement()
            // 生成成长包运行闭环投影。只读本地 store，不发成长积分、不写账本、不解锁设备。
            if !growthRuntime.hasBuilt {
                growthRuntime.refresh(family: family, schoolFamily: schoolFamily)
            }
        }
    }

    /// 基于最新离线重放报告与本地 store 重新生成结算建议。只读不写。
    private func refreshSettlement() {
        creditSettlement.refresh(
            offlineReport: offlineReplay.report,
            family: family,
            schoolFamily: schoolFamily,
            screenTime: screenTime
        )
    }

    @ViewBuilder
    private func homeItemRow(_ item: MobileHomeItem) -> some View {
        if let destination = item.destination, destination.allowedPerspectives.contains(perspective) {
            NavigationLink {
                destinationView(for: destination, perspective: perspective)
            } label: {
                HomeItemRow(item: item)
            }
            .accessibilityIdentifier("mobile-home-item-\(item.id)")
        } else {
            HomeItemRow(item: item)
        }
    }

    @ViewBuilder
    private func destinationView(for destination: MobileHomeDestination, perspective: MobileHomePerspective) -> some View {
        switch destination {
        case .moduleConfigurationDraft:
            MobileModuleConfigurationDraftView()
        case .aiHomeworkInbox:
            let role = aiHomeworkInboxRole(for: perspective)
            AIHomeworkFamilySchoolInboxView(initialRole: role, allowedRoles: [role])
        case .schoolJointApproval:
            let role = schoolJointApprovalRole(for: perspective)
            SchoolJointApprovalBoardView(initialRole: role, allowedRoles: [role])
        case .growthPackExecutionHub:
            let role = growthPackExecutionHubRole(for: perspective)
            MobileGrowthPackExecutionHubView(initialRole: role, allowedRoles: [role])
        case .rewardRedemption:
            ChildCreditWalletView()
        case .rewardStatus:
            RewardStatusView()
        case .rewardStoreFulfillment:
            // 孩子 -> child 视角，家长 -> guardian 视角；锁定单角色，孩子无法切到家长复核页。
            let role = rewardStoreFulfillmentRole(for: perspective)
            MobileRewardStoreInventoryFulfillmentWorkbenchView(initialRole: role, allowedRoles: [role])
        case .growthPackEntitlements:
            GrowthPackInstallEntitlementView(
                initialRole: growthPackInstallRole(for: perspective),
                allowsRoleSwitching: false
            )
        case .growthPackCloudSync:
            GrowthPackCloudSyncMobileBridgeView(
                initialRole: growthPackCloudSyncRole(for: perspective),
                allowsRoleSwitching: false
            )
        case .creditLedgerReview:
            // 仅家长可进入；孩子视角的编排层从不产出该目的地。
            CreditLedgerReviewView(viewerRole: .guardian)
        case .releaseGate:
            // 仅家长可进入；只读发布质量门，不发布、不写账本、不解锁设备。
            MobileReleaseCandidateGateView(initialRole: .guardian, allowsRoleSwitching: false)
        case .familyStorylineConsent:
            // 仅家长可进入；锁定同意入口，不发布、不通知、不发成长积分、不解锁设备。
            FamilyHonorStorylineConsentView(
                store: FamilyGrowthAchievementStore(),
                initialRole: .guardian,
                allowsRoleSwitching: false
            )
        case .familySocialFeedbackEmotionalSafety:
            let role = familySocialFeedbackEmotionalSafetyRole(for: perspective)
            MobileFamilySocialFeedbackEmotionalSafetyCenterView(initialRole: role, allowedRoles: [role])
        case .offlineSyncReview:
            // 孩子/家长均可进入；本地只读复核台，可手动重放但不落定，不写账本、不发成长积分、不解锁设备。
            MobileOfflineSyncReviewView(perspective: perspective)
        }
    }

    private func aiHomeworkInboxRole(for perspective: MobileHomePerspective) -> AIHomeworkFamilySchoolInboxViewerRole {
        switch perspective {
        case .child:
            return .child
        case .parent:
            return .guardian
        }
    }

    private func schoolJointApprovalRole(for perspective: MobileHomePerspective) -> SchoolJointApprovalViewerRole {
        switch perspective {
        case .child:
            return .child
        case .parent:
            return .guardian
        }
    }

    private func growthPackExecutionHubRole(for perspective: MobileHomePerspective) -> MobileGrowthPackExecutionHubRole {
        switch perspective {
        case .child:
            return .child
        case .parent:
            return .guardian
        }
    }

    private func growthPackInstallRole(for perspective: MobileHomePerspective) -> GrowthPackInstallViewerRole {
        switch perspective {
        case .child:
            return .child
        case .parent:
            return .guardian
        }
    }

    private func rewardStoreFulfillmentRole(for perspective: MobileHomePerspective) -> MobileRewardStoreFulfillmentRole {
        switch perspective {
        case .child:
            return .child
        case .parent:
            return .guardian
        }
    }

    private func growthPackCloudSyncRole(for perspective: MobileHomePerspective) -> GrowthPackCloudSyncMobileBridgeViewerRole {
        switch perspective {
        case .child:
            return .child
        case .parent:
            return .guardian
        }
    }

    private func familySocialFeedbackEmotionalSafetyRole(
        for perspective: MobileHomePerspective
    ) -> MobileFamilySocialFeedbackEmotionalSafetyCenterRole {
        switch perspective {
        case .child:
            return .child
        case .parent:
            return .guardian
        }
    }

    /// 把首页视角映射为模块能力中心初始视角：孩子 -> child，家长 -> guardian。
    /// 避免家长点进模块中心却停留在孩子页。
    private func moduleLaunchRole(for perspective: MobileHomePerspective) -> MobileModuleLaunchCenterViewerRole {
        switch perspective {
        case .child:
            return .child
        case .parent:
            return .guardian
        }
    }
}

/// 首页里的离线同步摘要。
private struct OfflineSyncStatusRow: View {
    let status: MobileOfflinePublicStatus

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.hasAttention ? "exclamationmark.arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath")
                .foregroundStyle(status.hasAttention ? Color.orange : Color.green)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(status.headline)
                    .font(.subheadline.weight(.semibold))
                Text("待同步 \(status.pendingCount) · 冲突 \(status.conflictCount) · 已回滚 \(status.rolledBackCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 首页里的冲突/回滚提示。
private struct OfflineConflictHintRow: View {
    let hint: MobileOfflineConflictHint

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: hint.rolledBack ? "arrow.uturn.backward.circle" : "exclamationmark.triangle")
                .foregroundStyle(hint.rolledBack ? Color.secondary : Color.orange)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(hint.kindLabel) · \(hint.actorLabel)")
                    .font(.subheadline.weight(.semibold))
                Text(hint.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(hint.nextStep)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 首页第一步入口：把孩子和家长最常见的下一步放在首屏。
private struct FirstStepCard: View {
    let perspective: MobileHomePerspective

    var body: some View {
        NavigationLink {
            switch perspective {
            case .child:
                ChildHomeView()
            case .parent:
                ParentModeView()
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
        }
    }

    private var title: String {
        switch perspective {
        case .child:
            return "孩子现在先做什么"
        case .parent:
            return "家长现在先做什么"
        }
    }

    private var message: String {
        switch perspective {
        case .child:
            return "先进入孩子首页，打开今日任务卡，完成后写一句证明，交给大人看看并等待成长积分。"
        case .parent:
            return "先进入家长工作台，用家长 PIN 解锁，就能审核孩子的提交、布置新任务、查看奖励余额。"
        }
    }

    private var systemImage: String {
        switch perspective {
        case .child:
            return "checklist"
        case .parent:
            return "person.badge.key"
        }
    }
}

/// 顶部指标条。
private struct MetricStrip: View {
    let metrics: [MobileHomeMetric]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(metrics) { metric in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(metric.value)
                            .font(.title3.bold())
                            .monospacedDigit()
                            .foregroundStyle(tint(for: metric.tone))
                        Text(metric.title)
                            .font(.caption)
                        if let caption = metric.caption {
                            Text(caption)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(minWidth: 96, alignment: .leading)
                    .background(tint(for: metric.tone).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func tint(for tone: MobileHomeTone) -> Color { tone.color }
}

/// 单条首页编排条目。
private struct HomeItemRow: View {
    let item: MobileHomeItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.body)
                .foregroundStyle(item.tone.color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = item.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if let badge = item.badge {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(item.tone.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(item.tone.color)
            }
        }
        .padding(.vertical, 2)
    }
}

extension MobileHomeTone {
    /// 语气对应的展示色。
    var color: Color {
        switch self {
        case .neutral: return .secondary
        case .positive: return .green
        case .attention: return .blue
        case .risk: return .orange
        }
    }
}
