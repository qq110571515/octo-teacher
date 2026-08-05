import XCTest
import ZIPFoundation
@testable import OctoTeacher

/// v5K 回归：电子书导入、体量分次规划、电子版渠道、书库持久化。
final class BookImportTests: XCTestCase {

    // MARK: - 分次规划

    func testPlannerUsesFiveToTenThousandWordsPerSession() {
        // 2.2 万词 → 目标约 7500 词/次 → 3 次，每次保持在约 5000-10000 词。
        let drafts = BookImportPlanner.plan(pageCount: 90, charCount: 110_000, wordCount: 22_000, age: 9)
        XCTAssertEqual(drafts.count, 3)
        XCTAssertEqual(drafts[0].chapters, "第 1-30 页")
        XCTAssertEqual(drafts[2].chapters, "第 61-90 页", "末次覆盖到最后一页")

        // 规则不再因年龄产生完全不同的次数；不足 1 万词的薄书一次完成。
        XCTAssertEqual(BookImportPlanner.plan(pageCount: 90, charCount: 45_000, wordCount: 9_000, age: 6).count, 1)
        XCTAssertEqual(BookImportPlanner.plan(pageCount: 10, charCount: 3_000, wordCount: 600, age: 14).count, 1)
        XCTAssertTrue(BookImportPlanner.plan(pageCount: 0, charCount: 0, age: 9).isEmpty)
    }

    func testPictureBookUsesTwoChaptersPerSession() {
        let chapters = (1...5).map { order in
            BookChapter(
                order: order,
                title: "图画 \(order)",
                startCharacter: (order - 1) * 100,
                endCharacter: order * 100
            )
        }
        let drafts = BookImportPlanner.plan(
            chapters: chapters,
            charCount: 500,
            wordCount: 80,
            age: 6,
            isPictureBook: true
        )
        XCTAssertEqual(drafts.count, 3)
        XCTAssertEqual(drafts[0].chapters, "第 1-2 章：图画 1 到 图画 2")
        XCTAssertEqual(drafts[2].chapters, "第 5 章：图画 5")
        XCTAssertEqual(drafts[0].startCharacter, 0)
        XCTAssertEqual(drafts[2].endCharacter, 500)
    }

    func testParentSelectedSessionCountIsExactAndCoversAllChapters() {
        let chapters = (1...10).map { order in
            BookChapter(
                order: order,
                title: "Chapter \(order)",
                startCharacter: (order - 1) * 1_000,
                endCharacter: order * 1_000
            )
        }
        let drafts = BookImportPlanner.plan(
            chapters: chapters,
            charCount: 10_000,
            wordCount: 2_000,
            age: 8,
            requestedSessions: 3
        )
        XCTAssertEqual(drafts.count, 3)
        XCTAssertEqual(drafts.map(\.startCharacter), [0, 3_000, 7_000])
        XCTAssertEqual(drafts.map(\.endCharacter), [3_000, 7_000, 10_000])

        let pages = BookImportPlanner.plan(
            pageCount: 80,
            charCount: 40_000,
            wordCount: 8_000,
            age: 8,
            requestedSessions: 4
        )
        XCTAssertEqual(pages.count, 4)
        XCTAssertEqual(pages.last?.chapters, "第 61-80 页")
    }

    func testPageAndCharRangesCoverWholeBook() {
        let last = BookImportPlanner.pageRange(index: 2, sessions: 3, pageCount: 100)
        XCTAssertEqual(last.end, 100)
        let first = BookImportPlanner.pageRange(index: 0, sessions: 3, pageCount: 100)
        XCTAssertEqual(first.start, 1)

        let charLast = BookImportPlanner.charRange(index: 2, sessions: 3, charCount: 10_000)
        XCTAssertEqual(charLast.end, 10_000)
    }

    // MARK: - 文件库（TXT 路径）

