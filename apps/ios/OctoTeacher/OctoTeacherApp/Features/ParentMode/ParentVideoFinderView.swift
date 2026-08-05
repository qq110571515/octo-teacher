import SwiftUI
import WebKit

/// 家长 App 内找视频：内嵌浏览器打开搜索页，浏览到想要的视频后
/// 点「就用当前这个视频」自动抓取链接——不用复制粘贴。
struct ParentVideoFinderView: View {
    @Environment(\.dismiss) private var dismiss

    let startURL: URL
    let onPick: (URL) -> Void

    @State private var currentURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            FinderWebView(startURL: startURL, currentURL: $currentURL)
            VStack(spacing: 6) {
                if let currentURL {
                    Text(currentURL.absoluteString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Button {
                    if let currentURL {
                        onPick(currentURL)
                        dismiss()
                    }
                } label: {
                    Label("就用当前这个视频", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isVideoPage)
                if !isVideoPage {
                    Text("点开一个具体视频后，这个按钮就能用了。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.thinMaterial)
        }
        .navigationTitle("找视频")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 当前页面是否是一个具体视频（而不是搜索列表/首页）。
    private var isVideoPage: Bool {
        Self.looksLikeVideoPage(currentURL)
    }

    /// 纯函数便于测试：覆盖 YouTube 网页版/移动版/短链/Bilibili。
    nonisolated static func looksLikeVideoPage(_ url: URL?) -> Bool {
        guard let url else { return false }
        let full = url.absoluteString.lowercased()
        return full.contains("watch?v=") || full.contains("/watch/")
            || full.contains("/shorts/") || full.contains("youtu.be/")
            || full.contains("/video/bv") || full.contains("/video/av")
    }
}

/// 跟踪当前地址的内嵌浏览器。
private struct FinderWebView: UIViewRepresentable {
    let startURL: URL
    @Binding var currentURL: URL?

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        // YouTube 是单页应用，点视频不触发常规导航回调——必须 KVO 监听 url。
        context.coordinator.observeURL(of: webView)
        webView.load(URLRequest(url: startURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator { url in currentURL = url }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onURLChange: (URL?) -> Void
        private var urlObservation: NSKeyValueObservation?

        init(onURLChange: @escaping (URL?) -> Void) {
            self.onURLChange = onURLChange
        }

        func observeURL(of webView: WKWebView) {
            urlObservation = webView.observe(\.url, options: [.new]) { [weak self] _, change in
                let url = change.newValue ?? nil
                DispatchQueue.main.async {
                    self?.onURLChange(url)
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onURLChange(webView.url)
        }
    }
}
