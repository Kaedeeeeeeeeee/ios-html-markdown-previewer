import XCTest
@testable import HTMLMarkdownPreviewer

final class ReadingAppearanceTests: XCTestCase {
    func testStoredDisplayValuesCannotProduceInvalidOrUnreadableLayout() {
        XCTAssertEqual(ReadingAppearance.normalizedFontScale(.nan), 1)
        XCTAssertEqual(ReadingAppearance.normalizedFontScale(-5), 0.8)
        XCTAssertEqual(ReadingAppearance.normalizedFontScale(20), 1.8)
        XCTAssertEqual(ReadingAppearance.normalizedFontScale(1.3), 1.3)
        XCTAssertEqual(ReadingAppearance.normalizedLineSpacing(.infinity), 4)
        XCTAssertEqual(ReadingAppearance.normalizedLineSpacing(-2), 0)
        XCTAssertEqual(ReadingAppearance.normalizedLineSpacing(30), 12)
        XCTAssertEqual(ReadingAppearance.normalizedHTMLZoom(-.infinity), 1)
        XCTAssertEqual(ReadingAppearance.normalizedHTMLZoom(0), 1)
        XCTAssertEqual(ReadingAppearance.normalizedHTMLZoom(5), 3)
    }

    func testImageFitsPortraitAndLandscapeWithoutStretching() {
        XCTAssertEqual(MarkdownImageZoomGeometry.fittedSize(
            image: CGSize(width: 1600, height: 900), viewport: CGSize(width: 400, height: 700)
        ), CGSize(width: 400, height: 225))
        XCTAssertEqual(MarkdownImageZoomGeometry.fittedSize(
            image: CGSize(width: 600, height: 1200), viewport: CGSize(width: 800, height: 400)
        ), CGSize(width: 200, height: 400))
        XCTAssertEqual(MarkdownImageZoomGeometry.fittedSize(
            image: .zero, viewport: CGSize(width: 400, height: 700)
        ), .zero)
    }

    func testDraggingKeepsImageEdgesWithinViewportAndCentersShortAxis() {
        let viewport = CGSize(width: 400, height: 700)
        let fitted = CGSize(width: 400, height: 225)
        let proposed = CGSize(width: 900, height: -900)
        XCTAssertEqual(MarkdownImageZoomGeometry.clampedOffset(
            proposed, fittedSize: fitted, viewport: viewport, scale: 2
        ), CGSize(width: 200, height: 0))
        XCTAssertEqual(MarkdownImageZoomGeometry.clampedOffset(
            proposed, fittedSize: fitted, viewport: viewport, scale: 4
        ), CGSize(width: 600, height: -100))
        XCTAssertEqual(MarkdownImageZoomGeometry.clampedOffset(
            proposed, fittedSize: fitted, viewport: viewport, scale: 1
        ), .zero)
    }

    func testExtremeAspectRatiosRemainCenteredOnTheirShortAxis() {
        let viewport = CGSize(width: 400, height: 700)
        let wide = MarkdownImageZoomGeometry.fittedSize(
            image: CGSize(width: 100_000, height: 100), viewport: viewport
        )
        let tall = MarkdownImageZoomGeometry.fittedSize(
            image: CGSize(width: 100, height: 100_000), viewport: viewport
        )
        XCTAssertEqual(MarkdownImageZoomGeometry.clampedOffset(
            CGSize(width: 100_000, height: 100_000), fittedSize: wide, viewport: viewport, scale: 5
        ), CGSize(width: 800, height: 0))
        XCTAssertEqual(MarkdownImageZoomGeometry.clampedOffset(
            CGSize(width: -100_000, height: -100_000), fittedSize: tall, viewport: viewport, scale: 5
        ), CGSize(width: 0, height: -1400))
    }

    func testImageZoomAndNonfiniteOffsetsStayBounded() {
        XCTAssertEqual(MarkdownImageZoomGeometry.normalizedScale(.nan), 1)
        XCTAssertEqual(MarkdownImageZoomGeometry.normalizedScale(0.1), 1)
        XCTAssertEqual(MarkdownImageZoomGeometry.normalizedScale(15), 5)
        XCTAssertEqual(MarkdownImageZoomGeometry.fittedSize(
            image: CGSize(width: CGFloat.nan, height: 100), viewport: CGSize(width: 300, height: 400)
        ), .zero)
        XCTAssertEqual(MarkdownImageZoomGeometry.clampedOffset(
            CGSize(width: 10, height: 10), fittedSize: CGSize(width: CGFloat.nan, height: 400),
            viewport: CGSize(width: 300, height: 400), scale: 2
        ), .zero)
        XCTAssertEqual(MarkdownImageZoomGeometry.clampedOffset(
            CGSize(width: CGFloat.infinity, height: CGFloat.nan),
            fittedSize: CGSize(width: 300, height: 400),
            viewport: CGSize(width: 300, height: 400), scale: 2
        ), .zero)
    }
}
