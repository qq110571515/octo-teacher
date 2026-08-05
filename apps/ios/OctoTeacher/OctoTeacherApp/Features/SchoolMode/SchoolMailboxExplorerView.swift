import SwiftUI

private struct SchoolMailboxFindingDraft: Identifiable {
    var finding: SchoolMailFinding
    var childID: UUID?
    var id: UUID { finding.id }
}

/// 家长学校邮箱的隐私优先工作台。
/// Gmail OAuth 未配置前只开放人工批量粘贴；页面永不伪造邮箱扫描结果。
struct SchoolMailboxExplorerView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(ParentAIProviderStore.self) private var aiProvider
    @Environment(GrowthMemoryStore.self) private var growthMemory

    @State private var pastedMailBatch = ""
    @State private var drafts: [SchoolMailboxFindingDraft] = []
    @State private var isAnalyzing = false
    @State private var message: String?
    @State private var lastAnalyzedAt: Date?

    private var lang: AppInterfaceLanguage { store.settings.resolvedParentInterfaceLanguage }

    var body: some View {
        Form {
            connectionSection
            overviewSection
            importSection
            resultSection
            privacySection
        }
        .navigationTitle(lang.pick("学校邮件洞察", "School Mail Insights"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var connectionSection: some View {
        Section {
            NavigationLink {
                SchoolMailboxAuthorizationView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "envelope.badge.shield.half.filled")
                        .foregroundStyle(.blue)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(lang.pick("连接 Gmail（只读）", "Connect Gmail (Read Only)"))
                            .font(.headline)
                        Text(lang.pick(
                            "尚未配置 Google OAuth；可先用下方人工批量导入验证分析闭环。",
                            "Google OAuth is not configured yet. Use manual batch import below to verify the analysis flow."
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityIdentifier("school-mail-connect-gmail")
        } header: {
            Text(lang.pick("邮箱授权", "Mailbox Authorization"))
        }
    }

    private var overviewSection: some View {
        Section {
            ForEach(store.children) { child in
                let records = store.schoolDynamics(for: child.id)
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(child.name).font(.subheadline.weight(.semibold))
                        Text(schoolSummary(records))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(lang.pick("\(records.count) 条", "\(records.count)"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.blue)
                }
            }
            if let lastAnalyzedAt {
                LabeledContent(
                    lang.pick("最近分析", "Last Analysis"),
                    value: lastAnalyzedAt.formatted(date: .abbreviated, time: .shortened)
                )
            }
        } header: {
            Text(lang.pick("孩子与学校", "Children & Schools"))
        } footer: {
            Text(lang.pick(
                "打开本页前已经保存的摘要会直接显示；正式邮箱连接后，后台扫描也会写入相同的本机摘要模型。",
                "Previously saved summaries appear immediately. Once mail is connected, background scans will write to the same on-device summary model."
            ))
        }
    }

    private var importSection: some View {
        Section {
            TextEditor(text: $pastedMailBatch)
                .frame(minHeight: 170)
                .accessibilityIdentifier("school-mail-batch-text")
            Text(lang.pick(
                "可以粘贴多封邮件；用一行“---”分隔。AI 会识别学校、孩子、成绩、出勤、老师反馈、活动和日期。",
                "Paste multiple messages and separate them with a line containing “---”. AI identifies schools, children, grades, attendance, teacher feedback, activities, and dates."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                analyzeBatch()
            } label: {
                if isAnalyzing {
                    ProgressView()
                } else {
                    Label(lang.pick("AI 探索这些学校邮件", "Explore These School Emails"), systemImage: "sparkles")
                }
            }
            .disabled(isAnalyzing || pastedMailBatch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("school-mail-analyze-batch")
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(drafts.isEmpty ? Color.orange : Color.secondary)
            }
        } header: {
            Text(lang.pick("批量探索", "Batch Exploration"))
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if !drafts.isEmpty {
            Section {
                ForEach($drafts) { $draft in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Label(draft.finding.title, systemImage: icon(draft.finding.category))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if let school = draft.finding.schoolName {
                                Text(school)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.blue)
                            }
                        }
                        Text(draft.finding.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker(lang.pick("归属孩子", "Child"), selection: $draft.childID) {
                            Text(lang.pick("需要家长选择", "Choose a child")).tag(Optional<UUID>.none)
                            ForEach(store.children) { child in
                                Text(child.name).tag(Optional(child.id))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Button {
                    confirmDrafts()
                } label: {
                    Label(lang.pick("确认归属并保存学校动态", "Confirm and Save School Updates"), systemImage: "checkmark.shield.fill")
                }
                .disabled(drafts.contains { $0.childID == nil })
                .accessibilityIdentifier("school-mail-confirm-batch")
            } header: {
                Text(lang.pick("AI 已分析 · 待确认归属", "Analyzed · Confirm Assignment"))
            } footer: {
                Text(lang.pick(
                    "能明确归属孩子的脱敏摘要已自动写入本机；需要家长选择孩子的项目会在确认后写入。只有点击确认后，日期类结果才会改变学校模式时间表。",
                    "Redacted summaries with a clear child match are already stored on-device. Items that need a child assignment are stored after confirmation. Date findings affect School Mode only after confirmation."
                ))
            }
        }
    }

    private var privacySection: some View {
        Section {
            Label(lang.pick("只读，不发送、不删除、不归档邮件", "Read only — never send, delete, or archive mail"), systemImage: "hand.raised.fill")
            Label(lang.pick("不保存邮件正文、地址、消息 ID 或附件", "No email bodies, addresses, message IDs, or attachments are retained"), systemImage: "lock.doc.fill")
            Label(lang.pick("可以撤销授权并删除全部学校摘要", "Authorization can be revoked and school summaries deleted"), systemImage: "trash.slash")
        } header: {
            Text(lang.pick("隐私边界", "Privacy Boundary"))
        }
    }

    private func analyzeBatch() {
        let text = pastedMailBatch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard aiProvider.isReadyForAIComposer else {
            message = lang.pick("请先在软件设置中连接家长 AI 服务。", "Connect the parent AI service in App Settings first.")
            return
        }
        isAnalyzing = true
        drafts = []
        message = nil
        Task {
            do {
                let raw = try await aiProvider.completeDraftJSON(
                    system: SchoolMailAnalyzer.systemPrompt(language: lang, childNames: store.children.map(\.name)),
                    user: SchoolMailAnalyzer.userPrompt(emailText: text),
                    using: OpenAIStyleChatClient()
                )
                let findings = SchoolMailAnalyzer.parse(raw)
                drafts = findings.map { finding in
                    SchoolMailboxFindingDraft(
                        finding: finding,
                        childID: matchedChildID(for: finding.childNameHint)
                    )
                }
                recordAutomaticMemories(from: drafts)
                pastedMailBatch = ""
                lastAnalyzedAt = Date()
                message = findings.isEmpty
                    ? lang.pick("没有识别到可靠的学校信息。", "No reliable school information was found.")
                    : lang.pick("分析完成。已保存脱敏成长记忆，请确认每条信息属于哪个孩子。", "Analysis complete. Redacted growth memory was saved; confirm which child each item belongs to.")
            } catch {
                pastedMailBatch = ""
                message = AICloudFailureDiagnosis.describe(error, language: lang)
            }
            isAnalyzing = false
        }
    }

    private func matchedChildID(for hint: String?) -> UUID? {
        if let hint {
            let normalized = hint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let child = store.children.first(where: {
                $0.name.lowercased() == normalized || normalized.contains($0.name.lowercased())
            }) {
                return child.id
            }
        }
        return store.children.count == 1 ? store.children[0].id : nil
    }

    private func recordAutomaticMemories(from items: [SchoolMailboxFindingDraft]) {
        for item in items {
            guard let childID = item.childID else { continue }
            let event = GrowthMemoryEventFactory.schoolDynamic(
                childId: childID,
                category: item.finding.category,
                title: item.finding.title,
                schoolName: item.finding.schoolName
            )
            let duplicate = growthMemory.events(for: childID).contains {
                $0.kind == .schoolDynamic && $0.summary == event.summary
            }
            if !duplicate { growthMemory.record(event) }
        }
    }

    private func confirmDrafts() {
        recordAutomaticMemories(from: drafts)
        let grouped = Dictionary(grouping: drafts.compactMap { draft -> (UUID, SchoolMailFinding)? in
            guard let childID = draft.childID else { return nil }
            return (childID, draft.finding)
        }, by: { $0.0 })
        for (childID, pairs) in grouped {
            store.confirmSchoolMailFindings(pairs.map(\.1), for: childID)
        }
        drafts = []
        message = lang.pick("已按孩子保存到本机学校动态。", "Saved to each child's on-device school updates.")
    }

    private func schoolSummary(_ records: [SchoolDynamicRecord]) -> String {
        let schools = Array(Set(records.compactMap(\.schoolName))).sorted()
        if schools.isEmpty {
            return records.isEmpty
                ? lang.pick("还没有学校邮件摘要", "No school mail summaries yet")
                : lang.pick("学校名称待识别", "School name not identified")
        }
        return schools.joined(separator: " · ")
    }

    private func icon(_ category: SchoolDynamicCategory) -> String {
        switch category {
        case .schedule: return "calendar.badge.clock"
        case .holiday: return "sun.max.fill"
        case .grade: return "chart.bar.fill"
        case .teacherFeedback: return "person.text.rectangle"
        case .attendance: return "person.badge.clock"
        case .activity: return "figure.run"
        }
    }
}

private struct SchoolMailboxAuthorizationView: View {
    @Environment(LocalFamilyStore.self) private var store
    private var lang: AppInterfaceLanguage { store.settings.resolvedParentInterfaceLanguage }

    var body: some View {
        Form {
            Section {
                LabeledContent(lang.pick("当前状态", "Status"), value: lang.pick("尚未配置", "Not configured"))
                LabeledContent(lang.pick("计划权限", "Planned Scope"), value: "gmail.readonly")
                LabeledContent(lang.pick("访问方式", "Access Mode"), value: lang.pick("家长 OAuth 授权", "Guardian OAuth"))
            } header: {
                Text(lang.pick("Gmail 连接", "Gmail Connection"))
            }
            Section {
                Text(lang.pick(
                    "正式启用前需要 Google Cloud OAuth 客户端、回调地址、隐私政策和敏感权限审核。章鱼老师 只申请只读邮件权限，不申请发送、删除、归档或修改权限。",
                    "Production use requires a Google Cloud OAuth client, redirect configuration, privacy policy, and sensitive-scope verification. Octo Teacher requests read-only mail access and never requests send, delete, archive, or modify access."
                ))
            } header: {
                Text(lang.pick("上线要求", "Release Requirements"))
            }
            Section {
                Label(lang.pick("只提取学校相关邮件", "Only school-related mail is processed"), systemImage: "line.3.horizontal.decrease.circle")
                Label(lang.pick("原文仅用于当次分析", "Bodies are used only for the current analysis"), systemImage: "doc.badge.clock")
                Label(lang.pick("长期只保存结构化摘要", "Only structured summaries are retained"), systemImage: "externaldrive.badge.checkmark")
            } header: {
                Text(lang.pick("数据最小化", "Data Minimization"))
            }
        }
        .navigationTitle(lang.pick("Gmail 只读授权", "Gmail Read-Only Access"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
