import XCTest
@testable import HTMLMarkdownPreviewer

final class MarkdownRenderServiceTests: XCTestCase {
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

    func testBlocksRemoteImagesAndResolvesLocalImagesAgainstBaseURL() throws {
        let baseURL = try makeTemporaryDirectory()
        let document = MarkdownRenderService().render(
            markdown: """
            ![Local alt](images/pixel.png)

            ![Remote alt](https://example.com/pixel.png)
            """,
            baseURL: baseURL
        )

        XCTAssertEqual(document.blocks.count, 2)

        guard case .image(let localImage) = document.blocks[0],
              case .local(let localURL) = localImage.kind else {
            return XCTFail("Expected local image.")
        }
        XCTAssertEqual(localImage.altText, "Local alt")
        XCTAssertEqual(localURL, baseURL.appendingPathComponent("images/pixel.png"))

        guard case .image(let remoteImage) = document.blocks[1],
              case .remoteBlocked(let source) = remoteImage.kind else {
            return XCTFail("Expected blocked remote image.")
        }
        XCTAssertEqual(remoteImage.altText, "Remote alt")
        XCTAssertEqual(source, "https://example.com/pixel.png")
    }
}

