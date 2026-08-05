import SwiftUI

/// 学校作业与成长包任务联动工作台。
///
/// 该页面只展示本地 mock/read-model，不提交作业、不验证老师或家长、不写学校系统、
/// 不调用 AI/网络、不写账本、不发成长积分、不解锁设备。
struct MobileSchoolHomeworkGrowthPackLinkageWorkbenchView: View {
    @Environment(LocalFamilyStore.self) private var family
    @Environment(SchoolFamilyStore.self) private var schoolFamily
    @Environment(GrowthPackRuntimeStore.self) private var growthRuntime

    @State private var role: MobileSchoolHomeworkGrowthPackLinkageViewerRole
    private let allowedRoles: [MobileSchoolHomeworkGrowthPackLinkageViewerRole]

    init(
        initialRole: MobileSchoolHomeworkGrowthPackLinkageViewerRole = .child,
        allowedRoles: [MobileSchoolHomeworkGrowthPackLinkageViewerRole] = MobileSchoolHomeworkGrowthPackLinkageViewerRole.allCases
    ) {
        let normalized = Self.normalizedRoles(allowedRoles)
        let resolvedRole = normalized.contains(initialRole) ? initialRole : normalized[0]
        _role = State(initialValue: resolvedRole)
        self.allowedRoles = normalized
    }

    private var workbench: MobileSchoolHomeworkGrowthPackLinkageWorkbench {
        MobileSchoolHomeworkGrowthPackLinkageBuilder().build(
            role: role,
            homeworks: schoolFamily.homeworks,
            runtimeReport: growthRuntime.report
        )
    }

