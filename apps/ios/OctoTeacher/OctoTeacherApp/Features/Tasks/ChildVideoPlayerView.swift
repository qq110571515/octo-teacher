import SwiftUI
import WebKit

/// 孩子端 App 内视频播放器。
///
/// 孩子手机锁定时 YouTube App / 浏览器都被屏蔽，学习视频必须在 章鱼老师 内部播放。
/// 用 WKWebView 加载家长确认过的视频 embed 地址，孩子不离开 App。
struct ChildVideoPlayerView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(FamilyCloudSessionStore.self) private var familyCloud
    @Environment(\.childSurfaceLanguage) private var childSurfaceLanguage
    let video: VideoSpec
    @State private var playbackMode: VideoPlaybackMode = .privacyEnhanced
    @State private var startedAt = Date()
    @State private var cloudSessionRef = UUID().uuidString.lowercased()
    @State private var didQueueCloudSession = false

    private var loc: ChildLocalizationContext { ChildLocalizationContext(language: childSurfaceLanguage) }

    var body: some View {
        Group {
            if let url = currentPlaybackURL {
                VStack(spacing: 0) {
                    EmbeddedVideoWebView(url: url)
                        .id(url.absoluteString)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    playbackControls
                }
            } else {
                ContentUnavailableView(
                    loc.pick("视频打不开", "Video won't open"),
                    systemImage: "play.slash",
                    description: Text(loc.pick(
                        "告诉大人重新选择一个可在 章鱼老师 内播放的视频链接。",
                        "Ask a grown-up to pick a video link that can play inside Octo Teacher."
                    ))
                )
            }
        }
        .navigationTitle(loc.pick("看视频学习", "Watch & Learn"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Text(loc.pick(
                    "至少认真看 \(video.minWatchMinutes) 分钟，看完回去说说学到了什么。",
                    "Watch carefully for at least \(video.minWatchMinutes) minutes, then go back and share what you learned."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            startedAt = Date()
        }
        .onDisappear {
            let seconds = max(0, Int(Date().timeIntervalSince(startedAt)))
            guard !didQueueCloudSession, seconds > 2 else { return }
            didQueueCloudSession = true
            let targetSeconds = max(1, video.minWatchMinutes * 60)
            familyCloud.queueActivityEvent(
                clientRef: "activity:video:\(cloudSessionRef)",
                kind: .video,
                title: loc.pick("教育视频", "Educational video"),
                durationSeconds: seconds,
                progressPercent: min(100, Double(seconds) / Double(targetSeconds) * 100)
            )
        }
    }

    private var currentPlaybackURL: URL? {
        switch playbackMode {
        case .privacyEnhanced:
            return VideoEmbedResolver.embedURL(for: video.urlString)
        case .compatibility:
            return VideoEmbedResolver.compatibilityEmbedURL(for: video.urlString)
                ?? VideoEmbedResolver.embedURL(for: video.urlString)
        }
    }

    private var canSwitchPlaybackMode: Bool {
        VideoEmbedResolver.compatibilityEmbedURL(for: video.urlString) != nil
    }

    private var playbackControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                playbackMode.statusText(for: loc.language),
                systemImage: playbackMode.systemImage
            )
            .accessibilityIdentifier("child-video-player-playback-mode")

            if canSwitchPlaybackMode {
                Button {
                    playbackMode.toggle()
                } label: {
                    Label(playbackMode.toggleTitle(for: loc.language), systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("child-video-player-toggle-playback-mode")

                Text(ChildVideoPlayerCopy.platformLimitWithSwitch(for: loc.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("child-video-player-platform-limit-note")
            } else {
                Text(ChildVideoPlayerCopy.platformLimitWithoutSwitch(for: loc.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("child-video-player-platform-limit-note")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
    }
}

private enum VideoPlaybackMode {
    case privacyEnhanced
    case compatibility

    mutating func toggle() {
        self = self == .privacyEnhanced ? .compatibility : .privacyEnhanced
    }

    func statusText(for language: AppInterfaceLanguage) -> String {
        switch self {
        case .privacyEnhanced:
            return language.pick("正在使用隐私优先播放方式。", "Playing in privacy-first mode.")
        case .compatibility:
            return language.pick("正在使用兼容播放方式。", "Playing in compatibility mode.")
        }
    }

    func toggleTitle(for language: AppInterfaceLanguage) -> String {
        switch self {
        case .privacyEnhanced:
            return ChildVideoPlayerCopy.switchToCompatibilityTitle(for: language)
        case .compatibility:
            return ChildVideoPlayerCopy.switchToPrivacyTitle(for: language)
        }
    }

    var systemImage: String {
        switch self {
        case .privacyEnhanced:
            return "hand.raised"
        case .compatibility:
            return "play.rectangle"
        }
    }
}

enum ChildVideoPlayerCopy {
    static func platformLimitWithSwitch(for language: AppInterfaceLanguage) -> String {
        language.pick(
            "如果视频提示不能在 App 里播放，先点上面的按钮换一种 章鱼老师 内播放方式；仍不行，再让大人换一个允许内嵌播放的视频。",
            "If the video says it can't play in the app, tap the button above to try another in-app playback mode. If it still won't play, ask a grown-up to pick a video that allows embedded playback."
        )
    }

    static func platformLimitWithoutSwitch(for language: AppInterfaceLanguage) -> String {
        language.pick(
            "如果视频打不开，不是你的问题；请让大人重新选择一个可在 章鱼老师 内播放的视频。",
            "If the video won't open, it's not your fault — ask a grown-up to pick another video that plays inside Octo Teacher."
        )
    }

    static func switchToCompatibilityTitle(for language: AppInterfaceLanguage) -> String {
        language.pick("视频不能播？换一种播放方式", "Video won't play? Try another mode")
    }

    static func switchToPrivacyTitle(for language: AppInterfaceLanguage) -> String {
        language.pick("切回隐私播放方式", "Switch back to privacy mode")
    }

    static func allUserFacingPlaybackHelp(for language: AppInterfaceLanguage) -> [String] {
        [
            platformLimitWithSwitch(for: language),
            platformLimitWithoutSwitch(for: language),
            switchToCompatibilityTitle(for: language),
            switchToPrivacyTitle(for: language)
        ]
    }

    /// 兼容既有测试的中文默认集合。
    static var allUserFacingPlaybackHelp: [String] {
        allUserFacingPlaybackHelp(for: .chinese)
    }
}

/// WKWebView 封装：只加载家长确认的这一个地址，禁止跳出到其它网站。
private struct EmbeddedVideoWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.bounces = false
        webView.load(VideoEmbedResolver.playbackRequest(for: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(allowedHost: url.host ?? "")
    }

    /// 拦截跳出：只允许停留在播放器同域，点推荐/外链一律不放行。
    final class Coordinator: NSObject, WKNavigationDelegate {
        let allowedHost: String

        init(allowedHost: String) {
            self.allowedHost = allowedHost.lowercased()
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let host = navigationAction.request.url?.host?.lowercased() else {
                decisionHandler(.allow)
                return
            }
            let requestURL = navigationAction.request.url
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            if isMainFrame,
               isYouTubeHost(host),
               requestURL.map(VideoEmbedResolver.isYouTubeEmbedURL) != true {
                decisionHandler(.cancel)
                return
            }
            // 允许播放器自身与其静态资源域；阻止导航去其它站点。
            if host == allowedHost || matches(host, suffixes: [allowedHost])
                || matches(host, suffixes: playerResourceHosts)
                || (!isMainFrame && matches(host, suffixes: resourceOnlyHosts)) {
                decisionHandler(.allow)
            } else if isMainFrame || navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        private var playerResourceHosts: [String] {
            [
                "youtube.com",
                "youtube-nocookie.com",
                "ytimg.com",
                "googlevideo.com",
                "hdslb.com",
                "bilivideo.com"
            ]
        }

        private var resourceOnlyHosts: [String] {
            [
                "google.com",
                "gstatic.com"
            ]
        }

        private func isYouTubeHost(_ host: String) -> Bool {
            matches(host, suffixes: ["youtube.com", "youtube-nocookie.com", "youtu.be"])
        }

        private func matches(_ host: String, suffixes: [String]) -> Bool {
            suffixes.contains { suffix in
                host == suffix || host.hasSuffix("." + suffix)
            }
        }
    }
}
