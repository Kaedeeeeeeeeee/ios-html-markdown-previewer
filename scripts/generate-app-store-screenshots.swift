#!/usr/bin/env swift

import AppKit
import Foundation

private struct MarketingCopy: Decodable {
    let eyebrow: String
    let title: String
    let subtitle: String
}

private struct StorefrontCopy: Decodable {
    let storefront: String
    let screenshots: [String: MarketingCopy]
}

private struct Options {
    let sourceDirectory: URL
    let outputDirectory: URL
    let copyFile: URL
    let previewDirectory: URL?
}

private struct ScreenshotSpec {
    let key: String
    let filenameSuffix: String
}

private struct Palette {
    let start: NSColor
    let end: NSColor
    let glow: NSColor
}

private enum GeneratorError: LocalizedError {
    case usage(String)
    case missingFile(URL)
    case invalidImage(URL)
    case invalidDimensions(URL, actual: CGSize, expected: CGSize)
    case missingCopy(locale: String, key: String)
    case cannotCreateBitmap(width: Int, height: Int)
    case cannotEncodePNG(URL)

    var errorDescription: String? {
        switch self {
        case .usage(let message):
            return message
        case .missingFile(let url):
            return "Missing file: \(url.path)"
        case .invalidImage(let url):
            return "Cannot read image: \(url.path)"
        case .invalidDimensions(let url, let actual, let expected):
            return "\(url.lastPathComponent) is \(Int(actual.width))x\(Int(actual.height)); expected \(Int(expected.width))x\(Int(expected.height))"
        case .missingCopy(let locale, let key):
            return "Missing marketing copy for \(locale)/\(key)"
        case .cannotCreateBitmap(let width, let height):
            return "Cannot create \(width)x\(height) bitmap"
        case .cannotEncodePNG(let url):
            return "Cannot encode PNG: \(url.path)"
        }
    }
}

private let specs = [
    ScreenshotSpec(key: "01-home", filenameSuffix: "01-home"),
    ScreenshotSpec(key: "02-html-safe-preview", filenameSuffix: "02-html-safe-preview"),
    ScreenshotSpec(key: "03-markdown-preview", filenameSuffix: "03-markdown-preview"),
    ScreenshotSpec(key: "04-zip-report-preview", filenameSuffix: "04-zip-report-preview"),
    ScreenshotSpec(key: "05-settings", filenameSuffix: "05-settings")
]

private let palettes = [
    Palette(start: NSColor(hex: 0x07152E), end: NSColor(hex: 0x0E63E9), glow: NSColor(hex: 0x67E8F9)),
    Palette(start: NSColor(hex: 0x0A1230), end: NSColor(hex: 0x6139D7), glow: NSColor(hex: 0x42C8FF)),
    Palette(start: NSColor(hex: 0x071B2D), end: NSColor(hex: 0x0879AD), glow: NSColor(hex: 0x6EE7D8)),
    Palette(start: NSColor(hex: 0x11133A), end: NSColor(hex: 0x2859D8), glow: NSColor(hex: 0xA78BFA)),
    Palette(start: NSColor(hex: 0x07111F), end: NSColor(hex: 0x1D4F91), glow: NSColor(hex: 0x60A5FA))
]

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }
}

private func parseOptions() throws -> Options {
    let arguments = Array(CommandLine.arguments.dropFirst())
    var values: [String: String] = [:]
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        guard argument.hasPrefix("--"), index + 1 < arguments.count else {
            throw GeneratorError.usage("Usage: generate-app-store-screenshots.swift --source-dir PATH --output-dir PATH --copy-file PATH [--preview-dir PATH]")
        }
        values[argument] = arguments[index + 1]
        index += 2
    }

    guard let source = values["--source-dir"],
          let output = values["--output-dir"],
          let copy = values["--copy-file"] else {
        throw GeneratorError.usage("Usage: generate-app-store-screenshots.swift --source-dir PATH --output-dir PATH --copy-file PATH [--preview-dir PATH]")
    }

    return Options(
        sourceDirectory: URL(fileURLWithPath: source, isDirectory: true),
        outputDirectory: URL(fileURLWithPath: output, isDirectory: true),
        copyFile: URL(fileURLWithPath: copy),
        previewDirectory: values["--preview-dir"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    )
}

private func makeBitmap(width: Int, height: Int) throws -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    ) else {
        throw GeneratorError.cannotCreateBitmap(width: width, height: height)
    }
    bitmap.size = NSSize(width: width, height: height)
    return bitmap
}

private func rectFromTop(
    left: CGFloat,
    top: CGFloat,
    width: CGFloat,
    height: CGFloat,
    canvasHeight: CGFloat
) -> NSRect {
    NSRect(x: left, y: canvasHeight - top - height, width: width, height: height)
}

