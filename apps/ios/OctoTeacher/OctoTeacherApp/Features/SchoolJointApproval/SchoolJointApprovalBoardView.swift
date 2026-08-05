import SwiftUI

/// 学校老师家长联合审批台页。
///
/// 手机端把学校作业、老师验证、家长确认、退回、申诉冻结、离线回滚和成长积分建议
/// 组合成一个只读联合审批面板：家长看完整队列与原因，老师只看学校相关验证状态，
/// 孩子只看安全进度文案。视图不验证老师、不确认家长、不发放成长积分、不调用学校系统。
struct SchoolJointApprovalBoardView: View {
    @Environment(LocalFamilyStore.self) private var family
    @Environment(SchoolFamilyStore.self) private var schoolFamily
    @Environment(MockScreenTimeController.self) private var screenTime
    @Environment(MobileOfflineOutboxStore.self) private var offlineOutbox
    @Environment(MobileOfflineReplayStore.self) private var offlineReplay
    @Environment(MobileCreditSettlementStore.self) private var creditSettlement
    @Environment(GrowthPackRuntimeStore.self) private var growthRuntime
    @Environment(GrowthEvidenceTimelineStore.self) private var evidenceTimeline

    @State private var viewerRole: SchoolJointApprovalViewerRole
    private let allowedRoles: [SchoolJointApprovalViewerRole]

    init(
        initialRole: SchoolJointApprovalViewerRole = .guardian,
        allowedRoles: [SchoolJointApprovalViewerRole] = SchoolJointApprovalViewerRole.allCases
    ) {
        let safeRoles = allowedRoles.isEmpty ? [initialRole] : allowedRoles
        let safeInitialRole = safeRoles.contains(initialRole) ? initialRole : safeRoles[0]
        self.allowedRoles = safeRoles
        _viewerRole = State(initialValue: safeInitialRole)
    }

    private var snapshot: SchoolJointApprovalSnapshot {
        let school = SchoolGrowthCreditSnapshotBuilder().build(
            viewerRole: schoolRole(for: viewerRole),
            homeworks: schoolFamily.homeworks,
            runtimeReport: growthRuntime.report,
            evidenceReport: evidenceTimeline.report,
            offlineStatus: offlineOutbox.publicStatus,
            offlineReport: offlineReplay.report
        )
        return SchoolJointApprovalSnapshotBuilder().build(
            viewerRole: viewerRole,
            homeworks: schoolFamily.homeworks,
            schoolCredit: school,
            creditSettlement: creditSettlement.report,
            offlineStatus: offlineOutbox.publicStatus,
            offlineReport: offlineReplay.report
        )
    }

    var body: some View {
        List {
            headerSection(snapshot)
            itemsSection(snapshot)
            creditSection(snapshot)
            findingsSection(snapshot)
            guardrailSection(snapshot)
        }
        .navigationTitle("联合审批台")
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
        creditSettlement.refresh(
            offlineReport: offlineReplay.report,
            family: family,
            schoolFamily: schoolFamily,
            screenTime: screenTime
        )
    }

