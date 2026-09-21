import WebKit

@MainActor
final class WebNavigationPolicy: NSObject, WKNavigationDelegate {
    private let mode: HTMLPreviewMode
    private let onPreviewReady: (WKWebView?) -> Void

    init(mode: HTMLPreviewMode, onPreviewReady: @escaping (WKWebView?) -> Void = { _ in }) {
        self.mode = mode
        self.onPreviewReady = onPreviewReady
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        onPreviewReady(nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onPreviewReady(webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onPreviewReady(nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onPreviewReady(nil)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        onPreviewReady(nil)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if navigationAction.navigationType == .formSubmitted {
            decisionHandler(.cancel)
            return
        }

        if url.isFileURL {
            decisionHandler(.allow)
            return
        }

        switch mode {
        case .safePreview:
            decisionHandler(.cancel)
        case .interactive:
            decisionHandler(.cancel)
        }
    }
}
