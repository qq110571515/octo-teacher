import Foundation

/// AI 找可直接下载的电子书版本（免费公版/无 DRM）。
///
/// 防幻觉设计：AI 只提供站点与书目编号（如 Project Gutenberg 的 ID），
/// 下载地址由 App 按官方稳定 URL 模式构造；下载回来校验文件头/长度，
/// AI 记错编号只会静默跳过，绝不会把坏文件装进书库。
enum AIBookSourceFinder {

    struct DownloadCandidate: Identifiable, Equatable {
        var id: String
        var sourceName: String
        var sourceTitle: String
        var author: String
        var format: String
        var detail: String
        var licenseNote: String
        var downloadURL: URL
    }

    struct SourceHint: Equatable {
        var gutenbergId: Int?
        /// 备选浏览站点（找不到直接下载时给家长手动找）。
        var browseSites: [(name: String, url: URL)]

        static func == (lhs: SourceHint, rhs: SourceHint) -> Bool {
            lhs.gutenbergId == rhs.gutenbergId
        }
    }

    static func systemPrompt(category: BookCategory? = nil) -> String {
        let categoryInstruction: String
        if let category, category.isPreReaderFoundation {
            categoryInstruction = """
            当前类别是「\(category.rawValue)」。这是幼儿/不识字孩子的启蒙资源，\
            检索时要优先 ABC、alphabet、phonics、counting、numbers、primer、picture book、\
            nursery rhymes、read aloud 这类公版/免费资源；避免长篇章节书、商业购买页和青少年读物。
            """
        } else {
            categoryInstruction = ""
        }
        return """
        你是电子书检索助手。判断这本书是否是公版书（版权已过期），\
        以及 Project Gutenberg 上的书目编号。只输出 JSON：\
        {"isPublicDomain":true,"gutenbergId":16,"gutenbergIdConfidence":"high 或 low",\
        "otherSites":[{"name":"Standard Ebooks","searchUrl":"https://standardebooks.org/ebooks?query=..."}]}。\
        gutenbergId 只在你确实记得时给出，不确定就填 null；\
        otherSites 给 2-3 个真实存在且可直接浏览的免费/无 DRM 电子书站搜索地址\
        （优先 Standard Ebooks、Internet Archive、Open Library、Wikisource；不要优先给商业书店）。\
        \(categoryInstruction)\
        不要输出 JSON 以外的任何内容。
        """
    }

    static func userPrompt(bookTitle: String, author: String, category: BookCategory? = nil) -> String {
        let categoryLine = category.map { "\n类别：\($0.rawValue)\n找书重点：\($0.preReaderRecommendationBrief)" } ?? ""
        return "书名：《\(bookTitle)》\(author.isEmpty ? "" : "；作者：\(author)")\(categoryLine)"
    }

