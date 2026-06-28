import WebKit

@MainActor
final class WebNavigationPolicy: NSObject, WKNavigationDelegate {
    private let mode: HTMLPreviewMode

    init(mode: HTMLPreviewMode) {
        self.mode = mode
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
