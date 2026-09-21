import Foundation
import UIKit

/// Builds a self-contained print document from the same safe model used on screen.
/// User-authored HTML and resource URLs are never inserted as executable markup.
struct MarkdownPrintHTMLRenderer {
    func render(_ document: MarkdownDocument, title: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
        <title>\(escaped(title))</title>
        <style>
        :root { color-scheme: light; }
        * { box-sizing: border-box; }
        html, body { margin: 0; padding: 0; background: white; color: #171717; }
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; font-size: 11pt; line-height: 1.5; overflow-wrap: anywhere; }
        h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1.2em 0 .5em; break-after: avoid; page-break-after: avoid; }
        h1 { font-size: 24pt; } h2 { font-size: 19pt; } h3 { font-size: 15pt; }
        h4, h5, h6 { font-size: 12pt; }
        p { margin: 0 0 .8em; orphans: 3; widows: 3; }
        blockquote { margin: .8em 0; padding: .1em 0 .1em 12pt; border-left: 3pt solid #b8b8b8; color: #424242; }
        ul, ol { padding-left: 24pt; margin: .5em 0 1em; }
        li { margin: .3em 0; }
        li > ul, li > ol { margin-bottom: .4em; }
        code, pre { font-family: ui-monospace, Menlo, monospace; font-size: 9pt; }
        code { background: #f1f1f1; padding: 1pt 3pt; border-radius: 2pt; }
        pre { padding: 10pt; background: #f1f1f1; white-space: pre-wrap; overflow-wrap: anywhere; word-break: break-word; }
        pre code { padding: 0; background: transparent; }
        .code-language { font-size: 8pt; color: #626262; margin-bottom: 3pt; }
        .link { color: #185f9c; text-decoration: underline; }
        table { width: 100%; table-layout: fixed; border-collapse: collapse; margin: .8em 0 1em; font-size: 10pt; }
        thead { display: table-header-group; }
        tr { break-inside: avoid; page-break-inside: avoid; }
        th, td { border: .6pt solid #bdbdbd; padding: 6pt; vertical-align: top; overflow-wrap: anywhere; word-break: break-word; }
        th { background: #f0f0f0; font-weight: 600; }
        .align-leading { text-align: left; } .align-center { text-align: center; } .align-trailing { text-align: right; }
        figure { margin: .8em 0; break-inside: avoid; page-break-inside: avoid; }
        img { display: block; max-width: 100%; max-height: 650pt; width: auto; height: auto; object-fit: contain; }
        .image-placeholder { padding: 10pt; border: .6pt solid #bdbdbd; color: #626262; }
        .image-placeholder strong { display: block; color: #424242; }
        hr { border: 0; border-top: .6pt solid #bdbdbd; margin: 14pt 0; }
        </style>
        </head>
        <body>\(renderBlocks(document.blocks))</body>
        </html>
        """
    }

    private func renderBlocks(_ blocks: [MarkdownBlock]) -> String {
        blocks.map(renderBlock).joined(separator: "\n")
    }

    private func renderBlock(_ block: MarkdownBlock) -> String {
        switch block {
        case .heading(let level, let text):
            let level = min(max(level, 1), 6)
            return "<h\(level)>\(renderInline(text))</h\(level)>"
        case .paragraph(let text):
            return "<p>\(renderInline(text))</p>"
        case .blockQuote(let blocks):
            return "<blockquote>\(renderBlocks(blocks))</blockquote>"
        case .codeBlock(let language, let code):
            let caption = language.flatMap { $0.isEmpty ? nil : "<div class=\"code-language\">\(escaped($0))</div>" } ?? ""
            return "\(caption)<pre><code>\(escaped(code))</code></pre>"
        case .unorderedList(let items):
            return "<ul>\(renderListItems(items))</ul>"
        case .orderedList(let start, let items):
            return "<ol start=\"\(start)\">\(renderListItems(items))</ol>"
        case .table(let table):
            return renderTable(table)
        case .image(let image):
            return renderImage(image)
        case .thematicBreak:
            return "<hr>"
        }
    }

    private func renderListItems(_ items: [MarkdownListItem]) -> String {
        items.map { item in
            "<li>\(renderInline(item.text))\(renderBlocks(item.children))</li>"
        }.joined()
    }

    private func renderTable(_ table: MarkdownTable) -> String {
        let columnCount = table.header.count
        guard columnCount > 0 else { return "" }

        func row(_ cells: [AttributedString], tag: String) -> String {
            let contents = (0..<columnCount).map { index in
                let alignment: String
                switch table.columnAlignments.indices.contains(index) ? table.columnAlignments[index] : .leading {
                case .leading: alignment = "leading"
                case .center: alignment = "center"
                case .trailing: alignment = "trailing"
                }
                let text = cells.indices.contains(index) ? renderInline(cells[index]) : ""
                let scope = tag == "th" ? " scope=\"col\"" : ""
                return "<\(tag)\(scope) class=\"align-\(alignment)\">\(text)</\(tag)>"
            }.joined()
            return "<tr>\(contents)</tr>"
        }

        return "<table><thead>\(row(table.header, tag: "th"))</thead><tbody>\(table.rows.map { row($0, tag: "td") }.joined())</tbody></table>"
    }

    private func renderInline(_ text: AttributedString) -> String {
        text.runs.map { run in
            var content = escaped(String(text[run.range].characters))
                .replacingOccurrences(of: "\n", with: "<br>")
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) { content = "<code>\(content)</code>" }
            if intent.contains(.stronglyEmphasized) { content = "<strong>\(content)</strong>" }
            if intent.contains(.emphasized) { content = "<em>\(content)</em>" }
            if intent.contains(.strikethrough) { content = "<s>\(content)</s>" }
            // Keep the preview's link appearance without introducing navigable URLs.
            if run.link != nil { content = "<span class=\"link\">\(content)</span>" }
            return content
        }.joined()
    }

    private func renderImage(_ image: MarkdownImage) -> String {
        switch image.kind {
        case .local(let url):
            guard url.isFileURL,
                  let rasterImage = UIImage(contentsOfFile: url.path),
                  let data = rasterImage.pngData() else {
                return imagePlaceholder(AppStrings.MarkdownImages.localUnavailable, image: image)
            }
            let altText = image.altText.isEmpty ? AppStrings.Accessibility.markdownImage : image.altText
            return "<figure><img src=\"data:image/png;base64,\(data.base64EncodedString())\" alt=\"\(escaped(altText))\"></figure>"
        case .remoteBlocked:
            return imagePlaceholder(AppStrings.MarkdownImages.remoteBlocked, image: image)
        case .unsupported:
            return imagePlaceholder(AppStrings.MarkdownImages.unsupported, image: image)
        }
    }

    private func imagePlaceholder(_ title: String, image: MarkdownImage) -> String {
        let altText = image.altText.isEmpty ? "" : "<br>\(escaped(image.altText))"
        return "<div class=\"image-placeholder\"><strong>\(escaped(title))</strong>\(escaped(image.source))\(altText)</div>"
    }

    private func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
