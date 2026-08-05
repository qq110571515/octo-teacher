import SwiftUI

/// 成长包云同步移动端只读桥接页。
///
/// 页面只消费本地 mock/read model，不触发云同步、购买、权益写入、账本、通知或设备解锁。
struct GrowthPackCloudSyncMobileBridgeView: View {
    @State private var viewerRole: GrowthPackCloudSyncMobileBridgeViewerRole
    private let builder = GrowthPackCloudSyncMobileBridgeBuilder()
    private let allowsRoleSwitching: Bool

    init(
        initialRole: GrowthPackCloudSyncMobileBridgeViewerRole = .guardian,
        allowsRoleSwitching: Bool = true
    ) {
        _viewerRole = State(initialValue: initialRole)
        self.allowsRoleSwitching = allowsRoleSwitching
    }

    private var snapshot: GrowthPackCloudSyncMobileBridgeSnapshot {
        builder.build(viewerRole: viewerRole)
    }

    var body: some View {
        List {
            roleSection(snapshot)
            headerSection(snapshot)
            refundDisputeSection()
            cardsSection(snapshot)
            detailSection(snapshot)
            offlineSection(snapshot)
            findingsSection(snapshot)
            guardrailSection(snapshot)
        }
        .navigationTitle("成长包云同步")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func roleSection(_ snapshot: GrowthPackCloudSyncMobileBridgeSnapshot) -> some View {
        Section {
            if allowsRoleSwitching {
                Picker("视角", selection: $viewerRole) {
                    ForEach(GrowthPackCloudSyncMobileBridgeViewerRole.allCases, id: \.self) { role in
                        Text(role.label).tag(role)
                    }
                }
                .pickerStyle(.segmented)
            }
            Text(roleNote(snapshot.visibility))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func refundDisputeSection() -> some View {
        Section(refundDisputeSectionTitle) {
            NavigationLink {
                MobileGrowthPackRefundRevocationQualityDisputeWorkbenchView(
                    initialRole: refundDisputeRole(for: viewerRole),
                    allowedRoles: [refundDisputeRole(for: viewerRole)]
                )
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(refundDisputeLinkTitle)
                            .font(.subheadline.weight(.semibold))
                        Text(refundDisputeLinkDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundStyle(.orange)
                }
            }
            .accessibilityIdentifier("growth-pack-cloud-sync-refund-dispute-link")
        }
    }

    private var refundDisputeSectionTitle: String {
        switch viewerRole {
        case .child, .relative:
            return "安全处理"
        case .guardian, .operations:
            return "售后复核"
        case .creator:
            return "质量反馈"
        }
    }

    private var refundDisputeLinkTitle: String {
        switch viewerRole {
        case .child, .relative:
            return "查看成长包安全处理"
        case .guardian, .operations:
            return "查看成长包售后复核"
        case .creator:
            return "查看成长包质量反馈"
        }
    }

    private var refundDisputeLinkDetail: String {
        switch viewerRole {
        case .child, .relative:
            return "把云端可用性变化转成安全下一步，不展示成人侧细节。"
        case .guardian, .operations:
            return "把云镜像过期、撤权下架、质量反馈和成长积分冻结汇总到本地只读复核壳。"
        case .creator:
            return "只看脱敏质量反馈和版本提示，不展示用户侧细节。"
        }
    }

    private func headerSection(_ snapshot: GrowthPackCloudSyncMobileBridgeSnapshot) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(snapshot.state.label)
                        .font(.title2.bold())
                        .foregroundStyle(color(for: snapshot.state))
                    Spacer(minLength: 8)
                    Text("\(snapshot.publicSummary.visibleCardCount) 卡")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(snapshot.headline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    GrowthPackCloudSyncMetricPill(title: "详情", value: "\(snapshot.publicSummary.visibleDetailCount)", tint: .blue)
                    GrowthPackCloudSyncMetricPill(title: "待办", value: "\(snapshot.publicSummary.actionRequiredCount)", tint: snapshot.publicSummary.actionRequiredCount > 0 ? .orange : .green)
                    GrowthPackCloudSyncMetricPill(title: "离线", value: "\(snapshot.publicSummary.offlineAttentionCount)", tint: snapshot.publicSummary.offlineAttentionCount > 0 ? .red : .green)
                }
            }
        } footer: {
            Text("这里是移动端 read model 桥接层，只读组合本地快照；真实云同步和市场权益必须经过后端权限闸门。")
        }
    }

