import SwiftUI

/// 离线同步重放结果的可复用展示组件。
///
/// 各页面（首页 / 任务 / 学校作业 / 家长 / 奖励 / 家庭动态）共用这一组视图，
/// 把 `MobileOfflineReplayStore.report` 渲染成一段同步结果区：总览 + 分态结果行。
/// 可按类型过滤，只展示与本页相关的动作；可选地提供一个「本地重放」按钮。
///
/// 只读脱敏展示：所有文本来自 `MobileOfflineReplayReport` 的脱敏字段，不含任何真实 ID。

/// 单条重放结果行。
struct MobileOfflineReplayResultRow: View {
    let result: MobileOfflineReplayResult

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: result.systemImage)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(result.kindLabel) · \(result.actorLabel)")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(result.status.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                }
                Text(result.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(result.nextStep)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("offline-sync-review-result-\(result.status.rawValue)")
    }

    private var tint: Color {
        switch result.status {
        case .confirmed: return .green
        case .needsGuardianReview: return .blue
        case .conflict: return .orange
        case .rolledBack: return .secondary
        }
    }
}

/// 一段「同步结果」Section：总览 + 过滤后的结果行（+ 可选重放按钮）。
struct MobileOfflineReplaySummarySection: View {
    let report: MobileOfflineReplayReport
    /// 只展示这些类型的结果；nil 表示展示全部。
    var focus: Set<MobileOfflineMutationKind>? = nil
    /// 单页最多展示的结果行数。
    var maxRows: Int = 4
    /// 可选的角色裁剪结果；用于离线复核台避免孩子端看到冲突/回滚明细。
    var visibleResults: [MobileOfflineReplayResult]? = nil
    /// 可选的安全总览文案；用于角色裁剪后避免 headline 泄露隐藏态数量。
    var headlineOverride: String? = nil
    /// 可选的「本地重放」动作；提供时显示按钮。
    var onReplay: (() -> Void)? = nil

    private var shownResults: [MobileOfflineReplayResult] {
        if let visibleResults {
            guard let focus else { return visibleResults }
            return visibleResults.filter { focus.contains($0.kind) }
        }
        if let focus {
            return report.results(for: focus)
        }
        return report.results
    }

    var body: some View {
        Section {
            if let onReplay {
                Button {
                    onReplay()
                } label: {
                    Label(report.isEmpty ? "模拟本地同步重放" : "重新模拟同步重放",
                          systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("offline-sync-review-replay-button")
            }

            if report.isEmpty {
                Text("还没有可重放的离线动作")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if shownResults.isEmpty {
                Text("本页相关动作暂无同步结果")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                if focus == nil {
                    Text(headlineOverride ?? report.headline)
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("offline-sync-review-replay-headline")
                }
                ForEach(shownResults.prefix(maxRows)) { result in
                    MobileOfflineReplayResultRow(result: result)
                }
                if shownResults.count > maxRows {
                    Text("另有 \(shownResults.count - maxRows) 条结果未展开")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("同步重放结果")
        } footer: {
            Text("本地重放预览：已确认仅代表已收到，仍需家长/老师或服务端流程落定，不发成长积分、不解锁设备。")
        }
    }
}
