import SwiftUI

/// 手机端「监护人与孩子同意策略入口」。
///
/// 本地只读投影 B49 同意策略契约：可切换角色（孩子/家长/亲友/老师/公开访客）与用途，
/// 查看同意状态、撤回传播、过期、可见性决策、审计摘要与关键阻断。
/// 不接网络、AI、学校系统、账本、通知或设备，也不做真实导出 / 删除 / 授权。
struct GuardianChildConsentPolicyView: View {
    let allowsRoleSwitching: Bool

    @State private var viewerRole: GuardianChildConsentPolicyViewerRole
    @State private var purpose: GuardianChildConsentPolicyPurpose = .familyStory

    private let builder = GuardianChildConsentPolicyBuilder()

    init(
        initialRole: GuardianChildConsentPolicyViewerRole = .guardian,
        allowsRoleSwitching: Bool = true
    ) {
        self.allowsRoleSwitching = allowsRoleSwitching
        _viewerRole = State(initialValue: initialRole)
    }

    /// 用一组确定性默认场景演示该角色 + 用途的同意投影。
    private var snapshot: GuardianChildConsentPolicySnapshot {
        builder.build(
            viewerRole: viewerRole,
            purpose: purpose,
            ageBand: purpose == .publicShare ? .age16To17 : .age13To15,
            exportRequested: purpose == .dataExportDelete,
            deleteRequested: false,
            revocationRequired: purpose == .dataExportDelete,
            revocationPropagated: true
        )
    }

    var body: some View {
        List {
            roleSection
            purposeSection
            headerSection
            consentSection
            decisionSection
            revocationSection
            auditSection
            findingsSection
            guardrailSection
        }
        .navigationTitle("同意策略")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var roleSection: some View {
        if allowsRoleSwitching {
            Section {
                Picker("视角", selection: $viewerRole) {
                    ForEach(GuardianChildConsentPolicyViewerRole.allCases, id: \.self) { role in
                        Text(role.label).tag(role)
                    }
                }
                .pickerStyle(.menu)
                Text(snapshot.audienceNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                Label(viewerRole.label, systemImage: "person.crop.circle")
                    .font(.subheadline)
                Text(snapshot.audienceNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var purposeSection: some View {
        Section("用途") {
            Picker("用途", selection: $purpose) {
                ForEach(GuardianChildConsentPolicyPurpose.allCases, id: \.self) { item in
                    Label(item.label, systemImage: item.systemImage).tag(item)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(snapshot.purpose.label, systemImage: snapshot.purpose.systemImage)
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    statusBadge(snapshot.state)
                }
                Text(snapshot.headline)
                    .font(.headline)
                Text(snapshot.childSafeCopy)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("年龄段：\(snapshot.ageBand.label)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
        }
    }

    private var consentSection: some View {
        Section("同意状态") {
            LabeledContent("家长同意", value: snapshot.guardianConsentDisplay)
            LabeledContent("孩子 assent", value: snapshot.childAssentDisplay)
            if !snapshot.visibility.canSeeInternalConsentState {
                Text("当前视角不展示家长和孩子的内部同意状态。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var decisionSection: some View {
        Section("可见性与权能") {
            BoundaryFlagRow(title: "家庭可见", value: snapshot.decision.familyVisible, positiveIsGood: true)
            BoundaryFlagRow(title: "亲友可见", value: snapshot.decision.relativeVisible, positiveIsGood: true)
            BoundaryFlagRow(title: "学校/老师可见", value: snapshot.decision.schoolVisible, positiveIsGood: true)
            BoundaryFlagRow(title: "公开可见", value: snapshot.decision.publicVisible, positiveIsGood: true)
            BoundaryFlagRow(title: "可导出", value: snapshot.decision.exportAllowed, positiveIsGood: true)
            BoundaryFlagRow(title: "可删除", value: snapshot.decision.deleteAllowed, positiveIsGood: true)
            LabeledContent("孩子可撤回", value: snapshot.decision.childCanWithdraw ? "可以" : "否")
            LabeledContent("需人工复核", value: snapshot.decision.requiresManualReview ? "是" : "否")
        }
    }

    private var revocationSection: some View {
        Section("撤回传播") {
            LabeledContent("需要撤回", value: snapshot.revocationPlan.revocationRequired ? "是" : "否")
            LabeledContent("已传播", value: snapshot.revocationPlan.revocationApplied ? "已完成" : "未完成")
            LabeledContent("待传播下游", value: "\(snapshot.revocationPlan.pendingTargetCount)")
            LabeledContent("执行真实删除", value: snapshot.revocationPlan.writesDeletion ? "会" : "不会")
        }
    }

    private var auditSection: some View {
        Section("审计摘要") {
            if snapshot.visibility.canSeeAuditDetail {
                LabeledContent("已链接事件", value: "\(snapshot.audit.linkedEventCount)")
                LabeledContent("缺失事件", value: "\(snapshot.audit.missingEventCount)")
                LabeledContent("写外部系统", value: snapshot.audit.writesExternalSystem ? "会" : "不会")
            } else {
                Text("审计明细仅家长可见。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var findingsSection: some View {
        Section("策略发现") {
            if snapshot.findings.isEmpty {
                Label("暂无发现", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.findings) { finding in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.code.label)
                                .font(.caption.bold())
                            Text(finding.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: icon(for: finding.severity))
                            .foregroundStyle(tint(for: finding.severity))
                    }
                }
            }
        }
    }

    private var guardrailSection: some View {
        Section("只读护栏") {
            LabeledContent("调用网络/AI", value: (snapshot.sideEffects.callsNetwork || snapshot.sideEffects.callsAi) ? "会" : "不会")
            LabeledContent("写库/账本", value: (snapshot.sideEffects.writesDatabase || snapshot.sideEffects.writesLedger) ? "会" : "不会")
            LabeledContent("发布/通知", value: (snapshot.sideEffects.publishesContent || snapshot.sideEffects.sendsNotification) ? "会" : "不会")
            LabeledContent("学校/社交平台", value: (snapshot.sideEffects.callsSchoolSystem || snapshot.sideEffects.callsSocialPlatform) ? "会" : "不会")
            LabeledContent("真实删除/授权/设备", value: (snapshot.sideEffects.writesDeletion || snapshot.sideEffects.writesPermissionGrant || snapshot.sideEffects.touchesDevice) ? "会" : "不会")
        }
    }

    private func statusBadge(_ state: GuardianChildConsentPolicyState) -> some View {
        Text(state.label)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint(for: state).opacity(0.15), in: Capsule())
            .foregroundStyle(tint(for: state))
    }

    private func tint(for state: GuardianChildConsentPolicyState) -> Color {
        switch state {
        case .allowed: return .green
        case .gated: return .orange
        case .blocked: return .red
        }
    }

    private func icon(for severity: GuardianChildConsentPolicySeverity) -> String {
        switch severity {
        case .ok: return "checkmark.circle"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .blocker: return "xmark.octagon"
        }
    }

    private func tint(for severity: GuardianChildConsentPolicySeverity) -> Color {
        switch severity {
        case .ok: return .green
        case .info: return .blue
        case .warning: return .orange
        case .blocker: return .red
        }
    }
}

private struct BoundaryFlagRow: View {
    let title: String
    let value: Bool
    let positiveIsGood: Bool

    var body: some View {
        LabeledContent(title) {
            Label(value ? "是" : "否", systemImage: value ? "checkmark.circle" : "minus.circle")
                .font(.caption.bold())
                .foregroundStyle(value ? (positiveIsGood ? .green : .red) : .secondary)
        }
    }
}