    private func cardsSection(_ snapshot: GrowthPackCloudSyncMobileBridgeSnapshot) -> some View {
        Section("首页卡片") {
            if snapshot.homeCards.isEmpty {
                Text("当前视角暂无可见卡片。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.homeCards) { card in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon(for: card.surface, state: card.state))
                            .foregroundStyle(color(for: card.state))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(card.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer(minLength: 8)
                                Text(card.badge)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(color(for: card.state))
                            }
                            Text(card.detail)
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

    private func detailSection(_ snapshot: GrowthPackCloudSyncMobileBridgeSnapshot) -> some View {
        Section("详情桥接") {
            if snapshot.detailItems.isEmpty {
                Text("当前视角不可查看详情桥接。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.detailItems) { item in
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: item.actionRequired ? "exclamationmark.triangle" : "doc.text.magnifyingglass")
                            .foregroundStyle(item.actionRequired ? Color.orange : Color.blue)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func offlineSection(_ snapshot: GrowthPackCloudSyncMobileBridgeSnapshot) -> some View {
        Section("离线提示") {
            if let prompt = snapshot.offlinePrompt {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(prompt.title)
                            .font(.subheadline.weight(.semibold))
                        Text(prompt.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: prompt.actionRequired ? "wifi.exclamationmark" : "wifi")
                        .foregroundStyle(prompt.actionRequired ? Color.orange : Color.green)
                }
            } else {
                Text("当前视角不显示离线同步提示。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func findingsSection(_ snapshot: GrowthPackCloudSyncMobileBridgeSnapshot) -> some View {
        Section("桥接发现") {
            ForEach(snapshot.findings) { finding in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon(for: finding.severity))
                        .foregroundStyle(color(for: finding.severity))
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

    private func guardrailSection(_ snapshot: GrowthPackCloudSyncMobileBridgeSnapshot) -> some View {
        Section("无副作用边界") {
            LabeledContent("云同步/写云", value: (snapshot.sideEffects.callsCloud || snapshot.sideEffects.writesCloud) ? "会" : "不会")
            LabeledContent("支付/订单/市场", value: (snapshot.sideEffects.chargesPayment || snapshot.sideEffects.createsOrder || snapshot.sideEffects.writesMarketplace) ? "会" : "不会")
            LabeledContent("权益/素材下载", value: (snapshot.sideEffects.writesEntitlement || snapshot.sideEffects.downloadsAssets) ? "会" : "不会")
            LabeledContent("账本/成长积分/设备", value: (snapshot.sideEffects.writesLedger || snapshot.sideEffects.grantsCredit || snapshot.sideEffects.unlocksDevice) ? "会" : "不会")
            LabeledContent("AI/LMS/学校/通知", value: (snapshot.sideEffects.callsAi || snapshot.sideEffects.callsLms || snapshot.sideEffects.writesSchoolSystem || snapshot.sideEffects.sendsNotification) ? "会" : "不会")
        }
    }

    private func roleNote(_ visibility: GrowthPackCloudSyncMobileBridgeVisibility) -> String {
        switch visibility.viewerRole {
        case .child:
            return "孩子只看能否继续和下一步，不看订单、权益、云端内部、同意细节或成长积分金额。"
        case .guardian:
            return "家长可看复核提示，但本页仍不购买、不退款、不写权益、不发成长积分。"
        case .relative:
            return "亲友只读，只看家长开放的成长包摘要。"
        case .creator:
            return "创作者只看公开生命周期和版本提示，不看家庭权益。"
        case .operations:
            return "运营只看脱敏计数和阻断状态。"
        }
    }

    private func refundDisputeRole(
        for role: GrowthPackCloudSyncMobileBridgeViewerRole
    ) -> MobileGrowthPackRefundDisputeRole {
        switch role {
        case .child, .relative:
            return .child
        case .guardian, .operations:
            return .guardian
        case .creator:
            return .creator
        }
    }

    private func color(for state: GrowthPackCloudSyncMobileBridgeState) -> Color {
        switch state {
        case .ready: return .green
        case .reviewRequired: return .orange
        case .conflict: return .red
        case .frozen: return .blue
        case .revoked, .blocked: return .red
        }
    }

    private func icon(
        for surface: GrowthPackCloudSyncMobileBridgeSurface,
        state: GrowthPackCloudSyncMobileBridgeState
    ) -> String {
        if state == .blocked || state == .revoked { return "xmark.octagon" }
        switch surface {
        case .homeCard: return "icloud.and.arrow.down"
        case .detail: return "shippingbox"
        case .offlinePrompt: return "wifi.exclamationmark"
        case .permissionGate: return "lock.shield"
        case .operationsSummary: return "chart.bar.doc.horizontal"
        }
    }

    private func color(for severity: GrowthPackCloudSyncMobileBridgeSeverity) -> Color {
        switch severity {
        case .ok: return .green
        case .info: return .blue
        case .warning: return .orange
        case .blocker: return .red
        }
    }

    private func icon(for severity: GrowthPackCloudSyncMobileBridgeSeverity) -> String {
        switch severity {
        case .ok: return "checkmark.seal"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .blocker: return "xmark.octagon"
        }
    }
}

private struct GrowthPackCloudSyncMetricPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.monospacedDigit().weight(.bold))
            Text(title)
                .font(.caption2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .foregroundStyle(tint)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
