import SwiftUI

/// 学校成长快照页。
///
/// 手机端把学校作业、老师验证、家长确认、成长包成长积分建议、证据申诉和离线冲突放到一个只读面板里。
/// 视图不提交作业、不批准成长积分、不调用学校系统，只消费本地快照。
struct SchoolGrowthCreditSnapshotView: View {
    @Environment(LocalFamilyStore.self) private var family
    @Environment(SchoolFamilyStore.self) private var schoolFamily
    @Environment(MobileOfflineOutboxStore.self) private var offlineOutbox
    @Environment(MobileOfflineReplayStore.self) private var offlineReplay
    @Environment(GrowthPackRuntimeStore.self) private var growthRuntime
    @Environment(GrowthEvidenceTimelineStore.self) private var evidenceTimeline

    @State private var viewerRole: SchoolGrowthCreditViewerRole = .child

    private var builder: SchoolGrowthCreditSnapshotBuilder {
        SchoolGrowthCreditSnapshotBuilder()
    }

    private var snapshot: SchoolGrowthCreditSnapshot {
        builder.build(
            viewerRole: viewerRole,
            homeworks: schoolFamily.homeworks,
            runtimeReport: growthRuntime.report,
            evidenceReport: evidenceTimeline.report,
            offlineStatus: offlineOutbox.publicStatus,
            offlineReport: offlineReplay.report
        )
    }

