import SwiftUI

/// iOS 测验练习 / 自检工作台。
///
/// 只消费本地 mock 和脱敏意图，不展示答案、不保存作答、不判分、不上传、不发成长积分。
struct MobileQuizSelfCheckPracticeWorkbenchView: View {
    @State private var role: MobileQuizSelfCheckViewerRole
    private let allowedRoles: [MobileQuizSelfCheckViewerRole]
    private let draft: CreatorManifestPreviewDraft
    private let messages: [AIHomeworkSessionMessage]

    init(
        initialRole: MobileQuizSelfCheckViewerRole = .child,
        allowedRoles: [MobileQuizSelfCheckViewerRole] = MobileQuizSelfCheckViewerRole.allCases,
        draft: CreatorManifestPreviewDraft = .growthPackContentPlayerMock,
        messages: [AIHomeworkSessionMessage] = []
    ) {
        let normalized = Self.normalizedRoles(allowedRoles)
        let resolvedRole = normalized.contains(initialRole) ? initialRole : normalized[0]
        _role = State(initialValue: resolvedRole)
        self.allowedRoles = normalized
        self.draft = draft
        self.messages = messages
    }

    private var workbench: MobileQuizSelfCheckPracticeWorkbench {
        MobileQuizSelfCheckPracticeBuilder().build(role: role, draft: draft, messages: messages)
    }

    var body: some View {
        List {
            roleSection
            overviewSection
            promptSection
            proofSection
            riskSection
            sideEffectSection
        }
        .navigationTitle("测验自检")
        .navigationBarTitleDisplayMode(.inline)
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
            Text(workbench.note)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var overviewSection: some View {
        Section(workbench.title) {
            Text(workbench.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            QuizMetric(title: "练习题", value: workbench.publicSummary.promptCount, systemImage: "questionmark.square")
            QuizMetric(title: "自检项", value: workbench.publicSummary.selfCheckCount, systemImage: "checklist")
            QuizMetric(title: "证明要求", value: workbench.publicSummary.proofRequirementCount, systemImage: "checkmark.shield")
            if role == .guardian {
                QuizMetric(title: "需复核", value: workbench.publicSummary.guardianReviewCount, systemImage: "person.badge.shield.checkmark")
                QuizMetric(title: "直接答案风险", value: workbench.publicSummary.directAnswerRiskCount, systemImage: "hand.raised")
            }
        }
    }

    private var promptSection: some View {
        Section("练习与自检") {
            if workbench.prompts.isEmpty {
                ContentUnavailableView("暂无可练习测验", systemImage: "lock")
            } else {
                ForEach(workbench.prompts) { prompt in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: "questionmark.square")
                                .foregroundStyle(tint(for: prompt.status))
                                .frame(width: 22)
                            Text(prompt.title)
                                .font(.subheadline.bold())
                            Spacer()
                            Text(prompt.status.label)
                                .font(.caption2.bold())
                                .foregroundStyle(tint(for: prompt.status))
                        }
                        Text(prompt.prompt)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Label(prompt.answerFormat.label, systemImage: "text.bubble")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ForEach(prompt.selfCheckItems, id: \.self) { item in
                            Label(item, systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Label(prompt.nextStep, systemImage: "arrow.forward.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private var proofSection: some View {
        Section("证明边界") {
            if workbench.proofs.isEmpty {
                Text("暂无测验证明要求")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(workbench.proofs) { proof in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(proof.title, systemImage: "checkmark.shield")
                            .font(.subheadline.bold())
                        Text(proof.instructions)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("验证角色：\(proof.verifierLabels.joined(separator: " / "))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var riskSection: some View {
        Section("家长边界") {
            if workbench.risks.isEmpty {
                Text(role == .child ? "孩子视角不展示家长风险" : "暂无风险提示")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(workbench.risks) { risk in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(risk.title).font(.subheadline.bold())
                            Text(risk.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: risk.actionRequired ? "exclamationmark.shield" : "checkmark.shield")
                            .foregroundStyle(risk.actionRequired ? .orange : .green)
                    }
                }
            }
        }
    }

    private var sideEffectSection: some View {
        Section("执行边界") {
            QuizBoundaryFlag(title: "答案/答案键", value: workbench.publicSummary.revealsAnswerKey || workbench.publicSummary.givesDirectAnswer)
            QuizBoundaryFlag(title: "保存作答", value: workbench.publicSummary.storesRawAnswer)
            QuizBoundaryFlag(title: "自动判分", value: workbench.publicSummary.autoGrades)
            QuizBoundaryFlag(title: "网络/AI/学校", value: workbench.publicSummary.callsNetwork || workbench.publicSummary.callsAIProvider || workbench.publicSummary.callsSchoolSystem)
            QuizBoundaryFlag(title: "上传/账本/成长积分/设备", value: workbench.publicSummary.uploadsProof || workbench.publicSummary.writesLedger || workbench.publicSummary.grantsCredit || workbench.publicSummary.unlocksDevice)
        }
    }

    private func tint(for status: MobileQuizSelfCheckStatus) -> Color {
        switch status {
        case .practiceOnly, .selfCheck: return .blue
        case .needsReflection, .guardianReview: return .orange
        case .blocked: return .red
        }
    }

    private static func normalizedRoles(
        _ roles: [MobileQuizSelfCheckViewerRole]
    ) -> [MobileQuizSelfCheckViewerRole] {
        let source = roles.isEmpty ? MobileQuizSelfCheckViewerRole.allCases : roles
        return MobileQuizSelfCheckViewerRole.allCases.filter { source.contains($0) }
    }
}

private struct QuizMetric: View {
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

private struct QuizBoundaryFlag: View {
    let title: String
    let value: Bool

    var body: some View {
        LabeledContent(title) {
            Text(value ? "会触发" : "不触发")
                .foregroundStyle(value ? .red : .green)
        }
    }
}
