import SwiftUI
import WebKit

/// Shows an SVG file as an image. The SVG is embedded through `<img>`, where
/// WebKit never runs its scripts, follows its links, or loads anything it
/// references; page JavaScript is off and remote requests are blocked as well.
struct SVGPreviewView: View {
    let fileURL: URL
    var onPreviewReady: (WKWebView?) -> Void = { _ in }

    @State private var configuration: WKWebViewConfiguration?
    @State private var html: String?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let configuration, let html {
                SVGWebView(html: html, configuration: configuration, onPreviewReady: onPreviewReady)
                    .accessibilityIdentifier("svg-preview")
            } else if let errorMessage {
                ContentUnavailableView(
                    AppStrings.Errors.cannotOpenFileTitle,
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ProgressView()
            }
        }
        .task(id: fileURL) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        onPreviewReady(nil)
        do {
            let data = try Data(contentsOf: fileURL)
            let loadedConfiguration = try await HTMLPreviewConfiguration.make(mode: .safePreview)
            guard !Task.isCancelled else { return }
            loadedConfiguration.ignoresViewportScaleLimits = true
            html = Self.page(svgData: data, title: fileURL.deletingPathExtension().lastPathComponent)
            configuration = loadedConfiguration
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func page(svgData: Data, title: String) -> String {
        let source = "data:image/svg+xml;base64,\(svgData.base64EncodedString())"
        return """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
        <title>\(escape(title))</title>
        <style>
        :root { color-scheme: light dark; }
        html, body { margin: 0; background: #f2f2f7; }
        @media (prefers-color-scheme: dark) { html, body { background: #1c1c1e; } }
        body { min-height: 100vh; box-sizing: border-box; padding: 16px; display: flex; align-items: center; justify-content: center; }
        figure { margin: 0; width: 100%; max-width: 960px; background: #fff; border-radius: 12px; padding: 16px; box-sizing: border-box; box-shadow: 0 1px 3px rgba(0,0,0,.12); }
        img { display: block; width: 100%; height: auto; max-height: calc(100vh - 64px); object-fit: contain; color: #6e6e73; font: 15px -apple-system, sans-serif; text-align: center; }
        @media print { html, body { background: #fff; } body { min-height: 0; padding: 0; } figure { box-shadow: none; padding: 0; } img { max-height: 640pt; } }
        </style></head>
        <body><figure><img src="\(source)" alt="\(escape(FormatStrings.svgUnavailable))"></figure></body></html>
        """
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private struct SVGWebView: UIViewRepresentable {
    let html: String
    let configuration: WKWebViewConfiguration
    let onPreviewReady: (WKWebView?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPreviewReady: onPreviewReady) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onPreviewReady: (WKWebView?) -> Void
        private var didLoad = false

        init(onPreviewReady: @escaping (WKWebView?) -> Void) {
            self.onPreviewReady = onPreviewReady
        }

        // Only the generated page itself may load; there is nothing to navigate to.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard !didLoad, navigationAction.request.url?.absoluteString == "about:blank" else { return .cancel }
            return .allow
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didLoad = true
            onPreviewReady(webView)
        }
    }
}
