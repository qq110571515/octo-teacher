import SwiftUI

/// 手动布置任务的类型。选类型后表单出现对应字段（P5 类型驱动表单）。
enum ComposerTaskKind: String, CaseIterable, Identifiable {
    case general
    case reading
    case video
    case outdoor
    case handcraft

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "普通"
        case .reading: return "阅读"
        case .video: return "视频"
        case .outdoor: return "户外"
        case .handcraft: return "创作"
        }
    }

    var defaultCategory: TaskCategory {
        switch self {
        case .general: return .home
        case .reading, .video: return .learning
        case .outdoor: return .health
        case .handcraft: return .creative
        }
    }

    var supportsAdultSupervision: Bool {
        self == .outdoor || self == .handcraft
    }
}

enum ParentTaskStarterPreset: String, CaseIterable, Identifiable {
    case reading20
    case outdoorPlay
    case tidyDesk
    case sleepReady

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .reading20: return "先读 20 分钟"
        case .outdoorPlay: return "去户外玩一会儿"
        case .tidyDesk: return "整理书桌"
        case .sleepReady: return "睡前准备"
        }
    }

    func menuTitle(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return menuTitle }
        switch self {
        case .reading20: return "Read for 20 Minutes"
        case .outdoorPlay: return "Play Outside"
        case .tidyDesk: return "Tidy the Desk"
        case .sleepReady: return "Get Ready for Bed"
        }
    }

    var systemImage: String {
        switch self {
        case .reading20: return "book.closed"
        case .outdoorPlay: return "figure.outdoor.cycle"
        case .tidyDesk: return "square.grid.3x3"
        case .sleepReady: return "moon.zzz"
        }
    }

    var kind: ComposerTaskKind {
        switch self {
        case .reading20: return .reading
        case .outdoorPlay: return .outdoor
        case .tidyDesk, .sleepReady: return .general
        }
    }

    var title: String {
        switch self {
        case .reading20: return "读一本书 20 分钟"
        case .outdoorPlay: return "去院子或公园玩一会儿"
        case .tidyDesk: return "整理书桌"
        case .sleepReady: return "睡前准备"
        }
    }

    var instructions: String {
        switch self {
        case .reading20:
            return "安静读 20 分钟，读完用一句话说说今天看到的内容。"
        case .outdoorPlay:
            return "放下手机，到院子或公园活动 20 分钟；如果要出门，先告诉大人。"
        case .tidyDesk:
            return "把书放回书架，桌面只留下今天要用的文具。"
        case .sleepReady:
            return "刷牙、收好明天要带的东西，把手机交给家长充电。"
        }
    }

    var category: TaskCategory {
        switch self {
        case .reading20: return .learning
        case .outdoorPlay: return .health
        case .tidyDesk, .sleepReady: return .home
        }
    }

    var rewardMinutes: Int {
        switch self {
        case .reading20: return 15
        case .outdoorPlay: return 20
        case .tidyDesk: return 10
        case .sleepReady: return 10
        }
    }

    var requiredProof: ProofKind {
        switch self {
        case .outdoorPlay: return .photo
        case .reading20, .tidyDesk, .sleepReady: return .text
        }
    }

    var needsAdult: Bool {
        self == .outdoorPlay
    }

    var bookTitle: String {
        switch self {
        case .reading20: return "今天想读的书"
        case .outdoorPlay, .tidyDesk, .sleepReady: return ""
        }
    }

    var readingMinMinutes: Int {
        switch self {
        case .reading20: return 20
        case .outdoorPlay, .tidyDesk, .sleepReady: return 30
        }
    }

    var chapterPlanText: String {
        switch self {
        case .reading20: return "继续读 20 分钟"
        case .outdoorPlay, .tidyDesk, .sleepReady: return ""
        }
    }
}

