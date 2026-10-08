import XCTest
import UIKit
import SwiftUI
@testable import HTMLMarkdownPreviewer

final class MarkdownReadingTests: XCTestCase {
    func testFoldBandRejectsBandsOutsideTheViewportAndClampsPartialOnes() {
        XCTAssertNil(ReaderFoldBand(top: 1.1, bottom: 1.2))
        XCTAssertNil(ReaderFoldBand(top: -0.2, bottom: 0))
        XCTAssertNil(ReaderFoldBand(top: 0.6, bottom: 0.4))
        XCTAssertEqual(ReaderFoldBand(top: -0.1, bottom: 0.2), ReaderFoldBand(top: 0, bottom: 0.2))
    }

    func testRevealTopKeepsTheUsualPositionWithoutAFold() {
        XCTAssertEqual(ReaderFoldBand.revealTop(targetHeight: 30, viewportHeight: 800, fold: nil), 280)
    }

    func testRevealTopPlacesAResultAboveTheFoldWhenItFits() throws {
        let fold = try XCTUnwrap(ReaderFoldBand(top: 0.48, bottom: 0.52))
        let top = ReaderFoldBand.revealTop(targetHeight: 30, viewportHeight: 1000, fold: fold)
        XCTAssertEqual(top, 350)
        XCTAssertFalse(fold.intersects(top: top, bottom: top + 30, viewportHeight: 1000))

        // A taller result moves up until its bottom clears the fold.
        let tall = ReaderFoldBand.revealTop(targetHeight: 200, viewportHeight: 1000, fold: fold)
        XCTAssertEqual(tall, 268)
        XCTAssertFalse(fold.intersects(top: tall, bottom: tall + 200, viewportHeight: 1000))
    }

