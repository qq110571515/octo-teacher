import SwiftUI

/// AI 作业家校收件箱。
///
/// 只读展示孩子、家长、老师、运营四种视角下的作业复核状态；真正提交、验证、
/// 发成长积分、通知学校或调用 AI/LMS 都不在这里发生。
struct AIHomeworkFamilySchoolInboxView: View {
    @Environment(SchoolFamilyStore.self) private var schoolFamily

    @State private var viewerRole: AIHomeworkFamilySchoolInboxViewerRole
    private let allowedRoles: [AIHomeworkFamilySchoolInboxViewerRole]

    private let builder = AIHomeworkFamilySchoolInboxBuilder()

    init(
        initialRole: AIHomeworkFamilySchoolInboxViewerRole = .guardian,
        allowedRoles: [AIHomeworkFamilySchoolInboxViewerRole] = AIHomeworkFamilySchoolInboxViewerRole.allCases
    ) {
        let safeRoles = allowedRoles.isEmpty ? [initialRole] : allowedRoles
        let safeInitialRole = safeRoles.contains(initialRole) ? initialRole : safeRoles[0]
        self.allowedRoles = safeRoles
        _viewerRole = State(initialValue: safeInitialRole)
    }

    private var snapshot: AIHomeworkFamilySchoolInboxSnapshot {
        builder.build(
            viewerRole: viewerRole,
            homeworks: schoolFamily.homeworks
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
        .navigationTitle("家校作业收件箱")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func headerSection(_ snapshot: AIHomeworkFamilySchoolInboxSnapshot) -> some View {
        Section {
            if allowedRoles.count > 1 {
                Picker("视角", selection: $viewerRole) {
                    ForEach(allowedRoles, id: \.self) { role in
                        Text(role.label).tag(role)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("ai-homework-inbox-role-picker")
            } else {
                LabeledContent("视角", value: viewerRole.label)
                    .accessibilityIdentifier("ai-homework-inbox-role-\(viewerRole.rawValue)")
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(snapshot.status.label)
                        .font(.title3.bold())
                        .accessibilityIdentifier("ai-homework-inbox-status")
                    Spacer()
                    Text("\(snapshot.publicSummary.visibleItemCount) 项")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("ai-homework-inbox-visible-count")
                }
                Text(snapshot.headline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ai-homework-inbox-headline")
            }
            .padding(.vertical, 2)
        } footer: {
            Text("此处只读汇总 AI 引导、学校复核、家长审批和 LMS 边界；不会发成长积分、通知学校、调用 AI 或修改作业。")
        }
    }

    private func itemsSection(_ snapshot: AIHomeworkFamilySchoolInboxSnapshot) -> some View {
        Section("收件箱") {
            if snapshot.items.isEmpty {
                Text("当前视角暂无可见事项")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ai-homework-inbox-empty")
            } else {
                ForEach(Array(snapshot.items.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon(for: item.kind))
                            .foregroundStyle(color(for: item))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(item.badge)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(color(for: item))
                            }
                            Text(item.kind.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityIdentifier("ai-homework-inbox-item-\(item.kind.rawValue)-\(index)")
                }
            }
        }
    }

    private func nextActionsSection(_ snapshot: AIHomeworkFamilySchoolInboxSnapshot) -> some View {
        Section("下一步") {
            ForEach(Array(snapshot.nextActions.prefix(8).enumerated()), id: \.element.id) { index, action in
                Label {
                    Text(action.title)
                        .font(.subheadline)
                } icon: {
                    Image(systemName: action.actionRequired ? "arrow.forward.circle" : "checkmark.circle")
                        .foregroundStyle(action.actionRequired ? .orange : .green)
                }
                .accessibilityIdentifier("ai-homework-inbox-action-\(index)")
            }
        }
    }

    private func findingsSection(_ snapshot: AIHomeworkFamilySchoolInboxSnapshot) -> some View {
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
                .accessibilityIdentifier("ai-homework-inbox-finding-\(finding.code.rawValue)")
            }
        }
    }

    private func guardrailSection(_ snapshot: AIHomeworkFamilySchoolInboxSnapshot) -> some View {
        Section("只读护栏") {
            LabeledContent("调用 AI / LMS", value: (snapshot.publicSummary.callsAiProvider || snapshot.publicSummary.callsLms) ? "会" : "不会")
                .accessibilityIdentifier("ai-homework-inbox-boundary-ai-lms")
            LabeledContent("写学校 / 通知", value: (snapshot.publicSummary.writesSchoolSystem || snapshot.publicSummary.sendsNotification) ? "会" : "不会")
                .accessibilityIdentifier("ai-homework-inbox-boundary-school-notification")
            LabeledContent("写账本 / 发成长积分", value: (snapshot.publicSummary.writesLedger || snapshot.publicSummary.issuesCredit) ? "会" : "不会")
                .accessibilityIdentifier("ai-homework-inbox-boundary-ledger-credit")
            LabeledContent("解锁设备", value: snapshot.publicSummary.unlocksDevice ? "会" : "不会")
                .accessibilityIdentifier("ai-homework-inbox-boundary-device")
        }
    }

    private func icon(for kind: AIHomeworkFamilySchoolInboxItemKind) -> String {
        switch kind {
        case .guidance: return "brain.head.profile"
        case .homeworkStatus: return "doc.text"
        case .teacherReview: return "graduationcap"
        case .guardianReview: return "person.badge.key"
        case .lmsBoundary: return "shield"
        case .creditReview: return "star.circle"
        case .parentInbox: return "tray.full"
        case .operationsSummary: return "chart.bar.doc.horizontal"
        }
    }

    private func color(for item: AIHomeworkFamilySchoolInboxItem) -> Color {
        if item.badge.contains("阻断") || item.badge.contains("拦截") { return .red }
        if item.actionRequired { return .orange }
        return .blue
    }
}
