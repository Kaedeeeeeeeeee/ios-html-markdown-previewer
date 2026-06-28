import Network
import WebKit
import XCTest
@testable import HTMLMarkdownPreviewer

@MainActor
final class HTMLSecurityTests: XCTestCase {
    func testSafePreviewBlocksExternalHTTPResources() async throws {
        let server = try LocalHTTPProbeServer()
        defer { server.stop() }

        let rootURL = try makeTemporaryDirectory()
        let htmlURL = rootURL.appendingPathComponent("external.html")
        let html = """
        <!doctype html>
        <html>
        <head>
          <link rel="stylesheet" href="\(server.baseURL.absoluteString)/style.css">
        </head>
        <body>
          <img src="\(server.baseURL.absoluteString)/pixel.png" alt="external">
          <p>M0 external resource blocking</p>
        </body>
        </html>
        """
        try html.data(using: .utf8)?.write(to: htmlURL)

        let configuration = try await HTMLPreviewConfiguration.make(mode: .safePreview)
        _ = try await loadFile(htmlURL, readAccessRoot: rootURL, configuration: configuration)

        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(server.requestCount, 0, "Safe preview must not request external http/https resources.")
    }

    func testZIPExtractedHTMLLoadsLocalCSSAndImages() async throws {
        let workURL = try makeTemporaryDirectory()
        let archiveURL = workURL.appendingPathComponent("report.zip")
        try makeArchive(
            at: archiveURL,
            files: [
                "index.html": """
                <!doctype html>
                <html>
                <head>
                  <link rel="stylesheet" href="assets/style.css">
                </head>
                <body>
                  <p id="target">Styled content</p>
                  <img id="preview-image" src="images/pixel.svg" alt="local">
                </body>
                </html>
                """.data(using: .utf8)!,
                "assets/style.css": "#target { color: rgb(1, 2, 3); }".data(using: .utf8)!,
                "images/pixel.svg": """
                <svg xmlns="http://www.w3.org/2000/svg" width="8" height="8">
                  <rect width="8" height="8" fill="red"/>
                </svg>
                """.data(using: .utf8)!
            ]
        )

        let destinationURL = workURL.appendingPathComponent("imported-report", isDirectory: true)
        let result = try ZipImportService().importArchive(from: archiveURL, to: destinationURL)

        let configuration = try await HTMLPreviewConfiguration.make(mode: .safePreview)
        let webView = try await loadFile(result.entryFileURL, readAccessRoot: result.rootURL, configuration: configuration)

        let color = try await webView.evaluateJavaScript(
            "getComputedStyle(document.getElementById('target')).color"
        ) as? String
        let imageWidth = try await webView.evaluateJavaScript(
            "document.getElementById('preview-image').naturalWidth"
        ) as? Int

        XCTAssertEqual(result.entryFileURL.lastPathComponent, "index.html")
        XCTAssertEqual(color, "rgb(1, 2, 3)")
        XCTAssertEqual(imageWidth, 8)
    }

    private func loadFile(
        _ fileURL: URL,
        readAccessRoot: URL,
        configuration: WKWebViewConfiguration
    ) async throws -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let loader = WebViewLoadObserver()
        webView.navigationDelegate = loader
        try await loader.load {
            webView.loadFileURL(fileURL, allowingReadAccessTo: readAccessRoot)
        }
        return webView
    }
}

private final class WebViewLoadObserver: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ action: () -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            action()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

private final class LocalHTTPProbeServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "LocalHTTPProbeServer")
    private let lock = NSLock()
    private var listener: NWListener?
    private var hits = 0

    private var baseURLStorage: URL?

    var baseURL: URL {
        guard let baseURLStorage else {
            preconditionFailure("Server base URL accessed before startup.")
        }
        return baseURLStorage
    }

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return hits
    }

    init() throws {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener

        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.signal()
            case .failed(let error):
                print("LocalHTTPProbeServer failed to start: \(error)")
                ready.signal()
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)

        guard ready.wait(timeout: .now() + 5) == .success else {
            throw TestError.serverDidNotStart
        }

        guard let port = listener.port?.rawValue,
              let baseURL = URL(string: "http://127.0.0.1:\(port)") else {
            throw TestError.serverDidNotStart
        }

        self.baseURLStorage = baseURL
    }

    func stop() {
        listener?.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] _, _, _, _ in
            guard let self else { return }

            lock.lock()
            hits += 1
            lock.unlock()

            let body = "blocked resource should not load"
            let response = """
            HTTP/1.1 200 OK\r
            Content-Type: text/plain\r
            Content-Length: \(body.utf8.count)\r
            Connection: close\r
            \r
            \(body)
            """
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}

private enum TestError: Error {
    case serverDidNotStart
}
