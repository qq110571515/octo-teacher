import SwiftUI

/// 家庭成就快照仪表盘。
///
/// 对齐 B32 的移动端成就快照语义：证据状态、徽章/成长球星卡/荣誉墙/故事线摘要、
/// 亲友参与、风险提示和下一步动作全部按角色门控。页面本身只读，无任何真实副作用。
struct FamilyAchievementSnapshotDashboardView: View {
    @State private var store: FamilyGrowthAchievementStore
    @State private var role: FamilyGrowthViewerRole
    private let allowsRoleSwitching: Bool

    init(
        store: FamilyGrowthAchievementStore = FamilyGrowthAchievementStore(),
        initialRole: FamilyGrowthViewerRole = .guardian,
        allowsRoleSwitching: Bool = true
    ) {
        _store = State(initialValue: store)
        _role = State(initialValue: initialRole)
        self.allowsRoleSwitching = allowsRoleSwitching
    }

    private var dashboard: FamilyAchievementSnapshotDashboard {
        FamilyAchievementSnapshotDashboardBuilder(store: store).dashboard(for: role)
    }

    var body: some View {
        List {
            roleSection
            statusSection
            evidenceSection
            summarySection
            relativeSection
            riskSection
            actionSection
            safetySection
        }
        .navigationTitle("成就快照")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var roleSection: some View {
        Section {
            if allowsRoleSwitching {
                Picker("视角", selection: $role) {
                    ForEach(FamilyGrowthViewerRole.allCases, id: \.self) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }
            Text(role.audienceNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusSection: some View {
        Section("快照状态") {
            LabeledContent("状态") {
                Text(dashboard.status.label)
                    .foregroundStyle(statusColor(dashboard.status))
            }
            .accessibilityIdentifier("family-achievement-status")
            LabeledContent("公开可展示") {
                Text("\(dashboard.publicSummary.publicReadyCount)").monospacedDigit()
            }
            .accessibilityIdentifier("family-achievement-public-ready-count")
            LabeledContent("脱敏家庭") {
                Text(dashboard.familyPublicRef)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("family-achievement-family-ref")
            LabeledContent("脱敏孩子") {
                Text(dashboard.childPublicRef)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("family-achievement-child-ref")
        }
    }

    private var evidenceSection: some View {
        Section("证据状态") {
            MetricRow(title: "可见成就", value: dashboard.evidence.visibleAchievementCount, systemImage: "square.grid.2x2")
                .accessibilityIdentifier("family-achievement-evidence-visible")
            MetricRow(title: "正式荣誉", value: dashboard.evidence.formalHonorCount, systemImage: "checkmark.seal")
                .accessibilityIdentifier("family-achievement-evidence-formal")
            if role == .guardian {
                MetricRow(title: "待复核", value: dashboard.evidence.reviewRequiredCount, systemImage: "clock")
                    .accessibilityIdentifier("family-achievement-evidence-review-required")
                MetricRow(title: "已阻断", value: dashboard.evidence.blockedCount, systemImage: "exclamationmark.shield")
                    .accessibilityIdentifier("family-achievement-evidence-blocked")
                MetricRow(title: "已撤回", value: dashboard.evidence.withdrawnCount, systemImage: "arrow.uturn.backward")
                    .accessibilityIdentifier("family-achievement-evidence-withdrawn")
            }
        }
    }

    private var summarySection: some View {
        Section("成长模块") {
            CountSummaryRow(summary: dashboard.badgeSummary, systemImage: "rosette")
                .accessibilityIdentifier("family-achievement-summary-badge")
            AbilityCardSummaryRow(summary: dashboard.abilityCardSummary)
                .accessibilityIdentifier("family-achievement-summary-ability-card")
            CountSummaryRow(summary: dashboard.honorSummary, systemImage: "trophy")
                .accessibilityIdentifier("family-achievement-summary-honor")
            CountSummaryRow(summary: dashboard.storylineSummary, systemImage: "sparkles")
                .accessibilityIdentifier("family-achievement-summary-storyline")
        }
    }

    private var relativeSection: some View {
        Section("亲友参与") {
            LabeledContent("可见亲友参与") {
                Text(dashboard.relativeParticipation.canSeeParticipation ? "是" : "否")
            }
            .accessibilityIdentifier("family-achievement-relative-visible")
            MetricRow(title: "已批准鼓励", value: dashboard.relativeParticipation.approvedCommentCount, systemImage: "text.bubble")
                .accessibilityIdentifier("family-achievement-relative-approved-comments")
            if role == .guardian {
                MetricRow(title: "待审核亲友内容", value: dashboard.relativeParticipation.pendingCommentCount, systemImage: "person.2.badge.gearshape")
                    .accessibilityIdentifier("family-achievement-relative-pending-comments")
                MetricRow(title: "亲友阻断项", value: dashboard.relativeParticipation.blockedActionCount, systemImage: "hand.raised")
                    .accessibilityIdentifier("family-achievement-relative-blocked-actions")
            }
            if let ref = dashboard.relativeParticipation.viewerRelativePublicRef {
                LabeledContent("脱敏亲友") {
                    Text(ref)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("family-achievement-relative-ref")
            }
        }
    }

    private var riskSection: some View {
        Section("风险提示") {
            if dashboard.riskFlags.isEmpty {
                Text(role == .guardian ? "暂无需要处理的风险" : "当前视角不展示家长复核风险")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dashboard.riskFlags) { risk in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(risk.title)
                                .font(.subheadline)
                            Text("\(risk.source.label) · \(risk.severity.label)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: risk.severity == .blocker ? "exclamationmark.shield" : "exclamationmark.triangle")
                            .foregroundStyle(risk.severity == .blocker ? .red : .orange)
                    }
                    .accessibilityIdentifier("family-achievement-risk-\(risk.source.rawValue)-\(risk.severity.rawValue)")
                }
            }
        }
    }

    private var actionSection: some View {
        Section("下一步") {
            ForEach(dashboard.nextActions) { action in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title)
                            .font(.subheadline)
                        Text(action.actionRequired ? "需要家长处理" : "只读展示")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: action.actionRequired ? "checklist" : "eye")
                        .foregroundStyle(action.actionRequired ? .orange : .blue)
                }
                .accessibilityIdentifier("family-achievement-action-\(action.kind.rawValue)")
            }
        }
    }

    private var safetySection: some View {
        Section {
            Text("快照仪表盘只读：不发布、不授徽章、不改能力卡、不写账本、不上传媒体、不通知亲友、不解锁设备。亲友视角看不到待审核数量、阻断数量或家长审批动作。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func statusColor(_ status: FamilyAchievementSnapshotStatus) -> Color {
        switch status {
        case .ready: return .green
        case .reviewRequired: return .orange
        case .blocked: return .red
        case .privateOnly: return .secondary
        }
    }
}

private struct MetricRow: View {
    let title: String
    let value: Int
    let systemImage: String

    var body: some View {
        LabeledContent {
            Text("\(value)").monospacedDigit()
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

private struct CountSummaryRow: View {
    let summary: FamilyAchievementCountSummary
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(summary.title, systemImage: systemImage)
                .font(.subheadline.bold())
            HStack {
                SmallMetric(title: "总数", value: summary.itemCount)
                SmallMetric(title: "已验证", value: summary.verifiedCount)
                SmallMetric(title: "待复核", value: summary.reviewRequiredCount)
                SmallMetric(title: "阻断", value: summary.blockedCount)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct AbilityCardSummaryRow: View {
    let summary: FamilyAchievementAbilityCardSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("成长球星卡", systemImage: "person.text.rectangle")
                .font(.subheadline.bold())
            HStack {
                SmallMetric(title: "卡片", value: summary.cardCount)
                SmallMetric(title: "维度", value: summary.dimensionScoreCount)
                SmallMetric(title: "平均", value: summary.averageScore ?? 0)
                SmallMetric(title: "警示", value: summary.warningCount)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SmallMetric: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.caption.bold()).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
