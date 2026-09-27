import Foundation
import WebKit

/// Only immutable, bundled renderer files are exposed through this scheme.
/// Imported Markdown has no access to arbitrary files or network resources.
enum MarkdownWebResources {
    static let origin = "markdown-resource://bundle"

    @MainActor
    static func makeConfiguration() async throws -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.setURLSchemeHandler(MarkdownResourceHandler(), forURLScheme: "markdown-resource")
        configuration.userContentController.add(try await ContentRuleListCompiler.compileExternalNetworkBlocker())
        return configuration
    }

    @MainActor
    static func waitUntilReady(in webView: WKWebView) async throws {
        _ = try await webView.callDocumentJavaScript("""
        if (!globalThis.__markdownEnhancements?.ready) throw new Error('Offline renderer unavailable');
        let timer;
        try {
            await Promise.race([
                globalThis.__markdownEnhancements.ready,
                new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('Render timeout')), 20000); })
            ]);
        } finally { clearTimeout(timer); }
        return true;
        """, arguments: [:], in: nil, contentWorld: .page)
    }

    static func resourceURL(for url: URL) -> URL? {
        guard url.scheme == "markdown-resource", url.host == "bundle", url.query == nil,
              let path = url.path.removingPercentEncoding,
              !path.contains(".."), !path.contains("\\"), !path.contains("\0"),
              ["js", "css", "woff2"].contains(url.pathExtension.lowercased()),
              let root = Bundle.main.url(forResource: "Markdown", withExtension: nil) else { return nil }
        let file = root.appendingPathComponent(String(path.drop(while: { $0 == "/" })))
            .standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(root.standardizedFileURL.resolvingSymlinksInPath().path + "/") else { return nil }
        return file
    }
}

private final class MarkdownResourceHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard urlSchemeTask.request.httpMethod == nil || urlSchemeTask.request.httpMethod == "GET",
              let url = urlSchemeTask.request.url,
              let file = MarkdownWebResources.resourceURL(for: url),
              let data = try? Data(contentsOf: file) else {
            urlSchemeTask.didFailWithError(URLError(.resourceUnavailable))
            return
        }
        let type: String
        switch file.pathExtension {
        case "js": type = "text/javascript"
        case "css": type = "text/css"
        default: type = "font/woff2"
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": type, "Access-Control-Allow-Origin": "*", "Cache-Control": "public, max-age=31536000"
        ])!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
