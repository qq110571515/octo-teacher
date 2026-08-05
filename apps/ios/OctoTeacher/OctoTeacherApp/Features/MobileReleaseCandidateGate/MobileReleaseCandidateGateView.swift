import SwiftUI

struct MobileReleaseCandidateGateView: View {
    @State private var viewerRole: MobileReleaseCandidateGateViewerRole
    private let builder = MobileReleaseCandidateGateBuilder()
    private let allowsRoleSwitching: Bool

    init(
        initialRole: MobileReleaseCandidateGateViewerRole = .guardian,
        allowsRoleSwitching: Bool = true
    ) {
        _viewerRole = State(initialValue: initialRole)
        self.allowsRoleSwitching = allowsRoleSwitching
    }

    private var snapshot: MobileReleaseCandidateGateSnapshot {
        builder.build(viewerRole: viewerRole)
    }

    var body: some View {
        List {
            headerSection(snapshot)
            checksSection(snapshot)
            nextActionsSection(snapshot)
            guardrailSection(snapshot)
        }
        .navigationTitle("发布质量门")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func headerSection(_ snapshot: MobileReleaseCandidateGateSnapshot) -> some View {
        Section {
            if allowsRoleSwitching {
                Picker("视角", selection: $viewerRole) {
                    ForEach(MobileReleaseCandidateGateViewerRole.allCases, id: \.self) { role in
                        Text(role.label).tag(role)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("release-gate-role-picker")
            } else {
                LabeledContent("视角", value: viewerRole.label)
                    .accessibilityIdentifier("release-gate-role-\(viewerRole.rawValue)")
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(snapshot.status.label)
                        .font(.title2.bold())
                        .accessibilityIdentifier("release-gate-status")
                    Spacer()
                    Text("\(snapshot.publicSummary.visibleCheckCount) 项")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("release-gate-visible-check-count")
                }
                Text(snapshot.headline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("release-gate-headline")
                HStack(spacing: 10) {
                    MobileReleaseMetricPill(
                        title: "阻断",
                        value: snapshot.publicSummary.blockerCount,
                        tint: snapshot.publicSummary.blockerCount > 0 ? .red : .green,
                        identifier: "release-gate-metric-blockers"
                    )
                    MobileReleaseMetricPill(
                        title: "复核",
                        value: snapshot.publicSummary.warningCount,
                        tint: snapshot.publicSummary.warningCount > 0 ? .orange : .green,
                        identifier: "release-gate-metric-warnings"
                    )
                    MobileReleaseMetricPill(
                        title: "待办",
                        value: snapshot.publicSummary.actionRequiredCount,
                        tint: snapshot.publicSummary.actionRequiredCount > 0 ? .orange : .blue,
                        identifier: "release-gate-metric-actions"
                    )
                }
            }
            .padding(.vertical, 2)
        } footer: {
            Text("这里只读检查本地 ReadModel 发布候选，不发布、不写入、不调用外部系统。")
        }
    }

    private func checksSection(_ snapshot: MobileReleaseCandidateGateSnapshot) -> some View {
        Section("质量门检查") {
            ForEach(snapshot.checks) { check in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon(for: check))
                        .foregroundStyle(color(for: check.severity))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(check.title)
                                .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 8)
                            Text(check.severity.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(color(for: check.severity))
                        }
                        Text(check.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
                .accessibilityIdentifier("release-gate-check-\(check.kind.rawValue)")
            }
        }
    }

    private func nextActionsSection(_ snapshot: MobileReleaseCandidateGateSnapshot) -> some View {
        Section("下一步") {
            if snapshot.nextActions.isEmpty {
                Text("暂无需要处理的候选门禁")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("release-gate-action-empty")
            } else {
                ForEach(Array(snapshot.nextActions.enumerated()), id: \.element.id) { index, action in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(action.title)
                            .font(.subheadline.weight(.semibold))
                        Text(action.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                    .accessibilityIdentifier("release-gate-action-\(action.severity.rawValue)-\(index)")
                }
            }
        }
    }

    private func guardrailSection(_ snapshot: MobileReleaseCandidateGateSnapshot) -> some View {
        Section("只读护栏") {
            LabeledContent("写成长积分账本", value: snapshot.publicSummary.writesLedger ? "会" : "不会")
                .accessibilityIdentifier("release-gate-boundary-ledger")
            LabeledContent("解锁设备", value: snapshot.publicSummary.unlocksDevice ? "会" : "不会")
                .accessibilityIdentifier("release-gate-boundary-device")
            LabeledContent("写学校 / LMS", value: (snapshot.publicSummary.writesSchoolSystem || snapshot.publicSummary.callsLms) ? "会" : "不会")
                .accessibilityIdentifier("release-gate-boundary-school-lms")
            LabeledContent("通知 / 上传", value: (snapshot.publicSummary.sendsNotification || snapshot.publicSummary.uploadsAttachment) ? "会" : "不会")
                .accessibilityIdentifier("release-gate-boundary-notification-upload")
            LabeledContent("AI / QWEN / 云端", value: (snapshot.publicSummary.callsAiProvider || snapshot.publicSummary.callsLocalModel || snapshot.publicSummary.callsCloud) ? "会" : "不会")
                .accessibilityIdentifier("release-gate-boundary-ai-cloud")
            LabeledContent("购买 / 权益", value: (snapshot.publicSummary.createsOrder || snapshot.publicSummary.writesEntitlement) ? "会" : "不会")
                .accessibilityIdentifier("release-gate-boundary-entitlement-order")
        }
    }

    private func icon(for check: MobileReleaseCandidateGateCheck) -> String {
        switch check.severity {
        case .ok: return "checkmark.seal"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .blocker: return "xmark.octagon"
        }
    }

    private func color(for severity: MobileReleaseCandidateGateSeverity) -> Color {
        switch severity {
        case .ok: return .green
        case .info: return .blue
        case .warning: return .orange
        case .blocker: return .red
        }
    }
}

private struct MobileReleaseMetricPill: View {
    let title: String
    let value: Int
    let tint: Color
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 66, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier(identifier)
    }
}
