import PDFKit
import UIKit
import WebKit
import XCTest
@testable import HTMLMarkdownPreviewer

@MainActor
final class PackageWebNavigationTests: XCTestCase {
    func testNestedLocalLinksAndScriptNavigationAreHandedToPackageReader() async throws {
        let fixture = try PackageNavigationFixture()
        defer { fixture.remove() }
        let session = try await PackageNavigationSession.make(fixture: fixture)
        defer { session.close() }
        try await session.loadEntry()
        XCTAssertEqual(session.events.finishedURLs.last?.lastPathComponent, "index.html")
        XCTAssertTrue(session.events.pageRequests.isEmpty, "Loading the entry must not create a history entry.")

        _ = try await session.webView.evaluateJavaScript("document.getElementById('details').click()")
        try await waitUntil { session.events.pageRequests.count == 1 }
        XCTAssertEqual(session.events.pageRequests.last?.lastPathComponent, "details.html")
        XCTAssertEqual(session.events.pageRequests.last?.fragment, "results")
        XCTAssertEqual(session.webView.url?.lastPathComponent, "index.html", "The host owns the page switch.")

        _ = try await session.webView.evaluateJavaScript("location.href = 'notes.md'")
        try await waitUntil { session.events.pageRequests.count == 2 }
        XCTAssertEqual(session.events.pageRequests.last?.lastPathComponent, "notes.md")
        XCTAssertEqual(session.webView.url?.lastPathComponent, "index.html")
    }

    func testTargetBlankLocalPageUsesPackageReaderWithoutCreatingAnotherWebView() async throws {
        let fixture = try PackageNavigationFixture()
        defer { fixture.remove() }
        let session = try await PackageNavigationSession.make(fixture: fixture)
        defer { session.close() }
        try await session.loadEntry()
        _ = try await session.webView.evaluateJavaScript("document.getElementById('new-window').click()")
        try await waitUntil { session.events.pageRequests.count == 1 }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(session.events.pageRequests.count, 1, "The navigation and UI delegates must not hand off the same link twice.")
        XCTAssertEqual(session.events.pageRequests.last?.lastPathComponent, "details.html")
        XCTAssertEqual(session.webView.url?.lastPathComponent, "index.html")
    }

    func testSamePageAnchorRemainsNativeAndLocalAssetsAndFramesStillLoad() async throws {
        let fixture = try PackageNavigationFixture()
        defer { fixture.remove() }
        let session = try await PackageNavigationSession.make(fixture: fixture)
        defer { session.close() }
        try await session.loadEntry()
        let color = try await session.webView.evaluateJavaScript("getComputedStyle(document.body).backgroundColor") as? String
        XCTAssertEqual(color, "rgb(12, 34, 56)")
        // File URLs may have distinct opaque origins, so inspecting
        // iframe.contentDocument would violate WebKit's same-origin policy.
        // A postMessage from the fixture proves its local frame really loaded.
        let frameText = try await session.webView.callDocumentJavaScript("""
        if (window.receivedFrameText) return window.receivedFrameText;
        return await new Promise((resolve, reject) => {
            const timer = setTimeout(() => reject(new Error('Local frame did not finish')), 2000);
            window.addEventListener('message', event => { clearTimeout(timer); resolve(event.data); }, {once: true});
        });
        """, contentWorld: .page) as? String
        XCTAssertTrue(frameText?.contains("Local frame") == true)
        XCTAssertTrue(session.events.pageRequests.isEmpty, "Subframes must not switch the package's active page.")

        _ = try await session.webView.evaluateJavaScript("document.getElementById('anchor').click()")
        try await waitUntil { session.webView.url?.fragment == "bottom" }
        // WebKit updates the URL before committing the anchor's scroll.
        try await waitUntil { session.webView.scrollView.contentOffset.y > 500 }
        XCTAssertTrue(session.events.pageRequests.isEmpty)
        let top = try await session.webView.evaluateJavaScript("window.scrollY") as? Double
        XCTAssertGreaterThan(top ?? 0, 500)
    }

    func testNavigationBoundaryRejectsSiblingTraversalSymlinksAndExternalSchemes() throws {
        let fixture = try PackageNavigationFixture()
        defer { fixture.remove() }
        let policy = WebNavigationPolicy(mode: .interactive, entryURL: fixture.entry, readAccessRootURL: fixture.root)
        XCTAssertTrue(policy.permitsLocalNavigation(to: fixture.details))
        XCTAssertTrue(policy.permitsLocalNavigation(to: fixture.entry.appending(fragment: "bottom")))
        XCTAssertFalse(policy.permitsLocalNavigation(to: fixture.outside))
        XCTAssertFalse(policy.permitsLocalNavigation(to: fixture.root.appendingPathComponent("../outside/secret.html")))
        XCTAssertFalse(policy.permitsLocalNavigation(to: fixture.root.appendingPathComponent("escape.html")))
        XCTAssertFalse(policy.permitsLocalNavigation(to: fixture.root.appendingPathComponent("escape-directory/secret.html")))
        XCTAssertFalse(policy.permitsLocalNavigation(to: URL(fileURLWithPath: fixture.root.path + "-sibling/details.html")))
        XCTAssertFalse(policy.permitsLocalNavigation(to: URL(string: "file://example.com" + fixture.entry.path)!))
        for address in ["https://example.com", "http://127.0.0.1", "javascript:alert(1)", "data:text/html,hello", "mailto:test@example.com", "about:blank"] {
            XCTAssertFalse(policy.permitsLocalNavigation(to: URL(string: address)!))
        }
    }

