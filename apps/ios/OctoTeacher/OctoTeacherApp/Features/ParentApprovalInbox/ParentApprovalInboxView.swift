import SwiftUI

/// 家长审批收件箱。
///
/// 只读展示待复核来源、优先级、冻结/阻断和下一步；真正批准/驳回仍留在 ParentMode
/// 原有闭环里，避免总览队列绕过业务流程。
struct ParentApprovalInboxView: View {
    @Environment(LocalFamilyStore.self) private var family
    @Environment(SchoolFamilyStore.self) private var schoolFamily
    @Environment(MockScreenTimeController.self) private var screenTime
    @Environment(MobileOfflineOutboxStore.self) private var offlineOutbox
    @Environment(MobileOfflineReplayStore.self) private var offlineReplay
    @Environment(MobileCreditSettlementStore.self) private var creditSettlement
    @Environment(GrowthPackRuntimeStore.self) private var growthRuntime
    @Environment(GrowthEvidenceTimelineStore.self) private var evidenceTimeline

    @State private var viewerRole: ParentApprovalInboxViewerRole = .guardian

    private var snapshot: ParentApprovalInboxSnapshot {
        let growth = GrowthPackMobileDetailSnapshotBuilder().build(
            viewerRole: growthRole(for: viewerRole),
            runtimeReport: growthRuntime.report,
            evidenceReport: evidenceTimeline.report,
            offlineStatus: offlineOutbox.publicStatus,
            offlineReport: offlineReplay.report
        )
        let school = SchoolGrowthCreditSnapshotBuilder().build(
            viewerRole: schoolRole(for: viewerRole),
            homeworks: schoolFamily.homeworks,
            runtimeReport: growthRuntime.report,
            evidenceReport: evidenceTimeline.report,
            offlineStatus: offlineOutbox.publicStatus,
            offlineReport: offlineReplay.report
        )
        let achievement = FamilyAchievementSnapshotDashboardBuilder()
            .dashboard(for: familyRole(for: viewerRole))
        return ParentApprovalInboxSnapshotBuilder().build(
            viewerRole: viewerRole,
            growthPack: growth,
            schoolCredit: school,
            familyAchievement: achievement,
            creditSettlement: creditSettlement.report,
            offlineStatus: offlineOutbox.publicStatus,
            offlineReport: offlineReplay.report
        )
    }

    var body: some View {
        List {
            headerSection(snapshot)
            itemsSection(snapshot)
            nextActionsSection(snapshot)
            findingsSection(snapshot)
            guardrailSection(snapshot)
        }
        .navigationTitle("审批收件箱")
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

    private func headerSection(_ snapshot: ParentApprovalInboxSnapshot) -> some View {
        Section {
            Picker("视角", selection: $viewerRole) {
                ForEach(ParentApprovalInboxViewerRole.allCases, id: \.self) { role in
                    Text(role.label).tag(role)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(snapshot.header.status.label)
                        .font(.title2.bold())
                    Spacer()
                    Text("\(snapshot.batchSummary.totalCount) 项")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text("紧急 \(snapshot.batchSummary.urgentCount) · 高 \(snapshot.batchSummary.highCount) · 中 \(snapshot.batchSummary.mediumCount) · 冻结 \(snapshot.batchSummary.frozenCount) · 阻断 \(snapshot.batchSummary.blockedCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text(snapshot.visibility.canSeeQueue ? "队列只读展示，真正批准/驳回仍在对应流程里完成。" : "非家长视角不会看到家长审批队列、内部优先级或私密证明。")
        }
    }

    private func itemsSection(_ snapshot: ParentApprovalInboxSnapshot) -> some View {
        Section("待复核来源") {
            if snapshot.items.isEmpty {
                Text(snapshot.visibility.canSeeQueue ? "暂无待复核项目" : "该视角不可查看家长审批队列")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon(for: item.kind))
                            .foregroundStyle(color(for: item.priority))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(item.priority.label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(color(for: item.priority))
                            }
                            Text("\(item.kind.label) · \(item.sourceBoundary.sourceRole.label) · \(item.sourceBoundary.sourceKind.label)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.childVisibleCopy)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let reason = item.frozenOrBlockedReason {
                                Text(reason)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func nextActionsSection(_ snapshot: ParentApprovalInboxSnapshot) -> some View {
        Section("下一步") {
            ForEach(snapshot.nextActions.prefix(8)) { action in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: action.kind == .resolveOfflineConflict ? "arrow.triangle.2.circlepath" : "checkmark.seal")
                        .foregroundStyle(color(for: action.priority))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(action.title)
                            .font(.subheadline.weight(.semibold))
                        Text("\(action.priority.label) · \(action.actionRequired ? "需要处理" : "只读提示")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func findingsSection(_ snapshot: ParentApprovalInboxSnapshot) -> some View {
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
            }
        }
    }

    private func guardrailSection(_ snapshot: ParentApprovalInboxSnapshot) -> some View {
        Section("只读护栏") {
            LabeledContent("批准 / 驳回", value: (snapshot.publicSummary.approvesItems || snapshot.publicSummary.rejectsItems) ? "会" : "不会")
            LabeledContent("写成长积分账本", value: snapshot.publicSummary.writesLedger ? "会" : "不会")
            LabeledContent("改作业 / 学校系统", value: (snapshot.publicSummary.modifiesHomework || snapshot.publicSummary.writesSchoolHomework || snapshot.publicSummary.callsSchoolSystem) ? "会" : "不会")
            LabeledContent("通知 / 解锁 / 上传", value: (snapshot.publicSummary.sendsNotification || snapshot.publicSummary.unlocksDevice || snapshot.publicSummary.uploadsMedia) ? "会" : "不会")
        }
    }

    private func growthRole(for role: ParentApprovalInboxViewerRole) -> GrowthPackMobileDetailViewerRole {
        switch role {
        case .guardian: return .guardian
        case .child: return .child
        case .relative: return .relative
        case .teacher: return .teacher
        }
    }

    private func schoolRole(for role: ParentApprovalInboxViewerRole) -> SchoolGrowthCreditViewerRole {
        switch role {
        case .guardian: return .guardian
        case .teacher: return .teacher
        case .child, .relative: return .child
        }
    }

    private func familyRole(for role: ParentApprovalInboxViewerRole) -> FamilyGrowthViewerRole {
        switch role {
        case .guardian: return .guardian
        case .relative: return .relative
        case .child, .teacher: return .child
        }
    }

    private func icon(for kind: ParentApprovalInboxItemKind) -> String {
        switch kind {
        case .growthProof: return "doc.badge.clock"
        case .schoolHomework: return "graduationcap"
        case .relativeComment: return "text.bubble"
        case .evidenceAppeal: return "exclamationmark.arrow.triangle.2.circlepath"
        case .creditSuggestion: return "star.circle"
        case .offlineConflict: return "arrow.triangle.2.circlepath"
        }
    }

    private func color(for priority: ParentApprovalInboxPriority) -> Color {
        switch priority {
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        case .urgent: return .purple
        }
    }
}