/// 家长布置 / 编辑任务表单（类型驱动）。
///
/// 新建模式：选任务类型 → 填对应字段 → 布置。
/// 阅读类型支持粘贴书本链接让 AI 识别书名（只取书名，不抓内容）。
/// 编辑模式：仅 open / rejected 状态可修改；支持「AI 改一改」按意图重写草稿。
struct ParentTaskComposerView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(ParentAIProviderStore.self) private var aiProvider
    @Environment(FamilyCloudSessionStore.self) private var familyCloud
    @Environment(\.dismiss) private var dismiss

    /// 编辑模式下传入既有任务；nil 表示新建。
    let editingAssignment: TaskAssignment?

    @State private var kind: ComposerTaskKind
    @State private var title: String
    @State private var instructions: String
    @State private var category: TaskCategory
    @State private var rewardMinutes: Int
    @State private var requiredProof: ProofKind
    // 阅读
    @State private var bookLinkOrTitle: String
    @State private var readingMinMinutes: Int
    @State private var chapterPlanText: String
    @State private var isRecognizingBook = false
    // 视频
    @State private var videoURLString: String
    @State private var minWatchMinutes: Int
    // 动手
    @State private var needsAdult: Bool
    @State private var creativeKind: CreativeTaskKind
    @State private var creativePrompt: String
    @State private var creativeMaterials: String
    @State private var creativeEstimatedMinutes: Int
    // AI 改一改
    @State private var editIntent = ""
    @State private var isAIEditing = false
    @State private var feedback: String?
    @State private var isSaving = false
    // 重复属性（仅新建）
    @State private var recurrence: TaskRecurrence = .once
    @State private var weekday = Calendar.current.component(.weekday, from: Date())

    init(
        editingAssignment: TaskAssignment? = nil,
        starterPreset: ParentTaskStarterPreset? = nil,
        creativeStarterKind: CreativeTaskKind? = nil
    ) {
        self.editingAssignment = editingAssignment
        let task = editingAssignment?.task

        let inferredKind: ComposerTaskKind
        if task?.reading != nil {
            inferredKind = .reading
        } else if task?.video != nil {
            inferredKind = .video
        } else if task?.needsAdultSupervision == true && task?.category == .health {
            inferredKind = .outdoor
        } else if task?.creative != nil || task?.category == .creative {
            inferredKind = .handcraft
        } else {
            inferredKind = creativeStarterKind == nil ? (starterPreset?.kind ?? .general) : .handcraft
        }
        _kind = State(initialValue: inferredKind)
        _title = State(initialValue: task?.title ?? starterPreset?.title ?? "")
        _instructions = State(initialValue: task?.instructions ?? starterPreset?.instructions ?? "")
        _category = State(initialValue: task?.category ?? starterPreset?.category ?? inferredKind.defaultCategory)
        _rewardMinutes = State(initialValue: task?.rewardMinutes ?? starterPreset?.rewardMinutes ?? 15)
        _requiredProof = State(initialValue: task?.requiredProof ?? starterPreset?.requiredProof ?? .text)
        _bookLinkOrTitle = State(initialValue: task?.reading?.bookTitle ?? starterPreset?.bookTitle ?? "")
        _readingMinMinutes = State(initialValue: task?.reading?.minMinutes ?? starterPreset?.readingMinMinutes ?? 30)
        _chapterPlanText = State(initialValue: task?.reading?.chapterPlanText ?? starterPreset?.chapterPlanText ?? "")
        _videoURLString = State(initialValue: task?.video?.urlString ?? "")
        _minWatchMinutes = State(initialValue: task?.video?.minWatchMinutes ?? 15)
        _needsAdult = State(initialValue: task?.needsAdultSupervision ?? starterPreset?.needsAdult ?? false)
        let initialCreativeKind = task?.creative?.kind ?? creativeStarterKind ?? .handcraft
        _creativeKind = State(initialValue: initialCreativeKind)
        _creativePrompt = State(initialValue: task?.creative?.creativePrompt ?? initialCreativeKind.starterPrompt)
        _creativeMaterials = State(initialValue: task?.creative?.materials.joined(separator: "、") ?? initialCreativeKind.starterMaterials.joined(separator: "、"))
        _creativeEstimatedMinutes = State(initialValue: task?.creative?.estimatedMinutes ?? 30)
        if task == nil, let creativeStarterKind {
            _title = State(initialValue: creativeStarterKind.starterTitle)
            _instructions = State(initialValue: creativeStarterKind.starterPrompt)
            _category = State(initialValue: .creative)
            _requiredProof = State(initialValue: .photo)
            _needsAdult = State(initialValue: creativeStarterKind.needsAdultByDefault)
        }
    }

    private var isEditing: Bool { editingAssignment != nil }

    var body: some View {
        Form {
            kindSection
            contentSection
            if !isEditing {
                starterTemplateSection
            }
            qualityGuidanceSection
            kindSpecificSection
            rewardSection
            publishPreviewSection
            if isEditing, aiProvider.isReadyForAIComposer {
                aiEditSection
            }
            saveSection
        }
        .navigationTitle(isEditing ? "编辑任务" : "布置新任务")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 分区

    private var kindSection: some View {
        Section("任务类型") {
            Picker("类型", selection: $kind) {
                ForEach(ComposerTaskKind.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: kind) { _, newKind in
                category = newKind.defaultCategory
            }
            .accessibilityIdentifier("task-composer-kind")
        }
    }

    private var contentSection: some View {
        Section("任务内容") {
            TextField("任务名称，例如：练琴 20 分钟", text: $title)
                .accessibilityIdentifier("task-composer-title")
            TextField("给孩子的说明（怎么做、做到什么程度）", text: $instructions, axis: .vertical)
                .lineLimit(2...5)
                .accessibilityIdentifier("task-composer-instructions")
            Picker("类别", selection: $category) {
                ForEach(TaskCategory.allCases, id: \.self) { item in
                    Label(item.label, systemImage: item.systemImage).tag(item)
                }
            }
        }
    }

    private var starterTemplateSection: some View {
        Section {
            Button {
                applyStarterTemplate()
            } label: {
                Label("套用一个孩子能立刻开始的任务模板", systemImage: "wand.and.stars")
            }
            .accessibilityIdentifier("task-composer-apply-starter-template")

            Text(starterTemplatePreview)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("task-composer-starter-template-preview")
        } header: {
            Text("不会写时")
        } footer: {
            Text("模板只填草稿，你可以继续改成自家的真实任务。")
        }
    }

    private var qualityGuidanceSection: some View {
        Section {
            Label(qualityTitleMessage, systemImage: qualityTitleIsReady ? "checkmark.circle.fill" : "1.circle")
                .foregroundStyle(qualityTitleIsReady ? .green : .orange)
                .accessibilityIdentifier("task-composer-quality-title")
            Label(qualityInstructionMessage, systemImage: qualityInstructionIsReady ? "checkmark.circle.fill" : "2.circle")
                .foregroundStyle(qualityInstructionIsReady ? .green : .orange)
                .accessibilityIdentifier("task-composer-quality-instructions")
            Label(qualityProofMessage, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityIdentifier("task-composer-quality-proof")
        } header: {
            Text("任务质量检查")
        } footer: {
            Text("写成孩子能立刻行动的小任务：一句标题、一步做法、一个证明。")
        }
        .accessibilityIdentifier("task-composer-quality-guidance")
    }

    @ViewBuilder
    private var kindSpecificSection: some View {
        switch kind {
        case .reading:
            Section {
                TextField("书名，或粘贴图书链接", text: $bookLinkOrTitle, axis: .vertical)
                    .lineLimit(1...3)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("task-composer-book-title")
                if aiProvider.isReadyForAIComposer, bookLinkOrTitle.contains("http") {
                    Button {
                        Task { await recognizeBook() }
                    } label: {
                        Label(isRecognizingBook ? "AI 正在识别……" : "AI 识别这个链接的书", systemImage: "sparkles")
                    }
                    .disabled(isRecognizingBook)
                    .accessibilityIdentifier("task-composer-recognize-book")
                }
                Picker("最低阅读时长", selection: $readingMinMinutes) {
                    ForEach([15, 20, 30, 45, 60], id: \.self) { minutes in
                        Text("\(minutes) 分钟").tag(minutes)
                    }
                }
                TextField("本次读哪些章节，例如：第 1-2 章", text: $chapterPlanText, axis: .vertical)
                    .lineLimit(1...3)
                    .accessibilityIdentifier("task-composer-chapter-plan")
            } header: {
                Text("阅读设置")
            } footer: {
                Text("想让 AI 按整本书排出多次章节计划，用工作台里的「AI 布置阅读」。链接只用于识别书名，不会抓取内容。")
            }
        case .video:
            Section("视频设置") {
                TextField("粘贴视频链接（YouTube / Bilibili 等）", text: $videoURLString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("task-composer-video-url")
                Picker("至少看", selection: $minWatchMinutes) {
                    ForEach([10, 15, 20, 30], id: \.self) { minutes in
                        Text("\(minutes) 分钟").tag(minutes)
                    }
                }
            }
        case .outdoor:
            Section("户外设置") {
                Toggle("需要大人在场或先告知家长", isOn: $needsAdult)
            }
        case .handcraft:
            Section {
                Picker("创作类型", selection: $creativeKind) {
                    ForEach(CreativeTaskKind.allCases) { item in
                        Label(item.label, systemImage: item.systemImage).tag(item)
                    }
                }
                .onChange(of: creativeKind) { _, newKind in
                    title = newKind.starterTitle
                    instructions = newKind.starterPrompt
                    creativePrompt = newKind.starterPrompt
                    creativeMaterials = newKind.starterMaterials.joined(separator: "、")
                    needsAdult = newKind.needsAdultByDefault
                    requiredProof = .photo
                }
                TextField("创作提示", text: $creativePrompt, axis: .vertical)
                    .lineLimit(2...5)
                TextField("准备材料，用顿号分隔", text: $creativeMaterials, axis: .vertical)
                    .lineLimit(1...3)
                Picker("建议用时", selection: $creativeEstimatedMinutes) {
                    ForEach([10, 15, 20, 30, 45, 60, 90], id: \.self) { minutes in
                        Text("\(minutes) 分钟").tag(minutes)
                    }
                }
                Toggle("需要大人在场（用刀/火/电等）", isOn: $needsAdult)
            } header: {
                Text("创作设置")
            } footer: {
                Text("绘画、音乐、手工、积木、乐高、玩具、故事、摄影、黏土、表演、料理、自然创作、科学制作和数字创作都进入同一个作品闭环。")
            }
        case .general:
            EmptyView()
        }
    }

    private let weekdayNames = [1: "周日", 2: "周一", 3: "周二", 4: "周三", 5: "周四", 6: "周五", 7: "周六"]

    private var rewardSection: some View {
        Section {
            if !isEditing {
                Picker("重复", selection: $recurrence) {
                    ForEach(TaskRecurrence.allCases, id: \.self) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                if recurrence == .weekly {
                    Picker("每周几", selection: $weekday) {
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                            Text(weekdayNames[day] ?? "").tag(day)
                        }
                    }
                }
            }
            Picker("完成奖励", selection: $rewardMinutes) {
                ForEach([5, 10, 15, 20, 30, 45, 60], id: \.self) { points in
                    Text(GrowthCreditCopy.label(points: points)).tag(points)
                }
            }
            Picker("完成证明", selection: $requiredProof) {
                Text("写一句话").tag(ProofKind.text)
                Text("拍一张照片").tag(ProofKind.photo)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("奖励与证明")
        } footer: {
            Text("孩子完成并经你确认后获得成长积分；成长积分可以换屏幕时间、零花钱或愿望。")
        }
    }

    private var publishPreviewSection: some View {
        Section {
            Label(childPreviewTitle, systemImage: "iphone")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("task-composer-child-preview")
            LabeledContent("证明要求", value: proofPreviewLabel)
            LabeledContent("完成奖励", value: GrowthCreditCopy.label(points: rewardMinutes))
            if !isEditing {
                LabeledContent("重复方式", value: recurrencePreviewLabel)
            }
        } header: {
            Text("保存后孩子会看到")
        } footer: {
            Text(isEditing ? "保存后，孩子端未提交的任务会同步更新。" : "点保存后，这个任务会出现在孩子首页和今日任务里。")
        }
    }

    private var childPreviewTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "先填写任务名称" : "孩子首页会看到：\(trimmed)"
    }

    private var starterTemplatePreview: String {
        switch kind {
        case .general:
            return "例：整理书桌。说明：把书放回书架，桌面只留下今天要用的文具。"
        case .reading:
            return "例：读《夏洛的网》20 分钟。说明：读完后写一句最喜欢的情节。"
        case .video:
            return "例：看 15 分钟科学视频。说明：看完说出一个新发现；视频链接仍需你粘贴。"
        case .outdoor:
            return "例：去院子或公园玩 20 分钟。说明：出门前先告诉大人。"
        case .handcraft:
            return "例：画画、音乐、手工、积木、乐高、故事、摄影或科学制作。完成后拍作品并说说自己的想法。"
        }
    }

    private var qualityTitleIsReady: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 3
    }

    private var qualityInstructionIsReady: Bool {
        instructions.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8
    }

    private var qualityTitleMessage: String {
        qualityTitleIsReady ? "标题已经能让孩子看懂要做什么" : "先写清楚孩子要做的那件事"
    }

    private var qualityInstructionMessage: String {
        qualityInstructionIsReady ? "说明已经写到孩子能照着开始" : "再补一句怎么做、做到什么程度"
    }

    private var qualityProofMessage: String {
        switch requiredProof {
        case .text:
            return "孩子完成后写一句话或录语音给你确认"
        case .photoPlaceholder, .photo:
            return "孩子完成后拍一张照片给你确认"
        }
    }

    private var proofPreviewLabel: String {
        switch requiredProof {
        case .text: return "写一句话或录语音"
        case .photoPlaceholder, .photo: return "拍一张照片"
        }
    }

    private var recurrencePreviewLabel: String {
        switch recurrence {
        case .once:
            return "一次性"
        case .daily:
            return "每天自动生成"
        case .weekly:
            return "每\(weekdayNames[weekday] ?? "周")自动生成"
        }
    }

    private var aiEditSection: some View {
        Section {
            TextField("想怎么改？例如：降低难度 / 改成英文的", text: $editIntent)
                .accessibilityIdentifier("task-composer-ai-intent")
            Button {
                Task { await aiEdit() }
            } label: {
                Label(isAIEditing ? "AI 正在改……" : "AI 改一改", systemImage: "sparkles")
            }
            .disabled(isAIEditing || editIntent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("task-composer-ai-edit")
        } header: {
            Text("AI 改一改")
        } footer: {
            Text("AI 只改草稿，以你保存的为准。")
        }
    }

    private var saveSection: some View {
        Section {
            Button {
                Task { await save() }
            } label: {
                Label(
                    isSaving ? "正在准备孩子端内容……" : (isEditing ? "保存修改" : "布置给\(store.child.name)"),
                    systemImage: isSaving ? "hourglass" : "checkmark.circle"
                )
            }
            .disabled(!canSave || isSaving)
            .accessibilityIdentifier("task-composer-save")
        } footer: {
            if let feedback {
                Text(feedback)
            }
        }
    }

    // MARK: - 校验与构建

    private var canSave: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch kind {
        case .reading:
            return hasTitle && !bookLinkOrTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .video:
            let urlOK = URL(string: videoURLString.trimmingCharacters(in: .whitespacesAndNewlines))?.scheme?.hasPrefix("http") == true
            return hasTitle && urlOK
        case .general, .outdoor, .handcraft:
            return hasTitle
        }
    }

    private var readingSpec: ReadingSpec? {
        guard kind == .reading else { return nil }
        let book = bookLinkOrTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !book.isEmpty else { return nil }
        return ReadingSpec(
            bookTitle: book,
            minMinutes: readingMinMinutes,
            chapterPlanText: chapterPlanText.trimmingCharacters(in: .whitespacesAndNewlines),
            deliveryMode: .physicalManual
        )
    }

    private var videoSpec: VideoSpec? {
        guard kind == .video else { return nil }
        let url = videoURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }
        let platform = url.contains("bilibili") ? "Bilibili" : (url.contains("youtu") ? "YouTube" : "网页视频")
        return VideoSpec(urlString: url, platformLabel: platform, minWatchMinutes: minWatchMinutes)
    }

    private var creativeSpec: CreativeTaskSpec? {
        guard kind == .handcraft else { return nil }
        let materials = creativeMaterials
            .split(whereSeparator: { $0 == "、" || $0 == "," || $0 == "，" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return CreativeTaskSpec(
            kind: creativeKind,
            creativePrompt: creativePrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            materials: materials,
            estimatedMinutes: creativeEstimatedMinutes
        )
    }

    // MARK: - 动作

    private func recognizeBook() async {
        isRecognizingBook = true
        defer { isRecognizingBook = false }
        do {
            let raw = try await aiProvider.completeDraftJSON(
                system: AIBookLinkReader.systemPrompt(),
                user: AIBookLinkReader.userPrompt(linkOrText: bookLinkOrTitle),
                using: OpenAIStyleChatClient()
            )
            if let book = AIBookLinkReader.parse(raw) {
                bookLinkOrTitle = book
                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    title = "读《\(book)》"
                }
                feedback = "识别到：《\(book)》"
            } else {
                feedback = "没认出来这本书，直接填书名也可以。"
            }
        } catch {
            feedback = "识别失败，直接填书名也可以。"
        }
    }

    private func applyStarterTemplate() {
        category = kind.defaultCategory
        recurrence = .once
        switch kind {
        case .general:
            title = "整理书桌"
            instructions = "把书放回书架，桌面只留下今天要用的文具。完成后写一句：我整理好了。"
            rewardMinutes = 10
            requiredProof = .text
        case .reading:
            title = "读《夏洛的网》20 分钟"
            instructions = "安静读 20 分钟，读完写一句最喜欢的情节。"
            bookLinkOrTitle = "夏洛的网"
            readingMinMinutes = 20
            chapterPlanText = "今天继续读 20 分钟"
            rewardMinutes = 15
            requiredProof = .text
        case .video:
            title = "看 15 分钟科学视频"
            instructions = "只看家长选好的视频，结束后写下一个新发现。"
            videoURLString = ""
            minWatchMinutes = 15
            rewardMinutes = 10
            requiredProof = .text
        case .outdoor:
            title = "去院子或公园玩一会儿"
            instructions = "放下手机，到院子或公园活动 20 分钟；如果要出门，先告诉大人。"
            needsAdult = true
            rewardMinutes = 20
            requiredProof = .photo
        case .handcraft:
            creativeKind = .handcraft
            title = creativeKind.starterTitle
            instructions = creativeKind.starterPrompt
            creativePrompt = creativeKind.starterPrompt
            creativeMaterials = creativeKind.starterMaterials.joined(separator: "、")
            creativeEstimatedMinutes = 30
            needsAdult = creativeKind.needsAdultByDefault
            rewardMinutes = 20
            requiredProof = .photo
        }
        feedback = "已套用任务模板，可以继续修改后再保存。"
    }

    private func aiEdit() async {
        guard let task = editingAssignment?.task else { return }
        isAIEditing = true
        defer { isAIEditing = false }
        do {
            let digest = ChildMemoryDigestBuilder.digest(for: store.activeChildId, store: store)
            let raw = try await aiProvider.completeDraftJSON(
                system: AITaskEditor.systemPrompt(language: store.settings.language),
                user: AITaskEditor.userPrompt(task: task, intent: editIntent, digest: digest),
                using: OpenAIStyleChatClient()
            )
            if let draft = AITaskEditor.parse(raw, packType: task.packType) {
                title = draft.title
                instructions = draft.instructions
                category = draft.category
                rewardMinutes = draft.rewardPoints
                requiredProof = draft.requiredProof
                needsAdult = draft.adultSupervisionRequired || needsAdult
                feedback = "AI 改好了草稿，确认后点保存。"
            } else {
                feedback = "AI 这次没改出来，再试一次。"
            }
        } catch {
            feedback = "AI 修改失败（网络或密钥问题）。"
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let localizedContent: [TaskLocalizedContent]
        do {
            localizedContent = try await localizedContentForChild()
        } catch {
            feedback = "孩子界面使用另一种语言，任务还没有安全翻译。请先在软件设置里配置 AI API，再重新布置。"
            return
        }

        var didSaveLocally = false
        var savedAssignmentIDs: [UUID] = []
        if let editingAssignment {
            let updated = store.updateTask(
                assignmentId: editingAssignment.id,
                title: title,
                instructions: instructions,
                category: category,
                rewardMinutes: rewardMinutes,
                requiredProof: requiredProof,
                adultSupervisionRequired: kind.supportsAdultSupervision && needsAdult,
                reading: readingSpec,
                video: videoSpec,
                creative: creativeSpec,
                localizedContent: localizedContent
            )
            if updated {
                didSaveLocally = true
                savedAssignmentIDs = [editingAssignment.id]
            }
        } else if recurrence != .once {
            // 重复任务：登记规则并自动生成今天到期的实例。
            let assignmentIDsBeforeSave = Set(store.assignments.map(\.id))
            let template = TaskTemplate(
                id: UUID(),
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category,
                difficulty: .easy,
                rewardMinutes: rewardMinutes,
                instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines),
                requiredProof: requiredProof,
                adultSupervisionRequired: (kind.supportsAdultSupervision && needsAdult) ? true : nil,
                reading: readingSpec,
                video: videoSpec,
                creative: creativeSpec,
                localizedContent: localizedContent
            )
            if store.addRecurringRule(template: template, recurrence: recurrence, weekday: weekday) != nil {
                didSaveLocally = true
                savedAssignmentIDs = store.assignments
                    .map(\.id)
                    .filter { !assignmentIDsBeforeSave.contains($0) }
            }
        } else {
            if let created = store.assignNewTask(
                title: title,
                instructions: instructions,
                category: category,
                rewardMinutes: rewardMinutes,
                requiredProof: requiredProof,
                adultSupervisionRequired: kind.supportsAdultSupervision && needsAdult,
                reading: readingSpec,
                video: videoSpec,
                creative: creativeSpec,
                localizedContent: localizedContent
            ) {
                didSaveLocally = true
                savedAssignmentIDs = [created.id]
            }
        }
        guard didSaveLocally else {
            feedback = "任务没有保存，请检查内容后重试。"
            return
        }
        if familyCloud.isGuardianSignedIn,
           !savedAssignmentIDs.isEmpty,
           !familyCloud.queueGuardianTaskUpserts(assignmentIds: savedAssignmentIDs, local: store) {
            feedback = "任务已保存在本机，但还没有进入家庭云同步队列。请检查家庭云登录后重试。"
            return
        }
        dismiss()
    }

    @MainActor
    private func localizedContentForChild() async throws -> [TaskLocalizedContent] {
        let target = store.settings.resolvedChildInterfaceLanguage
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        var content = editingAssignment?.task.localizedContent ?? []
        content.removeAll { $0.language == target }

        if !AITaskTranslator.needsTranslation(
            title: cleanTitle,
            instructions: cleanInstructions,
            target: target
        ) {
            content.append(TaskLocalizedContent(
                language: target,
                title: cleanTitle,
                instructions: cleanInstructions
            ))
            return content
        }

        guard aiProvider.isReadyForAIComposer else { throw AIChatError.notConfigured }
        let raw = try await aiProvider.completeDraftJSON(
            system: AITaskTranslator.systemPrompt(target: target),
            user: AITaskTranslator.userPrompt(title: cleanTitle, instructions: cleanInstructions),
            using: OpenAIStyleChatClient()
        )
        guard let translated = AITaskTranslator.parse(raw, language: target) else {
            throw AIChatError.badResponse
        }
        content.append(translated)
        return content
    }
}