    func testFormsExternalLinksAndEscapingFilesDoNotNavigateOrEnterHistory() async throws {
        let fixture = try PackageNavigationFixture()
        defer { fixture.remove() }
        let session = try await PackageNavigationSession.make(fixture: fixture)
        defer { session.close() }
        try await session.loadEntry()
        for script in [
            "document.getElementById('external').click()",
            "document.getElementById('escape').click()",
            "document.getElementById('form').submit()"
        ] {
            _ = try await session.webView.evaluateJavaScript(script)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(session.webView.url?.lastPathComponent, "index.html")
            XCTAssertTrue(session.events.pageRequests.isEmpty)
        }
        XCTAssertEqual(session.events.finishedURLs.count, 1)
    }

    func testPackageRejectsUnsupportedAndUnlistedTopLevelTargetsIncludingNewWindows() async throws {
        let fixture = try PackageNavigationFixture()
        defer { fixture.remove() }
        let session = try await PackageNavigationSession.make(fixture: fixture, rejectedPageNames: [".hidden.html"])
        defer { session.close() }
        try await session.loadEntry()
        for id in ["text-file", "svg-file", "svg-new-window", "hidden-page", "hidden-new-window"] {
            _ = try await session.webView.callDocumentJavaScript(
                "document.getElementById(id).click(); return null;", arguments: ["id": id], contentWorld: .page
            )
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(session.webView.url?.lastPathComponent, "index.html", "Rejected target \(id) must not replace the active package page.")
            XCTAssertEqual(session.events.finishedURLs.count, 1)
        }
        XCTAssertEqual(session.events.pageRequests.map(\.lastPathComponent), [".hidden.html", ".hidden.html"],
                       "Assets never enter the page catalog, and a rejected target=_blank request is offered only once.")
    }

    func testSingleFilePreviewStillNavigatesLocallyAndExportsTheCurrentPage() async throws {
        let fixture = try PackageNavigationFixture()
        defer { fixture.remove() }
        let session = try await PackageNavigationSession.make(fixture: fixture, handOffPages: false)
        defer { session.close() }
        try await session.loadEntry()
        _ = try await session.webView.evaluateJavaScript("document.getElementById('new-window').click()")
        try await waitUntil { session.events.finishedURLs.last?.lastPathComponent == "details.html" }
        XCTAssertEqual(session.webView.url?.lastPathComponent, "details.html")
        let pdfURL = try await PDFExportService().export(webView: session.webView, title: "Package details")
        defer { try? FileManager.default.removeItem(at: pdfURL) }
        let pdf = try XCTUnwrap(PDFDocument(url: pdfURL))
        XCTAssertTrue(pdf.string?.contains("Active package details") == true)
        XCTAssertFalse(pdf.string?.contains("Package entry sentinel") == true)
    }

    func testSafeModeLocalPageLinkDoesNotEnableDocumentScripts() async throws {
        let fixture = try PackageNavigationFixture()
        defer { fixture.remove() }
        let session = try await PackageNavigationSession.make(fixture: fixture, mode: .safePreview)
        defer { session.close() }
        try await session.loadEntry()
        XCTAssertFalse(session.webView.configuration.defaultWebpagePreferences.allowsContentJavaScript)
        let scriptResult = try await session.webView.evaluateJavaScript("document.getElementById('script-result').textContent") as? String
        XCTAssertEqual(scriptResult, "not executed")
        _ = try await session.webView.evaluateJavaScript("document.getElementById('details').click()")
        try await waitUntil { session.events.pageRequests.count == 1 }
        XCTAssertEqual(session.events.pageRequests.last?.lastPathComponent, "details.html")
        XCTAssertFalse(session.webView.configuration.defaultWebpagePreferences.allowsContentJavaScript)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw PackageNavigationError.timedOut }
            try await Task.sleep(for: .milliseconds(30))
        }
    }
}

