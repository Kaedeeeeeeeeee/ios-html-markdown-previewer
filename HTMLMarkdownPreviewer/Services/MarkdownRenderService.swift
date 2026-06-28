import Foundation
import Markdown

final class MarkdownRenderService {
    func render(markdown: String, baseURL: URL? = nil) -> MarkdownDocument {
        let document = Document(parsing: markdown)
        let blocks = document.children.flatMap { renderBlock($0, baseURL: baseURL) }
        return MarkdownDocument(blocks: blocks)
    }

    func render(fileURL: URL) throws -> MarkdownDocument {
        let markdown = try String(contentsOf: fileURL, encoding: .utf8)
        return render(markdown: markdown, baseURL: fileURL.deletingLastPathComponent())
    }

    private func renderBlock(_ markup: Markup, baseURL: URL?) -> [MarkdownBlock] {
        switch markup {
        case let heading as Heading:
            return [.heading(level: min(max(heading.level, 1), 6), text: renderInlineChildren(of: heading))]
        case let paragraph as Paragraph:
            if let image = paragraph.children.compactMap({ $0 as? Markdown.Image }).first,
               paragraph.childCount == 1 {
                return [.image(renderImage(image, baseURL: baseURL))]
            }
            return [.paragraph(renderInlineChildren(of: paragraph))]
        case let codeBlock as CodeBlock:
            return [.codeBlock(language: codeBlock.language, code: codeBlock.code)]
        case let quote as BlockQuote:
            return [.blockQuote(quote.children.flatMap { renderBlock($0, baseURL: baseURL) })]
        case let list as UnorderedList:
            return [.unorderedList(renderListItems(from: list, baseURL: baseURL))]
        case let list as OrderedList:
            return [.orderedList(start: Int(list.startIndex), items: renderListItems(from: list, baseURL: baseURL))]
        case _ as ThematicBreak:
            return [.thematicBreak]
        default:
            let fallback = plainText(from: markup).trimmingCharacters(in: .whitespacesAndNewlines)
            return fallback.isEmpty ? [] : [.paragraph(AttributedString(fallback))]
        }
    }

    private func renderListItems(from container: ListItemContainer, baseURL: URL?) -> [MarkdownListItem] {
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
                    nestedBlocks.append(contentsOf: renderBlock(itemChild, baseURL: baseURL))
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

    private func renderImage(_ image: Markdown.Image, baseURL: URL?) -> MarkdownImage {
        let source = image.source ?? ""
        let altText = image.plainText
        let kind: MarkdownImage.SourceKind

        if let url = URL(string: source), let scheme = url.scheme?.lowercased() {
            switch scheme {
            case "http", "https":
                kind = .remoteBlocked(source)
            case "file":
                kind = .local(url)
            default:
                kind = .unsupported(source)
            }
        } else if let baseURL {
            kind = .local(baseURL.appendingPathComponent(source))
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
}
