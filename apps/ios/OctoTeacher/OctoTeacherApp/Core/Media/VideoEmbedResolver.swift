import Foundation

/// 把家长确认的视频链接解析为 App 内嵌播放地址。
///
/// 为什么必须 App 内播放：孩子手机处于锁定状态时，YouTube App、浏览器等
/// 娱乐入口都是被屏蔽的；学习视频必须在 章鱼老师 内部播放，孩子不出应用。
enum VideoEmbedResolver {

    /// 解析出可用于 WKWebView 的 embed URL；无法识别时返回 nil。
    /// 普通网页、搜索页、购买页不能被当成学习视频入口，避免孩子被带出到广告或商店页面。
    static func embedURL(
        for urlString: String,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.octoteacher.app"
    ) -> URL? {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased() else { return nil }

        // YouTube: watch?v=ID / youtu.be/ID / shorts/ID / 已是 embed
        if host.contains("youtube.com") || host.contains("youtu.be") {
            if let id = youtubeVideoId(from: url) {
                // no-cookie 降低跟踪面；rel=0 尽量不出推荐流；playsinline 保持页内播放。
                return youtubeEmbedURL(videoId: id, host: "www.youtube-nocookie.com", bundleIdentifier: bundleIdentifier)
            }
            return nil
        }

        // Bilibili: /video/BVxxxx
        if host.contains("bilibili.com") {
            let parts = url.pathComponents
            if let index = parts.firstIndex(of: "video"), index + 1 < parts.count {
                let id = parts[index + 1]
                if id.hasPrefix("BV") {
                    return URL(string: "https://player.bilibili.com/player.html?bvid=\(id)&autoplay=0")
                }
                if id.lowercased().hasPrefix("av"), let aid = Int(id.dropFirst(2)) {
                    return URL(string: "https://player.bilibili.com/player.html?aid=\(aid)&autoplay=0")
                }
            }
            return nil
        }

        // 其它链接只允许 HTTPS 直连媒体文件；普通网页、搜索页、购买页返回 nil。
        if url.scheme == "https", isDirectMediaFile(url) {
            return url
        }
        return nil
    }

    /// Error 153 兜底：少数 iOS WebView/视频组合对 no-cookie 域仍失败时，
    /// 允许孩子/家长在 App 内切到标准 YouTube embed 域再试一次。
    static func compatibilityEmbedURL(
        for urlString: String,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.octoteacher.app"
    ) -> URL? {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased(),
              host.contains("youtube.com") || host.contains("youtu.be"),
              let id = youtubeVideoId(from: url) else {
            return nil
        }
        return youtubeEmbedURL(videoId: id, host: "www.youtube.com", bundleIdentifier: bundleIdentifier)
    }

    static func embeddedHTML(
        for url: URL,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.octoteacher.app"
    ) -> (html: String, baseURL: URL)? {
        guard isYouTubeEmbed(url) else { return nil }
        let source = escapedHTMLAttribute(url.absoluteString)
        let html = """
        <!doctype html>
        <html lang="zh-Hans">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
          <meta name="referrer" content="strict-origin-when-cross-origin">
          <style>
            html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: #000; overflow: hidden; }
            iframe { position: fixed; inset: 0; width: 100%; height: 100%; border: 0; }
          </style>
        </head>
        <body>
          <iframe
            src="\(source)"
            title="章鱼老师 学习视频"
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
            referrerpolicy="strict-origin-when-cross-origin"
            allowfullscreen>
          </iframe>
        </body>
        </html>
        """
        let baseURL = URL(string: youtubeReferrer(bundleIdentifier: bundleIdentifier))
            ?? URL(string: "https://com.octoteacher.app")!
        return (html, baseURL)
    }

    static func playbackRequest(
        for url: URL,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.octoteacher.app"
    ) -> URLRequest {
        var request = URLRequest(url: url)
        if isYouTubeEmbed(url) {
            let referrer = youtubeReferrer(bundleIdentifier: bundleIdentifier)
            request.addValue(referrer, forHTTPHeaderField: "Referer")
        }
        return request
    }

    static func isYouTubeEmbedURL(_ url: URL) -> Bool {
        isYouTubeEmbed(url)
    }

    static func youtubeReferrer(bundleIdentifier: String) -> String {
        let normalized = bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return "https://\(normalized.isEmpty ? "com.octoteacher.app" : normalized)"
    }

    static func youtubeVideoId(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        if host.contains("youtu.be") {
            let id = url.pathComponents.dropFirst().first ?? ""
            return id.isEmpty ? nil : id
        }
        let parts = url.pathComponents
        if let index = parts.firstIndex(where: { $0 == "embed" || $0 == "shorts" }), index + 1 < parts.count {
            return parts[index + 1]
        }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let id = components.queryItems?.first(where: { $0.name == "v" })?.value,
           !id.isEmpty {
            return id
        }
        return nil
    }

    private static func youtubeEmbedURL(videoId: String, host: String, bundleIdentifier: String) -> URL? {
        var components = URLComponents(string: "https://\(host)/embed/\(videoId)")
        components?.queryItems = [
            URLQueryItem(name: "rel", value: "0"),
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "origin", value: youtubeReferrer(bundleIdentifier: bundleIdentifier))
        ]
        return components?.url
    }

    private static func isYouTubeEmbed(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return (host.contains("youtube.com") || host.contains("youtube-nocookie.com"))
            && url.pathComponents.contains("embed")
    }

    private static func isDirectMediaFile(_ url: URL) -> Bool {
        let allowedExtensions = Set(["mp4", "m4v", "mov", "webm", "mp3", "m4a", "wav"])
        return allowedExtensions.contains(url.pathExtension.lowercased())
    }

    private static func escapedHTMLAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