    func testTxtImportAnalyzeAndSlice() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("book-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BookFileStore(directory: directory)

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("book-\(UUID().uuidString).txt")
        try "从前有一只章鱼老师，住在大海边。它每天都很努力。".write(to: tmp, atomically: true, encoding: .utf8)

        let fileName = try XCTUnwrap(store.importBook(from: tmp))
        let stats = try XCTUnwrap(store.analyze(fileName: fileName))
        XCTAssertEqual(stats.pageCount, 1)
        XCTAssertGreaterThan(stats.charCount, 10)
        XCTAssertGreaterThan(try XCTUnwrap(store.analyzeDetailed(fileName: fileName)).wordCount, 10)

        let slice = try XCTUnwrap(store.textSlice(fileName: fileName, from: 0, to: 5))
        XCTAssertEqual(slice, "从前有一只")

        let book = FamilyBook(
            id: UUID(),
            title: "章鱼老师",
            fileName: fileName,
            format: "txt",
            pageCount: 1,
            charCount: stats.charCount,
            importedAt: Date()
        )
        let excerpt = try XCTUnwrap(store.readingExcerpt(
            book: book,
            reading: ReadingSpec(bookTitle: "章鱼老师", minMinutes: 10, chapterPlanText: "第一段", pageStart: 0, pageEnd: 9),
            maxCharacters: 20
        ))
        XCTAssertTrue(excerpt.contains("从前有一只章鱼老师"))

        store.delete(fileName: fileName)
        XCTAssertNil(store.url(fileName: fileName))
    }

    func testHTMLImportAnalyzeAndSlice() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("book-html-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BookFileStore(directory: directory)

        let html = """
        <html><head><style>.x{}</style></head><body><h1>第一章</h1><p>孩子在院子里发现了一颗种子。</p><script>bad()</script></body></html>
        """
        let fileName = try XCTUnwrap(store.importBook(data: Data(html.utf8), ext: "html"))
        let stats = try XCTUnwrap(store.analyze(fileName: fileName))
        XCTAssertEqual(stats.pageCount, 1)
        XCTAssertGreaterThan(stats.charCount, 10)

        let slice = try XCTUnwrap(store.textSlice(fileName: fileName, from: 0, to: stats.charCount))
        XCTAssertTrue(slice.contains("第一章"))
        XCTAssertTrue(slice.contains("孩子在院子里发现了一颗种子。"))
        XCTAssertFalse(slice.contains("<p>"))
        XCTAssertFalse(slice.contains("bad()"))
    }

