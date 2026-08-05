import SwiftUI

/// iOS 娱乐 App 选择 / 锁定策略预览。
///
/// 只消费本地脱敏候选项，不打开 Apple FamilyControls 选择器，不写 ManagedSettings。
struct AppSelectionWorkbenchView: View {
    @State private var role: AppSelectionViewerRole
    private let allowedRoles: [AppSelectionViewerRole]
    private let candidates: [AppSelectionCandidate]

    init(
        initialRole: AppSelectionViewerRole = .guardian,
        allowedRoles: [AppSelectionViewerRole] = AppSelectionViewerRole.allCases,
        candidates: [AppSelectionCandidate] = AppSelectionWorkbenchBuilder.mockCandidates
    ) {
        let normalized = Self.normalizedRoles(allowedRoles)
        let resolvedRole = normalized.contains(initialRole) ? initialRole : normalized[0]
        _role = State(initialValue: resolvedRole)
        self.allowedRoles = normalized
        self.candidates = candidates
    }

    private var workbench: AppSelectionWorkbench {
        AppSelectionWorkbenchBuilder().build(role: role, candidates: candidates)
    }

    var body: some View {
        List {
            roleSection
            overviewSection
            candidateSection
            policySection
            findingSection
            boundarySection
        }
        .navigationTitle("娱乐 App")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var roleSection: some View {
        Section {
            if allowedRoles.count > 1 {
                Picker("视角", selection: $role) {
                    ForEach(allowedRoles, id: \.self) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("app-selection-role-picker")
            } else {
                LabeledContent("视角", value: role.label)
                    .accessibilityIdentifier("app-selection-role-\(role.rawValue)")
            }
            Text(workbench.note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("app-selection-note")
        }
    }

    private var overviewSection: some View {
        Section(workbench.title) {
            Text(workbench.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("app-selection-subtitle")
            AppSelectionMetric(title: "候选", value: workbench.publicSummary.candidateCount, systemImage: "square.grid.2x2")
                .accessibilityIdentifier("app-selection-metric-candidates")
            AppSelectionMetric(title: "已选", value: workbench.publicSummary.selectedCount, systemImage: "checkmark.square")
                .accessibilityIdentifier("app-selection-metric-selected")
            AppSelectionMetric(title: "已确认", value: workbench.publicSummary.approvedSelectedCount, systemImage: "person.badge.shield.checkmark")
                .accessibilityIdentifier("app-selection-metric-approved")
            if role == .guardian {
                AppSelectionMetric(title: "待确认", value: workbench.publicSummary.pendingGuardianCount, systemImage: "hourglass")
                    .accessibilityIdentifier("app-selection-metric-pending")
                AppSelectionMetric(title: "阻断", value: workbench.publicSummary.blockedCount, systemImage: "hand.raised")
                    .accessibilityIdentifier("app-selection-metric-blocked")
                AppSelectionMetric(title: "高风险", value: workbench.publicSummary.highRiskSelectedCount, systemImage: "exclamationmark.triangle")
                    .accessibilityIdentifier("app-selection-metric-high-risk")
            }
        }
    }

    private var candidateSection: some View {
        Section(role == .child ? "可兑换类别" : "候选 App") {
            if workbench.candidates.isEmpty {
                ContentUnavailableView("暂无可展示候选", systemImage: "lock.shield")
            } else {
                ForEach(workbench.candidates) { candidate in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: icon(for: candidate.category))
                                .foregroundStyle(tint(for: candidate.approvalState))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(candidate.displayName)
                                    .font(.subheadline.bold())
                                Text("\(candidate.category.label) · 风险\(candidate.riskLevel.label)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(candidate.approvalState.label)
                                .font(.caption2.bold())
                                .foregroundStyle(tint(for: candidate.approvalState))
                        }
                        Text(role == .child ? candidate.childSummary : candidate.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            AppSelectionPill(title: candidate.selectedForShield ? "已选" : "未选", active: candidate.selectedForShield)
                            AppSelectionPill(title: candidate.guardianApproved ? "已确认" : "待确认", active: candidate.guardianApproved)
                            AppSelectionPill(title: candidate.ageAllowed ? "年龄合适" : "年龄阻断", active: candidate.ageAllowed)
                        }
                    }
                    .padding(.vertical, 3)
                    .accessibilityIdentifier("app-selection-candidate-\(candidate.publicAppRef)")
                }
            }
        }
    }

    private var policySection: some View {
        Section("策略步骤") {
            ForEach(workbench.policySteps) { step in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.subheadline.bold())
                        Text(step.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: step.done ? "checkmark.circle" : "clock.badge.exclamationmark")
                        .foregroundStyle(step.done ? .green : .orange)
                }
                .accessibilityIdentifier("app-selection-policy-\(step.id)")
            }
        }
    }