    static func parse(_ raw: String) -> SourceHint? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        struct Payload: Decodable {
            struct Site: Decodable {
                let name: String
                let searchUrl: String
            }
            let isPublicDomain: Bool?
            let gutenbergId: Int?
            let otherSites: [Site]?
        }
        guard let data = text.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        let sites: [(String, URL)] = (payload.otherSites ?? []).compactMap { site in
            guard let url = URL(string: site.searchUrl), url.scheme == "https" else { return nil }
            return (site.name, url)
        }
        return SourceHint(gutenbergId: payload.gutenbergId, browseSites: sites)
    }

    /// Gutenberg 官方稳定下载地址（按可靠性排序，逐个尝试）。
    static func gutenbergCandidates(id: Int) -> [URL] {
        [
            "https://www.gutenberg.org/ebooks/\(id).epub3.images",
            "https://www.gutenberg.org/ebooks/\(id).epub.images",
            "https://www.gutenberg.org/cache/epub/\(id)/pg\(id).epub",
            "https://www.gutenberg.org/ebooks/\(id).txt.utf-8",
            "https://www.gutenberg.org/cache/epub/\(id)/pg\(id).txt",
            "https://www.gutenberg.org/files/\(id)/\(id)-0.txt",
            "https://www.gutenberg.org/files/\(id)/\(id).txt"
        ].compactMap(URL.init(string:))
    }

    static func gutenbergSearchURL(bookTitle: String, author: String) -> URL? {
        var components = URLComponents(string: "https://gutendex.com/books/")
        let query = [bookTitle, author].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " ")
        components?.queryItems = [
            URLQueryItem(name: "search", value: query)
        ]
        return components?.url
    }

    static func sourceSearchQueries(bookTitle: String, author: String, category: BookCategory? = nil) -> [String] {
        let cleanTitle = bookTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let exact = [cleanTitle, cleanAuthor].filter { !$0.isEmpty }.joined(separator: " ")
        var queries = exact.isEmpty ? [] : [exact]

        if let category, category.isPreReaderFoundation {
            let anchored = [cleanTitle, cleanAuthor].filter { !$0.isEmpty }.joined(separator: " ")
            for keyword in category.sourceDiscoveryKeywords {
                let query = [anchored, keyword].filter { !$0.isEmpty }.joined(separator: " ")
                if !query.isEmpty { queries.append(query) }
            }
            let generic = [category.sourceDiscoveryKeywords.prefix(3).joined(separator: " "), "children public domain"]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !generic.isEmpty { queries.append(generic) }
        }

        var seen = Set<String>()
        return queries.filter { query in
            let key = query.lowercased()
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }.prefix(6).map { $0 }
    }

    static func gutenbergSearchURLs(bookTitle: String, author: String, category: BookCategory? = nil) -> [URL] {
        sourceSearchQueries(bookTitle: bookTitle, author: author, category: category).compactMap { query in
            var components = URLComponents(string: "https://gutendex.com/books/")
            components?.queryItems = [URLQueryItem(name: "search", value: query)]
            return components?.url
        }
    }

    static func fallbackBrowseSites(bookTitle: String, category: BookCategory? = nil) -> [(name: String, url: URL)] {
        let query = sourceSearchQueries(bookTitle: bookTitle, author: "", category: category).first ?? bookTitle
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return [
            ("Project Gutenberg", URL(string: "https://www.gutenberg.org/ebooks/search/?query=\(encoded)")!),
            ("Standard Ebooks", URL(string: "https://standardebooks.org/ebooks?query=\(encoded)")!),
            ("Internet Archive", URL(string: "https://archive.org/search?query=\(encoded)")!),
            ("Open Library", URL(string: "https://openlibrary.org/search?q=\(encoded)")!),
            ("Wikisource", URL(string: "https://en.wikisource.org/w/index.php?search=\(encoded)")!)
        ]
    }

    static func knownGutenbergCandidate(id: Int, bookTitle: String, author: String) -> DownloadCandidate? {
        guard let url = gutenbergCandidates(id: id).first else { return nil }
        return DownloadCandidate(
            id: "gutenberg-\(id)",
            sourceName: "Project Gutenberg",
            sourceTitle: bookTitle,
            author: author,
            format: "EPUB",
            detail: "AI 记得的 Gutenberg 书目编号 \(id)，App 会优先下载 EPUB，失败时再尝试 TXT。",
            licenseNote: "免费公版/无 DRM；可导入 章鱼老师。",
            downloadURL: url
        )
    }

    static func resolveDownloadCandidates(
        bookTitle: String,
        author: String,
        hint: SourceHint?,
        category: BookCategory? = nil,
        session: URLSession = .shared
    ) async -> [DownloadCandidate] {
        var candidates: [DownloadCandidate] = []
        if let id = hint?.gutenbergId,
           let candidate = knownGutenbergCandidate(id: id, bookTitle: bookTitle, author: author) {
            candidates.append(candidate)
        }
        for url in gutenbergSearchURLs(bookTitle: bookTitle, author: author, category: category) {
            guard let (data, response) = try? await data(from: url, session: session),
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else { continue }
            let parsed = parseGutendexCandidates(data, requestedTitle: bookTitle)
            candidates.append(contentsOf: parsed)
            if !parsed.isEmpty, !(category?.isPreReaderFoundation ?? false) {
                break
            }
        }

        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = candidate.downloadURL.absoluteString
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }.prefix(5).map { $0 }
    }

    static func parseGutendexCandidates(_ data: Data, requestedTitle: String) -> [DownloadCandidate] {
        struct Response: Decodable {
            struct Person: Decodable { let name: String }
            struct Book: Decodable {
                let id: Int
                let title: String
                let authors: [Person]
                let formats: [String: String]
            }
            let results: [Book]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return response.results.compactMap { book in
            let epubFormat = book.formats
                .filter { key, value in
                    (key.lowercased().contains("epub") || value.lowercased().contains(".epub"))
                        && !value.lowercased().contains(".zip")
                }
                .sorted { lhs, rhs in
                    lhs.value.lowercased().contains("images") && !rhs.value.lowercased().contains("images")
                }
                .first
            let textFormat = book.formats
                .filter { key, value in
                    key.lowercased().contains("text/plain")
                        && value.lowercased().contains(".txt")
                        && !value.lowercased().contains(".zip")
                        && !value.lowercased().contains("readme")
                }
                .sorted { lhs, rhs in
                    lhs.key.contains("utf-8") && !rhs.key.contains("utf-8")
                }
                .first
            let picked = epubFormat ?? textFormat
            guard let value = picked?.value,
                  let url = URL(string: value),
                  url.scheme == "https" else { return nil }
            let author = book.authors.map(\.name).joined(separator: ", ")
            let matchNote = titleLooksRelevant(book.title, requestedTitle: requestedTitle) ? "书名匹配度高" : "请核对书名后再下载"
            let format = epubFormat?.value == value ? "EPUB" : "TXT"
            return DownloadCandidate(
                id: "gutendex-\(book.id)",
                sourceName: "Project Gutenberg",
                sourceTitle: book.title,
                author: author,
                format: format,
                detail: "\(matchNote)；来自 Gutendex/Gutenberg 目录，可直接下载\(format == "EPUB" ? "EPUB 版" : "文本版")。",
                licenseNote: "免费公版/无 DRM；可导入 章鱼老师。",
                downloadURL: url
            )
        }
    }

    static func titleLooksRelevant(_ sourceTitle: String, requestedTitle: String) -> Bool {
        let source = normalizedTitle(sourceTitle)
        let requested = normalizedTitle(requestedTitle)
        guard !source.isEmpty, !requested.isEmpty else { return false }
        if source.count < 4 || requested.count < 4 {
            return source == requested
        }
        return source == requested || source.contains(requested) || requested.contains(source)
    }

    private static func normalizedTitle(_ title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9\u{4e00}-\u{9fff}]"#, with: "", options: .regularExpression)
    }

    private static func data(from url: URL, session: URLSession) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue("OctoTeacher/0.12 source-check", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12
        return try await session.data(for: request)
    }
}

