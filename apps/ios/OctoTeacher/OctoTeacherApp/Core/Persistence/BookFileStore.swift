import Foundation
import PDFKit
import ZIPFoundation

/// 电子书文件库：导入的 PDF/TXT/HTML/EPUB 只存本机沙盒 Documents/books/，绝不上传。
final class BookFileStore: Sendable {
    static let shared = BookFileStore()
    static let readableExtensions: Set<String> = ["pdf", "txt", "html", "htm", "epub"]
    private let directory: URL

    struct BookAnalysis: Equatable {
        var pageCount: Int
        var charCount: Int
        var wordCount: Int
        var chapters: [BookChapter]

        var isLikelyPictureBook: Bool {
            if !chapters.isEmpty {
                return wordCount <= max(1_000, chapters.count * 350)
            }
            return pageCount > 1 && wordCount <= max(500, pageCount * 150)
        }
    }

    struct EPUBRenderChapter: Identifiable, Equatable {
        let id = UUID()
        var order: Int
        var title: String
        var fileURL: URL
        var startCharacter: Int
        var endCharacter: Int
    }

    struct EPUBRenderPackage: Equatable {
        var rootURL: URL
        var chapters: [EPUBRenderChapter]
    }

    init(directory: URL? = nil) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.directory = directory ?? documents.appendingPathComponent("books", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    /// 从文件选择器导入（处理安全作用域），返回库内文件名。
    func importBook(from pickedURL: URL) -> String? {
        let accessing = pickedURL.startAccessingSecurityScopedResource()
        defer { if accessing { pickedURL.stopAccessingSecurityScopedResource() } }
        let ext = pickedURL.pathExtension.lowercased()
        guard Self.readableExtensions.contains(ext) else { return nil }
        let fileName = "book-\(UUID().uuidString).\(ext)"
        do {
            try FileManager.default.copyItem(at: pickedURL, to: directory.appendingPathComponent(fileName))
            return fileName
        } catch {
            return nil
        }
    }

    /// 从下载数据入库（AI 自动下载路径）。
    func importBook(data: Data, ext: String) -> String? {
        let normalizedExt = ext.lowercased()
        guard Self.readableExtensions.contains(normalizedExt) else { return nil }
        let fileName = "book-\(UUID().uuidString).\(normalizedExt)"
        do {
            try data.write(to: directory.appendingPathComponent(fileName))
            return fileName
        } catch {
            return nil
        }
    }

    /// 写一份家长可见的副本到所选文件夹下的"电子书"目录；App 阅读仍以沙盒副本为准。
    @discardableResult
    func writeVisibleCopy(data: Data, ext: String, title: String, in pickedFolder: URL?) -> URL? {
        guard let pickedFolder else { return nil }
        let accessing = pickedFolder.startAccessingSecurityScopedResource()
        defer { if accessing { pickedFolder.stopAccessingSecurityScopedResource() } }
        let normalizedExt = ext.lowercased()
        guard Self.readableExtensions.contains(normalizedExt) else { return nil }
        let safeTitle = Self.safeFileName(title.isEmpty ? "章鱼老师电子书" : title)
        let folder = pickedFolder.appendingPathComponent("电子书", isDirectory: true)
        let target = folder.appendingPathComponent("\(safeTitle).\(normalizedExt)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try data.write(to: target)
            return target
        } catch {
            return nil
        }
    }

    func url(fileName: String) -> URL? {
        let target = directory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: target.path) ? target : nil
    }

    func delete(fileName: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
    }

    /// 分析书的体量：页数、字符数与章节结构（TXT/HTML/EPUB 视为 App 内文本阅读）。
    func analyze(fileName: String) -> (pageCount: Int, charCount: Int)? {
        analyzeDetailed(fileName: fileName).map { ($0.pageCount, $0.charCount) }
    }

