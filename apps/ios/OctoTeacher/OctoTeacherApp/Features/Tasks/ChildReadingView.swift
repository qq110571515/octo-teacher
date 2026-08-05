import PDFKit
import SwiftUI
import WebKit

/// 孩子端 App 内阅读器：读取家长导入/下载的 PDF、TXT、HTML、EPUB，并本地记录阅读时间、页码、字号和朗读速度。
/// 没有导入书时，仍保留原有 AI 改写内容/实体书计时兜底。
struct ChildReadingView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(\.childSurfaceLanguage) private var childSurfaceLanguage
    @Environment(ParentAIProviderStore.self) private var aiProvider
    @Environment(FamilyCloudSessionStore.self) private var familyCloud
    @Environment(\.dismiss) private var dismiss

    let assignment: TaskAssignment

    @State private var contentTitle = ""
    @State private var content: String?
    @State private var isGenerating = false
    @State private var startedAt = Date()
    @State private var elapsedSeconds = 0
    @State private var persistedSessionSeconds = 0
    @State private var pdfPage = 1
    @State private var textPages: [String] = []
    @State private var textPageIndex = 0
    @State private var epubPackage: BookFileStore.EPUBRenderPackage?
    @State private var epubChapterIndex = 0
    @State private var fontSize: Double = 18
    @State private var speechRate: Double = 1.0
    @State private var bilingualVisible = false
    @State private var bilingualPageKey: String?
    @State private var bilingualParagraphs: [ReadingBilingualParagraph] = []
    @State private var bilingualCache: [String: [ReadingBilingualParagraph]] = [:]
    @State private var isTranslating = false
    @State private var translationError: String?
    @State private var translationTask: Task<Void, Never>?
    @State private var showReaderSettings = false
    @State private var isRefreshingBook = false
    @State private var bookSyncMessage: String?
    @State private var cloudSessionRef = UUID().uuidString.lowercased()
    @State private var didQueueCloudSession = false
    @GestureState private var pinchScale: CGFloat = 1

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var loc: ChildLocalizationContext { ChildLocalizationContext(language: childSurfaceLanguage) }

    private var reading: ReadingSpec? { assignment.task.reading }
    private var linkedImportedBook: FamilyBook? { store.book(for: reading) }
    private var importedBook: FamilyBook? {
        guard let book = linkedImportedBook,
              BookFileStore.shared.url(fileName: book.fileName) != nil else { return nil }
        return book
    }
    private var requiresSyncedElectronicBook: Bool { reading?.importedBookId != nil }
    private var currentAssignment: TaskAssignment {
        store.assignments.first(where: { $0.id == assignment.id }) ?? assignment
    }
    private var alreadySpent: Int { currentAssignment.readingSecondsSpent ?? 0 }
    private var textChunkSize: Int { store.isPreReaderActive ? 1_000 : 1_800 }
    private var effectiveFontSize: CGFloat {
        min(36, max(16, CGFloat(fontSize) * pinchScale))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let importedBook {
                    importedBookView(importedBook)
                } else if requiresSyncedElectronicBook {
                    missingElectronicBookView
                } else if isGenerating {
                    header
                    generatingView
                } else if let content {
                    header
                    generatedContentView(content)
                } else {
                    header
                    offlineGuide
                }
            }
            .padding()
        }
        .navigationTitle(loc.pick(
            "阅读《\(reading?.bookTitle ?? "书")》",
            "Reading “\(reading?.bookTitle ?? "your book")”"
        ))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let importedBook {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if store.isSpeechEnabled {
                        Button {
                            speakCurrentPage(importedBook)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        .accessibilityLabel(loc.pick("朗读当前页", "Read current page"))
                        .accessibilityIdentifier("child-reading-speak-current-page")
                    }
                    Button {
                        showReaderSettings = true
                    } label: {
                        Image(systemName: "textformat.size")
                    }
                    .accessibilityLabel(loc.pick("阅读设置", "Reading settings"))
                    .accessibilityIdentifier("child-reading-open-settings")
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            doneButton
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showReaderSettings) {
            if let importedBook {
                readerSettingsSheet(importedBook)
            }
        }
        .onAppear {
            startedAt = Date()
            persistedSessionSeconds = 0
        }
        .task(id: importedBook?.id) {
            if importedBook == nil, requiresSyncedElectronicBook {
                await refreshMissingBook()
            }
            loadReaderState()
            await loadContentIfNeeded()
        }
        .onDisappear {
            translationTask?.cancel()
            persistSession(final: true)
            SpeechReader.shared.stop()
        }
        .onReceive(timer) { _ in
            elapsedSeconds = Int(Date().timeIntervalSince(startedAt))
            if elapsedSeconds - persistedSessionSeconds >= 30 {
                persistSession(final: false)
            }
        }
    }

    // MARK: - 分区

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let reading {
                // 章节计划文本本身是家长填的内容数据，不翻译；围绕它的模板句走双语。
                let planText = reading.chapterPlanText.isEmpty
                    ? loc.pick("接着上次读", "pick up where you left off")
                    : reading.chapterPlanText
                HStack {
                    Text(loc.pick("这次读：\(planText)", "This time: \(planText)"))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    SpeakButton(
                        text: loc.pick("这次读\(planText)。加油！", "This time: \(planText). You can do it!"),
                        language: loc.language
                    )
                }
            }
            HStack(spacing: 12) {
                Label(
                    ChildReadingProgressCopy.label(
                        seconds: alreadySpent + elapsedSeconds,
                        targetMinutes: reading?.minMinutes ?? 15,
                        isPreReader: store.isPreReaderActive,
                        language: loc.language
                    ),
                    systemImage: store.isPreReaderActive ? "star.fill" : "clock.fill"
                )
                .font(store.isPreReaderActive ? .subheadline.weight(.bold) : .caption.weight(.bold))
                .foregroundStyle(.orange)
                .monospacedDigit()

                if let importedBook {
                    Text(progressLabel(for: importedBook))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
        }
        .accessibilityIdentifier("child-reading-header")
    }

    private var generatingView: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(loc.pick("AI 正在为你准备这一节的内容……", "AI is getting this part ready for you…"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func generatedContentView(_ content: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !contentTitle.isEmpty {
                Text(contentTitle)
                    .font(.title2.bold())
            }
            if store.isSpeechEnabled {
                // 朗读书正文：音色按正文内容语言判断，不强制 UI 语言。
                SpeakButton(text: content, language: contentSpeechLanguage(content), rateMultiplier: speechRate)
            }
            Text(content)
                .font(.system(size: store.isPreReaderActive ? 22 : 18))
                .lineSpacing(8)
        }
    }

    private var offlineGuide: some View {
        VStack(spacing: 14) {
            Text("📚")
                .font(.system(size: 64))
            HStack(spacing: 8) {
                Text(loc.pick("去拿书读吧！", "Go grab your book!"))
                    .font(.title2.bold())
                SpeakButton(text: offlineGuideText, language: loc.language)
            }
            Text(offlineGuideText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .accessibilityIdentifier("child-reading-offline-guide")
    }

    private var offlineGuideText: String {
        let plan = reading?.chapterPlanText
        return loc.pick(
            "翻到\(plan ?? "要读的地方")，认真读一读。这个页面会帮你记时间，读完回来点下面的按钮。",
            "Open your book to \(plan ?? "the part you need to read") and read carefully. This page keeps track of your time — come back and tap the button below when you finish."
        )
    }

    private var missingElectronicBookView: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            Text(loc.pick("正在拿到这本书", "Getting your book"))
                .font(.title3.bold())
            Text(bookSyncMessage ?? loc.pick(
                "任务已经到了，书也会从家庭书库自动同步。准备好后就能直接开始阅读。",
                "The task is here. The book will sync automatically from your family library, then you can start reading."
            ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await refreshMissingBook() }
            } label: {
                HStack(spacing: 8) {
                    if isRefreshingBook { ProgressView() }
                    Image(systemName: "arrow.clockwise")
                    Text(loc.pick("重新同步", "Try again"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRefreshingBook)
            .accessibilityIdentifier("child-reading-sync-missing-book")
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier("child-reading-book-not-ready")
    }

    private var doneButton: some View {
        Button {
            persistSession(final: true)
            SpeechReader.shared.stop()
            dismiss()
        } label: {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text(loc.pick("保存进度并退出", "Save progress and exit"))
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("child-reading-done")
    }

    @ViewBuilder
    private func importedBookView(_ book: FamilyBook) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            compactReaderBar(book)

            if isPDF(book), let url = BookFileStore.shared.url(fileName: book.fileName) {
                BookPDFView(
                    url: url,
                    startPage: reading?.pageStart ?? 1,
                    endPage: reading?.pageEnd ?? book.pageCount,
                    currentPage: $pdfPage
                )
                .frame(height: 620)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.2))
                }
            } else if isEPUB(book), let epubPackage, !epubPackage.chapters.isEmpty {
                epubReader(epubPackage)
            } else if isEPUB(book) {
                ContentUnavailableView(
                    loc.pick("这本 EPUB 暂时不能图文阅读", "This EPUB can't be shown here yet"),
                    systemImage: "book.pages",
                    description: Text(loc.pick(
                        "文件可能缺少目录或章节 HTML。请让家长换一个无 DRM EPUB/PDF/TXT/HTML 版本。",
                        "The file may be missing its table of contents or chapter pages. Ask a parent for a DRM-free EPUB/PDF/TXT/HTML version."
                    ))
                )
            } else if isPlainTextBook(book), !textPages.isEmpty {
                textReader
            } else if isPlainTextBook(book) {
                ContentUnavailableView(
                    loc.pick("这一段还没有可读文字", "No readable text here yet"),
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(loc.pick(
                        "这本书可能是空文件，或者当前章节范围没有文字。请让家长重新导入。",
                        "This book may be empty, or this part has no text. Ask a parent to import it again."
                    ))
                )
            } else {
                ContentUnavailableView(
                    loc.pick("这种格式还不能在 App 内阅读", "This format can't be read in the app yet"),
                    systemImage: "book.closed",
                    description: Text(loc.pick(
                        "当前内置阅读器支持无 DRM 的 EPUB/PDF/TXT/HTML。请让家长换一个可导入版本。",
                        "The built-in reader supports DRM-free EPUB/PDF/TXT/HTML. Ask a parent for a version that can be imported."
                    ))
                )
            }
        }
    }

    private func compactReaderBar(_ book: FamilyBook) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(progressLabel(for: book), systemImage: "bookmark.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(pageLabel(for: book))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: readerProgress(for: book))
                .tint(.blue)
            Text(ChildReadingProgressCopy.numericLabel(
                seconds: alreadySpent + elapsedSeconds,
                language: loc.language
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("child-reading-quick-controls")
    }

    private func readerSettingsSheet(_ book: FamilyBook) -> some View {
        NavigationStack {
            Form {
                Section(loc.pick("阅读设置", "Reading settings")) {
                    readerControls(book)
                }
                if isPlainTextBook(book) {
                    Section(loc.pick("双语阅读", "Bilingual reading")) {
                        translationControls
                    }
                }
            }
            .navigationTitle(loc.pick("阅读设置", "Reading settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc.pick("完成", "Done")) {
                        persistSession(final: false)
                        showReaderSettings = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func bookStatusCard(_ book: FamilyBook) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(loc.pick("已加载到 App 书库", "Loaded into your app library"), systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.green)
            // 书名是内容数据不翻译；中文界面保留书名号，英文界面直接展示。
            Text(loc.pick("《\(book.title)》", book.title))
                .font(.headline)
            Text(bookDetailText(book))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func readerControls(_ book: FamilyBook) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(progressLabel(for: book), systemImage: "bookmark.fill")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(pageLabel(for: book))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isPlainTextBook(book) || isEPUB(book) {
                HStack {
                    Button {
                        fontSize = max(16, fontSize - 2)
                        persistSession(final: false)
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(loc.pick("缩小文字", "Make text smaller"))
                    .accessibilityIdentifier("child-reading-font-smaller")
                    Slider(value: $fontSize, in: 16...36, step: 1)
                        .accessibilityIdentifier("child-reading-font-slider")
                    Button {
                        fontSize = min(36, fontSize + 2)
                        persistSession(final: false)
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(loc.pick("放大文字", "Make text larger"))
                    .accessibilityIdentifier("child-reading-font-larger")
                }
            }

            if store.isSpeechEnabled {
                HStack {
                    Button {
                        speakCurrentPage(book)
                    } label: {
                        Label(loc.pick("读这一页", "Read this page"), systemImage: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("child-reading-speak-current-page")

                    Text(loc.pick("速度", "Speed"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $speechRate, in: 1.0...1.5, step: 0.1)
                        .frame(maxWidth: 140)
                        .accessibilityIdentifier("child-reading-speech-rate")
                    Text(String(format: "%.1fx", speechRate))
                        .font(.caption.monospacedDigit())
                        .frame(width: 38, alignment: .trailing)
                }
            } else {
                Label(
                    loc.pick("家长可在设置里开启小喇叭朗读。", "A parent can turn on read-aloud in Settings."),
                    systemImage: "speaker.slash"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var textReader: some View {
        VStack(alignment: .leading, spacing: 14) {
            textPageControls
            textPageBody
        }
        .accessibilityIdentifier("child-reading-text-reader")
    }

    private func epubReader(_ package: BookFileStore.EPUBRenderPackage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            epubChapterControls(package)
            if let chapter = package.chapters[safe: epubChapterIndex] {
                BookEPUBWebView(
                    chapterURL: chapter.fileURL,
                    readAccessURL: package.rootURL,
                    fontSize: effectiveFontSize,
                    loc: loc
                )
                .frame(height: 640)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.secondary.opacity(0.18))
                }
                .simultaneousGesture(textPinchGesture)
                .accessibilityIdentifier("child-reading-epub-reader")
            }
        }
    }

    private func epubChapterControls(_ package: BookFileStore.EPUBRenderPackage) -> some View {
        HStack {
            Button {
                epubChapterIndex = max(0, epubChapterIndex - 1)
                persistSession(final: false)
            } label: {
                Label(loc.pick("上一章", "Previous"), systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .disabled(epubChapterIndex == 0)

            Spacer()
            if let chapter = package.chapters[safe: epubChapterIndex] {
                VStack(spacing: 2) {
                    Text(loc.pick(
                        "第 \(chapter.order) / \(package.chapters.count) 章",
                        "Chapter \(chapter.order) / \(package.chapters.count)"
                    ))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                    Text(chapter.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()

            Button {
                epubChapterIndex = min(max(0, package.chapters.count - 1), epubChapterIndex + 1)
                persistSession(final: false)
            } label: {
                Label(loc.pick("下一章", "Next"), systemImage: "chevron.right")
            }
            .buttonStyle(.bordered)
            .disabled(epubChapterIndex >= package.chapters.count - 1)
        }
    }

    @ViewBuilder
    private var textPageBody: some View {
        let key = currentTranslationCacheKey
        if bilingualVisible,
           bilingualPageKey == key,
           !bilingualParagraphs.isEmpty {
            bilingualReader
        } else {
            originalTextPage
        }
    }

    private var originalTextPage: some View {
        Text(currentTextPageText)
            .font(.system(size: effectiveFontSize))
            .lineSpacing(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.secondary.opacity(0.18))
            }
            .gesture(textPinchGesture)
    }

    private var bilingualReader: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(bilingualParagraphs, id: \.index) { paragraph in
                VStack(alignment: .leading, spacing: 8) {
                    Text(paragraph.original)
                        .font(.system(size: effectiveFontSize))
                        .lineSpacing(7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(paragraph.translation)
                        .font(.system(size: max(16, effectiveFontSize - 1), weight: .semibold))
                        .lineSpacing(7)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(14)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.secondary.opacity(0.16))
                }
            }
        }
        .gesture(textPinchGesture)
        .accessibilityIdentifier("child-reading-bilingual-page")
    }

    private var translationControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    toggleBilingualTranslation()
                } label: {
                    Label(
                        bilingualVisible
                            ? loc.pick("隐藏中文", "Hide Chinese")
                            : loc.pick("中英双语", "Show Chinese"),
                        systemImage: bilingualVisible ? "textformat" : "character.book.closed"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTranslating || currentTextPageText.isEmpty || !aiProvider.isReadyForChildAICompanion)
                .accessibilityIdentifier("child-reading-translate-page")

                if isTranslating {
                    ProgressView()
                    Text(loc.pick("小伙伴正在翻这一页…", "Your buddy is translating this page…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let translationError {
                    Text(translationError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(loc.pick(
                        "保留英文原文，逐段显示中文意思。",
                        "Keeps the original text and shows the Chinese meaning under each paragraph."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !aiProvider.isReadyForChildAICompanion {
                Text(loc.pick(
                    "家长开启 AI 章鱼老师后，可以在这里翻译当前页。",
                    "Once a parent turns on AI Octo Teacher, you can translate this page here."
                ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var textPinchGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                fontSize = min(36, max(16, fontSize * Double(value)))
                persistSession(final: false)
            }
    }

    private var textPageControls: some View {
        HStack {
            Button {
                textPageIndex = max(0, textPageIndex - 1)
                persistSession(final: false)
                handleTextPageChanged()
            } label: {
                Label(loc.pick("上一页", "Previous"), systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .disabled(textPageIndex == 0)

            Spacer()
            Text(loc.pick(
                "第 \(textPageIndex + 1) / \(max(1, textPages.count)) 页",
                "Page \(textPageIndex + 1) / \(max(1, textPages.count))"
            ))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            Spacer()

            Button {
                textPageIndex = min(max(0, textPages.count - 1), textPageIndex + 1)
                persistSession(final: false)
                handleTextPageChanged()
            } label: {
                Label(loc.pick("下一页", "Next"), systemImage: "chevron.right")
            }
            .buttonStyle(.bordered)
            .disabled(textPageIndex >= textPages.count - 1)
        }
    }

    // MARK: - 动作

    @MainActor
    private func refreshMissingBook() async {
        guard requiresSyncedElectronicBook else { return }
        guard familyCloud.isChildDevice else {
            bookSyncMessage = loc.pick(
                "这本电子书还没有同步到此设备，请让家长重新布置已加载的书籍。",
                "This ebook has not synced to this device. Ask a parent to assign the loaded book again."
            )
            return
        }
        isRefreshingBook = true
        bookSyncMessage = nil
        defer { isRefreshingBook = false }
        do {
            try await familyCloud.refreshChildSurface(into: store)
            if importedBook == nil {
                bookSyncMessage = loc.pick(
                    "任务已更新，但书文件还没准备好。请保持联网后再试一次。",
                    "The task is updated, but the book file is not ready yet. Stay online and try again."
                )
            }
        } catch {
            bookSyncMessage = loc.pick(
                "暂时没有同步成功。请检查网络，再点一次。",
                "The book did not sync yet. Check the connection and try again."
            )
        }
    }

    private func loadReaderState() {
        fontSize = store.isPreReaderActive ? 24 : 18
        speechRate = 1.0
        guard let book = importedBook else { return }

        if isEPUB(book) {
            epubPackage = BookFileStore.shared.prepareEPUBForReading(fileName: book.fileName)
        } else if isPlainTextBook(book) {
            loadTextPages(for: book)
        }

        if let progress = store.readingProgress(
            childId: currentAssignment.childId,
            bookId: book.id,
            assignmentId: assignment.id
        ) {
            fontSize = min(36, max(16, progress.fontSize))
            speechRate = min(1.5, max(1.0, progress.speechRate))
            if isPDF(book) {
                let start = reading?.pageStart ?? 1
                let end = reading?.pageEnd ?? book.pageCount
                pdfPage = min(end, max(start, progress.lastPage ?? start))
            } else if isEPUB(book), let offset = progress.lastCharacterOffset {
                let chapters = epubPackage?.chapters ?? []
                if let index = chapters.lastIndex(where: { $0.startCharacter <= offset }) {
                    epubChapterIndex = min(max(0, chapters.count - 1), index)
                }
            } else if let offset = progress.lastCharacterOffset {
                let start = reading?.pageStart ?? 0
                let page = max(0, (offset - start) / textChunkSize)
                textPageIndex = min(max(0, textPages.count - 1), page)
            }
        } else {
            pdfPage = reading?.pageStart ?? 1
        }
    }

    private func loadTextPages(for book: FamilyBook) {
        let start = reading?.pageStart ?? 0
        let end = reading?.pageEnd ?? book.charCount
        guard let text = BookFileStore.shared.textSlice(fileName: book.fileName, from: start, to: end) else {
            textPages = []
            return
        }
        textPages = Self.paginate(text, chunkSize: textChunkSize)
        textPageIndex = min(textPageIndex, max(0, textPages.count - 1))
    }

    private func toggleBilingualTranslation() {
        if bilingualVisible,
           bilingualPageKey == currentTranslationCacheKey,
           !bilingualParagraphs.isEmpty {
            bilingualVisible = false
            return
        }
        translateCurrentPage()
    }

    private func translateCurrentPage() {
        let text = currentTextPageText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let key = currentTranslationCacheKey
        if let cached = bilingualCache[key] {
            bilingualVisible = true
            bilingualPageKey = key
            bilingualParagraphs = cached
            translationError = nil
            return
        }

        guard aiProvider.isReadyForChildAICompanion else {
            translationError = loc.pick("请让家长先开启 AI 章鱼老师。", "Ask a parent to turn on AI Octo Teacher first.")
            return
        }
        let paragraphs = AIReadingTranslator.paragraphs(from: text)
        guard !paragraphs.isEmpty else {
            translationError = loc.pick("这一页暂时没有可翻译的文字。", "There's no text to translate on this page.")
            return
        }

        translationTask?.cancel()
        bilingualVisible = true
        bilingualPageKey = key
        bilingualParagraphs = []
        translationError = nil
        isTranslating = true

        translationTask = Task {
            do {
                let result = try await aiProvider.translateReadingPage(
                    paragraphs: paragraphs,
                    childAge: store.child.age,
                    targetLanguage: .chinese,
                    using: OpenAIStyleChatClient()
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    bilingualCache[key] = result
                    bilingualPageKey = key
                    bilingualParagraphs = result
                    bilingualVisible = true
                    translationError = nil
                    isTranslating = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    translationError = loc.pick(
                        "翻译暂时没成功，英文原文可以继续读。",
                        "The translation didn't work this time — you can keep reading the original."
                    )
                    bilingualParagraphs = []
                    isTranslating = false
                }
            }
        }
    }

    private func handleTextPageChanged() {
        translationTask?.cancel()
        isTranslating = false
        translationError = nil
        let key = currentTranslationCacheKey
        if bilingualVisible, let cached = bilingualCache[key] {
            bilingualPageKey = key
            bilingualParagraphs = cached
        } else {
            bilingualPageKey = nil
            bilingualParagraphs = []
        }
    }

    private func persistSession(final: Bool) {
        let sessionSeconds = Int(Date().timeIntervalSince(startedAt))
        let delta = max(0, sessionSeconds - persistedSessionSeconds)
        if delta > 2 {
            store.recordReadingSeconds(delta, for: assignment.id)
        }
        if let book = importedBook {
            store.updateReadingProgress(
                childId: currentAssignment.childId,
                bookId: book.id,
                assignmentId: assignment.id,
                lastPage: isPDF(book) ? pdfPage : nil,
                lastCharacterOffset: readingCharacterOffset(for: book),
                fontSize: fontSize,
                speechRate: speechRate,
                secondsDelta: delta
            )
        }
        persistedSessionSeconds = sessionSeconds
        if final {
            elapsedSeconds = sessionSeconds
            if !didQueueCloudSession, sessionSeconds > 2, let book = importedBook {
                didQueueCloudSession = true
                familyCloud.queueActivityEvent(
                    clientRef: "activity:reading:\(cloudSessionRef)",
                    kind: .reading,
                    title: book.title,
                    durationSeconds: sessionSeconds,
                    progressPercent: readingProgressPercent(for: book),
                    resourceRef: "book:\(book.id.uuidString.lowercased())"
                )
            }
        }
    }

    private func readingProgressPercent(for book: FamilyBook) -> Double {
        if isPDF(book) {
            return Double(min(max(pdfPage, 1), max(book.pageCount, 1))) / Double(max(book.pageCount, 1)) * 100
        }
        if isEPUB(book) {
            let count = max(epubPackage?.chapters.count ?? book.chapters.count, 1)
            return Double(min(epubChapterIndex + 1, count)) / Double(count) * 100
        }
        let count = max(textPages.count, 1)
        return Double(min(textPageIndex + 1, count)) / Double(count) * 100
    }

    private func speakCurrentPage(_ book: FamilyBook) {
        let text: String?
        if isPDF(book),
           let url = BookFileStore.shared.url(fileName: book.fileName),
           let document = PDFDocument(url: url),
           let page = document.page(at: max(0, pdfPage - 1)) {
            text = page.string
        } else if isEPUB(book),
                  let chapter = epubPackage?.chapters[safe: epubChapterIndex] {
            text = BookFileStore.shared.textSlice(
                fileName: book.fileName,
                from: chapter.startCharacter,
                to: chapter.endCharacter
            )
        } else {
            text = textPages[safe: textPageIndex]
        }
        let resolved = String((text ?? "").prefix(1_800))
        if resolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // 兜底提示是 UI 文案：跟随孩子界面语言。
            SpeechReader.shared.speak(
                loc.pick("这一页没有可朗读的文字。", "There's nothing to read aloud on this page."),
                language: loc.language,
                voiceStyle: store.child.companionVoiceStyle,
                rateMultiplier: speechRate
            )
        } else {
            // 书正文：不传 language，按正文内容自动判断音色。
            SpeechReader.shared.speak(
                resolved,
                voiceStyle: store.child.companionVoiceStyle,
                rateMultiplier: speechRate
            )
        }
    }

    /// 正文朗读音色按内容语言自动判断（含中日韩字符用中文音色），不强制 UI 语言。
    private func contentSpeechLanguage(_ text: String) -> AppInterfaceLanguage {
        SpeechReader.languageCode(for: text) == "zh-CN" ? .chinese : .english
    }

    private func loadContentIfNeeded() async {
        guard let reading else { return }
        guard importedBook == nil else { return }
        if let cached = reading.inAppContent, !cached.isEmpty {
            content = cached
            return
        }
        guard reading.aiContentAllowed, aiProvider.isReadyForAIComposer else {
            return
        }
        isGenerating = true
        defer { isGenerating = false }
        do {
            let raw = try await aiProvider.completeDraftJSON(
                system: AIReadingContentGenerator.systemPrompt(language: store.activeContentLanguage),
                user: AIReadingContentGenerator.userPrompt(
                    bookTitle: reading.bookTitle,
                    chapters: reading.chapterPlanText,
                    childAge: store.child.age
                ),
                using: OpenAIStyleChatClient()
            )
            if let parsed = AIReadingContentGenerator.parse(raw) {
                contentTitle = parsed.title
                content = parsed.content
                store.updateReadingContent(parsed.content, for: assignment.id)
            }
        } catch {
            // 生成失败：回落到「去拿书读」引导，计时照常。
        }
    }

    // MARK: - 计算

    private var textCharacterOffset: Int {
        (reading?.pageStart ?? 0) + textPageIndex * textChunkSize
    }

    private var epubCharacterOffset: Int? {
        epubPackage?.chapters[safe: epubChapterIndex]?.startCharacter
    }

    private func readingCharacterOffset(for book: FamilyBook) -> Int? {
        if isEPUB(book) { return epubCharacterOffset }
        if isPlainTextBook(book) { return textCharacterOffset }
        return nil
    }

    private var currentTextPageText: String {
        textPages[safe: textPageIndex] ?? ""
    }

    private var currentTranslationCacheKey: String {
        let text = currentTextPageText
        let head = text.prefix(32)
        let bookID = importedBook?.id.uuidString ?? "generated"
        return "\(bookID)|\(textCharacterOffset)|\(text.count)|\(head)"
    }

    private func progressLabel(for book: FamilyBook) -> String {
        let percent = Int((readerProgress(for: book) * 100).rounded())
        let safePercent = min(100, max(0, percent))
        return loc.pick("本次进度 \(safePercent)%", "Progress \(safePercent)%")
    }

    private func readerProgress(for book: FamilyBook) -> Double {
        let progress: Double
        if isPDF(book) {
            let start = reading?.pageStart ?? 1
            let end = max(start, reading?.pageEnd ?? book.pageCount)
            let completed = min(max(1, pdfPage - start + 1), max(1, end - start + 1))
            progress = Double(completed) / Double(max(1, end - start + 1))
        } else if isEPUB(book), let package = epubPackage, !package.chapters.isEmpty {
            progress = Double(epubChapterIndex + 1) / Double(package.chapters.count)
        } else if !textPages.isEmpty {
            progress = Double(textPageIndex + 1) / Double(textPages.count)
        } else {
            progress = 0
        }
        return min(1, max(0, progress))
    }

    private func pageLabel(for book: FamilyBook) -> String {
        if isPDF(book) {
            return loc.pick("第 \(pdfPage) 页", "Page \(pdfPage)")
        }
        if isEPUB(book), let chapter = epubPackage?.chapters[safe: epubChapterIndex] {
            return loc.pick("第 \(chapter.order) 章", "Chapter \(chapter.order)")
        }
        if isPlainTextBook(book) {
            let pageText = loc.pick("第 \(textPageIndex + 1) 页", "Page \(textPageIndex + 1)")
            if let label = currentChapterLabel(for: book) {
                return "\(label) · \(pageText)"
            }
            return pageText
        }
        return book.format.uppercased()
    }

    private func bookDetailText(_ book: FamilyBook) -> String {
        let source = book.sourceName.map { loc.pick(" · 来源：\($0)", " · Source: \($0)") } ?? ""
        if isPDF(book) {
            return loc.pick(
                "\(book.format.uppercased()) · \(book.pageCount) 页\(source)",
                "\(book.format.uppercased()) · \(book.pageCount) pages\(source)"
            )
        }
        let chapterText = book.chapters.isEmpty
            ? ""
            : loc.pick(" · \(book.chapters.count) 章", " · \(book.chapters.count) chapters")
        return loc.pick(
            "\(book.format.uppercased()) · 约 \(max(1, book.charCount / 1000)) 千字\(chapterText)\(source)",
            "\(book.format.uppercased()) · about \(max(1, book.charCount / 1000))k characters\(chapterText)\(source)"
        )
    }

    private func isPDF(_ book: FamilyBook) -> Bool {
        book.format.lowercased() == "pdf" || book.fileName.lowercased().hasSuffix(".pdf")
    }

    private func isEPUB(_ book: FamilyBook) -> Bool {
        book.format.lowercased() == "epub" || book.fileName.lowercased().hasSuffix(".epub")
    }

    private func isPlainTextBook(_ book: FamilyBook) -> Bool {
        let format = book.format.lowercased()
        let fileName = book.fileName.lowercased()
        return ["txt", "html", "htm"].contains(format)
            || fileName.hasSuffix(".txt")
            || fileName.hasSuffix(".html")
            || fileName.hasSuffix(".htm")
    }

    private func currentChapterLabel(for book: FamilyBook) -> String? {
        guard !book.chapters.isEmpty else { return nil }
        let absoluteOffset = textCharacterOffset
        guard let chapter = book.chapters.last(where: { $0.startCharacter <= absoluteOffset }) else {
            return book.chapters.first.map { loc.pick("第 \($0.order) 章", "Chapter \($0.order)") }
        }
        return loc.pick("第 \(chapter.order) 章", "Chapter \(chapter.order)")
    }

    private static func paginate(_ text: String, chunkSize: Int) -> [String] {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }
        var pages: [String] = []
        var start = cleaned.startIndex
        while start < cleaned.endIndex {
            let end = cleaned.index(start, offsetBy: chunkSize, limitedBy: cleaned.endIndex) ?? cleaned.endIndex
            pages.append(String(cleaned[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines))
            start = end
        }
        return pages.filter { !$0.isEmpty }
    }
}

enum ChildReadingProgressCopy {
    // language 默认中文：保持既有调用方与测试行为不变，孩子端 View 显式传入界面语言。
    static func label(
        seconds: Int,
        targetMinutes: Int,
        isPreReader: Bool,
        language: AppInterfaceLanguage = .chinese
    ) -> String {
        if isPreReader {
            preReaderLabel(seconds: seconds, targetMinutes: targetMinutes, language: language)
        } else {
            numericLabel(seconds: seconds, language: language)
        }
    }

    static func numericLabel(seconds: Int, language: AppInterfaceLanguage = .chinese) -> String {
        let safeSeconds = max(0, seconds)
        return String(
            format: language.pick("已读 %d 分 %02d 秒", "Read %d min %02d sec"),
            safeSeconds / 60,
            safeSeconds % 60
        )
    }

    static func preReaderLabel(
        seconds: Int,
        targetMinutes: Int,
        language: AppInterfaceLanguage = .chinese
    ) -> String {
        let safeSeconds = max(0, seconds)
        let stars = preReaderStarCount(seconds: safeSeconds, targetMinutes: targetMinutes)
        let starText = String(repeating: "⭐️", count: stars) + String(repeating: "☆", count: 5 - stars)
        let prefix = language.pick("阅读星星", "Reading stars")
        if stars >= 5 {
            return "\(prefix) \(starText) \(language.pick("今天读够啦", "All done for today"))"
        }
        if stars == 0 {
            return "\(prefix) \(starText) \(language.pick("刚开始", "Just started"))"
        }
        return "\(prefix) \(starText) \(language.pick("继续读", "Keep reading"))"
    }

    static func preReaderStarCount(seconds: Int, targetMinutes: Int) -> Int {
        let safeSeconds = max(0, seconds)
        guard safeSeconds > 0 else { return 0 }
        let targetSeconds = max(60, targetMinutes * 60)
        let progress = Double(safeSeconds) / Double(targetSeconds)
        return min(5, max(1, Int(ceil(progress * 5))))
    }
}

private struct BookPDFView: UIViewRepresentable {
    let url: URL
    let startPage: Int
    let endPage: Int
    @Binding var currentPage: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(currentPage: $currentPage, startPage: startPage, endPage: endPage)
    }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        context.coordinator.pdfView = view
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: Notification.Name.PDFViewPageChanged,
            object: view
        )
        loadDocument(into: view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.startPage = startPage
        context.coordinator.endPage = endPage
        if view.document == nil {
            loadDocument(into: view)
        }
        guard let document = view.document else { return }
        let target = min(max(startPage, currentPage), max(startPage, endPage))
        if let page = document.page(at: max(0, target - 1)),
           view.currentPage != page {
            view.go(to: page)
        }
    }

    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    private func loadDocument(into view: PDFView) {
        guard let document = PDFDocument(url: url) else { return }
        view.document = document
        let targetPage = min(max(startPage, currentPage), max(startPage, endPage))
        if let page = document.page(at: max(0, targetPage - 1)) {
            view.go(to: page)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        @Binding var currentPage: Int
        weak var pdfView: PDFView?
        var startPage: Int
        var endPage: Int

        init(currentPage: Binding<Int>, startPage: Int, endPage: Int) {
            _currentPage = currentPage
            self.startPage = startPage
            self.endPage = endPage
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let view = pdfView,
                  let document = view.document,
                  let page = view.currentPage else { return }
            let pageNumber = document.index(for: page) + 1
            let clamped = min(max(startPage, pageNumber), max(startPage, endPage))
            if clamped != pageNumber,
               let target = document.page(at: max(0, clamped - 1)) {
                view.go(to: target)
            }
            currentPage = clamped
        }
    }
}

private struct BookEPUBWebView: UIViewRepresentable {
    let chapterURL: URL
    let readAccessURL: URL
    let fontSize: CGFloat
    // 子 View 没有 store：由父 View 传入孩子界面语言上下文，兜底提示走双语。
    let loc: ChildLocalizationContext

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.alwaysBounceVertical = true
        return view
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let roundedFont = Int(fontSize.rounded())
        guard context.coordinator.lastURL != chapterURL
                || context.coordinator.lastFontSize != roundedFont else { return }
        context.coordinator.lastURL = chapterURL
        context.coordinator.lastFontSize = roundedFont
        let rawHTML = (try? String(contentsOf: chapterURL, encoding: .utf8))
            ?? (try? String(contentsOf: chapterURL, encoding: .isoLatin1))
        guard let rawHTML else {
            let fallback = loc.pick("这一章暂时打不开。", "This chapter can't be opened right now.")
            webView.loadHTMLString("<html><body>\(fallback)</body></html>", baseURL: readAccessURL)
            return
        }
        do {
            let renderURL = try EPUBReaderHTMLRenderer.writeStyledChapter(
                rawHTML,
                sourceURL: chapterURL,
                fontSize: roundedFont
            )
            webView.loadFileURL(renderURL, allowingReadAccessTo: readAccessURL)
        } catch {
            webView.loadFileURL(chapterURL, allowingReadAccessTo: readAccessURL)
        }
    }
}

enum EPUBReaderHTMLRenderer {
    static func writeStyledChapter(_ html: String, sourceURL: URL, fontSize: Int) throws -> URL {
        let renderURL = renderedChapterURL(for: sourceURL, fontSize: fontSize)
        guard let data = readerHTML(html, fontSize: fontSize).data(using: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: renderURL, options: [.atomic])
        return renderURL
    }

    static func renderedChapterURL(for sourceURL: URL, fontSize: Int) -> URL {
        sourceURL
            .deletingLastPathComponent()
            .appendingPathComponent(".octoteacher-reader-\(fontSize)-\(sourceURL.lastPathComponent)")
    }

    static func readerHTML(_ html: String, fontSize: Int) -> String {
        let style = """
        <style id="octoteacher-reader-style">
        :root { color-scheme: light dark; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
          font-size: \(fontSize)px;
          line-height: 1.65;
          padding: 18px;
          margin: 0;
          background: transparent;
          color: CanvasText;
          overflow-wrap: anywhere;
        }
        img, svg {
          max-width: 100%;
          height: auto;
          display: block;
          margin: 12px auto;
          border-radius: 8px;
        }
        p { margin: 0 0 0.9em; }
        h1, h2, h3 { line-height: 1.25; }
        </style>
        """
        if html.range(of: "</head>", options: .caseInsensitive) != nil {
            return html.replacingOccurrences(of: "</head>", with: "\(style)</head>", options: .caseInsensitive)
        }
        return "<html><head>\(style)</head><body>\(html)</body></html>"
    }
}

extension BookEPUBWebView {
    final class Coordinator {
        var lastURL: URL?
        var lastFontSize: Int?
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
