import Network
import PDFKit
import UIKit
import WebKit
import XCTest
@testable import HTMLMarkdownPreviewer

@MainActor
final class HTMLReadingTests: XCTestCase {
    func testDocumentJavaScriptPreservesPromisesArgumentsErrorsAndIsolatedWorld() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("javascript.html")
        try fixture("<h1>JavaScript bridge</h1>").write(to: url, atomically: true, encoding: .utf8)
        let session = try await ReadingTestSession(entryURL: url)
        defer { session.close() }
        try await session.load(url)

        let value = try await session.webView.callDocumentJavaScript(
            "globalThis.__bridgeProbe = input; return await Promise.resolve(input.value + 1);",
            arguments: ["input": ["value": 41]], contentWorld: HTMLReadingController.contentWorld
        )
        XCTAssertEqual(value as? Int, 42)
        let pageGlobal = try await session.webView.evaluateJavaScript("typeof globalThis.__bridgeProbe")
        XCTAssertEqual(pageGlobal as? String, "undefined")
        let undefined = try await session.webView.callDocumentJavaScript(
            "return undefined;", contentWorld: HTMLReadingController.contentWorld
        )
        XCTAssertNil(undefined)

        do {
            _ = try await session.webView.callDocumentJavaScript(
                "return Promise.reject(new Error('expected failure'));",
                contentWorld: HTMLReadingController.contentWorld
            )
            XCTFail("A rejected JavaScript promise must propagate its error.")
        } catch {
            XCTAssertEqual((error as NSError).domain, WKError.errorDomain)
        }
    }

    func testSafePreviewSearchAndOutlineDoNotEnablePageScriptsOrExternalResources() async throws {
        let server = try ReadingHTTPProbe()
        defer { server.stop() }
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("safe.html")
        try fixture("""
        <h1>Reading notes</h1>
        <h2 style="display:none">Hidden heading</h2>
        <h2>Chapter <em>one</em></h2>
        <h2>Chapter one</h2>
        <p id="text">Quiet <strong>morning</strong> and quiet morning.</p>
        <p hidden>quiet morning</p>
        <p aria-hidden="true">quiet morning</p>
        <p style="visibility:hidden">quiet morning</p>
        <p id="script-result">before</p>
        <p>a+b and a+b</p>
        <script>document.getElementById('script-result').textContent = 'executed';</script>
        <img src="\(server.baseURL)/pixel.png" onerror="document.getElementById('script-result').textContent = 'event executed'">
        <link rel="stylesheet" href="\(server.baseURL)/style.css">
        """).write(to: url, atomically: true, encoding: .utf8)
        let session = try await ReadingTestSession(entryURL: url)
        defer { session.close() }
        try await session.load(url)

        XCTAssertFalse(session.webView.configuration.defaultWebpagePreferences.allowsContentJavaScript)
        XCTAssertEqual(session.state.headings.map(\.title), ["Reading notes", "Chapter one", "Chapter one"])
        XCTAssertEqual(Set(session.state.headings.map(\.id)).count, 3)
        let originalBody = try await session.webView.evaluateJavaScript("document.body.innerHTML") as? String
        session.state.query = "quiet morning"
        session.reader.synchronize()
        try await waitUntil { session.state.matchCount == 2 }
        XCTAssertEqual(session.state.selectedMatch, 0)
        let unchangedBody = try await session.webView.evaluateJavaScript("document.body.innerHTML") as? String
        XCTAssertEqual(unchangedBody, originalBody, "Finding text must not wrap or replace document text nodes.")
        let pageResult = try await session.webView.evaluateJavaScript("document.getElementById('script-result').textContent") as? String
        let pageGlobal = try await session.webView.evaluateJavaScript("typeof globalThis.__htmlPreviewReading") as? String
        XCTAssertEqual(pageResult, "before")
        XCTAssertEqual(pageGlobal, "undefined", "Reading globals must not be exposed to page-world scripts.")
        let highlightVisible = try await session.webView.callDocumentJavaScript(
            "return globalThis.CSS?.highlights?.get('html-previewer-reading-matches')?.size === 2 || !!document.querySelector('[data-html-previewer-reading-overlay]');",
            arguments: [:], in: nil, contentWorld: HTMLReadingController.contentWorld
        ) as? Bool
        XCTAssertEqual(highlightVisible, true)

        // Treat regex metacharacters as literal user input.
        session.state.query = "a+b"
        session.reader.synchronize()
        try await waitUntil { session.state.matchCount == 2 && session.state.selectedMatch == 0 }
        let selectedText = try await session.webView.callDocumentJavaScript(
            "const highlight = globalThis.CSS?.highlights?.get('html-previewer-reading-current'); return highlight ? Array.from(highlight)[0].toString() : null;",
            arguments: [:], in: nil, contentWorld: HTMLReadingController.contentWorld
        ) as? String
        if let selectedText { XCTAssertEqual(selectedText, "a+b") }
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(server.requestCount, 0)
        XCTAssertFalse(session.webView.configuration.defaultWebpagePreferences.allowsContentJavaScript)
    }

    func testRestoresScrollPositionAndUpdatesItAfterScrollAndOutlineNavigation() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("long.html")
        try longFixture().write(to: url, atomically: true, encoding: .utf8)
        let session = try await ReadingTestSession(entryURL: url, position: ReadingPosition(progress: 0.55))
        defer { session.close() }
        try await session.load(url)
        let initialProgress = session.state.position?.progress ?? -1
        XCTAssertEqual(initialProgress, 0.55, accuracy: 0.015)

        let target = try XCTUnwrap(session.state.headings.last)
        session.state.navigate(to: .heading(target.id))
        session.reader.synchronize()
        try await waitUntil { (session.state.position?.progress ?? 0) > 0.85 }
        XCTAssertEqual(session.state.position?.anchorID, target.id)

        session.state.navigate(to: .beginning)
        session.reader.synchronize()
        try await waitUntil { (session.state.position?.progress ?? 1) < 0.01 }
        _ = try await session.webView.evaluateJavaScript("window.scrollTo(0, (document.scrollingElement.scrollHeight - document.scrollingElement.clientHeight) * .3)")
        try await waitUntil { abs((session.state.position?.progress ?? 0) - 0.3) < 0.015 }
        XCTAssertNotNil(session.state.position?.anchorID)

        session.state.query = "reading target"
        session.reader.synchronize()
        try await waitUntil { session.state.matchCount == 10 }
        session.state.navigate(to: .match(8))
        session.reader.synchronize()
        try await waitUntil { session.state.selectedMatch == 8 && (session.state.position?.progress ?? 0) > 0.7 }
        let saved = try XCTUnwrap(session.state.position)
        // Reapplying an active query on reload must not jump back to the first hit.
        try await session.load(url)
        try await waitUntil { session.state.matchCount == 10 }
        XCTAssertEqual(session.state.position?.progress ?? -1, saved.progress, accuracy: 0.015)
        session.reader.detach()
        XCTAssertFalse(session.state.isReady)
        XCTAssertEqual(session.state.position?.progress ?? -1, saved.progress, accuracy: 0.02)
        let cleaned = try await session.webView.callDocumentJavaScript(
            "return !document.querySelector('[data-html-previewer-reading-overlay]') && !(globalThis.CSS?.highlights?.has('html-previewer-reading-matches'));",
            arguments: [:], in: nil, contentWorld: HTMLReadingController.contentWorld
        ) as? Bool
        XCTAssertEqual(cleaned, true)
    }

    func testLatestSearchWinsAndClearingSearchRemovesResults() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("search.html")
        try fixture("<h1>Search</h1><p>First first first.</p><p>Second.</p>")
            .write(to: url, atomically: true, encoding: .utf8)
        let session = try await ReadingTestSession(entryURL: url)
        defer { session.close() }
        try await session.load(url)
        session.state.query = "First"
        session.reader.synchronize()
        session.state.query = "Second"
        session.reader.synchronize()
        try await waitUntil { session.state.matchCount == 1 && session.state.selectedMatch == 0 }
        session.state.query = ""
        session.reader.synchronize()
        try await waitUntil { session.state.matchCount == 0 && session.state.selectedMatch == -1 }
        let removed = try await session.webView.callDocumentJavaScript(
            "return !(globalThis.CSS?.highlights?.has('html-previewer-reading-matches')) && !document.querySelector('[data-html-previewer-reading-overlay]');",
            arguments: [:], in: nil, contentWorld: HTMLReadingController.contentWorld
        ) as? Bool
        XCTAssertEqual(removed, true)
    }

    func testAnotherLocalPageDoesNotOverwriteTheEntryPagePosition() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let entry = directory.appendingPathComponent("index.html")
        let other = directory.appendingPathComponent("appendix.html")
        try longFixture().write(to: entry, atomically: true, encoding: .utf8)
        try fixture("<h1>Appendix</h1><div style='height:2500px'>other text</div><h2>End</h2>")
            .write(to: other, atomically: true, encoding: .utf8)
        let session = try await ReadingTestSession(entryURL: entry, position: ReadingPosition(progress: 0.4))
        defer { session.close() }
        try await session.load(entry)
        let saved = try XCTUnwrap(session.state.position)
        try await session.load(other)
        XCTAssertEqual(session.state.headings.map(\.title), ["Appendix", "End"])
        session.state.query = "other text"
        session.reader.synchronize()
        try await waitUntil { session.state.matchCount == 1 }
        XCTAssertEqual(session.state.position, saved)
        session.state.query = ""
        session.reader.synchronize()
        try await session.load(entry)
        XCTAssertEqual(session.state.position?.progress ?? -1, saved.progress, accuracy: 0.015)
        XCTAssertEqual(session.state.headings.count, 10)
    }

    func testNestedVerticalAndHorizontalScrollingRevealsMatchAndRestoresPosition() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("nested.html")
        try fixture("""
        <style>
        html, body { margin: 0; height: 100%; overflow: hidden; }
        header { position: fixed; inset: 0 0 auto; height: 64px; background: white; z-index: 5; }
        main { height: 100vh; overflow: auto; }
        #table-scroll { width: 240px; overflow: auto; }
        table { width: 1400px; table-layout: fixed; border-collapse: collapse; }
        td { height: 90px; padding: 0; }
        </style>
        <header id="fixed-header">Fixed document toolbar</header>
        <main id="main-scroll">
          <h1>Nested report</h1><div style="height: 1000px"></div>
          <h2>Table chapter</h2>
          <div id="table-scroll"><table><tr>
            <td style="width: 1100px">First column</td>
            <td><span id="needle">horizontal needle</span></td>
          </tr></table></div>
          <div style="height: 1400px"></div><h2>Final chapter</h2>
        </main>
        """).write(to: url, atomically: true, encoding: .utf8)
        let session = try await ReadingTestSession(entryURL: url)
        defer { session.close() }
        try await session.load(url)
        session.state.query = "horizontal needle"
        session.reader.synchronize()
        try await waitUntil { session.state.matchCount == 1 }

        let geometryScript = """
        (() => {
            const main = document.getElementById('main-scroll');
            const table = document.getElementById('table-scroll');
            const box = table.getBoundingClientRect();
            const range = document.createRange();
            range.selectNodeContents(document.getElementById('needle'));
            const text = range.getBoundingClientRect();
            return { mainTop: main.scrollTop, tableLeft: table.scrollLeft,
                textLeft: text.left, textRight: text.right, textTop: text.top, textBottom: text.bottom,
                containerLeft: box.left + table.clientLeft,
                containerRight: box.left + table.clientLeft + table.clientWidth,
                headerBottom: document.getElementById('fixed-header').getBoundingClientRect().bottom,
                viewportBottom: innerHeight, windowTop: scrollY };
        })()
        """
        let beforeValue = try await session.webView.evaluateJavaScript(geometryScript)
        let before = try XCTUnwrap(beforeValue as? [String: Double])
        XCTAssertGreaterThan(before["mainTop"] ?? 0, 300)
        XCTAssertGreaterThan(before["tableLeft"] ?? 0, 500)
        XCTAssertGreaterThanOrEqual(before["textLeft"] ?? -1, (before["containerLeft"] ?? 0) - 1)
        XCTAssertLessThanOrEqual(before["textRight"] ?? .infinity, (before["containerRight"] ?? 0) + 1)
        XCTAssertGreaterThanOrEqual(before["textTop"] ?? -1, before["headerBottom"] ?? 0)
        XCTAssertLessThanOrEqual(before["textBottom"] ?? .infinity, before["viewportBottom"] ?? 0)
        XCTAssertEqual(before["windowTop"] ?? -1, 0, accuracy: 1)
        let saved = try XCTUnwrap(session.state.position)
        XCTAssertEqual(saved.progress, 0, accuracy: 0.01)
        session.close()

        let restored = try await ReadingTestSession(entryURL: url, position: saved)
        defer { restored.close() }
        try await restored.load(url)
        let afterValue = try await restored.webView.evaluateJavaScript(geometryScript)
        let after = try XCTUnwrap(afterValue as? [String: Double])
        XCTAssertEqual(after["mainTop"] ?? -1, before["mainTop"] ?? -2, accuracy: 2)
        XCTAssertEqual(after["tableLeft"] ?? -1, before["tableLeft"] ?? -2, accuracy: 2)

        let priorAnchor = restored.state.position?.anchorID
        _ = try await restored.webView.evaluateJavaScript("document.getElementById('main-scroll').scrollTop += 100")
        try await waitUntil { restored.state.position?.anchorID != priorAnchor }
        restored.state.navigate(to: .beginning)
        restored.reader.synchronize()
        let beginningValue = try await restored.webView.evaluateJavaScript(geometryScript)
        let beginning = try XCTUnwrap(beginningValue as? [String: Double])
        XCTAssertEqual(beginning["mainTop"] ?? -1, 0, accuracy: 1)
        XCTAssertEqual(beginning["tableLeft"] ?? -1, 0, accuracy: 1)
    }

    func testVisibleLineBreaksFormSearchBoundariesWithoutChangingTextNodes() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("line-break.html")
        try fixture("<p>receipt<br>number</p><p>receipt<span> number</span></p><p>joined<br hidden>word</p>")
            .write(to: url, atomically: true, encoding: .utf8)
        let session = try await ReadingTestSession(entryURL: url)
        defer { session.close() }
        try await session.load(url)
        session.state.query = "receipt number"
        session.reader.synchronize()
        try await waitUntil { session.state.matchCount == 2 }
        session.state.query = "receiptnumber"
        session.reader.synchronize()
        let count = try await session.webView.callDocumentJavaScript(
            "return globalThis.__htmlPreviewReading.snapshot().matchCount;",
            arguments: [:], in: nil, contentWorld: HTMLReadingController.contentWorld
        ) as? Int
        XCTAssertEqual(count, 0)
        session.state.query = "joinedword"
        session.reader.synchronize()
        try await waitUntil { session.state.matchCount == 1 }
        let unchanged = try await session.webView.evaluateJavaScript("document.querySelectorAll('br').length") as? Int
        XCTAssertEqual(unchanged, 2)
    }

    func testPDFExportTemporarilySuspendsActiveSearchHighlightsAndRestoresThem() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("print.html")
        try fixture("<h1>Export test</h1><p style='color: blue'>export needle</p>")
            .write(to: url, atomically: true, encoding: .utf8)
        let session = try await ReadingTestSession(entryURL: url)
        defer { session.close() }
        try await session.load(url)
        session.state.query = "export needle"
        session.reader.synchronize()
        try await waitUntil { session.state.matchCount == 1 }
        _ = try await session.webView.callDocumentJavaScript(
            """
            const reader = globalThis.__htmlPreviewReading;
            const highlighted = () => !!globalThis.CSS?.highlights?.has('html-previewer-reading-current') ||
                !!document.querySelector('[data-html-previewer-reading-overlay]');
            globalThis.__readingPrintEvents = [];
            const suspend = reader.suspendHighlights;
            const resume = reader.resumeHighlights;
            reader.suspendHighlights = () => {
                suspend();
                globalThis.__readingPrintEvents.push({ event: 'suspend', highlighted: highlighted() });
            };
            reader.resumeHighlights = () => {
                resume();
                globalThis.__readingPrintEvents.push({ event: 'resume', highlighted: highlighted() });
            };
            return null;
            """, arguments: [:], in: nil, contentWorld: HTMLReadingController.contentWorld
        )
        let data = try await PDFExportService().pdfData(webView: session.webView, title: "Search export")
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertTrue(pdf.string?.contains("export needle") == true)
        let eventsValue = try await session.webView.callDocumentJavaScript(
            "return globalThis.__readingPrintEvents;", arguments: [:],
            in: nil, contentWorld: HTMLReadingController.contentWorld
        )
        let events = try XCTUnwrap(eventsValue as? [[String: Any]])
        XCTAssertEqual(events.compactMap { $0["event"] as? String }, ["suspend", "resume"])
        XCTAssertEqual(events.compactMap { $0["highlighted"] as? Bool }, [false, true])
        XCTAssertEqual(session.state.matchCount, 1)
        XCTAssertEqual(session.state.selectedMatch, 0)
    }

    private func fixture(_ body: String) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>body { margin: 16px; font: 18px sans-serif; } h1, h2 { margin: 0 0 16px; }</style>
        </head><body>\(body)</body></html>
        """
    }

    private func longFixture() -> String {
        fixture((0..<10).map { index in
            "<section style='height:700px'><h2>Chapter \(index)</h2><p>reading target \(index)</p></section>"
        }.joined())
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw ReadingTestError.timedOut }
            try await Task.sleep(for: .milliseconds(30))
        }
    }
}

@MainActor
private final class ReadingTestSession: NSObject, WKNavigationDelegate {
    let state: DocumentReadingState
    let webView: WKWebView
    let reader: HTMLReadingController
    private let window: UIWindow
    private weak var previousKeyWindow: UIWindow?
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?

    init(entryURL: URL, position: ReadingPosition? = nil) async throws {
        state = DocumentReadingState(position: position)
        let configuration = try await HTMLPreviewConfiguration.make(mode: .safePreview)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }, "Reading tests require an active host scene.")
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), configuration: configuration)
        reader = HTMLReadingController(state: state, entryURL: entryURL)
        window = UIWindow(windowScene: scene)
        previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        super.init()
        window.frame = scene.coordinateSpace.bounds
        let host = UIViewController()
        host.view.addSubview(webView)
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
        webView.layoutIfNeeded()
        XCTAssertTrue(window.isKeyWindow)
        XCTAssertTrue(webView.window?.windowScene === scene)
        webView.navigationDelegate = self
        reader.attach(to: webView)
    }

    func load(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            timeout = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(15))
                    self?.finish(.failure(ReadingTestError.timedOut))
                } catch {}
            }
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        let deadline = ContinuousClock.now + .seconds(10)
        while !state.isReady {
            guard ContinuousClock.now < deadline else { throw ReadingTestError.timedOut }
            try await Task.sleep(for: .milliseconds(30))
        }
    }

    func close() {
        timeout?.cancel()
        reader.detach()
        webView.stopLoading()
        webView.navigationDelegate = nil
        window.isHidden = true
        previousKeyWindow?.makeKey()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        reader.navigationDidStart()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        reader.navigationDidFinish(in: webView)
        finish(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<Void, Error>) {
        timeout?.cancel()
        timeout = nil
        continuation?.resume(with: result)
        continuation = nil
    }
}

private enum ReadingTestError: Error {
    case timedOut
    case serverDidNotStart
}

private final class ReadingHTTPProbe: @unchecked Sendable {
    private let queue = DispatchQueue(label: "HTMLReadingTests.HTTP")
    private let lock = NSLock()
    private let listener: NWListener
    private var hits = 0
    let baseURL: String

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return hits
    }

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed: ready.signal()
            default: break
            }
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port else {
            listener.cancel()
            throw ReadingTestError.serverDidNotStart
        }
        baseURL = "http://127.0.0.1:\(port.rawValue)"
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: self?.queue ?? .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] _, _, _, _ in
                guard let self else { connection.cancel(); return }
                self.lock.lock()
                self.hits += 1
                self.lock.unlock()
                let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }

    func stop() {
        listener.cancel()
    }
}
