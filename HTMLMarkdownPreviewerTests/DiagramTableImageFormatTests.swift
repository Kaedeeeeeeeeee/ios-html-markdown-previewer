import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import HTMLMarkdownPreviewer

final class DiagramTableImageFormatTests: XCTestCase {
    // MARK: Detection

    func testDetectsMermaidCSVAndSVGExtensions() {
        XCTAssertEqual(FileTypeDetector.documentType(forPath: "flow.mmd"), .mermaid)
        XCTAssertEqual(FileTypeDetector.documentType(forPath: "flow.MERMAID"), .mermaid)
        XCTAssertEqual(FileTypeDetector.documentType(forPath: "data.csv"), .csv)
        XCTAssertEqual(FileTypeDetector.documentType(forPath: "data.TSV"), .csv)
        XCTAssertEqual(FileTypeDetector.documentType(forPath: "logo.svg"), .svg)
    }

    func testDetectsMermaidCSVAndSVGTypes() {
        XCTAssertEqual(FileTypeDetector.documentType(for: SupportedDocumentTypes.mermaid), .mermaid)
        XCTAssertEqual(FileTypeDetector.documentType(for: .commaSeparatedText), .csv)
        XCTAssertEqual(FileTypeDetector.documentType(for: .tabSeparatedText), .csv)
        XCTAssertEqual(FileTypeDetector.documentType(for: .svg), .svg)
        for type in [SupportedDocumentTypes.mermaid, .commaSeparatedText, .tabSeparatedText, .svg] {
            XCTAssertTrue(ImportPickerScope.previewDocument.allowedContentTypes.contains(type), "\(type)")
        }
    }

    func testNewTypesOfferRenderedAndRawTextModes() {
        for type in [PreviewDocumentType.markdown, .mermaid, .csv, .svg] {
            XCTAssertTrue(type.offersRenderedAndSourceModes)
            XCTAssertEqual(PreviewMode.defaultMode(for: type), .safePreview)
        }
        XCTAssertFalse(PreviewDocumentType.html.offersRenderedAndSourceModes)
    }

    func testImportsKeepTypeAndLibraryFilter() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DocumentLibraryStore(rootURL: root.appendingPathComponent("Library"))
        let service = DocumentImportService(store: store)
        let samples: [(String, String, PreviewDocumentType, DocumentLibraryFilter)] = [
            ("Flow.mmd", "flowchart LR\nA --> B\n", .mermaid, .mermaid),
            ("Table.csv", "a,b\n1,2\n", .csv, .csv),
            ("Logo.svg", #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"/>"#, .svg, .svg)
        ]
        for (name, content, type, filter) in samples {
            let source = root.appendingPathComponent(name)
            try content.write(to: source, atomically: true, encoding: .utf8)
            let document = try service.importDocument(from: source, source: .externalOpen)
            XCTAssertEqual(document.type, type)
            XCTAssertEqual(document.entryDocumentType, type)
            XCTAssertEqual(filter.documents(in: [document], matching: ""), [document])
            XCTAssertEqual(DocumentLibraryFilter.markdown.documents(in: [document], matching: ""), [])
        }
        let reopened = try DocumentLibraryStore(rootURL: root.appendingPathComponent("Library")).loadDocuments()
        XCTAssertEqual(Set(reopened.map(\.type)), [.mermaid, .csv, .svg])
    }

    // MARK: Mermaid

    func testMermaidFileBecomesOneEnhancedDiagramBlock() {
        let document = MermaidDocumentRenderer().render(source: "\nflowchart TD\n  A --> B\n")
        XCTAssertEqual(document.blocks, [.codeBlock(language: "mermaid", code: "flowchart TD\n  A --> B")])
        XCTAssertTrue(document.requiresEnhancedRendering)
    }

    func testMermaidFileUnwrapsAMarkdownFence() {
        let document = MermaidDocumentRenderer().render(source: "```mermaid\nsequenceDiagram\n  A->>B: Hi\n```")
        XCTAssertEqual(document.blocks, [.codeBlock(language: "mermaid", code: "sequenceDiagram\n  A->>B: Hi")])
        XCTAssertEqual(MermaidDocumentRenderer.unwrappingFence("```python\nprint(1)\n```"), "```python\nprint(1)\n```")
    }

    func testEmptyMermaidFileExplainsItself() {
        XCTAssertEqual(MermaidDocumentRenderer().render(source: "  \n").blocks,
                       [.paragraph(AttributedString(FormatStrings.mermaidEmpty))])
    }

    // MARK: CSV

    func testParsesQuotedFieldsEscapedQuotesAndEmbeddedNewlines() {
        let text = "\u{FEFF}name,note,qty\r\n\"Smith, J\",\"said \"\"hi\"\"\nthen left\",3\r\n,,\n\nlast,,\n"
        XCTAssertEqual(CSVRenderService.parse(text, delimiter: ","), [
            ["name", "note", "qty"],
            ["Smith, J", "said \"hi\"\nthen left", "3"],
            ["", "", ""],
            ["last", "", ""]
        ])
    }

    func testParsesFileWithoutTrailingNewline() {
        XCTAssertEqual(CSVRenderService.parse("a,b\n1,\"2\"", delimiter: ","), [["a", "b"], ["1", "2"]])
    }

