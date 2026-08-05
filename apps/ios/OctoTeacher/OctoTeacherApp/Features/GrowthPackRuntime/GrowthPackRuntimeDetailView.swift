import SwiftUI

/// 成长包运行详情与结算预览的可复用展示组件。
///
/// - 孩子端（`GrowthPackRuntimeChildSection`）：逐步骤看活动类型、阶段、证明要求与状态、
///   下一步与脱敏结算预览。
/// - 家长端（`GrowthPackRuntimeParentSection`）：按「待审核 / 可建议 / 已阻断 / 申诉中」摘要。
///
/// 只读脱敏展示：所有文本来自报告的脱敏字段，不含任何真实 ID；投影与结算预览账本中立，
/// 不发成长积分、不授徽章、不改任务/作业终态、不发动态/通知、不解锁设备。

// MARK: - 单步骤行

struct GrowthPackRuntimeStepRow: View {
    let step: GrowthRuntimeStepProjection

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: step.systemImage)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(step.order). \(step.title)")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(step.statusLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                }
                Text("\(step.kindLabel) · \(step.stageLabel)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("证明：\(step.proofStatus.label) · \(step.proofRequirementLabel)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(step.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if step.status == .creditSuggested {
                    Text("结算预览：可建议 \(step.settlement.suggestedCreditLabel) · 徽章建议 \(step.settlement.badgeSuggestionCount) · 能力建议 \(step.settlement.abilitySuggestionCount)（均待家长审核）")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Label("下一步：\(step.nextStep)", systemImage: "arrow.turn.down.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private var tint: Color {
        if step.isAppealing { return .pink }
        switch step.status {
        case .creditSuggested: return .green
        case .reviewRequired: return .orange
        case .blocked: return .secondary
        case .alreadyCredited: return .blue
        case .planned: return .secondary
        case .duplicate, .voided: return .secondary
        }
    }
}

// MARK: - 孩子端：成长包运行详情

struct GrowthPackRuntimeChildSection: View {
    let report: GrowthRuntimeSettlementReport
    var maxRows: Int = 12
    var onRefresh: (() -> Void)? = nil

    var body: some View {
        Section {
            if let onRefresh {
                Button {
                    onRefresh()
                } label: {
                    Label(report.isEmpty ? "查看成长包运行详情" : "刷新成长包运行详情",
                          systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("growth-pack-runtime-child-refresh")
            }

            if report.isEmpty {
                Text("暂无成长包步骤")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(report.childHeadline)
                    .font(.subheadline.weight(.semibold))
                ForEach(report.steps.prefix(maxRows)) { step in
                    GrowthPackRuntimeStepRow(step: step)
                }
                if report.steps.count > maxRows {
                    Text("另有 \(report.steps.count - maxRows) 步未展开")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(report.isEmpty ? "成长包运行详情" : report.packTitle)
        } footer: {
            Text("仅本地运行详情预览：可建议结算只是脱敏预览，不发成长积分、不授徽章、不改任务终态；未审核证明、失败测验、老师退回、申诉中、年龄不适配内容都不会展示为已完成可用成长积分。")
        }
    }
}

// MARK: - 家长端：待审核 / 可建议 / 已阻断 / 申诉中摘要

struct GrowthPackRuntimeParentSection: View {
    let report: GrowthRuntimeSettlementReport
    var maxRowsPerGroup: Int = 4
    var onRefresh: (() -> Void)? = nil

    private let order: [GrowthRuntimeParentGroup] = [.reviewRequired, .proposable, .appealing, .blocked]

    var body: some View {
        Section {
            if let onRefresh {
                Button {
                    onRefresh()
                } label: {
                    Label(report.isEmpty ? "生成成长包结算摘要" : "刷新成长包结算摘要",
                          systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("growth-pack-runtime-parent-refresh")
            }

            if report.isEmpty {
                Text("暂无成长包步骤")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(report.parentHeadline)
                    .font(.subheadline.weight(.semibold))
                ForEach(order, id: \.self) { group in
                    let steps = report.steps(in: group)
                    if !steps.isEmpty {
                        Label("\(group.label)（\(steps.count)）", systemImage: group.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(steps.prefix(maxRowsPerGroup)) { step in
                            GrowthPackRuntimeStepRow(step: step)
                        }
                        if steps.count > maxRowsPerGroup {
                            Text("另有 \(steps.count - maxRowsPerGroup) 条未展开")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("成长包运行结算摘要")
        } footer: {
            Text("家长端只读摘要：可建议表示通过验证可交审核，批准前不发任何成长积分、不授徽章、不解锁设备；待审核/申诉中/已阻断都不会自动结算为可用成长积分。")
        }
    }
}