    @ViewBuilder
    private var findingSection: some View {
        let visibleFindings = workbench.findings.filter { role == .guardian || $0.visibleToChild }
        if !visibleFindings.isEmpty {
            Section(role == .child ? "兑换边界" : "家长复核") {
                ForEach(visibleFindings) { finding in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.title)
                                .font(.subheadline.bold())
                            Text(finding.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: finding.actionRequired ? "exclamationmark.shield" : "checkmark.shield")
                            .foregroundStyle(finding.actionRequired ? .orange : .green)
                    }
                    .accessibilityIdentifier("app-selection-finding-\(finding.id)")
                }
            }
        }
    }

    private var boundarySection: some View {
        Section("执行边界") {
            AppSelectionBoundaryFlag(title: "FamilyControls", value: workbench.publicSummary.callsFamilyControls)
                .accessibilityIdentifier("app-selection-boundary-family-controls")
            AppSelectionBoundaryFlag(title: "ManagedSettings", value: workbench.publicSummary.callsManagedSettings)
                .accessibilityIdentifier("app-selection-boundary-managed-settings")
            AppSelectionBoundaryFlag(title: "DeviceActivity", value: workbench.publicSummary.callsDeviceActivity)
                .accessibilityIdentifier("app-selection-boundary-device-activity")
            AppSelectionBoundaryFlag(title: "读取已安装 App", value: workbench.publicSummary.readsInstalledApplications)
                .accessibilityIdentifier("app-selection-boundary-installed-apps")
            AppSelectionBoundaryFlag(title: "保存系统标识", value: workbench.publicSummary.storesBundleIdentifiers)
                .accessibilityIdentifier("app-selection-boundary-bundle-ids")
            AppSelectionBoundaryFlag(title: "账本 / 成长积分 / 解锁", value: workbench.publicSummary.writesLedger || workbench.publicSummary.grantsCredit || workbench.publicSummary.unlocksDevice)
                .accessibilityIdentifier("app-selection-boundary-ledger-credit-device")
        }
    }

    private func icon(for category: AppSelectionCategory) -> String {
        switch category {
        case .game: return "gamecontroller"
        case .shortVideo: return "play.rectangle"
        case .social: return "bubble.left.and.bubble.right"
        case .learning: return "book"
        }
    }

    private func tint(for state: AppSelectionApprovalState) -> Color {
        switch state {
        case .ready: return .green
        case .pendingGuardian: return .orange
        case .blocked: return .red
        }
    }

    private static func normalizedRoles(_ roles: [AppSelectionViewerRole]) -> [AppSelectionViewerRole] {
        let source = roles.isEmpty ? AppSelectionViewerRole.allCases : roles
        return AppSelectionViewerRole.allCases.filter { source.contains($0) }
    }
}

private struct AppSelectionMetric: View {
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

private struct AppSelectionPill: View {
    let title: String
    let active: Bool

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(active ? .green : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((active ? Color.green : Color.secondary).opacity(0.12), in: Capsule())
    }
}

private struct AppSelectionBoundaryFlag: View {
    let title: String
    let value: Bool

    var body: some View {
        LabeledContent(title) {
            Text(value ? "会触发" : "不触发")
                .foregroundStyle(value ? .red : .green)
        }
    }
}
