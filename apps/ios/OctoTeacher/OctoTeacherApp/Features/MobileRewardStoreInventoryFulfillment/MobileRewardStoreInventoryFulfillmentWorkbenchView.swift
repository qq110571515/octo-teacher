import SwiftUI

/// 奖励商店库存履约安全壳页面。
///
/// 只消费本地 mock，不真实兑换、不扣成长积分、不发货、不写账本/订单/库存、不退款、不通知、不解锁设备。
/// 可从 RewardRedemptionView 或 RewardStatusView 进入。
struct MobileRewardStoreInventoryFulfillmentWorkbenchView: View {
    @State private var role: MobileRewardStoreFulfillmentRole
    private let allowedRoles: [MobileRewardStoreFulfillmentRole]
    private let builder = MobileRewardStoreInventoryFulfillmentBuilder()

    init(
        initialRole: MobileRewardStoreFulfillmentRole = .child,
        allowedRoles: [MobileRewardStoreFulfillmentRole] = MobileRewardStoreFulfillmentRole.allCases
    ) {
        let resolved = allowedRoles.contains(initialRole) ? initialRole : allowedRoles.first ?? .child
        _role = State(initialValue: resolved)
        self.allowedRoles = allowedRoles.isEmpty ? [.child] : allowedRoles
    }

    private var workbench: MobileRewardStoreInventoryFulfillmentWorkbench {
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
                    .accessibilityIdentifier("reward-store-fulfillment-title")
                Text(workbench.subtitle)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("reward-store-fulfillment-subtitle")
                HStack(spacing: 8) {
                    RewardFulfillmentMetricPill(
                        id: "reward-store-fulfillment-metric-redeemable",
                        title: "可兑换",
                        value: "\(workbench.publicSummary.redeemableCount)",
                        tint: .green
                    )
                    RewardFulfillmentMetricPill(
                        id: "reward-store-fulfillment-metric-needs-parent",
                        title: "待家长",
                        value: "\(workbench.publicSummary.needsParentCount)",
                        tint: .orange
                    )
                    RewardFulfillmentMetricPill(
                        id: "reward-store-fulfillment-metric-unavailable",
                        title: "不可兑换",
                        value: "\(workbench.publicSummary.unavailableCount)",
                        tint: .red
                    )
                }
            }
        } footer: {
            Text(headerFooter)
        }
    }

    private var rowsSection: some View {
        Section("奖励列表") {
            if workbench.rows.isEmpty {
                Text("当前视角暂无可见奖励。")
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
                                Text("\(row.kindLabel) · \(row.category)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        LabeledContent("库存", value: row.availabilityLabel)
                        if role == .guardian {
                            LabeledContent("履约", value: row.fulfillmentLabel)
                            LabeledContent("成长积分边界", value: row.creditBoundaryLabel)
                            LabeledContent("设备上限", value: row.deviceCapLabel)
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
                    .accessibilityIdentifier("reward-store-fulfillment-row-\(row.state.rawValue)")
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
                .accessibilityIdentifier("reward-store-fulfillment-finding-\(finding.code.rawValue)")
            }
        }
    }

    private var guardrailSection: some View {
        Section("无副作用边界") {
            ForEach(guardrailItems) { item in
                LabeledContent(item.title, value: item.triggered ? "会" : "不会")
                    .accessibilityIdentifier("reward-store-fulfillment-guardrail-\(guardrailId(for: item.title))")
            }
        }
    }

    private var navigationTitle: String {
        role == .child ? "奖励商店" : "库存履约复核"
    }

    private var headerFooter: String {
        switch role {
        case .child:
            return "这里只看奖励，不会真的兑换；想换什么先告诉家长。"
        case .guardian:
            return "这里只读展示库存与履约复核建议；真实兑换、扣成长积分、发货、退款、回滚和设备解锁必须由正式流程处理。"
        }
    }

    private var guardrailItems: [RewardFulfillmentGuardrailItem] {
        let summary = workbench.publicSummary
        switch role {
        case .child:
            return [
                RewardFulfillmentGuardrailItem(title: "真实兑换", triggered: summary.redeemsReward),
                RewardFulfillmentGuardrailItem(title: "扣成长积分", triggered: summary.deductsCredit || summary.writesLedger),
                RewardFulfillmentGuardrailItem(title: "发货收货", triggered: summary.shipsGoods),
                RewardFulfillmentGuardrailItem(title: "娱乐时间", triggered: summary.unlocksDevice),
                RewardFulfillmentGuardrailItem(title: "提醒联网", triggered: summary.sendsNotification || summary.callsNetwork || summary.callsAI)
            ]
        case .guardian:
            return [
                RewardFulfillmentGuardrailItem(title: "兑换/订单/库存", triggered: summary.redeemsReward || summary.writesOrder || summary.writesInventory || summary.writesRedemption),
                RewardFulfillmentGuardrailItem(title: "扣成长积分/账本", triggered: summary.deductsCredit || summary.writesLedger),
                RewardFulfillmentGuardrailItem(title: "发货/退款/回滚", triggered: summary.shipsGoods || summary.refundsPayment || summary.rollsBack),
                RewardFulfillmentGuardrailItem(title: "徽章/能力卡/设备", triggered: summary.grantsBadge || summary.mutatesAbilityCard || summary.unlocksDevice),
                RewardFulfillmentGuardrailItem(title: "网络/AI/学校/通知", triggered: summary.callsNetwork || summary.callsAI || summary.writesSchoolSystem || summary.sendsNotification || summary.opensStoreKit)
            ]
        }
    }

    private func color(for state: MobileRewardStoreFulfillmentDisplayState) -> Color {
        switch state {
        case .redeemable: return .green
        case .reserved: return .blue
        case .needsParent: return .orange
        case .unavailable: return .red
        }
    }

    private func icon(for state: MobileRewardStoreFulfillmentDisplayState) -> String {
        switch state {
        case .redeemable: return "gift"
        case .reserved: return "hourglass"
        case .needsParent: return "person.2.badge.gearshape"
        case .unavailable: return "xmark.octagon"
        }
    }

    private func guardrailId(for title: String) -> String {
        switch title {
        case "真实兑换": return "real-redemption"
        case "扣成长积分": return "credit-deduction"
        case "发货收货": return "shipping"
        case "娱乐时间": return "device-time"
        case "提醒联网": return "network-notification"
        case "兑换/订单/库存": return "redemption-order-inventory"
        case "扣成长积分/账本": return "credit-ledger"
        case "发货/退款/回滚": return "shipping-refund-rollback"
        case "徽章/能力卡/设备": return "badge-card-device"
        case "网络/AI/学校/通知": return "network-ai-school-notification"
        default:
            return title
                .lowercased()
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: " ", with: "-")
        }
    }
}

private struct RewardFulfillmentMetricPill: View {
    let id: String
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
        .accessibilityIdentifier(id)
    }
}

private struct RewardFulfillmentGuardrailItem: Identifiable {
    let title: String
    let triggered: Bool

    var id: String { title }
}
