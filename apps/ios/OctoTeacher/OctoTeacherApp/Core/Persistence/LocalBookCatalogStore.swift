import Foundation

/// 章鱼老师云端图书馆目录。
/// 这里保存的是书目元数据，不打包真实电子书文件；运行态目录保存在 Application Support，
/// App 内置 JSON 只作为首次启动/离线兜底的引导清单，未来后端控制台可发布同 schema 的云端目录。
struct LocalBookCatalog: Codable, Equatable {
    var source: String
    var version: Int?
    var revision: String?
    var categories: [LocalBookCatalogSection]

    func section(for category: BookCategory) -> LocalBookCatalogSection? {
        categories.first { $0.bookCategory == category }
    }

    func books(for category: BookCategory) -> [LocalBookCatalogItem] {
        section(for: category)?.books ?? []
    }
}

struct LocalBookCatalogSection: Identifiable, Codable, Equatable {
    var id: String { category }
    var category: String
    var count: Int?
    var books: [LocalBookCatalogItem]

    var displayCount: Int { count ?? books.count }

    var bookCategory: BookCategory? {
        BookCategory(rawValue: category)
    }
}

struct LocalBookCatalogItem: Identifiable, Codable, Equatable {
    var id: Int
    var title: String
    var category: String?
    /// Legacy bootstrap path hint. Runtime/remote catalogs should rely on section/category metadata instead.
    var file: String?
    var url: String

    var categoryHint: BookCategory? {
        BookCategory(rawValue: category ?? fileCategoryName ?? "")
    }

    var fileCategoryName: String? {
        file?
            .split(separator: "/", maxSplits: 1)
            .first
            .map(String.init)?
            .replacingOccurrences(of: #"^\d+_"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "_", with: "/")
    }

    var sourceURL: URL? { URL(string: url) }

    var downloadURL: URL? {
        AIBookSourceFinder.gutenbergCandidates(id: id).first
    }

    var downloadCandidate: AIBookSourceFinder.DownloadCandidate? {
        guard let downloadURL else { return nil }
        return AIBookSourceFinder.DownloadCandidate(
            id: "catalog-gutenberg-\(id)",
            sourceName: "Project Gutenberg",
            sourceTitle: title,
            author: "",
            format: "EPUB",
            detail: "来自 章鱼老师 可运营书库目录；优先下载含插图 EPUB。",
            licenseNote: "免费公版/无 DRM；可导入 章鱼老师。",
            downloadURL: downloadURL
        )
    }

    var bookCandidate: BookCandidate {
        BookCandidate(
            title: title,
            author: "Project Gutenberg",
            blurb: "来自章鱼老师云端图书馆的公版/无 DRM 书目。目录保存在本机运行态缓存，未来可由云端后台实时更新。"
        )
    }
}

protocol BookCatalogRemoteFetching {
    func fetchCatalog() async throws -> LocalBookCatalog
}

struct RemoteBookCatalogEndpoint: Equatable {
    var url: URL
    var revision: String?
}

enum BookCatalogStoreError: Error {
    case remoteEndpointNotConfigured
}

struct RemoteBookCatalogService: BookCatalogRemoteFetching {
    var endpoint: RemoteBookCatalogEndpoint?

    func fetchCatalog() async throws -> LocalBookCatalog {
        guard let endpoint else { throw BookCatalogStoreError.remoteEndpointNotConfigured }
        var request = URLRequest(url: endpoint.url)
        if let revision = endpoint.revision {
            request.setValue(revision, forHTTPHeaderField: "If-None-Match")
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        return try LocalBookCatalogStore.parse(data)
    }
}

enum LocalBookCatalogStore {
    private static let runtimeDirectoryName = "OctoTeacher/BookCatalog"
    private static let runtimeFileName = "catalog.json"

    static func runtimeCatalog(
        directory: URL? = nil,
        bootstrapCatalog: LocalBookCatalog? = nil,
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> LocalBookCatalog {
        let bootstrap = bootstrapCatalog ?? bundledBootstrapCatalog(bundle: bundle) ?? fallbackCatalog
        let url = runtimeCatalogURL(directory: directory, fileManager: fileManager)
        if let data = try? Data(contentsOf: url),
           let catalog = try? parse(data) {
            return catalog
        }
        try? replaceRuntimeCatalog(bootstrap, directory: directory, fileManager: fileManager)
        return bootstrap
    }

    static func replaceRuntimeCatalog(
        _ catalog: LocalBookCatalog,
        directory: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let url = runtimeCatalogURL(directory: directory, fileManager: fileManager)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var resourceURL = url.deletingLastPathComponent()
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? resourceURL.setResourceValues(values)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(catalog).write(to: url, options: [.atomic])
    }

    static func refreshRuntimeCatalog(
        using remote: BookCatalogRemoteFetching,
        directory: URL? = nil,
        fileManager: FileManager = .default
    ) async throws -> LocalBookCatalog {
        let catalog = try await remote.fetchCatalog()
        try replaceRuntimeCatalog(catalog, directory: directory, fileManager: fileManager)
        return catalog
    }

    static func runtimeCatalogURL(
        directory: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        let root: URL
        if let directory {
            root = directory
        } else if let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            root = applicationSupport.appendingPathComponent(runtimeDirectoryName, isDirectory: true)
        } else {
            root = fileManager.temporaryDirectory.appendingPathComponent(runtimeDirectoryName, isDirectory: true)
        }
        return root.appendingPathComponent(runtimeFileName)
    }

    static func bundledBootstrapCatalog(bundle: Bundle = .main) -> LocalBookCatalog? {
        guard let url = bundle.url(forResource: "LocalBookCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(LocalBookCatalog.self, from: data) else {
            return nil
        }
        return catalog
    }

    static func parse(_ data: Data) throws -> LocalBookCatalog {
        try JSONDecoder().decode(LocalBookCatalog.self, from: data)
    }

    static var fallbackCatalog: LocalBookCatalog {
        LocalBookCatalog(
            source: "Octo Teacher bundled bootstrap catalog",
            categories: [
                LocalBookCatalogSection(
                    category: "字母启蒙",
                    count: 2,
                    books: [
                        LocalBookCatalogItem(
                            id: 10742,
                            title: "The Picture Alphabet",
                            file: "01_字母启蒙/01_pg10742_The_Picture_Alphabet.epub",
                            url: "https://www.gutenberg.org/ebooks/10742"
                        ),
                        LocalBookCatalogItem(
                            id: 15809,
                            title: "A Apple Pie",
                            file: "01_字母启蒙/02_pg15809_A_Apple_Pie.epub",
                            url: "https://www.gutenberg.org/ebooks/15809"
                        )
                    ]
                )
            ]
        )
    }
}
