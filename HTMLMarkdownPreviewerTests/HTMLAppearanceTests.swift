import Observation
import PDFKit
import SwiftUI
import WebKit
import XCTest
@testable import HTMLMarkdownPreviewer

@MainActor
final class HTMLAppearanceTests: XCTestCase {
    func testZoomUpdatesLoadedPageWithoutReloadingOrChangingSourceStyles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("report.html")
        try """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>body { font: 16px -apple-system; } p { margin: 20px; }</style></head>
        <body><h1>Zoom report</h1><p id="live">Original</p><div style="min-height:1600px"></div><p id="search-marker">Searchable marker</p>
        <script>window.reportState = { value: 17 };</script></body></html>
        """.write(to: url, atomically: true, encoding: .utf8)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let model = HTMLAppearanceTestModel()
        let host = UIHostingController(rootView: HTMLAppearanceTestHost(url: url, model: model))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        try await waitUntil { model.webView != nil && model.reading.isReady }
        let webView = try XCTUnwrap(model.webView)
        _ = try await webView.evaluateJavaScript("window.reportState.value = 42; document.getElementById('live').textContent = 'Updated live report'")
        let originalHTML = try await webView.evaluateJavaScript("document.body.innerHTML") as? String
        let baselinePDFData = try await PDFExportService().pdfData(webView: webView, title: "Zoom report")
        let baselinePDF = try XCTUnwrap(PDFDocument(data: baselinePDFData))
        let baselineSelection = try XCTUnwrap(baselinePDF.findString("Updated live report", withOptions: []).first)
        let baselinePage = try XCTUnwrap(baselineSelection.pages.first)
        let baselineBounds = baselineSelection.bounds(for: baselinePage)
        model.zoom = 1.5
        try await waitForNativeZoom(1.5, in: webView)
        XCTAssertTrue(model.webView === webView)
        let liveValue = try await webView.evaluateJavaScript("window.reportState.value") as? Int
        let zoomedHTML = try await webView.evaluateJavaScript("document.body.innerHTML") as? String
        XCTAssertEqual(liveValue, 42, "Zoom must preserve page interaction state.")
        XCTAssertEqual(zoomedHTML, originalHTML, "Zoom must not rewrite the imported source's styles or content.")

