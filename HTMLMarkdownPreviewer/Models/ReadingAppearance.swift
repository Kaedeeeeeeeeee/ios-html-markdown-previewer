import Foundation
import CoreGraphics

/// Persisted display choices are always clamped before they reach layout code.
enum ReadingAppearance {
    static let fontScaleRange = 0.8...1.8
    static let lineSpacingRange = 0.0...12.0
    static let htmlZoomRange = 1.0...3.0
    static let defaultFontScale = 1.0
    static let defaultLineSpacing = 4.0
    static let defaultHTMLZoom = 1.0

    static func normalizedFontScale(_ value: Double) -> Double {
        normalized(value, in: fontScaleRange, fallback: defaultFontScale)
    }

    static func normalizedLineSpacing(_ value: Double) -> Double {
        normalized(value, in: lineSpacingRange, fallback: defaultLineSpacing)
    }

    static func normalizedHTMLZoom(_ value: Double) -> Double {
        normalized(value, in: htmlZoomRange, fallback: defaultHTMLZoom)
    }

    private static func normalized(_ value: Double, in range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}

/// Keep the enlarged image covering the viewport; smaller axes remain centered.
enum MarkdownImageZoomGeometry {
    static let scaleRange: ClosedRange<CGFloat> = 1...5

    static func normalizedScale(_ scale: CGFloat) -> CGFloat {
        scale.isFinite ? min(scaleRange.upperBound, max(scaleRange.lowerBound, scale)) : 1
    }

    static func fittedSize(image: CGSize, viewport: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0, viewport.width > 0, viewport.height > 0,
              image.width.isFinite, image.height.isFinite,
              viewport.width.isFinite, viewport.height.isFinite else { return .zero }
        let ratio = min(viewport.width / image.width, viewport.height / image.height)
        return CGSize(width: image.width * ratio, height: image.height * ratio)
    }

    static func clampedOffset(_ offset: CGSize, fittedSize: CGSize, viewport: CGSize, scale: CGFloat) -> CGSize {
        guard fittedSize.width.isFinite, fittedSize.height.isFinite,
              viewport.width.isFinite, viewport.height.isFinite,
              viewport.width > 0, viewport.height > 0 else { return .zero }
        let scale = normalizedScale(scale)
        let horizontal = max(0, (fittedSize.width * scale - viewport.width) / 2)
        let vertical = max(0, (fittedSize.height * scale - viewport.height) / 2)
        return CGSize(
            width: offset.width.isFinite ? min(horizontal, max(-horizontal, offset.width)) : 0,
            height: offset.height.isFinite ? min(vertical, max(-vertical, offset.height)) : 0
        )
    }
}