    func testUnsupportedFormatRejected() throws {
        let store = BookFileStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("book-rej-\(UUID().uuidString)", isDirectory: true))
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("book.mobi")
        try Data("zip".utf8).write(to: tmp)
        XCTAssertNil(store.importBook(from: tmp), "只支持 EPUB/PDF/TXT/HTML")
    }

    func testEPUBImportAnalyzeChaptersAndSlice() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("book-epub-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BookFileStore(directory: directory)

        let epub = try makeMinimalEPUB()
        let fileName = try XCTUnwrap(store.importBook(data: epub, ext: "epub"))
        let analysis = try XCTUnwrap(store.analyzeDetailed(fileName: fileName))
        XCTAssertEqual(analysis.pageCount, 2)
        XCTAssertEqual(analysis.chapters.count, 2)
        XCTAssertEqual(analysis.chapters.first?.title, "第一章 出发")
        XCTAssertGreaterThan(analysis.charCount, 20)

        let first = try XCTUnwrap(analysis.chapters.first)
        let slice = try XCTUnwrap(store.textSlice(fileName: fileName, from: first.startCharacter, to: first.endCharacter))
        XCTAssertTrue(slice.contains("孩子带着星星伙伴出发"))

        let book = FamilyBook(
            id: UUID(),
            title: "星星伙伴",
            fileName: fileName,
            format: "epub",
            pageCount: analysis.pageCount,
            charCount: analysis.charCount,
            chapters: analysis.chapters,
            importedAt: Date()
        )
        let excerpt = try XCTUnwrap(store.readingExcerpt(
            book: book,
            reading: ReadingSpec(
                bookTitle: "星星伙伴",
                minMinutes: 10,
                chapterPlanText: "第一章",
                importedBookId: book.id,
                pageStart: first.startCharacter,
                pageEnd: first.endCharacter
            )
        ))
        XCTAssertTrue(excerpt.contains("星星伙伴出发"))
    }

    func testEPUBRenderPackageKeepsRelativeImagesReadable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("book-epub-image-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BookFileStore(directory: directory)

        let epub = try makeMinimalEPUBWithImage()
        let fileName = try XCTUnwrap(store.importBook(data: epub, ext: "epub"))
        let package = try XCTUnwrap(store.prepareEPUBForReading(fileName: fileName))
        let chapter = try XCTUnwrap(package.chapters.first)
        let rawHTML = try String(contentsOf: chapter.fileURL, encoding: .utf8)

        XCTAssertTrue(rawHTML.contains(#"src="images/star.png""#))
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.rootURL.appendingPathComponent("OEBPS/images/star.png").path))

        let renderURL = try EPUBReaderHTMLRenderer.writeStyledChapter(rawHTML, sourceURL: chapter.fileURL, fontSize: 24)
        XCTAssertEqual(renderURL.deletingLastPathComponent(), chapter.fileURL.deletingLastPathComponent())
        XCTAssertTrue(FileManager.default.fileExists(atPath: renderURL.path))
        let renderedHTML = try String(contentsOf: renderURL, encoding: .utf8)
        XCTAssertTrue(renderedHTML.contains("octoteacher-reader-style"))
        XCTAssertTrue(renderedHTML.contains(#"src="images/star.png""#), "样式注入不能破坏 EPUB 图片相对路径")
    }

    func testEPUBSkipsNonLinearLinkedImagePages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("book-epub-linear-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BookFileStore(directory: directory)

        let epub = try makeEPUBWithLinkedImageHelperPage()
        let fileName = try XCTUnwrap(store.importBook(data: epub, ext: "epub"))

        let analysis = try XCTUnwrap(store.analyzeDetailed(fileName: fileName))
        XCTAssertEqual(analysis.pageCount, 1)
        XCTAssertEqual(analysis.chapters.map(\.title), ["字母正文"])
        XCTAssertTrue(analysis.chapters.first.map { analysis.charCount == $0.endCharacter } == true)
        XCTAssertFalse(try XCTUnwrap(store.plainText(fileName: fileName)).contains("back"))

        let package = try XCTUnwrap(store.prepareEPUBForReading(fileName: fileName))
        XCTAssertEqual(package.chapters.count, 1)
        XCTAssertEqual(package.chapters.first?.title, "字母正文")
        XCTAssertTrue(try XCTUnwrap(package.chapters.first?.fileURL.lastPathComponent).contains("alphabet"))
    }

    func testEPUBSkipsLinkedImagePagesEvenWhenPublisherMarksThemLinear() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("book-epub-mislabelled-helper-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BookFileStore(directory: directory)

        let epub = try makeEPUBWithMislabelledLinkedImageHelperPage()
        let fileName = try XCTUnwrap(store.importBook(data: epub, ext: "epub"))

        let analysis = try XCTUnwrap(store.analyzeDetailed(fileName: fileName))
        XCTAssertEqual(analysis.pageCount, 1)
        XCTAssertEqual(analysis.chapters.map(\.title), ["数字童谣正文"])
        XCTAssertFalse(try XCTUnwrap(store.plainText(fileName: fileName)).contains("back"))

        let package = try XCTUnwrap(store.prepareEPUBForReading(fileName: fileName))
        XCTAssertEqual(package.chapters.count, 1)
        XCTAssertEqual(package.chapters.first?.title, "数字童谣正文")
        XCTAssertTrue(try XCTUnwrap(package.chapters.first?.fileURL.lastPathComponent).contains("book-content"))
    }

    // MARK: - 电子版渠道（内容语言主导）

    func testEnglishContentGetsInternationalEbookChannels() {
        // 关键回归：即使地区还是中国，选英文也必须推国际电子书渠道。
        let channels = BookMarketLinks.channels(for: "Charlotte's Web", region: .china, contentLanguage: .english)
        XCTAssertTrue(channels.contains { $0.name.contains("Kindle") })
        XCTAssertTrue(channels.contains { $0.name.contains("Gutenberg") })
        XCTAssertFalse(channels.contains { $0.name == "当当" }, "英文内容不再推纸书渠道")
    }

    func testChineseContentGetsChineseEbookChannels() {
        let channels = BookMarketLinks.channels(for: "小王子", region: .usa, contentLanguage: .chinese)
        XCTAssertTrue(channels.contains { $0.name == "微信读书" })
        XCTAssertTrue(channels.contains { $0.name.contains("Apple Books") })
    }

    func testRegionOnlyAffectsAppleStoreLocale() {
        let cn = BookMarketLinks.channels(for: "小王子", region: .china, contentLanguage: .chinese)
        let us = BookMarketLinks.channels(for: "小王子", region: .usa, contentLanguage: .chinese)
        XCTAssertTrue(cn.first { $0.name.contains("Apple") }!.url.absoluteString.contains("/cn/"))
        XCTAssertTrue(us.first { $0.name.contains("Apple") }!.url.absoluteString.contains("/us/"))
    }

    func testAcquisitionOptionsPutInAppReadingFirst() {
        let options = BookMarketLinks.acquisitionOptions(
            for: "Peter Pan",
            region: .usa,
            contentLanguage: .english
        )
        XCTAssertEqual(options.first?.kind, .directDownload)
        XCTAssertEqual(options.dropFirst().first?.kind, .importOwnedFile)
        XCTAssertTrue(options.first?.detail.contains("生成阅读计划") == true)
        XCTAssertTrue(options.contains { $0.title.contains("Project Gutenberg") })
    }

    func testEnglishAcquisitionOptionsOnlyShowOpenSourcesAfterClosedLoopEntrypoints() throws {
        let options = BookMarketLinks.acquisitionOptions(
            for: "Peter Pan",
            region: .usa,
            contentLanguage: .english
        )
        let titles = options.map(\.title)
        let gutenbergIndex = try XCTUnwrap(titles.firstIndex { $0.contains("Project Gutenberg") })
        let standardIndex = try XCTUnwrap(titles.firstIndex { $0.contains("Standard Ebooks") })
        let archiveIndex = try XCTUnwrap(titles.firstIndex { $0.contains("Internet Archive") })
        let directDownloadIndex = try XCTUnwrap(titles.firstIndex { $0 == "查找可下载版本" })
        let importIndex = try XCTUnwrap(titles.firstIndex { $0 == "我已有电子书文件" })
        XCTAssertLessThan(directDownloadIndex, gutenbergIndex)
        XCTAssertLessThan(importIndex, gutenbergIndex)
        XCTAssertLessThan(gutenbergIndex, standardIndex)
        XCTAssertLessThan(standardIndex, archiveIndex)
        XCTAssertFalse(titles.contains { $0.contains("Amazon Kindle") })
        XCTAssertFalse(titles.contains { $0.contains("Apple Books") })
        XCTAssertFalse(titles.contains { $0 == "微信读书" })
        XCTAssertTrue(options[gutenbergIndex].detail.contains("免费公版"))
    }

    func testBilingualChannelsKeepFreeSourcesBeforeCommercialAndChineseChannels() throws {
        let channels = BookMarketLinks.channels(
            for: "小王子",
            region: .usa,
            contentLanguage: .bilingual
        )
        let names = channels.map(\.name)
        let gutenbergIndex = try XCTUnwrap(names.firstIndex { $0.contains("Project Gutenberg") })
        let archiveIndex = try XCTUnwrap(names.firstIndex { $0.contains("Internet Archive") })
        let kindleIndex = try XCTUnwrap(names.firstIndex { $0.contains("Amazon Kindle") })
        let wereadIndex = try XCTUnwrap(names.firstIndex { $0 == "微信读书" })
        XCTAssertLessThan(gutenbergIndex, kindleIndex)
        XCTAssertLessThan(archiveIndex, kindleIndex)
        XCTAssertLessThan(kindleIndex, wereadIndex)
    }

    func testDrmHeavyChannelsAreMarkedExternalReadOnly() {
        let chinese = BookMarketLinks.channels(
            for: "小王子",
            region: .china,
            contentLanguage: .chinese
        )
        let weRead = chinese.first { $0.name == "微信读书" }
        XCTAssertEqual(weRead.map(BookMarketLinks.externalKind(for:)), .externalReadOnly)
        XCTAssertTrue(weRead.map(BookMarketLinks.externalDetail(for:))?.contains("不能自动装入") == true)

        let english = BookMarketLinks.channels(
            for: "Peter Pan",
            region: .usa,
            contentLanguage: .english
        )
        let kindle = english.first { $0.name == "Amazon Kindle" }
        XCTAssertEqual(kindle.map(BookMarketLinks.externalKind(for:)), .externalReadOnly)
    }

    func testChineseAcquisitionOptionsAvoidExternalOnlyStores() {
        let options = BookMarketLinks.acquisitionOptions(
            for: "小王子",
            region: .china,
            contentLanguage: .chinese
        )
        let titles = options.map(\.title)
        XCTAssertEqual(titles, ["查找可下载版本", "我已有电子书文件"])
        XCTAssertFalse(titles.contains("微信读书"))
        XCTAssertFalse(titles.contains("Apple Books"))
    }

    // MARK: - 书库与任务关联

    func testBookLibraryAndReadingSpecRoundTrip() throws {
        let store = LocalFamilyStore()
        let book = store.addBook(
            title: "夏洛的网",
            fileName: "book-x.pdf",
            format: "pdf",
            pageCount: 120,
            charCount: 60_000,
            sourceName: "Project Gutenberg",
            sourceURLString: "https://www.gutenberg.org/ebooks/1.txt.utf-8"
        )
        store.assignNewTask(
            title: "读《夏洛的网》第 1 次",
            instructions: "",
            category: .learning,
            rewardMinutes: 20,
            requiredProof: .text,
            reading: ReadingSpec(
                bookTitle: "夏洛的网",
                minMinutes: 60,
                chapterPlanText: "第 1-30 页",
                importedBookId: book.id,
                pageStart: 1,
                pageEnd: 30
            )
        )

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FamilyStoreSnapshot.self, from: encoder.encode(store.snapshot))
        XCTAssertEqual(decoded.books?.first?.title, "夏洛的网")
        XCTAssertEqual(decoded.books?.first?.sourceName, "Project Gutenberg")
        XCTAssertEqual(decoded.books?.first?.sourceURLString, "https://www.gutenberg.org/ebooks/1.txt.utf-8")
        XCTAssertEqual(decoded.assignments.last?.task.reading?.importedBookId, book.id)
        XCTAssertEqual(decoded.assignments.last?.task.reading?.pageEnd, 30)
        XCTAssertEqual(store.book(id: book.id)?.pageCount, 120)
    }

    func testReadingTaskWithoutBookIdFallsBackToMatchingImportedTitle() throws {
        let store = LocalFamilyStore()
        let book = store.addBook(title: "彼得潘", fileName: "book-peter.txt", format: "txt", pageCount: 1, charCount: 12_000)
        let assignment = try XCTUnwrap(store.assignNewTask(
            title: "读《彼得潘》第 1 次",
            instructions: "",
            category: .learning,
            rewardMinutes: 20,
            requiredProof: .text,
            reading: ReadingSpec(
                bookTitle: "彼得潘",
                minMinutes: 60,
                chapterPlanText: "第 1 段",
                pageStart: 0,
                pageEnd: 4_000
            )
        ))

        XCTAssertNil(assignment.task.reading?.importedBookId, "旧任务可能没有保存书库 ID")
        XCTAssertEqual(store.book(for: assignment.task.reading)?.id, book.id)
    }
}

