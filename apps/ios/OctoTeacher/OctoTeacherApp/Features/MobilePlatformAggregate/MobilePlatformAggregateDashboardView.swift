import SwiftUI

/// 移动平台总览仪表盘。
///
/// 这是 iOS 端跨模块的聚合视图：把首页、成长包、学校、家庭成就、成长积分奖励和离线同步
/// 编排成一个角色感知的只读驾驶舱。
struct MobilePlatformAggregateDashboardView: View {
    @Environment(LocalFamilyStore.self) private var family
    @Environment(SchoolFamilyStore.self) private var schoolFamily
    @Environment(MockScreenTimeController.self) private var screenTime
    @Environment(MobileOfflineOutboxStore.self) private var offlineOutbox
    @Environment(MobileOfflineReplayStore.self) private var offlineReplay
    @Environment(MobileCreditSettlementStore.self) private var creditSettlement
    @Environment(GrowthPackRuntimeStore.self) private var growthRuntime
    @Environment(GrowthEvidenceTimelineStore.self) private var evidenceTimeline

    @State private var viewerRole: MobilePlatformAggregateViewerRole = .guardian
    @State private var sync = MobileSyncClient.makeMockOrEmpty()
    private let adapter = MobilePlatformAggregateReadOnlyAdapter()

    private var snapshot: MobilePlatformAggregateSnapshot {
        let growth = GrowthPackMobileDetailSnapshotBuilder().build(
            viewerRole: growthRole(for: viewerRole),
            runtimeReport: growthRuntime.report,
            evidenceReport: evidenceTimeline.report,
            offlineStatus: offlineOutbox.publicStatus,
            offlineReport: offlineReplay.report
        )
        let school = SchoolGrowthCreditSnapshotBuilder().build(
            viewerRole: schoolRole(for: viewerRole),
            homeworks: schoolFamily.homeworks,
            runtimeReport: growthRuntime.report,
            evidenceReport: evidenceTimeline.report,
            offlineStatus: offlineOutbox.publicStatus,
            offlineReport: offlineReplay.report
        )
        let achievement = FamilyAchievementSnapshotDashboardBuilder()
            .dashboard(for: familyRole(for: viewerRole))
        return adapter.makeSnapshot(
            viewerRole: viewerRole,
            mobileSnapshot: sync.snapshot,
            familyAchievement: achievement,
            growthPack: growth,
            schoolCredit: school,
            offlineStatus: offlineOutbox.publicStatus,
            offlineReport: offlineReplay.report,
            creditSettlement: creditSettlement.report
        )
    }