    func analyzeDetailed(fileName: String) -> BookAnalysis? {
        guard let url = url(fileName: fileName) else { return nil }
        if fileName.hasSuffix(".pdf") {
            guard let document = PDFDocument(url: url) else { return nil }
            var chars = 0
            var words = 0
            for index in 0..<document.pageCount {
                let text = document.page(at: index)?.string ?? ""
                chars += text.count
                words += Self.wordCount(in: text)
            }
            return BookAnalysis(pageCount: document.pageCount, charCount: chars, wordCount: words, chapters: [])
        }
        if fileName.lowercased().hasSuffix(".epub") {
            guard let parsed = parseEPUB(fileName: fileName) else { return nil }
            return BookAnalysis(
                pageCount: max(1, parsed.chapters.count),
                charCount: parsed.text.count,
                wordCount: Self.wordCount(in: parsed.text),
                chapters: parsed.chapters
            )
        }
        guard let text = plainText(fileName: fileName) else { return nil }
        let chapters = Self.detectPlainTextChapters(text)
        return BookAnalysis(pageCount: 1, charCount: text.count, wordCount: Self.wordCount(in: text), chapters: chapters)
    }

    /// 取 TXT/HTML 的一段（按字符范围，用于分次阅读）。
    func textSlice(fileName: String, from start: Int, to end: Int) -> String? {
        guard let text = plainText(fileName: fileName) else { return nil }
        let lower = max(0, min(start, text.count))
        let upper = max(lower, min(end, text.count))
        let startIndex = text.index(text.startIndex, offsetBy: lower)
        let endIndex = text.index(text.startIndex, offsetBy: upper)
        return String(text[startIndex..<endIndex])
    }

    /// 取可分页/朗读的纯文本。PDF 走 PDFKit，不在这里抽。
    func plainText(fileName: String) -> String? {
        guard let url = url(fileName: fileName) else { return nil }
        let lower = fileName.lowercased()
        if lower.hasSuffix(".epub") {
            return parseEPUB(fileName: fileName)?.text
        }
        guard lower.hasSuffix(".txt") || lower.hasSuffix(".html") || lower.hasSuffix(".htm"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        if lower.hasSuffix(".html") || lower.hasSuffix(".htm") {
            return Self.stripHTML(raw)
        }
        return raw
    }

    /// 为 EPUB 图文阅读器准备可被 WKWebView 读取的章节 HTML 与图片资源。
    /// EPUB 文件本身仍留在 Documents/books；解压副本放在 Caches，可随时重建。
    func prepareEPUBForReading(fileName: String) -> EPUBRenderPackage? {
        guard let url = url(fileName: fileName),
              fileName.lowercased().hasSuffix(".epub"),
              let archive = try? Archive(url: url, accessMode: .read, pathEncoding: nil),
              let container = readText("META-INF/container.xml", from: archive),
              let opfPath = firstMatch(in: container, pattern: #"full-path\s*=\s*["']([^"']+)["']"#),
              let opf = readText(opfPath, from: archive) else { return nil }

        let root = epubRenderRoot(for: fileName)
        guard extractEPUBArchiveIfNeeded(archive, to: root) else { return nil }

        let basePath = (opfPath as NSString).deletingLastPathComponent
        let manifest = parseManifest(opf)
        let spineIDs = readableSpineIDs(opf)
        guard !manifest.isEmpty, !spineIDs.isEmpty else { return nil }

        var fullTextLength = 0
        var chapters: [EPUBRenderChapter] = []
        for idref in spineIDs {
            guard let item = manifest[idref] else { continue }
            let path = resolveEPUBPath(base: basePath, href: item.href)
            guard let html = readText(path, from: archive) else { continue }
            guard !isEPUBImageHelperPage(html, path: path) else { continue }
            let cleaned = Self.stripHTML(html)
            guard !cleaned.isEmpty else { continue }
            let title = chapterTitle(from: html) ?? item.title ?? "第 \(chapters.count + 1) 章"
            let start = fullTextLength
            if fullTextLength > 0 { fullTextLength += 2 }
            fullTextLength += cleaned.count
            let chapterURL = root.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: chapterURL.path) else { continue }
            chapters.append(EPUBRenderChapter(
                order: chapters.count + 1,
                title: title,
                fileURL: chapterURL,
                startCharacter: start,
                endCharacter: fullTextLength
            ))
        }
        guard !chapters.isEmpty else { return nil }
        return EPUBRenderPackage(rootURL: root, chapters: chapters)
    }

    /// 取 PDF/TXT/EPUB 阅读任务对应的真实内容摘录，用于 AI 出题或复述初评。
    func readingExcerpt(book: FamilyBook, reading: ReadingSpec, maxCharacters: Int = 4_000) -> String? {
        let limit = max(500, maxCharacters)
        if ["txt", "html", "htm", "epub"].contains(book.format.lowercased())
            || book.fileName.hasSuffix(".txt")
            || book.fileName.hasSuffix(".html")
            || book.fileName.hasSuffix(".htm")
            || book.fileName.hasSuffix(".epub") {
            let start = reading.pageStart ?? 0
            let end = reading.pageEnd ?? book.charCount
            return textSlice(fileName: book.fileName, from: start, to: end)
                .map { String($0.prefix(limit)) }
        }

        guard let url = url(fileName: book.fileName),
              let document = PDFDocument(url: url) else { return nil }
        let firstPage = max(1, reading.pageStart ?? 1)
        let lastPage = max(firstPage, min(reading.pageEnd ?? document.pageCount, document.pageCount))
        var text = ""
        for pageNumber in firstPage...lastPage {
            guard text.count < limit else { break }
            if let pageText = document.page(at: pageNumber - 1)?.string,
               !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                text += pageText + "\n"
            }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(limit))
    }

