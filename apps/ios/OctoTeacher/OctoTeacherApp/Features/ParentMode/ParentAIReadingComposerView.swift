import SwiftUI
import UniformTypeIdentifiers

enum ReadingAssignmentBookPolicy {
    static func canAssign(
        fileIsReady: Bool,
        hasRemoteHTTPSSource: Bool,
        familyConnected: Bool
    ) -> Bool {
        guard fileIsReady else { return false }
        return !familyConnected || hasRemoteHTTPSSource
    }
}

enum ParentAIReadingComposerCopy {
    static func recommendationSystemPrompt(
        contentLanguage: FamilyLanguage,
        parentInterfaceLanguage: AppInterfaceLanguage
    ) -> String {
        AIBookRecommender.systemPrompt(
            language: contentLanguage,
            parentLanguage: parentInterfaceLanguage == .english ? .english : .chinese
        )
    }

    static func readingPlanSystemPrompt(parentInterfaceLanguage: AppInterfaceLanguage) -> String {
        let base = AIReadingPlanner.systemPrompt()
        guard parentInterfaceLanguage == .english else { return base }
        return base + """

        Parent-facing output language requirement: intro, sessions[].chapters, and sessions[].note must all be written in English. Use labels such as "Chapters 1-2" or "Pages 10-25". This requirement overrides the earlier Chinese chapter-label example.
        """
    }

    static func childTaskLanguage(
        contentLanguage: FamilyLanguage,
        interfaceLanguage: AppInterfaceLanguage
    ) -> AppInterfaceLanguage {
        switch contentLanguage {
        case .chinese: return .chinese
        case .english: return .english
        case .bilingual: return interfaceLanguage
        }
    }

    static func childTaskTitle(
        bookTitle: String,
        order: Int,
        language: AppInterfaceLanguage
    ) -> String {
        language.pick("读《\(bookTitle)》第 \(order) 次", "Read \(bookTitle): Session \(order)")
    }

    static func childTaskInstructions(
        note: String,
        language: AppInterfaceLanguage
    ) -> String {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        switch language {
        case .chinese:
            if trimmedNote.isEmpty || containsLatin(trimmedNote) {
                return "读完后用自己的话说说这一段讲了什么、你最喜欢哪里。不限时，读懂最重要。"
            }
            return "\(trimmedNote) 读完后用自己的话说说学到了什么。"
        case .english:
            let guidance = "After reading, explain in your own words what happened and what you liked most. Take your time; understanding matters most."
            return trimmedNote.isEmpty || containsHan(trimmedNote) ? guidance : "\(trimmedNote) \(guidance)"
        }
    }

    static func childChapterPlan(
        _ chapters: String,
        order: Int,
        sessionCount: Int,
        language: AppInterfaceLanguage
    ) -> String {
        let trimmed = chapters.trimmingCharacters(in: .whitespacesAndNewlines)
        switch language {
        case .chinese:
            guard !trimmed.isEmpty, !containsLatin(trimmed) else {
                return "第 \(order) 次阅读（共 \(sessionCount) 次）"
            }
            return trimmed
        case .english:
            guard !trimmed.isEmpty else { return "Reading session \(order) of \(sessionCount)" }
            guard containsHan(trimmed) else { return trimmed }
            if let range = numericRange(in: trimmed, unit: "章") {
                return range.lower == range.upper
                    ? "Chapter \(range.lower)"
                    : "Chapters \(range.lower)-\(range.upper)"
            }
            if let range = numericRange(in: trimmed, unit: "页") {
                return range.lower == range.upper
                    ? "Page \(range.lower)"
                    : "Pages \(range.lower)-\(range.upper)"
            }
            if let range = numericRange(in: trimmed, unit: "段") {
                return range.lower == range.upper
                    ? "Section \(range.lower)"
                    : "Sections \(range.lower)-\(range.upper)"
            }
            return "Reading session \(order) of \(sessionCount)"
        }
    }

    static func parentLocalizedDrafts(
        _ drafts: [ReadingSessionDraft],
        language: AppInterfaceLanguage
    ) -> [ReadingSessionDraft] {
        guard language == .english else { return drafts }
        return drafts.map { draft in
            var localized = draft
            localized.chapters = childChapterPlan(
                draft.chapters,
                order: draft.order,
                sessionCount: drafts.count,
                language: .english
            )
            localized.note = parentDraftNote(draft.note, language: .english)
            return localized
        }
    }

    static func parentDraftNote(_ note: String, language: AppInterfaceLanguage) -> String {
        guard language == .english, containsHan(note) else { return note }
        switch note {
        case "按家长指定次数均衡划分 EPUB 真实章节。":
            return "Balanced across the ebook's actual chapters using the parent's session count."
        case "幼儿图文书按每两章一次自动划分。":
            return "Picture-book plan with two chapters per reading session."
        case "按每次约 5,000-10,000 词均衡划分 EPUB 真实章节。":
            return "Balanced across the ebook's actual chapters at about 5,000-10,000 words per session."
        default:
            return "The app created a balanced plan using the ebook's actual structure."
        }
    }

    private static func numericRange(in value: String, unit: String) -> (lower: String, upper: String)? {
        let pattern = #"第\s*(\d+)\s*(?:[-–—至到]\s*(\d+)\s*)?"# + NSRegularExpression.escapedPattern(for: unit)
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let lowerRange = Range(match.range(at: 1), in: value) else { return nil }
        let lower = String(value[lowerRange])
        let upper: String
        if match.range(at: 2).location != NSNotFound,
           let upperRange = Range(match.range(at: 2), in: value) {
            upper = String(value[upperRange])
        } else {
            upper = lower
        }
        return (lower, upper)
    }