    private func headerSection(_ snapshot: SchoolJointApprovalSnapshot) -> some View {
        Section {
            Picker("视角", selection: $viewerRole) {
                ForEach(allowedRoles, id: \.self) { role in
                    Text(role.label).tag(role)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(snapshot.header.status.label)
                        .font(.title2.bold())
                        .accessibilityIdentifier("school-joint-approval-status")
                    Spacer()
                    Text("\(snapshot.stageSummary.totalCount) 项")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("school-joint-approval-total-count")
                }
                Text("等老师 \(snapshot.stageSummary.awaitingTeacherCount) · 等家长 \(snapshot.stageSummary.awaitingGuardianCount) · 退回 \(snapshot.stageSummary.returnedCount) · 冻结 \(snapshot.stageSummary.appealFrozenCount) · 回滚 \(snapshot.stageSummary.offlineRollbackCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("school-joint-approval-stage-summary")
            }
        } footer: {
            Text(footerText(for: snapshot.visibility.viewerRole))
        }
    }

    private func footerText(for role: SchoolJointApprovalViewerRole) -> String {
        switch role {
        case .guardian:
            return "队列只读展示，老师验证与家长确认仍在各自流程里完成。"
        case .teacher:
            return "老师只看学校相关验证状态，看不到家长内部优先级、申诉原因或成长积分金额。"
        case .child:
            return "孩子只看安全进度文案，看不到内部优先级、原因、成长积分金额或冲突细节。"
        }
    }

    private func itemsSection(_ snapshot: SchoolJointApprovalSnapshot) -> some View {
        Section("联合审批阶段") {
            if snapshot.items.isEmpty {
                Text("暂无需要展示的审批阶段")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: icon(for: item.stage))
                                .foregroundStyle(color(for: item.stage))
                            Text(item.headline)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if let priority = item.priority {
                                Text(priority.label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if snapshot.visibility.viewerRole == .child {
                            Text(item.childSafeCopy)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(item.stage.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let reason = item.guardianReason {
                                Text(reason)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityIdentifier("school-joint-approval-item-\(item.stage.rawValue)")
                }
            }
        }
    }

    @ViewBuilder
    private func creditSection(_ snapshot: SchoolJointApprovalSnapshot) -> some View {
        if snapshot.visibility.canSeeCreditAmount {
            Section("成长积分建议（只读）") {
                if snapshot.creditNotes.isEmpty {
                    Text("暂无学校作业成长积分建议")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.creditNotes) { note in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(note.stateLabel)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                if let amount = note.amount {
                                    Text("\(amount) 分")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let reason = note.reason {
                                Text(reason)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 2)
                        .accessibilityIdentifier("school-joint-approval-credit-note-\(note.actionRequired ? "action" : "preview")")
                    }
                }
            }
        }
    }

    private func findingsSection(_ snapshot: SchoolJointApprovalSnapshot) -> some View {
        Section("发现项") {
            ForEach(snapshot.findings) { finding in
                VStack(alignment: .leading, spacing: 3) {
                    Text(finding.code.rawValue)
                        .font(.caption.weight(.semibold))
                    Text(finding.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
                .accessibilityIdentifier("school-joint-approval-finding-\(finding.code.rawValue)")
            }
        }
    }

    private func guardrailSection(_ snapshot: SchoolJointApprovalSnapshot) -> some View {
        Section("只读护栏") {
            LabeledContent("验证老师 / 确认家长", value: (snapshot.publicSummary.verifiesTeacher || snapshot.publicSummary.confirmsGuardian) ? "会" : "不会")
                .accessibilityIdentifier("school-joint-approval-guardrail-teacher-guardian")
            LabeledContent("写成长积分账本 / 暂停成长积分", value: (snapshot.publicSummary.writesLedger || snapshot.publicSummary.freezesCredit) ? "会" : "不会")
                .accessibilityIdentifier("school-joint-approval-guardrail-credit-ledger")
            LabeledContent("改作业 / 调用 LMS", value: (snapshot.publicSummary.writesSchoolHomework || snapshot.publicSummary.callsSchoolSystem || snapshot.publicSummary.callsLms) ? "会" : "不会")
                .accessibilityIdentifier("school-joint-approval-guardrail-school-lms")
            LabeledContent("通知 / 解锁设备", value: (snapshot.publicSummary.sendsNotification || snapshot.publicSummary.unlocksDevice) ? "会" : "不会")
                .accessibilityIdentifier("school-joint-approval-guardrail-notification-device")
        }
    }

    private func schoolRole(for role: SchoolJointApprovalViewerRole) -> SchoolGrowthCreditViewerRole {
        switch role {
        case .guardian: return .guardian
        case .teacher: return .teacher
        case .child: return .child
        }
    }

    private func icon(for stage: SchoolJointApprovalStage) -> String {
        switch stage {
        case .awaitingSubmission: return "pencil.and.outline"
        case .awaitingTeacher: return "graduationcap"
        case .awaitingGuardian: return "person.badge.shield.checkmark"
        case .confirmed: return "checkmark.seal"
        case .returned: return "arrow.uturn.backward"
        case .appealFrozen: return "exclamationmark.triangle"
        case .offlineRollback: return "arrow.triangle.2.circlepath"
        case .blocked: return "lock"
        }
    }

    private func color(for stage: SchoolJointApprovalStage) -> Color {
        switch stage {
        case .confirmed: return .green
        case .awaitingTeacher, .awaitingGuardian: return .orange
        case .awaitingSubmission: return .blue
        case .returned: return .red
        case .appealFrozen, .offlineRollback, .blocked: return .purple
        }
    }
}
