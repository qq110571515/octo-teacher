import SwiftUI
import UniformTypeIdentifiers

/// 导入已购电子书并自动布置阅读计划。
///
/// 流程：选文件（EPUB/PDF/TXT/HTML，无 DRM）→ App 分析页数/单词数/章节 → 按
/// 普通书每次约 5,000-10,000 词、图文书每两章，或家长指定次数来划分 → 家长确认布置。
/// 说明：Kindle、微信读书等 DRM 加密书无法导入任何第三方 App（行业限制）；
/// 公版书（Project Gutenberg 等）和无 DRM 版本可直接导入。
struct ParentBookImportView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(FamilyCloudSessionStore.self) private var familyCloud
    @Environment(\.dismiss) private var dismiss

    @State private var showFilePicker = false
    @State private var importedFileName: String?
    @State private var bookTitle = ""
    @State private var stats: (pageCount: Int, charCount: Int)?
    @State private var bookAnalysis: BookFileStore.BookAnalysis?
    @State private var drafts: [ReadingSessionDraft] = []
    @State private var planMode: ReadingPlanMode = .automatic
    @State private var customSessionCount = 4
    @State private var rewardPoints = 20
    @State private var feedback: String?

    var body: some View {
        Form {
            targetSection
            importSection
            if stats != nil { planSection }
            librarySection
        }
        .navigationTitle("导入电子书")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.epubBook, .pdf, .plainText, .html],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                handlePicked(url)
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
                        Text("\(member.name)（\(member.age) 岁）").tag(member.id)
                    }
                }
            } else {
                LabeledContent("布置给", value: "\(store.child.name)（\(store.child.age) 岁）")
            }
        }
    }

    private var importSection: some View {
        Section {
            Button {
                showFilePicker = true
            } label: {
                Label(importedFileName == nil ? "选择电子书文件（EPUB / PDF / TXT / HTML）" : "换一本", systemImage: "doc.badge.plus")
            }
            .accessibilityIdentifier("book-import-pick")

            if importedFileName != nil {
                TextField("书名（用于计划和记录）", text: $bookTitle)
                    .accessibilityIdentifier("book-import-title")
                if let stats {
                    Text(stats.pageCount > 1
                         ? "共 \(stats.pageCount) 页 · 约 \(stats.charCount / 1000) 千字"
                         : "约 \(stats.charCount / 1000) 千字")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("第一步：导入")
        } footer: {
            Text("支持无 DRM 的 EPUB/PDF/TXT/HTML（公版书、开放版本）。Kindle/微信读书等加密电子书无法被任何第三方 App 读取——这是行业限制，不是故障。文件只存本机。")
        }
    }

    private var planSection: some View {
        Section {
            Picker(lang.pick("阅读次数划分", "Reading session plan"), selection: $planMode) {
                Text(lang.pick("自动划分", "Automatic")).tag(ReadingPlanMode.automatic)
                Text(lang.pick("家长指定次数", "Parent chooses")).tag(ReadingPlanMode.custom)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("book-import-plan-mode")

            if planMode == .custom {
                Stepper(
                    lang.pick("整本书分成 \(customSessionCount) 次", "Split the book into \(customSessionCount) sessions"),
                    value: $customSessionCount,
                    in: 1...customSessionUpperBound
                )
                .accessibilityIdentifier("book-import-custom-session-count")
            } else {
                Label(automaticPlanExplanation, systemImage: "wand.and.stars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                rebuildPlan()
            } label: {
                Label(lang.pick("按当前设置重新划分", "Rebuild with these settings"), systemImage: "arrow.triangle.2.circlepath")
            }
            .accessibilityIdentifier("book-import-rebuild-plan")

            ForEach($drafts) { $draft in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("第 \(draft.order) 次")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(GrowthCreditCopy.label(points: draft.suggestedPoints ?? rewardPoints))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    TextField("范围", text: $draft.chapters)
                }
            }
            .onDelete { drafts.remove(atOffsets: $0); renumber() }

            Picker("每次成长积分", selection: $rewardPoints) {
                ForEach([10, 15, 20, 30, 45], id: \.self) { points in
                    Text(GrowthCreditCopy.label(points: points)).tag(points)
                }
            }
            Button {
                assignAll()
            } label: {
                Text("给\(store.child.name)布置这 \(drafts.count) 次阅读")
                    .frame(maxWidth: .infinity)
            }
            .disabled(drafts.isEmpty || bookTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("book-import-assign")
        } header: {
            Text("第二步：划分阅读次数")
        } footer: {
            Text("普通文本每次约 5,000-10,000 个单词；幼儿图文书每 2 章一次。也可以由家长指定整本书的阅读次数。")
            if let feedback { Text(feedback) }
        }
    }

    private var librarySection: some View {
        Section("已导入的书（\(store.books.count)）") {
            if store.books.isEmpty {
                Text("还没有导入过电子书。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.books) { book in
                    HStack {
                        Text(book.format == "pdf" ? "📕" : "📄")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(book.title)
                                .font(.subheadline)
                            Text(book.pageCount > 1 ? "\(book.pageCount) 页" : "约 \(book.charCount / 1000) 千字")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            _ = store.removeBook(book.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - 动作

    private func renumber() {
        for index in drafts.indices {
            drafts[index].order = index + 1
        }
    }

    private var lang: AppInterfaceLanguage {
        store.settings.resolvedParentInterfaceLanguage
    }

    private var requestedSessionCount: Int? {
        planMode == .custom ? customSessionCount : nil
    }

    private var customSessionUpperBound: Int {
        guard let analysis = bookAnalysis else { return 60 }
        if !analysis.chapters.isEmpty { return max(1, min(100, analysis.chapters.count)) }
        if analysis.pageCount > 1 { return max(1, min(100, analysis.pageCount)) }
        return 100
    }

    private var usesPictureBookPlanning: Bool {
        bookAnalysis?.isLikelyPictureBook == true
    }

    private var automaticPlanExplanation: String {
        usesPictureBookPlanning
            ? lang.pick(
                "检测为幼儿图文书：每 2 章形成一次阅读任务。",
                "Detected a picture book: every 2 chapters becomes one reading task."
            )
            : lang.pick(
                "普通文本按每次约 5,000-10,000 个单词自动划分。",
                "Regular text is split into about 5,000-10,000 words per session."
            )
    }

    private func handlePicked(_ url: URL) {
        guard let fileName = BookFileStore.shared.importBook(from: url) else {
            feedback = "导入失败：只支持无 DRM 的 EPUB/PDF/TXT/HTML 文件。"
            return
        }
        guard let analyzed = BookFileStore.shared.analyzeDetailed(fileName: fileName) else {
            BookFileStore.shared.delete(fileName: fileName)
            feedback = "读不出这个文件的内容（可能有 DRM 加密），换一个版本试试。"
            return
        }
        importedFileName = fileName
        stats = (analyzed.pageCount, analyzed.charCount)
        bookAnalysis = analyzed
        bookTitle = url.deletingPathExtension().lastPathComponent
        clampCustomSessionCount(to: analyzed)
        drafts = makePlan(from: analyzed)
        feedback = nil
    }

    private func rebuildPlan() {
        guard let analysis = bookAnalysis else { return }
        clampCustomSessionCount(to: analysis)
        drafts = makePlan(from: analysis)
        feedback = "已按当前设置重新划分为 \(drafts.count) 次。"
    }

    private func makePlan(from analysis: BookFileStore.BookAnalysis) -> [ReadingSessionDraft] {
        if analysis.chapters.isEmpty {
            return BookImportPlanner.plan(
                pageCount: analysis.pageCount,
                charCount: analysis.charCount,
                wordCount: analysis.wordCount,
                age: store.child.age,
                requestedSessions: requestedSessionCount
            )
        }
        return BookImportPlanner.plan(
            chapters: analysis.chapters,
            charCount: analysis.charCount,
            wordCount: analysis.wordCount,
            age: store.child.age,
            isPictureBook: usesPictureBookPlanning,
            requestedSessions: requestedSessionCount
        )
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
        guard let fileName = importedFileName, let stats else { return }
        let format = fileName.split(separator: ".").last.map { String($0).lowercased() } ?? "txt"
        let book = store.addBook(
            title: bookTitle,
            fileName: fileName,
            format: format,
            pageCount: stats.pageCount,
            charCount: stats.charCount,
            chapters: BookFileStore.shared.analyzeDetailed(fileName: fileName)?.chapters ?? []
        )
        let sessions = drafts.count
        var assigned = 0
        var createdAssignmentIDs: [UUID] = []
        for (index, draft) in drafts.enumerated() {
            let range: (start: Int, end: Int)
            if format == "pdf" {
                range = BookImportPlanner.pageRange(index: index, sessions: sessions, pageCount: stats.pageCount)
            } else if let start = draft.startCharacter, let end = draft.endCharacter {
                range = (start, end)
            } else {
                range = BookImportPlanner.charRange(index: index, sessions: sessions, charCount: stats.charCount)
            }
            let created = store.assignNewTask(
                title: "读《\(book.title)》第 \(draft.order) 次",
                instructions: "在 App 里翻到这一段读完，然后说说学到了什么。不限时，读懂最重要。",
                category: .learning,
                rewardMinutes: draft.suggestedPoints ?? rewardPoints,
                requiredProof: .text,
                reading: ReadingSpec(
                    bookTitle: book.title,
                    minMinutes: draft.estimatedMinutes,
                    chapterPlanText: draft.chapters,
                    importedBookId: book.id,
                    pageStart: range.start,
                    pageEnd: range.end,
                    deliveryMode: .digitalLoaded
                ),
                verification: store.isPreReaderActive
                    ? .retell(seconds: 180, contentKind: .story)
                    : .reading(questionCount: 5, contentKind: .story)
            )
            if let created {
                assigned += 1
                createdAssignmentIDs.append(created.id)
            }
        }
        if familyCloud.isGuardianSignedIn,
           !createdAssignmentIDs.isEmpty,
           !familyCloud.queueGuardianTaskUpserts(assignmentIds: createdAssignmentIDs, local: store) {
            feedback = "阅读任务已保存在本机，但还没有进入家庭云同步队列。"
            return
        }
        feedback = "已布置 \(assigned) 次阅读，孩子可以直接在 App 里读这本书。"
        if assigned > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                dismiss()
            }
        }
    }
}

private extension UTType {
    static var epubBook: UTType {
        UTType(filenameExtension: "epub") ?? .data
    }
}
