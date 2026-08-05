import SwiftUI

/// iOS 成长包安装前试运行配置沙盒页面。
///
/// 只消费本地 mock 投影，不购买、不退款、不安装、不创建任务、不写权益、不发成长积分、不解锁设备。
struct MobileGrowthPackPreinstallTrialSandboxWorkbenchView: View {
    @State private var role: MobileGrowthPackPreinstallTrialRole
    private let allowedRoles: [MobileGrowthPackPreinstallTrialRole]

    init(
        initialRole: MobileGrowthPackPreinstallTrialRole = .guardian,
        allowedRoles: [MobileGrowthPackPreinstallTrialRole] = MobileGrowthPackPreinstallTrialRole.allCases
    ) {
        let normalized = Self.normalizedRoles(allowedRoles)
        let resolvedRole = normalized.contains(initialRole) ? initialRole : normalized[0]
        _role = State(initialValue: resolvedRole)
        self.allowedRoles = normalized
    }

    private var workbench: MobileGrowthPackPreinstallTrialSandboxWorkbench {
        MobileGrowthPackPreinstallTrialSandboxBuilder().build(role: role)
    }

    var body: some View {
        List {
            roleSection
            overviewSection
            trialSection
            findingSection
            sideEffectSection
        }
        .navigationTitle("安装前试运行")
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
            }
            Text(workbench.audienceNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var overviewSection: some View {
        Section(workbench.title) {
            Text(workbench.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            PreinstallTrialMetric(title: "可见成长包", value: workbench.publicSummary.visiblePackCount, systemImage: "shippingbox")
                .accessibilityIdentifier("preinstall-trial-metric-visible")
            if role != .child {
                PreinstallTrialMetric(title: "待复核", value: workbench.publicSummary.guardianReviewCount, systemImage: "person.badge.clock")
                    .accessibilityIdentifier("preinstall-trial-metric-guardian-review")
                PreinstallTrialMetric(title: "已阻断/冻结", value: workbench.publicSummary.blockedCount, systemImage: "lock.shield")
                    .accessibilityIdentifier("preinstall-trial-metric-blocked")
                PreinstallTrialMetric(title: "学校优先级", value: workbench.publicSummary.schoolPriorityConflictCount, systemImage: "graduationcap")
                    .accessibilityIdentifier("preinstall-trial-metric-school-priority")
                PreinstallTrialMetric(title: "成长积分边界", value: workbench.publicSummary.creditBoundaryReviewCount, systemImage: "creditcard.trianglebadge.exclamationmark")
                    .accessibilityIdentifier("preinstall-trial-metric-credit-boundary")
            }
        }
    }

    private var trialSection: some View {
        Section("试运行预览") {
            if workbench.rows.isEmpty {
                ContentUnavailableView("暂无可见试运行", systemImage: "lock")
            } else {
                ForEach(workbench.rows) { row in
                    PreinstallTrialRow(row: row)
                }
            }
        }
    }

    private var findingSection: some View {
        Section(role == .child ? "安全提示" : "试运行发现") {
            if workbench.findings.isEmpty {
                Text(role == .child ? "暂无风险提示" : "暂无待修项")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(workbench.findings) { finding in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.code.rawValue)
                                .font(.caption.bold())
                            Text(finding.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: finding.actionRequired ? "exclamationmark.shield" : "checkmark.shield")
                            .foregroundStyle(finding.actionRequired ? .orange : .green)
                    }
                    .accessibilityIdentifier("preinstall-trial-finding-\(finding.code.rawValue)")
                }
            }
        }
    }

    private var sideEffectSection: some View {
        Section("执行边界") {
            PreinstallTrialBoundaryFlag(title: "真实安装动作", value: workbench.publicSummary.purchasesPack || workbench.publicSummary.refundsPayment || workbench.publicSummary.installsPack)
                .accessibilityIdentifier("preinstall-trial-boundary-install")
            PreinstallTrialBoundaryFlag(title: "配置记录写入", value: workbench.publicSummary.createsAssignment || workbench.publicSummary.writesEntitlement || workbench.publicSummary.writesOrder)
                .accessibilityIdentifier("preinstall-trial-boundary-configuration")
            PreinstallTrialBoundaryFlag(title: "账本/奖励/设备", value: workbench.publicSummary.writesLedger || workbench.publicSummary.grantsCredit || workbench.publicSummary.unlocksDevice)
                .accessibilityIdentifier("preinstall-trial-boundary-ledger-device")
            PreinstallTrialBoundaryFlag(title: "荣誉资料写入", value: workbench.publicSummary.grantsBadge || workbench.publicSummary.mutatesAbilityCard)
                .accessibilityIdentifier("preinstall-trial-boundary-honor")
            PreinstallTrialBoundaryFlag(title: "外部系统调用", value: workbench.publicSummary.sendsNotification || workbench.publicSummary.callsNetwork || workbench.publicSummary.callsAI || workbench.publicSummary.writesSchoolSystem)
                .accessibilityIdentifier("preinstall-trial-boundary-external")
        }
    }

    private static func normalizedRoles(
        _ roles: [MobileGrowthPackPreinstallTrialRole]
    ) -> [MobileGrowthPackPreinstallTrialRole] {
        let source = roles.isEmpty ? MobileGrowthPackPreinstallTrialRole.allCases : roles
        return MobileGrowthPackPreinstallTrialRole.allCases.filter { source.contains($0) }
    }
}

private struct PreinstallTrialRow: View {
    let row: MobileGrowthPackPreinstallTrialRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "shippingbox")
                    .foregroundStyle(tint)
                    .frame(width: 22)
                Text(row.title)
                    .font(.subheadline.bold())
                Spacer()
                Text(row.state.label)
                    .font(.caption2.bold())
                    .foregroundStyle(tint)
            }

            Text(row.learningPreview)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 5) {
                Label(row.installBoundaryLabel, systemImage: "square.and.arrow.down")
                Label(row.agePermissionLabel, systemImage: "person.crop.circle")
                Label(row.scheduleLabel, systemImage: "calendar")
                Label(row.proofLabel, systemImage: "checkmark.shield")
                Label(row.creditBoundaryLabel, systemImage: "creditcard")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Label(row.safetyNote, systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)

            Label(row.nextStep, systemImage: "arrow.forward.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .accessibilityIdentifier("preinstall-trial-row-\(row.state.rawValue)")
    }

    private var tint: Color {
        switch row.state {
        case .canTrial: return .blue
        case .needsGuardianReview: return .orange
        case .frozen: return .purple
        case .blocked: return .red
        case .hidden: return .secondary
        }
    }
}

private struct PreinstallTrialMetric: View {
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

private struct PreinstallTrialBoundaryFlag: View {
    let title: String
    let value: Bool

    var body: some View {
        LabeledContent(title) {
            Text(value ? "会触发" : "不触发")
                .foregroundStyle(value ? .red : .green)
        }
    }
}