private struct PackageNavigationFixture {
    let directory: URL
    let root: URL
    let entry: URL
    let details: URL
    let outside: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("PackageNavigation-" + UUID().uuidString, isDirectory: true)
        root = directory.appendingPathComponent("report", isDirectory: true)
        let nested = root.appendingPathComponent("chapters", isDirectory: true)
        let outsideDirectory = directory.appendingPathComponent("outside", isDirectory: true)
        entry = root.appendingPathComponent("index.html")
        details = nested.appendingPathComponent("details.html")
        outside = outsideDirectory.appendingPathComponent("secret.html")
        for folder in [nested, outsideDirectory] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try "<h1>Outside</h1>".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape.html"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape-directory"), withDestinationURL: outsideDirectory)
        try "body { background-color: rgb(12, 34, 56); }".write(to: root.appendingPathComponent("style.css"), atomically: true, encoding: .utf8)
        try "# Local notes".write(to: root.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        try "Plain text must not replace the package page.".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try "<svg xmlns='http://www.w3.org/2000/svg'><text x='10' y='20'>Asset</text></svg>".write(to: root.appendingPathComponent("asset.svg"), atomically: true, encoding: .utf8)
        try Self.html("<h1>Hidden page outside the catalog</h1>").write(to: root.appendingPathComponent(".hidden.html"), atomically: true, encoding: .utf8)
        try "<html><body>Local frame<script>parent.postMessage('Local frame loaded', '*');</script></body></html>"
            .write(to: root.appendingPathComponent("frame.html"), atomically: true, encoding: .utf8)
        try Self.html("<h1>Active package details</h1><h2 id='results'>Results</h2><p>Current page PDF sentinel</p>")
            .write(to: details, atomically: true, encoding: .utf8)
        try Self.html("""
        <link rel="stylesheet" href="style.css">
        <h1>Package entry sentinel</h1>
        <p id="script-result">not executed</p>
        <script>document.getElementById('script-result').textContent = 'executed'; window.addEventListener('message', event => { window.receivedFrameText = event.data; });</script>
        <a id="details" href="chapters/details.html#results">Details</a>
        <a id="new-window" href="chapters/details.html" target="_blank">New window</a>
        <a id="anchor" href="#bottom">Bottom</a>
        <a id="external" href="https://example.invalid">External</a>
        <a id="escape" href="escape.html">Outside root</a>
        <a id="text-file" href="notes.txt">Text asset</a>
        <a id="svg-file" href="asset.svg">SVG asset</a>
        <a id="svg-new-window" href="asset.svg" target="_blank">SVG new window</a>
        <a id="hidden-page" href=".hidden.html">Hidden page</a>
        <a id="hidden-new-window" href=".hidden.html" target="_blank">Hidden new window</a>
        <form id="form" action="chapters/details.html"><input name="q" value="test"></form>
        <iframe src="frame.html"></iframe>
        <div style="height:1800px"></div><h2 id="bottom">Bottom anchor</h2>
        """).write(to: entry, atomically: true, encoding: .utf8)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }

    private static func html(_ body: String) -> String {
        "<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1'></head><body>\(body)</body></html>"
    }
}

@MainActor
private final class PackageNavigationEvents {
    var pageRequests: [URL] = []
    var finishedURLs: [URL] = []
}

@MainActor
private final class PackageNavigationSession {
    let webView: WKWebView
    let events: PackageNavigationEvents
    private let fixture: PackageNavigationFixture
    private let policy: WebNavigationPolicy
    private let window: UIWindow
    private weak var previousKeyWindow: UIWindow?

    static func make(fixture: PackageNavigationFixture, mode: HTMLPreviewMode = .interactive, handOffPages: Bool = true,
                     rejectedPageNames: Set<String> = []) async throws -> PackageNavigationSession {
        let configuration = try await HTMLPreviewConfiguration.make(mode: mode)
        // Programmatic clicks stand in for a real tap; this is only a test
        // setting. Production continues to block script-created popups.
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        return try PackageNavigationSession(fixture: fixture, mode: mode, handOffPages: handOffPages,
                                            rejectedPageNames: rejectedPageNames, configuration: configuration)
    }

    private init(fixture: PackageNavigationFixture, mode: HTMLPreviewMode, handOffPages: Bool,
                 rejectedPageNames: Set<String>, configuration: WKWebViewConfiguration) throws {
        self.fixture = fixture
        let events = PackageNavigationEvents()
        self.events = events
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), configuration: configuration)
        policy = WebNavigationPolicy(
            mode: mode, entryURL: fixture.entry, readAccessRootURL: fixture.root,
            onLocalPageNavigation: handOffPages ? { url in
                events.pageRequests.append(url)
                return !rejectedPageNames.contains(url.lastPathComponent)
            } : nil,
            onPageFinished: { events.finishedURLs.append($0) }
        )
        window = UIWindow(windowScene: scene)
        previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        window.frame = scene.coordinateSpace.bounds
        let host = UIViewController()
        host.view.addSubview(webView)
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
        webView.navigationDelegate = policy
        webView.uiDelegate = policy
    }

    func loadEntry() async throws {
        webView.loadFileURL(fixture.entry, allowingReadAccessTo: fixture.root)
        let deadline = ContinuousClock.now + .seconds(15)
        while events.finishedURLs.isEmpty {
            guard ContinuousClock.now < deadline else { throw PackageNavigationError.timedOut }
            try await Task.sleep(for: .milliseconds(30))
        }
    }

    func close() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        window.isHidden = true
        previousKeyWindow?.makeKey()
    }
}

private enum PackageNavigationError: Error { case timedOut }

private extension URL {
    func appending(fragment: String) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        components.fragment = fragment
        return components.url!
    }
}