        model.reading.query = "Searchable marker"
        try await waitUntil { model.reading.matchCount == 1 }
        let markerVisible = try await webView.evaluateJavaScript("""
        (() => {
            const range = document.createRange();
            range.selectNodeContents(document.getElementById('search-marker'));
            const rect = range.getBoundingClientRect();
            const root = document.scrollingElement;
            const view = window.visualViewport;
            const height = Math.min(root.clientHeight, view.height);
            const top = Math.min(Math.max(0, view.offsetTop), root.clientHeight - height);
            return rect.top >= top && rect.bottom <= top + height;
        })()
        """) as? Bool
        XCTAssertEqual(markerVisible, true, "Search must scroll the actual zoomed match into the visible viewport.")
        let readingOffsetBeforeExport = webView.scrollView.contentOffset
        let pdf = try await PDFExportService().pdfData(webView: webView, title: "Zoom report")
        let zoomedPDF = try XCTUnwrap(PDFDocument(data: pdf))
        let zoomedSelection = try XCTUnwrap(zoomedPDF.findString("Updated live report", withOptions: []).first)
        let zoomedPage = try XCTUnwrap(zoomedSelection.pages.first)
        let zoomedBounds = zoomedSelection.bounds(for: zoomedPage)
        XCTAssertEqual(zoomedPDF.pageCount, baselinePDF.pageCount, "Reader zoom must not change print pagination.")
        XCTAssertEqual(zoomedPDF.index(for: zoomedPage), baselinePDF.index(for: baselinePage))
        XCTAssertEqual(zoomedBounds.minX, baselineBounds.minX, accuracy: 1)
        XCTAssertEqual(zoomedBounds.minY, baselineBounds.minY, accuracy: 1)
        XCTAssertEqual(zoomedBounds.width, baselineBounds.width, accuracy: 1)
        XCTAssertEqual(zoomedBounds.height, baselineBounds.height, accuracy: 1,
                       "Reader zoom must leave the PDF's actual text size and placement unchanged.")
        try await waitForNativeZoom(1.5, in: webView)
        XCTAssertEqual(webView.scrollView.contentOffset.x, readingOffsetBeforeExport.x, accuracy: 1)
        XCTAssertEqual(webView.scrollView.contentOffset.y, readingOffsetBeforeExport.y, accuracy: 1)
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001, "Native page zoom must remain stable to avoid text autosizing drift.")

        model.zoom = 8
        try await waitForNativeZoom(3, in: webView)
        model.zoom = .nan
        try await waitForNativeZoom(1, in: webView)

        let linkedURL = directory.appendingPathComponent("linked.html")
        try """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>
        <body><h1>Linked report</h1><p>Local navigation keeps the reader preference.</p></body></html>
        """.write(to: linkedURL, atomically: true, encoding: .utf8)
        model.zoom = 1.5
        try await waitForNativeZoom(1.5, in: webView)
        webView.loadFileURL(linkedURL, allowingReadAccessTo: directory)
        try await waitUntil { webView.url?.lastPathComponent == "linked.html" && !webView.isLoading && model.reading.isReady }
        try await waitForNativeZoom(1.5, in: webView)
        webView.goBack()
        try await waitUntil { webView.url?.lastPathComponent == "report.html" && !webView.isLoading && model.reading.isReady }
        try await waitForNativeZoom(1.5, in: webView)
    }

    func testSavedZoomLoadsWithTheSameTextBaselineAndResetRestoresFreshSize() async throws {
        for textAdjustment in ["auto", "100%"] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("report.html")
        // Match the UI fixture, including its long heading and mobile viewport:
        // mobile text autosizing depends on the page's actual line wrapping.
        try """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html{-webkit-text-size-adjust:\(textAdjustment)}body{font:16px -apple-system;line-height:1.5;padding:18px;color:#173a35;background:#f5faf8}h1{font-size:24px}p{max-width:44rem}</style>
        </head><body><h1>QA HTML D30DDCDD-6BED-456B-B67D-F614FA78F077</h1><p>HTML layout marker</p>
        <p>A local report keeps its typography while the reader adjusts page zoom. The document stays available without a network connection.</p>
        <h2>Details</h2><p>Full screen makes room for the report. The restore button brings navigation and reading controls back.</p>
        </body></html>
        """.write(to: url, atomically: true, encoding: .utf8)

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let baselineModel = HTMLAppearanceTestModel()
        window.rootViewController = UIHostingController(rootView: HTMLAppearanceTestHost(url: url, model: baselineModel))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        try await waitUntil { baselineModel.webView != nil && baselineModel.reading.isReady }
        let baselineWebView = try XCTUnwrap(baselineModel.webView)
        let baseline = try await markerMetrics(in: baselineWebView)
        recordMetrics(baseline, stage: "fresh-100")
        let originalTextHeight = try XCTUnwrap(baseline["textHeight"])
        let originalParagraphHeight = try XCTUnwrap(baseline["paragraphHeight"])
        XCTAssertGreaterThan(originalTextHeight, 0)
        baselineModel.zoom = 1.5
        try await waitForNativeZoom(1.5, in: baselineWebView)
        let changed = try await markerMetrics(in: baselineWebView)
        recordMetrics(changed, stage: "change-150")
        XCTAssertGreaterThan(try XCTUnwrap(changed["screenTextHeight"]), originalTextHeight + 2)
        baselineModel.zoom = 1
        try await waitForNativeZoom(1, in: baselineWebView)
        let changedResetMetrics = try await markerMetrics(in: baselineWebView)
        recordMetrics(changedResetMetrics, stage: "change-reset-100")

        let restoredModel = HTMLAppearanceTestModel()
        restoredModel.zoom = 1.5
        window.rootViewController = UIHostingController(rootView: HTMLAppearanceTestHost(url: url, model: restoredModel))
        try await waitUntil { restoredModel.webView != nil && restoredModel.reading.isReady }
        let restoredWebView = try XCTUnwrap(restoredModel.webView)
        XCTAssertFalse(restoredWebView === baselineWebView)
        try await waitForNativeZoom(1.5, in: restoredWebView)
        XCTAssertEqual(restoredWebView.pageZoom, 1, accuracy: 0.001)
        let zoomed = try await markerMetrics(in: restoredWebView)
        recordMetrics(zoomed, stage: "fresh-150")
        let zoomedDisplayHeight = try XCTUnwrap(zoomed["screenTextHeight"])
        XCTAssertGreaterThan(zoomedDisplayHeight, originalTextHeight + 2,
                             "Increasing page zoom must enlarge the rendered text, not just narrow its layout.")

        restoredModel.zoom = 1
        try await waitForNativeZoom(1, in: restoredWebView)
        // The Swift property can change before WebKit completes its layout.
        let deadline = ContinuousClock.now + .seconds(5)
        var reset = try await markerMetrics(in: restoredWebView)
        while abs((reset["textHeight"] ?? 0) - originalTextHeight) > 1, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(80))
            reset = try await markerMetrics(in: restoredWebView)
        }
        recordMetrics(reset, stage: "fresh-150-reset-100")
        XCTAssertEqual(try XCTUnwrap(reset["textHeight"]), originalTextHeight, accuracy: 1,
                       "Reset must restore the rendered glyph height, not just the stored zoom value.")
        XCTAssertEqual(try XCTUnwrap(reset["paragraphHeight"]), originalParagraphHeight, accuracy: 1,
                       "Reset must also restore the original paragraph line box.")
        }
    }

    func testReadingStylePreservesAuthorCascadeAndConstructedStyleSheets() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("author-styles.html")
        try """
        <!doctype html><html style="-webkit-text-size-adjust:80%"><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style id="author-layer">@layer author { html { -webkit-text-size-adjust:150% } }</style>
        <style id="author-style">html { -webkit-text-size-adjust:125% } body { -webkit-text-size-adjust:110% }</style>
        <script>
        const authorSheet = new CSSStyleSheet();
        authorSheet.replaceSync('p { color: rgb(17, 34, 51) }');
        document.adoptedStyleSheets = [...document.adoptedStyleSheets, authorSheet];
        </script></head><body><p>Author typography</p></body></html>
        """.write(to: url, atomically: true, encoding: .utf8)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let model = HTMLAppearanceTestModel()
        window.rootViewController = UIHostingController(rootView: HTMLAppearanceTestHost(url: url, model: model))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        try await waitUntil { model.webView != nil && model.reading.isReady }
        let webView = try XCTUnwrap(model.webView)
        let rootAdjustment = "getComputedStyle(document.documentElement).webkitTextSizeAdjust"
        _ = try await webView.evaluateJavaScript("document.documentElement.style.zoom = '1.25'")
        model.zoom = 1.5
        try await waitForNativeZoom(1.5, in: webView)
        model.zoom = 1
        try await waitForNativeZoom(1, in: webView)
        let sourceZoom = try await webView.evaluateJavaScript("getComputedStyle(document.documentElement).zoom") as? String
        XCTAssertEqual(sourceZoom, "1.25", "Optical zoom must preserve the author's own root scale.")
        let inlineAdjustment = try await webView.evaluateJavaScript(rootAdjustment) as? String
        XCTAssertEqual(inlineAdjustment, "80%")
        let bodyAdjustment = try await webView.evaluateJavaScript("getComputedStyle(document.body).webkitTextSizeAdjust") as? String
        XCTAssertEqual(bodyAdjustment, "110%", "The reader default must not override a descendant's explicit style.")
        let color = try await webView.evaluateJavaScript("getComputedStyle(document.querySelector('p')).color") as? String
        XCTAssertEqual(color, "rgb(17, 34, 51)", "Author constructed style sheets must remain adopted.")

        _ = try await webView.evaluateJavaScript("document.documentElement.removeAttribute('style')")
        let ordinaryAdjustment = try await webView.evaluateJavaScript(rootAdjustment) as? String
        XCTAssertEqual(ordinaryAdjustment, "125%")
        _ = try await webView.evaluateJavaScript("document.getElementById('author-style').remove()")
        let layerAdjustment = try await webView.evaluateJavaScript(rootAdjustment) as? String
        XCTAssertEqual(layerAdjustment, "150%", "Author cascade layers must outrank the reader's earliest layer.")
        _ = try await webView.evaluateJavaScript("document.getElementById('author-layer').remove()")
        let defaultAdjustment = try await webView.evaluateJavaScript(rootAdjustment) as? String
        XCTAssertEqual(defaultAdjustment, "auto", "Reader zoom must leave the document's text-size-adjust behavior unchanged.")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8).contains("html-previewer-reading"), false,
                       "The reading preference must never be written into the imported file.")
    }

    func testSafePreviewInstallsReadingStyleWithoutEnablingDocumentScripts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("safe-styles.html")
        try """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body><p>Safe reading marker</p><script>window.documentScriptRan = true;</script></body></html>
        """.write(to: url, atomically: true, encoding: .utf8)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let model = HTMLAppearanceTestModel()
        model.zoom = 1.5
        window.rootViewController = UIHostingController(rootView: HTMLAppearanceTestHost(url: url, model: model, mode: .safePreview))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        try await waitUntil { model.webView != nil && model.reading.isReady }
        let webView = try XCTUnwrap(model.webView)
        let adjustment = try await webView.evaluateJavaScript("getComputedStyle(document.documentElement).webkitTextSizeAdjust") as? String
        XCTAssertEqual(adjustment, "auto")
        let didRun = try await webView.evaluateJavaScript("window.documentScriptRan === true") as? Bool
        XCTAssertEqual(didRun, false)
        let sheets = try await webView.evaluateJavaScript("document.querySelectorAll('style[data-html-previewer-reading]').length") as? Int
        XCTAssertEqual(sheets, 0, "Optical zoom must not inject a stylesheet.")
        try await waitForNativeZoom(1.5, in: webView)
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)
    }

    func testReaderZoomDoesNotWeakenStrictContentSecurityPolicy() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("strict-csp.html")
        try """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'nonce-readable'">
        <style nonce="readable">html { zoom:1.25 } body { font:16px -apple-system; color:rgb(17, 34, 51) }</style>
        </head><body><p id="marker">Restricted document</p>
        <style>body { color:rgb(255, 0, 0) }</style>
        <script>window.documentScriptRan = true;</script></body></html>
        """.write(to: url, atomically: true, encoding: .utf8)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let model = HTMLAppearanceTestModel()
        model.zoom = 1.5
        window.rootViewController = UIHostingController(rootView: HTMLAppearanceTestHost(url: url, model: model))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        try await waitUntil { model.webView != nil && model.reading.isReady }
        let webView = try XCTUnwrap(model.webView)
        try await waitForNativeZoom(1.5, in: webView)
        model.zoom = 1
        try await waitForNativeZoom(1, in: webView)
        let color = try await webView.evaluateJavaScript("getComputedStyle(document.body).color") as? String
        XCTAssertEqual(color, "rgb(17, 34, 51)", "CSP must still reject the document's unapproved inline stylesheet.")
        let didRun = try await webView.evaluateJavaScript("window.documentScriptRan === true") as? Bool
        XCTAssertEqual(didRun, false, "CSP must still reject unapproved document scripts.")
    }

    func testOpticalZoomUsesNaturalFitForDocumentsWithoutViewport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("desktop.html")
        try """
        <!doctype html><html><head><style>body{width:980px;font:16px -apple-system}</style></head>
        <body><p>Desktop layout marker</p><div style="height:2000px"></div></body></html>
        """.write(to: url, atomically: true, encoding: .utf8)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let model = HTMLAppearanceTestModel()
        window.rootViewController = UIHostingController(rootView: HTMLAppearanceTestHost(url: url, model: model))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        try await waitUntil { model.webView != nil && model.reading.isReady }
        let webView = try XCTUnwrap(model.webView)
        let baselineScale = webView.scrollView.zoomScale
        XCTAssertLessThan(baselineScale, 1)
        let original = try await markerMetrics(in: webView)
        model.zoom = 1.5
        try await waitForNativeZoom(baselineScale * 1.5, in: webView)
        let zoomed = try await markerMetrics(in: webView)
        let zoomedHeight = try XCTUnwrap(zoomed["screenTextHeight"])
        let originalHeight = try XCTUnwrap(original["screenTextHeight"])
        XCTAssertEqual(zoomedHeight, originalHeight * 1.5, accuracy: 1)
        model.zoom = 1
        try await waitForNativeZoom(baselineScale, in: webView)
    }

    func testOpticalZoomRestoresVisualReadingPositionOnReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("long.html")
        try """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <style>html{-webkit-text-size-adjust:100%}body{font:16px -apple-system}</style></head>
        <body><h1>Long report</h1><p>Fixed author typography</p><div style="height:6000px"></div><p>Final marker</p></body></html>
        """.write(to: url, atomically: true, encoding: .utf8)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let model = HTMLAppearanceTestModel()
        model.zoom = 1.5
        window.rootViewController = UIHostingController(rootView: HTMLAppearanceTestHost(url: url, model: model))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        try await waitUntil { model.webView != nil && model.reading.isReady }
        let webView = try XCTUnwrap(model.webView)
        try await waitForNativeZoom(1.5, in: webView)
        let scroll = webView.scrollView
        let inset = scroll.adjustedContentInset
        let extent = scroll.contentSize.height - scroll.bounds.height + inset.top + inset.bottom
        scroll.setContentOffset(CGPoint(x: 0, y: extent * 0.92 - inset.top), animated: false)
        try await waitUntil { abs((model.reading.position?.progress ?? 0) - 0.92) < 0.02 }
        let originalTop = (scroll.contentOffset.y + inset.top) / scroll.zoomScale
        window.rootViewController = nil
        try await waitUntil { !model.reading.isReady }
        let saved = try XCTUnwrap(model.reading.position)
        XCTAssertEqual(saved.progress, 0.92, accuracy: 0.02)
        let reopened = HTMLAppearanceTestModel()
        reopened.zoom = 1.5
        reopened.reading.position = saved
        window.rootViewController = UIHostingController(rootView: HTMLAppearanceTestHost(url: url, model: reopened))
        try await waitUntil { reopened.webView != nil && reopened.reading.isReady }
        let restored = try XCTUnwrap(reopened.webView).scrollView
        let restoredTop = (restored.contentOffset.y + restored.adjustedContentInset.top) / restored.zoomScale
        XCTAssertEqual(restoredTop, originalTop, accuracy: 5, "Reopening a zoomed document must restore its visual reading position.")
    }

    private func waitForNativeZoom(_ scale: Double, in webView: WKWebView) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while true {
            let visual = try await webView.evaluateJavaScript("visualViewport.scale") as? Double
            let animating: Bool
            if #available(iOS 17.4, *) { animating = webView.scrollView.isZoomAnimating }
            else { animating = webView.scrollView.isZooming }
            if !animating, abs(webView.scrollView.zoomScale - scale) < 0.005,
               let visual, abs(visual - scale) < 0.005 { return }
            guard ContinuousClock.now < deadline else {
                let diagnostic = try await webView.evaluateJavaScript("JSON.stringify({visualScale:visualViewport.scale,width:visualViewport.width,height:visualViewport.height,innerWidth,innerHeight,print:matchMedia('print').matches,scrollY,top:visualViewport.pageTop})")
                print("Native zoom timeout diagnostic: \(String(describing: diagnostic))")
                XCTFail("Timed out waiting for optical zoom \(scale); native \(webView.scrollView.zoomScale), visual \(String(describing: visual))")
                throw HTMLAppearanceTestError.timedOut
            }
            try await Task.sleep(for: .milliseconds(40))
        }
    }

    private func markerMetrics(in webView: WKWebView) async throws -> [String: Double] {
        let value = try await webView.evaluateJavaScript("""
        (() => {
            const paragraph = document.querySelector('p');
            const range = document.createRange();
            range.selectNodeContents(paragraph);
            const glyphs = range.getBoundingClientRect();
            const style = getComputedStyle(paragraph);
            return { textHeight: glyphs.height, textWidth: glyphs.width,
                paragraphHeight: paragraph.getBoundingClientRect().height,
                fontSize: parseFloat(style.fontSize), lineHeight: parseFloat(style.lineHeight),
                innerWidth: innerWidth, visualScale: visualViewport.scale,
                documentWidth: document.documentElement.scrollWidth,
                rootZoom: Number.parseFloat(getComputedStyle(document.documentElement).zoom) || 1 };
        })()
        """)
        var metrics = try XCTUnwrap(value as? [String: Double])
        metrics["pageZoom"] = webView.pageZoom
        metrics["viewWidth"] = webView.bounds.width
        metrics["scrollZoom"] = webView.scrollView.zoomScale
        metrics["screenTextHeight"] = (metrics["textHeight"] ?? 0) * (metrics["rootZoom"] ?? 1) * webView.pageZoom * webView.scrollView.zoomScale
        return metrics
    }

    private func recordMetrics(_ metrics: [String: Double], stage: String) {
        let data = try? JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys])
        let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? String(describing: metrics)
        print("HTML zoom baseline \(stage): \(text)")
        let attachment = XCTAttachment(string: text)
        attachment.name = "HTML zoom baseline \(stage)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitUntil(file: StaticString = #filePath, line: UInt = #line,
                           _ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(30)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("Timed out waiting for HTML appearance update", file: file, line: line)
                throw HTMLAppearanceTestError.timedOut
            }
            try await Task.sleep(for: .milliseconds(40))
        }
    }
}

private enum HTMLAppearanceTestError: Error { case timedOut }

@MainActor
@Observable
private final class HTMLAppearanceTestModel {
    var zoom = 1.0
    var webView: WKWebView?
    let reading = DocumentReadingState()
}

private struct HTMLAppearanceTestHost: View {
    let url: URL
    let model: HTMLAppearanceTestModel
    var mode: HTMLPreviewMode = .interactive

    var body: some View {
        HTMLPreviewView(fileURL: url, readAccessRootURL: url.deletingLastPathComponent(),
                        mode: mode, readingState: model.reading, pageZoom: model.zoom) {
            model.webView = $0
        }
    }
}
