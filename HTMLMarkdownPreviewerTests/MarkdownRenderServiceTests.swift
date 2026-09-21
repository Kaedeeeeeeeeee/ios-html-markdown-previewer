import XCTest
@testable import HTMLMarkdownPreviewer

final class MarkdownRenderServiceTests: XCTestCase {
    func testRendersTableColumnsAndAlignment() {
        let document = MarkdownRenderService().render(markdown: """
        | Default | Left | Center | Right |
        | --- | :--- | :---: | ---: |
        | A | B | C | 42 |
        | D | E | F | 108 |
        """)

        XCTAssertEqual(document.blocks.count, 1)
        guard case .table(let table) = document.blocks.first else {
            return XCTFail("Expected a table instead of flattened paragraph text.")
        }
        XCTAssertEqual(table.columnAlignments, [.leading, .leading, .center, .trailing])
        XCTAssertEqual(table.header.map { String($0.characters) }, ["Default", "Left", "Center", "Right"])
        XCTAssertEqual(table.rows.map { $0.map { String($0.characters) } }, [["A", "B", "C", "42"], ["D", "E", "F", "108"]])
    }

    func testTablePreservesEmptyCellsAndPadsShortRows() {
        let document = MarkdownRenderService().render(markdown: """
        | First | Second | Third |
        | --- | --- | --- |
        | | middle | |
        | only first |
        | one | two | three | extra |
        """)

        guard case .table(let table) = document.blocks.first else {
            return XCTFail("Expected a table.")
        }
        XCTAssertEqual(table.rows.map { $0.map { String($0.characters) } }, [
            ["", "middle", ""],
            ["only first", "", ""],
            ["one", "two", "three"]
        ])
    }

