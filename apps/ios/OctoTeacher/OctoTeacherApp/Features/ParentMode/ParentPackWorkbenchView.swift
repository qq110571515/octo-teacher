import SwiftUI

/// 包工作台：每个任务包的统一操作台。
///
/// 三个入口：AI 一键生成（用孩子的记忆摘要个性化）、模板勾选、手动添加；
/// 底部显示本包已布置的任务。AI 不可用时生成入口降级隐藏，模板和手动始终可用。
enum ParentPackWorkbenchCopy {
    static func rewardLabel(points: Int) -> String {
        GrowthCreditCopy.label(points: points)
    }
}

struct ParentPackWorkbenchView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(ParentAIProviderStore.self) private var aiProvider
    @Environment(FamilyCloudSessionStore.self) private var familyCloud

    let group: PackTemplateGroup

    @State private var generateCount = 4
    @State private var contentLanguage: FamilyLanguage?
    @State private var drafts: [GeneratedTaskDraft] = []
    @State private var selectedDraftIds: Set<UUID> = []
    @State private var isGenerating = false
    @State private var isComposingManually = false
    @State private var isAddingCustomTemplate = false
    @State private var feedback: String?

    var body: some View {
        List {
            targetSection
            aiGenerateSection
            otherWaysSection
            assignedSection
        }
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isComposingManually) {
            NavigationStack {
                ParentTaskComposerView()
            }
        }
        .sheet(isPresented: $isAddingCustomTemplate) {
            NavigationStack {
                ParentCustomPackTemplateEditorView(packType: group.packType)
            }
        }
    }

    // MARK: - 分区

    private var targetSection: some View {
        Section {
            if store.hasMultipleChildren {
                Picker("布置给谁", selection: Binding(
                    get: { store.activeChildId },
                    set: { store.setActiveChild($0) }
                )) {
                    ForEach(store.children) { member in
                        Text(member.name).tag(member.id)
                    }
                }
            } else {
                LabeledContent("布置给", value: store.child.name)
            }
            Stepper(
                store.defaultPoints(for: group.packType) == nil
                    ? "本包默认分值：按各任务建议"
                    : "本包默认分值：每个任务 \(store.defaultPoints(for: group.packType)!) 分",
                value: Binding(
                    get: { store.defaultPoints(for: group.packType) ?? 0 },
                    set: { store.setPackDefaultPoints($0, for: group.packType) }
                ),
                in: 0...60,
                step: 5
            )
            .font(.subheadline)
        } footer: {
            Text(group.summary + " 设了默认分值后，模板和 AI 生成的任务都按该分值布置；调到 0 恢复按各任务建议。")
        }
    }

    private var aiGenerateSection: some View {
        Section {
            if aiProvider.isReadyForAIComposer {
                Picker("内容语言", selection: $contentLanguage) {
                    Text("跟随家庭设置").tag(FamilyLanguage?.none)
                    Text("中文").tag(FamilyLanguage?.some(.chinese))
                    Text("English").tag(FamilyLanguage?.some(.english))
                }
                Stepper("生成 \(generateCount) 个任务", value: $generateCount, in: 2...6)
                Button {
                    Task { await generate() }
                } label: {
                    if isGenerating {
                        Label("AI 正在按\(store.child.name)的情况设计……", systemImage: "sparkles")
                    } else {
                        Label(drafts.isEmpty ? "AI 生成任务（用 TA 的记忆）" : "换一批", systemImage: "sparkles")
                    }
                }
                .disabled(isGenerating)
                .accessibilityIdentifier("pack-workbench-generate")
            } else {
                Label("配置 AI 助手后可一键生成个性化任务", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(drafts) { draft in
                Button {
                    toggleDraft(draft)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: selectedDraftIds.contains(draft.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedDraftIds.contains(draft.id) ? Color.accentColor : Color.secondary)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(draft.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if draft.adultSupervisionRequired {
                                    Label("需大人在场", systemImage: "figure.and.child.holdinghands")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                            if !draft.instructions.isEmpty {
                                Text(draft.instructions)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 10) {
                                Label(ParentPackWorkbenchCopy.rewardLabel(points: draft.rewardPoints), systemImage: "star")
                                if let reading = draft.reading {
                                    Label("《\(reading.bookTitle)》\(reading.chapterPlanText)", systemImage: "book")
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            if !drafts.isEmpty {
                Button {
                    assignSelected()
                } label: {
                    Text(selectedDraftIds.isEmpty ? "先勾选上面的草稿" : "布置所选的 \(selectedDraftIds.count) 个任务")
                        .frame(maxWidth: .infinity)
                }
                .disabled(selectedDraftIds.isEmpty)
                .accessibilityIdentifier("pack-workbench-assign")
            }
        } header: {
            Text("AI 生成")
        } footer: {
            if let feedback {
                Text(feedback)
            } else if aiProvider.isReadyForAIComposer {
                Text("AI 会参考 TA 的年龄、兴趣、阅读进度和最近完成的任务，每次生成都不一样。")
            }
        }
    }

    private var otherWaysSection: some View {
        Section("其它方式") {
            NavigationLink {
                ParentPackGroupDetailView(group: group)
            } label: {
                Label("从模板勾选（\(store.templates(for: group.packType).count) 个）", systemImage: "square.grid.2x2")
            }
            if group.packType.supportsCustomTemplates {
                Button {
                    isAddingCustomTemplate = true
                } label: {
                    Label("添加自定义任务类型", systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("pack-workbench-add-custom-template")
            }
            Button {
                isComposingManually = true
            } label: {
                Label("手动添加任务", systemImage: "plus.circle")
            }
        }
    }

    private var assignedSection: some View {
        let mine = store.assignments.filter {
            $0.childId == store.activeChildId && $0.task.packType == group.packType
        }
        return Section {
            if mine.isEmpty {
                Text("这个包还没给\(store.child.name)布置过任务。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(mine) { assignment in
                    HStack {
                        Text(assignment.task.title)
                            .font(.subheadline)
                        Spacer()
                        Text(ParentPackWorkbenchCopy.rewardLabel(points: assignment.task.rewardMinutes))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("本包已布置（\(mine.count)）")
        }
    }

    // MARK: - 动作

    private func toggleDraft(_ draft: GeneratedTaskDraft) {
        if selectedDraftIds.contains(draft.id) {
            selectedDraftIds.remove(draft.id)
        } else {
            selectedDraftIds.insert(draft.id)
        }
    }

    private func generate() async {
        isGenerating = true
        defer { isGenerating = false }
        do {
            let digest = ChildMemoryDigestBuilder.digest(for: store.activeChildId, store: store)
            let raw = try await aiProvider.completeDraftJSON(
                system: AIPackTaskGenerator.systemPrompt(packType: group.packType, language: contentLanguage ?? store.activeContentLanguage),
                user: AIPackTaskGenerator.userPrompt(digest: digest, count: generateCount),
                using: OpenAIStyleChatClient()
            )
            let parsed = AIPackTaskGenerator.parse(raw, packType: group.packType)
            if parsed.isEmpty {
                feedback = "AI 这次没生成出来，再试一次或用模板。"
            } else {
                drafts = parsed
                selectedDraftIds = Set(parsed.map(\.id))
                feedback = nil
            }
        } catch {
            feedback = "AI 生成失败（网络或密钥问题），可以用模板或手动添加。"
        }
    }

    private func assignSelected() {
        let picked = drafts.filter { selectedDraftIds.contains($0.id) }
        let assignmentIDsBeforeSave = Set(store.assignments.map(\.id))
        let count = store.assignGeneratedDrafts(picked, packType: group.packType)
        let createdAssignmentIDs = store.assignments.map(\.id).filter { !assignmentIDsBeforeSave.contains($0) }
        if familyCloud.isGuardianSignedIn,
           !createdAssignmentIDs.isEmpty,
           !familyCloud.queueGuardianTaskUpserts(assignmentIds: createdAssignmentIDs, local: store) {
            feedback = "任务已保存在本机，但还没有进入家庭云同步队列。"
            return
        }
        feedback = "已布置 \(count) 个任务。"
        drafts.removeAll { selectedDraftIds.contains($0.id) }
        selectedDraftIds.removeAll()
    }
}

/// 家庭自定义任务包模板：保存后会出现在对应任务包的「从模板勾选」里。
struct ParentCustomPackTemplateEditorView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let packType: PackType

    @State private var title = ""
    @State private var instructions = ""
    @State private var expectedMinutes = 20
    @State private var rewardPoints = 15
    @State private var requiredProof: ProofKind = .text
    @State private var adultSupervisionRequired = false
    @State private var feedback: String?

    var body: some View {
        Form {
            Section {
                TextField(titlePlaceholder, text: $title)
                    .accessibilityIdentifier("custom-template-title")
                TextField("给孩子看的说明（可选）", text: $instructions, axis: .vertical)
                    .lineLimit(2...4)
                    .accessibilityIdentifier("custom-template-instructions")
                Stepper("预计 \(expectedMinutes) 分钟", value: $expectedMinutes, in: 5...180, step: 5)
                Stepper("\(rewardPoints) 成长积分", value: $rewardPoints, in: 5...60, step: 5)
                Picker("完成证明", selection: $requiredProof) {
                    ForEach([ProofKind.text, .photo], id: \.self) { proof in
                        Text(proof.label).tag(proof)
                    }
                }
                Toggle("需要大人在场", isOn: $adultSupervisionRequired)
            } header: {
                Text("自定义 \(packType.label)")
            } footer: {
                Text(packType.customTemplatePrompt)
            }

            Section {
                Button {
                    save()
                } label: {
                    Text("保存到这个任务包")
                        .frame(maxWidth: .infinity)
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("custom-template-save")
            } footer: {
                if let feedback {
                    Text(feedback)
                } else {
                    Text("保存后不会马上布置给孩子；回到模板列表勾选后再安排。")
                }
            }
        }
        .navigationTitle("添加自定义任务")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .onAppear {
            if packType == .outdoorSports {
                adultSupervisionRequired = true
                requiredProof = .photo
                expectedMinutes = 30
                rewardPoints = 20
            }
        }
    }

    private var titlePlaceholder: String {
        switch packType {
        case .basicHabits:
            return "例如：自己整理洗澡用品"
        case .chores:
            return "例如：给植物浇水"
        case .outdoorSports:
            return "例如：跳绳 15 分钟"
        default:
            return "任务类型"
        }
    }

    private func save() {
        guard store.addCustomPackTemplate(
            packType: packType,
            title: title,
            instructions: instructions,
            expectedMinutes: expectedMinutes,
            rewardPoints: rewardPoints,
            requiredProof: requiredProof,
            adultSupervisionRequired: adultSupervisionRequired
        ) != nil else {
            feedback = "没有保存成功，请检查标题。"
            return
        }
        feedback = "已保存到\(packType.label)。"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            dismiss()
        }
    }
}
