import PDFKit
import UIKit
import WebKit
import XCTest
@testable import HTMLMarkdownPreviewer

@MainActor
final class PDFExportServiceTests: XCTestCase {
    func testHTMLExportContainsMultiplePagesAndLastPageText() async throws {
        let webView = try await loadHTML("""
        <html><style>section { break-after: page; height: 500px; }</style><body>
        <section>First page marker</section><section>Second page marker</section>
        <section>Final page marker</section></body></html>
        """)
        let url = try await PDFExportService().export(webView: webView, title: "Report")
        defer { PDFExportService.removeExport(at: url) }
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThanOrEqual(pdf.pageCount, 3)
        XCTAssertTrue(pdf.string?.contains("First page marker") == true)
        XCTAssertTrue(pdf.string?.contains("Final page marker") == true)
        let bounds = try XCTUnwrap(pdf.page(at: 0)).bounds(for: .mediaBox)
        XCTAssertEqual(bounds.width, PDFExportService.pageBounds.width, accuracy: 1)
        XCTAssertEqual(bounds.height, PDFExportService.pageBounds.height, accuracy: 1)
        XCTAssertEqual(url.lastPathComponent, "Report.pdf")
    }

    func testHTMLExportPreservesLiveDOMAndLocalImage() async throws {
        let root = try makeTemporaryDirectory()
        let html = root.appendingPathComponent("index.html")
        try "body { font-size: 24px; }".write(to: root.appendingPathComponent("style.css"), atomically: true, encoding: .utf8)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        try XCTUnwrap(image.pngData()).write(to: root.appendingPathComponent("image.png"))
        try """
        <html><head><link rel="stylesheet" href="style.css"></head><body>
        <p id="value">Before interaction</p><img src="image.png" width="100" height="100">
        </body></html>
        """.write(to: html, atomically: true, encoding: .utf8)
        let configuration = try await HTMLPreviewConfiguration.make(mode: .interactive)
        let webView = WKWebView(frame: PDFExportService.pageBounds, configuration: configuration)
        let observer = PDFTestLoadObserver()
        webView.navigationDelegate = observer
        try await observer.load { webView.loadFileURL(html, allowingReadAccessTo: root) }
        _ = try await webView.evaluateJavaScript("document.getElementById('value').textContent = 'After interaction'")
        let data = try await PDFExportService().pdfData(webView: webView, title: "Live report")
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertTrue(pdf.string?.contains("After interaction") == true)
        XCTAssertFalse(pdf.string?.contains("Before interaction") == true)

        let page = try XCTUnwrap(pdf.page(at: 0))
        let thumbnail = page.thumbnail(of: CGSize(width: 300, height: 424), for: .mediaBox)
        let cgImage = try XCTUnwrap(thumbnail.cgImage)
        var pixels = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: cgImage.width, height: cgImage.height,
            bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        let redPixels = stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0] > 180 && pixels[$0 + 1] < 80 && pixels[$0 + 2] < 80
        }.count
        XCTAssertGreaterThan(redPixels, 100, "The local image must remain visible in the PDF.")
    }

    func testHTMLPDFPreservesDarkBackgroundWithoutChangingPreview() async throws {
        let webView = try await loadHTML("""
        <!doctype html><html><head><style>
        body { margin: 0; min-height: 700px; background: rgb(18, 52, 86); color: white; }
        p { margin: 0; padding: 30px; font: 32px sans-serif; }
        </style></head><body><p>White text on a dark report</p></body></html>
        """)
        let previewStateScript = """
        JSON.stringify({
            html: document.documentElement.outerHTML,
            background: getComputedStyle(document.body).backgroundColor,
            color: getComputedStyle(document.body).color,
            scrollX: window.scrollX,
            scrollY: window.scrollY
        })
        """
        let stateBefore = try await webView.evaluateJavaScript(
            previewStateScript
        ) as? String
        XCTAssertNotNil(stateBefore)

        let data = try await PDFExportService().pdfData(webView: webView, title: "Dark report")

        let stateAfter = try await webView.evaluateJavaScript(
            previewStateScript
        ) as? String
        XCTAssertEqual(stateAfter, stateBefore, "Export must remove its temporary style and preserve the preview DOM, colors, and scroll position.")

        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertTrue(pdf.string?.contains("White text on a dark report") == true)
        let page = try XCTUnwrap(pdf.page(at: 0))
        let thumbnail = page.thumbnail(of: CGSize(width: 300, height: 424), for: .mediaBox)
        let cgImage = try XCTUnwrap(thumbnail.cgImage)
        var pixels = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: cgImage.width, height: cgImage.height,
            bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        let darkBluePixels = stride(from: 0, to: pixels.count, by: 4).filter {
            abs(Int(pixels[$0]) - 18) <= 12
                && abs(Int(pixels[$0 + 1]) - 52) <= 12
                && abs(Int(pixels[$0 + 2]) - 86) <= 12
        }.count
        XCTAssertGreaterThan(darkBluePixels, 1_000, "Printing must preserve the dark blue background instead of replacing it with white.")
    }

    func testMarkdownPDFIncludesTableAndEndOfLongDocument() async throws {
        let paragraphs = (1...90).map { "Paragraph \($0): readable report content." }.joined(separator: "\n\n")
        let markdown = MarkdownRenderService().render(markdown: """
        # Markdown Report

        | Feature | Status |
        | :--- | ---: |
        | **Table export** | Available |

        \(paragraphs)

        Final markdown marker
        """)
        let url = try await PDFExportService().export(markdown: markdown, title: "Notes")
        let directory = url.deletingLastPathComponent()
        defer { PDFExportService.removeExport(at: url) }
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThan(pdf.pageCount, 1)
        for text in ["Feature", "Table export", "Available", "Final markdown marker"] {
            XCTAssertTrue(pdf.string?.contains(text) == true, "PDF missing \(text)")
        }
        PDFExportService.removeExport(at: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testZIPOriginalCanBeSharedAndReimportedWithAllAssets() throws {
        let root = try makeTemporaryDirectory()
        let css = Data("body { color: red; }".utf8)
        let image = Data([1, 2, 3, 4])
        let archive = try makeArchive(files: [
            "index.html": Data("<link rel='stylesheet' href='assets/style.css'><img src='images/chart.png'>".utf8),
            "assets/style.css": css,
            "images/chart.png": image
        ])
        let store = DocumentLibraryStore(rootURL: root.appendingPathComponent("sender"))
        let document = try DocumentImportService(store: store).importDocument(from: archive, source: .fileImporter)
        let sharedURL = store.originalFileURL(for: document)
        XCTAssertEqual(sharedURL.pathExtension, "zip")
        XCTAssertEqual(try Data(contentsOf: sharedURL), try Data(contentsOf: archive))
        let receiver = try ZipImportService().importArchive(from: sharedURL, to: root.appendingPathComponent("receiver"))
        XCTAssertEqual(try Data(contentsOf: receiver.rootURL.appendingPathComponent("assets/style.css")), css)
        XCTAssertEqual(try Data(contentsOf: receiver.rootURL.appendingPathComponent("images/chart.png")), image)
    }

    private func loadHTML(_ html: String) async throws -> WKWebView {
        let configuration = try await HTMLPreviewConfiguration.make(mode: .safePreview)
        let webView = WKWebView(frame: PDFExportService.pageBounds, configuration: configuration)
        let observer = PDFTestLoadObserver()
        webView.navigationDelegate = observer
        try await observer.load { webView.loadHTMLString(html, baseURL: nil) }
        return webView
    }
}

@MainActor
private final class PDFTestLoadObserver: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    func load(_ action: () -> Void) async throws {
        try await withCheckedThrowingContinuation {
            continuation = $0
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