private func drawBackground(size: CGSize, palette: Palette, index: Int) {
    let bounds = NSRect(origin: .zero, size: size)
    NSGradient(starting: palette.start, ending: palette.end)?.draw(in: bounds, angle: -58)

    let glowColor = palette.glow.withAlphaComponent(0.19)
    glowColor.setFill()
    NSBezierPath(ovalIn: NSRect(
        x: size.width * 0.58,
        y: size.height * 0.63,
        width: size.width * 0.7,
        height: size.width * 0.7
    )).fill()

    let ringColor = NSColor.white.withAlphaComponent(0.1)
    ringColor.setStroke()
    for ring in 0..<3 {
        let diameter = size.width * (0.34 + CGFloat(ring) * 0.13)
        let path = NSBezierPath(ovalIn: NSRect(
            x: size.width - diameter * 0.68,
            y: size.height - diameter * 0.63,
            width: diameter,
            height: diameter
        ))
        path.lineWidth = max(2, size.width / 700)
        path.setLineDash([10, 16], count: 2, phase: CGFloat(index * 9 + ring * 5))
        path.stroke()
    }

    NSColor.white.withAlphaComponent(0.055).setStroke()
    let grid = NSBezierPath()
    let spacing = max(72, size.width / 14)
    var x: CGFloat = -spacing
    while x < size.width + spacing {
        grid.move(to: NSPoint(x: x, y: 0))
        grid.line(to: NSPoint(x: x + size.height * 0.36, y: size.height))
        x += spacing
    }
    grid.lineWidth = 1
    grid.stroke()
}

private func fittedFont(
    text: String,
    maximumWidth: CGFloat,
    startingSize: CGFloat,
    minimumSize: CGFloat,
    weight: NSFont.Weight
) -> NSFont {
    var size = startingSize
    while size > minimumSize {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        if width <= maximumWidth {
            return font
        }
        size -= 2
    }
    return NSFont.systemFont(ofSize: minimumSize, weight: weight)
}

private func drawText(
    _ text: String,
    in rect: NSRect,
    font: NSFont,
    color: NSColor,
    lineHeightMultiple: CGFloat = 1,
    alignment: NSTextAlignment = .left
) {
    let context = NSGraphicsContext.current
    context?.saveGraphicsState()
    defer { context?.restoreGraphicsState() }

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.lineHeightMultiple = lineHeightMultiple
    let attributed = NSAttributedString(
        string: text,
        attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
    )
    attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
}

private func drawBadge(copy: MarketingCopy, size: CGSize, isPhone: Bool) {
    let left: CGFloat = isPhone ? 96 : 132
    let top: CGFloat = isPhone ? 104 : 116
    let height: CGFloat = isPhone ? 62 : 70
    let fontSize: CGFloat = isPhone ? 22 : 26
    let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
    let textWidth = (copy.eyebrow as NSString).size(withAttributes: [.font: font]).width
    let width = min(size.width - left * 2, textWidth + (isPhone ? 102 : 120))
    let pillRect = rectFromTop(left: left, top: top, width: width, height: height, canvasHeight: size.height)

    NSColor.white.withAlphaComponent(0.12).setFill()
    let pill = NSBezierPath(roundedRect: pillRect, xRadius: height / 2, yRadius: height / 2)
    pill.fill()
    NSColor.white.withAlphaComponent(0.18).setStroke()
    pill.lineWidth = 2
    pill.stroke()

    let markRect = NSRect(x: pillRect.minX + 20, y: pillRect.midY - 11, width: 28, height: 22)
    let mark = NSBezierPath()
    mark.move(to: NSPoint(x: markRect.maxX - 17, y: markRect.minY))
    mark.line(to: NSPoint(x: markRect.minX, y: markRect.midY))
    mark.line(to: NSPoint(x: markRect.maxX - 17, y: markRect.maxY))
    mark.move(to: NSPoint(x: markRect.minX + 17, y: markRect.minY))
    mark.line(to: NSPoint(x: markRect.maxX, y: markRect.midY))
    mark.line(to: NSPoint(x: markRect.minX + 17, y: markRect.maxY))
    NSColor.white.setStroke()
    mark.lineWidth = 4
    mark.lineCapStyle = .round
    mark.lineJoinStyle = .round
    mark.stroke()

    drawText(
        copy.eyebrow.uppercased(),
        in: NSRect(x: pillRect.minX + 62, y: pillRect.minY + 4, width: pillRect.width - 76, height: pillRect.height - 8),
        font: font,
        color: .white
    )
}