/// 电子书下载器：拉取候选地址并校验内容，通过才算成功。
struct EbookDownloader: Sendable {
    var session: URLSession = .shared

    /// 依次尝试候选地址，返回第一个通过校验的 (数据, 扩展名)。
    func download(candidates: [URL]) async -> (data: Data, ext: String)? {
        for url in candidates {
            var request = URLRequest(url: url)
            request.setValue("OctoTeacher/0.12 ebook-download", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 20
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
            if let validated = Self.validate(data: data, urlPath: url.path) {
                return validated
            }
        }
        return nil
    }

    /// 内容校验（纯函数）：PDF/EPUB 看魔数，TXT/HTML 要能按 UTF-8 解码且有足够长度。
    static func validate(data: Data, urlPath: String) -> (data: Data, ext: String)? {
        if data.prefix(4) == Data("%PDF".utf8) {
            return data.count > 10_000 ? (data, "pdf") : nil
        }
        if data.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]),
           urlPath.lowercased().contains(".epub") {
            return data.count > 2_000 ? (data, "epub") : nil
        }
        if urlPath.lowercased().contains(".html") || urlPath.lowercased().contains(".htm"),
           let text = String(data: data, encoding: .utf8),
           text.count > 2_000,
           text.lowercased().contains("<html") {
            return (data, "html")
        }
        if urlPath.lowercased().contains(".txt"),
           let text = String(data: data, encoding: .utf8),
           text.count > 2_000,
           !text.lowercased().contains("<html") {
            return (data, "txt")
        }
        return nil
    }
}
