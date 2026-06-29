import Foundation
import Markdown

final class MarkdownRenderService {
    func render(markdown: String, baseURL: URL? = nil, readAccessRootURL: URL? = nil) -> MarkdownDocument {
        let document = Document(parsing: markdown)
        let blocks = document.children.flatMap {
            renderBlock($0, baseURL: baseURL, readAccessRootURL: readAccessRootURL)
        }
        return MarkdownDocument(blocks: blocks)
    }

    func render(fileURL: URL, readAccessRootURL: URL? = nil) throws -> MarkdownDocument {
        let markdown = try TextFileReader().readText(from: fileURL)
        return render(
            markdown: markdown,
            baseURL: fileURL.deletingLastPathComponent(),
            readAccessRootURL: readAccessRootURL
        )
    }

    private func renderBlock(_ markup: Markup, baseURL: URL?, readAccessRootURL: URL?) -> [MarkdownBlock] {
        switch markup {
        case let heading as Heading:
            return [.heading(level: min(max(heading.level, 1), 6), text: renderInlineChildren(of: heading))]
        case let paragraph as Paragraph:
            if let image = paragraph.children.compactMap({ $0 as? Markdown.Image }).first,
               paragraph.childCount == 1 {
                return [.image(renderImage(image, baseURL: baseURL, readAccessRootURL: readAccessRootURL))]
            }
            return [.paragraph(renderInlineChildren(of: paragraph))]
        case let codeBlock as CodeBlock:
            return [.codeBlock(language: codeBlock.language, code: codeBlock.code)]
        case let quote as BlockQuote:
            return [.blockQuote(quote.children.flatMap {
                renderBlock($0, baseURL: baseURL, readAccessRootURL: readAccessRootURL)
            })]
        case let list as UnorderedList:
            return [.unorderedList(renderListItems(
                from: list,
                baseURL: baseURL,
                readAccessRootURL: readAccessRootURL
            ))]
        case let list as OrderedList:
            return [.orderedList(
                start: Int(list.startIndex),
                items: renderListItems(from: list, baseURL: baseURL, readAccessRootURL: readAccessRootURL)
            )]
        case _ as ThematicBreak:
            return [.thematicBreak]
        default:
            let fallback = plainText(from: markup).trimmingCharacters(in: .whitespacesAndNewlines)
            return fallback.isEmpty ? [] : [.paragraph(AttributedString(fallback))]
        }
    }

    private func renderListItems(
        from container: ListItemContainer,
        baseURL: URL?,
        readAccessRootURL: URL?
    ) -> [MarkdownListItem] {
        container.children.compactMap { child -> MarkdownListItem? in
            guard let item = child as? ListItem else {
                return nil
            }

            var text = AttributedString()
            var nestedBlocks: [MarkdownBlock] = []

            for itemChild in item.children {
                if let paragraph = itemChild as? Paragraph, text.characters.isEmpty {
                    text = renderInlineChildren(of: paragraph)
                } else {
                    nestedBlocks.append(contentsOf: renderBlock(
                        itemChild,
                        baseURL: baseURL,
                        readAccessRootURL: readAccessRootURL
                    ))
                }
            }

            return MarkdownListItem(text: text, children: nestedBlocks)
        }
    }

    private func renderInlineChildren(of container: InlineContainer) -> AttributedString {
        var result = AttributedString()
        for child in container.children {
            result.append(renderInline(child))
        }
        return result
    }

    private func renderInline(_ markup: Markup) -> AttributedString {
        switch markup {
        case let text as Markdown.Text:
            return AttributedString(text.string)
        case let code as InlineCode:
            var value = AttributedString(code.code)
            value.inlinePresentationIntent = .code
            return value
        case let strong as Strong:
            var value = renderInlineChildren(of: strong)
            value.inlinePresentationIntent = (value.inlinePresentationIntent ?? []).union(.stronglyEmphasized)
            return value
        case let emphasis as Emphasis:
            var value = renderInlineChildren(of: emphasis)
            value.inlinePresentationIntent = (value.inlinePresentationIntent ?? []).union(.emphasized)
            return value
        case let strikethrough as Strikethrough:
            var value = renderInlineChildren(of: strikethrough)
            value.inlinePresentationIntent = (value.inlinePresentationIntent ?? []).union(.strikethrough)
            return value
        case let link as Link:
            var value = renderInlineChildren(of: link)
            if let destination = link.destination,
               let url = URL(string: destination) {
                value.link = url
            }
            return value
        case let image as Markdown.Image:
            return AttributedString(image.plainText)
        case _ as SoftBreak:
            return AttributedString("\n")
        case _ as LineBreak:
            return AttributedString("\n")
        default:
            return AttributedString(plainText(from: markup))
        }
    }

