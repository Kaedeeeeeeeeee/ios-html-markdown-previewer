import UIKit

/// A glyph-based measurement used only for the currently selected search hit.
/// The caller caches the result while scrolling and supplies the actual Text
/// width, matching system font, inline styles, paragraph spacing and alignment.
@MainActor
enum MarkdownTextLayout {
    struct Request: Equatable {
        let text: AttributedString
        let range: NSRange
        let width: CGFloat
        let font: UIFont
        var lineSpacing: CGFloat = 0
        var alignment: NSTextAlignment = .natural
    }

    static func matchRect(for request: Request) -> CGRect? {
        guard request.width > 0, request.width.isFinite else { return nil }
        let attributed = attributedText(for: request)
        guard request.range.location != NSNotFound, request.range.length > 0,
              NSMaxRange(request.range) <= attributed.length else { return nil }

        let storage = NSTextStorage(attributedString: attributed)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: request.width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)

        let glyphs = manager.glyphRange(forCharacterRange: request.range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        // Reveal the first line of a match that itself spans multiple lines.
        var firstLine: CGRect?
        manager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: glyphs, in: container) { rect, stop in
            guard rect.width > 0, rect.height > 0 else { return }
            firstLine = rect
            stop.pointee = true
        }
        return firstLine ?? manager.boundingRect(forGlyphRange: glyphs, in: container)
    }

    private static func attributedText(for request: Request) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = request.lineSpacing
        paragraph.alignment = request.alignment
        paragraph.lineBreakMode = .byWordWrapping
        let result = NSMutableAttributedString(
            string: String(request.text.characters),
            attributes: [.font: request.font, .paragraphStyle: paragraph]
        )
        var location = 0
        for run in request.text.runs {
            let text = String(request.text[run.range].characters)
            let range = NSRange(location: location, length: text.utf16.count)
            location += range.length
            let intent = run.inlinePresentationIntent ?? []
            var font = intent.contains(.code)
                ? UIFont.monospacedSystemFont(ofSize: request.font.pointSize, weight: .regular)
                : request.font
            var traits = font.fontDescriptor.symbolicTraits
            if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
            if intent.contains(.emphasized) { traits.insert(.traitItalic) }
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                font = UIFont(descriptor: descriptor, size: font.pointSize)
            }
            result.addAttribute(.font, value: font, range: range)
        }
        return result
    }
}
