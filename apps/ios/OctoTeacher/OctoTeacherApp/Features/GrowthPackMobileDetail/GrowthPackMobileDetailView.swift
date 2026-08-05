import SwiftUI

/// 成长包移动详情快照页。
///
/// 这是手机端「成长包模块」的可组合消费面：孩子看步骤与提交证明，家长看审核/成长积分预览/申诉/离线风险，
/// 亲友只能只读看已裁剪摘要。所有内容来自本地 snapshot，不做真实写入。
struct GrowthPackMobileDetailView: View {
    @Environment(LocalFamilyStore.self) private var family
    @Environment(SchoolFamilyStore.self) private var schoolFamily
    @Environment(MobileOfflineOutboxStore.self) private var offlineOutbox
    @Environment(MobileOfflineReplayStore.self) private var offlineReplay
    @Environment(GrowthPackRuntimeStore.self) private var growthRuntime
    @Environment(GrowthEvidenceTimelineStore.self) private var evidenceTimeline
    @State private var viewerRole: GrowthPackMobileDetailViewerRole
    private let allowedRoles: [GrowthPackMobileDetailViewerRole]

    init(
        initialRole: GrowthPackMobileDetailViewerRole = .child,
        allowedRoles: [GrowthPackMobileDetailViewerRole] = GrowthPackMobileDetailViewerRole.allCases
    ) {
        let safeRoles = allowedRoles.isEmpty ? [initialRole] : allowedRoles
        let safeInitialRole = safeRoles.contains(initialRole) ? initialRole : safeRoles[0]
        _viewerRole = State(initialValue: safeInitialRole)
        self.allowedRoles = safeRoles
    }

    private var builder: GrowthPackMobileDetailSnapshotBuilder {
        GrowthPackMobileDetailSnapshotBuilder()
    }

    private var snapshot: GrowthPackMobileDetailSnapshot {
        builder.build(
            viewerRole: viewerRole,
            runtimeReport: growthRuntime.report,
            evidenceReport: evidenceTimeline.report,
            offlineStatus: offlineOutbox.publicStatus,
            offlineReport: offlineReplay.report
        )
    }

    var body: some View {
        List {
            headerSection(snapshot)
            contentPlayerSection
            nextActionsSection(snapshot)
            stepsSection(snapshot)
            proofSection(snapshot)
            rewardSection(snapshot)
            evidenceSection(snapshot)
            offlineSection(snapshot)
            findingsSection(snapshot)
        }
        .navigationTitle("成长包详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            refreshSnapshotInputs()
        }
    }

