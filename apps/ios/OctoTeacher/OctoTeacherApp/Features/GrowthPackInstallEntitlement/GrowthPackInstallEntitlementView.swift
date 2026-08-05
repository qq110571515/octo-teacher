import SwiftUI

/// 成长包安装权益 / 市场入口本地只读页。
///
/// 家长可查看购买与权益边界；孩子、亲友、创作者按角色裁剪。页面不购买、不退款、
/// 不写 entitlement、不发成长积分、不解锁设备。
struct GrowthPackInstallEntitlementView: View {
    @State private var viewerRole: GrowthPackInstallViewerRole
    private let builder = GrowthPackInstallEntitlementBuilder()
    private let allowsRoleSwitching: Bool

    init(
        initialRole: GrowthPackInstallViewerRole = .guardian,
        allowsRoleSwitching: Bool = true
    ) {
        _viewerRole = State(initialValue: initialRole)
        self.allowsRoleSwitching = allowsRoleSwitching
    }

    private var snapshot: GrowthPackInstallSnapshot {
        builder.build(viewerRole: viewerRole)
    }

    var body: some View {
        List {
            roleSection(snapshot)
            headerSection(snapshot)
            cloudSyncBridgeSection()
            preinstallTrialSection()
            refundDisputeSection()
            packSection(snapshot)
            findingsSection(snapshot)
            guardrailSection(snapshot)
        }
        .navigationTitle("成长包安装权益")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func roleSection(_ snapshot: GrowthPackInstallSnapshot) -> some View {
        Section {
            if allowsRoleSwitching {
                Picker("视角", selection: $viewerRole) {
                    ForEach(GrowthPackInstallViewerRole.allCases, id: \.self) { role in
                        Text(role.label).tag(role)
                    }
                }
                .pickerStyle(.segmented)
            }
            Text(snapshot.audienceNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func headerSection(_ snapshot: GrowthPackInstallSnapshot) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(snapshot.headline)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("可见 \(snapshot.publicSummary.visiblePackCount) · 可安装 \(snapshot.publicSummary.installableCount) · 已安装 \(snapshot.publicSummary.installedCount) · 待确认/冻结 \(snapshot.publicSummary.gatedCount) · 阻断 \(snapshot.publicSummary.blockedCount)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("所有安装、购买、退款和权益状态都是本地权益预览；真实支付和市场接入后仍必须经过云端权限闸门。")
        }
    }

    private func cloudSyncBridgeSection() -> some View {
        Section("云同步桥接") {
            NavigationLink {
                GrowthPackCloudSyncMobileBridgeView(
                    initialRole: cloudSyncBridgeRole(for: viewerRole),
                    allowsRoleSwitching: allowsRoleSwitching
                )
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("查看移动端云同步只读桥接")
                            .font(.subheadline.weight(.semibold))
                        Text("组合安装权益、权限闸门和离线回放状态，不写云端、不发成长积分、不解锁设备。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "icloud.and.arrow.down")
                        .foregroundStyle(.blue)
                }
            }
            .accessibilityIdentifier("growth-pack-install-link-cloud-sync")
        }
    }

    private func preinstallTrialSection() -> some View {
        Section("安装前试运行") {
            NavigationLink {
                MobileGrowthPackPreinstallTrialSandboxWorkbenchView(
                    initialRole: preinstallTrialRole(for: viewerRole),
                    allowedRoles: [preinstallTrialRole(for: viewerRole)]
                )
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("查看安装前配置试运行")
                            .font(.subheadline.weight(.semibold))
                        Text("本地预览任务节奏、证明、学校优先级和成长积分边界，不购买、不安装、不创建任务。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "play.square.stack")
                        .foregroundStyle(.blue)
                }
            }
            .accessibilityIdentifier("growth-pack-install-link-preinstall-trial")
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
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(.orange)
                }
            }
            .accessibilityIdentifier("growth-pack-install-link-refund-dispute")
        }
    }

    private var refundDisputeSectionTitle: String {
        switch viewerRole {
        case .child, .relative:
            return "安全处理"
        case .guardian:
            return "售后复核"
        case .creator:
            return "质量反馈"
        }
    }

    private var refundDisputeLinkTitle: String {
        switch viewerRole {
        case .child, .relative:
            return "查看成长包安全处理"
        case .guardian:
            return "查看退款撤权质量复核"
        case .creator:
            return "查看成长包质量反馈"
        }
    }

    private var refundDisputeLinkDetail: String {
        switch viewerRole {
        case .child, .relative:
            return "只看可继续、暂时暂停和等待家长处理的安全下一步。"
        case .guardian:
            return "本地复核退款窗口、撤权下架、进度保留和成长积分冻结，不退款、不写权益。"
        case .creator:
            return "只看脱敏质量反馈和版本提示，不展示用户侧细节。"
        }
    }

    private func packSection(_ snapshot: GrowthPackInstallSnapshot) -> some View {
        Section("成长包与权益") {
            if snapshot.decisions.isEmpty {
                Text("该视角暂无可见成长包。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.decisions) { decision in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: icon(for: decision.state))
                                .foregroundStyle(color(for: decision.state))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(decision.title)
                                        .font(.subheadline.weight(.semibold))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                    Text(decision.state.label)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(color(for: decision.state))
                                }
                                Text(decision.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(decision.category) · \(decision.creatorDisplayName) · \(decision.ageLabel)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let listing = decision.listingLabel {
                            LabeledContent("市场状态", value: listing)
                        }
                        if let entitlement = decision.entitlementLabel {
                            LabeledContent("权益状态", value: entitlement)
                        }
                        if let price = decision.priceLabel {
                            LabeledContent("价格/订单", value: price)
                        }
                        if let order = decision.orderPublicRef {
                            LabeledContent("订单引用", value: order)
                        }
                        if let entitlementRef = decision.entitlementPublicRef {
                            LabeledContent("权益引用", value: entitlementRef)
                        }
                        if !decision.requiredPermissionLabels.isEmpty {
                            LabeledContent("所需权限", value: decision.requiredPermissionLabels.joined(separator: "、"))
                        }
                        if let migration = decision.migrationNotice {
                            Label(migration, systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(decision.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(decision.nextAction)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(color(for: decision.state))
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("growth-pack-install-decision-\(decision.state.rawValue)")
                }
            }
        }
    }

    private func findingsSection(_ snapshot: GrowthPackInstallSnapshot) -> some View {
        Section("投影发现") {
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
                .accessibilityIdentifier("growth-pack-install-finding-\(finding.code.rawValue)")
            }
        }
    }

    private func guardrailSection(_ snapshot: GrowthPackInstallSnapshot) -> some View {
        Section("无副作用边界") {
            GrowthPackInstallGuardrailFlag(id: "payment-order", title: "真实购买/订单", value: snapshot.publicSummary.chargesPayment || snapshot.publicSummary.createsOrder)
            GrowthPackInstallGuardrailFlag(id: "marketplace-entitlement", title: "写市场/权益", value: snapshot.publicSummary.writesMarketplace || snapshot.publicSummary.writesEntitlement)
            GrowthPackInstallGuardrailFlag(id: "credit-device", title: "成长积分/设备", value: snapshot.publicSummary.writesLedger || snapshot.publicSummary.grantsCredit || snapshot.publicSummary.unlocksDevice)
            GrowthPackInstallGuardrailFlag(id: "cloud-cdn-notification", title: "云端/CDN/通知", value: snapshot.publicSummary.callsCloud || snapshot.publicSummary.fetchesCdn || snapshot.publicSummary.sendsNotification)
            GrowthPackInstallGuardrailFlag(id: "ai-school", title: "AI/学校系统", value: snapshot.publicSummary.callsAi || snapshot.publicSummary.writesSchoolSystem)
        }
    }

    private func cloudSyncBridgeRole(
        for role: GrowthPackInstallViewerRole
    ) -> GrowthPackCloudSyncMobileBridgeViewerRole {
        switch role {
        case .child: return .child
        case .guardian: return .guardian
        case .relative: return .relative
        case .creator: return .creator
        }
    }

    private func preinstallTrialRole(
        for role: GrowthPackInstallViewerRole
    ) -> MobileGrowthPackPreinstallTrialRole {
        switch role {
        case .child, .relative: return .child
        case .guardian: return .guardian
        case .creator: return .creator
        }
    }

    private func refundDisputeRole(
        for role: GrowthPackInstallViewerRole
    ) -> MobileGrowthPackRefundDisputeRole {
        switch role {
        case .child, .relative: return .child
        case .guardian: return .guardian
        case .creator: return .creator
        }
    }

    private func color(for state: GrowthPackInstallDecisionState) -> Color {
        switch state {
        case .installable, .installed: return .green
        case .pendingGuardianConfirmation: return .orange
        case .frozen: return .blue
        case .blocked: return .red
        case .hidden: return .secondary
        }
    }

    private func icon(for state: GrowthPackInstallDecisionState) -> String {
        switch state {
        case .installable: return "square.and.arrow.down"
        case .installed: return "checkmark.seal"
        case .pendingGuardianConfirmation: return "person.badge.clock"
        case .frozen: return "pause.circle"
        case .blocked: return "xmark.octagon"
        case .hidden: return "eye.slash"
        }
    }

    private func color(for severity: GrowthPackInstallSeverity) -> Color {
        switch severity {
        case .ok: return .green
        case .info: return .blue
        case .warning: return .orange
        case .blocker: return .red
        }
    }

    private func icon(for severity: GrowthPackInstallSeverity) -> String {
        switch severity {
        case .ok: return "checkmark.seal"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .blocker: return "xmark.octagon"
        }
    }
}

private struct GrowthPackInstallGuardrailFlag: View {
    let id: String
    let title: String
    let value: Bool

    var body: some View {
        LabeledContent(title, value: value ? "会" : "不会")
            .accessibilityIdentifier("growth-pack-install-guardrail-\(id)")
    }
}
