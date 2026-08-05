import SwiftUI

/// 成长积分账本复核台视图。
///
/// 家长视角：展示余额快照、按分组（可建议/待审核/冻结/冲突/退款回滚/已阻断）逐条复核，
/// 含原因、金额与只读来源标签。非家长视角：仅展示安全状态文案，看不到金额、原因与来源。
/// 全程只读：不发成长积分、不解锁设备、不写账本、不发通知。

/// 单条复核项行（角色门控由数据层完成，视图按字段是否存在渲染）。
struct CreditLedgerReviewRow: View {
    let item: CreditLedgerReviewItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.section.systemImage)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(headlineText)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(item.statusLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                }
                if let reason = item.reason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(item.childSafeStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !item.originTags.isEmpty {
                    Text(item.originTags.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("credit-ledger-review-row-\(item.section.rawValue)")
    }

    /// 家长可见金额；非家长仅显示分组标签。
    private var headlineText: String {
        if let amountLabel = item.amountLabel {
            return "\(item.kindLabel) · \(amountLabel)"
        }
        return item.section.label
    }

    private var tint: Color {
        switch item.section {
        case .proposable: return .green
        case .frozen: return .blue
        case .reviewRequired: return .orange
        case .conflict: return .red
        case .refundOrRollback: return .purple
        case .blockedOrIgnored: return .secondary
        }
    }
}

/// 复核台正文（接受已构建好的 console，便于测试与预览）。
struct CreditLedgerReviewContent: View {
    let console: CreditLedgerReviewConsole
    var onRefresh: (() -> Void)? = nil

    var body: some View {
        List {
            overviewSection
            if console.viewerRole.canReviewInternals, let balance = console.balance {
                balanceSection(balance)
            }
            if console.isEmpty {
                Section {
                    Text(emptyText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(console.sections) { group in
                    sectionView(group)
                }
            }
            findingsSection
        }
    }

    private var overviewSection: some View {
        Section {
            if let onRefresh {
                Button {
                    onRefresh()
                } label: {
                    Label("重新生成复核视图", systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("credit-ledger-review-refresh")
            }
            HStack {
                Text(console.headline)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(console.status.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("credit-ledger-review-status")
        } header: {
            Text("成长积分账本复核台")
        } footer: {
            Text("仅本地只读复核：所有分组都只是脱敏建议，不发放成长积分、不扣成长积分、不解锁设备，最终由家长流程与真实账本决定。")
        }
    }

    private func balanceSection(_ balance: CreditLedgerBalanceSnapshot) -> some View {
        Section("成长积分余额快照（只读）") {
            LabeledContent("可用成长积分", value: balance.availableLabel)
                .accessibilityIdentifier("credit-ledger-review-balance-available")
            LabeledContent("冻结中", value: balance.frozenLabel)
                .accessibilityIdentifier("credit-ledger-review-balance-frozen")
            LabeledContent("待审核", value: balance.pendingLabel)
                .accessibilityIdentifier("credit-ledger-review-balance-pending")
            LabeledContent("累计获得", value: balance.lifetimeEarnedLabel)
                .accessibilityIdentifier("credit-ledger-review-balance-lifetime")
        }
    }

    private func sectionView(_ group: CreditLedgerReviewSectionGroup) -> some View {
        Section {
            ForEach(group.items) { item in
                CreditLedgerReviewRow(item: item)
            }
        } header: {
            Label("\(group.label)（\(group.count)）", systemImage: group.systemImage)
        }
    }

    private var findingsSection: some View {
        Section("复核说明") {
            ForEach(console.findings) { finding in
                Label(finding.message, systemImage: icon(for: finding.severity))
                    .font(.caption)
                    .foregroundStyle(color(for: finding.severity))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("credit-ledger-review-finding-\(finding.code.rawValue)")
            }
        }
    }

    private var emptyText: String {
        console.viewerRole.canReviewInternals ? "暂无成长积分复核项。" : "现在没有需要关注的内容。"
    }

    private func icon(for severity: CreditLedgerReviewSeverity) -> String {
        switch severity {
        case .ok: return "checkmark.seal"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .blocker: return "nosign"
        }
    }

    private func color(for severity: CreditLedgerReviewSeverity) -> Color {
        switch severity {
        case .ok: return .green
        case .info: return .secondary
        case .warning: return .orange
        case .blocker: return .red
        }
    }
}

/// 复核台屏幕：从环境 store 取结算报告与本地余额，按角色构建只读复核台。
struct CreditLedgerReviewView: View {
    var viewerRole: CreditLedgerReviewViewerRole = .guardian

    @Environment(LocalFamilyStore.self) private var family
    @Environment(SchoolFamilyStore.self) private var schoolFamily
    @Environment(MockScreenTimeController.self) private var screenTime
    @Environment(MobileOfflineOutboxStore.self) private var offlineOutbox
    @Environment(MobileOfflineReplayStore.self) private var offlineReplay
    @Environment(MobileCreditSettlementStore.self) private var creditSettlement

    @State private var console: CreditLedgerReviewConsole?

    private let builder = CreditLedgerReviewBuilder()

    var body: some View {
        Group {
            if let console {
                CreditLedgerReviewContent(console: console) {
                    rebuild(refreshSettlement: true)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("成长积分账本复核台")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if console == nil { rebuild(refreshSettlement: creditSettlement.report.isEmpty) }
        }
    }

    private func rebuild(refreshSettlement: Bool) {
        if refreshSettlement {
            offlineReplay.replay(outbox: offlineOutbox)
            creditSettlement.refresh(
                offlineReport: offlineReplay.report,
                family: family,
                schoolFamily: schoolFamily,
                screenTime: screenTime
            )
        }
        console = builder.build(
            viewerRole: viewerRole,
            report: creditSettlement.report,
            balance: balanceSnapshot()
        )
    }

    /// 把本地家庭成长积分余额映射成只读余额快照。冻结分钟取当前结算报告里的冻结建议合计（仅展示）。
    private func balanceSnapshot() -> CreditLedgerBalanceSnapshot {
        let balance = family.creditBalance
        let frozen = creditSettlement.report.proposals(in: .frozen).reduce(0) { $0 + $1.amount }
        return CreditLedgerBalanceSnapshot(
            availableMinutes: balance.availableMinutes,
            frozenMinutes: frozen,
            pendingMinutes: balance.pendingMinutes,
            lifetimeEarnedMinutes: balance.lifetimeEarnedMinutes,
            asOf: console?.generatedAt ?? ""
        )
    }
}
