import XCTest
@testable import OctoTeacher

/// v5L 回归：AI 找书解析、Gutenberg 地址构造、下载校验、数据入库。
final class AutoBookDownloadTests: XCTestCase {

    // MARK: - AI 找书解析

    func testSourceFinderParse() {
        let raw = """
        {"isPublicDomain":true,"gutenbergId":16,"gutenbergIdConfidence":"high",
         "otherSites":[{"name":"Standard Ebooks","searchUrl":"https://standardebooks.org/ebooks?query=peter+pan"},
                       {"name":"坏站","searchUrl":"http://insecure.example.com"}]}
        """
        let hint = AIBookSourceFinder.parse(raw)
        XCTAssertEqual(hint?.gutenbergId, 16)
        XCTAssertEqual(hint?.browseSites.count, 1, "非 https 站点必须丢弃")
        XCTAssertEqual(hint?.browseSites.first?.name, "Standard Ebooks")
    }

    func testSourceFinderHandlesUnknownBook() {
        let hint = AIBookSourceFinder.parse(#"{"isPublicDomain":false,"gutenbergId":null,"otherSites":[]}"#)
        XCTAssertNil(hint?.gutenbergId)
        XCTAssertNil(AIBookSourceFinder.parse("不是JSON"))
    }

    func testGutenbergCandidateURLs() {
        let candidates = AIBookSourceFinder.gutenbergCandidates(id: 16)
        XCTAssertEqual(candidates.count, 7)
        XCTAssertEqual(candidates[0].absoluteString, "https://www.gutenberg.org/ebooks/16.epub3.images")
        XCTAssertTrue(candidates.contains { $0.absoluteString == "https://www.gutenberg.org/ebooks/16.txt.utf-8" })
        XCTAssertTrue(candidates.allSatisfy { $0.scheme == "https" })
    }

    func testGutendexCandidatesUseRealTextDownloadURLs() throws {
        let json = """
        {
          "results": [
            {
              "id": 16,
              "title": "Peter Pan",
              "authors": [{"name": "J. M. Barrie"}],
              "formats": {
                "text/plain; charset=utf-8": "https://www.gutenberg.org/ebooks/16.txt.utf-8",
                "application/epub+zip": "https://www.gutenberg.org/ebooks/16.epub3.images"
              }
            },
            {
              "id": 9999,
              "title": "Bad Zip",
              "authors": [],
              "formats": {
                "text/plain": "https://www.gutenberg.org/files/9999/9999.zip"
              }
            }
          ]
        }
        """
        let candidates = AIBookSourceFinder.parseGutendexCandidates(Data(json.utf8), requestedTitle: "Peter Pan")
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.sourceName, "Project Gutenberg")
        XCTAssertEqual(candidates.first?.sourceTitle, "Peter Pan")
        XCTAssertEqual(candidates.first?.format, "EPUB")
        XCTAssertTrue(candidates.first?.downloadURL.absoluteString.contains("16.epub3.images") == true)
        XCTAssertTrue(candidates.first?.licenseNote.contains("可导入") == true)
    }

    func testGutendexCandidatesRejectReadmeFiles() throws {
        let json = """
        {
          "results": [
            {
              "id": 22984,
              "title": "Peter Pan",
              "authors": [{"name": "J. M. Barrie"}],
              "formats": {
                "text/plain; charset=utf-8": "https://www.gutenberg.org/files/22984/22984-readme.txt"
              }
            }
          ]
        }
        """
        XCTAssertTrue(AIBookSourceFinder.parseGutendexCandidates(Data(json.utf8), requestedTitle: "Peter Pan").isEmpty)
    }

    func testKnownGutenbergCandidateIsPresentedAsDownloadable() throws {
        let candidate = try XCTUnwrap(AIBookSourceFinder.knownGutenbergCandidate(id: 16, bookTitle: "Peter Pan", author: "J. M. Barrie"))
        XCTAssertEqual(candidate.sourceName, "Project Gutenberg")
        XCTAssertEqual(candidate.format, "EPUB")
        XCTAssertTrue(candidate.detail.contains("16"))
    }

    func testFallbackBrowseSitesPreferReachableFreeSources() {
        let sites = AIBookSourceFinder.fallbackBrowseSites(bookTitle: "Peter Pan")
        XCTAssertEqual(sites.map(\.name), [
            "Project Gutenberg",
            "Standard Ebooks",
            "Internet Archive",
            "Open Library",
            "Wikisource"
        ])
        XCTAssertTrue(sites.allSatisfy { $0.url.scheme == "https" })
        XCTAssertFalse(sites.contains { $0.name == "Amazon Kindle" })
        XCTAssertFalse(sites.contains { $0.name == "ManyBooks" })
    }