private func makeMinimalEPUB() throws -> Data {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("minimal-\(UUID().uuidString).epub")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let archive = try Archive(url: tmp, accessMode: .create)
    try archive.addEntry(path: "mimetype", text: "application/epub+zip")
    try archive.addEntry(path: "META-INF/container.xml", text: """
    <?xml version="1.0"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
    </container>
    """)
    try archive.addEntry(path: "OEBPS/content.opf", text: """
    <package version="3.0" xmlns="http://www.idpf.org/2007/opf">
      <manifest>
        <item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
        <item id="c2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
      </manifest>
      <spine><itemref idref="c1"/><itemref idref="c2"/></spine>
    </package>
    """)
    try archive.addEntry(path: "OEBPS/chapter1.xhtml", text: "<html><head><title>第一章 出发</title></head><body><h1>第一章 出发</h1><p>孩子带着星星伙伴出发，学习如何观察。</p></body></html>")
    try archive.addEntry(path: "OEBPS/chapter2.xhtml", text: "<html><head><title>第二章 花园</title></head><body><h1>第二章 花园</h1><p>他们在花园里记录昆虫和植物。</p></body></html>")
    return try Data(contentsOf: tmp)
}

private func makeMinimalEPUBWithImage() throws -> Data {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("minimal-image-\(UUID().uuidString).epub")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let archive = try Archive(url: tmp, accessMode: .create)
    try archive.addEntry(path: "mimetype", text: "application/epub+zip")
    try archive.addEntry(path: "META-INF/container.xml", text: """
    <?xml version="1.0"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
    </container>
    """)
    try archive.addEntry(path: "OEBPS/content.opf", text: """
    <package version="3.0" xmlns="http://www.idpf.org/2007/opf">
      <manifest>
        <item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
        <item id="star" href="images/star.png" media-type="image/png"/>
      </manifest>
      <spine><itemref idref="c1"/></spine>
    </package>
    """)
    try archive.addEntry(path: "OEBPS/chapter1.xhtml", text: """
    <html><head><title>图画章节</title></head><body>
      <h1>图画章节</h1>
      <p>孩子先看图，再说看到了什么。</p>
      <img src="images/star.png" alt="一颗星星"/>
    </body></html>
    """)
    try archive.addEntry(path: "OEBPS/images/star.png", data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    return try Data(contentsOf: tmp)
}

private func makeEPUBWithLinkedImageHelperPage() throws -> Data {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("linked-image-\(UUID().uuidString).epub")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let archive = try Archive(url: tmp, accessMode: .create)
    try archive.addEntry(path: "mimetype", text: "application/epub+zip")
    try archive.addEntry(path: "META-INF/container.xml", text: """
    <?xml version="1.0"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
    </container>
    """)
    try archive.addEntry(path: "OEBPS/content.opf", text: """
    <package version="3.0" xmlns="http://www.idpf.org/2007/opf">
      <manifest>
        <item id="alphabet" href="alphabet.xhtml" media-type="application/xhtml+xml"/>
        <item id="linked-image" href="zebra-wrapper.xhtml" media-type="application/xhtml+xml"/>
        <item id="zebra" href="images/zebra.png" media-type="image/png"/>
      </manifest>
      <spine>
        <itemref idref="alphabet" linear="yes"/>
        <itemref idref="linked-image" linear="no"/>
      </spine>
    </package>
    """)
    try archive.addEntry(path: "OEBPS/alphabet.xhtml", text: """
    <html><head><title>字母正文</title></head><body>
      <h1>X Y Z</h1><p>孩子在正文里看完整的字母和图画。</p>
      <a href="zebra-wrapper.xhtml"><img src="images/zebra.png" alt="Zebra"/></a>
    </body></html>
    """)
    try archive.addEntry(path: "OEBPS/zebra-wrapper.xhtml", text: """
    <html><head><title>linked image</title></head><body>
      <img src="images/zebra.png" alt="Zebra"/><a href="alphabet.xhtml">back</a>
    </body></html>
    """)
    try archive.addEntry(path: "OEBPS/images/zebra.png", data: Data([0x89, 0x50, 0x4E, 0x47]))
    return try Data(contentsOf: tmp)
}

private func makeEPUBWithMislabelledLinkedImageHelperPage() throws -> Data {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mislabelled-linked-image-\(UUID().uuidString).epub")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let archive = try Archive(url: tmp, accessMode: .create)
    try archive.addEntry(path: "mimetype", text: "application/epub+zip")
    try archive.addEntry(path: "META-INF/container.xml", text: """
    <?xml version="1.0"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
    </container>
    """)
    try archive.addEntry(path: "OEBPS/content.opf", text: """
    <package version="3.0" xmlns="http://www.idpf.org/2007/opf">
      <manifest>
        <item id="content" href="book-content.xhtml" media-type="application/xhtml+xml"/>
        <item id="linked-image" href="page.jpg.id-123.wrap-0.html.html" media-type="application/xhtml+xml"/>
        <item id="page" href="images/page.jpg" media-type="image/jpeg"/>
      </manifest>
      <spine>
        <itemref idref="content" linear="yes"/>
        <itemref idref="linked-image" linear="yes"/>
      </spine>
    </package>
    """)
    try archive.addEntry(path: "OEBPS/book-content.xhtml", text: """
    <html><head><title>数字童谣正文</title></head><body>
      <h1>One, Two, Buckle My Shoe</h1>
      <p>One, two, buckle my shoe. Three, four, open the door.</p>
      <a href="page.jpg.id-123.wrap-0.html.html"><img src="images/page.jpg" alt="Picture page"/></a>
    </body></html>
    """)
    try archive.addEntry(path: "OEBPS/page.jpg.id-123.wrap-0.html.html", text: """
    <html><head><title>"linked image"</title></head><body>
      <img src="images/page.jpg" alt="Picture page"/>
      <br/><a href="book-content.xhtml#page" title="back">back</a>
    </body></html>
    """)
    try archive.addEntry(path: "OEBPS/images/page.jpg", data: Data([0xFF, 0xD8, 0xFF, 0xD9]))
    return try Data(contentsOf: tmp)
}

private extension Archive {
    func addEntry(path: String, text: String) throws {
        let data = Data(text.utf8)
        try addEntry(path: path, data: data)
    }

    func addEntry(path: String, data: Data) throws {
        try addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(data.count),
            provider: { position, size in
                let start = Int(position)
                let end = Swift.min(start + size, data.count)
                return data[start..<end]
            }
        )
    }
}