    private static func containsHan(_ value: String) -> Bool {
        value.range(of: #"\p{Han}"#, options: .regularExpression) != nil
    }

    private static func containsLatin(_ value: String) -> Bool {
        value.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
    }

    static func categoryTitle(_ category: BookCategory, language: AppInterfaceLanguage) -> String {
        guard language == .english else { return category.rawValue }
        switch category {
        case .alphabet: return "Alphabet Basics"
        case .numbers: return "Numbers & Early Math"
        case .colorsShapes: return "Colors & Shapes"
        case .nurseryRhymes: return "Nursery Rhymes"
        case .habitPicture: return "Habit-Building Picture Books"
        case .emotionPicture: return "Emotional Learning Picture Books"
        case .classicFairy: return "Classic Fairy Tales"
        case .fables: return "Fables & Idiom Stories"
        case .bridgeBooks: return "Early Chapter Books"
        case .childrenLiterature: return "Children's Classics"
        case .scienceEncyclopedia: return "Science & Encyclopedias"
        case .dinosaurNature: return "Dinosaurs & Nature"
        case .spaceUniverse: return "Space & the Universe"
        case .historyStories: return "History Stories"
        case .biography: return "Biographies"
        case .detectiveAdventure: return "Mystery & Adventure"
        case .fantasyMagic: return "Fantasy & Magic"
        case .scienceFiction: return "Science Fiction"
        case .poetryProse: return "Poetry & Prose"
        case .englishGraded: return "English Graded Readers"
        case .comicScience: return "Science Comics"
        case .growthPsychology: return "Psychology & Growing Up"
        case .safetyEducation: return "Safety & Self-Protection"
        case .traditionalCulture: return "Traditional Culture & Festivals"
        case .artMusic: return "Art & Music"
        case .teenNovel: return "Young Adult Novels"
        }
    }

    static func categoryAgeHint(_ category: BookCategory, language: AppInterfaceLanguage) -> String {
        guard language == .english else { return category.ageHint }
        switch category {
        case .alphabet, .numbers, .colorsShapes, .nurseryRhymes: return "Ages 3-6"
        case .habitPicture, .emotionPicture, .classicFairy: return "Ages 3-8"
        case .fables, .bridgeBooks: return "Ages 6-9"
        case .childrenLiterature, .scienceEncyclopedia, .dinosaurNature, .spaceUniverse,
             .historyStories, .detectiveAdventure, .comicScience, .safetyEducation,
             .traditionalCulture, .artMusic: return "Ages 6-12"
        case .biography, .fantasyMagic, .poetryProse, .englishGraded, .growthPsychology: return "Ages 8-14"
        case .scienceFiction, .teenNovel: return "Ages 10-16"
        }
    }

    static func verificationModeLabel(_ mode: TaskVerificationMode, language: AppInterfaceLanguage) -> String {
        switch mode {
        case .choiceQuiz: return language.pick("选择题小测", "Multiple-choice quiz")
        case .voiceRetell: return language.pick("语音复述", "Voice retelling")
        case .learningDrill: return language.pick("识字/数学练习", "Literacy / math practice")
        }
    }

    static func contentKindLabel(_ kind: TaskVerificationContentKind, language: AppInterfaceLanguage) -> String {
        switch kind {
        case .story: return language.pick("故事理解", "Story comprehension")
        case .knowledge: return language.pick("知识理解", "Knowledge comprehension")
        case .literacy: return language.pick("识字/字母", "Literacy / letters")
        case .math: return language.pick("数学练习", "Math practice")
        }
    }

    static func growthPoints(_ points: Int, language: AppInterfaceLanguage) -> String {
        language.pick("\(points) 成长积分", "\(points) Growth Points")
    }

    static func acquisitionTitle(_ option: BookMarketLinks.AcquisitionOption, language: AppInterfaceLanguage) -> String {
        guard language == .english else { return option.title }
        switch option.kind {
        case .directDownload: return "Find a downloadable edition"
        case .importOwnedFile: return "I already have an ebook file"
        case .externalPurchase, .externalReadOnly: return option.channel?.name ?? "External source"
        }
    }

    static func acquisitionDetail(_ option: BookMarketLinks.AcquisitionOption, language: AppInterfaceLanguage) -> String {
        guard language == .english else { return option.detail }
        switch option.kind {
        case .directDownload:
            return "Search verified public-domain and DRM-free sources that can be imported into the app."
        case .importOwnedFile:
            return "Import a DRM-free EPUB, PDF, or TXT file that you already own."
        case .externalPurchase:
            return "Browse this source for an available edition. Confirm licensing and download access before assigning it."
        case .externalReadOnly:
            return "This source may support reading or purchasing outside Octo Teacher and may not allow in-app import."
        }
    }

    static func downloadCandidateDetail(language: AppInterfaceLanguage) -> String {
        language.pick("App 会在下载后再次校验文件格式和内容。", "The app will validate the file format and content again after downloading.")
    }

    static func downloadCandidateLicense(language: AppInterfaceLanguage) -> String {
        language.pick("请在下载前确认书名、作者和授权信息。", "Confirm the title, author, and license before downloading.")
    }
}

/// AI 布置阅读 v2：选类别 → AI 推荐书（附简介）→ 选一本 → AI 生成
/// 书籍简介 + 整本书的分次章节计划（普通书每次约 5,000-10,000 词，图文书每两章）→ 家长确认布置。
///
/// 家长全程不需要想书名、不需要定次数；AI 不可用时可退回手动布置（类型表单）。
struct ParentAIReadingComposerView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(ParentAIProviderStore.self) private var aiProvider
    @Environment(FamilyCloudSessionStore.self) private var familyCloud
    @Environment(\.dismiss) private var dismiss

    @State private var category: BookCategory = .childrenLiterature
    @State private var cloudCatalog = LocalBookCatalogStore.runtimeCatalog()
    @State private var candidates: [BookCandidate] = []
    @State private var candidateDownloads: [String: [AIBookSourceFinder.DownloadCandidate]] = [:]
    @State private var selectedBook: BookCandidate?
    @State private var bookIntro = ""
    @State private var drafts: [ReadingSessionDraft] = []
    @State private var planMode: ReadingPlanMode = .automatic
    @State private var customSessionCount = 4
    @State private var rewardPoints = 20
    @State private var verificationMode: TaskVerificationMode = .choiceQuiz
    @State private var verificationQuestionCount = 5
    @State private var verificationContentKind: TaskVerificationContentKind = .story
    @State private var isFindingDownload = false
    @State private var isDownloadingBook = false
    @State private var downloadedBook: FamilyBook?
    @State private var downloadedPayloads: [String: DownloadedBookPayload] = [:]
    @State private var pendingDownload: PendingBookDownload?
    @State private var showDownloadFolderPicker = false
    @State private var downloadCandidates: [AIBookSourceFinder.DownloadCandidate] = []
    @State private var browseSites: [(name: String, url: URL)] = []
    @State private var contentLanguage: FamilyLanguage?
    @State private var isRecommending = false
    @State private var isCheckingSources = false
    @State private var isPlanning = false
    @State private var feedback: String?