    private struct ParsedEPUB {
        var text: String
        var chapters: [BookChapter]
    }

    private func parseEPUB(fileName: String) -> ParsedEPUB? {
        guard let url = url(fileName: fileName),
              let archive = try? Archive(url: url, accessMode: .read, pathEncoding: nil),
              let container = readText("META-INF/container.xml", from: archive),
              let opfPath = firstMatch(
                  in: container,
                  pattern: #"full-path\s*=\s*["']([^"']+)["']"#
              ),
              let opf = readText(opfPath, from: archive) else { return nil }

        let basePath = (opfPath as NSString).deletingLastPathComponent
        let manifest = parseManifest(opf)
        let spineIDs = readableSpineIDs(opf)
        guard !manifest.isEmpty, !spineIDs.isEmpty else { return nil }

        var fullText = ""
        var chapters: [BookChapter] = []
        for idref in spineIDs {
            guard let item = manifest[idref] else { continue }
            let path = resolveEPUBPath(base: basePath, href: item.href)
            guard let html = readText(path, from: archive) else { continue }
            guard !isEPUBImageHelperPage(html, path: path) else { continue }
            let cleaned = Self.stripHTML(html)
            guard !cleaned.isEmpty else { continue }
            let start = fullText.count
            if !fullText.isEmpty { fullText += "\n\n" }
            let title = chapterTitle(from: html) ?? item.title ?? "第 \(chapters.count + 1) 章"
            fullText += cleaned
            let end = fullText.count
            chapters.append(BookChapter(
                order: chapters.count + 1,
                title: title,
                startCharacter: start,
                endCharacter: end
            ))
        }
        let text = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return ParsedEPUB(text: text, chapters: chapters)
    }

    private func readText(_ path: String, from archive: Archive) -> String? {
        guard let data = readData(path, from: archive) else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }

    private func readData(_ path: String, from archive: Archive) -> Data? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard let entry = archive[normalized] else { return nil }
        var data = Data()
        do {
            _ = try archive.extract(entry) { chunk in
                data.append(chunk)
            }
            guard data.count <= 12_000_000 else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private func epubRenderRoot(for fileName: String) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let root = caches
            .appendingPathComponent("OctoTeacherEPUBRender", isDirectory: true)
            .appendingPathComponent(Self.safeFileName(fileName), isDirectory: true)
        return root
    }

    private func extractEPUBArchiveIfNeeded(_ archive: Archive, to root: URL) -> Bool {
        let marker = root.appendingPathComponent(".octoteacher-ready")
        if FileManager.default.fileExists(atPath: marker.path) {
            return true
        }
        do {
            if FileManager.default.fileExists(atPath: root.path) {
                try FileManager.default.removeItem(at: root)
            }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for entry in archive {
                let normalized = entry.path.replacingOccurrences(of: "\\", with: "/")
                guard !normalized.contains(".."),
                      !normalized.hasPrefix("/") else { continue }
                let target = root.appendingPathComponent(normalized)
                if entry.type == .directory {
                    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                    continue
                }
                try FileManager.default.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                var data = Data()
                _ = try archive.extract(entry) { chunk in
                    data.append(chunk)
                }
                guard data.count <= 20_000_000 else { continue }
                try data.write(to: target)
            }
            try Data("ready".utf8).write(to: marker)
            return true
        } catch {
            return false
        }
    }

    private struct ManifestItem {
        var href: String
        var title: String?
    }