    private func plainText(from markup: Markup) -> String {
        if let markup = markup as? PlainTextConvertibleMarkup {
            return markup.plainText
        }

        return markup.children.map { plainText(from: $0) }.joined(separator: " ")
    }

    private func renderImage(_ image: Markdown.Image, baseURL: URL?, readAccessRootURL: URL?) -> MarkdownImage {
        let source = image.source ?? ""
        let altText = image.plainText
        let kind: MarkdownImage.SourceKind

        if let url = URL(string: source), let scheme = url.scheme?.lowercased() {
            switch scheme {
            case "http", "https":
                kind = .remoteBlocked(source)
            case "file":
                kind = containedLocalImageKind(for: url, source: source, readAccessRootURL: readAccessRootURL)
            default:
                kind = .unsupported(source)
            }
        } else if let baseURL {
            let resolvedURL = baseURL.appendingPathComponent(source)
            kind = containedLocalImageKind(for: resolvedURL, source: source, readAccessRootURL: readAccessRootURL)
        } else {
            kind = .unsupported(source)
        }

        return MarkdownImage(
            source: source,
            altText: altText,
            title: image.title,
            kind: kind
        )
    }

    private func containedLocalImageKind(
        for url: URL,
        source: String,
        readAccessRootURL: URL?
    ) -> MarkdownImage.SourceKind {
        guard !source.isEmpty else {
            return .unsupported(source)
        }

        guard let readAccessRootURL else {
            return .local(url)
        }

        guard !source.contains("\\") else {
            return .unsupported(source)
        }

        let imageURL = url.standardizedFileURL
        let rootURL = readAccessRootURL.standardizedFileURL
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : "\(rootURL.path)/"

        guard imageURL.path == rootURL.path || imageURL.path.hasPrefix(rootPath) else {
            return .unsupported(source)
        }

        return .local(imageURL)
    }
}

enum TextFileReaderError: Error, Equatable, LocalizedError {
    case unsupportedEncoding(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedEncoding(let filename):
            "Cannot decode \(filename) as text. Export it as UTF-8 or UTF-16 and try again."
        }
    }
}

struct TextFileReader {
    func readText(from fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return ""
        }

        if hasPrefix([0xEF, 0xBB, 0xBF], in: data) {
            return try decode(data.dropFirst(3), as: .utf8, filename: fileURL.lastPathComponent)
        }

        if hasPrefix([0xFF, 0xFE], in: data) {
            return try decode(data.dropFirst(2), as: .utf16LittleEndian, filename: fileURL.lastPathComponent)
        }

        if hasPrefix([0xFE, 0xFF], in: data) {
            return try decode(data.dropFirst(2), as: .utf16BigEndian, filename: fileURL.lastPathComponent)
        }

        if looksLikeUTF16LittleEndian(data),
           let text = String(data: data, encoding: .utf16LittleEndian) {
            return text
        }

        if looksLikeUTF16BigEndian(data),
           let text = String(data: data, encoding: .utf16BigEndian) {
            return text
        }

        if let text = String(data: data, encoding: .utf8),
           !text.contains("\u{0}") {
            return text
        }

        throw TextFileReaderError.unsupportedEncoding(fileURL.lastPathComponent)
    }

    private func decode(_ data: Data.SubSequence, as encoding: String.Encoding, filename: String) throws -> String {
        guard let text = String(data: Data(data), encoding: encoding) else {
            throw TextFileReaderError.unsupportedEncoding(filename)
        }
        return text
    }

    private func hasPrefix(_ prefix: [UInt8], in data: Data) -> Bool {
        data.count >= prefix.count && zip(prefix, data).allSatisfy { pair in
            pair.0 == pair.1
        }
    }

    private func looksLikeUTF16LittleEndian(_ data: Data) -> Bool {
        looksLikeUTF16(data, zeroByteOffset: 1)
    }

    private func looksLikeUTF16BigEndian(_ data: Data) -> Bool {
        looksLikeUTF16(data, zeroByteOffset: 0)
    }

    private func looksLikeUTF16(_ data: Data, zeroByteOffset: Int) -> Bool {
        guard data.count >= 4 else {
            return false
        }

        let sampleCount = min(data.count, 512)
        var expectedZeroBytes = 0
        var expectedPositions = 0
        var oppositeZeroBytes = 0
        var oppositePositions = 0

        for index in 0..<sampleCount {
            if index % 2 == zeroByteOffset {
                expectedPositions += 1
                if data[index] == 0 {
                    expectedZeroBytes += 1
                }
            } else {
                oppositePositions += 1
                if data[index] == 0 {
                    oppositeZeroBytes += 1
                }
            }
        }

        return expectedPositions > 0
            && oppositePositions > 0
            && expectedZeroBytes * 100 / expectedPositions >= 30
            && oppositeZeroBytes * 100 / oppositePositions <= 10
    }
}
