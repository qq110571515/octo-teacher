import SwiftUI

struct SchoolMailRecognitionView: View {
    @Environment(LocalFamilyStore.self) private var store
    let childID: UUID
    let onConfirmed: () -> Void

    private var lang: AppInterfaceLanguage { store.settings.resolvedParentInterfaceLanguage }

    var body: some View {
        Form {
            SchoolMailAssistView(childID: childID, onConfirmed: onConfirmed)
        }
        .navigationTitle(lang.pick("识别学校邮件", "Analyze School Email"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SchoolMailAssistView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(ParentAIProviderStore.self) private var aiProvider
    @Environment(GrowthMemoryStore.self) private var growthMemory

    let childID: UUID
    let onConfirmed: () -> Void

    @State private var pastedMail = ""
    @State private var findings: [SchoolMailFinding] = []
    @State private var analysisMessage: String?
    @State private var isAnalyzing = false

    private var lang: AppInterfaceLanguage { store.settings.resolvedParentInterfaceLanguage }

    var body: some View {
        mailSection
        if !findings.isEmpty {
            findingSection
        }
    }

    private var mailSection: some View {
        Section {
            LabeledContent(lang.pick("邮箱连接", "Mailbox Connection"), value: lang.pick("尚未连接", "Not connected"))
                .accessibilityIdentifier("school-mode-mail-connection")
            Text(lang.pick(
                "自动扫描需要 Google 或 Microsoft 的只读 OAuth 授权。当前版本不会假装已经读取邮箱；可先粘贴一封学校邮件做同样的识别与确认。",
                "Automatic scanning needs read-only Google or Microsoft OAuth. This build never pretends it read your inbox; paste one school email to use the same review flow now."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            TextEditor(text: $pastedMail)
                .frame(minHeight: 130)
                .accessibilityIdentifier("school-mode-mail-text")
            Button {
                analyzeMail()
            } label: {
                if isAnalyzing {
                    ProgressView()
                } else {
                    Label(lang.pick("AI 识别这封学校邮件", "Analyze This School Email"), systemImage: "sparkles")
                }
            }
            .disabled(isAnalyzing || pastedMail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("school-mode-analyze-mail")

            if let analysisMessage {
                Text(analysisMessage)
                    .font(.caption)
                    .foregroundStyle(findings.isEmpty ? Color.orange : Color.secondary)
            }
        } header: {
            Text(lang.pick("学校邮件识别", "School Mail Recognition"))
        } footer: {
            Text(lang.pick(
                "邮件原文只在当前输入框和本次 AI 请求中存在；识别后立即清空，家庭文件只保存家长确认过的结构化摘要。",
                "The email body exists only in this field and the current AI request. It is cleared after analysis; the family file stores only parent-confirmed structured summaries."
            ))
        }
    }

    private var findingSection: some View {
        Section {
            ForEach(findings) { finding in
                VStack(alignment: .leading, spacing: 4) {
                    Label(finding.title, systemImage: findingIcon(finding.category))
                        .font(.subheadline.weight(.semibold))
                    Text(finding.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let date = finding.dateKey {
                        Text(scheduleDetail(finding, date: date))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                }
            }
            Button {
                recordMemories(findings)
                store.confirmSchoolMailFindings(findings, for: childID)
                findings = []
                onConfirmed()
                analysisMessage = lang.pick("已保存到本机学校动态。", "Saved to on-device school updates.")
            } label: {
                Label(lang.pick("家长确认并保存全部", "Parent Confirm and Save All"), systemImage: "checkmark.shield")
            }
            .accessibilityIdentifier("school-mode-confirm-findings")
        } header: {
            Text(lang.pick("待家长确认", "Parent Review Required"))
        }
    }

    private func analyzeMail() {
        let text = pastedMail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard aiProvider.isReadyForAIComposer else {
            analysisMessage = lang.pick("请先在软件设置里配置家长 AI 服务。", "Set up the parent AI service in App Settings first.")
            return
        }
        isAnalyzing = true
        findings = []
        analysisMessage = nil
        Task {
            do {
                let raw = try await aiProvider.completeDraftJSON(
                    system: SchoolMailAnalyzer.systemPrompt(
                        language: lang,
                        childNames: store.children.map(\.name)
                    ),
                    user: SchoolMailAnalyzer.userPrompt(emailText: text),
                    using: OpenAIStyleChatClient()
                )
                let parsed = SchoolMailAnalyzer.parse(raw)
                findings = parsed
                pastedMail = ""
                analysisMessage = parsed.isEmpty
                    ? lang.pick("没有识别到可确认的学校信息。", "No confirmable school information was found.")
                    : lang.pick("识别完成，保存前请逐项核对。", "Analysis complete. Review every item before saving.")
                isAnalyzing = false
            } catch {
                pastedMail = ""
                analysisMessage = AICloudFailureDiagnosis.describe(error, language: lang)
                isAnalyzing = false
            }
        }
    }

    private func scheduleDetail(_ finding: SchoolMailFinding, date: String) -> String {
        if finding.category == .holiday { return lang.pick("\(date) 全天不锁定", "\(date) no school restriction") }
        guard finding.category == .schedule else { return date }
        if let start = finding.startMinutes, let end = finding.endMinutes {
            return "\(date) · \(clockText(start))–\(clockText(end))"
        }
        return lang.pick(
            "\(date) · 邮件无完整时间，将采用家长默认时段",
            "\(date) · No complete hours; parent defaults will be used"
        )
    }

    private func clockText(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private func recordMemories(_ items: [SchoolMailFinding]) {
        for finding in items {
            let event = GrowthMemoryEventFactory.schoolDynamic(
                childId: childID,
                category: finding.category,
                title: finding.title,
                schoolName: finding.schoolName
            )
            let duplicate = growthMemory.events(for: childID).contains {
                $0.kind == .schoolDynamic && $0.summary == event.summary
            }
            if !duplicate { growthMemory.record(event) }
        }
    }

    private func findingIcon(_ category: SchoolDynamicCategory) -> String {
        switch category {
        case .schedule: return "calendar.badge.clock"
        case .holiday: return "sun.max"
        case .grade: return "chart.bar"
        case .teacherFeedback: return "person.text.rectangle"
        case .attendance: return "person.badge.clock"
        case .activity: return "figure.run"
        }
    }
}
