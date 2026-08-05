import SwiftUI

/// 孩子端 AI 作业引导会话壳。
///
/// 孩子选择/输入作业问题后，看到苏格拉底式分步提示、追问、自检清单和下一步。
/// 全部内容由本地 `AIHomeworkGuidanceSessionBuilder` 确定性派生：不接真实 AI、网络、
/// 学校系统、通知、账本或设备，绝不给作业答案，也绝不留存原始输入文本。
struct AIHomeworkGuidanceSessionView: View {
    @Environment(SchoolFamilyStore.self) private var store
    let homeworkId: UUID

    @State private var messages: [AIHomeworkSessionMessage] = []
    @State private var draft: String = ""

    private let builder = AIHomeworkGuidanceSessionBuilder()

    private var homework: SchoolHomework? {
        store.homeworks.first(where: { $0.id == homeworkId })
    }

    private var snapshot: AIHomeworkGuidanceSessionSnapshot {
        builder.build(viewerRole: .child, homework: homework, messages: messages)
    }

    var body: some View {
        Group {
            if homework == nil {
                ContentUnavailableView("作业不存在", systemImage: "questionmark.folder")
            } else {
                content
            }
        }
        .navigationTitle("AI 作业引导")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var content: some View {
        let current = snapshot
        return List {
            headerSection(current)
            if current.header.status == .blocked {
                blockedSection(current)
            } else {
                stepsSection(current)
                followUpSection(current)
                checklistSection(current)
                askSection
            }
            assuranceSection(current)
        }
    }

    private func headerSection(_ snapshot: AIHomeworkGuidanceSessionSnapshot) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label(snapshot.subjectLabel, systemImage: homework?.subject.systemImage ?? "book")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Text(snapshot.topicLabel)
                    .font(.title3.bold())
                if let intent = snapshot.currentIntentLabel {
                    Text("你问的是：\(intent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func stepsSection(_ snapshot: AIHomeworkGuidanceSessionSnapshot) -> some View {
        if !snapshot.steps.isEmpty {
            Section("一步一步想") {
                ForEach(snapshot.steps) { step in
                    Label {
                        Text(step.prompt).font(.subheadline)
                    } icon: {
                        Image(systemName: step.kind.systemImage)
                            .foregroundStyle(tint(for: step.kind))
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private func followUpSection(_ snapshot: AIHomeworkGuidanceSessionSnapshot) -> some View {
        if !snapshot.followUps.isEmpty {
            Section("还可以继续问我") {
                ForEach(Array(snapshot.followUps.enumerated()), id: \.offset) { index, followUp in
                    Button {
                        send(.init(freeText: followUp))
                    } label: {
                        Label(followUp, systemImage: "arrow.turn.down.right")
                            .font(.subheadline)
                    }
                    .accessibilityIdentifier("ai-homework-followup-\(index)")
                }
            }
        }
    }

    @ViewBuilder
    private func checklistSection(_ snapshot: AIHomeworkGuidanceSessionSnapshot) -> some View {
        if !snapshot.checklist.isEmpty || !snapshot.nextStep.isEmpty {
            Section("提交前自检") {
                ForEach(Array(snapshot.checklist.enumerated()), id: \.offset) { _, item in
                    Label {
                        Text(item).font(.subheadline)
                    } icon: {
                        Image(systemName: "checklist").foregroundStyle(.blue)
                    }
                }
                if !snapshot.nextStep.isEmpty {
                    Label {
                        Text(snapshot.nextStep).font(.subheadline)
                    } icon: {
                        Image(systemName: "arrow.forward.circle").foregroundStyle(.green)
                    }
                }
            }
        }
    }

    private var askSection: some View {
        Section {
            ForEach(AIHomeworkPresetQuestion.allCases, id: \.self) { preset in
                Button {
                    send(.init(preset: preset))
                } label: {
                    Label(preset.label, systemImage: "questionmark.bubble")
                        .font(.subheadline)
                }
                .accessibilityIdentifier("ai-homework-preset-\(preset.rawValue)")
            }
            HStack {
                TextField("也可以打字问我（不会帮你写答案）", text: $draft, axis: .vertical)
                    .lineLimit(1...3)
                    .accessibilityIdentifier("ai-homework-free-text")
                Button {
                    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    send(.init(freeText: text))
                    draft = ""
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("ai-homework-send-free-text")
            }
        } header: {
            Text("问问 AI")
        } footer: {
            Text("AI 只会给你提示和思路，陪你自己想出答案，不会直接告诉你答案。")
        }
    }

    private func blockedSection(_ snapshot: AIHomeworkGuidanceSessionSnapshot) -> some View {
        Section {
            Label(snapshot.assurance, systemImage: "hand.raised")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func assuranceSection(_ snapshot: AIHomeworkGuidanceSessionSnapshot) -> some View {
        Section {
            Label(snapshot.assurance, systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func send(_ message: AIHomeworkSessionMessage) {
        messages.append(message)
    }

    private func tint(for kind: AIHomeworkStepKind) -> Color {
        switch kind {
        case .probe: return .purple
        case .hint: return .yellow
        case .check: return .blue
        }
    }
}

/// 家长/老师端 AI 作业引导会话脱敏摘要 Section。
///
/// 只展示脱敏意图标签、风险标签和是否需要人工介入，看不到引导步骤明细、孩子原话、
/// 答案、内部风险评分数值或模型/供应商细节。会话样例为本地确定性 mock。
struct AIHomeworkGuidanceCareSection: View {
    let viewerRole: AIHomeworkSessionViewerRole
    let homeworks: [SchoolHomework]
    /// 本地 mock 会话样例：把若干作业映射到一组确定性会话输入，方便家长/老师只读查看。
    let sampleMessages: [UUID: [AIHomeworkSessionMessage]]

    private let builder = AIHomeworkGuidanceSessionBuilder()

    var body: some View {
        Section {
            if homeworks.isEmpty {
                Text("还没有作业引导会话")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(homeworks) { homework in
                    let snapshot = builder.build(
                        viewerRole: viewerRole,
                        homework: homework,
                        messages: sampleMessages[homework.id] ?? []
                    )
                    if let summary = snapshot.careSummary {
                        CareSummaryRow(status: snapshot.header.status, summary: summary)
                    }
                }
            }
        } header: {
            Text("AI 作业引导会话（脱敏摘要）")
        } footer: {
            Text("只看脱敏摘要、风险标签和是否需要人工介入；看不到孩子原话、答案或引导步骤明细。")
        }
    }
}

private struct CareSummaryRow: View {
    let status: AIHomeworkSessionStatus
    let summary: AIHomeworkSessionCareSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(summary.subjectLabel) · \(summary.topicLabel)")
                    .font(.subheadline.bold())
                Spacer()
                if summary.needsHumanIntervention {
                    Label("建议跟进", systemImage: "exclamationmark.bubble")
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                }
            }
            Text("提问 \(summary.messageCount) 次 · \(status.label)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !summary.riskLabels.isEmpty {
                HStack(spacing: 6) {
                    ForEach(summary.riskLabels, id: \.self) { label in
                        Text(label.label)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(riskTint(label.severity).opacity(0.15), in: Capsule())
                            .foregroundStyle(riskTint(label.severity))
                    }
                }
            }
            Text(summary.recommendedAction)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func riskTint(_ severity: AIHomeworkSeverity) -> Color {
        switch severity {
        case .ok: return .green
        case .info: return .blue
        case .warning: return .orange
        case .blocker: return .red
        }
    }
}
