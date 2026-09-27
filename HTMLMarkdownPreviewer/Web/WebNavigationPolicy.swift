import WebKit

@MainActor
final class WebNavigationPolicy: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let entryURL: URL
    private let readAccessRootURL: URL
    private let onLocalPageNavigation: ((URL) -> Bool)?
    private let onPageFinished: ((URL) -> Void)?
    private let onPreviewReady: (WKWebView?) -> Void

    init(
        mode: HTMLPreviewMode,
        entryURL: URL,
        readAccessRootURL: URL,
        onLocalPageNavigation: ((URL) -> Bool)? = nil,
        onPageFinished: ((URL) -> Void)? = nil,
        onPreviewReady: @escaping (WKWebView?) -> Void = { _ in }
    ) {
        // Safe and interactive previews share the same navigation boundary.
        // Their script/resource permissions are set by HTMLPreviewConfiguration.
        self.entryURL = entryURL
        self.readAccessRootURL = readAccessRootURL.standardizedFileURL.resolvingSymlinksInPath()
        self.onLocalPageNavigation = onLocalPageNavigation
        self.onPageFinished = onPageFinished
        self.onPreviewReady = onPreviewReady
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        onPreviewReady(nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onPreviewReady(webView)
        if let url = webView.url, permitsLocalNavigation(to: url) {
            onPageFinished?(url)
        }
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

    /// Normalize traversal and check resolved symlink destinations, including a
    /// sibling whose directory name merely starts with the root's name.
    func permitsLocalNavigation(to url: URL) -> Bool {
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost" else { return false }
        let destination = url.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = readAccessRootURL.path
        return destination.path == rootPath || destination.path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType != .formSubmitted,
              navigationAction.navigationType != .formResubmitted,
              let url = navigationAction.request.url,
              permitsLocalNavigation(to: url) else {
            decisionHandler(.cancel)
            return
        }

        if navigationAction.targetFrame?.isMainFrame != false,
           handlesPackageNavigation(url, currentURL: webView.url) {
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              navigationAction.navigationType != .formSubmitted,
              navigationAction.navigationType != .formResubmitted,
              let url = navigationAction.request.url,
              permitsLocalNavigation(to: url) else { return nil }

        // No second browser or window is created. A local target=_blank anchor
        // behaves just like an ordinary link in the current reader.
        if !handlesPackageNavigation(url, currentURL: webView.url) {
            webView.load(navigationAction.request)
        }
        return nil
    }

    private func handlesPackageNavigation(_ url: URL, currentURL: URL?) -> Bool {
        guard let onLocalPageNavigation else { return false }
        let currentPath = (currentURL ?? entryURL).standardizedFileURL.resolvingSymlinksInPath().path
        guard url.standardizedFileURL.resolvingSymlinksInPath().path != currentPath else { return false }
        if ["html", "htm", "md", "markdown"].contains(url.pathExtension.lowercased()) {
            _ = onLocalPageNavigation(url)
        }
        // A package's native reader owns every page transition. Rejected or
        // unsupported targets must not replace WebKit content behind a stale
        // page title, search state, or export selection.
        return true
    }
}
