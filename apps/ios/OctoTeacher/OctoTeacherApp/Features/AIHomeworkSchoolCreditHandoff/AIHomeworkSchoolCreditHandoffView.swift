import SwiftUI

/// AI 作业学校成长积分交接复核入口。
///
/// 只读组合本地学校作业、AI 引导会话、成人确认和成长积分复核状态；不调用真实 AI、学校系统、
/// 账本、通知或设备，也不发放成长积分。
struct AIHomeworkSchoolCreditHandoffView: View {
    @Environment(SchoolFamilyStore.self) private var store

    let homeworkId: UUID?
    let allowsRoleSwitching: Bool

    @State private var viewerRole: AIHomeworkSchoolCreditHandoffViewerRole

    private let builder = AIHomeworkSchoolCreditHandoffBuilder()

    init(
        homeworkId: UUID? = nil,
        initialRole: AIHomeworkSchoolCreditHandoffViewerRole = .child,
        allowsRoleSwitching: Bool = false
    ) {
        self.homeworkId = homeworkId
        self.allowsRoleSwitching = allowsRoleSwitching
        _viewerRole = State(initialValue: initialRole)
    }

    private var homework: SchoolHomework? {
        if let homeworkId {
            return store.homeworks.first { $0.id == homeworkId }
        }
        return store.homeworks.first
    }

    private var snapshot: AIHomeworkSchoolCreditHandoffSnapshot {
        builder.build(
            viewerRole: viewerRole,
            homework: homework,
            messages: sampleMessages(for: homework)
        )
    }

    var body: some View {
        Group {
            if homework == nil {
                ContentUnavailableView("暂无作业", systemImage: "tray")
            } else {
                content(snapshot)
            }
        }
        .navigationTitle("作业交接复核")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ snapshot: AIHomeworkSchoolCreditHandoffSnapshot) -> some View {
        List {
            roleSection(snapshot)
            headerSection(snapshot)
            guidanceSection(snapshot)
            reviewSection(snapshot)
            creditSection(snapshot)
            nextStepSection(snapshot)
            careSection(snapshot)
            findingsSection(snapshot)
        }
    }

