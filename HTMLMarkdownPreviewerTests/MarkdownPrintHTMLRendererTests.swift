import UIKit
import XCTest
@testable import HTMLMarkdownPreviewer

final class MarkdownPrintHTMLRendererTests: XCTestCase {
    func testPreservesFormattingNestedListsCodeAndTableStructure() {
        let document = MarkdownRenderService().render(markdown: """
        # Report

        **Strong**, *emphasis*, ~~strike~~, `inline`, and [link](https://example.com).

        > Quoted text

        3. Third
           - Nested

        ```swift
        let value = "<tag>"
        ```

        | Name | Count | Total |
        | :--- | :---: | ---: |
        | **Item** | 2 | 30 |
        """)

        let html = MarkdownPrintHTMLRenderer().render(document, title: "Report")

        XCTAssertTrue(html.contains("<h1>Report</h1>"))
        XCTAssertTrue(html.contains("<strong>Strong</strong>"))
        XCTAssertTrue(html.contains("<em>emphasis</em>"))
        XCTAssertTrue(html.contains("<s>strike</s>"))
        XCTAssertTrue(html.contains("<code>inline</code>"))
        XCTAssertTrue(html.contains("<span class=\"link\">link</span>"))
        XCTAssertFalse(html.contains("href="))
        XCTAssertTrue(html.contains("<blockquote><p>Quoted text</p></blockquote>"))
        XCTAssertTrue(html.contains("<ol start=\"3\"><li>Third<ul><li>Nested</li></ul></li></ol>"))
        XCTAssertTrue(html.contains("let value = &quot;&lt;tag&gt;&quot;"))
        XCTAssertTrue(html.contains("<thead><tr><th scope=\"col\" class=\"align-leading\">Name</th>"))
        XCTAssertTrue(html.contains("<th scope=\"col\" class=\"align-center\">Count</th>"))
        XCTAssertTrue(html.contains("<th scope=\"col\" class=\"align-trailing\">Total</th>"))
        XCTAssertTrue(html.contains("<tbody><tr><td class=\"align-leading\"><strong>Item</strong></td>"))
    }

    func testEscapesContentAndDoesNotEmitActiveRemoteResources() {
        var link = AttributedString("<script>alert('unsafe')</script>")
        link.link = URL(string: "javascript:alert(1)")
        let document = MarkdownDocument(blocks: [
            .paragraph(link),
            .codeBlock(language: "</div><script>unsafe()</script>", code: "<img src='https://example.com/pixel'>"),
            .image(MarkdownImage(
                source: "https://example.com/pixel?x=\" onerror=\"unsafe()",
                altText: "<iframe src='https://example.com'></iframe>",
                title: nil,
                kind: .remoteBlocked("https://example.com/pixel")
            )),
            .image(MarkdownImage(
                source: "data:image/svg+xml,<svg onload='unsafe()'></svg>",
                altText: "SVG",
                title: nil,
                kind: .unsupported("data:")
            ))
        ])

        let html = MarkdownPrintHTMLRenderer().render(document, title: "</title><script>unsafe()</script>")

        XCTAssertFalse(html.contains("<script"))
        XCTAssertFalse(html.contains("<iframe"))
        XCTAssertFalse(html.contains("<img"))
        XCTAssertFalse(html.contains("href="))
        XCTAssertFalse(html.contains("javascript:"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertTrue(html.contains("&quot; onerror=&quot;"))
        XCTAssertTrue(html.contains("default-src 'none'; img-src data:"))
        XCTAssertTrue(html.contains(AppStrings.MarkdownImages.remoteBlocked))
        XCTAssertTrue(html.contains(AppStrings.MarkdownImages.unsupported))
    }

    @MainActor
    func testEmbedsLocalImageAsPNGAndEscapesAlternativeText() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("image.jpg")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        try XCTUnwrap(image.jpegData(compressionQuality: 1)).write(to: imageURL)
        let document = MarkdownDocument(blocks: [.image(MarkdownImage(
            source: "image.jpg",
            altText: "Picture \" onload=\"unsafe() <tag>",
            title: nil,
            kind: .local(imageURL)
        ))])

        let html = MarkdownPrintHTMLRenderer().render(document, title: "Image")

        XCTAssertTrue(html.contains("src=\"data:image/png;base64,"))
        XCTAssertFalse(html.contains(imageURL.absoluteString))
        XCTAssertTrue(html.contains("alt=\"Picture &quot; onload=&quot;unsafe() &lt;tag&gt;\""))
        let marker = "src=\"data:image/png;base64,"
        let start = try XCTUnwrap(html.range(of: marker)?.upperBound)
        let end = try XCTUnwrap(html[start...].firstIndex(of: "\""))
        let data = try XCTUnwrap(Data(base64Encoded: String(html[start..<end])))
        XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertNotNil(UIImage(data: data))
    }

    func testUnavailableImageProducesReadablePlaceholder() {
        let document = MarkdownDocument(blocks: [.image(MarkdownImage(
            source: "missing.png",
            altText: "Diagram",
            title: nil,
            kind: .local(URL(fileURLWithPath: "/missing/image.png"))
        ))])

        let html = MarkdownPrintHTMLRenderer().render(document, title: "Missing image")

        XCTAssertFalse(html.contains("<img"))
        XCTAssertTrue(html.contains(AppStrings.MarkdownImages.localUnavailable))
        XCTAssertTrue(html.contains("missing.png<br>Diagram"))
    }
}