    func testRevealTopPlacesAResultBelowTheFoldWhenTheUpperPartIsTooShort() throws {
        let fold = try XCTUnwrap(ReaderFoldBand(top: 0.2, bottom: 0.25))
        let top = ReaderFoldBand.revealTop(targetHeight: 180, viewportHeight: 1000, fold: fold)
        XCTAssertEqual(top, 262)
        XCTAssertFalse(fold.intersects(top: top, bottom: top + 180, viewportHeight: 1000))
    }

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
    func testNativeMarkdownPreservesBlockFractionAcrossViewportReflow() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let container = UIViewController()
        let state = DocumentReadingState(position: ReadingPosition(anchorID: "markdown-block-8@0.35", progress: 0.5))
        let text = AttributedString(String(repeating: "A long native Markdown paragraph wraps at the current reading width. ", count: 30))
        let document = MarkdownDocument(blocks: (0..<16).map { _ in .paragraph(text) })
        let host = UIHostingController(rootView: MarkdownPreviewView(document: document, readingState: state))
        container.addChild(host)
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        window.rootViewController = container
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }
        container.view.layoutIfNeeded()
        host.view.layoutIfNeeded()
        try await waitForNativeAnchor(state, blockID: "markdown-block-8", fraction: 0.35)
        var descendants = [host.view!]
        var resolvedScroll: UIScrollView?
        while !descendants.isEmpty {
            let view = descendants.removeFirst()
            if let scroll = view as? UIScrollView { resolvedScroll = scroll; break }
            descendants.append(contentsOf: view.subviews)
        }
        let scroll = try XCTUnwrap(resolvedScroll)
        let originalOffset = scroll.contentOffset.y
        XCTAssertGreaterThan(originalOffset, 1_000, "The initial lazy block anchor must actually scroll into view.")
        host.view.frame.size.width = 280
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await waitForNativeAnchor(state, blockID: "markdown-block-8", fraction: 0.35)
        let narrowOffset = scroll.contentOffset.y
        XCTAssertGreaterThan(narrowOffset, originalOffset * 1.15, "Narrow reflow must restore the block at its new offset.")
        host.view.frame.size.width = 540
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await waitForNativeAnchor(state, blockID: "markdown-block-8", fraction: 0.35)
        XCTAssertLessThan(scroll.contentOffset.y, narrowOffset * 0.8, "Wide reflow must restore the block at its new offset.")
    }

    @MainActor
    func testNativeVisibleSelectedMatchSurvivesShorterAndNarrowerViewport() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let container = UIViewController()
        let state = DocumentReadingState()
        let finalParagraph = String(repeating: "A paragraph stays readable as its reading column changes. ", count: 8) + "needle"
        let document = MarkdownDocument(blocks: [.paragraph(AttributedString("First needle")),
                                                .paragraph(AttributedString(finalParagraph))])
        let host = UIHostingController(rootView: MarkdownPreviewView(document: document, readingState: state)
            .environment(\.dynamicTypeSize, .large))
        container.addChild(host)
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 900)
        window.rootViewController = container
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }
        container.view.layoutIfNeeded()
        host.view.layoutIfNeeded()
        try await waitForNativeCondition { state.isReady }
        state.query = "needle"
        try await waitForNativeCondition { state.matchCount == 2 }
        state.navigate(to: .match(1))
        try await waitForNativeCondition { state.selectedMatch == 1 }
        var descendants = [host.view!]
        var resolvedScroll: UIScrollView?
        while !descendants.isEmpty {
            let view = descendants.removeFirst()
            if let scroll = view as? UIScrollView { resolvedScroll = scroll; break }
            descendants.append(contentsOf: view.subviews)
        }
        let scroll = try XCTUnwrap(resolvedScroll)
        XCTAssertLessThan(scroll.contentSize.height, scroll.bounds.height,
                          "Both matches must initially fit in the tall viewport.")
        XCTAssertEqual(scroll.contentOffset.y + scroll.adjustedContentInset.top, 0, accuracy: 1)
        // Height-only collapse must preserve visible search focus as well as a
        // subsequent narrowing that wraps the final match onto a later line.
        for size in [CGSize(width: 390, height: 240), CGSize(width: 280, height: 180)] {
            host.view.frame.size = size
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await waitForNativeCondition {
                let maximum = scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom
                return maximum > 100 && abs(scroll.contentOffset.y - maximum) <= 1
            }
            XCTAssertEqual(state.query, "needle")
            XCTAssertEqual(state.matchCount, 2)
            XCTAssertEqual(state.selectedMatch, 1)
        }
    }

    @MainActor
    private func waitForNativeCondition(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        var stableSince: ContinuousClock.Instant?
        while true {
            if condition() {
                if stableSince == nil { stableSince = ContinuousClock.now }
                if let stableSince, ContinuousClock.now - stableSince >= .milliseconds(300) { return }
            } else { stableSince = nil }
            guard ContinuousClock.now < deadline else {
                XCTFail("Native reading interaction did not settle")
                throw NSError(domain: "MarkdownReadingTests", code: 2)
            }
            try await Task.sleep(for: .milliseconds(30))
        }
    }

    @MainActor
    private func waitForNativeAnchor(_ state: DocumentReadingState, blockID: String, fraction: Double) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        var stableSince: ContinuousClock.Instant?
        while true {
            let anchor = MarkdownReadingIndex.StoredAnchor(state.position?.anchorID)
            if state.isReady, anchor?.blockID == blockID, abs((anchor?.fraction ?? -1) - fraction) < 0.025 {
                if stableSince == nil { stableSince = ContinuousClock.now }
                if let stableSince, ContinuousClock.now - stableSince >= .milliseconds(350) { return }
            } else { stableSince = nil }
            guard ContinuousClock.now < deadline else {
                XCTFail("Native viewport reflow lost \(blockID)@\(fraction): \(String(describing: state.position))")
                throw NSError(domain: "MarkdownReadingTests", code: 1)
            }
            try await Task.sleep(for: .milliseconds(30))
        }
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