    @ViewBuilder
    private var contentPlayerSection: some View {
        Section("学习内容播放器") {
            switch viewerRole {
            case .child:
                NavigationLink {
                    GrowthPackContentPlayerWorkbenchView(initialRole: .child, allowedRoles: [.child])
                } label: {
                    Label("打开内容播放器", systemImage: "play.rectangle")
                }
                .accessibilityIdentifier("growth-pack-detail-content-player-child")
            case .guardian:
                NavigationLink {
                    GrowthPackContentPlayerWorkbenchView(initialRole: .guardian, allowedRoles: [.guardian])
                } label: {
                    Label("打开内容与证明安全壳", systemImage: "rectangle.stack.badge.play")
                }
                .accessibilityIdentifier("growth-pack-detail-content-player-guardian")
            case .teacher, .relative:
                Label("当前视角不可进入内容播放器", systemImage: "lock")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("growth-pack-detail-content-player-locked")
            }
            Text("只读查看文本、图片观察、视频引用、测验练习和截图证明要求；不打开外链、不上传、不判分、不发成长积分。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func refreshSnapshotInputs() {
        growthRuntime.refresh(family: family, schoolFamily: schoolFamily)
        let runtime = GrowthEvidenceTimelineRuntimeContext(report: growthRuntime.report)
        evidenceTimeline.refresh(family: family, schoolFamily: schoolFamily, runtime: runtime)
        if !offlineReplay.hasReplayed {
            offlineReplay.replay(outbox: offlineOutbox)
        }
    }

    private func headerSection(_ snapshot: GrowthPackMobileDetailSnapshot) -> some View {
        Section {
            if allowedRoles.count > 1 {
                Picker("视角", selection: $viewerRole) {
                    ForEach(allowedRoles, id: \.self) { role in
                        Text(role.label).tag(role)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("growth-pack-detail-role-picker")
            } else {
                LabeledContent("视角", value: viewerRole.label)
                    .accessibilityIdentifier("growth-pack-detail-role-\(viewerRole.rawValue)")
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(snapshot.header.status.label)
                        .font(.title3.bold())
                        .accessibilityIdentifier("growth-pack-detail-status")
                    Spacer()
                    Text(snapshot.header.manifestVersion)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("growth-pack-detail-manifest-version")
                }
                Text("步骤 \(snapshot.publicSummary.stepCount) · 证明 \(snapshot.publicSummary.proofRequirementCount) · 下一步 \(snapshot.publicSummary.nextActionCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("growth-pack-detail-summary-steps")
                Text("成长积分预览 \(snapshot.publicSummary.creditPreviewCount) · 可建议 \(snapshot.publicSummary.availableCreditPreviewCount) · 申诉 \(snapshot.publicSummary.appealCount) · 离线提示 \(snapshot.publicSummary.offlineHintCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("growth-pack-detail-summary-credit")
            }
            .padding(.vertical, 2)

            RoleVisibilityGrid(visibility: snapshot.roleVisibility)
        } footer: {
            Text("该详情页只读消费本地快照；成长积分预览只是审核前建议，不发成长积分、不授徽章、不改作业、不通知、不上传媒体、不解锁设备。")
        }
    }

    private func nextActionsSection(_ snapshot: GrowthPackMobileDetailSnapshot) -> some View {
        Section("下一步") {
            ForEach(snapshot.nextActions) { action in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon(for: action.kind))
                        .foregroundStyle(color(for: action.severity))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(action.title)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(action.kind.label) · \(action.actionRequired ? "需要处理" : "只读提示")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
                .accessibilityIdentifier("growth-pack-detail-action-\(action.kind.rawValue)")
            }
        }
    }

    private func stepsSection(_ snapshot: GrowthPackMobileDetailSnapshot) -> some View {
        Section("成长包步骤") {
            if snapshot.steps.isEmpty {
                Text("暂无可见步骤")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("growth-pack-detail-steps-empty")
            } else {
                ForEach(Array(snapshot.steps.prefix(10).enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: step.systemImage)
                            .foregroundStyle(color(for: step.status))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("\(step.order). \(step.title)")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(step.status.label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(color(for: step.status))
                            }
                            Text(step.kindLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(step.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("下一步：\(step.nextStep)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityIdentifier("growth-pack-detail-step-\(index)")
                }
                if snapshot.steps.count > 10 {
                    Text("另有 \(snapshot.steps.count - 10) 步未展开")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func proofSection(_ snapshot: GrowthPackMobileDetailSnapshot) -> some View {
        Section("证明要求") {
            if snapshot.proofRequirements.isEmpty {
                Text(snapshot.roleVisibility.canSeeProofRequirements ? "暂无证明要求" : "该视角不可查看证明要求")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("growth-pack-detail-proof-empty")
            } else {
                ForEach(Array(snapshot.proofRequirements.prefix(6).enumerated()), id: \.element.id) { index, item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.kindLabel)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("验证角色：\(item.verifierRoles.map(\.label).joined(separator: " / "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.evidenceRefsOnly ? "只接收脱敏证据引用" : "需要补充证据")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .accessibilityIdentifier("growth-pack-detail-proof-\(index)")
                }
            }
        }
    }

    private func rewardSection(_ snapshot: GrowthPackMobileDetailSnapshot) -> some View {
        Section {
            let summary = snapshot.rewardSummary
            LabeledContent("可见成长积分预览", value: "\(summary.creditPreviewCount)")
                .accessibilityIdentifier("growth-pack-detail-reward-credit-preview-count")
            LabeledContent("可建议成长积分", value: "\(summary.totalAvailablePreviewCredit) 积分")
                .accessibilityIdentifier("growth-pack-detail-reward-available-credit")
            LabeledContent("冻结 / 阻断", value: "\(summary.frozenCreditPreviewCount) / \(summary.blockedCreditPreviewCount)")
                .accessibilityIdentifier("growth-pack-detail-reward-frozen-blocked")
            LabeledContent("徽章 / 能力建议", value: "\(summary.badgeSuggestionCount) / \(summary.abilitySuggestionCount)")
                .accessibilityIdentifier("growth-pack-detail-reward-badge-ability")

            ForEach(Array(snapshot.creditPreviews.prefix(4).enumerated()), id: \.element.id) { index, preview in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(preview.state.label) · \(preview.creditLabel)")
                        .font(.subheadline.weight(.semibold))
                    Text(preview.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
                .accessibilityIdentifier("growth-pack-detail-credit-preview-\(index)")
            }
        } header: {
            Text("奖励预览")
        } footer: {
            Text(snapshot.roleVisibility.canSeeSettlementPreview ? "家长视角可看结算建议，但仍不落账。" : "该视角不会暴露成长积分预览数组和结算计数。")
        }
    }

    private func evidenceSection(_ snapshot: GrowthPackMobileDetailSnapshot) -> some View {
        Section("证据与申诉") {
            let summary = snapshot.evidenceAppealSummary
            LabeledContent("链节点 / 公开线", value: "\(summary.chainEventCount) / \(summary.publicTimelineCount)")
                .accessibilityIdentifier("growth-pack-detail-evidence-chain")
            LabeledContent("申诉 / 冲突", value: "\(summary.appealCount) / \(summary.conflictCount)")
                .accessibilityIdentifier("growth-pack-detail-evidence-appeal-conflict")
            LabeledContent("冻结 / 释放 / 阻断", value: "\(summary.creditFrozenCount) / \(summary.creditReleasedCount) / \(summary.creditBlockedCount)")
                .accessibilityIdentifier("growth-pack-detail-evidence-credit-state")
            if summary.relativeReviewCount > 0 {
                LabeledContent("亲友待复核", value: "\(summary.relativeReviewCount)")
                    .accessibilityIdentifier("growth-pack-detail-evidence-relative-review")
            }

            ForEach(Array(summary.visibleTimeline.prefix(4).enumerated()), id: \.element.id) { index, item in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(item.kindLabel) · \(item.statusLabel)")
                        .font(.subheadline.weight(.semibold))
                    Text(item.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
                .accessibilityIdentifier("growth-pack-detail-evidence-timeline-\(index)")
            }
        }
    }

    private func offlineSection(_ snapshot: GrowthPackMobileDetailSnapshot) -> some View {
        Section("离线同步") {
            if snapshot.offlineHints.isEmpty {
                Text("暂无可见离线提示")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("growth-pack-detail-offline-empty")
            } else {
                ForEach(Array(snapshot.offlineHints.enumerated()), id: \.element.id) { index, hint in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: hint.kind == .conflict ? "exclamationmark.triangle" : "arrow.triangle.2.circlepath")
                            .foregroundStyle(color(for: hint.severity))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(hint.title)
                                .font(.subheadline.weight(.semibold))
                            Text(hint.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(hint.actionRequired ? "需要处理" : "等待同步")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityIdentifier("growth-pack-detail-offline-\(index)")
                }
            }
        }
    }

    private func findingsSection(_ snapshot: GrowthPackMobileDetailSnapshot) -> some View {
        Section("安全发现项") {
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
                .accessibilityIdentifier("growth-pack-detail-finding-\(finding.code.rawValue)")
            }
        }
    }

    private func icon(for kind: GrowthPackMobileDetailNextAction.Kind) -> String {
        switch kind {
        case .submitProof: return "square.and.arrow.up"
        case .guardianReview: return "person.badge.clock"
        case .teacherReview: return "book.closed"
        case .appealReview: return "exclamationmark.bubble"
        case .offlineSync: return "arrow.triangle.2.circlepath"
        case .readOnly: return "eye"
        }
    }

    private func icon(for severity: GrowthPackMobileDetailSeverity) -> String {
        switch severity {
        case .ok: return "checkmark.seal"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.circle"
        case .blocker: return "xmark.octagon"
        }
    }

    private func color(for severity: GrowthPackMobileDetailNextAction.Severity) -> Color {
        switch severity {
        case .info: return .blue
        case .warning: return .orange
        case .urgent: return .red
        }
    }

    private func color(for severity: GrowthPackMobileDetailSeverity) -> Color {
        switch severity {
        case .ok: return .green
        case .info: return .blue
        case .warning: return .orange
        case .blocker: return .red
        }
    }

    private func color(for status: GrowthPackMobileStepStatus) -> Color {
        switch status {
        case .ready: return .blue
        case .needsProof: return .orange
        case .waitingReview: return .orange
        case .complete: return .green
        case .blocked: return .secondary
        }
    }
}

private struct RoleVisibilityGrid: View {
    let visibility: GrowthPackMobileDetailRoleVisibility

    private var items: [(String, Bool)] {
        [
            ("证明", visibility.canSeeProofRequirements),
            ("成长积分预览", visibility.canSeeSettlementPreview),
            ("家长审核", visibility.canSeeGuardianReviewQueue),
            ("亲友复核", visibility.canSeeRelativeReview),
            ("设备失败", visibility.canSeeOfflineDeviceFailures)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("当前视角：\(visibility.viewerRole.label)")
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier("growth-pack-detail-visibility-role-\(visibility.viewerRole.rawValue)")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(items, id: \.0) { title, enabled in
                    Label(title, systemImage: enabled ? "checkmark.circle" : "lock")
                        .font(.caption2)
                        .foregroundStyle(enabled ? Color.green : Color.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("growth-pack-detail-visibility-\(title)-\(enabled ? "enabled" : "locked")")
                }
            }
        }
        .padding(.vertical, 2)
    }
}
