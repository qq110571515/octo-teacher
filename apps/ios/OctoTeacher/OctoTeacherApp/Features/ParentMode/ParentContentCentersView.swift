import SwiftUI

/// 家长端内容资产中心：这里按"资源"聚合，不按"今天任务"展示。
/// 图书馆看已安装/下载/导入的书；教育视频看市场安装和历史安排过的视频资源。
struct ParentBookCenterView: View {
    @Environment(LocalFamilyStore.self) private var store
    @State private var catalog = LocalBookCatalogStore.runtimeCatalog()
    @State private var loadingCatalogBookID: Int?
    @State private var catalogFeedback: String?

    private var lang: AppInterfaceLanguage {
        store.settings.resolvedParentInterfaceLanguage
    }

    var body: some View {
        List {
            if !installedBookResources.isEmpty {
                Section {
                    ForEach(installedBookResources) { installed in
                        marketplaceBookRow(installed.resource)
                    }
                } header: {
                    Text(lang.pick("成长包市场已安装书目", "Installed Marketplace Books"))
                } footer: {
                    Text(lang.pick(
                        "安装成长包只加入书目。点击加载后才会下载 EPUB 并进入孩子端阅读器。",
                        "Installing a pack adds catalog entries only. Load a book to download its EPUB for the child reader."
                    ))
                }
            }

            Section {
                ForEach(catalog.categories) { section in
                    DisclosureGroup {
                        ForEach(section.books) { item in
                            catalogBookRow(item)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(section.category)
                                    .font(.headline)
                                Text("\(section.displayCount) 本 · 可扩展目录")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            } header: {
                Text(lang.pick("章鱼老师云端图书目录", "Octo Teacher Cloud Book Catalog"))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("现在读取本机运行态书库缓存；App 内置目录只用于首次启动或离线兜底。未来云端书库返回同样结构，手机端同步后就能看到新增书。")
                    if let catalogFeedback {
                        Text(catalogFeedback)
                    }
                }
            }

            Section {
                if store.books.isEmpty {
                    ContentUnavailableView(
                        "还没有下载或导入图书",
                        systemImage: "books.vertical",
                        description: Text("在「AI 布置阅读」里下载公版书，或导入你已经拥有的无 DRM EPUB/PDF/TXT/HTML。")
                    )
                } else {
                    ForEach(store.books) { book in
                        downloadedBookRow(book)
                    }
                }
            } header: {
                Text("已下载/已导入图书资源")
            } footer: {
                Text("这里是本机书库：只显示已经真正进入 章鱼老师 的图书文件，以及这些书被安排过多少次、孩子读到哪里。")
            }

            Section {
                if arrangedBookResources.isEmpty {
                    ContentUnavailableView(
                        "还没有安排过阅读资源",
                        systemImage: "bookmark",
                        description: Text("家长布置过阅读任务后，这里会按书名聚合显示，不会按今天任务逐条堆叠。")
                    )
                } else {
                    ForEach(arrangedBookResources) { resource in
                        arrangedBookResourceRow(resource)
                    }
                }
            } header: {
                Text("已安排过的阅读资源")
            } footer: {
                Text("这里回答「家里曾经给孩子安排过哪些书/章节」。如果资源未下载，只会标记为外部/实体书资源。")
            }
        }
        .navigationTitle(lang.pick("图书馆", "Library"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var installedBookResources: [TrainingMarketplaceInstalledResource] {
        store.installedMarketplaceResources
            .filter { $0.resource.kind == .book }
            .sorted { $0.resource.title.localizedCaseInsensitiveCompare($1.resource.title) == .orderedAscending }
    }

    private func marketplaceBookRow(_ resource: TrainingMarketplaceResource) -> some View {
        let item = marketplaceBookItem(resource)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("《\(resource.localizedTitle(lang))》")
                        .font(.subheadline.weight(.semibold))
                    Text(resource.localizedSummary(lang))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if let item {
                    if loadedCatalogBook(for: item) != nil {
                        Label(lang.pick("已加载", "Loaded"), systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    } else {
                        Button(lang.pick("加载", "Load")) {
                            Task { await loadCatalogBook(item) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(loadingCatalogBookID != nil)
                    }
                }
            }
            if let url = URL(string: resource.sourceURL) {
                Link(destination: url) {
                    Label(lang.pick("查看来源", "View Source"), systemImage: "safari")
                }
                .font(.caption2.weight(.semibold))
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("parent-library-market-resource-\(resource.id)")
    }

    private func marketplaceBookItem(_ resource: TrainingMarketplaceResource) -> LocalBookCatalogItem? {
        guard let match = resource.id.range(of: #"\d+$"#, options: .regularExpression),
              let identifier = Int(resource.id[match]) else { return nil }
        return LocalBookCatalogItem(
            id: identifier,
            title: resource.titleEnglish.isEmpty ? resource.title : resource.titleEnglish,
            category: resource.categories.first,
            file: nil,
            url: resource.sourceURL
        )
    }

    private var arrangedBookResources: [BookResourceSummary] {
        let assignments = store.assignments.filter { $0.task.reading != nil && $0.status != .cancelled }
        let grouped = Dictionary(grouping: assignments) { assignment in
            guard let reading = assignment.task.reading else { return assignment.id.uuidString }
            if let importedBookId = reading.importedBookId {
                return "book-\(importedBookId.uuidString)"
            }
            return "title-\(normalized(reading.bookTitle))"
        }
        return grouped.map { key, assignments in
            let sorted = assignments.sorted { $0.date > $1.date }
            let first = sorted[0]
            let reading = first.task.reading
            let linkedBook = store.book(for: reading)
            let title = linkedBook?.title ?? reading?.bookTitle ?? first.task.title
            let childNames = Array(Set(sorted.compactMap { childName(for: $0.childId) })).sorted()
            let chapters = sorted
                .compactMap { $0.task.reading?.chapterPlanText.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return BookResourceSummary(
                id: key,
                title: title,
                linkedBook: linkedBook,
                assignments: sorted,
                childNames: childNames,
                chapterPreview: Array(chapters.prefix(4)).joined(separator: "、")
            )
        }
        .sorted { lhs, rhs in
            lhs.latestDate == rhs.latestDate ? lhs.title < rhs.title : lhs.latestDate > rhs.latestDate
        }
    }

    private func catalogBookRow(_ item: LocalBookCatalogItem) -> some View {
        let loaded = loadedCatalogBook(for: item)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("《\(item.title)》")
                        .font(.subheadline.weight(.semibold))
                    Text("Project Gutenberg #\(item.id) · 含插图 EPUB 优先")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let loaded {
                    Label("已加载", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("parent-book-catalog-loaded-\(loaded.id.uuidString)")
                } else {
                    Button {
                        Task { await loadCatalogBook(item) }
                    } label: {
                        if loadingCatalogBookID == item.id {
                            ProgressView()
                        } else {
                            Text("加载")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(loadingCatalogBookID != nil)
                    .accessibilityIdentifier("parent-book-catalog-load-\(item.id)")
                }
            }
            HStack(spacing: 8) {
                if let url = item.sourceURL {
                    Link(destination: url) {
                        Label("来源页", systemImage: "safari")
                    }
                    .font(.caption2.weight(.semibold))
                }
                statusPill(item.categoryHint?.ageHint ?? "公版资源", systemImage: "person.2")
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("parent-book-catalog-row-\(item.id)")
    }

    private func downloadedBookRow(_ book: FamilyBook) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("《\(book.title)》")
                        .font(.headline)
                    Text(bookMetaText(book))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(fileLoaded(book) ? "已加载" : "文件丢失", systemImage: fileLoaded(book) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(fileLoaded(book) ? .green : .orange)
            }

            HStack(spacing: 8) {
                statusPill("安排 \(assignmentCount(for: book)) 次", systemImage: "checklist")
                statusPill(progressText(for: book), systemImage: "bookmark.fill")
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("parent-book-center-downloaded-\(book.id.uuidString)")
    }

    private func loadedCatalogBook(for item: LocalBookCatalogItem) -> FamilyBook? {
        store.books.first {
            $0.sourceURLString == item.downloadURL?.absoluteString
                || $0.sourceURLString == item.url
                || $0.title.localizedCaseInsensitiveCompare(item.title) == .orderedSame
        }
    }

    @MainActor
    private func loadCatalogBook(_ item: LocalBookCatalogItem) async {
        guard let candidate = item.downloadCandidate else {
            catalogFeedback = "这本书暂时没有可下载链接。"
            return
        }
        loadingCatalogBookID = item.id
        defer { loadingCatalogBookID = nil }
        guard let downloaded = await EbookDownloader().download(candidates: [candidate.downloadURL]),
              let fileName = BookFileStore.shared.importBook(data: downloaded.data, ext: downloaded.ext),
              let analysis = BookFileStore.shared.analyzeDetailed(fileName: fileName) else {
            catalogFeedback = "加载《\(item.title)》失败：下载源没有返回可识别的 EPUB/TXT/PDF。"
            return
        }
        let book = store.addBook(
            title: item.title,
            fileName: fileName,
            format: downloaded.ext,
            pageCount: analysis.pageCount,
            charCount: analysis.charCount,
            chapters: analysis.chapters,
            sourceName: candidate.sourceName,
            sourceURLString: candidate.downloadURL.absoluteString
        )
        catalogFeedback = "已加载《\(book.title)》，现在可以在 AI 布置阅读或任务中心安排给孩子。"
    }

    private func arrangedBookResourceRow(_ resource: BookResourceSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("《\(resource.title)》")
                        .font(.headline)
                    Text(resource.linkedBook.map(bookMetaText) ?? "外部/实体书资源 · 未加载到 App 书库")
                        .font(.caption)
                        .foregroundStyle(resource.linkedBook == nil ? .orange : .secondary)
                }
                Spacer()
                Label(resource.linkedBook.map { fileLoaded($0) } == true ? "App 内可读" : "需外部阅读", systemImage: resource.linkedBook == nil ? "rectangle.on.rectangle" : "book.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(resource.linkedBook == nil ? .orange : .green)
            }

            if !resource.chapterPreview.isEmpty {
                Text("安排范围：\(resource.chapterPreview)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                statusPill("安排 \(resource.assignments.count) 次", systemImage: "checklist")
                statusPill("完成 \(resource.approvedCount)/\(resource.assignments.count)", systemImage: "checkmark.seal")
                if resource.submittedCount > 0 {
                    statusPill("待审核 \(resource.submittedCount)", systemImage: "tray.full")
                }
            }

            if !resource.childNames.isEmpty {
                Text("关联孩子：\(resource.childNames.joined(separator: "、"))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("parent-book-center-arranged-\(resource.id)")
    }

    private func bookMetaText(_ book: FamilyBook) -> String {
        let source = book.sourceName.map { " · 来源：\($0)" } ?? ""
        if book.format.lowercased() == "pdf" {
            return "\(book.format.uppercased()) · \(book.pageCount) 页\(source)"
        }
        let chapters = book.chapters.isEmpty ? "" : " · \(book.chapters.count) 章"
        return "\(book.format.uppercased()) · 约 \(max(1, book.charCount / 1000)) 千字\(chapters)\(source)"
    }

    private func fileLoaded(_ book: FamilyBook) -> Bool {
        BookFileStore.shared.url(fileName: book.fileName) != nil
    }

    private func assignmentCount(for book: FamilyBook) -> Int {
        store.assignments.filter { assignment in
            guard let reading = assignment.task.reading else { return false }
            return reading.importedBookId == book.id || reading.bookTitle.localizedCaseInsensitiveContains(book.title)
        }.count
    }

    private func progressText(for book: FamilyBook) -> String {
        let progresses = store.bookReadingProgress.filter { $0.bookId == book.id }
        let seconds = progresses.reduce(0) { $0 + $1.totalSeconds }
        let minutes = seconds / 60
        let percent: Int
        if book.format.lowercased() == "pdf", book.pageCount > 0 {
            let page = progresses.compactMap(\.lastPage).max() ?? 0
            percent = Int((Double(page) / Double(book.pageCount) * 100).rounded())
        } else if book.charCount > 0 {
            let offset = progresses.compactMap(\.lastCharacterOffset).max() ?? 0
            percent = Int((Double(offset) / Double(book.charCount) * 100).rounded())
        } else {
            percent = 0
        }
        if minutes == 0 {
            return "未开始"
        }
        return "已读 \(minutes) 分 · \(min(100, max(0, percent)))%"
    }

    private func statusPill(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.secondarySystemBackground), in: Capsule())
    }

    private func childName(for childId: UUID) -> String? {
        store.children.first(where: { $0.id == childId })?.name
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct ParentVideoCenterView: View {
    @Environment(LocalFamilyStore.self) private var store

    private var lang: AppInterfaceLanguage {
        store.settings.resolvedParentInterfaceLanguage
    }

    var body: some View {
        List {
            if !installedVideoResources.isEmpty {
                Section {
                    ForEach(installedVideoResources) { installed in
                        installedVideoRow(installed.resource)
                    }
                } header: {
                    Text(lang.pick("成长包市场已安装视频", "Installed Marketplace Videos"))
                } footer: {
                    Text(lang.pick(
                        "安装不会自动布置任务。先预览内容，再从视频任务入口安排给孩子。",
                        "Installation never assigns tasks automatically. Preview first, then assign from the video task workflow."
                    ))
                }
            }

            Section {
                if arrangedVideoResources.isEmpty {
                    ContentUnavailableView(
                        lang.pick("还没有安排过视频资源", "No assigned video resources yet"),
                        systemImage: "play.rectangle",
                        description: Text(lang.pick(
                            "家长确认并布置过视频学习后，这里会按视频资源聚合显示。",
                            "Videos appear here after a parent reviews and assigns them."
                        ))
                    )
                } else {
                    ForEach(arrangedVideoResources) { resource in
                        videoResourceRow(resource)
                    }
                }
            } header: {
                Text(lang.pick("已安排过的视频资源", "Previously Assigned Videos"))
            } footer: {
                Text(lang.pick(
                    "这里不是当前任务列表，而是内容管理视角：家长曾经选择、确认并安排过哪些学习视频，以及孩子反馈情况。",
                    "This is a content-management view of videos parents selected and assigned, plus child feedback."
                ))
            }
        }
        .navigationTitle(lang.pick("教育视频", "Educational Videos"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var installedVideoResources: [TrainingMarketplaceInstalledResource] {
        store.installedMarketplaceResources
            .filter { $0.resource.kind == .video }
            .sorted {
                if $0.resource.minAge == $1.resource.minAge {
                    return $0.resource.title.localizedCaseInsensitiveCompare($1.resource.title) == .orderedAscending
                }
                return $0.resource.minAge < $1.resource.minAge
            }
    }

    private func installedVideoRow(_ resource: TrainingMarketplaceResource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(resource.localizedTitle(lang))
                        .font(.subheadline.weight(.semibold))
                    Text(lang.pick(
                        "\(resource.sourceName) · 建议 \(resource.minAge)-\(resource.maxAge) 岁",
                        "\(resource.sourceName) · Ages \(resource.minAge)-\(resource.maxAge)"
                    ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Label(lang.pick("已安装", "Installed"), systemImage: "checkmark.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
            }
            Text(resource.localizedSummary(lang))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            HStack(spacing: 10) {
                if let url = URL(string: resource.sourceURL) {
                    Link(destination: url) {
                        Label(lang.pick("预览视频", "Preview Video"), systemImage: "play.rectangle")
                    }
                }
                if resource.durationSeconds > 0 {
                    Text(lang.pick(
                        "约 \(max(1, resource.durationSeconds / 60)) 分钟",
                        "About \(max(1, resource.durationSeconds / 60)) min"
                    ))
                }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("parent-educational-video-market-resource-\(resource.id)")
    }

    private var arrangedVideoResources: [VideoResourceSummary] {
        let assignments = store.assignments.filter { $0.task.video != nil && $0.status != .cancelled }
        let grouped = Dictionary(grouping: assignments) { assignment in
            let video = assignment.task.video
            let urlKey = video?.urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            return urlKey.isEmpty ? "title-\(normalized(assignment.task.title))" : "url-\(urlKey)"
        }
        return grouped.map { key, assignments in
            let sorted = assignments.sorted { $0.date > $1.date }
            let first = sorted[0]
            let video = first.task.video
            let childNames = Array(Set(sorted.compactMap { childName(for: $0.childId) })).sorted()
            let latestFeedback = sorted
                .map { $0.proof.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            return VideoResourceSummary(
                id: key,
                title: first.task.title,
                platformLabel: video?.platformLabel ?? "视频",
                urlString: video?.urlString,
                contentSummary: video?.contentSummary,
                minWatchMinutes: video?.minWatchMinutes ?? 0,
                assignments: sorted,
                childNames: childNames,
                latestFeedback: latestFeedback
            )
        }
        .sorted { lhs, rhs in
            lhs.latestDate == rhs.latestDate ? lhs.title < rhs.title : lhs.latestDate > rhs.latestDate
        }
    }

    private func videoResourceRow(_ resource: VideoResourceSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(resource.title)
                        .font(.headline)
                    Text("\(resource.platformLabel) · 至少 \(resource.minWatchMinutes) 分钟")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("已安排", systemImage: "play.rectangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }

            if let summary = resource.contentSummary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 8) {
                statusPill("安排 \(resource.assignments.count) 次", systemImage: "checklist")
                statusPill("完成 \(resource.approvedCount)/\(resource.assignments.count)", systemImage: "checkmark.seal")
                if resource.submittedCount > 0 {
                    statusPill("待审核 \(resource.submittedCount)", systemImage: "tray.full")
                }
            }

            if !resource.childNames.isEmpty {
                Text("关联孩子：\(resource.childNames.joined(separator: "、"))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let latestFeedback = resource.latestFeedback {
                Text("最近反馈：\(latestFeedback)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let urlString = resource.urlString, let url = URL(string: urlString) {
                Link("打开视频资源链接", destination: url)
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("parent-video-center-resource-\(resource.id)")
    }

    private func statusPill(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.secondarySystemBackground), in: Capsule())
    }

    private func childName(for childId: UUID) -> String? {
        store.children.first(where: { $0.id == childId })?.name
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct BookResourceSummary: Identifiable {
    var id: String
    var title: String
    var linkedBook: FamilyBook?
    var assignments: [TaskAssignment]
    var childNames: [String]
    var chapterPreview: String

    var latestDate: Date { assignments.map(\.date).max() ?? .distantPast }
    var approvedCount: Int { assignments.filter { $0.status == .approved }.count }
    var submittedCount: Int { assignments.filter { $0.status == .submitted }.count }
}

private struct VideoResourceSummary: Identifiable {
    var id: String
    var title: String
    var platformLabel: String
    var urlString: String?
    var contentSummary: String?
    var minWatchMinutes: Int
    var assignments: [TaskAssignment]
    var childNames: [String]
    var latestFeedback: String?

    var latestDate: Date { assignments.map(\.date).max() ?? .distantPast }
    var approvedCount: Int { assignments.filter { $0.status == .approved }.count }
    var submittedCount: Int { assignments.filter { $0.status == .submitted }.count }
}