    func testEarlyFoundationSourceQueriesAddPreReaderKeywords() {
        let alphabetQueries = AIBookSourceFinder.sourceSearchQueries(
            bookTitle: "The ABC Bunny",
            author: "Wanda Gag",
            category: .alphabet
        )
        XCTAssertEqual(alphabetQueries.first, "The ABC Bunny Wanda Gag")
        XCTAssertTrue(alphabetQueries.contains { $0.localizedCaseInsensitiveContains("alphabet book") })
        XCTAssertTrue(alphabetQueries.contains { $0.localizedCaseInsensitiveContains("phonics primer") })
        XCTAssertLessThanOrEqual(alphabetQueries.count, 6)

        let numberQueries = AIBookSourceFinder.sourceSearchQueries(
            bookTitle: "Number Stories",
            author: "",
            category: .numbers
        )
        XCTAssertTrue(numberQueries.contains { $0.localizedCaseInsensitiveContains("counting") })
        XCTAssertTrue(numberQueries.contains { $0.localizedCaseInsensitiveContains("arithmetic primer") })
    }

    func testGenericSourceQueriesStayNarrow() {
        let queries = AIBookSourceFinder.sourceSearchQueries(
            bookTitle: "Peter Pan",
            author: "J. M. Barrie",
            category: .childrenLiterature
        )
        XCTAssertEqual(queries, ["Peter Pan J. M. Barrie"])
    }

    func testEarlyFoundationSourcePromptAvoidsCommercialAndDenseBooks() {
        let prompt = AIBookSourceFinder.systemPrompt(category: .alphabet)
        XCTAssertTrue(prompt.contains("alphabet"))
        XCTAssertTrue(prompt.contains("phonics"))
        XCTAssertTrue(prompt.contains("避免长篇章节书"))
        XCTAssertTrue(prompt.contains("不要优先给商业书店"))
    }

    func testLocalBookCatalogParsesCloudReadyManifestShape() throws {
        let json = """
        {
          "source": "Project Gutenberg public-domain/open distribution EPUBs",
          "version": 3,
          "revision": "catalog-2026-07-09",
          "categories": [
            {
              "category": "字母启蒙",
              "count": 1,
              "books": [
                {
                  "id": 10742,
                  "title": "The Picture Alphabet",
                  "category": "字母启蒙",
                  "file": "01_字母启蒙/01_pg10742_The_Picture_Alphabet.epub",
                  "url": "https://www.gutenberg.org/ebooks/10742"
                }
              ]
            }
          ]
        }
        """
        let catalog = try LocalBookCatalogStore.parse(Data(json.utf8))
        let section = try XCTUnwrap(catalog.categories.first)
        let item = try XCTUnwrap(section.books.first)

        XCTAssertEqual(catalog.version, 3)
        XCTAssertEqual(catalog.revision, "catalog-2026-07-09")
        XCTAssertEqual(section.category, "字母启蒙")
        XCTAssertEqual(item.categoryHint, .alphabet)
        XCTAssertEqual(item.downloadCandidate?.sourceName, "Project Gutenberg")
        XCTAssertEqual(item.downloadCandidate?.format, "EPUB")
        XCTAssertTrue(item.downloadCandidate?.downloadURL.absoluteString.contains("10742.epub") == true)
    }

    func testLocalBookCatalogFiltersBooksByOctoTeacherCategory() throws {
        let catalog = LocalBookCatalog(
            source: "OctoTeacher cloud seed",
            categories: [
                LocalBookCatalogSection(
                    category: BookCategory.alphabet.rawValue,
                    count: nil,
                    books: [
                        LocalBookCatalogItem(
                            id: 10742,
                            title: "The Picture Alphabet",
                            file: "01_字母启蒙/01_pg10742_The_Picture_Alphabet.epub",
                            url: "https://www.gutenberg.org/ebooks/10742"
                        )
                    ]
                ),
                LocalBookCatalogSection(
                    category: BookCategory.childrenLiterature.rawValue,
                    count: nil,
                    books: [
                        LocalBookCatalogItem(
                            id: 16,
                            title: "Peter Pan",
                            file: "10_儿童文学经典/01_pg16_Peter_Pan.epub",
                            url: "https://www.gutenberg.org/ebooks/16"
                        )
                    ]
                )
            ]
        )

        XCTAssertEqual(catalog.books(for: .alphabet).map(\.title), ["The Picture Alphabet"])
        XCTAssertEqual(catalog.books(for: .childrenLiterature).map(\.title), ["Peter Pan"])
        XCTAssertTrue(catalog.books(for: .numbers).isEmpty)
        XCTAssertEqual(catalog.books(for: .alphabet).first?.bookCandidate.title, "The Picture Alphabet")
    }

    func testBookCatalogRuntimeCacheOverridesBundledBootstrap() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-runtime-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let bootstrap = LocalBookCatalog(
            source: "bundled bootstrap",
            version: 1,
            revision: "bundle",
            categories: [
                LocalBookCatalogSection(
                    category: BookCategory.alphabet.rawValue,
                    count: nil,
                    books: [
                        LocalBookCatalogItem(
                            id: 10742,
                            title: "The Picture Alphabet",
                            file: "01_字母启蒙/01_pg10742_The_Picture_Alphabet.epub",
                            url: "https://www.gutenberg.org/ebooks/10742"
                        )
                    ]
                )
            ]
        )
        let remoteCatalog = LocalBookCatalog(
            source: "OctoTeacher cloud console",
            version: 9,
            revision: "remote-9",
            categories: [
                LocalBookCatalogSection(
                    category: BookCategory.childrenLiterature.rawValue,
                    count: nil,
                    books: [
                        LocalBookCatalogItem(
                            id: 16,
                            title: "Peter Pan",
                            category: BookCategory.childrenLiterature.rawValue,
                            file: nil,
                            url: "https://www.gutenberg.org/ebooks/16"
                        )
                    ]
                )
            ]
        )