private func drawDevice(image: NSImage, size: CGSize, isPhone: Bool) {
    let sourceAspect = image.size.width / image.size.height
    let imageWidth: CGFloat = isPhone ? 920 : 1460
    let imageHeight = imageWidth / sourceAspect
    let imageLeft: CGFloat = isPhone ? 286 : 446
    let imageTop: CGFloat = isPhone ? 748 : 694
    let imageRect = rectFromTop(
        left: imageLeft,
        top: imageTop,
        width: imageWidth,
        height: imageHeight,
        canvasHeight: size.height
    )
    let bezel: CGFloat = isPhone ? 22 : 26
    let corner: CGFloat = isPhone ? 106 : 62
    let frameRect = imageRect.insetBy(dx: -bezel, dy: -bezel)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.48)
    shadow.shadowBlurRadius = isPhone ? 54 : 70
    shadow.shadowOffset = NSSize(width: -12, height: -22)
    shadow.set()
    NSColor(hex: 0x080B12).setFill()
    NSBezierPath(roundedRect: frameRect, xRadius: corner + bezel, yRadius: corner + bezel).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.18).setStroke()
    let frameStroke = NSBezierPath(roundedRect: frameRect, xRadius: corner + bezel, yRadius: corner + bezel)
    frameStroke.lineWidth = 2
    frameStroke.stroke()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: imageRect, xRadius: corner, yRadius: corner).addClip()
    image.draw(
        in: imageRect,
        from: NSRect(origin: .zero, size: image.size),
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    NSGraphicsContext.restoreGraphicsState()
}

private func render(
    sourceURL: URL,
    outputURL: URL,
    copy: MarketingCopy,
    palette: Palette,
    isPhone: Bool,
    expectedSize: CGSize,
    index: Int
) throws {
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
        throw GeneratorError.missingFile(sourceURL)
    }
    guard let image = NSImage(contentsOf: sourceURL),
          let representation = image.representations.first else {
        throw GeneratorError.invalidImage(sourceURL)
    }
    let actual = CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
    guard actual == expectedSize else {
        throw GeneratorError.invalidDimensions(sourceURL, actual: actual, expected: expectedSize)
    }
    image.size = expectedSize

    let width = Int(expectedSize.width)
    let height = Int(expectedSize.height)
    let bitmap = try makeBitmap(width: width, height: height)
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw GeneratorError.cannotCreateBitmap(width: width, height: height)
    }

    let previousContext = NSGraphicsContext.current
    NSGraphicsContext.current = context
    context.saveGraphicsState()
    context.imageInterpolation = .high
    drawBackground(size: expectedSize, palette: palette, index: index)
    drawBadge(copy: copy, size: expectedSize, isPhone: isPhone)

    let horizontalMargin: CGFloat = isPhone ? 96 : 132
    let titleTop: CGFloat = isPhone ? 214 : 226
    let titleHeight: CGFloat = isPhone ? 252 : 240
    let titleStartingSize: CGFloat = isPhone ? 96 : 112
    let titleMinimumSize: CGFloat = isPhone ? 70 : 84
    let titleFont = fittedFont(
        text: copy.title,
        maximumWidth: expectedSize.width - horizontalMargin * 2,
        startingSize: titleStartingSize,
        minimumSize: titleMinimumSize,
        weight: .bold
    )
    drawText(
        copy.title,
        in: rectFromTop(
            left: horizontalMargin,
            top: titleTop,
            width: expectedSize.width - horizontalMargin * 2,
            height: titleHeight,
            canvasHeight: expectedSize.height
        ),
        font: titleFont,
        color: .white,
        lineHeightMultiple: 0.92
    )

    let subtitleTop: CGFloat = isPhone ? 484 : 496
    let subtitleFont = NSFont.systemFont(ofSize: isPhone ? 38 : 44, weight: .medium)
    drawText(
        copy.subtitle,
        in: rectFromTop(
            left: horizontalMargin,
            top: subtitleTop,
            width: expectedSize.width - horizontalMargin * 2,
            height: isPhone ? 118 : 126,
            canvasHeight: expectedSize.height
        ),
        font: subtitleFont,
        color: NSColor.white.withAlphaComponent(0.75),
        lineHeightMultiple: 1.08
    )

    drawDevice(image: image, size: expectedSize, isPhone: isPhone)
    context.restoreGraphicsState()
    NSGraphicsContext.current = previousContext

    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let data = bitmap.representation(using: .png, properties: [.compressionFactor: 0.92]) else {
        throw GeneratorError.cannotEncodePNG(outputURL)
    }
    try data.write(to: outputURL, options: .atomic)
}

