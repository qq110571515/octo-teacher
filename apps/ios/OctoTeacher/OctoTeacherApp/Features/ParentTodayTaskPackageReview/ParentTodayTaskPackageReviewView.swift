import SwiftUI

/// 家长端今日任务包复核台。
///
/// 本页只读展示任务包进度、证明摘要、成长积分和离线同步提示；真正批准/驳回仍在
/// ParentMode 的「待批准任务」区完成，避免总览页绕过既有安全闭环。
struct ParentTodayTaskPackageReviewView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(MobileOfflineOutboxStore.self) private var offlineOutbox

    private let builder = MobileParentTodayTaskPackageReviewBuilder()

    private var review: MobileParentTodayTaskPackageReview {
        builder.build(
            viewerRole: .guardian,
            store: store,
            offlineStatus: offlineOutbox.publicStatus
        )
    }

    var body: some View {
        List {
            headerSection(review)
            summarySection(review)
            taskSection(review)
            findingSection(review)
            guardrailSection(review)
        }
        .navigationTitle("今日任务包复核")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func headerSection(_ review: MobileParentTodayTaskPackageReview) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(review.title)
                        .font(.title3.bold())
                    Spacer()
                    Text("\(review.counts.needsAttention) 项待看")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(review.counts.needsAttention > 0 ? .orange : .secondary)
                }
                if !review.summary.isEmpty {
                    Text(review.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } footer: {
            Text("本页只读总览；批准、驳回和成长积分结算仍在原有待批准任务区完成。")
        }
    }

    private func summarySection(_ review: MobileParentTodayTaskPackageReview) -> some View {
        Section("复核摘要") {
            LabeledContent("待确认", value: "\(review.counts.waitingCheck)")
            LabeledContent("可开始", value: "\(review.counts.readyToStart)")
            LabeledContent("已完成", value: "\(review.counts.done)")
            LabeledContent("再试一次", value: "\(review.counts.redo)")
            LabeledContent("可用成长积分", value: "\(review.credit.availableMinutes) 积分")
            LabeledContent("等待确认", value: "\(review.credit.pendingMinutes) 积分")
            if review.offlineHint.hasPending {
                Label(review.offlineHint.title, systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(review.offlineHint.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func taskSection(_ review: MobileParentTodayTaskPackageReview) -> some View {
        Section("任务包步骤") {
            if review.items.isEmpty {
                Text("今天还没有可复核任务")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(review.items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Label("\(item.order). \(item.title)", systemImage: item.state.systemImage)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(tint(for: item.state))
                            Spacer()
                            Text(item.state.label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(tint(for: item.state))
                        }
                        HStack(spacing: 10) {
                            Label(item.proofSummary, systemImage: item.proofRequirement.systemImage)
                            Label(item.rewardLabel, systemImage: "seal")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Text(item.nextAction)
                            .font(.caption)
                            .foregroundStyle(item.actionRequired ? .primary : .secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func findingSection(_ review: MobileParentTodayTaskPackageReview) -> some View {
        Section("安全提示") {
            ForEach(review.findings) { finding in
                Label(finding.message, systemImage: icon(for: finding.severity))
                    .font(.caption)
                    .foregroundStyle(color(for: finding.severity))
            }
        }
    }

    private func guardrailSection(_ review: MobileParentTodayTaskPackageReview) -> some View {
        Section("边界") {
            Label(review.publicSummary.approvesTask ? "可直接批准" : "不直接批准", systemImage: "hand.raised")
            Label(review.publicSummary.writesLedger ? "会写账本" : "不写账本", systemImage: "list.bullet.rectangle")
            Label(review.publicSummary.unlocksDevice ? "会解锁设备" : "不解锁设备", systemImage: "lock")
            Label(review.publicSummary.sendsNotification ? "会发通知" : "不发通知", systemImage: "bell.slash")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func tint(for state: MobileTodayTaskCardState) -> Color {
        switch state {
        case .locked: return .secondary
        case .active: return .blue
        case .waitingCheck: return .orange
        case .done: return .green
        case .redo: return .red
        }
    }

    private func icon(for severity: MobileParentTodayTaskReviewSeverity) -> String {
        switch severity {
        case .ok: return "checkmark.seal"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .blocker: return "xmark.octagon"
        }
    }

    private func color(for severity: MobileParentTodayTaskReviewSeverity) -> Color {
        switch severity {
        case .ok: return .green
        case .info: return .secondary
        case .warning: return .orange
        case .blocker: return .red
        }
    }
}