    var body: some View {
        List {
            roleSection
            overviewSection
            linkageSection
            findingSection
            relatedSection
            guardrailSection
        }
        .navigationTitle("作业联动")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !growthRuntime.hasBuilt {
                growthRuntime.refresh(family: family, schoolFamily: schoolFamily)
            }
        }
    }

    private var roleSection: some View {
        Section {
            if allowedRoles.count > 1 {
                Picker("视角", selection: $role) {
                    ForEach(allowedRoles, id: \.self) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }
            Text(workbench.audienceNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var overviewSection: some View {
        Section(workbench.title) {
            Text(workbench.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            LinkageMetric(title: "联动作业", value: workbench.publicSummary.linkedHomeworkCount, systemImage: "book.closed")
            LinkageMetric(title: "等老师", value: workbench.publicSummary.waitingTeacherCount, systemImage: "graduationcap")
            LinkageMetric(title: "等家长", value: workbench.publicSummary.waitingGuardianCount, systemImage: "person.badge.shield.checkmark")
            LinkageMetric(title: "退回/阻断", value: workbench.publicSummary.returnedOrBlockedCount, systemImage: "lock.shield")
            if role == .guardian {
                LinkageMetric(title: "建议边界", value: workbench.publicSummary.guardianCreditSuggestionCount, systemImage: "checkmark.seal")
            }
        }
    }

    private var linkageSection: some View {
        Section("作业与成长包") {
            if workbench.items.isEmpty {
                ContentUnavailableView("暂无可展示联动", systemImage: "lock")
            } else {
                ForEach(workbench.items) { item in
                    LinkageItemRow(item: item)
                }
            }
        }
    }

    private var findingSection: some View {
        Section("边界提示") {
            ForEach(workbench.findings) { finding in
                Label {
                    Text(finding.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: icon(for: finding.code))
                        .foregroundStyle(color(for: finding.code))
                }
            }
        }
    }

    private var relatedSection: some View {
        Section("相关入口") {
            NavigationLink {
                SchoolHomeworkView()
            } label: {
                Label("学校作业列表", systemImage: "list.bullet.clipboard")
            }
            .accessibilityIdentifier("school-homework-linkage-school-homework-list")
            NavigationLink {
                SchoolJointApprovalBoardView(initialRole: jointApprovalRole(for: role), allowedRoles: [jointApprovalRole(for: role)])
            } label: {
                Label("家校联合审批台", systemImage: "person.2.badge.gearshape")
            }
            .accessibilityIdentifier("school-homework-linkage-joint-approval")
            if role != .teacher {
                NavigationLink {
                    GrowthPackContentPlayerWorkbenchView(
                        initialRole: role == .guardian ? .guardian : .child,
                        allowedRoles: [role == .guardian ? .guardian : .child]
                    )
                } label: {
                    Label("成长包内容播放器", systemImage: "play.rectangle")
                }
                .accessibilityIdentifier("school-homework-linkage-content-player")
            }
        }
    }

    private var guardrailSection: some View {
        Section("执行边界") {
            LinkageBoundaryFlag(title: "提交/上传", value: workbench.publicSummary.submitsHomework || workbench.publicSummary.uploadsAttachment)
            LinkageBoundaryFlag(title: "老师/家长验证", value: workbench.publicSummary.verifiesTeacher || workbench.publicSummary.confirmsGuardian)
            LinkageBoundaryFlag(title: "学校/LMS/AI/网络", value: workbench.publicSummary.writesSchoolSystem || workbench.publicSummary.callsLms || workbench.publicSummary.callsAIProvider || workbench.publicSummary.callsNetwork)
            LinkageBoundaryFlag(title: "账本/奖励/设备", value: workbench.publicSummary.writesLedger || workbench.publicSummary.grantsCredit || workbench.publicSummary.unlocksDevice)
            LinkageBoundaryFlag(title: "通知", value: workbench.publicSummary.sendsNotification)
        }
    }

    private func jointApprovalRole(
        for role: MobileSchoolHomeworkGrowthPackLinkageViewerRole
    ) -> SchoolJointApprovalViewerRole {
        switch role {
        case .child: return .child
        case .guardian: return .guardian
        case .teacher: return .teacher
        }
    }

    private func icon(for code: MobileSchoolHomeworkGrowthPackFindingCode) -> String {
        switch code {
        case .readOnlyReady: return "checkmark.shield"
        case .returnedBlocksCredit: return "arrow.uturn.backward"
        case .teacherCreditHidden: return "eye.slash"
        case .childAdultReasonHidden: return "person.crop.circle.badge.checkmark"
        case .guardianConfirmationRequired: return "person.badge.shield.checkmark"
        case .unsafePayloadBlocked: return "lock.shield"
        }
    }

    private func color(for code: MobileSchoolHomeworkGrowthPackFindingCode) -> Color {
        switch code {
        case .readOnlyReady, .teacherCreditHidden, .childAdultReasonHidden:
            return .green
        case .guardianConfirmationRequired:
            return .orange
        case .returnedBlocksCredit, .unsafePayloadBlocked:
            return .red
        }
    }

    private static func normalizedRoles(
        _ roles: [MobileSchoolHomeworkGrowthPackLinkageViewerRole]
    ) -> [MobileSchoolHomeworkGrowthPackLinkageViewerRole] {
        let source = roles.isEmpty ? MobileSchoolHomeworkGrowthPackLinkageViewerRole.allCases : roles
        return MobileSchoolHomeworkGrowthPackLinkageViewerRole.allCases.filter { source.contains($0) }
    }
}

private struct LinkageItemRow: View {
    let item: MobileSchoolHomeworkGrowthPackLinkageItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: item.status.systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 22)
                Text(item.title)
                    .font(.subheadline.bold())
                Spacer()
                Text(item.status.label)
                    .font(.caption2.bold())
                    .foregroundStyle(tint)
            }

            HStack(spacing: 8) {
                Label(item.subjectLabel, systemImage: "graduationcap")
                Label(item.dueLabel, systemImage: "clock")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text(item.growthPackStatusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            Label(item.verificationLabel, systemImage: "checkmark.shield")
                .font(.caption)
                .foregroundStyle(.secondary)

            Label(item.creditBoundaryLabel, systemImage: "creditcard.and.123")
                .font(.caption)
                .foregroundStyle(.secondary)

            Label(item.proofLabel, systemImage: "doc.text")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Label(item.nextStep, systemImage: "arrow.forward.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private var tint: Color {
        switch item.status {
        case .waitingChild: return .blue
        case .waitingTeacher, .waitingGuardian: return .orange
        case .suggestedBoundary: return .green
        case .returned, .blocked: return .red
        }
    }
}

private struct LinkageMetric: View {
    let title: String
    let value: Int
    let systemImage: String

    var body: some View {
        LabeledContent {
            Text("\(value)").monospacedDigit()
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

private struct LinkageBoundaryFlag: View {
    let title: String
    let value: Bool

    var body: some View {
        LabeledContent(title) {
            Text(value ? "会触发" : "不触发")
                .foregroundStyle(value ? .red : .green)
        }
    }
}
