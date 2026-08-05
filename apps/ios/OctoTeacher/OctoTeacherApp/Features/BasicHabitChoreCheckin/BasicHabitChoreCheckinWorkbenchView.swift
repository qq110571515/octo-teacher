import SwiftUI

struct BasicHabitChoreCheckinWorkbenchView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(MobileOfflineOutboxStore.self) private var offlineOutbox
    @State private var viewerRole: MobileBasicHabitChoreViewerRole

    private let allowedRoles: [MobileBasicHabitChoreViewerRole]
    private let builder = MobileBasicHabitChoreCheckinWorkbenchBuilder()

    init(
        initialRole: MobileBasicHabitChoreViewerRole = .child,
        allowedRoles: [MobileBasicHabitChoreViewerRole] = MobileBasicHabitChoreViewerRole.allCases
    ) {
        let roles = allowedRoles.isEmpty ? [initialRole] : allowedRoles
        self.allowedRoles = roles
        _viewerRole = State(initialValue: roles.contains(initialRole) ? initialRole : roles[0])
    }

    private var workbench: MobileBasicHabitChoreCheckinWorkbench {
        builder.build(
            store: store,
            viewerRole: viewerRole,
            offlineStatus: offlineOutbox.publicStatus
        )
    }

    var body: some View {
        let workbench = workbench

        List {
            roleSection
            summarySection(workbench)
            primaryActionSection(workbench)
            nextActionSection(workbench)
            itemSection(workbench)
            if viewerRole == .guardian {
                findingSection(workbench)
            }
            noSideEffectSection(workbench)
        }
        .navigationTitle(workbench.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var roleSection: some View {
        if allowedRoles.count > 1 {
            Section {
                Picker("视角", selection: $viewerRole) {
                    ForEach(allowedRoles, id: \.self) { role in
                        Text(role.label).tag(role)
                    }
            }
            .pickerStyle(.segmented)
        } footer: {
                Text("这里只读汇总个人独立性与家务状态，不在本页处理奖励、审批、通知或设备。")
            }
        } else {
            Section {
                LabeledContent("视角", value: viewerRole.label)
            }
        }
    }

    private func summarySection(
        _ workbench: MobileBasicHabitChoreCheckinWorkbench
    ) -> some View {
        Section {
            Text(workbench.projection.headline)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                metric("可打卡", "\(workbench.counts.ready)")
                metric("等待", "\(workbench.counts.waitingCheck)")
                metric("已完成", "\(workbench.counts.done)")
                metric("连续", "\(workbench.longestStreakDays)d")
            }
        } header: {
            Text("今日概览")
        }
    }

    private func nextActionSection(
        _ workbench: MobileBasicHabitChoreCheckinWorkbench
    ) -> some View {
        Section("下一步") {
            ForEach(workbench.projection.nextActions, id: \.self) { action in
                Label(action, systemImage: "arrow.forward.circle")
                    .font(.subheadline)
            }
            if workbench.offlineHint.hasPending {
                Label(workbench.offlineHint.title, systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func primaryActionSection(
        _ workbench: MobileBasicHabitChoreCheckinWorkbench
    ) -> some View {
        if viewerRole == .child, let assignment = primaryActionAssignment(in: workbench) {
            Section {
                NavigationLink {
                    TaskDetailView(assignment: assignment)
                } label: {
                    Label("开始第一个可打卡任务", systemImage: "play.circle.fill")
                        .font(.headline)
                }
                .accessibilityIdentifier("basic-habit-primary-action")
            } footer: {
                Text("进入后可以写一句话、拍照或从相册选择证明，再提交给大人确认；确认后才会进入成长积分。")
            }
        }
    }

    @ViewBuilder
    private func itemSection(
        _ workbench: MobileBasicHabitChoreCheckinWorkbench
    ) -> some View {
        if workbench.isEmpty {
            Section("个人独立性与家务") {
                ContentUnavailableView("暂无个人独立性或家务任务", systemImage: "checklist")
            }
        } else {
            Section("个人独立性与家务") {
                ForEach(workbench.projection.visibleItems) { item in
                    if viewerRole == .child, let assignment = assignment(for: item) {
                        NavigationLink {
                            TaskDetailView(assignment: assignment)
                        } label: {
                            HabitChoreItemRow(item: item, viewerRole: viewerRole)
                        }
                        .accessibilityIdentifier("basic-habit-item-\(item.publicItemRef)")
                    } else {
                        HabitChoreItemRow(item: item, viewerRole: viewerRole)
                    }
                }
            }
        }
    }

    private func primaryActionAssignment(
        in workbench: MobileBasicHabitChoreCheckinWorkbench
    ) -> TaskAssignment? {
        workbench.projection.visibleItems
            .filter { $0.state == .ready || $0.state == .redo }
            .compactMap { assignment(for: $0) }
            .first
    }

    private func assignment(for item: MobileBasicHabitChoreItem) -> TaskAssignment? {
        store.assignments.first { $0.id == item.assignmentId }
    }

    private func findingSection(
        _ workbench: MobileBasicHabitChoreCheckinWorkbench
    ) -> some View {
        Section("护栏") {
            ForEach(workbench.findings) { finding in
                Label(finding.message, systemImage: icon(for: finding.severity))
                    .font(.caption)
                    .foregroundStyle(color(for: finding.severity))
            }
        }
    }

    private func noSideEffectSection(
        _ workbench: MobileBasicHabitChoreCheckinWorkbench
    ) -> some View {
        Section("无副作用") {
            LabeledContent("网络 / AI", value: (workbench.publicSummary.callsNetwork || workbench.publicSummary.callsAiProvider || workbench.publicSummary.callsLocalModel) ? "会" : "不会")
            LabeledContent("学校 / LMS", value: (workbench.publicSummary.writesSchoolSystem || workbench.publicSummary.callsLms) ? "会" : "不会")
            LabeledContent("写账本 / 奖励", value: (workbench.publicSummary.writesLedger || workbench.publicSummary.grantsCredit || workbench.publicSummary.spendsCredit) ? "会" : "不会")
            LabeledContent("通知 / 设备", value: (workbench.publicSummary.sendsNotification || workbench.publicSummary.unlocksDevice) ? "会" : "不会")
            LabeledContent("上传媒体", value: workbench.publicSummary.uploadsMedia ? "会" : "不会")
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

    private func icon(for severity: MobileBasicHabitChoreSeverity) -> String {
        switch severity {
        case .ok: return "checkmark.circle.fill"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle.fill"
        case .blocker: return "xmark.octagon.fill"
        }
    }

    private func color(for severity: MobileBasicHabitChoreSeverity) -> Color {
        switch severity {
        case .ok: return .green
        case .info: return .blue
        case .warning: return .orange
        case .blocker: return .red
        }
    }
}

private struct HabitChoreItemRow: View {
    let item: MobileBasicHabitChoreItem
    let viewerRole: MobileBasicHabitChoreViewerRole

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.kind.systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(item.state.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(tint)
                    }
                    Text(viewerRole == .child ? item.childNextStep : item.guardianNextStep)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.proofSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Label(item.kind.label, systemImage: item.kind.systemImage)
                        Label(item.rewardLabel, systemImage: "seal")
                        Label("\(item.streakDays) 天", systemImage: "flame")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var tint: Color {
        switch item.state {
        case .locked: return .secondary
        case .ready: return .blue
        case .waitingCheck: return .orange
        case .done: return .green
        case .redo: return .red
        }
    }
}