    func testDetectsDelimiter() {
        XCTAssertEqual(CSVRenderService.detectDelimiter(in: "a,b,c\n1,2,3"), ",")
        XCTAssertEqual(CSVRenderService.detectDelimiter(in: "name;price\n\"a, b\";1,5\nc;2"), ";")
        XCTAssertEqual(CSVRenderService.detectDelimiter(in: "a\tb\n1\t2"), "\t")
        XCTAssertEqual(CSVRenderService.detectDelimiter(in: "single column\nvalue"), ",")
        XCTAssertEqual(CSVRenderService.detectDelimiter(in: "Status (A|B|C|D|E),Count\nA,10"), ",")
        XCTAssertEqual(CSVRenderService.detectDelimiter(in: "a|b|c,d\n1|2|3,4\n5|6|7,8"), "|")
    }

    func testTSVExtensionAlwaysUsesTabs() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("t.tsv")
        try "a,b\tc\n1,2\t3\n".write(to: url, atomically: true, encoding: .utf8)
        let table = try XCTUnwrap(Self.table(in: CSVRenderService().render(fileURL: url)))
        XCTAssertEqual(table.header.map { String($0.characters) }, ["a,b", "c"])
    }

    func testRendersSummaryTableAndRightAlignsNumbers() throws {
        let document = CSVRenderService().render(text: "item,price,share\nTea,\"1,200.50\",12%\nCake,-3,\nShort\n")
        XCTAssertEqual(document.blocks.first,
                       .paragraph(AttributedString(FormatStrings.csvSummary(rows: 3, columns: 3))))
        let table = try XCTUnwrap(Self.table(in: document))
        XCTAssertEqual(table.columnAlignments, [.leading, .trailing, .trailing])
        XCTAssertEqual(table.rows.count, 3)
        XCTAssertEqual(table.rows[2].map { String($0.characters) }, ["Short", "", ""])
        XCTAssertFalse(document.requiresEnhancedRendering)
    }

    func testCellsAreNeverParsedAsMarkdownOrMath() throws {
        let document = CSVRenderService().render(text: "a,b\n**bold**,$x^2$\n<b>x</b>,[link](https://example.com)\n")
        let table = try XCTUnwrap(Self.table(in: document))
        XCTAssertEqual(table.rows.flatMap { $0.map { String($0.characters) } },
                       ["**bold**", "$x^2$", "<b>x</b>", "[link](https://example.com)"])
        XCTAssertFalse(document.requiresEnhancedRendering)
    }

    func testLongTablesShowFirstRowsAndSayHowManyAreHidden() throws {
        let total = CSVRenderService.maximumDisplayedRows + 25
        let text = "n\n" + (1...total).map(String.init).joined(separator: "\n")
        let document = CSVRenderService().render(text: text)
        let table = try XCTUnwrap(Self.table(in: document))
        XCTAssertEqual(table.rows.count, CSVRenderService.maximumDisplayedRows)
        XCTAssertEqual(document.blocks.last, .paragraph(AttributedString(
            FormatStrings.csvTruncated(shown: CSVRenderService.maximumDisplayedRows, total: total)
        )))
    }

    func testEmptyCSV() {
        XCTAssertEqual(CSVRenderService().render(text: "\n\n").blocks,
                       [.paragraph(AttributedString(FormatStrings.csvEmpty))])
    }

    // MARK: SVG

    @MainActor
    func testSVGPageEmbedsTheImageOnlyThroughADataURL() {
        let svg = Data(#"<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script><image href="https://example.com/x.png"/></svg>"#.utf8)
        let page = SVGPreviewView.page(svgData: svg, title: "a<b>\"c")
        XCTAssertTrue(page.contains("<img src=\"data:image/svg+xml;base64,\(svg.base64EncodedString())\""))
        XCTAssertTrue(page.contains("default-src 'none'; img-src data:"))
        XCTAssertFalse(page.contains("<script"))
        XCTAssertFalse(page.contains("example.com"))
        XCTAssertTrue(page.contains("<title>a&lt;b&gt;&quot;c</title>"))
    }

    // MARK: Samples

    func testSamplesRenderThroughTheNewReaders() throws {
        let mermaid = MermaidDocumentRenderer().render(source: BuiltInSampleProvider.mermaidSample)
        guard case .codeBlock(language: .some("mermaid"), code: let code)? = mermaid.blocks.first else { return XCTFail("\(mermaid.blocks)") }
        XCTAssertTrue(code.contains("flowchart TD"))

        let csv = CSVRenderService().render(text: BuiltInSampleProvider.csvSample)
        let table = try XCTUnwrap(Self.table(in: csv))
        XCTAssertEqual(table.header.count, 6)
        XCTAssertEqual(table.rows.count, 8)
        XCTAssertEqual(table.columnAlignments, [.leading, .leading, .trailing, .trailing, .trailing, .leading])
        XCTAssertEqual(String(table.rows[2][5].characters), "Found the root cause, then added a test")

        let svg = BuiltInSampleProvider.svgSample
        for forbidden in ["<script", "href", "<image", "<foreignObject", "url("] {
            XCTAssertFalse(svg.contains(forbidden), forbidden)
        }
        // <img> only draws well-formed XML.
        XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse())
    }

    private static func table(in document: MarkdownDocument) -> MarkdownTable? {
        for block in document.blocks {
            if case .table(let table) = block { return table }
        }
        return nil
    }
}