    private func parseManifest(_ opf: String) -> [String: ManifestItem] {
        let pattern = #"(?is)<item\b([^>]*)>"#
        let matches = regexMatches(in: opf, pattern: pattern)
        var items: [String: ManifestItem] = [:]
        for attrs in matches {
            guard let id = attribute("id", in: attrs),
                  let href = attribute("href", in: attrs) else { continue }
            let media = attribute("media-type", in: attrs)?.lowercased() ?? ""
            if media.contains("html") || href.lowercased().hasSuffix(".xhtml") || href.lowercased().hasSuffix(".html") {
                items[id] = ManifestItem(href: href, title: attribute("title", in: attrs))
            }
        }
        return items
    }

    private struct SpineReference {
        var id: String
        var isLinear: Bool
    }

    /// EPUB 的 `linear="no"` 页面通常是放大图片、注释或导航辅助页，不属于正常顺序阅读。
    /// 若一本不规范的 EPUB 把全部页面都标成非线性，则回退到完整书脊，避免阅读器空白。
    private func readableSpineIDs(_ opf: String) -> [String] {
        let references = regexMatches(in: opf, pattern: #"(?is)<itemref\b([^>]*)>"#)
            .compactMap { attrs -> SpineReference? in
                guard let id = attribute("idref", in: attrs) else { return nil }
                let linear = attribute("linear", in: attrs)?.lowercased()
                return SpineReference(id: id, isLinear: linear != "no")
            }
        let linearReferences = references.filter(\.isLinear)
        return (linearReferences.isEmpty ? references : linearReferences).map(\.id)
    }

    /// Gutenberg 等 EPUB 会把“点击图片放大后返回正文”的辅助页错误放进正常书脊。
    /// 这些页不是章节；若保留，阅读器会先显示一张小图和 `back`，必须再点一次才能回正文。
    private func isEPUBImageHelperPage(_ html: String, path: String) -> Bool {
        let normalizedTitle = (chapterTitle(from: html) ?? "")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'“”‘’")))
        let normalizedPath = path.lowercased()
        let looksLikeImageWrapper = normalizedTitle == "linked image"
            || normalizedPath.contains("linked-image")
            || normalizedPath.contains(".wrap-")
        guard looksLikeImageWrapper,
              html.range(of: #"(?is)<img\b"#, options: .regularExpression) != nil else {
            return false
        }
        return html.range(
            of: #"(?is)<a\b[^>]*(?:title\s*=\s*[\"']back[\"']|href\s*=\s*[\"'][^\"']+[\"'])[^>]*>\s*back\s*</a>"#,
            options: .regularExpression
        ) != nil
    }

    private func resolveEPUBPath(base: String, href: String) -> String {
        let cleanHref = href.removingPercentEncoding ?? href
        guard !base.isEmpty, base != "." else { return cleanHref }
        return "\(base)/\(cleanHref)"
            .replacingOccurrences(of: "//", with: "/")
    }

    private func chapterTitle(from html: String) -> String? {
        guard let raw = firstMatch(in: html, pattern: #"(?is)<title[^>]*>(.*?)</title>"#) else {
            return nil
        }
        let title = Self.stripHTML(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        regexMatches(in: text, pattern: pattern).first
    }

    private func regexMatches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let swiftRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[swiftRange])
        }
    }

    private func attribute(_ name: String, in attrs: String) -> String? {
        firstMatch(in: attrs, pattern: #"\b\#(name)\s*=\s*["']([^"']+)["']"#)
    }

    private static func stripHTML(_ html: String) -> String {
        var text = html
            .replacingOccurrences(of: "(?is)<script.*?</script>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "(?is)<style.*?</style>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "(?is)<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "(?is)</p>", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: "(?is)<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func detectPlainTextChapters(_ text: String) -> [BookChapter] {
        let lines = text.components(separatedBy: .newlines)
        var offset = 0
        var starts: [(title: String, start: Int)] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.range(of: #"^(chapter|第).{0,24}(章|回|\d+|[ivxlcdm]+)"#, options: [.regularExpression, .caseInsensitive]) != nil {
                starts.append((trimmed, offset))
            }
            offset += line.count + 1
        }
        guard !starts.isEmpty else { return [] }
        return starts.enumerated().map { index, item in
            BookChapter(
                order: index + 1,
                title: item.title,
                startCharacter: item.start,
                endCharacter: index == starts.count - 1 ? text.count : starts[index + 1].start
            )
        }
    }

    private static func safeFileName(_ text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: #"[\\/:*?"<>|]"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "章鱼老师电子书" : String(cleaned.prefix(80))
    }

    /// 英文按单词、中文按单字估算阅读体量；数字也计为一个学习单元。
    static func wordCount(in text: String) -> Int {
        let pattern = #"[A-Za-z0-9]+(?:['’-][A-Za-z0-9]+)*|\p{Han}"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return max(0, text.count / 5)
        }
        return expression.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}

/// 导入书的分次规划：普通书每次约 5,000-10,000 词，图文书每两章一次；家长可指定次数。
enum BookImportPlanner {

    static let minimumWordsPerSession = 5_000
    static let targetWordsPerSession = 7_500
    static let maximumWordsPerSession = 10_000

    static func recommendedSessionCount(wordCount: Int) -> Int {
        guard wordCount > 0 else { return 1 }
        guard wordCount > maximumWordsPerSession else { return 1 }
        let minimumSessions = Int(ceil(Double(wordCount) / Double(maximumWordsPerSession)))
        let maximumSessions = max(minimumSessions, wordCount / minimumWordsPerSession)
        let targetSessions = max(1, Int((Double(wordCount) / Double(targetWordsPerSession)).rounded()))
        return min(maximumSessions, max(minimumSessions, targetSessions))
    }

    /// 按体量划分：每次一个页码段（PDF）或字符段（TXT/HTML），附建议积分。
    static func plan(
        pageCount: Int,
        charCount: Int,
        wordCount: Int? = nil,
        age: Int,
        requestedSessions: Int? = nil
    ) -> [ReadingSessionDraft] {
        guard charCount > 0 else { return [] }
        _ = age
        let estimatedWords = max(1, wordCount ?? (charCount / 5))
        let automaticSessions = recommendedSessionCount(wordCount: estimatedWords)
        let upperBound = pageCount > 1 ? max(1, pageCount) : 100
        let sessions = min(upperBound, max(1, requestedSessions ?? automaticSessions))
        let isPDF = pageCount > 1
        var drafts: [ReadingSessionDraft] = []
        for index in 0..<sessions {
            let chapters: String
            var draft: ReadingSessionDraft
            if isPDF {
                let pagesPer = Double(pageCount) / Double(sessions)
                let start = Int(Double(index) * pagesPer) + 1
                let end = index == sessions - 1 ? pageCount : Int(Double(index + 1) * pagesPer)
                chapters = "第 \(start)-\(end) 页"
                draft = ReadingSessionDraft(order: index + 1, chapters: chapters, estimatedMinutes: 60, note: "")
                draft.suggestedPoints = 20
            } else {
                let charsPer = charCount / sessions
                let start = index * charsPer
                let end = index == sessions - 1 ? charCount : (index + 1) * charsPer
                chapters = "第 \(index + 1) 段（约 \(max(1, estimatedWords / sessions)) 词）"
                draft = ReadingSessionDraft(order: index + 1, chapters: chapters, estimatedMinutes: 60, note: "")
                draft.suggestedPoints = 20
                draft.startCharacter = start
                draft.endCharacter = end
            }
            drafts.append(draft)
        }
        return drafts
    }

    /// EPUB 优先按真实章节合并；TXT/HTML 没章节时退回字符均分。
    static func plan(
        chapters: [BookChapter],
        charCount: Int,
        wordCount: Int? = nil,
        age: Int,
        isPictureBook: Bool = false,
        requestedSessions: Int? = nil
    ) -> [ReadingSessionDraft] {
        guard !chapters.isEmpty else {
            return plan(
                pageCount: 1,
                charCount: charCount,
                wordCount: wordCount,
                age: age,
                requestedSessions: requestedSessions
            )
        }
        _ = age
        let groups: [[BookChapter]]
        let note: String
        if let requestedSessions {
            groups = groupedChapters(chapters, sessions: min(chapters.count, max(1, requestedSessions)))
            note = "按家长指定次数均衡划分 EPUB 真实章节。"
        } else if isPictureBook {
            groups = groupedChapters(chapters, chaptersPerSession: 2)
            note = "幼儿图文书按每两章一次自动划分。"
        } else {
            let estimatedWords = max(1, wordCount ?? (charCount / 5))
            let sessions = min(chapters.count, recommendedSessionCount(wordCount: estimatedWords))
            groups = groupedChapters(chapters, sessions: sessions)
            note = "按每次约 5,000-10,000 词均衡划分 EPUB 真实章节。"
        }
        return groups.enumerated().map { index, group in
            let first = group.first
            let last = group.last
            let title: String
            if group.count == 1, let first {
                title = "第 \(first.order) 章：\(first.title)"
            } else if let first, let last {
                title = "第 \(first.order)-\(last.order) 章：\(first.title) 到 \(last.title)"
            } else {
                title = "第 \(index + 1) 段"
            }
            var draft = ReadingSessionDraft(order: index + 1, chapters: title, estimatedMinutes: 60, note: note)
            draft.suggestedPoints = 20
            draft.startCharacter = first?.startCharacter
            draft.endCharacter = last?.endCharacter
            return draft
        }
    }

    static func charRange(index: Int, sessions: Int, chapters: [BookChapter], charCount: Int) -> (start: Int, end: Int) {
        guard !chapters.isEmpty else {
            return charRange(index: index, sessions: sessions, charCount: charCount)
        }
        let groups = groupedChapters(chapters, sessions: sessions)
        guard groups.indices.contains(index),
              let first = groups[index].first,
              let last = groups[index].last else {
            return charRange(index: index, sessions: sessions, charCount: charCount)
        }
        return (max(0, first.startCharacter), min(charCount, last.endCharacter))
    }

    private static func groupedChapters(_ chapters: [BookChapter], sessions: Int) -> [[BookChapter]] {
        let sorted = chapters.sorted(by: { $0.order < $1.order })
        guard sessions > 0, !sorted.isEmpty else { return [] }
        let normalizedSessions = min(sessions, sorted.count)
        var remainingCharacters = sorted.reduce(0) {
            $0 + max(1, $1.endCharacter - $1.startCharacter)
        }
        var cursor = 0
        var result: [[BookChapter]] = []

        for sessionIndex in 0..<normalizedSessions {
            let remainingSessions = normalizedSessions - sessionIndex
            let target = Double(remainingCharacters) / Double(remainingSessions)
            let latestExclusiveEnd = sorted.count - (remainingSessions - 1)
            var group: [BookChapter] = []
            var groupCharacters = 0

            while cursor < latestExclusiveEnd {
                let chapter = sorted[cursor]
                let chapterCharacters = max(1, chapter.endCharacter - chapter.startCharacter)
                if !group.isEmpty {
                    let currentDistance = abs(target - Double(groupCharacters))
                    let appendedDistance = abs(target - Double(groupCharacters + chapterCharacters))
                    if appendedDistance > currentDistance { break }
                }
                group.append(chapter)
                groupCharacters += chapterCharacters
                cursor += 1
            }

            if group.isEmpty, cursor < sorted.count {
                let chapter = sorted[cursor]
                group = [chapter]
                groupCharacters = max(1, chapter.endCharacter - chapter.startCharacter)
                cursor += 1
            }
            result.append(group)
            remainingCharacters = max(0, remainingCharacters - groupCharacters)
        }
        return result
    }

    private static func groupedChapters(_ chapters: [BookChapter], chaptersPerSession: Int) -> [[BookChapter]] {
        let sorted = chapters.sorted(by: { $0.order < $1.order })
        let size = max(1, chaptersPerSession)
        var groups: [[BookChapter]] = []
        var start = 0
        while start < sorted.count {
            let end = min(sorted.count, start + size)
            groups.append(Array(sorted[start..<end]))
            start = end
        }
        return groups
    }

    /// PDF 页码段：给第 index 次（0-based）算起止页。
    static func pageRange(index: Int, sessions: Int, pageCount: Int) -> (start: Int, end: Int) {
        let pagesPer = Double(pageCount) / Double(sessions)
        let start = Int(Double(index) * pagesPer) + 1
        let end = index == sessions - 1 ? pageCount : Int(Double(index + 1) * pagesPer)
        return (start, max(start, end))
    }

    /// TXT 字符段。
    static func charRange(index: Int, sessions: Int, charCount: Int) -> (start: Int, end: Int) {
        let per = charCount / sessions
        let start = index * per
        let end = index == sessions - 1 ? charCount : (index + 1) * per
        return (start, end)
    }
}