    var body: some View {
        List {
            headerSection(snapshot)
            assignmentSection(snapshot)
            nextActionSection(snapshot)
            creditPreviewSection(snapshot)
            evidenceSection(snapshot)
            offlineSection(snapshot)
            findingsSection(snapshot)
        }
        .navigationTitle("学校成长快照")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            refreshSnapshotInputs()
        }
    }

    private func refreshSnapshotInputs() {
        growthRuntime.refresh(family: family, schoolFamily: schoolFamily)
        evidenceTimeline.refresh(
            family: family,
            schoolFamily: schoolFamily,
            runtime: GrowthEvidenceTimelineRuntimeContext(report: growthRuntime.report)
        )
        if !offlineReplay.hasReplayed {
            offlineReplay.replay(outbox: offlineOutbox)
        }
    }

    private func headerSection(_ snapshot: SchoolGrowthCreditSnapshot) -> some View {
        Section {
            Picker("视角", selection: $viewerRole) {
                ForEach(SchoolGrowthCreditViewerRole.allCases, id: \.self) { role in
                    Text(role.label).tag(role)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(snapshot.header.status.label)
                        .font(.title3.bold())
                    Spacer()
                    Text(snapshot.header.privacyScope)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text("作业 \(snapshot.publicSummary.assignmentCount) · 成长积分建议 \(snapshot.publicSummary.creditPreviewCount) · 可发放建议 \(snapshot.publicSummary.usableCreditPreviewCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("申诉 \(snapshot.publicSummary.appealCount) · 离线冲突 \(snapshot.publicSummary.offlineConflictCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

            SchoolGrowthCreditVisibilityGrid(visibility: snapshot.visibility)
        } footer: {
            Text("该页面只读展示；成长积分建议只是家长审核前建议，不写学校作业、不写账本、不上传附件、不通知、不解锁设备。")
        }
    }

    private func assignmentSection(_ snapshot: SchoolGrowthCreditSnapshot) -> some View {
        Section("作业状态") {
            if snapshot.assignments.isEmpty {
                Text("暂无可见作业")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.assignments) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon(for: item.status))
                            .foregroundStyle(color(for: item.status))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                Text(item.status.label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(color(for: item.status))
                            }
                            Text("\(item.subject) · 截止 \(item.dueLabel)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.verificationMode)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func nextActionSection(_ snapshot: SchoolGrowthCreditSnapshot) -> some View {
        Section("下一步") {
            ForEach(snapshot.nextActions) { action in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon(for: action.kind))
                        .foregroundStyle(color(for: action.severity))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(action.title)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(action.kind.label) · \(action.actionRequired ? "需要处理" : "只读提示")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func creditPreviewSection(_ snapshot: SchoolGrowthCreditSnapshot) -> some View {
        Section {
            if snapshot.creditPreviews.isEmpty {
                Text(snapshot.visibility.canSeeCreditPreview ? "暂无成长积分建议" : "该视角不显示成长积分建议")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.creditPreviews) { preview in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(preview.state.label)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(preview.amountLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(color(for: preview.state))
                        }
                        Text(preview.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("成长积分建议")
        } footer: {
            Text(snapshot.visibility.canSeeCreditPreview ? "只有家长视角能看到可审核成长积分建议；这里仍然不落账。" : "成长积分建议已被当前角色可见性隐藏。")
        }
    }

    private func evidenceSection(_ snapshot: SchoolGrowthCreditSnapshot) -> some View {
        Section("证据与申诉") {
            LabeledContent("时间线节点", value: "\(snapshot.evidenceStatus.timelineEventCount)")
            LabeledContent("申诉 / 未结申诉", value: "\(snapshot.evidenceStatus.appealCount) / \(snapshot.evidenceStatus.openAppealCount)")
            LabeledContent("成长积分暂停 / 阻断", value: "\(snapshot.evidenceStatus.creditFrozenCount) / \(snapshot.evidenceStatus.creditBlockedCount)")
        }
    }

    private func offlineSection(_ snapshot: SchoolGrowthCreditSnapshot) -> some View {
        Section("离线状态") {
            LabeledContent("可见卡片", value: "\(snapshot.offlineStatus.cardCount)")
            LabeledContent("冲突 / 回滚", value: "\(snapshot.offlineStatus.conflictCount) / \(snapshot.offlineStatus.rollbackRequiredCount)")
            LabeledContent("需处理", value: "\(snapshot.offlineStatus.actionRequiredCount)")
        }
    }

    private func findingsSection(_ snapshot: SchoolGrowthCreditSnapshot) -> some View {
        Section("安全发现项") {
            ForEach(snapshot.findings) { finding in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon(for: finding.severity))
                        .foregroundStyle(color(for: finding.severity))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(finding.code.rawValue)
                            .font(.caption.monospaced().weight(.semibold))
                        Text(finding.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func icon(for status: SchoolGrowthCreditAssignmentStatus) -> String {
        switch status {
        case .assigned: return "circle"
        case .submitted: return "paperplane"
        case .teacherVerified: return "checkmark.seal"
        case .guardianConfirmed: return "person.badge.shield.checkmark"
        case .reviewRequired: return "hourglass"
        case .appealed: return "exclamationmark.bubble"
        case .offlineConflict: return "arrow.triangle.2.circlepath"
        case .blocked: return "nosign"
        }
    }

    private func icon(for kind: SchoolGrowthCreditNextAction.Kind) -> String {
        switch kind {
        case .submitHomework: return "square.and.arrow.up"
        case .teacherVerify: return "book.closed"
        case .guardianConfirm: return "person.badge.shield.checkmark"
        case .resolveAppeal: return "exclamationmark.bubble"
        case .resolveOfflineConflict: return "arrow.triangle.2.circlepath"
        case .readOnly: return "eye"
        }
    }

    private func icon(for severity: SchoolGrowthCreditSeverity) -> String {
        switch severity {
        case .ok: return "checkmark.seal"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .blocker: return "xmark.octagon"
        }
    }

    private func color(for status: SchoolGrowthCreditAssignmentStatus) -> Color {
        switch status {
        case .assigned: return .blue
        case .submitted, .reviewRequired: return .orange
        case .teacherVerified, .guardianConfirmed: return .green
        case .appealed, .offlineConflict: return .purple
        case .blocked: return .red
        }
    }

    private func color(for state: SchoolGrowthCreditPreviewState) -> Color {
        switch state {
        case .availablePreview: return .green
        case .reviewRequired, .frozen: return .orange
        case .blocked, .voided: return .red
        case .duplicate, .alreadyCredited: return .secondary
        }
    }

    private func color(for severity: SchoolGrowthCreditNextAction.Severity) -> Color {
        switch severity {
        case .info: return .blue
        case .warning: return .orange
        case .urgent: return .red
        }
    }

    private func color(for severity: SchoolGrowthCreditSeverity) -> Color {
        switch severity {
        case .ok: return .green
        case .info: return .blue
        case .warning: return .orange
        case .blocker: return .red
        }
    }
}

private struct SchoolGrowthCreditVisibilityGrid: View {
    let visibility: SchoolGrowthCreditVisibility

    private var items: [(String, Bool)] {
        [
            ("提交", visibility.canSeeSubmission),
            ("老师验证", visibility.canSeeTeacherVerification),
            ("家长确认", visibility.canSeeGuardianConfirmation),
            ("成长积分", visibility.canSeeCreditPreview),
            ("离线冲突", visibility.canSeeOfflineConflicts),
            ("申诉状态", visibility.canSeeAppealState)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("当前视角：\(visibility.viewerRole.label)")
                .font(.caption.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(items, id: \.0) { title, enabled in
                    Label(title, systemImage: enabled ? "checkmark.circle" : "lock")
                        .font(.caption2)
                        .foregroundStyle(enabled ? Color.green : Color.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
