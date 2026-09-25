import Foundation
import XCTest
@testable import HTMLMarkdownPreviewer

final class PastedDocumentImportServiceTests: XCTestCase {
    func testSuggestsHTMLForDocumentsFragmentsAndWholeHTMLFences() {
        let htmlExamples = [
            "<!DOCTYPE html><html><body>Report</body></html>",
            "\u{FEFF}  <!-- Generated report -->\n<DIV class=\"report\">Hello</DIV>",
            "<h2>Summary</h2><p>All done.</p>",
            "```html\n<h1>Report</h1>\n```",
            "~~~HTML\r\n<section>Report</section>\r\n~~~",
            "```\n<table><tr><td>1</td></tr></table>\n```"
        ]
        for text in htmlExamples {
            XCTAssertEqual(PastedDocumentImportService.suggestedFormat(for: text), .html, text)
        }

        for text in ["# Report\n\nHello", "Use <div> in HTML.", "```swift\nlet x = 1\n```", "```markdown\n<div>Example</div>\n```"] {
            XCTAssertEqual(PastedDocumentImportService.suggestedFormat(for: text), .markdown, text)
        }
    }

    func testRemovesOnlyWholeMatchingFencesAndRespectsManualFormat() throws {
        let html = "<h1>Report</h1>\n<p>Ready</p>"
        let fencedHTML = "```html\n\(html)\n```"
        let preparedHTML = try PastedDocumentImportService.prepare(text: fencedHTML, name: "Report", format: .html)
        XCTAssertEqual(preparedHTML.content, html)
        XCTAssertEqual(preparedHTML.filename, "Report.html")

        let showCode = try PastedDocumentImportService.prepare(text: fencedHTML, name: "Example", format: .markdown)
        XCTAssertEqual(showCode.content, fencedHTML, "Choosing Markdown should preserve an HTML code example")

        let markdown = "# Notes\n\n```swift\nlet value = 1\n```"
        let fencedMarkdown = "````markdown\n\(markdown)\n````"
        XCTAssertEqual(
            try PastedDocumentImportService.prepare(text: fencedMarkdown, name: "Notes", format: .markdown).content,
            markdown
        )

        let separateBlocks = "```html\n<p>One</p>\n```\n\nExplanation\n\n```html\n<p>Two</p>\n```"
        XCTAssertEqual(PastedDocumentImportService.suggestedFormat(for: separateBlocks), .markdown)
        XCTAssertEqual(
            try PastedDocumentImportService.prepare(text: separateBlocks, name: "Examples", format: .markdown).content,
            separateBlocks
        )
    }

    func testPreservesMarkdownIndentationAndHardBreaks() throws {
        let markdown = "    indented code\r\n\r\nFirst line  \r\nSecond line\r\n"
        let prepared = try PastedDocumentImportService.prepare(text: markdown, name: "Notes.md", format: .markdown)
        XCTAssertEqual(prepared.content, "    indented code\n\nFirst line  \nSecond line\n")
        XCTAssertEqual(prepared.filename, "Notes.md")
    }

    func testRejectsEmptyURLAndOversizedTextWithoutRejectingMarkdownLinks() throws {
        for text in ["", " \n\t ", "\u{FEFF}\n", "```html\n\n```"] {
            XCTAssertThrowsError(try PastedDocumentImportService.prepare(text: text, name: "", format: .html)) {
                XCTAssertEqual($0 as? PastedDocumentError, .emptyContent)
            }
        }

        for text in ["https://example.com/report", "  www.example.com\n", "file:///tmp/report.html", "mailto:person@example.com"] {
            XCTAssertThrowsError(try PastedDocumentImportService.prepare(text: text, name: "", format: .markdown)) {
                XCTAssertEqual($0 as? PastedDocumentError, .webAddressOnly)
            }
        }
        let link = "[Read the report](https://example.com/report)"
        XCTAssertEqual(
            try PastedDocumentImportService.prepare(text: link, name: "Link", format: .markdown).content,
            link
        )

        let maximum = PastedDocumentImportService.maximumUTF8Bytes
        let boundary = String(repeating: "x", count: maximum)
        XCTAssertNoThrow(try PastedDocumentImportService.prepare(text: boundary, name: "Large", format: .markdown))
        let multibyteOverflow = String(repeating: "界", count: maximum / 3) + "🙂"
        XCTAssertLessThan(multibyteOverflow.count, maximum)
        XCTAssertThrowsError(try PastedDocumentImportService.prepare(text: multibyteOverflow, name: "Large", format: .markdown)) {
            XCTAssertEqual($0 as? PastedDocumentError, .contentTooLarge)
        }
    }

