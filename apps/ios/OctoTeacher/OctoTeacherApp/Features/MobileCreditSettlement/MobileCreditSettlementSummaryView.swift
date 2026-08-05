import SwiftUI

/// 成长积分结算建议的可复用展示组件。
///
/// 首页 / 奖励 / 家长端共用：把 `MobileCreditSettlementReport` 渲染成一段「结算建议」区：
/// 总览 + 按展示分组（待审核 / 冻结 / 可建议 / 退款回滚建议 / 已阻断）的建议行。
///
/// 只读脱敏展示：所有文本来自报告的脱敏字段，不含任何真实 ID；建议账本中立，
/// 不发成长积分、不解锁设备、不改作业终态、不发通知。

/// 单条结算建议行。
struct MobileCreditSettlementRow: View {
    let proposal: MobileCreditSettlementProposal

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: proposal.systemImage)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(proposal.kindLabel) · \(proposal.amountLabel)")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(proposal.statusLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                }
                Text("来源：\(proposal.sourceLabel) · \(proposal.scopeLabel)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(proposal.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private var tint: Color {
        switch proposal.displayGroup {
        case .proposable: return .green
        case .frozen: return .blue
        case .reviewRequired: return .orange
        case .refundSuggestion: return .purple
        case .blocked: return .secondary
        }
    }
}

/// 一段「结算建议」Section：总览 + 按分组过滤的建议行（+ 可选刷新按钮）。
struct MobileCreditSettlementSummarySection: View {
    let report: MobileCreditSettlementReport
    /// 只展示这些展示分组；nil 表示展示全部。
    var focus: Set<MobileCreditSettlementDisplayGroup>? = nil
    /// 单页最多展示的建议行数。
    var maxRows: Int = 5
    /// 可选的「重新生成」动作；提供时显示按钮。
    var onRefresh: (() -> Void)? = nil

    private var shownProposals: [MobileCreditSettlementProposal] {
        guard let focus else { return report.proposals }
        return report.proposals.filter { focus.contains($0.displayGroup) }
    }

    var body: some View {
        Section {
            if let onRefresh {
                Button {
                    onRefresh()
                } label: {
                    Label(report.isEmpty ? "生成结算建议" : "重新生成结算建议",
                          systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("credit-settlement-refresh")
            }

            if report.isEmpty {
                Text("暂无结算建议")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if shownProposals.isEmpty {
                Text("本页相关的结算建议暂时为空")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                if focus == nil {
                    Text(report.headline)
                        .font(.subheadline.weight(.semibold))
                }
                ForEach(shownProposals.prefix(maxRows)) { proposal in
                    MobileCreditSettlementRow(proposal: proposal)
                }
                if shownProposals.count > maxRows {
                    Text("另有 \(shownProposals.count - maxRows) 条建议未展开")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("成长积分结算建议")
        } footer: {
            Text("仅本地结算建议预览：可建议/冻结/待审核/已阻断/退款回滚都只是脱敏建议，不发成长积分、不扣成长积分、不解锁设备，最终由家长流程与真实账本决定。")
        }
    }
}