        let firstLoad = LocalBookCatalogStore.runtimeCatalog(directory: directory, bootstrapCatalog: bootstrap)
        XCTAssertEqual(firstLoad.source, "bundled bootstrap")
        XCTAssertTrue(FileManager.default.fileExists(atPath: LocalBookCatalogStore.runtimeCatalogURL(directory: directory).path))

        try LocalBookCatalogStore.replaceRuntimeCatalog(remoteCatalog, directory: directory)
        let secondLoad = LocalBookCatalogStore.runtimeCatalog(directory: directory, bootstrapCatalog: bootstrap)
        XCTAssertEqual(secondLoad.source, "OctoTeacher cloud console")
        XCTAssertEqual(secondLoad.version, 9)
        XCTAssertEqual(secondLoad.books(for: .childrenLiterature).map(\.title), ["Peter Pan"])
        XCTAssertTrue(secondLoad.books(for: .alphabet).isEmpty)
    }

    func testBookCatalogRuntimeCacheFallsBackWhenCacheIsCorrupt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-corrupt-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: LocalBookCatalogStore.runtimeCatalogURL(directory: directory))

        let bootstrap = LocalBookCatalog(
            source: "healthy bootstrap",
            categories: [
                LocalBookCatalogSection(
                    category: BookCategory.numbers.rawValue,
                    count: nil,
                    books: [
                        LocalBookCatalogItem(
                            id: 123,
                            title: "Number Primer",
                            category: BookCategory.numbers.rawValue,
                            file: nil,
                            url: "https://www.gutenberg.org/ebooks/123"
                        )
                    ]
                )
            ]
        )

        let catalog = LocalBookCatalogStore.runtimeCatalog(directory: directory, bootstrapCatalog: bootstrap)
        XCTAssertEqual(catalog.source, "healthy bootstrap")
        XCTAssertEqual(catalog.books(for: .numbers).map(\.title), ["Number Primer"])
    }

    func testShortEarlyLearningTitlesDoNotOvermatch() {
        XCTAssertTrue(AIBookSourceFinder.titleLooksRelevant("ABC", requestedTitle: "ABC"))
        XCTAssertFalse(AIBookSourceFinder.titleLooksRelevant("A Big Collection of Stories", requestedTitle: "ABC"))
        XCTAssertTrue(AIBookSourceFinder.titleLooksRelevant("A Apple Pie", requestedTitle: "Apple Pie"))
    }

    // MARK: - 下载校验（防 AI 幻觉装坏文件）

    func testValidateAcceptsRealContent() {
        let pdf = Data("%PDF-1.4".utf8) + Data(repeating: 0x20, count: 20_000)
        XCTAssertEqual(EbookDownloader.validate(data: pdf, urlPath: "/x/pg16.pdf")?.ext, "pdf")

        let txt = Data(String(repeating: "从前有一只章鱼老师。", count: 500).utf8)
        XCTAssertEqual(EbookDownloader.validate(data: txt, urlPath: "/ebooks/16.txt.utf-8")?.ext, "txt")

        let epub = Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 0x20, count: 3_000)
        XCTAssertEqual(EbookDownloader.validate(data: epub, urlPath: "/ebooks/16.epub3.images")?.ext, "epub")
    }

    func testValidateRejectsGarbage() {
        XCTAssertNil(EbookDownloader.validate(data: Data("%PDF".utf8), urlPath: "/x.pdf"), "太小的 PDF 拒收")
        XCTAssertNil(EbookDownloader.validate(data: Data("短".utf8), urlPath: "/x.txt"), "太短的 TXT 拒收")
        let html = Data(("<html><body>404 Not Found" + String(repeating: "x", count: 3000)).utf8)
        XCTAssertNil(EbookDownloader.validate(data: html, urlPath: "/x.txt"), "HTML 错误页拒收")
        XCTAssertNil(EbookDownloader.validate(data: Data(repeating: 0xFF, count: 9000), urlPath: "/x.bin"), "未知格式拒收")
    }

    // MARK: - 数据入库

    func testImportBookFromDownloadedData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dl-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BookFileStore(directory: directory)

        let text = String(repeating: "章鱼老师的故事。", count: 300)
        let fileName = try XCTUnwrap(store.importBook(data: Data(text.utf8), ext: "txt"))
        let stats = try XCTUnwrap(store.analyze(fileName: fileName))
        XCTAssertEqual(stats.charCount, text.count)
        XCTAssertNil(store.importBook(data: Data("x".utf8), ext: "mobi"), "仅 epub/pdf/txt/html")
    }
}
