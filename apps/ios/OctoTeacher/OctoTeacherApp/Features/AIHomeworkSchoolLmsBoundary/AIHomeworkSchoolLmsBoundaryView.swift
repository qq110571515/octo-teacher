import SwiftUI

/// 手机端 AI 作业学校 LMS/provider 边界入口。
///
/// 只展示本地 mock 边界状态：真实 AI provider、局域网 QWEN、LMS、学校系统、账本、
/// 通知和设备都不会被调用。
struct AIHomeworkSchoolLmsBoundaryView: View {
    @Environment(SchoolFamilyStore.self) private var store

    let homeworkId: UUID?
    let allowsRoleSwitching: Bool

    @State private var viewerRole: AIHomeworkSchoolLmsBoundaryViewerRole

    private let builder = AIHomeworkSchoolLmsBoundaryBuilder()

    init(
        homeworkId: UUID? = nil,
        initialRole: AIHomeworkSchoolLmsBoundaryViewerRole = .guardian,
        allowsRoleSwitching: Bool = true
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

    private var snapshot: AIHomeworkSchoolLmsBoundarySnapshot {
        builder.build(
            viewerRole: viewerRole,
            homework: homework,
            messages: sampleMessages(for: homework)
        )
    }

    var body: some View {
        List {
            roleSection(snapshot)
            headerSection(snapshot)
            providerBoundarySection(snapshot)
            lmsSection(snapshot)
            consentSection(snapshot)
            transcriptSection(snapshot)
            auditSection(snapshot)
            findingsSection(snapshot)
            guardrailSection(snapshot)
        }
        .navigationTitle("作业 AI 安全边界")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func roleSection(_ snapshot: AIHomeworkSchoolLmsBoundarySnapshot) -> some View {
        if allowsRoleSwitching {
            Section {
                Picker("视角", selection: $viewerRole) {
                    ForEach(AIHomeworkSchoolLmsBoundaryViewerRole.allCases, id: \.self) { role in
                        Text(role.label).tag(role)
                    }
                }
                .pickerStyle(.segmented)
            }
        } else {
            Section {
                Label(snapshot.visibility.viewerRole.label, systemImage: "person.crop.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func headerSection(_ snapshot: AIHomeworkSchoolLmsBoundarySnapshot) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(snapshot.subjectLabel, systemImage: homework?.subject.systemImage ?? "book")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    statusBadge(snapshot.state)
                }
                Text(snapshot.headline)
                    .font(.headline)
                    .accessibilityIdentifier("ai-lms-boundary-headline")
                Text(snapshot.childSafeCopy)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ai-lms-boundary-child-safe-copy")
            }
            .padding(.vertical, 2)
        }
    }

    private func providerBoundarySection(_ snapshot: AIHomeworkSchoolLmsBoundarySnapshot) -> some View {
        Section("AI 接入边界") {
            if snapshot.visibility.viewerRole == .child {
                Text("AI 接入细节已隐藏，只保留下一步提示。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ai-lms-boundary-provider-details-hidden")
                LabeledContent("不直给答案", value: snapshot.provider.noDirectAnswer ? "是" : "否")
                    .accessibilityIdentifier("ai-lms-boundary-provider-no-direct-answer")
            } else {
                LabeledContent("模式", value: snapshot.provider.requestMode.label)
                    .accessibilityIdentifier("ai-lms-boundary-provider-mode")
                LabeledContent("请求", value: snapshot.provider.requestAllowed ? "允许预演" : "关闭")
                    .accessibilityIdentifier("ai-lms-boundary-provider-request")
                LabeledContent("AI 内容上限", value: "\(snapshot.provider.maxTokens)/\(snapshot.provider.tokenCeiling)")
                    .accessibilityIdentifier("ai-lms-boundary-provider-token-ceiling")
                LabeledContent("不直给答案", value: snapshot.provider.noDirectAnswer ? "是" : "否")
                    .accessibilityIdentifier("ai-lms-boundary-provider-no-direct-answer")
                LabeledContent("孩子可见接入细节", value: snapshot.provider.childSeesProviderDetails ? "会" : "不会")
                    .accessibilityIdentifier("ai-lms-boundary-provider-child-details")
            }
        }
    }

    private func lmsSection(_ snapshot: AIHomeworkSchoolLmsBoundarySnapshot) -> some View {
        Section("学校系统") {
            LabeledContent("模式", value: snapshot.lms.mode.label)
                .accessibilityIdentifier("ai-lms-boundary-lms-mode")
            LabeledContent("只读", value: snapshot.lms.lmsReadOnly ? "是" : "否")
                .accessibilityIdentifier("ai-lms-boundary-lms-read-only")
            LabeledContent("写成绩", value: snapshot.lms.writesGrade ? "会" : "不会")
                .accessibilityIdentifier("ai-lms-boundary-lms-writes-grade")
            LabeledContent("改作业", value: snapshot.lms.mutatesAssignment ? "会" : "不会")
                .accessibilityIdentifier("ai-lms-boundary-lms-mutates-assignment")
            LabeledContent("上传附件", value: snapshot.lms.uploadsAttachment ? "会" : "不会")
                .accessibilityIdentifier("ai-lms-boundary-lms-uploads-attachment")
        }
    }

    private func consentSection(_ snapshot: AIHomeworkSchoolLmsBoundarySnapshot) -> some View {
        Section("同意与授权") {
            if snapshot.visibility.canSeeConsentDetail {
                LabeledContent("家长同意", value: snapshot.consent.guardianConsentGranted ? "已具备" : "缺失")
                    .accessibilityIdentifier("ai-lms-boundary-consent-guardian")
                LabeledContent("孩子 assent", value: snapshot.consent.childAssentGranted ? "已具备" : "缺失")
                    .accessibilityIdentifier("ai-lms-boundary-consent-child")
                LabeledContent("老师授权", value: snapshot.consent.teacherAuthorized ? "已具备" : "缺失")
                    .accessibilityIdentifier("ai-lms-boundary-consent-teacher")
            } else if snapshot.visibility.canSeeTeacherDetail {
                LabeledContent("老师授权", value: snapshot.consent.teacherAuthorized ? "已具备" : "缺失")
                    .accessibilityIdentifier("ai-lms-boundary-consent-teacher")
                Text("家长和孩子同意细节仅家长可见。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ai-lms-boundary-consent-guardian-child-hidden")
            } else {
                Text("同意细节已隐藏，等家长或老师确认。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ai-lms-boundary-consent-details-hidden")
            }
        }
    }

    private func transcriptSection(_ snapshot: AIHomeworkSchoolLmsBoundarySnapshot) -> some View {
        Section("互动记录") {
            LabeledContent("留存", value: snapshot.transcript.retentionMode)
                .accessibilityIdentifier("ai-lms-boundary-transcript-retention")
            LabeledContent("家长摘要脱敏", value: snapshot.transcript.parentSummaryRedacted ? "是" : "否")
                .accessibilityIdentifier("ai-lms-boundary-transcript-parent-redacted")
            LabeledContent("老师摘要脱敏", value: snapshot.transcript.teacherSummaryRedacted ? "是" : "否")
                .accessibilityIdentifier("ai-lms-boundary-transcript-teacher-redacted")
            LabeledContent("保存原文", value: snapshot.transcript.storesRawTranscript ? "会" : "不会")
                .accessibilityIdentifier("ai-lms-boundary-transcript-stores-raw")
            LabeledContent("显示答案键", value: snapshot.transcript.revealsAnswerKey ? "会" : "不会")
                .accessibilityIdentifier("ai-lms-boundary-transcript-answer-key")
        }
    }

    private func auditSection(_ snapshot: AIHomeworkSchoolLmsBoundarySnapshot) -> some View {
        Section("审计事件") {
            LabeledContent("已链接", value: "\(snapshot.audit.linkedEventCount)")
                .accessibilityIdentifier("ai-lms-boundary-audit-linked")
            LabeledContent("缺失", value: "\(snapshot.audit.missingEventCount)")
                .accessibilityIdentifier("ai-lms-boundary-audit-missing")
            LabeledContent("写外部系统", value: snapshot.audit.writesExternalSystem ? "会" : "不会")
                .accessibilityIdentifier("ai-lms-boundary-audit-writes-external")
        }
    }

    private func findingsSection(_ snapshot: AIHomeworkSchoolLmsBoundarySnapshot) -> some View {
        Section("边界发现") {
            if snapshot.findings.isEmpty {
                Label("暂无发现", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
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
                    .accessibilityIdentifier("ai-lms-boundary-finding-\(finding.code.rawValue)")
                }
            }
        }
    }

    private func guardrailSection(_ snapshot: AIHomeworkSchoolLmsBoundarySnapshot) -> some View {
        Section("只读护栏") {
            LabeledContent("调用 AI/QWEN", value: (snapshot.publicSummary.callsAiProvider || snapshot.publicSummary.callsLocalModel) ? "会" : "不会")
                .accessibilityIdentifier("ai-lms-boundary-guardrail-ai-qwen")
            LabeledContent("调用网络/学校系统", value: (snapshot.publicSummary.callsNetwork || snapshot.publicSummary.callsLms) ? "会" : "不会")
                .accessibilityIdentifier("ai-lms-boundary-guardrail-network-lms")
            LabeledContent("写学校/账本", value: (snapshot.publicSummary.writesSchoolSystem || snapshot.publicSummary.writesLedger) ? "会" : "不会")
                .accessibilityIdentifier("ai-lms-boundary-guardrail-school-ledger")
            LabeledContent("通知/设备", value: (snapshot.publicSummary.sendsNotification || snapshot.publicSummary.unlocksDevice) ? "会" : "不会")
                .accessibilityIdentifier("ai-lms-boundary-guardrail-notification-device")
        }
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

    private func statusBadge(_ state: AIHomeworkSchoolLmsBoundaryState) -> some View {
        Text(state.label)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint(for: state).opacity(0.15), in: Capsule())
            .foregroundStyle(tint(for: state))
    }

    private func tint(for state: AIHomeworkSchoolLmsBoundaryState) -> Color {
        switch state {
        case .ready: return .green
        case .gated: return .orange
        case .blocked: return .red
        case .empty: return .secondary
        }
    }

    private func icon(for severity: AIHomeworkSchoolLmsBoundarySeverity) -> String {
        switch severity {
        case .ok: return "checkmark.circle"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .blocker: return "xmark.octagon"
        }
    }

    private func tint(for severity: AIHomeworkSchoolLmsBoundarySeverity) -> Color {
        switch severity {
        case .ok: return .green
        case .info: return .blue
        case .warning: return .orange
        case .blocker: return .red
        }
    }
}
