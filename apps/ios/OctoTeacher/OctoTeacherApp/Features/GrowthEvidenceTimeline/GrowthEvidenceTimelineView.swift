import SwiftUI

/// 成长证据链申诉时间线的可复用展示组件。
///
/// - 孩子端（`GrowthEvidenceTimelineChildSection`）：按序看自己的证明链——每个节点的事件类型、
///   链状态、证明引用、下一步与脱敏文案；不展示裁决细节，未审核 / 阻断节点只显示「待处理」语义。
/// - 家长端（`GrowthEvidenceTimelineParentSection`）：按「冲突待裁 / 申诉中 / 撤销待传播 /
///   亲友待复核 / 已阻断」摘要，并附成长积分暂停 / 释放 / 阻断计数。
///
/// 只读脱敏展示：所有文本来自报告的脱敏字段，不含任何真实 ID；节点与成长积分账本中立，
/// 不写账本、不改作业终态、不发布时间线、不通知亲友、不保存原始媒体、不解锁设备。

// MARK: - 单节点行

struct GrowthEvidenceTimelineNodeRow: View {
    let node: GrowthEvidenceTimelineNode
    /// 孩子端隐藏裁决细节，只显示链状态与下一步。
    var childFacing: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: node.systemImage)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(node.sequence). \(node.title)")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(node.statusLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                }
                Text("\(node.kindLabel) · \(node.actorLabel) · \(node.hashPresent ? "链已校验" : "缺哈希")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(node.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if node.actionRequired {
                    Label("下一步：\(node.nextStep)", systemImage: "arrow.turn.down.right")
                        .font(.caption2)
                        .foregroundStyle(childFacing ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var tint: Color {
        switch node.status {
        case .accepted, .released, .restored: return .green
        case .reviewRequired, .frozen: return .orange
        case .conflict: return .pink
        case .blocked, .rejected, .revoked: return .secondary
        case .duplicate: return .secondary
        }
    }
}

// MARK: - 孩子端：自己的证明链

struct GrowthEvidenceTimelineChildSection: View {
    let report: GrowthEvidenceTimelineReport
    var maxRows: Int = 12
    var onRefresh: (() -> Void)? = nil

    var body: some View {
        Section {
            if let onRefresh {
                Button {
                    onRefresh()
                } label: {
                    Label(report.isEmpty ? "查看我的成长证据链" : "刷新我的成长证据链",
                          systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("growth-evidence-timeline-child-refresh")
            }

            if report.isEmpty {
                Text("暂无成长证据节点")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(report.childHeadline)
                    .font(.subheadline.weight(.semibold))
                ForEach(report.childChainNodes.prefix(maxRows)) { node in
                    GrowthEvidenceTimelineNodeRow(node: node, childFacing: true)
                }
                if report.childChainNodes.count > maxRows {
                    Text("另有 \(report.childChainNodes.count - maxRows) 个节点未展开")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(report.isEmpty ? "成长证据链" : report.caseTitle)
        } footer: {
            Text("仅本地证据链预览：缺哈希、链断裂、重复或跨孩子证明都会显示为待处理，不会自动发放成长积分；亲友鼓励要家长复核后才进时间线。")
        }
    }
}

// MARK: - 家长端：冲突 / 申诉 / 撤销 / 亲友待审核摘要

struct GrowthEvidenceTimelineParentSection: View {
    let report: GrowthEvidenceTimelineReport
    var maxRowsPerGroup: Int = 4
    var onRefresh: (() -> Void)? = nil

    var body: some View {
        Section {
            if let onRefresh {
                Button {
                    onRefresh()
                } label: {
                    Label(report.isEmpty ? "生成证据时间线摘要" : "刷新证据时间线摘要",
                          systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("growth-evidence-timeline-parent-refresh")
            }

            if report.isEmpty {
                Text("暂无成长证据节点")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(report.parentHeadline)
                    .font(.subheadline.weight(.semibold))

                creditSummary

                group("冲突待裁", systemImage: "exclamationmark.triangle", nodes: report.conflictNodes)
                group("申诉", systemImage: "gavel", nodes: report.appealNodes)
                group("撤销", systemImage: "arrow.uturn.backward.circle", nodes: report.revocationNodes)
                group("亲友待复核", systemImage: "person.crop.circle.badge.clock", nodes: report.relativePendingNodes)
                group("已阻断", systemImage: "nosign", nodes: report.blockedNodes)
            }
        } header: {
            Text("证据链申诉时间线摘要")
        } footer: {
            Text("家长端只读摘要：申诉不绕过家长 / 老师边界，亲友不能审批或发放成长积分；冲突、申诉中、撤销未传播、已阻断都不会自动结算为可用成长积分。")
        }
    }

    private var creditSummary: some View {
        let summary = report.publicSummary
        return Text("成长积分状态：暂停 \(summary.creditFrozenCount) · 可发放 \(summary.creditReleasedCount) · 阻断 \(summary.creditBlockedCount)")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func group(_ title: String, systemImage: String, nodes: [GrowthEvidenceTimelineNode]) -> some View {
        if !nodes.isEmpty {
            Label("\(title)（\(nodes.count)）", systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(nodes.prefix(maxRowsPerGroup)) { node in
                GrowthEvidenceTimelineNodeRow(node: node)
            }
            if nodes.count > maxRowsPerGroup {
                Text("另有 \(nodes.count - maxRowsPerGroup) 条未展开")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
