import PDFKit
import UIKit
import WebKit
import XCTest
@testable import HTMLMarkdownPreviewer

@MainActor
final class MarkdownEnhancementTests: XCTestCase {
    func testOfflineMathLoadsBundledFontsAndProducesAccessibleInlineAndDisplayOutput() async throws {
        let document = MarkdownRenderService().render(markdown: #"""
        Inline $a^2 + b^2 = c^2$ remains readable.

        $$
        \frac{x + 1}{y + 2} + \sqrt{z}
        $$
        """#)
        let session = try await MarkdownEnhancementSession.make()
        defer { session.close() }
        try await session.load(document)
        let result = try await session.object(#"""
        ({ ready: document.documentElement.dataset.markdownReady,
           inline: document.querySelectorAll('.math[data-math-display="false"] .katex').length,
           display: document.querySelectorAll('.math-display .katex-display').length,
           fractions: document.querySelectorAll('.katex .mfrac').length,
           accessibleMath: document.querySelectorAll('.katex math').length,
           loadedFonts: Array.from(document.fonts).filter(f => f.family.includes('KaTeX') && f.status === 'loaded').length,
           stylesheet: document.querySelector('link[rel=stylesheet]').href,
           width: document.querySelector('.math-display .katex').getBoundingClientRect().width,
           remoteResources: performance.getEntriesByType('resource').filter(e => /^https?:/i.test(e.name)).map(e => e.name)
        })
        """#)
        XCTAssertEqual(result["ready"] as? String, "true")
        XCTAssertEqual(result["inline"] as? Int, 1)
        XCTAssertEqual(result["display"] as? Int, 1)
        XCTAssertEqual(result["fractions"] as? Int, 1)
        XCTAssertEqual(result["accessibleMath"] as? Int, 2)
        XCTAssertGreaterThan(result["loadedFonts"] as? Int ?? 0, 0, "KaTeX must use bundled fonts, not missing-font fallbacks.")
        XCTAssertEqual(result["stylesheet"] as? String, MarkdownWebResources.origin + "/katex.min.css")
        XCTAssertGreaterThan(result["width"] as? Double ?? 0, 30)
        XCTAssertEqual(result["remoteResources"] as? [String], [])
    }

    func testHighlightAndCopyPreserveExactCodeIncludingWhitespaceAndHostileMarkup() async throws {
        let source = "let html = \"<img src=x onerror=alert(1)>\"\n\tprint(html)  \n"
        let document = MarkdownDocument(blocks: [.codeBlock(language: "swift", code: source)])
        let session = try await MarkdownEnhancementSession.make()
        defer { session.close() }
        try await session.load(document)
        let result = try await session.object("""
        ({ text: document.querySelector('pre code').textContent,
           spans: document.querySelectorAll('pre code .hljs-keyword').length,
           injectedImages: document.querySelectorAll('pre code img').length })
        """)
        XCTAssertEqual(result["text"] as? String, source)
        XCTAssertGreaterThan(result["spans"] as? Int ?? 0, 0)
        XCTAssertEqual(result["injectedImages"] as? Int, 0)
        _ = try await session.webView.evaluateJavaScript("document.querySelector('.copy-code').click()")
        try await session.waitForCopy()
        XCTAssertEqual(session.messages.last?["type"] as? String, "copy")
        XCTAssertEqual(session.messages.last?["text"] as? String, source)
        let feedback = try await session.object("""
        ({ label: document.querySelector('.copy-label').textContent,
           expected: document.body.dataset.copiedLabel,
           accessibility: document.querySelector('.copy-code').getAttribute('aria-label') })
        """)
        XCTAssertEqual(feedback["label"] as? String, feedback["expected"] as? String)
        XCTAssertEqual(feedback["accessibility"] as? String, feedback["expected"] as? String)
    }

    func testMermaidRendersVisibleSVGLabelsWithoutHTMLOrExternalAssets() async throws {
        let document = MarkdownDocument(blocks: [.codeBlock(language: "mermaid", code: "flowchart LR\nStartCheckpoint[StartCheckpoint] --> FinishCheckpoint[FinishCheckpoint]")])
        let session = try await MarkdownEnhancementSession.make()
        defer { session.close() }
        try await session.load(document)
        let result = try await session.object("""
        (() => {
          const host = document.querySelector('.mermaid-diagram');
          const svg = host.querySelector('svg');
          return { state: host.dataset.renderState, text: svg?.textContent,
            width: svg?.getBoundingClientRect().width, height: svg?.getBoundingClientRect().height,
            labels: Array.from(svg?.querySelectorAll('text') || []).filter(e => e.getBBox().width > 0).length,
            forbidden: host.querySelectorAll('foreignObject,script,iframe,image,a').length };
        })()
        """)
        XCTAssertEqual(result["state"] as? String, "ready")
        XCTAssertTrue((result["text"] as? String)?.contains("StartCheckpoint") == true)
        XCTAssertTrue((result["text"] as? String)?.contains("FinishCheckpoint") == true)
        XCTAssertGreaterThan(result["width"] as? Double ?? 0, 50)
        XCTAssertGreaterThan(result["height"] as? Double ?? 0, 20)
        XCTAssertGreaterThanOrEqual(result["labels"] as? Int ?? 0, 2, "Visible SVG text must survive strict sanitization.")
        XCTAssertEqual(result["forbidden"] as? Int, 0)
    }

    func testMalformedBlocksPreserveSourceAndDoNotStopLaterRendering() async throws {
        let invalidMath = #"\frac{broken"#
        let invalidDiagram = "this is not a diagram {{ broken"
        let document = MarkdownDocument(blocks: [
            .mathBlock(invalidMath), .codeBlock(language: "mermaid", code: invalidDiagram),
            .mathBlock(#"\sqrt{x}"#),
            .codeBlock(language: "mermaid", code: "flowchart TD\nRecoveryStart --> RecoveryEnd"),
            .codeBlock(language: "swift", code: "let recovery = true")
        ])
        let session = try await MarkdownEnhancementSession.make()
        defer { session.close() }
        try await session.load(document)
        let result = try await session.object("""
        ({ ready: document.documentElement.dataset.markdownReady,
          failures: document.querySelectorAll('[data-render-state=error]').length,
          sources: Array.from(document.querySelectorAll('[data-render-state=error] pre')).map(e => e.textContent),
          math: document.querySelectorAll('.math[data-render-state=ready] .katex').length,
          diagrams: document.querySelectorAll('.mermaid-diagram[data-render-state=ready] svg').length,
          highlighted: document.querySelectorAll('pre code .hljs-keyword').length })
        """)
        XCTAssertEqual(result["ready"] as? String, "true")
        XCTAssertEqual(result["failures"] as? Int, 2)
        XCTAssertEqual(result["sources"] as? [String], [invalidMath, invalidDiagram])
        XCTAssertEqual(result["math"] as? Int, 1)
        XCTAssertEqual(result["diagrams"] as? Int, 1)
        XCTAssertGreaterThan(result["highlighted"] as? Int ?? 0, 0)
    }

    func testHostileSourceAndDiagramDirectivesCannotExecuteOrEnableNavigation() async throws {
        let attack = "globalThis.__markdownAttack = true"
        let document = MarkdownDocument(blocks: [
            .codeBlock(language: "html", code: "<script>\(attack)</script><img src='https://example.invalid/leak' onerror='\(attack)'>"),
            .mathBlock(#"\href{javascript:globalThis.__markdownAttack=true}{unsafe}"#),
            .mathBlock(#"\includegraphics{https://example.invalid/math.png}"#),
            .codeBlock(language: "mermaid", code: """
            %%{init: {"securityLevel":"loose", "htmlLabels":true}}%%
            flowchart LR
            A[Unsafe] --> B[Target]
            click A "javascript:globalThis.__markdownAttack=true"
            """),
            .codeBlock(language: "mermaid", code: "flowchart LR\nSafeStart --> SafeEnd\nclick SafeStart \"https://example.invalid/navigation\"")
        ])
        let session = try await MarkdownEnhancementSession.make()
        defer { session.close() }
        try await session.load(document)
        let result = try await session.object(#"""
        ({ executed: globalThis.__markdownAttack === true,
          activeURLs: Array.from(document.querySelectorAll('main *')).flatMap(e =>
            Array.from(e.attributes).filter(a => /^(?:xlink:)?(?:href|src)$/i.test(a.name) && /^(?:https?:|javascript:|data:text\/html)/i.test(a.value)).map(a => a.value)),
          handlers: Array.from(document.querySelectorAll('main *')).flatMap(e => Array.from(e.attributes).filter(a => /^on/i.test(a.name)).map(a => a.name)),
          sourceScripts: document.querySelectorAll('main script').length,
          directiveRejected: document.querySelector('.mermaid-diagram').dataset.renderState,
          laterDiagram: document.querySelectorAll('.mermaid-diagram')[1].dataset.renderState,
          security: MarkdownLibraries.mermaid.mermaidAPI.getConfig().securityLevel,
          remoteRequests: performance.getEntriesByType('resource').filter(e => /^https?:/i.test(e.name)).length
        })
        """#)
        XCTAssertEqual(result["executed"] as? Bool, false)
        XCTAssertEqual(result["activeURLs"] as? [String], [])
        XCTAssertEqual(result["handlers"] as? [String], [])
        XCTAssertEqual(result["sourceScripts"] as? Int, 0)
        XCTAssertEqual(result["directiveRejected"] as? String, "error")
        XCTAssertEqual(result["laterDiagram"] as? String, "ready")
        XCTAssertEqual(result["security"] as? String, "strict")
        XCTAssertEqual(result["remoteRequests"] as? Int, 0)
    }

    func testPDFContainsRenderedFormulaAndDiagramPixelsInsteadOfSource() async throws {
        let formula = MarkdownDocument(blocks: [.mathBlock(#"\frac{x + 1}{y + 2} + \sqrt{z}"#)])
        let formulaURL = try await PDFExportService().export(markdown: formula, title: "Formula")
        defer { PDFExportService.removeExport(at: formulaURL) }
        let formulaPDF = try XCTUnwrap(PDFDocument(url: formulaURL))
        XCTAssertEqual(formulaPDF.pageCount, 1)
        XCTAssertFalse(formulaPDF.string?.contains(#"\frac"#) == true)
        XCTAssertGreaterThan(try darkPixelCount(in: XCTUnwrap(formulaPDF.page(at: 0))), 60, "A rendered equation must leave actual ink in the PDF.")

        let diagram = MarkdownDocument(blocks: [.codeBlock(language: "mermaid", code: "flowchart LR\nStartCheckpoint --> FinishCheckpoint")])
        let diagramURL = try await PDFExportService().export(markdown: diagram, title: "Diagram")
        defer { PDFExportService.removeExport(at: diagramURL) }
        let diagramPDF = try XCTUnwrap(PDFDocument(url: diagramURL))
        XCTAssertEqual(diagramPDF.pageCount, 1)
        XCTAssertTrue(diagramPDF.string?.contains("StartCheckpoint") == true)
        XCTAssertTrue(diagramPDF.string?.contains("FinishCheckpoint") == true)
        XCTAssertFalse(diagramPDF.string?.contains("flowchart LR") == true)
        XCTAssertGreaterThan(try darkPixelCount(in: XCTUnwrap(diagramPDF.page(at: 0))), 150)
    }

    func testOversizedDisplayFormulaFitsPrintedPageAndKeepsItsFinalTermVisible() async throws {
        let terms = (1...24).map { "a_{\($0)}" }.joined(separator: " + ")
        let source = #"\underbrace{\#(terms) + \text{EndOfWideFormula}}_{\text{WideResult}}"#
        let document = MarkdownDocument(blocks: [.mathBlock(source)])
        let session = try await MarkdownEnhancementSession.make()
        defer { session.close() }
        // Match the viewport used by the production offscreen A4 exporter.
        session.webView.frame = PDFExportService.pageBounds
        session.webView.layoutIfNeeded()
        try await session.load(document, forPrinting: true)
        let geometry = try await session.object("""
        (() => {
          const main = document.querySelector('main').getBoundingClientRect();
          const math = document.querySelector('.math-display .katex').getBoundingClientRect();
          return { mainWidth: main.width, leftOverflow: main.left - math.left,
            rightOverflow: math.right - main.right, mathWidth: math.width, mathHeight: math.height,
            ready: document.querySelector('.math-display').dataset.renderState };
        })()
        """)
        XCTAssertEqual(geometry["ready"] as? String, "ready")
        XCTAssertEqual(try XCTUnwrap(geometry["mainWidth"] as? Double),
                       Double(PDFExportService.pageBounds.width - 72), accuracy: 1)
        XCTAssertLessThanOrEqual(geometry["leftOverflow"] as? Double ?? .infinity, 1)
        XCTAssertLessThanOrEqual(geometry["rightOverflow"] as? Double ?? .infinity, 1)
        XCTAssertGreaterThan(geometry["mathWidth"] as? Double ?? 0, 100)
        XCTAssertGreaterThan(geometry["mathHeight"] as? Double ?? 0, 3)

        let url = try await PDFExportService().export(markdown: document, title: "Wide formula")
        defer { PDFExportService.removeExport(at: url) }
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(pdf.pageCount, 1)
        let page = try XCTUnwrap(pdf.page(at: 0))
        let compactText = (pdf.string ?? "").filter { !$0.isWhitespace }
        XCTAssertTrue(compactText.contains("WideResult"), "The underbrace annotation must remain in the export.")
        XCTAssertTrue(compactText.contains("EndOfWideFormula"), "The final term must not disappear off the right edge.")
        XCTAssertFalse(compactText.contains(#"\underbrace"#), "The PDF must contain the rendered equation, not its fallback source.")
        let end = try XCTUnwrap(pdf.findString("EndOfWideFormula", withOptions: []).first)
        let endBounds = end.bounds(for: page)
        XCTAssertGreaterThan(endBounds.width, 0)
        XCTAssertGreaterThanOrEqual(endBounds.minX, 34)
        XCTAssertLessThanOrEqual(endBounds.maxX, page.bounds(for: .mediaBox).maxX - 34)
        XCTAssertGreaterThan(try darkPixelCount(in: page, bounds: endBounds.insetBy(dx: -1, dy: -1)), 3,
                             "The final term must have visible raster ink; invisible PDF text is insufficient.")
    }

    func testLongInlineFormulasFitPrintedTableCellsIncludingNestedEmphasis() async throws {
        let terms = (1...10).map { "a_{\($0)}" }.joined(separator: " + ")
        let plainFormula = #"\underbrace{\#(terms) + \text{PlainCellEnd}}_{\text{PlainResult}}"#
        let emphasizedFormula = #"\underbrace{\#(terms) + \text{StrongCellEnd}}_{\text{StrongResult}}"#
        let document = MarkdownRenderService().render(markdown: """
        | Formula | Reference |
        | --- | --- |
        | $\(plainFormula)$ | PlainNeighbor |
        | **$\(emphasizedFormula)$** | StrongNeighbor |
        """)
        let session = try await MarkdownEnhancementSession.make()
        defer { session.close() }
        session.webView.frame = PDFExportService.pageBounds
        session.webView.layoutIfNeeded()
        try await session.load(document, forPrinting: true)
        let geometry = try await session.object("""
        (() => ({
          tableLayout: getComputedStyle(document.querySelector('table')).tableLayout,
          cells: Array.from(document.querySelectorAll('tbody tr')).map(row => {
            const cell = row.cells[0];
            const source = cell.querySelector('.math');
            const formula = source.querySelector('.katex').getBoundingClientRect();
            const bounds = cell.getBoundingClientRect();
            const css = getComputedStyle(cell);
            const left = bounds.left + parseFloat(css.borderLeftWidth || 0) + parseFloat(css.paddingLeft || 0);
            const right = bounds.right - parseFloat(css.borderRightWidth || 0) - parseFloat(css.paddingRight || 0);
            return { state: source.dataset.renderState, parent: source.parentElement.tagName,
              leftOverflow: left - formula.left, rightOverflow: formula.right - right,
              width: formula.width, height: formula.height,
              fontSize: parseFloat(getComputedStyle(source).fontSize), cellFontSize: parseFloat(css.fontSize) };
          })
        }))()
        """)
        XCTAssertEqual(geometry["tableLayout"] as? String, "fixed", "Fit formulas against the eventual printed column widths.")
        let cells = try XCTUnwrap(geometry["cells"] as? [[String: Any]])
        XCTAssertEqual(cells.count, 2)
        XCTAssertEqual(cells.map { $0["parent"] as? String }, ["TD", "STRONG"], "Exercise both direct and styled inline formulas.")
        for cell in cells {
            XCTAssertEqual(cell["state"] as? String, "ready")
            XCTAssertLessThanOrEqual(cell["leftOverflow"] as? Double ?? .infinity, 1)
            XCTAssertLessThanOrEqual(cell["rightOverflow"] as? Double ?? .infinity, 1)
            XCTAssertGreaterThan(cell["width"] as? Double ?? 0, 80)
            XCTAssertGreaterThan(cell["height"] as? Double ?? 0, 3)
            XCTAssertLessThan(try XCTUnwrap(cell["fontSize"] as? Double),
                              try XCTUnwrap(cell["cellFontSize"] as? Double),
                              "The deliberately wide expression must actually be fitted, not merely measured through a clipped box.")
        }

        let url = try await PDFExportService().export(markdown: document, title: "Formula table")
        defer { PDFExportService.removeExport(at: url) }
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(pdf.pageCount, 1)
        let page = try XCTUnwrap(pdf.page(at: 0))
        let compactText = (pdf.string ?? "").filter { !$0.isWhitespace }
        XCTAssertFalse(compactText.contains(#"\underbrace"#), "Print the equations rather than fallback LaTeX.")
        for (endMarker, resultMarker, neighborMarker) in [
            ("PlainCellEnd", "PlainResult", "PlainNeighbor"),
            ("StrongCellEnd", "StrongResult", "StrongNeighbor")
        ] {
            XCTAssertTrue(compactText.contains(resultMarker), "Keep the formula's underbrace annotation.")
            let end = try XCTUnwrap(pdf.findString(endMarker, withOptions: []).first)
            let neighbor = try XCTUnwrap(pdf.findString(neighborMarker, withOptions: []).first)
            let endBounds = end.bounds(for: page)
            let neighborBounds = neighbor.bounds(for: page)
            XCTAssertGreaterThan(endBounds.width, 0)
            XCTAssertGreaterThanOrEqual(endBounds.minX, 34)
            XCTAssertLessThanOrEqual(endBounds.maxX, neighborBounds.minX - 4,
                                     "The final formula term must stay clear of the next column's content.")
            XCTAssertLessThanOrEqual(endBounds.maxX, page.bounds(for: .mediaBox).maxX - 34)
            XCTAssertGreaterThan(try darkPixelCount(in: page, bounds: endBounds.insetBy(dx: -1, dy: -1)), 3,
                                 "Each cell's final formula term must produce visible PDF pixels, not just invisible text.")
        }
    }

    func testLongEnhancedPDFKeepsFinalPageAndOmitsCopyControls() async throws {
        let paragraphs = (1...95).map { "Paragraph \($0): all of this offline report must survive export." }.joined(separator: "\n\n")
        let document = MarkdownRenderService().render(markdown: #"""
        # Enhanced report

        ```swift
        let exportedValue = 42
        ```

        $$
        \frac{1}{2}
        $$

        ```mermaid
        flowchart LR
        ExportStart --> ExportEnd
        ```

        \#(paragraphs)

        FinalEnhancedPDFSentinel
        """#)
        let session = try await MarkdownEnhancementSession.make()
        defer { session.close() }
        try await session.load(document, forPrinting: true)
        let chrome = try await session.webView.evaluateJavaScript("document.querySelectorAll('.copy-code').length") as? Int
        XCTAssertEqual(chrome, 0)
        let url = try await PDFExportService().export(markdown: document, title: "Enhanced report")
        defer { PDFExportService.removeExport(at: url) }
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThan(pdf.pageCount, 2)
        XCTAssertTrue(pdf.string?.contains("let exportedValue = 42") == true)
        XCTAssertTrue(pdf.string?.contains("ExportStart") == true)
        XCTAssertTrue(pdf.string?.contains("ExportEnd") == true)
        let lastPage = try XCTUnwrap(pdf.page(at: pdf.pageCount - 1))
        XCTAssertTrue(lastPage.string?.contains("FinalEnhancedPDFSentinel") == true)
        XCTAssertFalse(pdf.string?.contains(MarkdownEnhancementStrings.copy) == true)
        XCTAssertFalse(pdf.string?.contains(MarkdownEnhancementStrings.copied) == true)
    }

    func testResourceSchemeRejectsTraversalOtherOriginsAndNonRuntimeFiles() throws {
        for path in ["markdown-libraries.min.js", "katex.min.css", "fonts/KaTeX_Main-Regular.woff2"] {
            let url = try XCTUnwrap(URL(string: MarkdownWebResources.origin + "/" + path))
            let file = try XCTUnwrap(MarkdownWebResources.resourceURL(for: url))
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "Bundled runtime asset missing: \(path)")
        }
        for source in [
            "markdown-resource://bundle/%2e%2e/private.js", "markdown-resource://bundle/%252e%252e/private.js",
            "markdown-resource://bundle/fonts%5cprivate.js", "markdown-resource://bundle/file.js?path=secret",
            "markdown-resource://other/markdown-libraries.min.js", "https://bundle/markdown-libraries.min.js",
            "markdown-resource://bundle/manifest.json", "markdown-resource://bundle/THIRD-PARTY-LICENSES.txt"
        ] {
            XCTAssertNil(MarkdownWebResources.resourceURL(for: try XCTUnwrap(URL(string: source))), source)
        }
    }

    private func darkPixelCount(in page: PDFPage, bounds: CGRect) throws -> Int {
        let thumbnail = page.thumbnail(of: CGSize(width: 1190, height: 1684), for: .mediaBox)
        let image = try XCTUnwrap(thumbnail.cgImage)
        let pageBounds = page.bounds(for: .mediaBox)
        let scaleX = CGFloat(image.width) / pageBounds.width
        let scaleY = CGFloat(image.height) / pageBounds.height
        // PDF coordinates start at the bottom-left; image pixels start at the top-left.
        let pixelBounds = CGRect(x: (bounds.minX - pageBounds.minX) * scaleX,
                                 y: (pageBounds.maxY - bounds.maxY) * scaleY,
                                 width: bounds.width * scaleX, height: bounds.height * scaleY).integral
        let crop = try XCTUnwrap(image.cropping(to: pixelBounds.intersection(
            CGRect(x: 0, y: 0, width: image.width, height: image.height))))
        var pixels = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: crop.width, height: crop.height,
            bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        return stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0] < 150 && pixels[$0 + 1] < 150 && pixels[$0 + 2] < 150 && pixels[$0 + 3] > 200
        }.count
    }

    private func darkPixelCount(in page: PDFPage) throws -> Int {
        let thumbnail = page.thumbnail(of: CGSize(width: 595, height: 842), for: .mediaBox)
        let image = try XCTUnwrap(thumbnail.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0] < 150 && pixels[$0 + 1] < 150 && pixels[$0 + 2] < 150 && pixels[$0 + 3] > 200
        }.count
    }
}

@MainActor
private final class MarkdownEnhancementSession: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let webView: WKWebView
    private let window: UIWindow
    private weak var previousKeyWindow: UIWindow?
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    private(set) var messages: [[String: Any]] = []

    static func make() async throws -> MarkdownEnhancementSession {
        let configuration = try await MarkdownWebResources.makeConfiguration()
        return try MarkdownEnhancementSession(configuration: configuration)
    }

    private init(configuration: WKWebViewConfiguration) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }, "Runtime tests require an active app scene.")
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 700), configuration: configuration)
        window = UIWindow(windowScene: scene)
        previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        super.init()
        configuration.userContentController.add(self, contentWorld: .page, name: "markdownAction")
        window.frame = scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = .light
        let controller = UIViewController()
        controller.view.addSubview(webView)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        webView.layoutIfNeeded()
        webView.navigationDelegate = self
    }

    func load(_ document: MarkdownDocument, forPrinting: Bool = false) async throws {
        let html = MarkdownEnhancedHTMLRenderer().render(document, title: "Markdown runtime test", forPrinting: forPrinting)
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            timeout = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(30))
                    self?.finish(.failure(MarkdownEnhancementTestError.timedOut))
                } catch {}
            }
            webView.loadHTMLString(html, baseURL: nil)
        }
        try await MarkdownWebResources.waitUntilReady(in: webView)
    }

    func object(_ script: String) async throws -> [String: Any] {
        let result = try await webView.evaluateJavaScript(script)
        return try XCTUnwrap(result as? [String: Any])
    }

    func waitForCopy() async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while messages.isEmpty {
            guard ContinuousClock.now < deadline else { throw MarkdownEnhancementTestError.timedOut }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func close() {
        finish(.failure(CancellationError()))
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "markdownAction", contentWorld: .page)
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let value = message.body as? [String: Any] { messages.append(value) }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(.success(())) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    private func finish(_ result: Result<Void, Error>) {
        timeout?.cancel()
        timeout = nil
        continuation?.resume(with: result)
        continuation = nil
    }
}

private enum MarkdownEnhancementTestError: Error { case timedOut }
