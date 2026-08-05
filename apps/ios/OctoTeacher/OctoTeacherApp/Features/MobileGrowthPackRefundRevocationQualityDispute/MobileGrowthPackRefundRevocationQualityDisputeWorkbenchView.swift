import SwiftUI

/// 成长包退款/撤权/质量争议复核页。
///
/// 只消费本地 mock，不触发退款、权益写入、账本、通知、成长积分或设备控制。
struct MobileGrowthPackRefundRevocationQualityDisputeWorkbenchView: View {
    @State private var role: MobileGrowthPackRefundDisputeRole
    private let allowedRoles: [MobileGrowthPackRefundDisputeRole]
    private let builder = MobileGrowthPackRefundRevocationQualityDisputeBuilder()

    init(
        initialRole: MobileGrowthPackRefundDisputeRole = .guardian,
        allowedRoles: [MobileGrowthPackRefundDisputeRole] = MobileGrowthPackRefundDisputeRole.allCases
    ) {
        let resolved = allowedRoles.contains(initialRole) ? initialRole : allowedRoles.first ?? .guardian
        _role = State(initialValue: resolved)
        self.allowedRoles = allowedRoles.isEmpty ? [.guardian] : allowedRoles
    }

    private var workbench: MobileGrowthPackRefundDisputeWorkbench {
        builder.build(role: role)
    }

    var body: some View {
        List {
            roleSection
            headerSection
            rowsSection
            findingsSection
            guardrailSection
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var roleSection: some View {
        Section {
            if allowedRoles.count > 1 {
                Picker("视角", selection: $role) {
                    ForEach(allowedRoles, id: \.self) { role in
                        Text(role.label).tag(role)
                    }
                }
                .pickerStyle(.segmented)
            }
            Text(workbench.audienceNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(workbench.title)
                    .font(.headline)
                Text(workbench.subtitle)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    RefundDisputeMetricPill(title: "待复核", value: "\(workbench.publicSummary.reviewRequiredCount)", tint: .orange)
                    RefundDisputeMetricPill(title: "冻结", value: "\(workbench.publicSummary.frozenCount)", tint: .blue)
                    RefundDisputeMetricPill(title: "阻断", value: "\(workbench.publicSummary.blockedCount)", tint: .red)
                }
            }
        } footer: {
            Text(headerFooter)
        }
    }

    private var rowsSection: some View {
        Section("成长包复核") {
            if workbench.rows.isEmpty {
                Text("当前视角暂无可见复核项。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(workbench.rows) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: icon(for: row.state))
                                .foregroundStyle(color(for: row.state))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(row.title)
                                        .font(.subheadline.weight(.semibold))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 8)
                                    Text(row.state.label)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(color(for: row.state))
                                }
                                Text(row.statusLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(row.category)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        LabeledContent("生命周期", value: row.lifecycleLabel)
                        LabeledContent("进度", value: row.progressLabel)
                        LabeledContent("成长积分边界", value: row.creditBoundaryLabel)
                        if let creatorFeedback = row.creatorFeedback {
                            LabeledContent("质量反馈", value: creatorFeedback)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.nextStep)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(color(for: row.state))
                            Text(row.safetyNote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var findingsSection: some View {
        Section("复核发现") {
            ForEach(workbench.findings) { finding in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: finding.actionRequired ? "exclamationmark.triangle" : "checkmark.seal")
                        .foregroundStyle(finding.actionRequired ? Color.orange : Color.green)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(finding.code.rawValue)
                            .font(.caption.monospaced().weight(.semibold))
                        Text(finding.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var guardrailSection: some View {
        Section("无副作用边界") {
            ForEach(guardrailItems) { item in
                LabeledContent(item.title, value: item.triggered ? "会" : "不会")
            }
        }
    }

    private var navigationTitle: String {
        switch role {
        case .child:
            return "安全处理"
        case .guardian:
            return "售后复核"
        case .creator:
            return "质量反馈"
        }
    }

    private var headerFooter: String {
        switch role {
        case .child:
            return "这里只读展示安全下一步；暂停项需要家长流程处理。"
        case .guardian:
            return "这里只读展示售后复核建议；真实退款、权益恢复、成长积分回滚和设备状态必须由正式家长流程处理。"
        case .creator:
            return "这里只读展示脱敏反馈；版本改进由创作者流程处理。"
        }
    }

    private var guardrailItems: [RefundDisputeGuardrailItem] {
        let summary = workbench.publicSummary
        switch role {
        case .child:
            return [
                RefundDisputeGuardrailItem(title: "任务改动", triggered: summary.writesSchoolSystem),
                RefundDisputeGuardrailItem(title: "成长积分变化", triggered: summary.writesLedger || summary.grantsCredit || summary.deductsCredit),
                RefundDisputeGuardrailItem(title: "徽章能力", triggered: summary.grantsBadge || summary.mutatesAbilityCard),
                RefundDisputeGuardrailItem(title: "提醒联网", triggered: summary.sendsNotification || summary.callsNetwork || summary.callsAI),
                RefundDisputeGuardrailItem(title: "娱乐时间", triggered: summary.unlocksDevice)
            ]
        case .guardian:
            return [
                RefundDisputeGuardrailItem(title: "支付/退款", triggered: summary.chargesPayment || summary.refundsPayment),
                RefundDisputeGuardrailItem(title: "权益/订单", triggered: summary.restoresEntitlement || summary.writesEntitlement || summary.writesOrder),
                RefundDisputeGuardrailItem(title: "账本/成长积分", triggered: summary.writesLedger || summary.grantsCredit || summary.deductsCredit),
                RefundDisputeGuardrailItem(title: "徽章/能力卡", triggered: summary.grantsBadge || summary.mutatesAbilityCard),
                RefundDisputeGuardrailItem(title: "网络/AI/学校/设备", triggered: summary.callsNetwork || summary.callsAI || summary.writesSchoolSystem || summary.unlocksDevice)
            ]
        case .creator:
            return [
                RefundDisputeGuardrailItem(title: "反馈改动", triggered: false),
                RefundDisputeGuardrailItem(title: "版本记录", triggered: summary.mutatesAbilityCard),
                RefundDisputeGuardrailItem(title: "结算动作", triggered: summary.chargesPayment || summary.refundsPayment || summary.writesLedger),
                RefundDisputeGuardrailItem(title: "通知动作", triggered: summary.sendsNotification),
                RefundDisputeGuardrailItem(title: "外部服务", triggered: summary.callsNetwork || summary.callsAI || summary.writesSchoolSystem)
            ]
        }
    }

    private func color(for state: MobileGrowthPackRefundDisputeState) -> Color {
        switch state {
        case .active: return .green
        case .reviewRequired: return .orange
        case .frozen: return .blue
        case .blocked: return .red
        case .hidden: return .secondary
        }
    }

    private func icon(for state: MobileGrowthPackRefundDisputeState) -> String {
        switch state {
        case .active: return "checkmark.seal"
        case .reviewRequired: return "doc.text.magnifyingglass"
        case .frozen: return "pause.circle"
        case .blocked: return "xmark.octagon"
        case .hidden: return "eye.slash"
        }
    }
}

private struct RefundDisputeMetricPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.bold))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(tint)
    }
}

private struct RefundDisputeGuardrailItem: Identifiable {
    let title: String
    let triggered: Bool

    var id: String { title }
}
