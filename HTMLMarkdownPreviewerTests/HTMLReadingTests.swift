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
        try await waitForRestoredProgress(0.4, session: session)
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
        // Installation readiness and the UI-process scroll transaction are
        // separate. Require the saved model and both actual viewport positions
        // to settle before checking that the appendix did not overwrite them.
        try await waitForRestoredProgress(saved.progress, session: session)
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

    func testMarkdownAtomicSearchUsesSourceOnceAndIgnoresReaderControls() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("markdown-atomic.html")
        try fixture("""
        <section data-markdown-block="markdown-block-0"><h1 id="markdown-block-0" data-reading-heading-id="markdown-block-0">Math notes</h1></section>
        <section data-markdown-block="markdown-block-1">
          <p>Before the expression. Café notes.</p>
          <span id="formula" data-reading-atomic data-reading-text="x^2 + x" style="display:inline-block;padding:12px">
            <span aria-hidden="true">x^2 + x</span><span style="position:absolute;clip:rect(1px,1px,1px,1px)">x^2 + x</span>
          </span>
          <button data-reading-ignore>Copy code</button>
          <pre><code><span>let </span><span>answer</span> = 42</code></pre>
        </section>
        <section data-markdown-block="markdown-block-2"><h2 data-reading-heading-id="markdown-block-2-child-0">Repeated title</h2></section>
        <section data-markdown-block="markdown-block-3"><h2 data-reading-heading-id="markdown-block-3-child-0">Repeated title</h2></section>
        """).write(to: url, atomically: true, encoding: .utf8)
        let session = try await ReadingTestSession(entryURL: url, documentKind: .markdown)
        defer { session.close() }
        try await session.load(url)
        XCTAssertEqual(session.state.headings.map(\.id), ["markdown-block-0", "markdown-block-2-child-0", "markdown-block-3-child-0"])
        let encoding = try await session.webView.evaluateJavaScript("document.characterSet") as? String
        let accentedText = try await session.webView.evaluateJavaScript("document.querySelector('p').textContent") as? String
        XCTAssertEqual(encoding, "UTF-8", "The local test HTML must use the same explicit UTF-8 charset as generated Markdown pages.")
        XCTAssertEqual(accentedText, "Before the expression. Café notes.", "The diacritic search fixture must not be decoded as mojibake.")
        try await assertMarkdownSearch("x^2", count: 1, session: session)
        let outlined = try await session.webView.evaluateJavaScript("""
        (() => {
            const formula = document.getElementById('formula').getBoundingClientRect();
            const border = document.querySelector('[data-html-previewer-reading-overlay] > div')?.getBoundingClientRect();
            return !!border && Math.abs(border.width - formula.width) < 1 && Math.abs(border.height - formula.height) < 1;
        })()
        """) as? Bool
        XCTAssertEqual(outlined, true, "Canonical math matches should reveal and outline the complete visible formula.")
        try await assertMarkdownSearch("cafe", count: 1, session: session)
        try await assertMarkdownSearch("Copy code", count: 0, session: session)
        try await assertMarkdownSearch("let answer", count: 1, session: session)
        let source = try await session.webView.evaluateJavaScript("document.querySelector('code').textContent") as? String
        XCTAssertEqual(source, "let answer = 42", "Search must preserve the exact highlighted code for copying.")
        let overlayRemoved = try await session.webView.evaluateJavaScript("!document.querySelector('[data-html-previewer-reading-overlay]')") as? Bool
        if #available(iOS 17.2, *) { XCTAssertEqual(overlayRemoved, true) }
    }

    func testMarkdownSearchSpansInlineFormulaBoundariesWithoutInventingWhitespace() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("markdown-inline-search.html")
        func formula(_ source: String) -> String {
            "<span class=\"math\" data-math-display=\"false\" data-reading-atomic data-reading-text=\"\(source)\"><span aria-hidden=\"true\">\(source)</span><span style=\"position:absolute;width:1px;height:1px;overflow:hidden\">\(source)</span></span>"
        }
        try fixture("""
        <div data-markdown-block="markdown-block-0"><h1>Inline mathematics</h1></div>
        <div data-markdown-block="markdown-block-1"><p id="spaced">Measure \(formula("x")) now.</p></div>
        <div data-markdown-block="markdown-block-2"><p id="compact">a\(formula("x"))b</p></div>
        <div data-markdown-block="markdown-block-3"><p id="several">Start \(formula("x")) plus \(formula("y")) end</p></div>
        """).write(to: url, atomically: true, encoding: .utf8)
        let session = try await ReadingTestSession(entryURL: url, documentKind: .markdown)
        defer { session.close() }
        try await session.load(url)
        let originalBody = try await session.webView.evaluateJavaScript("document.body.innerHTML") as? String
        for query in ["Measure x", "x now", "Measure x now", "axb", "Start x plus y end"] {
            try await assertMarkdownSearch(query, count: 1, session: session)
            let outlined = try await session.webView.evaluateJavaScript("""
            (() => {
                const parts = Array.from(document.querySelectorAll('[data-html-previewer-reading-overlay] > div'));
                return parts.length >= 2 && parts.every(part => {
                    const rect = part.getBoundingClientRect(); return rect.width > 0 && rect.height > 0;
                });
            })()
            """) as? Bool
            XCTAssertEqual(outlined, true, "The mixed phrase \(query) must visibly highlight both its text and formula.")
        }
        try await assertMarkdownSearch("x", count: 3, session: session)
        try await assertMarkdownSearch("a x b", count: 0, session: session)
        let unchangedBody = try await session.webView.evaluateJavaScript("document.body.innerHTML") as? String
        XCTAssertEqual(unchangedBody, originalBody, "Cross-formula search must not change the rendered math or surrounding text.")
    }

    private func assertMarkdownSearch(_ query: String, count: Int, session: ReadingTestSession,
                                      file: StaticString = #filePath, line: UInt = #line) async throws {
        session.state.query = query
        session.reader.synchronize()
        // Flush this request through the same isolated world before checking a
        // zero-result query; resetting the Swift count is not completion proof.
        let value = try await session.webView.callDocumentJavaScript(
            "return globalThis.__htmlPreviewReading.snapshot();", contentWorld: HTMLReadingController.contentWorld
        )
        let deadline = ContinuousClock.now + .seconds(10)
        while session.state.matchCount != count || session.state.selectedMatch != (count > 0 ? 0 : -1) {
            guard ContinuousClock.now < deadline else {
                let current = try? await session.webView.callDocumentJavaScript(
                    "return globalThis.__htmlPreviewReading.snapshot();", contentWorld: HTMLReadingController.contentWorld
                )
                XCTFail("Search \(query) expected \(count), got \(session.state.matchCount); initial DOM: \(String(describing: value)); current DOM: \(String(describing: current))", file: file, line: line)
                throw ReadingTestError.timedOut
            }
            try await Task.sleep(for: .milliseconds(30))
        }
    }

    func testMarkdownStructuralPositionSurvivesTypographyReflowAndRelaunch() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("markdown-position.html")
        try fixture((0..<10).map { index in
            """
            <section data-markdown-block="markdown-block-\(index)" style="height:calc(700px * var(--reader-scale, 1))">
              <h2 data-reading-heading-id="markdown-block-\(index)">Chapter \(index)</h2><p>Reader block \(index)</p>
            </section>
            """
        }.joined()).write(to: url, atomically: true, encoding: .utf8)
        let saved = ReadingPosition(anchorID: "markdown-block-4@0.3", progress: 0.45)
        let session = try await ReadingTestSession(entryURL: url, position: saved, documentKind: .markdown)
        defer { session.close() }
        try await session.load(url)
        let initial = try XCTUnwrap(MarkdownReadingIndex.StoredAnchor(session.state.position?.anchorID))
        XCTAssertEqual(initial.blockID, "markdown-block-4")
        XCTAssertEqual(initial.fraction, 0.3, accuracy: 0.015)

        session.state.query = "Reader block"
        session.reader.synchronize()
        try await waitUntil { session.state.matchCount == 10 }
        session.state.navigate(to: .heading("markdown-block-4"))
        session.reader.synchronize()
        try await waitUntil { (session.state.position?.progress ?? 0) > 0.35 }
        _ = try await session.webView.evaluateJavaScript("window.scrollBy(0, 210)")
        try await waitUntil {
            guard let anchor = MarkdownReadingIndex.StoredAnchor(session.state.position?.anchorID) else { return false }
            return anchor.blockID == "markdown-block-4" && abs(anchor.fraction - 198.0 / 700) < 0.015
        }
        let before = try XCTUnwrap(MarkdownReadingIndex.StoredAnchor(session.state.position?.anchorID))
        try await session.reader.applyMarkdownAppearance(fontScale: 1.6, lineSpacing: 8, baseSize: 20)
        let after = try XCTUnwrap(MarkdownReadingIndex.StoredAnchor(session.state.position?.anchorID))
        XCTAssertEqual(after.blockID, before.blockID)
        XCTAssertEqual(after.fraction, before.fraction, accuracy: 0.015)
        XCTAssertEqual(session.state.matchCount, 10)
        XCTAssertEqual(session.state.query, "Reader block")
        let restoredPosition = try XCTUnwrap(session.state.position)
        session.close()

        let restored = try await ReadingTestSession(entryURL: url, position: restoredPosition, documentKind: .markdown)
        defer { restored.close() }
        try await restored.load(url)
        let reopened = try XCTUnwrap(MarkdownReadingIndex.StoredAnchor(restored.state.position?.anchorID))
        XCTAssertEqual(reopened.blockID, after.blockID)
        XCTAssertEqual(reopened.fraction, after.fraction, accuracy: 0.015)
        restored.state.navigate(to: .beginning)
        restored.reader.synchronize()
        try await waitUntil { (restored.state.position?.progress ?? 1) < 0.01 }
    }

    func testHTMLParagraphPositionSurvivesRepeatedViewportWidthChanges() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("html-width-reflow.html")
        let text = String(repeating: "Reading a long paragraph keeps the same place across column widths. ", count: 45)
        let floatingHeaders = """
        <h1 style="position:fixed;top:0;left:16px;font-size:18px;margin:0">Fixed heading</h1>
        <header style="position:fixed;top:28px;left:16px"><p style="margin:0">Fixed ancestor heading</p></header>
        <h2 style="position:sticky;top:56px;font-size:18px;margin:0">Sticky heading</h2>
        <aside style="position:sticky;top:80px"><p style="margin:0">Sticky ancestor heading</p></aside>
        """
        try fixture(floatingHeaders + (0..<16).map { "<p id='paragraph-\($0)'>\(text)</p>" }.joined())
            .write(to: url, atomically: true, encoding: .utf8)
        let session = try await ReadingTestSession(entryURL: url)
        defer { session.close() }
        try await session.load(url)
        let originalBody = try await session.webView.evaluateJavaScript("document.body.innerHTML") as? String
        _ = try await session.webView.evaluateJavaScript("""
        (() => { const rect = document.getElementById('paragraph-8').getBoundingClientRect();
          window.scrollTo(0, window.scrollY + rect.top + rect.height * .35); })()
        """)
        try await waitForBlockFraction(id: "paragraph-8", fraction: 0.35, session: session,
                                       stage: "html initial width 390")
        let visibleFloatingHeaders = try await session.webView.evaluateJavaScript("""
        Array.from(document.querySelectorAll('h1,header,h2,aside')).every(element => {
          const rect = element.getBoundingClientRect(); return rect.top >= 0 && rect.bottom < 150;
        })
        """) as? Bool
        XCTAssertEqual(visibleFloatingHeaders, true, "The fixed and sticky headings must remain visible above the middle paragraph.")
        // Exercise two width changes before the debounced restoration fires.
        // Floating headings must not replace the scrolling paragraph anchor.
        session.resize(width: 320)
        session.resize(width: 540)
        try await waitForBlockFraction(id: "paragraph-8", fraction: 0.35, session: session,
                                       stage: "html burst width 320 then 540")
        session.resize(width: 280)
        try await waitForBlockFraction(id: "paragraph-8", fraction: 0.35, session: session,
                                       stage: "html final width 280")
        let unchangedBody = try await session.webView.evaluateJavaScript("document.body.innerHTML") as? String
        XCTAssertEqual(unchangedBody, originalBody, "Viewport anchoring must preserve the imported HTML body.")
    }

    func testMarkdownBlockPositionSurvivesWidthChangeAndNewNavigationWins() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("markdown-width-reflow.html")
        let text = String(repeating: "Markdown paragraphs reflow as the reading column changes. ", count: 45)
        try fixture((0..<16).map { index in
            "<section id='block-\(index)' data-markdown-block='markdown-block-\(index)'><h2 data-reading-heading-id='markdown-block-\(index)'>Chapter \(index)</h2><p>\(text)</p></section>"
        }.joined()).write(to: url, atomically: true, encoding: .utf8)
        let saved = ReadingPosition(anchorID: "markdown-block-8@0.35", progress: 0.5)
        let session = try await ReadingTestSession(entryURL: url, position: saved, documentKind: .markdown)
        defer { session.close() }
        try await session.load(url)
        try await waitForBlockFraction(id: "block-8", fraction: 0.35, session: session,
                                       stage: "markdown initial width 390")
        session.resize(width: 540)
        try await waitForBlockFraction(id: "block-8", fraction: 0.35, session: session,
                                       stage: "markdown width 540")
        let anchor = try XCTUnwrap(MarkdownReadingIndex.StoredAnchor(session.state.position?.anchorID))
        XCTAssertEqual(anchor.blockID, "markdown-block-8")
        XCTAssertEqual(anchor.fraction, 0.35, accuracy: 0.02)

        session.resize(width: 280)
        // Let WebKit deliver resize, then issue a newer explicit reader action.
        _ = try await session.webView.callDocumentJavaScript(
            "await new Promise(resolve => requestAnimationFrame(resolve)); return null;",
            contentWorld: HTMLReadingController.contentWorld
        )
        session.state.navigate(to: .beginning)
        session.reader.synchronize()
        try await waitForRestoredProgress(0, session: session)
        try await Task.sleep(for: .milliseconds(250))
        try await waitForRestoredProgress(0, session: session)
    }

    func testHeadingNavigationDuringWidthReflowSettlesAtVisibleTarget() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = String(repeating: "Changing the reading column moves later chapters as preceding paragraphs wrap. ", count: 45)
        for kind in [HTMLReadingController.DocumentKind.html, .markdown] {
            let url = directory.appendingPathComponent("heading-navigation-reflow-\(kind).html")
            try fixture((0..<16).map { index in
                "<section id='block-\(index)' data-markdown-block='markdown-block-\(index)'><h2 id='heading-\(index)' data-reading-heading-id='markdown-block-\(index)'>Chapter \(index)</h2><p>\(text)</p></section>"
            }.joined()).write(to: url, atomically: true, encoding: .utf8)
            let session = try await ReadingTestSession(entryURL: url, documentKind: kind)
            defer { session.close() }
            try await session.load(url)
            let target = try XCTUnwrap(session.state.headings.first { $0.title == "Chapter 12" })
            let initialTargetValue = try await session.webView.evaluateJavaScript(
                "document.getElementById('heading-12').getBoundingClientRect().top + scrollY"
            )
            let initialTargetY = try XCTUnwrap(initialTargetValue as? Double)
            _ = try await session.webView.evaluateJavaScript("""
            (() => { const rect = document.getElementById('block-3').getBoundingClientRect();
              window.scrollTo(0, window.scrollY + rect.top + rect.height * .35); })()
            """)
            try await waitForBlockFraction(id: "block-3", fraction: 0.35, session: session,
                                           stage: "heading navigation \(kind) initial width 390")
            try await waitForSearchResultVisibility(id: "heading-12", visible: false, session: session)

            session.resize(width: 320)
            // Start reflow, then request a different heading immediately with the
            // final width. No settled-layout wait may serialize away this race.
            _ = try await session.webView.callDocumentJavaScript(
                "await new Promise(resolve => requestAnimationFrame(resolve)); return null;",
                contentWorld: HTMLReadingController.contentWorld
            )
            session.resize(width: 540)
            session.state.navigate(to: .heading(target.id))
            session.reader.synchronize()

            let deadline = ContinuousClock.now + .seconds(10)
            var stableSince: ContinuousClock.Instant?
            var settledScrollY: Double?
            while true {
                let value = try await session.webView.callDocumentJavaScript("""
                const root = document.scrollingElement;
                const rect = document.getElementById('heading-12').getBoundingClientRect();
                const paragraph = document.querySelector('#block-11 p').getBoundingClientRect();
                const view = window.visualViewport;
                const top = view?.offsetTop || 0;
                return { width: root.clientWidth, paragraphWidth: paragraph.width,
                         top: rect.top, bottom: rect.bottom, viewportTop: top,
                         viewportBottom: top + (view?.height || innerHeight),
                         scrollY, documentY: rect.top + scrollY };
                """, contentWorld: HTMLReadingController.contentWorld)
                let geometry = try XCTUnwrap(value as? [String: Double])
                let scrollY = try XCTUnwrap(geometry["scrollY"])
                let targetTop = try XCTUnwrap(geometry["top"])
                let targetBottom = try XCTUnwrap(geometry["bottom"])
                let viewportTop = try XCTUnwrap(geometry["viewportTop"])
                let viewportBottom = try XCTUnwrap(geometry["viewportBottom"])
                let visible = targetTop >= viewportTop && targetBottom <= viewportBottom
                let width = try XCTUnwrap(geometry["width"])
                let paragraphWidth = try XCTUnwrap(geometry["paragraphWidth"])
                let finalLayout = abs(width - 540) < 1 && abs(paragraphWidth - 508) < 1
                if finalLayout && visible {
                    if settledScrollY == nil || abs(scrollY - (settledScrollY ?? scrollY)) > 1 {
                        settledScrollY = scrollY
                        stableSince = ContinuousClock.now
                    }
                    if let stableSince, ContinuousClock.now - stableSince >= .milliseconds(400) {
                        XCTAssertGreaterThan(abs(try XCTUnwrap(geometry["documentY"]) - initialTargetY), 300,
                                             "The target must actually move through paragraph reflow, unlike a beginning-at-zero request.")
                        break
                    }
                } else {
                    stableSince = nil
                    settledScrollY = nil
                }
                guard ContinuousClock.now < deadline else {
                    await recordViewportGeometry(id: "heading-12", stage: "heading navigation \(kind) timeout",
                                                 session: session, keepAttachment: true)
                    XCTFail("New heading navigation did not remain visible and stable in the final layout: \(geometry)")
                    throw ReadingTestError.timedOut
                }
                try await Task.sleep(for: .milliseconds(30))
            }
        }
    }

    func testVisibleSelectedSearchResultRemainsVisibleAfterViewportShrinks() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for kind in [HTMLReadingController.DocumentKind.html, .markdown] {
            let url = directory.appendingPathComponent("visible-search-\(kind).html")
            try fixture("""
            <p id="first" data-markdown-block="markdown-block-0">needle</p>
            <p id="selected" data-markdown-block="markdown-block-1" style="margin-top:360px">needle</p>
            """).write(to: url, atomically: true, encoding: .utf8)
            let session = try await ReadingTestSession(entryURL: url, documentKind: kind)
            defer { session.close() }
            try await session.load(url)
            try await assertMarkdownSearch("needle", count: 2, session: session)
            session.state.navigate(to: .match(1))
            session.reader.synchronize()
            try await waitUntil { session.state.selectedMatch == 1 }
            try await waitForSearchResultVisibility(id: "selected", visible: true, session: session)
            let initialScroll = session.webView.scrollView
            XCTAssertEqual(initialScroll.contentOffset.y + initialScroll.adjustedContentInset.top, 0, accuracy: 1,
                           "The entire short page should initially fit without scrolling.")
            session.resize(width: 390, height: 180)
            try await waitForSearchResultVisibility(id: "selected", visible: true, session: session)
            XCTAssertGreaterThan(session.webView.scrollView.contentOffset.y, 100,
                                 "Shrinking height must actually reveal the previously visible second match.")
            XCTAssertEqual(session.state.query, "needle")
            XCTAssertEqual(session.state.matchCount, 2)
            XCTAssertEqual(session.state.selectedMatch, 1)

            session.resize(width: 320, height: 140)
            _ = try await session.webView.callDocumentJavaScript(
                "await new Promise(resolve => requestAnimationFrame(resolve)); return null;",
                contentWorld: HTMLReadingController.contentWorld
            )
            session.state.navigate(to: .beginning)
            session.reader.synchronize()
            try await waitForRestoredProgress(0, session: session)
            try await Task.sleep(for: .milliseconds(200))
            try await waitForRestoredProgress(0, session: session)
            XCTAssertEqual(session.state.selectedMatch, 1, "A newer navigation must cancel resize revelation without resetting search selection.")
        }
    }

    func testResizePreservesReadingAnchorWhenUserScrolledAwayFromSelectedResult() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = String(repeating: "A reader can continue elsewhere while keeping a previous search open. ", count: 45)
        for kind in [HTMLReadingController.DocumentKind.html, .markdown] {
            let url = directory.appendingPathComponent("scrolled-search-\(kind).html")
            let paragraphs = (0..<16).map { index in
                "<p id='paragraph-\(index)' data-markdown-block='markdown-block-\(index + 1)'>\(text)</p>"
            }.joined()
            try fixture("<p data-markdown-block='markdown-block-0'>needle</p>" + paragraphs
                        + "<p id='selected' data-markdown-block='markdown-block-17'>needle</p>")
                .write(to: url, atomically: true, encoding: .utf8)
            let session = try await ReadingTestSession(entryURL: url, documentKind: kind)
            defer { session.close() }
            try await session.load(url)
            try await assertMarkdownSearch("needle", count: 2, session: session)
            session.state.navigate(to: .match(1))
            session.reader.synchronize()
            try await waitUntil { session.state.selectedMatch == 1 }
            try await waitForSearchResultVisibility(id: "selected", visible: true, session: session)
            _ = try await session.webView.evaluateJavaScript("""
            (() => { const rect = document.getElementById('paragraph-8').getBoundingClientRect();
              window.scrollTo(0, window.scrollY + rect.top + rect.height * .35); })()
            """)
            try await waitForBlockFraction(id: "paragraph-8", fraction: 0.35, session: session,
                                           stage: "scrolled-away \(kind) initial width 390")
            try await waitForSearchResultVisibility(id: "selected", visible: false, session: session)
            session.resize(width: 280, height: 220)
            try await waitForBlockFraction(id: "paragraph-8", fraction: 0.35, session: session,
                                           stage: "scrolled-away \(kind) width 280 height 220")
            try await waitForSearchResultVisibility(id: "selected", visible: false, session: session)
            XCTAssertEqual(session.state.query, "needle")
            XCTAssertEqual(session.state.matchCount, 2)
            XCTAssertEqual(session.state.selectedMatch, 1)
        }
    }

    private func waitForSearchResultVisibility(id: String, visible: Bool, session: ReadingTestSession) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        var stableSince: ContinuousClock.Instant?
        while true {
            let value = try await session.webView.callDocumentJavaScript("""
            const rect = document.getElementById(id).getBoundingClientRect();
            const view = window.visualViewport;
            const top = view?.offsetTop || 0;
            const bottom = top + (view?.height || innerHeight);
            return visible ? rect.top >= top && rect.bottom <= bottom : rect.bottom <= top || rect.top >= bottom;
            """, arguments: ["id": id, "visible": visible], contentWorld: HTMLReadingController.contentWorld)
            if value as? Bool == true {
                if stableSince == nil { stableSince = ContinuousClock.now }
                if let stableSince, ContinuousClock.now - stableSince >= .milliseconds(200) { return }
            } else { stableSince = nil }
            guard ContinuousClock.now < deadline else {
                XCTFail("Result \(id) did not settle with visibility \(visible)")
                throw ReadingTestError.timedOut
            }
            try await Task.sleep(for: .milliseconds(30))
        }
    }

    private func recordViewportGeometry(id: String, stage: String, session: ReadingTestSession,
                                        keepAttachment: Bool = false) async {
        let value = try? await session.webView.callDocumentJavaScript("""
        const rect = document.getElementById(id).getBoundingClientRect();
        const view = window.visualViewport;
        const root = document.scrollingElement;
        const height = root.clientHeight || innerHeight;
        const visibleHeight = Math.min(view?.height || height, height);
        const effectiveTop = Math.min(Math.max(0, view?.offsetTop || 0), height - visibleHeight);
        return {
          block: { id, top: rect.top, bottom: rect.bottom, width: rect.width, height: rect.height,
                   fraction: -rect.top / rect.height,
                   effectiveViewportFraction: (effectiveTop - rect.top) / rect.height },
          innerWidth, innerHeight, scrollX, scrollY,
          root: { scrollTop: root.scrollTop, scrollLeft: root.scrollLeft,
                  clientWidth: root.clientWidth, clientHeight: root.clientHeight,
                  scrollWidth: root.scrollWidth, scrollHeight: root.scrollHeight },
          visualViewport: view ? { offsetTop: view.offsetTop, offsetLeft: view.offsetLeft,
                                  pageTop: view.pageTop, pageLeft: view.pageLeft,
                                  width: view.width, height: view.height, scale: view.scale } : null,
          effectiveViewportTop: effectiveTop
        };
        """, arguments: ["id": id], contentWorld: HTMLReadingController.contentWorld)
        let dom: String
        if let value, JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            dom = text
        } else {
            dom = "unavailable"
        }
        let scroll = session.webView.scrollView
        let diagnostic = "Viewport anchor [\(stage)] DOM \(dom) "
            + "WK frame=\(session.webView.frame) bounds=\(session.webView.bounds) "
            + "contentOffset=\(scroll.contentOffset) contentSize=\(scroll.contentSize) "
            + "contentInset=\(scroll.contentInset) adjustedContentInset=\(scroll.adjustedContentInset) "
            + "zoomScale=\(scroll.zoomScale) pageZoom=\(session.webView.pageZoom) "
            + "storedProgress=\(String(describing: session.state.position?.progress))"
        print(diagnostic)
        if keepAttachment {
            let attachment = XCTAttachment(string: diagnostic)
            attachment.name = "Viewport anchor geometry \(stage)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func waitForBlockFraction(id: String, fraction: Double, session: ReadingTestSession,
                                      stage: String) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        var stableSince: ContinuousClock.Instant?
        await recordViewportGeometry(id: id, stage: stage + " first sample", session: session)
        while true {
            let value = try await session.webView.callDocumentJavaScript(
                "const rect = document.getElementById(id).getBoundingClientRect(); return -rect.top / rect.height;",
                arguments: ["id": id], contentWorld: HTMLReadingController.contentWorld
            )
            if let current = value as? Double, abs(current - fraction) < 0.02 {
                if stableSince == nil { stableSince = ContinuousClock.now }
                if let stableSince, ContinuousClock.now - stableSince >= .milliseconds(200) {
                    await recordViewportGeometry(id: id, stage: stage + " settled", session: session)
                    return
                }
            } else { stableSince = nil }
            guard ContinuousClock.now < deadline else {
                await recordViewportGeometry(id: id, stage: stage + " timeout", session: session,
                                             keepAttachment: true)
                XCTFail("Block \(id) did not retain fraction \(fraction) at \(stage); observed \(String(describing: value))")
                throw ReadingTestError.timedOut
            }
            try await Task.sleep(for: .milliseconds(30))
        }
    }

    private func fixture(_ body: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
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

    private func waitForRestoredProgress(_ expected: Double, session: ReadingTestSession) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        var stableSince: ContinuousClock.Instant?
        var firstSample = true
        var diagnostic = ""
        while true {
            let value = try await session.webView.callDocumentJavaScript(
                "return globalThis.__htmlPreviewReading?.snapshot().progress;",
                arguments: [:], contentWorld: HTMLReadingController.contentWorld
            )
            let dom = try XCTUnwrap(value as? Double)
            let scroll = session.webView.scrollView
            let inset = scroll.adjustedContentInset
            let extent = scroll.contentSize.height - scroll.bounds.height + inset.top + inset.bottom
            let native = extent > 0 ? Double((scroll.contentOffset.y + inset.top) / extent) : 0
            let model = session.state.position?.progress ?? -1
            diagnostic = "expected: \(expected), model: \(model), DOM: \(dom), native: \(native), extent: \(extent)"
            if firstSample {
                print("Entry reading restoration initial: \(diagnostic)")
                firstSample = false
            }
            if !session.webView.isLoading, [model, dom, native].allSatisfy({ abs($0 - expected) < 0.015 }) {
                if stableSince == nil { stableSince = ContinuousClock.now }
                if let stableSince, ContinuousClock.now - stableSince >= .milliseconds(150) {
                    print("Entry reading restoration settled: \(diagnostic)")
                    return
                }
            } else {
                stableSince = nil
            }
            guard ContinuousClock.now < deadline else {
                let attachment = XCTAttachment(string: diagnostic)
                attachment.name = "Entry reading position did not settle"
                attachment.lifetime = .keepAlways
                add(attachment)
                if let image = try? await session.webView.takeSnapshot(configuration: nil) {
                    let snapshot = XCTAttachment(image: image)
                    snapshot.name = "Entry reading viewport on timeout"
                    snapshot.lifetime = .keepAlways
                    add(snapshot)
                }
                XCTFail("Entry reading position did not settle: \(diagnostic)")
                throw ReadingTestError.timedOut
            }
            try await Task.sleep(for: .milliseconds(40))
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

    init(entryURL: URL, position: ReadingPosition? = nil, documentKind: HTMLReadingController.DocumentKind = .html) async throws {
        state = DocumentReadingState(position: position)
        let configuration = try await HTMLPreviewConfiguration.make(mode: .safePreview)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }, "Reading tests require an active host scene.")
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), configuration: configuration)
        reader = HTMLReadingController(state: state, entryURL: entryURL, documentKind: documentKind)
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

    func resize(width: CGFloat, height: CGFloat? = nil) {
        webView.frame.size = CGSize(width: width, height: height ?? webView.bounds.height)
        webView.setNeedsLayout()
        webView.layoutIfNeeded()
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
