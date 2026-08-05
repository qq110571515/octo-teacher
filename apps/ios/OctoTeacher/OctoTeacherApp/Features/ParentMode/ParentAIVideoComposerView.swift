import SwiftUI

/// 待家长确认的视频条目：AI 推荐（带简介）先进列表，家长找到真实链接后逐条确认布置。
private struct PendingVideoItem: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var blurb: String
    var channel: String
    var searchQuery: String
    var urlString: String = ""
    var contentSummary: String = ""

    var youtubeSearchURL: URL? {
        var components = URLComponents(string: "https://www.youtube.com/results")
        components?.queryItems = [URLQueryItem(name: "search_query", value: searchQuery)]
        return components?.url
    }
}

/// AI 布置视频学习 v2：33 个适龄类别 → AI 推荐（含内容简介）→
/// 加入待确认列表 → 家长贴上真实链接确认 → 布置。
/// 视频计入对应学科徽章；孩子看完批准后可考试（题量按视频长度 5-30 题自适应）。
struct ParentAIVideoComposerView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(ParentAIProviderStore.self) private var aiProvider
    @Environment(FamilyCloudSessionStore.self) private var familyCloud
    @Environment(\.dismiss) private var dismiss

    @State private var category: VideoCategory = .scienceExperiments
    @State private var contentLanguage: FamilyLanguage?
    @State private var topic = ""
    @State private var suggestions: [VideoSuggestionDraft] = []
    @State private var pending: [PendingVideoItem] = []
    @State private var isSuggesting = false
    @State private var analyzingVideoIds: Set<UUID> = []
    @State private var minWatchMinutes = 15
    @State private var rewardMinutes = 15
    @State private var feedback: String?

    var body: some View {
        Form {
            targetSection
            suggestSection
            pendingSection
            manualSection
        }
        .navigationTitle("布置视频学习")
        .navigationBarTitleDisplayMode(.inline)
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
                        Text("\(member.name)（\(member.age) 岁）").tag(member.id)
                    }
                }
            } else {
                LabeledContent("布置给", value: "\(store.child.name)（\(store.child.age) 岁）")
            }
            Picker("类别（\(VideoCategory.allCases.count) 类）", selection: $category) {
                ForEach(VideoCategory.allCases) { item in
                    Text("\(item.rawValue)（\(item.ageHint)）").tag(item)
                }
            }
            .accessibilityIdentifier("ai-video-category")
            Picker("内容语言", selection: $contentLanguage) {
                Text("跟随家庭设置").tag(FamilyLanguage?.none)
                Text("中文").tag(FamilyLanguage?.some(.chinese))
                Text("English").tag(FamilyLanguage?.some(.english))
            }
        } footer: {
            Text("这个类别的视频计入「\(category.subject.label)」学科徽章；看完批准后可以考试（5-30 题，按视频长度自动定）。")
        }
    }

    private var suggestSection: some View {
        Section {
            TextField("想看什么？（选填，例如：火山是怎么喷发的）", text: $topic)
            if aiProvider.isReadyForAIComposer {
                Button {
                    Task { await suggest() }
                } label: {
                    if isSuggesting {
                        Label("AI 正在挑视频……", systemImage: "sparkles")
                    } else {
                        Label(suggestions.isEmpty ? "让 AI 推荐" : "换一批", systemImage: "sparkles")
                    }
                }
                .disabled(isSuggesting)
                .accessibilityIdentifier("ai-video-suggest")
            } else {
                Label("AI 助手未就绪，可在下面手动贴链接布置", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(suggestions) { suggestion in
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.title)
                        .font(.subheadline.weight(.semibold))
                    if !suggestion.reason.isEmpty {
                        Text(suggestion.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !suggestion.channel.isEmpty {
                        Text("频道：\(suggestion.channel)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        addToPending(suggestion)
                    } label: {
                        Label("加入待确认列表", systemImage: "plus.circle.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("ai-video-add-pending")
                }
                .padding(.vertical, 3)
            }
        } header: {
            Text("第一步：AI 推荐（含内容简介）")
        }
    }

    private var pendingSection: some View {
        Section {
            if pending.isEmpty {
                Text("从上面把想要的视频加进来。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach($pending) { $item in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title.isEmpty ? "（手动添加的视频）" : item.title)
                            .font(.subheadline.weight(.semibold))
                        if !item.blurb.isEmpty {
                            Text(item.blurb)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        NavigationLink {
                            ParentVideoFinderView(
                                startURL: item.youtubeSearchURL ?? URL(string: "https://www.youtube.com")!
                            ) { picked in
                                item.urlString = picked.absoluteString
                            }
                        } label: {
                            Label("在 App 里找到它（自动抓链接）", systemImage: "magnifyingglass.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.blue)
                        }
                        TextField("或手动粘贴视频链接", text: $item.urlString)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.caption)
                        TextField("家长确认的学习摘要（用于孩子复述评分）", text: $item.contentSummary, axis: .vertical)
                            .lineLimit(2...5)
                            .font(.caption)
                        Button {
                            Task { await analyzeVideoContent(item.id) }
                        } label: {
                            Label(
                                analyzingVideoIds.contains(item.id) ? "AI 正在起草验收摘要……" : "AI 起草学习验收摘要",
                                systemImage: "sparkles"
                            )
                            .font(.caption.weight(.semibold))
                        }
                        .disabled(analyzingVideoIds.contains(item.id))
                        .buttonStyle(.borderless)
                        Button {
                            confirm(item)
                        } label: {
                            Label(
                                isValidURL(item.urlString) ? "✅ 确认并布置给\(store.child.name)" : "先找到视频链接",
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isValidURL(item.urlString))
                        .accessibilityIdentifier("ai-video-confirm")
                    }
                    .padding(.vertical, 3)
                }
                .onDelete { pending.remove(atOffsets: $0) }
            }
            Picker("至少看", selection: $minWatchMinutes) {
                ForEach([10, 15, 20, 30, 45], id: \.self) { minutes in
                    Text("\(minutes) 分钟").tag(minutes)
                }
            }
            Picker("完成奖励", selection: $rewardMinutes) {
                ForEach([10, 15, 20, 30], id: \.self) { points in
                    Text(GrowthCreditCopy.label(points: points)).tag(points)
                }
            }
        } header: {
            Text("第二步：待确认列表（\(pending.count)）")
        } footer: {
            if let feedback {
                Text(feedback)
            } else {
                Text("每个视频都要你亲自确认过内容合适；左滑可移除。")
            }
        }
    }

    private var manualSection: some View {
        Section("或者直接贴链接") {
            Button {
                pending.append(
                    PendingVideoItem(title: "", blurb: "", channel: "", searchQuery: "")
                )
            } label: {
                Label("手动添加一个视频", systemImage: "link.badge.plus")
            }
        }
    }

    // MARK: - 动作

    private func isValidURL(_ string: String) -> Bool {
        URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))?.scheme?.hasPrefix("http") == true
    }

    private func addToPending(_ suggestion: VideoSuggestionDraft) {
        guard !pending.contains(where: { $0.title == suggestion.title }) else { return }
        pending.append(
            PendingVideoItem(
                title: suggestion.title,
                blurb: suggestion.reason,
                channel: suggestion.channel,
                searchQuery: suggestion.searchQuery,
                contentSummary: suggestion.reason
            )
        )
        feedback = "已加入待确认列表，去找到真实链接贴回来。"
    }

    private func suggest() async {
        isSuggesting = true
        defer { isSuggesting = false }
        do {
            let raw = try await aiProvider.completeDraftJSON(
                system: AIVideoSuggester.systemPrompt(),
                user: AIVideoSuggester.userPrompt(
                    subject: "\(category.rawValue)（适龄 \(category.ageHint)，内容语言：\((contentLanguage ?? store.activeContentLanguage).label)）",
                    topic: topic,
                    childAge: store.child.age
                ),
                using: OpenAIStyleChatClient()
            )
            let parsed = AIVideoSuggester.parse(raw)
            if parsed.isEmpty {
                feedback = "AI 这次没给出建议，再试一次。"
            } else {
                suggestions = parsed
                feedback = nil
            }
        } catch {
            feedback = "AI 推荐失败（网络或密钥问题）。"
        }
    }

    private func confirm(_ item: PendingVideoItem) {
        let url = item.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let platform = url.contains("bilibili") ? "Bilibili" : (url.contains("youtu") ? "YouTube" : "网页视频")
        let title = item.title.isEmpty ? "看视频学习" : item.title
        let created = store.assignNewTask(
            title: title,
            instructions: item.blurb.isEmpty
                ? "认真看完视频（至少 \(minWatchMinutes) 分钟），然后用自己的话说说学到了什么。"
                : "\(item.blurb) 认真看完后用自己的话说说学到了什么。",
            category: .learning,
            rewardMinutes: rewardMinutes,
            requiredProof: .text,
            video: VideoSpec(
                urlString: url,
                platformLabel: platform,
                minWatchMinutes: minWatchMinutes,
                subjectRaw: category.subject.rawValue,
                contentSummary: item.contentSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : item.contentSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            verification: item.contentSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : .retell(
                    summary: item.contentSummary.trimmingCharacters(in: .whitespacesAndNewlines),
                    seconds: 180,
                    contentKind: category.subject == .math ? .math : .knowledge
                )
        )
        if let created {
            if familyCloud.isGuardianSignedIn,
               !familyCloud.queueGuardianTaskUpsert(assignmentId: created.id, local: store) {
                feedback = "任务已保存在本机，但还没有进入家庭云同步队列。"
                return
            }
            pending.removeAll { $0.id == item.id }
            feedback = "已布置「\(title)」，计入\(category.subject.label)徽章。"
        }
    }

    private func analyzeVideoContent(_ itemId: UUID) async {
        guard let index = pending.firstIndex(where: { $0.id == itemId }) else { return }
        analyzingVideoIds.insert(itemId)
        defer { analyzingVideoIds.remove(itemId) }
        let item = pending[index]
        do {
            let raw = try await aiProvider.completeDraftJSON(
                system: AIVideoLearningAnalyzer.systemPrompt(),
                user: AIVideoLearningAnalyzer.userPrompt(
                    title: item.title.isEmpty ? "手动添加的视频" : item.title,
                    channel: item.channel,
                    blurb: item.blurb,
                    urlString: item.urlString,
                    childAge: store.child.age
                ),
                using: OpenAIStyleChatClient()
            )
            if let summary = AIVideoLearningAnalyzer.parse(raw),
               let latest = pending.firstIndex(where: { $0.id == itemId }) {
                pending[latest].contentSummary = summary
                feedback = "AI 已起草摘要，请你确认或修改后再布置。"
            } else {
                feedback = "AI 没生成摘要，你可以手动写两三句话。"
            }
        } catch {
            feedback = "AI 摘要失败；你可以手动写两三句话作为验收依据。"
        }
    }
}
