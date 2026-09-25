import XCTest
import UIKit
@testable import HTMLMarkdownPreviewer

final class MarkdownReadingTests: XCTestCase {
    func testRepeatedHeadingsHaveDistinctDestinationsIncludingNestedHeadings() {
        let index = MarkdownReadingIndex(document: MarkdownDocument(blocks: [
            .heading(level: 1, text: AttributedString("Repeated")),
            .heading(level: 2, text: AttributedString("Repeated")),
            .blockQuote([.heading(level: 3, text: AttributedString("Repeated"))]),
            .unorderedList([MarkdownListItem(text: AttributedString("Item"), children: [
                .heading(level: 4, text: AttributedString("Repeated"))
            ])])
        ]))

        XCTAssertEqual(index.headings.map(\.title), Array(repeating: "Repeated", count: 4))
        XCTAssertEqual(index.headings.map(\.level), [1, 2, 3, 4])
        XCTAssertEqual(Set(index.headings.map(\.id)).count, 4)
        XCTAssertEqual(index.blockID(containing: index.headings[2].id), "markdown-block-2")
        XCTAssertEqual(index.blockID(containing: index.headings[3].id), "markdown-block-3")
    }

    func testSearchCoversQuotedTextNestedListsTablesAndCodeInReadingOrder() {
        let document = MarkdownDocument(blocks: [
            .heading(level: 1, text: AttributedString("Find heading")),
            .paragraph(AttributedString("find paragraph")),
            .blockQuote([.paragraph(AttributedString("find quote"))]),
            .unorderedList([MarkdownListItem(text: AttributedString("find item"), children: [
                .orderedList(start: 3, items: [
                    MarkdownListItem(text: AttributedString("find nested"), children: [])
                ])
            ])]),
            .table(MarkdownTable(columnAlignments: [.leading],
                                 header: [AttributedString("find header")],
                                 rows: [[AttributedString("find cell")]])),
            .codeBlock(language: "swift", code: "find(value)"),
            .image(MarkdownImage(source: "find.png", altText: "find image", title: nil,
                                 kind: .remoteBlocked("https://example.com/find.png"))),
            .thematicBreak
        ])
        let index = MarkdownReadingIndex(document: document)
        let matches = index.matches(for: "FIND")

        XCTAssertEqual(matches.count, 8)
        XCTAssertEqual(matches.map(\.blockID), [
            "markdown-block-0", "markdown-block-1", "markdown-block-2",
            "markdown-block-3", "markdown-block-3", "markdown-block-4",
            "markdown-block-4", "markdown-block-5"
        ])
        XCTAssertEqual(Set(matches.map(\.elementID)).count, 8)
        // Asset paths and non-visible alt text must not create unreachable results.
        XCTAssertTrue(index.matches(for: "find.png").isEmpty)
    }

    func testUnicodeAndDiacriticMatchesReturnRangesInOriginalText() {
        let text = "👩🏽‍💻 Café / CAFE / cafe\u{301} / 東京 東京"
        let index = MarkdownReadingIndex(document: MarkdownDocument(blocks: [.paragraph(AttributedString(text))]))
        let latinMatches = index.matches(for: "cafe")

        XCTAssertEqual(latinMatches.count, 3)
        XCTAssertEqual(latinMatches.map { String(text[$0.range]) }, ["Café", "CAFE", "cafe\u{301}"])
        XCTAssertEqual(index.matches(for: "東京").count, 2)
        XCTAssertEqual(index.matches(for: "👩🏽‍💻").count, 1)
    }

    func testSearchIsLiteralNonOverlappingAndIgnoresEmptyQueries() {
        let index = MarkdownReadingIndex(document: MarkdownDocument(blocks: [
            .paragraph(AttributedString("[a.*] banana [a.*]"))
        ]))

        XCTAssertEqual(index.matches(for: "[a.*]").count, 2)
        XCTAssertEqual(index.matches(for: "ana").count, 1)
        XCTAssertTrue(index.matches(for: "").isEmpty)
        XCTAssertTrue(index.matches(for: " \n\t").isEmpty)
        XCTAssertTrue(index.matches(for: "unavailable").isEmpty)
    }