    var body: some View {
        List {
            headerSection(snapshot)
            moduleCardsSection(snapshot)
            growthPackInstallSection(snapshot)
            todayTasksSection(snapshot)
            nextActionsSection(snapshot)
            riskSection(snapshot)
            guardrailSection(snapshot)
        }
        .navigationTitle("平台总览")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            refreshSnapshotInputs()
        }
    }

    private func refreshSnapshotInputs() {
        growthRuntime.refresh(family: family, schoolFamily: schoolFamily)
        evidenceTimeline.refresh(
            family: family,
            schoolFamily: schoolFamily,
            runtime: GrowthEvidenceTimelineRuntimeContext(report: growthRuntime.report)
        )
        if !offlineReplay.hasReplayed {
            offlineReplay.replay(outbox: offlineOutbox)
        }
        creditSettlement.refresh(
            offlineReport: offlineReplay.report,
            family: family,
            schoolFamily: schoolFamily,
            screenTime: screenTime
        )
    }

    private func headerSection(_ snapshot: MobilePlatformAggregateSnapshot) -> some View {
        Section {
            Picker("视角", selection: $viewerRole) {
                ForEach(MobilePlatformAggregateViewerRole.allCases, id: \.self) { role in
                    Text(role.label).tag(role)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(MobilePlatformAggregateUserFacingCopy.statusLabel(for: snapshot.header.status, role: snapshot.header.viewerRole))
                        .font(.title2.bold())
                    Spacer()
                    Text("\(snapshot.publicSummary.visibleModuleCount) 模块")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(summaryLine(snapshot))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    MetricPill(title: "任务", value: "\(snapshot.publicSummary.todayTaskCount)", tint: .blue)
                    MetricPill(title: "待审", value: "\(snapshot.publicSummary.pendingReviewCount)", tint: .orange)
                    MetricPill(title: "风险", value: "\(snapshot.publicSummary.riskCount)", tint: snapshot.publicSummary.riskCount > 0 ? .red : .green)
                }
            }
            .padding(.vertical, 2)

            NavigationLink {
                MobileReleaseCandidateGateView()
            } label: {
                Label("移动端发布质量门", systemImage: "checkmark.shield")
            }
            .accessibilityIdentifier("mobile-platform-release-gate-link")
        } footer: {
            Text("总览只读聚合本地快照。不同角色看到的模块、风险和下一步都由上游可见性规则裁剪。")
        }
    }

    private func moduleCardsSection(_ snapshot: MobilePlatformAggregateSnapshot) -> some View {
        Section("模块树干") {
            if snapshot.moduleCards.isEmpty {
                Text("当前视角暂无可见模块")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.moduleCards) { card in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon(for: card.kind))
                            .foregroundStyle(color(actionRequired: card.actionRequired))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(card.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer(minLength: 8)
                                Text(card.metricLabel)
                                    .font(.caption.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(color(actionRequired: card.actionRequired))
                            }
                            Text(card.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func growthPackInstallSection(_ snapshot: MobilePlatformAggregateSnapshot) -> some View {
        let display = adapter.growthPackInstallDisplay(from: snapshot)
        return Section {
            if !display.visible {
                Text("该视角不可查看成长包安装权益")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: display.actionRequired ? "shippingbox.and.arrow.backward" : "shippingbox")
                        .foregroundStyle(display.actionRequired ? Color.orange : Color.blue)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(display.title)
                            .font(.subheadline.weight(.semibold))
                        Text(display.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88, maximum: 118), spacing: 8)], spacing: 8) {
                    ForEach(display.metrics) { metric in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(metric.value)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(metric.label == "需关注" && metric.value > 0 ? Color.orange : Color.blue)
                            Text(metric.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        } header: {
            Text("成长包安装权益")
        } footer: {
            Text("此区块只显示本地只读安装权益投影，不购买、不退款、不写权益、不调用云端。")
        }
    }

    private func todayTasksSection(_ snapshot: MobilePlatformAggregateSnapshot) -> some View {
        Section("今日任务") {
            if snapshot.todayTasks.isEmpty {
                Text(snapshot.roleVisibility.canSeeTodayTasks ? "暂无今日任务" : "该视角不可查看今日任务")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.todayTasks.prefix(8)) { task in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: task.actionRequired ? "checklist" : "checkmark.seal")
                            .foregroundStyle(task.actionRequired ? Color.orange : Color.green)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.title)
                                .font(.subheadline.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(task.category) · \(task.priority) · \(task.status)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                if snapshot.todayTasks.count > 8 {
                    Text("另有 \(snapshot.todayTasks.count - 8) 项未展开")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func nextActionsSection(_ snapshot: MobilePlatformAggregateSnapshot) -> some View {
        Section("下一步") {
            ForEach(snapshot.nextActions.prefix(8)) { action in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon(for: action.source))
                        .foregroundStyle(color(for: action.severity))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(action.title)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(action.source.label) · \(action.severity.label) · \(action.actionRequired ? "需要处理" : "只读提示")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func riskSection(_ snapshot: MobilePlatformAggregateSnapshot) -> some View {
        let visibleRisks = snapshot.riskFlags.filter {
            snapshot.header.viewerRole != .child || $0.visibleToChild
        }

        return Section("风险与发现") {
            if visibleRisks.isEmpty {
                Text("暂无当前视角可见风险")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleRisks.prefix(8)) { risk in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: risk.severity == .blocker ? "exclamationmark.octagon" : "exclamationmark.triangle")
                            .foregroundStyle(color(for: risk.severity))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(MobilePlatformAggregateUserFacingCopy.riskTitle(for: risk))
                                .font(.subheadline.weight(.semibold))
                            Text(MobilePlatformAggregateUserFacingCopy.riskDetail(for: risk))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            DisclosureGroup("开发者信息") {
                                Text(MobilePlatformAggregateUserFacingCopy.developerCodeLabel(risk.code))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            .font(.caption2)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            ForEach(snapshot.findings) { finding in
                VStack(alignment: .leading, spacing: 3) {
                    Text(MobilePlatformAggregateUserFacingCopy.findingTitle(for: finding))
                        .font(.caption.weight(.semibold))
                    Text(MobilePlatformAggregateUserFacingCopy.findingDetail(for: finding))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup("开发者信息") {
                        Text(MobilePlatformAggregateUserFacingCopy.developerCodeLabel(finding.code.rawValue))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .font(.caption2)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func guardrailSection(_ snapshot: MobilePlatformAggregateSnapshot) -> some View {
        let install = adapter.growthPackInstallDisplay(from: snapshot)
        return Section("只读护栏") {
            LabeledContent("写成长积分账本", value: snapshot.publicSummary.writesLedger ? "会" : "不会")
            LabeledContent("改任务 / 作业", value: (snapshot.publicSummary.modifiesTaskState || snapshot.publicSummary.modifiesHomework || snapshot.publicSummary.writesSchoolHomework) ? "会" : "不会")
            LabeledContent("发徽章 / 更新球星卡", value: (snapshot.publicSummary.grantsBadge || snapshot.publicSummary.updatesAbilityCard) ? "会" : "不会")
            LabeledContent("通知 / 上传 / 解锁", value: (snapshot.publicSummary.sendsNotification || snapshot.publicSummary.uploadsMedia || snapshot.publicSummary.unlocksDevice) ? "会" : "不会")
            LabeledContent("购买 / 市场 / 权益", value: (install.createsOrder || install.writesMarketplace || install.writesEntitlement) ? "会" : "不会")
            LabeledContent("云端 / AI / 学校", value: (install.callsCloud || install.callsAi || install.writesSchoolSystem) ? "会" : "不会")
        }
    }

    private func summaryLine(_ snapshot: MobilePlatformAggregateSnapshot) -> String {
        "学校 \(snapshot.publicSummary.schoolAssignmentCount) · 家庭成就 \(snapshot.publicSummary.familyAchievementCount) · 已装 \(snapshot.publicSummary.growthPackInstalledCount) · 安装关注 \(snapshot.publicSummary.growthPackInstallAttentionCount)"
    }

    private func growthRole(for role: MobilePlatformAggregateViewerRole) -> GrowthPackMobileDetailViewerRole {
        switch role {
        case .child: return .child
        case .guardian: return .guardian
        case .relative: return .relative
        case .teacher: return .teacher
        }
    }

    private func schoolRole(for role: MobilePlatformAggregateViewerRole) -> SchoolGrowthCreditViewerRole {
        switch role {
        case .child, .relative: return .child
        case .guardian: return .guardian
        case .teacher: return .teacher
        }
    }

    private func familyRole(for role: MobilePlatformAggregateViewerRole) -> FamilyGrowthViewerRole {
        switch role {
        case .child, .teacher: return .child
        case .guardian: return .guardian
        case .relative: return .relative
        }
    }

    private func icon(for kind: MobilePlatformAggregateModuleKind) -> String {
        switch kind {
        case .todayTasks: return "checklist"
        case .growthPack: return "square.stack.3d.up"
        case .schoolHomework: return "graduationcap"
        case .creditReward: return "star.circle"
        case .familyAchievement: return "rosette"
        case .pendingReview: return "tray.full"
        case .offlineSync: return "arrow.triangle.2.circlepath"
        case .risk: return "shield.lefthalf.filled"
        }
    }

    private func icon(for source: MobilePlatformAggregateRiskSource) -> String {
        switch source {
        case .growthPack: return "square.stack.3d.up"
        case .schoolHomework: return "graduationcap"
        case .familyAchievement: return "rosette"
        case .creditReward: return "star.circle"
        case .offlineSync: return "arrow.triangle.2.circlepath"
        case .roleBoundary: return "person.crop.circle.badge.exclamationmark"
        }
    }

    private func color(actionRequired: Bool) -> Color {
        actionRequired ? .orange : .blue
    }

    private func color(for severity: MobilePlatformAggregateNextAction.Severity) -> Color {
        switch severity {
        case .info: return .blue
        case .warning: return .orange
        case .urgent: return .red
        }
    }

    private func color(for severity: MobilePlatformAggregateSeverity) -> Color {
        switch severity {
        case .ok: return .green
        case .info: return .blue
        case .warning: return .orange
        case .blocker: return .red
        }
    }
}

private struct MetricPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 66, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}