    func testTablePreservesInlineFormattingAndEscapedPipes() {
        let document = MarkdownRenderService().render(markdown: #"""
        | **Name** | Details |
        | --- | --- |
        | A\|B | **bold** and *italic* and `a\|b` and [link](https://example.com) |
        """#)

        guard case .table(let table) = document.blocks.first else {
            return XCTFail("Expected a table.")
        }
        XCTAssertEqual(String(table.header[0].characters), "Name")
        XCTAssertEqual(table.header[0].inlinePresentationIntent, .stronglyEmphasized)
        XCTAssertEqual(String(table.rows[0][0].characters), "A|B")
        let details = table.rows[0][1]
        XCTAssertEqual(String(details.characters), "bold and italic and a|b and link")
        XCTAssertTrue(details.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        XCTAssertTrue(details.runs.contains { $0.inlinePresentationIntent?.contains(.emphasized) == true })
        XCTAssertTrue(details.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
        XCTAssertTrue(details.runs.contains { $0.link == URL(string: "https://example.com") })
    }

    func testRendersHeaderOnlyTableAndTableInsideBlockQuote() {
        let document = MarkdownRenderService().render(markdown: """
        | Header |
        | --- |

        > | Item | Value |
        > | --- | ---: |
        > | Nested | 7 |
        """)

        XCTAssertEqual(document.blocks.count, 2)
        guard case .table(let headerOnly) = document.blocks[0],
              case .blockQuote(let quotedBlocks) = document.blocks[1],
              case .table(let nested) = quotedBlocks.first else {
            return XCTFail("Expected both top-level and nested tables.")
        }
        XCTAssertEqual(headerOnly.header, [AttributedString("Header")])
        XCTAssertTrue(headerOnly.rows.isEmpty)
        XCTAssertEqual(nested.columnAlignments, [.leading, .trailing])
        XCTAssertEqual(nested.rows[0], [AttributedString("Nested"), AttributedString("7")])
    }

    func testRendersCoreMarkdownBlocks() {
        let markdown = """
        # Title

        Paragraph with **strong**, *emphasis*, ~~strike~~, `code`, and [link](https://example.com).

        > Quoted text

        - First
          - Nested
        - Second

        3. Third
        4. Fourth

        ```swift
        let value = 1
        ```

        ---
        """

        let document = MarkdownRenderService().render(markdown: markdown)

        XCTAssertEqual(document.blocks.count, 7)
        XCTAssertEqual(document.blocks[0], .heading(level: 1, text: AttributedString("Title")))

        guard case .paragraph(let paragraph) = document.blocks[1] else {
            return XCTFail("Expected paragraph.")
        }
        XCTAssertTrue(String(paragraph.characters).contains("strong"))
        XCTAssertTrue(String(paragraph.characters).contains("emphasis"))
        XCTAssertTrue(String(paragraph.characters).contains("code"))
        XCTAssertTrue(String(paragraph.characters).contains("link"))

        guard case .blockQuote(let quoteBlocks) = document.blocks[2] else {
            return XCTFail("Expected block quote.")
        }
        XCTAssertEqual(quoteBlocks.count, 1)

        guard case .unorderedList(let unorderedItems) = document.blocks[3] else {
            return XCTFail("Expected unordered list.")
        }
        XCTAssertEqual(unorderedItems.count, 2)
        XCTAssertEqual(String(unorderedItems[0].text.characters), "First")
        XCTAssertFalse(unorderedItems[0].children.isEmpty)

        guard case .orderedList(let start, let orderedItems) = document.blocks[4] else {
            return XCTFail("Expected ordered list.")
        }
        XCTAssertEqual(start, 3)
        XCTAssertEqual(orderedItems.count, 2)

        guard case .codeBlock(let language, let code) = document.blocks[5] else {
            return XCTFail("Expected code block.")
        }
        XCTAssertEqual(language, "swift")
        XCTAssertTrue(code.contains("let value = 1"))

        XCTAssertEqual(document.blocks[6], .thematicBreak)
    }

    func testRendersUTF16MarkdownFile() throws {
        let fileURL = try makeTemporaryDirectory().appendingPathComponent("utf16.md")
        let markdown = """
        # UTF-16 Title

        Body text
        """
        try markdown.data(using: .utf16LittleEndian)!.write(to: fileURL)

        let document = try MarkdownRenderService().render(fileURL: fileURL)

        XCTAssertEqual(document.blocks.first, .heading(level: 1, text: AttributedString("UTF-16 Title")))
    }

    func testTextFileReaderReportsUnsupportedEncoding() throws {
        let fileURL = try makeTemporaryDirectory().appendingPathComponent("binary.md")
        try Data([0x80, 0x81, 0x82]).write(to: fileURL)

        XCTAssertThrowsError(try TextFileReader().readText(from: fileURL)) { error in
            XCTAssertEqual(error as? TextFileReaderError, .unsupportedEncoding("binary.md"))
            XCTAssertTrue(error.localizedDescription.contains("UTF-8 or UTF-16"))
        }
    }

    func testMarkdownLinkPolicyBlocksExternalWebURLs() throws {
        let link = MarkdownLinkPolicy.blockedLink(for: URL(string: "https://example.com/report")!)

        XCTAssertEqual(link.reason, .externalWebURL)
        XCTAssertEqual(link.title, "External Link Blocked")
    }

    func testMarkdownLinkPolicyTreatsRelativeLinksAsUnsupported() throws {
        let link = MarkdownLinkPolicy.blockedLink(for: URL(fileURLWithPath: "notes.md"))

        XCTAssertEqual(link.reason, .unsupportedURL)
        XCTAssertEqual(link.title, "Link Not Opened")
    }

    func testBlocksRemoteImagesAndResolvesLocalImagesAgainstBaseURL() throws {
        let baseURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: baseURL) }
        try writeImageFixture(to: baseURL.appendingPathComponent("images/pixel.png"))
        let document = MarkdownRenderService().render(
            markdown: """
            ![Local alt](images/pixel.png)

            ![Remote alt](https://example.com/pixel.png)
            """,
            baseURL: baseURL,
            readAccessRootURL: baseURL
        )

        XCTAssertEqual(document.blocks.count, 2)

        guard case .image(let localImage) = document.blocks[0],
              case .local(let localURL) = localImage.kind else {
            return XCTFail("Expected local image.")
        }
        XCTAssertEqual(localImage.altText, "Local alt")
        XCTAssertEqual(localURL, baseURL.appendingPathComponent("images/pixel.png").standardizedFileURL)

        guard case .image(let remoteImage) = document.blocks[1],
              case .remoteBlocked(let source) = remoteImage.kind else {
            return XCTFail("Expected blocked remote image.")
        }
        XCTAssertEqual(remoteImage.altText, "Remote alt")
        XCTAssertEqual(source, "https://example.com/pixel.png")
    }

    func testMarkdownLocalImagesCannotEscapeReadAccessRoot() throws {
        let containerURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let rootURL = containerURL.appendingPathComponent("document-root", isDirectory: true)
        let baseURL = rootURL.appendingPathComponent("nested", isDirectory: true)
        let outsideURL = containerURL.appendingPathComponent("outside.png")
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try writeImageFixture(to: rootURL.appendingPathComponent("asset.png"))
        try writeImageFixture(to: outsideURL)

        let document = MarkdownRenderService().render(
            markdown: """
            ![Root asset](../asset.png)

            ![Outside relative](../../outside.png)

            ![Outside file](\(outsideURL.absoluteString))

            ![Backslash](images\\pixel.png)
            """,
            baseURL: baseURL,
            readAccessRootURL: rootURL
        )

        XCTAssertEqual(document.blocks.count, 4)

        guard case .image(let rootAsset) = document.blocks[0],
              case .local(let rootAssetURL) = rootAsset.kind else {
            return XCTFail("Expected root-contained image.")
        }
        XCTAssertEqual(rootAssetURL, rootURL.appendingPathComponent("asset.png").standardizedFileURL)

        for index in 1...3 {
            guard case .image(let image) = document.blocks[index],
                  case .unsupported = image.kind else {
                return XCTFail("Expected unsupported escaped image at index \(index).")
            }
        }
    }

    private func writeImageFixture(to url: URL) throws {
        // Existing files and missing paths can standardize /private/var differently on devices.
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let pixel = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII="
        ))
        try pixel.write(to: url)
    }
}
