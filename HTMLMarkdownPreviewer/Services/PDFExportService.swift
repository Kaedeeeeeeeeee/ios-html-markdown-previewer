import UIKit
import WebKit

enum PDFExportError: LocalizedError {
    case previewNotReady
    case noPages
    case loadTimedOut

    var errorDescription: String? {
        switch self {
        case .previewNotReady: AppStrings.Errors.pdfPreviewNotReady
        case .noPages: AppStrings.Errors.pdfNoPages
        case .loadTimedOut: AppStrings.Errors.pdfLoadTimedOut
        }
    }
}

/// Prints the loaded HTML DOM, including its current interactive state, without reloading it.
@MainActor
struct PDFExportService {
    nonisolated static let pageBounds = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)

    func export(webView: WKWebView, title: String) async throws -> URL {
        guard !webView.isLoading else { throw PDFExportError.previewNotReady }
        let data = try await pdfData(webView: webView, title: title)
        return try writePDF(data, title: title)
    }

    func export(markdown: MarkdownDocument, title: String) async throws -> URL {
        let configuration = try await HTMLPreviewConfiguration.make(mode: .safePreview)
        let webView = WKWebView(frame: Self.pageBounds, configuration: configuration)
        let loader = PDFWebViewLoader()
        webView.navigationDelegate = loader
        defer {
            webView.stopLoading()
            webView.navigationDelegate = nil
        }
        try await loader.load(
            html: MarkdownPrintHTMLRenderer().render(markdown, title: title),
            in: webView
        )
        try Task.checkCancellation()
        return try await export(webView: webView, title: title)
    }

    func pdfData(webView: WKWebView, title: String) async throws -> Data {
        // WebKit otherwise omits backgrounds and lightens text for paper printing.
        // Limit this temporary rule to print media; keep the source's own print layout.
        let styleID = "html-previewer-print-\(UUID().uuidString)"
        let insertStyle = """
        (() => {
            const style = document.createElement('style');
            style.id = '\(styleID)';
            style.textContent = '@media print { * { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; } }';
            document.documentElement.appendChild(style);
        })()
        """
        let removeStyle = "document.getElementById('\(styleID)')?.remove()"
        _ = try await webView.evaluateJavaScript(insertStyle)
        do {
            // Search decoration belongs to the reader, never to the exported document.
            _ = try await webView.callAsyncJavaScript(
                "globalThis.__htmlPreviewReading?.suspendHighlights(); return null;",
                arguments: [:], in: nil, contentWorld: HTMLReadingController.contentWorld
            )
            try Task.checkCancellation()
            let data = try renderPDF(webView: webView, title: title)
            _ = try? await webView.evaluateJavaScript(removeStyle)
            await resumeReadingHighlights(in: webView)
            return data
        } catch {
            _ = try? await webView.evaluateJavaScript(removeStyle)
            await resumeReadingHighlights(in: webView)
            throw error
        }
    }

    private func resumeReadingHighlights(in webView: WKWebView) async {
        _ = try? await webView.callAsyncJavaScript(
            "globalThis.__htmlPreviewReading?.resumeHighlights(); return null;",
            arguments: [:], in: nil, contentWorld: HTMLReadingController.contentWorld
        )
    }

    private func renderPDF(webView: WKWebView, title: String) throws -> Data {
        let renderer = DocumentPrintPageRenderer()
        renderer.addPrintFormatter(webView.viewPrintFormatter(), startingAtPageAt: 0)
        let pageCount = renderer.numberOfPages
        guard pageCount > 0 else { throw PDFExportError.noPages }
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: pageCount))

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: title]
        return UIGraphicsPDFRenderer(bounds: Self.pageBounds, format: format).pdfData { context in
            for page in 0..<pageCount {
                context.beginPage()
                renderer.drawPage(at: page, in: Self.pageBounds)
            }
        }
    }

    private func writePDF(_ data: Data, title: String) throws -> URL {
        try Task.checkCancellation()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HTMLPreviewerPDFExports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = String(title.prefix(120)).map { character in
            character == "/" || character == "\\" || character == ":" ? "-" : character
        }
        let trimmed = String(name).trimmingCharacters(in: .whitespacesAndNewlines)
        let fileURL = directory.appendingPathComponent(trimmed.isEmpty ? "Document" : trimmed)
            .appendingPathExtension("pdf")
        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func removeExport(at fileURL: URL) {
        let directory = fileURL.deletingLastPathComponent()
        guard directory.deletingLastPathComponent().lastPathComponent == "HTMLPreviewerPDFExports" else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class DocumentPrintPageRenderer: UIPrintPageRenderer {
    override var paperRect: CGRect { PDFExportService.pageBounds }
    override var printableRect: CGRect { paperRect.insetBy(dx: 36, dy: 36) }
}

@MainActor
private final class PDFWebViewLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?

    func load(html: String, in webView: WKWebView) async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                timeout = Task { [weak self] in
                    do {
                        try await Task.sleep(for: .seconds(20))
                        self?.finish(.failure(PDFExportError.loadTimedOut))
                    } catch {}
                }
                webView.loadHTMLString(html, baseURL: nil)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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