    var body: some View {
        Form {
            targetSection
            categorySection
            cloudBookCenterSection
            if !candidates.isEmpty { candidateSection }
            if selectedBook != nil { planSection }
            if !drafts.isEmpty { assignSection }
        }
        .navigationTitle(lang.pick("AI 布置阅读", "AI Reading Planner"))
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showDownloadFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard let pendingDownload else { return }
            guard case .success(let urls) = result else {
                feedback = lang.pick(
                    "已取消下载。请重新点击「下载」，选择一个保存文件夹。",
                    "Download canceled. Tap Download again and choose a destination folder."
                )
                self.pendingDownload = nil
                return
            }
            let folder = urls.first
            Task { await download(pendingDownload.candidate, for: pendingDownload.book, visibleFolder: folder) }
            self.pendingDownload = nil
        }
    }

    // MARK: - 分区

    private var targetSection: some View {
        Section {
            if store.hasMultipleChildren {
                Picker(lang.pick("布置给谁", "Assign to"), selection: Binding(
                    get: { store.activeChildId },
                    set: { store.setActiveChild($0) }
                )) {
                    ForEach(store.children) { member in
                        Text(lang.pick("\(member.name)（\(member.age) 岁）", "\(member.name) (age \(member.age))")).tag(member.id)
                    }
                }
            } else {
                LabeledContent(
                    lang.pick("布置给", "Assign to"),
                    value: lang.pick("\(store.child.name)（\(store.child.age) 岁）", "\(store.child.name) (age \(store.child.age))")
                )
            }
        }
    }

    private var categorySection: some View {
        Section {
            Picker(lang.pick("内容语言", "Content language"), selection: $contentLanguage) {
                Text(lang.pick("跟随家庭设置", "Use family setting")).tag(FamilyLanguage?.none)
                Text(lang.pick("中文", "Chinese")).tag(FamilyLanguage?.some(.chinese))
                Text("English").tag(FamilyLanguage?.some(.english))
            }
            Picker(lang.pick("所在地区（购书渠道）", "Region (book sources)"), selection: Binding(
                get: { store.settings.resolvedRegion },
                set: { store.setRegion($0) }
            )) {
                ForEach(FamilyRegion.allCases, id: \.self) { region in
                    Text(region.label(for: lang)).tag(region)
                }
            }
            .accessibilityIdentifier("ai-reading-region")
            NavigationLink {
                ParentBookImportView()
            } label: {
                Label(lang.pick("已买好电子书？导入到 App 直接布置", "Already have an ebook? Import it and assign it"), systemImage: "doc.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
            }
            .accessibilityIdentifier("ai-reading-import-entry")
            Picker(lang.pick("书的类别", "Book category"), selection: $category) {
                ForEach(BookCategory.allCases) { item in
                    Text("\(categoryTitle(item)) (\(categoryAgeHint(item)))").tag(item)
                }
            }
            .accessibilityIdentifier("ai-reading-category")
            .onChange(of: category) { _, _ in
                resetBookSelectionForCategoryChange()
            }

            if aiProvider.isReadyForAIComposer {
                Button {
                    Task { await recommendBooks() }
                } label: {
                    if isRecommending || isCheckingSources {
                        Label(lang.pick("AI 正在为\(store.child.name)选书……", "AI is choosing books for \(store.child.name)..."), systemImage: "sparkles")
                    } else {
                        Label(lang.pick("AI 推荐换一批书", "AI Recommend New Books"), systemImage: "sparkles")
                    }
                }
                .disabled(isRecommending)
                .accessibilityIdentifier("ai-reading-recommend")
            } else {
                Label(lang.pick(
                    "AI 助手未就绪；可以用「布置新任务」的阅读类型手动布置",
                    "The AI assistant is not ready. You can create a reading task manually from New Task."
                ), systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(lang.pick("第一步：选类别（\(BookCategory.allCases.count) 类）", "Step 1: Choose a category (\(BookCategory.allCases.count))"))
        } footer: {
            Text(lang.pick(
                "AI 会结合 TA 的年龄、兴趣和已读过的书来推荐，避开读过的。",
                "AI uses the child's age, interests, and reading history and avoids books already read."
            ))
        }
    }

    private var cloudBookCenterSection: some View {
        Section {
            let books = cloudCatalog.books(for: category)
            if books.isEmpty {
                ContentUnavailableView(
                    lang.pick("这个类别还没有入库书目", "No books in this category yet"),
                    systemImage: "cloud",
                    description: Text(lang.pick(
                        "可以先点「AI 推荐换一批书」走外部找书逻辑；未来后台更新云端图书馆后，这里会实时出现新书。",
                        "Try AI Recommend New Books for an external search. New titles will appear here as the cloud library is updated."
                    ))
                )
            } else {
                ForEach(books.prefix(8)) { item in
                    Button {
                        Task { await pickCloudCatalogBook(item) }
                    } label: {
                        cloudCatalogBookRow(item)
                    }
                    .buttonStyle(.plain)
                    .disabled(isPlanning)
                    .accessibilityIdentifier("ai-reading-cloud-book-\(item.id)")
                }
                if books.count > 8 {
                    Text(lang.pick(
                        "已显示前 8 本。未来云端版会支持搜索、筛选和后台精选排序。",
                        "Showing the first 8 books. A future cloud release will add search, filters, and curated ranking."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(lang.pick("章鱼老师云端图书馆", "Octo Teacher Cloud Library"))
        } footer: {
            Text(lang.pick(
                "这里读取章鱼老师运行态书库目录；未来后台更新云端书库后会同步到本机缓存。目录只保存书名、类别和合法来源链接，不把整套书文件塞进 App。",
                "This list uses Octo Teacher's runtime library catalog. Future cloud updates will sync to the local cache. The catalog stores titles, categories, and legal source links, not complete book files inside the app."
            ))
        }
    }

    private func cloudCatalogBookRow(_ item: LocalBookCatalogItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: selectedBook?.sourceKey == item.bookCandidate.sourceKey ? "checkmark.circle.fill" : "cloud.fill")
                .foregroundStyle(selectedBook?.sourceKey == item.bookCandidate.sourceKey ? Color.accentColor : Color.blue)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(lang.pick("《\(item.title)》", "\(item.title)"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(categoryTitle(item.categoryHint ?? category)) · \(categoryAgeHint(item.categoryHint ?? category))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Label(lang.pick("自有书库书目", "Octo Teacher library"), systemImage: "cloud")
                    if matchingImportedBook(for: item.bookCandidate) != nil {
                        Label(lang.pick("已加载", "Loaded"), systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else if item.downloadCandidate != nil {
                        Label(lang.pick("可下载 EPUB", "EPUB available"), systemImage: "arrow.down.doc")
                            .foregroundStyle(.green)
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.top, 5)
        }
        .padding(.vertical, 3)
    }

    private var candidateSection: some View {
        Section(lang.pick("第二步：选一本", "Step 2: Choose a book")) {
            if isCheckingSources {
                Label(lang.pick("正在核对哪些书能免费下载安装到 App……", "Checking which books can be legally downloaded into the app..."), systemImage: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(candidates) { book in
                Button {
                    Task { await pickBook(book) }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: selectedBook == book ? "checkmark.circle.fill" : "book.closed")
                            .foregroundStyle(selectedBook == book ? Color.accentColor : Color.secondary)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(lang.pick("《\(book.title)》", book.title))\(book.author.isEmpty ? "" : " · \(book.author)")")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(book.blurb)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let existing = matchingImportedBook(for: book) {
                                Label(lang.pick("已加载到 App 书库 · \(existing.format.uppercased())", "Loaded in the app library · \(existing.format.uppercased())"), systemImage: "checkmark.circle.fill")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.green)
                            } else if let downloads = candidateDownloads[book.sourceKey], !downloads.isEmpty {
                                Label(lang.pick(
                                    "可直接装入 App · \(downloads.first?.sourceName ?? "免费书源")",
                                    "Available for import · \(downloads.first?.sourceName ?? "free source")"
                                ), systemImage: "arrow.down.doc.fill")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.green)
                            } else {
                                Label(lang.pick("未确认可下载，可能只能外部阅读/导入", "No verified download; external reading or manual import may be required"), systemImage: "rectangle.on.rectangle")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isPlanning)
            }
        }
    }

    private var planSection: some View {
        Section {
            if isPlanning {
                Label(lang.pick("AI 正在读这本书、切分章节计划……", "AI is reviewing the book and building a reading plan..."), systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !bookIntro.isEmpty {
                Text(bookIntro)
                    .font(.callout)
            }
            if let book = selectedBook {
                VStack(alignment: .leading, spacing: 6) {
                    Text(lang.pick("获取这本书", "Get this book"))
                        .font(.headline)
                    Text(lang.pick(
                        "优先选择能让孩子直接在 App 里读的方式；外部购买渠道只作为兜底。",
                        "Prefer an edition the child can read directly in the app. External purchase options are a fallback."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    let options = BookMarketLinks.acquisitionOptions(
                        for: book.title,
                        region: store.settings.resolvedRegion,
                        contentLanguage: contentLanguage ?? store.activeContentLanguage
                    )

                    ForEach(options) { option in
                        switch option.kind {
                        case .directDownload:
                            if let activeImportedBook {
                                Label(
                                    lang.pick(
                                        "已装入 App：《\(activeImportedBook.title)》（" +
                                        (activeImportedBook.format == "pdf" ? "\(activeImportedBook.pageCount) 页" : "约 \(activeImportedBook.charCount / 1000) 千字") +
                                        "），布置后孩子可直接读。",
                                        "Loaded in the app: \(activeImportedBook.title) (" +
                                        (activeImportedBook.format == "pdf" ? "\(activeImportedBook.pageCount) pages" : "about \(activeImportedBook.charCount / 1000)K characters") +
                                        "). The child can read it directly after assignment."
                                    ),
                                    systemImage: "checkmark.seal.fill"
                                )
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Button {
                                    Task { await findDownloadSources(book) }
                                } label: {
                                    if isFindingDownload {
                                        Label(lang.pick("正在查找合法可下载版本……", "Searching for legal downloadable editions..."), systemImage: "magnifyingglass")
                                    } else {
                                        Label(acquisitionTitle(option), systemImage: option.systemImage)
                                            .font(.subheadline.weight(.semibold))
                                    }
                                }
                                .disabled(isFindingDownload || isDownloadingBook)
                                .accessibilityIdentifier("ai-reading-auto-download")
                                Text(acquisitionDetail(option))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if !downloadCandidates.isEmpty {
                                    Text(lang.pick("找到可导入版本", "Importable editions found"))
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                    ForEach(downloadCandidates) { candidate in
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(alignment: .top) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("\(candidate.sourceName) · \(candidate.format)")
                                                        .font(.caption.weight(.semibold))
                                                    Text("\(lang.pick("《\(candidate.sourceTitle)》", candidate.sourceTitle))\(candidate.author.isEmpty ? "" : " · \(candidate.author)")")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                    Text(lang == .english ? ParentAIReadingComposerCopy.downloadCandidateDetail(language: lang) : candidate.detail)
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                    Text(lang == .english ? ParentAIReadingComposerCopy.downloadCandidateLicense(language: lang) : candidate.licenseNote)
                                                        .font(.caption2)
                                                        .foregroundStyle(.green)
                                                }
                                                Spacer()
                                                if isCandidateLoaded(candidate) {
                                                    Label(lang.pick("已加载", "Loaded"), systemImage: "checkmark.seal.fill")
                                                        .font(.caption.weight(.semibold))
                                                        .foregroundStyle(.green)
                                                } else if let payload = downloadedPayloads[candidate.id] {
                                                    VStack(alignment: .trailing, spacing: 6) {
                                                        Label(lang.pick("已下载", "Downloaded"), systemImage: "checkmark.circle.fill")
                                                            .font(.caption.weight(.semibold))
                                                            .foregroundStyle(.green)
                                                        if let visibleURL = payload.visibleURL {
                                                            Text(visibleURL.lastPathComponent)
                                                                .font(.caption2)
                                                                .foregroundStyle(.secondary)
                                                                .lineLimit(1)
                                                        }
                                                        Button {
                                                            loadDownloadedBook(candidate, for: book)
                                                        } label: {
                                                            Text(lang.pick("加载书籍", "Load Book"))
                                                                .font(.caption.weight(.semibold))
                                                        }
                                                        .buttonStyle(.borderedProminent)
                                                        .accessibilityIdentifier("ai-reading-load-book-\(candidate.id)")
                                                    }
                                                } else {
                                                    Button {
                                                        pendingDownload = PendingBookDownload(candidate: candidate, book: book)
                                                        showDownloadFolderPicker = true
                                                    } label: {
                                                        if isDownloadingBook {
                                                            ProgressView()
                                                        } else {
                                                            Text(lang.pick("下载", "Download"))
                                                                .font(.caption.weight(.semibold))
                                                        }
                                                    }
                                                    .disabled(isDownloadingBook)
                                                    .buttonStyle(.borderedProminent)
                                                }
                                            }
                                        }
                                        .padding(.vertical, 4)
                                        .accessibilityIdentifier("ai-reading-download-candidate-\(candidate.id)")
                                    }
                                }
                            }
                        case .importOwnedFile:
                            NavigationLink {
                                ParentBookImportView()
                            } label: {
                                Label(acquisitionTitle(option), systemImage: option.systemImage)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .accessibilityIdentifier("ai-reading-import-owned-file")
                            Text(acquisitionDetail(option))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        case .externalPurchase, .externalReadOnly:
                            if let channel = option.channel {
                                Link(destination: channel.url) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Label(externalOptionTitle(option), systemImage: option.systemImage)
                                            .font(.caption.weight(.semibold))
                                        Text(acquisitionDetail(option))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    if !browseSites.isEmpty {
                        Divider()
                        Text(lang.pick("AI 没有一键装入时，可先去这些免费/无 DRM 站点找。", "If one-tap import is unavailable, try these free or DRM-free sources."))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(browseSites, id: \.name) { site in
                            Link(destination: site.url) {
                                Label(lang.pick("去 \(site.name) 手动找", "Search on \(site.name)"), systemImage: "safari")
                                    .font(.caption)
                            }
                        }
                    }
                    Label(lang.pick(
                        "提示：Kindle、微信读书等 DRM 书通常只能在原 App 阅读，不能自动导入第三方 App。",
                        "Note: DRM-protected books from services such as Kindle usually stay in their original app and cannot be imported automatically."
                    ), systemImage: "lock.doc")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("ai-reading-acquisition-options")
            }
            Picker(lang.pick("阅读次数划分", "Reading session plan"), selection: $planMode) {
                Text(lang.pick("自动划分", "Automatic")).tag(ReadingPlanMode.automatic)
                Text(lang.pick("家长指定次数", "Parent chooses")).tag(ReadingPlanMode.custom)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("ai-reading-plan-mode")

            if planMode == .custom {
                Stepper(
                    lang.pick("整本书分成 \(customSessionCount) 次", "Split the book into \(customSessionCount) sessions"),
                    value: $customSessionCount,
                    in: 1...customSessionUpperBound
                )
                .accessibilityIdentifier("ai-reading-custom-session-count")
            } else {
                Label(automaticPlanExplanation, systemImage: "wand.and.stars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await rebuildReadingPlan() }
            } label: {
                Label(lang.pick("按当前设置重新划分", "Rebuild with these settings"), systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(selectedBook == nil || isPlanning)
            .accessibilityIdentifier("ai-reading-rebuild-plan")

            ForEach($drafts) { $draft in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(lang.pick("第 \(draft.order) 次", "Session \(draft.order)"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(lang.pick(
                            "约 \(draft.estimatedMinutes) 分钟的量 · \(ParentAIReadingComposerCopy.growthPoints(draft.suggestedPoints ?? rewardPoints, language: lang))",
                            "About \(draft.estimatedMinutes) minutes · \(ParentAIReadingComposerCopy.growthPoints(draft.suggestedPoints ?? rewardPoints, language: lang))"
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    TextField(lang.pick("读哪些章节", "Chapters to read"), text: $draft.chapters)
                    if !draft.note.isEmpty {
                        Text(draft.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .onDelete { drafts.remove(atOffsets: $0); renumber() }
        } header: {
            Text(lang.pick("第三步：书籍简介与计划（可修改）", "Step 3: Book overview and plan (editable)"))
        } footer: {
            if !drafts.isEmpty {
                Text(lang.pick(
                    "普通文本每次约 5,000-10,000 个单词；幼儿图文书每 2 章一次。家长也可以指定整本书的阅读次数；左滑可删除某一次。",
                    "Regular text uses about 5,000-10,000 words per session; picture books use 2 chapters per session. Parents can choose the total number of sessions, and swipe left to delete one."
                ))
            }
        }
    }

    private var assignSection: some View {
        Section {
            Label(
                assignmentBookReadinessText,
                systemImage: canAssignLoadedBook ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(canAssignLoadedBook ? Color.green : Color.orange)
            .accessibilityIdentifier("ai-reading-book-readiness")
            Picker(lang.pick("阅读验收方式", "Reading check"), selection: $verificationMode) {
                ForEach(TaskVerificationMode.allCases, id: \.self) { mode in
                    Text(ParentAIReadingComposerCopy.verificationModeLabel(mode, language: lang)).tag(mode)
                }
            }
            Picker(lang.pick("内容类型", "Content type"), selection: $verificationContentKind) {
                ForEach(TaskVerificationContentKind.allCases, id: \.self) { kind in
                    Text(ParentAIReadingComposerCopy.contentKindLabel(kind, language: lang)).tag(kind)
                }
            }
            if verificationMode != .voiceRetell {
                Picker(lang.pick("验收题数", "Number of questions"), selection: $verificationQuestionCount) {
                    ForEach(5...10, id: \.self) { count in
                        Text(lang.pick("\(count) 题", "\(count) questions")).tag(count)
                    }
                }
            }
            Picker(lang.pick("默认成长积分（AI 未建议时）", "Default Growth Points (when AI has no suggestion)"), selection: $rewardPoints) {
                ForEach([10, 15, 20, 30, 45], id: \.self) { points in
                    Text(ParentAIReadingComposerCopy.growthPoints(points, language: lang)).tag(points)
                }
            }
            Button {
                assignAll()
            } label: {
                Text(lang.pick(
                    "给\(store.child.name)布置这 \(validDrafts.count) 次阅读",
                    "Assign \(validDrafts.count) reading sessions to \(store.child.name)"
                ))
                    .frame(maxWidth: .infinity)
            }
            .disabled(validDrafts.isEmpty || !canAssignLoadedBook)
            .accessibilityIdentifier("ai-reading-assign")
        } footer: {
            if let feedback {
                Text(feedback)
            }
        }
    }

    // MARK: - 动作

    private var validDrafts: [ReadingSessionDraft] {
        drafts.filter { !$0.chapters.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var lang: AppInterfaceLanguage {
        store.settings.resolvedParentInterfaceLanguage
    }

    private func categoryTitle(_ category: BookCategory) -> String {
        ParentAIReadingComposerCopy.categoryTitle(category, language: lang)
    }

    private func categoryAgeHint(_ category: BookCategory) -> String {
        ParentAIReadingComposerCopy.categoryAgeHint(category, language: lang)
    }

    private func acquisitionTitle(_ option: BookMarketLinks.AcquisitionOption) -> String {
        ParentAIReadingComposerCopy.acquisitionTitle(option, language: lang)
    }

    private func acquisitionDetail(_ option: BookMarketLinks.AcquisitionOption) -> String {
        ParentAIReadingComposerCopy.acquisitionDetail(option, language: lang)
    }

    private var activeImportedBook: FamilyBook? {
        downloadedBook ?? selectedBook.flatMap { matchingImportedBook(for: $0) }
    }

    private var activeBookFileIsReady: Bool {
        guard let book = activeImportedBook else { return false }
        return BookFileStore.shared.url(fileName: book.fileName) != nil
    }

    private var activeBookHasRemoteSource: Bool {
        guard let source = activeImportedBook?.sourceURLString,
              let url = URL(string: source) else { return false }
        return url.scheme?.lowercased() == "https"
    }

    private var canAssignLoadedBook: Bool {
        ReadingAssignmentBookPolicy.canAssign(
            fileIsReady: activeBookFileIsReady,
            hasRemoteHTTPSSource: activeBookHasRemoteSource,
            familyConnected: familyCloud.family != nil
        )
    }

    private var assignmentBookReadinessText: String {
        guard activeBookFileIsReady else {
            return lang.pick(
                "请先下载并加载书籍。只有 App 已验证的书文件才能布置给孩子。",
                "Download and load the book first. Only a verified in-app book can be assigned."
            )
        }
        if familyCloud.family != nil, !activeBookHasRemoteSource {
            return lang.pick(
                "这本书只在本机，无法同步到孩子手机。请选择可下载书源；实体书请使用自定义任务。",
                "This book exists only on this device and cannot sync to the child's phone. Choose a downloadable source, or create a custom task for a physical book."
            )
        }
        return familyCloud.family == nil
            ? lang.pick(
                "书籍已加载，可以在这台设备布置和阅读。",
                "The book is loaded and ready to assign on this device."
            )
            : lang.pick(
                "书籍已加载并具备同步书源，孩子手机会自动下载后开放阅读。",
                "The book is loaded with a sync source. The child's phone will download it before reading."
            )
    }

    private var activeBookAnalysis: BookFileStore.BookAnalysis? {
        guard let activeImportedBook else { return nil }
        return BookFileStore.shared.analyzeDetailed(fileName: activeImportedBook.fileName)
    }

    private var requestedSessionCount: Int? {
        planMode == .custom ? customSessionCount : nil
    }

    private var usesPictureBookPlanning: Bool {
        category.usesPictureBookSessionPlanning || activeBookAnalysis?.isLikelyPictureBook == true
    }

    private var customSessionUpperBound: Int {
        if let analysis = activeBookAnalysis {
            if !analysis.chapters.isEmpty { return max(1, min(100, analysis.chapters.count)) }
            if analysis.pageCount > 1 { return max(1, min(100, analysis.pageCount)) }
        }
        return 60
    }

    private var automaticPlanExplanation: String {
        usesPictureBookPlanning
            ? lang.pick(
                "已按幼儿图文书处理：每 2 章形成一次阅读任务。",
                "Picture-book mode: every 2 chapters becomes one reading task."
            )
            : lang.pick(
                "普通文本按每次约 5,000-10,000 个单词自动划分。",
                "Regular text is split into about 5,000-10,000 words per session."
            )
    }

    private func renumber() {
        for index in drafts.indices {
            drafts[index].order = index + 1
        }
    }

    private func resetBookSelectionForCategoryChange() {
        selectedBook = nil
        drafts = []
        bookIntro = ""
        downloadedBook = nil
        downloadedPayloads = [:]
        browseSites = []
        downloadCandidates = []
        candidateDownloads = [:]
        candidates = []
        feedback = nil
        planMode = .automatic
        customSessionCount = 4
    }

    private func pickCloudCatalogBook(_ item: LocalBookCatalogItem) async {
        let book = item.bookCandidate
        if let candidate = item.downloadCandidate {
            candidateDownloads[book.sourceKey] = [candidate]
            downloadCandidates = [candidate]
        } else {
            downloadCandidates = []
        }
        candidates = []
        await pickBook(book)
    }

    private func recommendBooks() async {
        isRecommending = true
        defer { isRecommending = false }
        selectedBook = nil
        drafts = []
        bookIntro = ""
        downloadedBook = nil
        downloadedPayloads = [:]
        browseSites = []
        candidateDownloads = [:]
        do {
            let digest = ChildMemoryDigestBuilder.digest(for: store.activeChildId, store: store)
            let raw = try await aiProvider.completeDraftJSON(
                system: ParentAIReadingComposerCopy.recommendationSystemPrompt(
                    contentLanguage: contentLanguage ?? store.activeContentLanguage,
                    parentInterfaceLanguage: lang
                ),
                user: AIBookRecommender.userPrompt(category: category, digest: digest),
                using: OpenAIStyleChatClient()
            )
            let parsed = AIBookRecommender.parse(raw)
            if parsed.isEmpty {
                feedback = lang.pick("AI 这次没推荐出来，再试一次。", "AI did not return recommendations this time. Please try again.")
            } else {
                candidates = parsed
                feedback = lang.pick(
                    "AI 已推荐，正在核对哪些书能直接下载安装到 App。",
                    "Recommendations are ready. Checking which books can be downloaded into the app."
                )
                await resolveCandidateDownloads(parsed)
            }
        } catch {
            feedback = lang.pick("AI 推荐失败（网络或密钥问题）。", "AI recommendations failed. Check the network and API key.")
        }
    }

    private func resolveCandidateDownloads(_ books: [BookCandidate]) async {
        isCheckingSources = true
        defer { isCheckingSources = false }
        var resolved: [String: [AIBookSourceFinder.DownloadCandidate]] = [:]
        for book in books.prefix(5) {
            let candidates = await AIBookSourceFinder.resolveDownloadCandidates(
                bookTitle: book.title,
                author: book.author,
                hint: nil,
                category: category
            )
            resolved[book.sourceKey] = candidates
        }
        candidateDownloads = resolved
        candidates = books.sorted { lhs, rhs in
            let lhsHas = !(resolved[lhs.sourceKey] ?? []).isEmpty
            let rhsHas = !(resolved[rhs.sourceKey] ?? []).isEmpty
            if lhsHas != rhsHas { return lhsHas && !rhsHas }
            return lhs.title < rhs.title
        }
        let downloadable = resolved.values.filter { !$0.isEmpty }.count
        feedback = downloadable > 0
            ? lang.pick(
                "已找到 \(downloadable) 本可直接装入 App 的书，已排在前面。",
                "Found \(downloadable) books that can be imported directly; they are listed first."
            )
            : lang.pick(
                "这一批没有确认可直接装入 App 的版本；建议换一批，或选一本后查看免费/无 DRM 站点。",
                "No directly importable editions were verified in this batch. Try new recommendations or choose a book to browse free and DRM-free sources."
            )
    }

    private func pickBook(_ book: BookCandidate) async {
        selectedBook = book
        isPlanning = true
        downloadCandidates = candidateDownloads[book.sourceKey] ?? []
        downloadedBook = matchingImportedBook(for: book)
        if let analysis = activeBookAnalysis {
            clampCustomSessionCount(to: analysis)
        }
        browseSites = []
        defer { isPlanning = false }
        do {
            let raw = try await aiProvider.completeDraftJSON(
                system: ParentAIReadingComposerCopy.readingPlanSystemPrompt(parentInterfaceLanguage: lang),
                user: AIReadingPlanner.userPrompt(
                    bookTitle: book.title,
                    childAge: store.child.age,
                    requestedSessions: requestedSessionCount,
                    isPictureBook: usesPictureBookPlanning
                ),
                using: OpenAIStyleChatClient()
            )
            let result = AIReadingPlanner.parseWithIntro(raw)
            if result.sessions.isEmpty {
                feedback = lang.pick("AI 没排出计划，换一本或再试一次。", "AI could not build a plan. Choose another book or try again.")
            } else {
                bookIntro = result.intro
                if let analysis = activeBookAnalysis {
                    clampCustomSessionCount(to: analysis)
                    drafts = localPlan(for: analysis)
                } else {
                    drafts = result.sessions
                }
                feedback = nil
            }
        } catch {
            feedback = lang.pick("AI 排计划失败（网络或密钥问题）。", "AI planning failed. Check the network and API key.")
        }
    }

    /// 查找可下载版本：AI 只提供书目提示；真实候选来自 Gutendex/Gutenberg
    /// 等可校验来源。家长看到候选后再决定下载。
    private func findDownloadSources(_ book: BookCandidate) async {
        isFindingDownload = true
        defer { isFindingDownload = false }
        downloadCandidates = []
        var hint: AIBookSourceFinder.SourceHint?
        do {
            let raw = try await aiProvider.completeDraftJSON(
                system: AIBookSourceFinder.systemPrompt(category: category),
                user: AIBookSourceFinder.userPrompt(bookTitle: book.title, author: book.author, category: category),
                using: OpenAIStyleChatClient()
            )
            hint = AIBookSourceFinder.parse(raw)
        } catch {
            hint = nil
        }
        browseSites = hint?.browseSites ?? AIBookSourceFinder.fallbackBrowseSites(bookTitle: book.title, category: category)
        let resolved = await AIBookSourceFinder.resolveDownloadCandidates(
            bookTitle: book.title,
            author: book.author,
            hint: hint,
            category: category
        )
        downloadCandidates = resolved
        if resolved.isEmpty {
            feedback = lang.pick(
                "没有查到可直接导入的合法 EPUB/TXT/PDF。下面只列免费/无 DRM 浏览站点供你手动核对；Amazon/Kindle/微信读书这类渠道大多只能外部阅读，不算可下载版本。",
                "No legal EPUB, TXT, or PDF edition was found for direct import. The links below are free or DRM-free sources for manual review. Services such as Amazon or Kindle usually support external reading only and do not count as downloadable editions."
            )
        } else {
            feedback = lang.pick(
                "找到 \(resolved.count) 个可下载候选。请核对书名后点击下载，App 会再次校验文件。",
                "Found \(resolved.count) download candidates. Confirm the title, then download; the app will validate the file again."
            )
        }
    }

    private func download(_ candidate: AIBookSourceFinder.DownloadCandidate, for book: BookCandidate, visibleFolder: URL?) async {
        isDownloadingBook = true
        defer { isDownloadingBook = false }
        guard let downloaded = await EbookDownloader().download(candidates: [candidate.downloadURL]) else {
            feedback = downloadFailureMessage(for: candidate)
            return
        }
        let visibleURL = BookFileStore.shared.writeVisibleCopy(
            data: downloaded.data,
            ext: downloaded.ext,
            title: book.title,
            in: visibleFolder
        )
        downloadedPayloads[candidate.id] = DownloadedBookPayload(
            data: downloaded.data,
            ext: downloaded.ext,
            visibleURL: visibleURL
        )
        feedback = visibleURL == nil
            ? lang.pick(
                "下载成功，尚未选择可写文件夹或外部副本保存失败；点击「加载书籍」后仍会装入 App 书库。",
                "Download complete. No writable folder was selected, or the external copy could not be saved. Load Book can still add it to the app library."
            )
            : lang.pick(
                "下载成功，已保存到「\(visibleURL?.deletingLastPathComponent().lastPathComponent ?? "电子书")」。请点击「加载书籍」让 App 分析章节并布置。",
                "Download complete and saved in \(visibleURL?.deletingLastPathComponent().lastPathComponent ?? "Ebooks"). Tap Load Book to analyze chapters and prepare the assignment."
            )
    }

    private func loadDownloadedBook(_ candidate: AIBookSourceFinder.DownloadCandidate, for book: BookCandidate) {
        guard let payload = downloadedPayloads[candidate.id],
              let fileName = BookFileStore.shared.importBook(data: payload.data, ext: payload.ext),
              let analysis = BookFileStore.shared.analyzeDetailed(fileName: fileName) else {
            feedback = lang.pick(
                "加载失败：文件下载到了，但 App 无法识别正文或章节。请换一个无 DRM EPUB/TXT/PDF 版本。",
                "Could not load the book. The file downloaded, but the app could not identify readable text or chapters. Try another DRM-free EPUB, TXT, or PDF edition."
            )
            return
        }
        let saved = store.addBook(
            title: book.title,
            fileName: fileName,
            format: payload.ext,
            pageCount: analysis.pageCount,
            charCount: analysis.charCount,
            chapters: analysis.chapters,
            sourceName: candidate.sourceName,
            sourceURLString: candidate.downloadURL.absoluteString
        )
        downloadedBook = saved
        clampCustomSessionCount(to: analysis)
        drafts = localPlan(for: analysis)
        feedback = analysis.chapters.isEmpty
            ? lang.pick(
                "加载成功！计划已按整本书的真实长度重排，确认后布置。",
                "Book loaded. The plan now uses the book's actual length and is ready for review."
            )
            : lang.pick(
                "加载成功！已识别 \(analysis.chapters.count) 个章节，并按章节重排计划。",
                "Book loaded. \(analysis.chapters.count) chapters were identified and the plan was rebuilt by chapter."
            )
    }

    private func rebuildReadingPlan() async {
        if let analysis = activeBookAnalysis {
            clampCustomSessionCount(to: analysis)
            drafts = localPlan(for: analysis)
            feedback = lang.pick("已按当前设置重新划分为 \(drafts.count) 次。", "Rebuilt as \(drafts.count) sessions using the current settings.")
            return
        }
        guard let book = selectedBook else { return }
        isPlanning = true
        defer { isPlanning = false }
        do {
            let raw = try await aiProvider.completeDraftJSON(
                system: ParentAIReadingComposerCopy.readingPlanSystemPrompt(parentInterfaceLanguage: lang),
                user: AIReadingPlanner.userPrompt(
                    bookTitle: book.title,
                    childAge: store.child.age,
                    requestedSessions: requestedSessionCount,
                    isPictureBook: usesPictureBookPlanning
                ),
                using: OpenAIStyleChatClient()
            )
            let result = AIReadingPlanner.parseWithIntro(raw)
            guard !result.sessions.isEmpty else {
                feedback = lang.pick(
                    "AI 没有生成可用计划，请先加载电子书，让 App 按真实章节划分。",
                    "AI did not produce a usable plan. Load the ebook first so the app can use its actual chapters."
                )
                return
            }
            if !result.intro.isEmpty { bookIntro = result.intro }
            drafts = result.sessions
            feedback = lang.pick("已按当前设置重新生成 \(drafts.count) 次阅读计划。", "Generated a new \(drafts.count)-session reading plan.")
        } catch {
            feedback = lang.pick(
                "重新划分失败。可以先加载电子书，再由 App 按真实章节稳定划分。",
                "Could not rebuild the plan. Load the ebook first so the app can split it reliably using real chapters."
            )
        }
    }

    private func localPlan(for analysis: BookFileStore.BookAnalysis) -> [ReadingSessionDraft] {
        let plan: [ReadingSessionDraft]
        if analysis.chapters.isEmpty {
            plan = BookImportPlanner.plan(
                pageCount: analysis.pageCount,
                charCount: analysis.charCount,
                wordCount: analysis.wordCount,
                age: store.child.age,
                requestedSessions: requestedSessionCount
            )
        } else {
            plan = BookImportPlanner.plan(
                chapters: analysis.chapters,
                charCount: analysis.charCount,
                wordCount: analysis.wordCount,
                age: store.child.age,
                isPictureBook: usesPictureBookPlanning,
                requestedSessions: requestedSessionCount
            )
        }
        return ParentAIReadingComposerCopy.parentLocalizedDrafts(plan, language: lang)
    }

    private func clampCustomSessionCount(to analysis: BookFileStore.BookAnalysis) {
        let upper: Int
        if !analysis.chapters.isEmpty {
            upper = analysis.chapters.count
        } else if analysis.pageCount > 1 {
            upper = analysis.pageCount
        } else {
            upper = 100
        }
        customSessionCount = min(max(1, customSessionCount), max(1, upper))
    }

    private func assignAll() {
        guard let book = selectedBook, canAssignLoadedBook, let linkedBook = activeImportedBook else {
            feedback = assignmentBookReadinessText
            return
        }
        var assigned = 0
        var createdAssignmentIDs: [UUID] = []
        let sessions = validDrafts.count
        let childLanguage = ParentAIReadingComposerCopy.childTaskLanguage(
            contentLanguage: store.activeContentLanguage,
            interfaceLanguage: store.activeChildInterfaceLanguage
        )
        for (index, draft) in validDrafts.enumerated() {
            let importedBookId = linkedBook.id
            var pageStart: Int?
            var pageEnd: Int?
            if linkedBook.format == "pdf" {
                let range = BookImportPlanner.pageRange(index: index, sessions: sessions, pageCount: linkedBook.pageCount)
                pageStart = range.start; pageEnd = range.end
            } else if let start = draft.startCharacter, let end = draft.endCharacter {
                pageStart = start; pageEnd = end
            } else {
                let range = BookImportPlanner.charRange(index: index, sessions: sessions, charCount: linkedBook.charCount)
                pageStart = range.start; pageEnd = range.end
            }
            let created = store.assignNewTask(
                title: ParentAIReadingComposerCopy.childTaskTitle(
                    bookTitle: book.title,
                    order: draft.order,
                    language: childLanguage
                ),
                instructions: ParentAIReadingComposerCopy.childTaskInstructions(
                    note: draft.note,
                    language: childLanguage
                ),
                category: .learning,
                rewardMinutes: draft.suggestedPoints ?? rewardPoints,
                requiredProof: .text,
                reading: ReadingSpec(
                    bookTitle: book.title,
                    minMinutes: draft.estimatedMinutes,
                    chapterPlanText: ParentAIReadingComposerCopy.childChapterPlan(
                        draft.chapters,
                        order: draft.order,
                        sessionCount: sessions,
                        language: childLanguage
                    ),
                    allowAIContent: nil,
                    importedBookId: importedBookId,
                    pageStart: pageStart,
                    pageEnd: pageEnd,
                    deliveryMode: .digitalLoaded
                ),
                verification: readingVerificationSpec()
            )
            if let created {
                assigned += 1
                createdAssignmentIDs.append(created.id)
            }
        }
        if familyCloud.isGuardianSignedIn,
           !createdAssignmentIDs.isEmpty,
           !familyCloud.queueGuardianTaskUpserts(assignmentIds: createdAssignmentIDs, local: store) {
            feedback = lang.pick(
                "阅读任务已保存在本机，但还没有进入家庭云同步队列。",
                "The reading tasks are saved locally but are not queued for family cloud sync yet."
            )
            return
        }
        feedback = lang.pick("已布置 \(assigned) 次阅读任务。", "Assigned \(assigned) reading sessions.")
        if assigned > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                dismiss()
            }
        }
    }

    private func externalOptionTitle(_ option: BookMarketLinks.AcquisitionOption) -> String {
        if lang == .english {
            switch option.kind {
            case .externalReadOnly:
                return "Read or buy externally: \(acquisitionTitle(option))"
            case .externalPurchase:
                return "Browse source: \(acquisitionTitle(option))"
            case .directDownload, .importOwnedFile:
                return acquisitionTitle(option)
            }
        }
        switch option.kind {
        case .externalReadOnly:
            return "外部阅读/购买：\(option.title)"
        case .externalPurchase:
            return "开放书源浏览：\(option.title)"
        case .directDownload, .importOwnedFile:
            return option.title
        }
    }

    private func downloadFailureMessage(for candidate: AIBookSourceFinder.DownloadCandidate) -> String {
        lang.pick(
            "未能从 \(candidate.sourceName) 下载《\(candidate.sourceTitle)》：下载地址没有返回可校验的 EPUB/TXT/PDF（可能是网页、文件过短或临时网络失败）。请点下一个可下载候选；如果都失败，选择「我已有电子书文件」导入你手里的无 DRM EPUB/PDF/TXT。",
            "Could not download \(candidate.sourceTitle) from \(candidate.sourceName). The URL did not return a valid EPUB, TXT, or PDF file. It may be a web page, an incomplete file, or a temporary network failure. Try the next candidate, or use I Already Have an Ebook File to import a DRM-free EPUB, PDF, or TXT file."
        )
    }

    private func matchingImportedBook(for candidate: BookCandidate) -> FamilyBook? {
        store.book(matchingTitle: candidate.title)
    }

    private func isCandidateLoaded(_ candidate: AIBookSourceFinder.DownloadCandidate) -> Bool {
        store.books.contains {
                $0.sourceURLString == candidate.downloadURL.absoluteString
                    || ($0.sourceName == candidate.sourceName && $0.title.localizedCaseInsensitiveContains(candidate.sourceTitle))
        }
    }

    private func readingVerificationSpec() -> TaskVerificationSpec {
        if store.isPreReaderActive || verificationMode == .voiceRetell {
            return .retell(seconds: 180, contentKind: verificationContentKind)
        }
        return TaskVerificationSpec(
            mode: verificationMode == .learningDrill ? .learningDrill : .choiceQuiz,
            contentKind: verificationContentKind,
            questionCount: verificationQuestionCount,
            minimumRetellSeconds: nil,
            parentApprovedSummary: nil
        )
    }
}

private struct PendingBookDownload {
    var candidate: AIBookSourceFinder.DownloadCandidate
    var book: BookCandidate
}

private struct DownloadedBookPayload {
    var data: Data
    var ext: String
    var visibleURL: URL?
}
