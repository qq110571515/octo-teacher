import SwiftUI

/// 离线同步本地复核台（只读）。
///
/// 从首页「同步复核台」快捷入口进入：复用 `MobileOfflineOutboxStore.publicStatus` /
/// `conflictHints` 与 `MobileOfflineReplayStore.report`，按视角脱敏展示同步状态、
/// 下一步与（仅家长）冲突/回滚摘要。可手动触发一次本地确定性重放，但**绝不把结果落定**：
///
/// - 完全本地只读：不接真实网络、云 API、数据库、队列、登录、支付、AI、LMS、学校系统、
///   通知、账本、FamilyControls、HealthKit 或真实设备控制。
/// - 本地重放的 `confirmed` 只代表「mock 已收到」，复核台不写账本、不发成长积分、不扣成长积分、
///   不解锁设备、不改 entitlement、不应用回滚。
/// - 孩子只看安全状态与下一步；冲突原因明细与回滚摘要仅家长可见。
struct MobileOfflineSyncReviewView: View {
    let perspective: MobileHomePerspective

    @Environment(MobileOfflineOutboxStore.self) private var offlineOutbox
    @Environment(MobileOfflineReplayStore.self) private var offlineReplay

    private var presenter: MobileOfflineSyncReviewPresenter {
        MobileOfflineSyncReviewPresenter(
            perspective: perspective,
            status: offlineOutbox.publicStatus,
            conflictHints: offlineOutbox.conflictHints,
            report: offlineReplay.report
        )
    }

    var body: some View {
        let review = presenter
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(review.headline)
                        .font(.headline)
                        .accessibilityIdentifier("offline-sync-review-headline")
                    HStack(spacing: 12) {
                        ForEach(review.statusCounts) { count in
                            VStack(spacing: 2) {
                                Text("\(count.value)")
                                    .font(.title3.bold())
                                    .monospacedDigit()
                                Text(count.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(minWidth: 56)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityIdentifier("offline-sync-review-count-\(countIdentifier(for: count))")
                        }
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text("同步状态")
            } footer: {
                Text(review.footnote)
            }

            // 手动本地重放：确定性，不落定任何业务状态。
            MobileOfflineReplaySummarySection(
                report: offlineReplay.report,
                visibleResults: review.visibleResults,
                headlineOverride: perspective == .child ? review.headline : nil
            ) {
                offlineReplay.replay(outbox: offlineOutbox)
            }

            // 重放结果（按视角裁剪：孩子只看安全态）。
            Section {
                if review.visibleResults.isEmpty {
                    Text(offlineReplay.report.isEmpty ? "还没有可重放的离线动作" : "暂无可显示的同步结果")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(review.visibleResults) { result in
                        MobileOfflineReplayResultRow(result: result)
                    }
                }
            } header: {
                Text(perspective == .child ? "同步进度" : "逐条同步结果")
            } footer: {
                Text(perspective == .child
                     ? "已确认只代表已收到，仍要等家长或老师处理后才算完成。"
                     : "已确认仅代表已收到，仍需专属流程落定；本页不发成长积分、不解锁设备。")
            }

            // 冲突/回滚摘要：仅家长可见。
            if review.showsConflictDetails {
                Section {
                    if review.visibleConflictHints.isEmpty {
                        Text("暂无冲突或回滚")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(review.visibleConflictHints) { hint in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Image(systemName: hint.rolledBack ? "arrow.uturn.backward.circle" : "exclamationmark.triangle")
                                        .foregroundStyle(hint.rolledBack ? Color.secondary : Color.orange)
                                    Text("\(hint.kindLabel) · \(hint.actorLabel)")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer(minLength: 8)
                                    Text(hint.rolledBack ? "已回滚" : "有冲突")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(hint.rolledBack ? Color.secondary : Color.orange)
                                }
                                Text(hint.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(hint.nextStep)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 2)
                            .accessibilityIdentifier("offline-sync-review-conflict-\(hint.rolledBack ? "rolledBack" : "conflict")")
                        }
                    }
                } header: {
                    Text("冲突与回滚摘要")
                } footer: {
                    Text("回滚只是本地撤销提示；真实重处理仍需到专属流程，复核台不应用回滚、不写账本。")
                }
            }
        }
        .navigationTitle("离线同步复核台")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func countIdentifier(for count: MobileOfflineSyncReviewPresenter.Count) -> String {
        switch count.label {
        case "待同步": return "pending"
        case "冲突": return "conflict"
        case "已回滚": return "rolledBack"
        default: return count.label
        }
    }
}