private func renderContactSheet(
    imageURLs: [URL],
    locale: String,
    storefront: String,
    device: String,
    outputURL: URL
) throws {
    let images = try imageURLs.map { url -> NSImage in
        guard let image = NSImage(contentsOf: url) else { throw GeneratorError.invalidImage(url) }
        return image
    }
    guard let first = images.first else { return }
    let thumbnailHeight: CGFloat = 720
    let thumbnailWidth = thumbnailHeight * first.size.width / first.size.height
    let gap: CGFloat = 34
    let margin: CGFloat = 56
    let header: CGFloat = 126
    let canvasWidth = Int(margin * 2 + thumbnailWidth * CGFloat(images.count) + gap * CGFloat(images.count - 1))
    let canvasHeight = Int(header + thumbnailHeight + margin)
    let bitmap = try makeBitmap(width: canvasWidth, height: canvasHeight)
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw GeneratorError.cannotCreateBitmap(width: canvasWidth, height: canvasHeight)
    }

    let previousContext = NSGraphicsContext.current
    NSGraphicsContext.current = context
    context.saveGraphicsState()
    NSColor(hex: 0xEDF2F8).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)).fill()
    drawText(
        "\(storefront) · \(device) · \(locale)",
        in: NSRect(x: margin, y: CGFloat(canvasHeight) - 94, width: CGFloat(canvasWidth) - margin * 2, height: 54),
        font: NSFont.systemFont(ofSize: 34, weight: .semibold),
        color: NSColor(hex: 0x17243A)
    )
    for (index, image) in images.enumerated() {
        let x = margin + CGFloat(index) * (thumbnailWidth + gap)
        let rect = NSRect(x: x, y: margin, width: thumbnailWidth, height: thumbnailHeight)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }
    context.restoreGraphicsState()
    NSGraphicsContext.current = previousContext

    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let data = bitmap.representation(using: .png, properties: [.compressionFactor: 0.86]) else {
        throw GeneratorError.cannotEncodePNG(outputURL)
    }
    try data.write(to: outputURL, options: .atomic)
}

private func run() throws {
    let options = try parseOptions()
    guard FileManager.default.fileExists(atPath: options.copyFile.path) else {
        throw GeneratorError.missingFile(options.copyFile)
    }
    let copy = try JSONDecoder().decode(
        [String: StorefrontCopy].self,
        from: Data(contentsOf: options.copyFile)
    )
    let locales = ["en-US", "zh-Hans", "ja"]
    let devices: [(prefix: String, size: CGSize, isPhone: Bool)] = [
        ("iphone", CGSize(width: 1320, height: 2868), true),
        ("ipad", CGSize(width: 2064, height: 2752), false)
    ]

    for locale in locales {
        guard let localeCopy = copy[locale] else {
            throw GeneratorError.missingCopy(locale: locale, key: "locale")
        }
        var renderedByDevice: [String: [URL]] = [:]

        for device in devices {
            for (index, spec) in specs.enumerated() {
                guard let marketingCopy = localeCopy.screenshots[spec.key] else {
                    throw GeneratorError.missingCopy(locale: locale, key: spec.key)
                }
                let filename = "\(device.prefix)-\(spec.filenameSuffix).png"
                let sourceURL = options.sourceDirectory.appendingPathComponent(filename)
                let outputURL = options.outputDirectory
                    .appendingPathComponent(locale, isDirectory: true)
                    .appendingPathComponent(filename)
                try render(
                    sourceURL: sourceURL,
                    outputURL: outputURL,
                    copy: marketingCopy,
                    palette: palettes[index],
                    isPhone: device.isPhone,
                    expectedSize: device.size,
                    index: index
                )
                renderedByDevice[device.prefix, default: []].append(outputURL)

                if locale == "en-US" {
                    let compatibilityURL = options.outputDirectory.appendingPathComponent(filename)
                    try FileManager.default.createDirectory(at: options.outputDirectory, withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: compatibilityURL.path) {
                        try FileManager.default.removeItem(at: compatibilityURL)
                    }
                    try FileManager.default.copyItem(at: outputURL, to: compatibilityURL)
                }
                print("Generated \(locale)/\(filename)")
            }
        }

        if let previewDirectory = options.previewDirectory {
            for device in devices {
                try renderContactSheet(
                    imageURLs: renderedByDevice[device.prefix, default: []],
                    locale: locale,
                    storefront: localeCopy.storefront,
                    device: device.isPhone ? "iPhone 6.9-inch" : "iPad 13-inch",
                    outputURL: previewDirectory.appendingPathComponent("\(locale)-\(device.prefix).png")
                )
            }
        }
    }
}

do {
    try run()
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