    func testStoredAnchorRoundTripsWithinBlockPositionAndRejectsForeignAnchors() {
        let anchor = MarkdownReadingIndex.StoredAnchor(blockID: "markdown-block-12", fraction: 0.673)
        XCTAssertEqual(MarkdownReadingIndex.StoredAnchor(anchor.encoded), anchor)
        XCTAssertEqual(MarkdownReadingIndex.StoredAnchor("markdown-block-2")?.fraction, 0)
        XCTAssertEqual(MarkdownReadingIndex.StoredAnchor("markdown-block-2@3")?.fraction, 1)
        XCTAssertEqual(MarkdownReadingIndex.StoredAnchor("markdown-block-2@-1")?.fraction, 0)
        XCTAssertEqual(MarkdownReadingIndex.StoredAnchor("markdown-block-2@nan")?.fraction, 0)
        XCTAssertNil(MarkdownReadingIndex.StoredAnchor("html-section-2"))
        XCTAssertNil(MarkdownReadingIndex.StoredAnchor("markdown-block-title"))
        XCTAssertNil(MarkdownReadingIndex.StoredAnchor(nil))
    }

    @MainActor
    func testTextKitLocatesTwoMatchesFarApartWithinOneLongParagraph() throws {
        let plain = "needle " + String(repeating: "A longer sentence with wide WWW and narrow iii characters. ", count: 100) + "needle"
        let text = AttributedString(plain)
        let font = UIFont.preferredFont(forTextStyle: .body)
        let firstRange = NSRange(try XCTUnwrap(plain.range(of: "needle")), in: plain)
        let lastRange = NSRange(try XCTUnwrap(plain.range(of: "needle", options: .backwards)), in: plain)
        let first = try XCTUnwrap(MarkdownTextLayout.matchRect(for: .init(
            text: text, range: firstRange, width: 280, font: font, lineSpacing: 4
        )))
        let last = try XCTUnwrap(MarkdownTextLayout.matchRect(for: .init(
            text: text, range: lastRange, width: 280, font: font, lineSpacing: 4
        )))

        XCTAssertLessThan(first.minY, 40)
        XCTAssertGreaterThan(last.minY - first.minY, 1_000)
        XCTAssertGreaterThan(last.width, 0)
        XCTAssertLessThanOrEqual(last.maxX, 281)
    }

    @MainActor
    func testTextKitUsesUnicodeRangesAndReflowsCJKAtTheActualColumnWidth() throws {
        let plain = String(repeating: "👩🏽‍💻 読書の記録と今日的发现。", count: 40) + "東京"
        let range = NSRange(try XCTUnwrap(plain.range(of: "東京")), in: plain)
        var text = AttributedString(plain)
        text.inlinePresentationIntent = [.stronglyEmphasized, .emphasized]
        let font = UIFont.preferredFont(forTextStyle: .body)
        let narrow = try XCTUnwrap(MarkdownTextLayout.matchRect(for: .init(text: text, range: range, width: 88, font: font)))
        let wide = try XCTUnwrap(MarkdownTextLayout.matchRect(for: .init(text: text, range: range, width: 240, font: font)))

        XCTAssertGreaterThan(narrow.minY, wide.minY)
        XCTAssertTrue(narrow.minY.isFinite)
        XCTAssertLessThanOrEqual(narrow.maxX, 89)
        XCTAssertGreaterThan(wide.width, 0)
    }

    @MainActor
    func testTextKitLocatesHorizontalCodeHitAndAlignedTableCell() throws {
        let plain = String(repeating: "let value = 1; ", count: 12) + "needle"
        let range = NSRange(try XCTUnwrap(plain.range(of: "needle")), in: plain)
        let code = try XCTUnwrap(MarkdownTextLayout.matchRect(for: .init(
            text: AttributedString(plain), range: range, width: 5_000,
            font: .monospacedSystemFont(ofSize: 17, weight: .regular)
        )))
        XCTAssertGreaterThan(code.minX, 600)
        XCTAssertLessThan(code.minY, 40)

        let cell = try XCTUnwrap(MarkdownTextLayout.matchRect(for: .init(
            text: AttributedString("42"), range: NSRange(location: 0, length: 2), width: 240,
            font: .preferredFont(forTextStyle: .body), alignment: .right
        )))
        XCTAssertGreaterThan(cell.minX, 180)
        XCTAssertLessThanOrEqual(cell.maxX, 241)
    }
}
