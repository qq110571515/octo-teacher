import Foundation

/// 图书购买/下载渠道：按书名生成各平台的搜索直达链接（纯函数、不依赖 AI，
/// 不会编造无效地址）。家长选好书后自己去正规渠道购买或下载，规避版权风险。
enum BookMarketLinks {

    struct Channel: Identifiable, Equatable {
        let id: String
        let name: String
        let url: URL
    }

    enum AcquisitionKind: Equatable {
        /// App 可直接尝试下载并导入（免费/无 DRM 优先）。
        case directDownload
        /// 家长已有 PDF/TXT 文件，走系统文件选择器导入。
        case importOwnedFile
        /// 外部购买/借阅后，可能只能在对方 App 或网页阅读。
        case externalPurchase
        /// 明确大概率不能导入 章鱼老师，只适合作为外部阅读入口。
        case externalReadOnly
    }

    struct AcquisitionOption: Identifiable, Equatable {
        let id: String
        let kind: AcquisitionKind
        let title: String
        let detail: String
        let systemImage: String
        let channel: Channel?
    }

    /// 电子书渠道：内容语言主导（选英文就推国际电子书渠道），地区只影响
    /// Apple Books 商店区域。这里保留完整外部渠道清单；AI 阅读布置页会再筛出
    /// 免费/公版/无 DRM 的开放书源，避免把商业书店误当作可导入来源。
    static func channels(
        for bookTitle: String,
        region: FamilyRegion,
        contentLanguage: FamilyLanguage
    ) -> [Channel] {
        let query = bookTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? bookTitle
        let appleStore = region == .china ? "cn" : "us"
        let englishFreeSources: [(String, String)] = [
            ("Project Gutenberg（免费公版）", "https://www.gutenberg.org/ebooks/search/?query=\(query)"),
            ("Standard Ebooks（免费公版）", "https://standardebooks.org/ebooks?query=\(query)"),
            ("Internet Archive（免费借阅/公版）", "https://archive.org/search?query=\(query)"),
            ("Open Library（免费借阅）", "https://openlibrary.org/search?q=\(query)"),
            ("Wikisource（免费公版）", "https://en.wikisource.org/w/index.php?search=\(query)")
        ]
        let englishCommercialStores: [(String, String)] = [
            ("Amazon Kindle", "https://www.amazon.com/s?k=\(query)&i=digital-text"),
            ("Apple Books", "https://books.apple.com/\(appleStore)/search?term=\(query)"),
            ("Google Play Books", "https://play.google.com/store/search?q=\(query)&c=books"),
            ("Kobo", "https://www.kobo.com/us/en/search?query=\(query)")
        ]
        let englishEbooks = englishFreeSources + englishCommercialStores
        let chineseEbooks: [(String, String)] = [
            ("微信读书", "https://weread.qq.com/web/search/books?keyword=\(query)"),
            ("Apple Books", "https://books.apple.com/\(appleStore)/search?term=\(query)"),
            ("京东读书", "https://e.jd.com/ebook/search?keyword=\(query)"),
            ("豆瓣阅读", "https://read.douban.com/search?q=\(query)"),
            ("Kindle 中文", "https://www.amazon.com/s?k=\(query)&i=digital-text")
        ]
        let picked: [(String, String)]
        switch contentLanguage {
        case .english: picked = englishEbooks
        case .chinese: picked = chineseEbooks
        case .bilingual: picked = Array(englishFreeSources.prefix(3)) + Array(englishCommercialStores.prefix(1)) + Array(chineseEbooks.prefix(2))
        }
        return picked.compactMap { name, urlString in
            guard let url = URL(string: urlString) else { return nil }
            return Channel(id: name, name: name, url: url)
        }
    }

    /// 家长视角的「获取这本书」路径。不要把所有链接混成购买渠道：
    /// 先显示能在 章鱼老师 内闭环的方式，再显示外部只读/购买兜底。
    static func acquisitionOptions(
        for bookTitle: String,
        region: FamilyRegion,
        contentLanguage: FamilyLanguage
    ) -> [AcquisitionOption] {
        let channels = channels(for: bookTitle, region: region, contentLanguage: contentLanguage)
        let openSources = channels.filter(isFreeOrPublicReadingChannel)
        let external = openSources.map { channel in
            AcquisitionOption(
                id: "channel-\(channel.id)",
                kind: externalKind(for: channel),
                title: channel.name,
                detail: externalDetail(for: channel),
                systemImage: externalKind(for: channel) == .externalReadOnly ? "rectangle.on.rectangle" : "safari",
                channel: channel
            )
        }
        return [
            AcquisitionOption(
                id: "direct-download",
                kind: .directDownload,
                title: "查找可下载版本",
                detail: "优先找免费公版/无 DRM 的 PDF/TXT；先列出真实下载候选，下载后再校验文件并生成阅读计划。",
                systemImage: "arrow.down.doc",
                channel: nil
            ),
            AcquisitionOption(
                id: "import-owned-file",
                kind: .importOwnedFile,
                title: "我已有电子书文件",
                detail: "支持 PDF/TXT。Kindle、微信读书等加密书通常无法导出给第三方 App。",
                systemImage: "doc.badge.plus",
                channel: nil
            )
        ] + external
    }

    static func externalKind(for channel: Channel) -> AcquisitionKind {
        let name = channel.name.lowercased()
        if name.contains("kindle")
            || name.contains("微信读书")
            || name.contains("京东读书")
            || name.contains("豆瓣阅读")
            || name.contains("apple books")
            || name.contains("google play")
            || name.contains("kobo") {
            return .externalReadOnly
        }
        return .externalPurchase
    }

    static func externalDetail(for channel: Channel) -> String {
        switch externalKind(for: channel) {
        case .externalReadOnly:
            return "可购买或借阅，但大概率只能在对方 App/网页阅读，不能自动装入 章鱼老师。"
        case .externalPurchase:
            if isFreeOrPublicReadingChannel(channel) {
                if channel.name.lowercased().contains("open library") {
                    return "可免费借阅/查找公版；借阅书通常只能在对方页面阅读，只有可下载 EPUB/TXT/PDF/无 DRM 文件才可导入 章鱼老师。"
                }
                return "优先从这里找免费公版/无 DRM 版本；若能下载 EPUB/TXT/PDF，可导入 章鱼老师。"
            }
            return "可去正规站点查看；若能下载 PDF/TXT/无 DRM 文件，可再导入 章鱼老师。"
        case .directDownload, .importOwnedFile:
            return ""
        }
    }

    static func isFreeOrPublicReadingChannel(_ channel: Channel) -> Bool {
        let name = channel.name.lowercased()
        return name.contains("gutenberg")
            || name.contains("standard ebooks")
            || name.contains("internet archive")
            || name.contains("open library")
            || name.contains("wikisource")
    }
}