    func testFilenameCannotEscapeImportDirectoryAndKeepsUnicode() throws {
        let prepared = try PastedDocumentImportService.prepare(
            text: "# 内容",
            name: "../../週報:計画\\notes\u{0000}.HTML",
            format: .markdown
        )
        XCTAssertTrue(prepared.filename.hasSuffix(".md"))
        XCTAssertFalse(prepared.filename.contains("/"))
        XCTAssertFalse(prepared.filename.contains("\\"))
        XCTAssertFalse(prepared.filename.contains(":"))
        XCTAssertFalse(prepared.filename.contains("\u{0000}"))
        XCTAssertTrue(prepared.filename.contains("週報"))
        XCTAssertFalse(prepared.filename.hasSuffix(".HTML.md"))

        let longName = try PastedDocumentImportService.prepare(
            text: "Notes", name: String(repeating: "研究🙂", count: 200), format: .html
        ).filename
        XCTAssertLessThanOrEqual(longName.utf8.count, 165)
        XCTAssertTrue(longName.hasSuffix(".html"))
        let defaultName = try PastedDocumentImportService.prepare(text: "Notes", name: "  ", format: .markdown).filename
        XCTAssertEqual(defaultName, PasteStrings.defaultDocumentName + ".md")
    }

    func testHTMLImportCreatesRecentDocumentInInteractiveModeAndRemovesTemporaryFile() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let store = DocumentLibraryStore(rootURL: workspace.appendingPathComponent("library"))
        let temporaryRoot = workspace.appendingPathComponent("paste-inputs")
        let service = PastedDocumentImportService(store: store, temporaryRootURL: temporaryRoot)
        let html = "<h1>Weekly report</h1><script>window.example = true</script><img src=\"https://example.com/a.png\">"

        let document = try service.importDocument(text: "```html\n\(html)\n```", name: "Weekly report.html", format: .html)

        XCTAssertEqual(document.originalFilename, "Weekly report.html")
        XCTAssertEqual(document.displayName, "Weekly report")
        XCTAssertEqual(document.type, .html)
        XCTAssertEqual(document.importSource, .pastedText)
        XCTAssertEqual(document.preferredPreviewMode, .interactive)
        XCTAssertEqual(document.externalURLCount, 1)
        XCTAssertEqual(try store.loadDocuments(), [document])
        XCTAssertEqual(try String(contentsOf: store.originalFileURL(for: document), encoding: .utf8), html)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(at: temporaryRoot, includingPropertiesForKeys: nil),
            []
        )
    }

    func testMarkdownImportPreservesTableContentAndInvalidInputCreatesNoDocument() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let store = DocumentLibraryStore(rootURL: workspace.appendingPathComponent("library"))
        let service = PastedDocumentImportService(store: store, temporaryRootURL: workspace.appendingPathComponent("paste-inputs"))
        XCTAssertThrowsError(try service.importDocument(text: "https://example.com", name: "URL", format: .markdown))
        XCTAssertEqual(try store.loadDocuments(), [])

        let markdown = "# Summary\n\n| Status | Count |\n| --- | ---: |\n| Done | 3 |"
        let document = try service.importDocument(text: markdown, name: "Summary", format: .markdown)
        XCTAssertEqual(document.type, .markdown)
        XCTAssertEqual(document.importSource, .pastedText)
        XCTAssertEqual(document.preferredPreviewMode, .safePreview)
        XCTAssertEqual(document.originalFilename, "Summary.md")
        XCTAssertEqual(try String(contentsOf: store.entryFileURL(for: document), encoding: .utf8), markdown)
        XCTAssertEqual(try store.loadDocuments(), [document])
    }

    private func makeWorkspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PastedDocumentImportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