    @ViewBuilder
    private func roleSection(_ snapshot: AIHomeworkSchoolCreditHandoffSnapshot) -> some View {
        if allowsRoleSwitching {
            Section {
                Picker("视角", selection: $viewerRole) {
                    ForEach(AIHomeworkSchoolCreditHandoffViewerRole.allCases, id: \.self) { role in
                        Text(role.label).tag(role)
                    }
                }
                .pickerStyle(.segmented)
            }
        } else {
            Section {
                Label(snapshot.header.viewerRole.label, systemImage: "person.crop.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func headerSection(_ snapshot: AIHomeworkSchoolCreditHandoffSnapshot) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(snapshot.assignment.subjectLabel, systemImage: homework?.subject.systemImage ?? "book")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    statusBadge(snapshot.state)
                }
                Text(snapshot.headline)
                    .font(.headline)
                Text(snapshot.assignment.statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    private func guidanceSection(_ snapshot: AIHomeworkSchoolCreditHandoffSnapshot) -> some View {
        Section("AI 引导") {
            Label(
                snapshot.guidance.noDirectAnswer ? "只给提示和自检" : "已拦截直接答案",
                systemImage: snapshot.guidance.noDirectAnswer ? "checkmark.seal" : "hand.raised"
            )
            LabeledContent("提示数", value: "\(snapshot.guidance.referenceHintCount)")
            LabeledContent("自检数", value: "\(snapshot.guidance.selfCheckCount)")
            LabeledContent("步骤数", value: "\(snapshot.guidance.guidanceStepCount)")
        }
    }

    private func reviewSection(_ snapshot: AIHomeworkSchoolCreditHandoffSnapshot) -> some View {
        Section("学校与成人确认") {
            if snapshot.visibility.canSeeAdultReviewDetail {
                LabeledContent("审批状态", value: snapshot.adultReview.boardStatusLabel)
                LabeledContent("老师验证", value: snapshot.adultReview.teacherReviewRequired ? "待验证" : "无需等待")
                LabeledContent("家长确认", value: snapshot.adultReview.guardianConfirmationRequired ? "待确认" : "无需等待")
                LabeledContent("已确认", value: "\(snapshot.adultReview.confirmedCount)")
            } else {
                Text(snapshot.adultReview.childVisibleMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func creditSection(_ snapshot: AIHomeworkSchoolCreditHandoffSnapshot) -> some View {
        Section("成长积分复核") {
            Label(snapshot.credit.childVisibleCopy, systemImage: icon(for: snapshot.credit.state))
            if snapshot.visibility.canSeeCreditDetail {
                LabeledContent("状态", value: snapshot.credit.state.label)
                LabeledContent("可复核", value: "\(snapshot.credit.settleableCount)")
                LabeledContent("冻结", value: "\(snapshot.credit.frozenCount)")
                LabeledContent("待审核", value: "\(snapshot.credit.reviewRequiredCount)")
                LabeledContent("阻断", value: "\(snapshot.credit.blockedCount)")
            }
        }
    }

    private func nextStepSection(_ snapshot: AIHomeworkSchoolCreditHandoffSnapshot) -> some View {
        Section("下一步") {
            Label(snapshot.childNextStep.title, systemImage: snapshot.childNextStep.actionRequired ? "arrow.forward.circle" : "checkmark.circle")
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private func careSection(_ snapshot: AIHomeworkSchoolCreditHandoffSnapshot) -> some View {
        if let care = snapshot.careSummary, snapshot.visibility.canSeeCareSummary {
            Section("照护摘要") {
                Text(care.headline)
                    .font(.subheadline.bold())
                if !care.intentLabels.isEmpty {
                    TagFlow(labels: care.intentLabels, tint: .blue)
                }
                if !care.riskLabels.isEmpty {
                    TagFlow(labels: care.riskLabels, tint: .orange)
                }
                Text(care.recommendedAction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func findingsSection(_ snapshot: AIHomeworkSchoolCreditHandoffSnapshot) -> some View {
        Section("复核发现") {
            ForEach(snapshot.findings) { finding in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(finding.code.rawValue)
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

    private func statusBadge(_ state: AIHomeworkSchoolCreditHandoffState) -> some View {
        Text(state.label)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint(for: state).opacity(0.15), in: Capsule())
            .foregroundStyle(tint(for: state))
    }

    private func sampleMessages(for homework: SchoolHomework?) -> [AIHomeworkSessionMessage] {
        guard let homework else { return [] }
        switch homework.status {
        case .assigned:
            return []
        case .inProgress:
            return [.init(preset: .whereToStart)]
        case .submitted, .verified:
            return [.init(preset: .howToCheck)]
        case .returned:
            return [.init(preset: .stuckOnStep)]
        }
    }

    private func tint(for state: AIHomeworkSchoolCreditHandoffState) -> Color {
        switch state {
        case .ready: return .green
        case .reviewRequired: return .orange
        case .frozen: return .blue
        case .blocked: return .red
        case .empty: return .secondary
        }
    }

    private func icon(for state: AIHomeworkSchoolCreditCreditState) -> String {
        switch state {
        case .reviewable: return "checkmark.seal"
        case .frozen: return "lock.circle"
        case .blocked: return "nosign"
        }
    }

    private func icon(for severity: AIHomeworkSchoolCreditHandoffSeverity) -> String {
        switch severity {
        case .ok: return "checkmark.circle"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .blocker: return "xmark.octagon"
        }
    }

    private func tint(for severity: AIHomeworkSchoolCreditHandoffSeverity) -> Color {
        switch severity {
        case .ok: return .green
        case .info: return .blue
        case .warning: return .orange
        case .blocker: return .red
        }
    }
}

private struct TagFlow: View {
    let labels: [String]
    let tint: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                chips
            }
            VStack(alignment: .leading, spacing: 6) {
                chips
            }
        }
    }

    private var chips: some View {
        ForEach(labels, id: \.self) { label in
            Text(label)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tint.opacity(0.14), in: Capsule())
                .foregroundStyle(tint)
        }
    }
}
