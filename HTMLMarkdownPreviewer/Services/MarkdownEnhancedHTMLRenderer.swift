import Foundation
import UIKit

/// A document assembled exclusively from the safe Markdown model. The only
/// executable code is the renderer shipped with the app, never imported HTML.
struct MarkdownEnhancedHTMLRenderer {
    func render(_ document: MarkdownDocument, title: String, forPrinting: Bool = false) -> String {
        var builder = Builder(forPrinting: forPrinting)
        let body = builder.blocks(document.blocks, parent: nil)
        let nonce = UUID().uuidString
        let origin = MarkdownWebResources.origin
        return """
        <!doctype html><html lang="\(escape(Locale.current.language.languageCode?.identifier ?? "en"))"><head>
        <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; font-src \(origin); style-src 'unsafe-inline' \(origin); script-src 'nonce-\(nonce)' \(origin); connect-src 'none'; base-uri 'none'; form-action 'none'; frame-src 'none'; object-src 'none'">
        <title>\(escape(title))</title>
        <link rel="stylesheet" href="\(origin)/katex.min.css">
        <style>\(Self.styles)</style>
        </head><body\(forPrinting ? " class=\"printing\"" : "")
          data-copy-label="\(escape(MarkdownEnhancementStrings.copy))"
          data-copied-label="\(escape(MarkdownEnhancementStrings.copied))"
          data-math-error="\(escape(MarkdownEnhancementStrings.mathError))"
          data-diagram-error="\(escape(MarkdownEnhancementStrings.diagramError))">
        <main>\(body)</main>
        <script src="\(origin)/markdown-libraries.min.js"></script>
        <script nonce="\(nonce)">\(MarkdownEnhancementScript.source)</script>
        </body></html>
        """
    }

    private struct Builder {
        let forPrinting: Bool
        var imageIndex = 0

        mutating func blocks(_ blocks: [MarkdownBlock], parent: String?) -> String {
            var result = ""
            for (offset, block) in blocks.enumerated() {
                let path = parent.map { MarkdownReadingIndex.childID($0, offset: offset) }
                    ?? MarkdownReadingIndex.blockID(offset)
                let content = render(block, path: path)
                result += parent == nil ? "<div data-markdown-block=\"\(path)\">\(content)</div>" : content
            }
            return result
        }

        mutating func render(_ block: MarkdownBlock, path: String) -> String {
            switch block {
            case .heading(let level, let text):
                let level = min(6, max(1, level))
                return "<h\(level) id=\"\(path)\" data-reading-heading-id=\"\(path)\" data-reading-heading-title=\"\(escape(String(text.characters)))\">\(inline(text))</h\(level)>"
            case .paragraph(let text): return "<p>\(inline(text))</p>"
            case .blockQuote(let children): return "<blockquote>\(blocks(children, parent: path))</blockquote>"
            case .mathBlock(let source):
                return math(source, display: true)
            case .codeBlock(let language, let code):
                if language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "mermaid" {
                    let caption = escape(MarkdownEnhancementStrings.diagram)
                    return """
                    <figure class="diagram-block"><div class="code-toolbar" data-reading-ignore><span>\(caption)</span></div>
                    <div class="mermaid-diagram" data-reading-atomic data-reading-text="\(escape(code))"><pre class="diagram-source">\(escape(code))</pre></div></figure>
                    """
                }
                let name = language?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let label = name.isEmpty ? MarkdownEnhancementStrings.code : name
                let copy = forPrinting ? "" : "<button class=\"copy-code\" type=\"button\" aria-label=\"\(escape(MarkdownEnhancementStrings.copy))\"><span class=\"copy-icon\" aria-hidden=\"true\"></span> <span class=\"copy-label\">\(escape(MarkdownEnhancementStrings.copy))</span></button>"
                return """
                <section class="code-block"><div class="code-toolbar" data-reading-ignore><span>\(escape(label))</span>\(copy)</div>
                <pre><code data-language="\(escape(name))">\(escape(code))</code></pre></section>
                """
            case .unorderedList(let items): return "<ul>\(list(items, path: path))</ul>"
            case .orderedList(let start, let items): return "<ol start=\"\(start)\">\(list(items, path: path))</ol>"
            case .table(let table):
                func row(_ cells: [AttributedString], header: Bool) -> String {
                    var result = "<tr>"
                    for (column, cell) in cells.enumerated() {
                        let tag = header ? "th" : "td"
                        let alignment: String
                        switch table.columnAlignments.indices.contains(column) ? table.columnAlignments[column] : .leading {
                        case .leading: alignment = "left"
                        case .center: alignment = "center"
                        case .trailing: alignment = "right"
                        }
                        result += "<\(tag)\(header ? " scope=\"col\"" : "") style=\"text-align:\(alignment)\">\(inline(cell))</\(tag)>"
                    }
                    return result + "</tr>"
                }
                return "<div class=\"table-scroll\"><table><thead>\(row(table.header, header: true))</thead><tbody>\(table.rows.map { row($0, header: false) }.joined())</tbody></table></div>"
            case .image(let image):
                let index = imageIndex
                imageIndex += 1
                let alt = image.altText.isEmpty ? AppStrings.Accessibility.markdownImage : image.altText
                if case .local(let url) = image.kind, url.isFileURL,
                   let value = UIImage(contentsOfFile: url.path), let data = value.pngData() {
                    let action = forPrinting ? "" : " data-image-index=\"\(index)\" role=\"button\" tabindex=\"0\" aria-label=\"\(escape(alt))\""
                    return "<figure class=\"document-image\"><img\(action) src=\"data:image/png;base64,\(data.base64EncodedString())\" alt=\"\(escape(alt))\"></figure>"
                }
                let reason: String
                switch image.kind {
                case .local: reason = AppStrings.MarkdownImages.localUnavailable
                case .remoteBlocked: reason = AppStrings.MarkdownImages.remoteBlocked
                case .unsupported: reason = AppStrings.MarkdownImages.unsupported
                }
                return "<div class=\"image-placeholder\"><strong>\(escape(reason))</strong><br>\(escape(image.source))<br>\(escape(alt))</div>"
            case .thematicBreak: return "<hr>"
            }
        }

        mutating func list(_ items: [MarkdownListItem], path: String) -> String {
            var result = ""
            for (offset, item) in items.enumerated() {
                let itemPath = MarkdownReadingIndex.itemID(path, offset: offset)
                result += "<li>\(inline(item.text))\(blocks(item.children, parent: itemPath))</li>"
            }
            return result
        }

        func math(_ source: String, display: Bool) -> String {
            let tag = display ? "div" : "span"
            return "<\(tag) class=\"math\(display ? " math-display" : "")\" data-math-display=\"\(display)\" data-reading-atomic data-reading-text=\"\(escape(source))\">\(escape(source))</\(tag)>"
        }

        func inline(_ text: AttributedString) -> String {
            text.runs.map { run in
                var value: String
                if let source = run[MarkdownMathAttribute.self] {
                    value = math(source, display: false)
                } else {
                    value = escape(String(text[run.range].characters)).replacingOccurrences(of: "\n", with: "<br>")
                }
                let intent = run.inlinePresentationIntent ?? []
                if intent.contains(.code) { value = "<code>\(value)</code>" }
                if intent.contains(.stronglyEmphasized) { value = "<strong>\(value)</strong>" }
                if intent.contains(.emphasized) { value = "<em>\(value)</em>" }
                if intent.contains(.strikethrough) { value = "<s>\(value)</s>" }
                if let url = run.link, !forPrinting {
                    value = "<span class=\"link\" role=\"link\" tabindex=\"0\" data-link-url=\"\(escape(url.absoluteString))\">\(value)</span>"
                } else if run.link != nil { value = "<span class=\"link\">\(value)</span>" }
                return value
            }.joined()
        }
    }

    private static let styles = #"""
    :root { color-scheme: light dark; --reader-scale:1; --reader-spacing:0px; --ink:#202124; --muted:#70757c; --paper:#fff; --soft:#f5f6f8; --border:#e5e7eb; --accent:#087db9; --keyword:#a33687; --string:#38774d; --number:#a36226; --title:#3068a7; }
    @media(prefers-color-scheme:dark) { :root { --ink:#e8e9ed; --muted:#a0a5ae; --paper:#000; --soft:#151619; --border:#303238; --accent:#65c4ee; --keyword:#e0a2d4; --string:#a8d6a2; --number:#ecc28b; --title:#91bdeb; } }
    * { box-sizing:border-box; } html,body { margin:0; padding:0; background:var(--paper); color:var(--ink); }
    body { font-family:-apple-system,BlinkMacSystemFont,sans-serif; font-size:calc(var(--reader-base-size,17px) * var(--reader-scale)); line-height:calc(1.5em + var(--reader-spacing)); overflow-wrap:anywhere; -webkit-text-size-adjust:100%; }
    main { max-width:728px; margin:auto; padding:28px 24px; }
    [data-markdown-block] { margin-bottom:18px; } [data-markdown-block]:last-child { margin-bottom:0; }
    h1,h2,h3,h4,h5,h6 { line-height:1.25; letter-spacing:-.025em; margin:1.15em 0 .55em; font-weight:700; } h1 { font-size:2em; } h2 { font-size:1.55em; } h3 { font-size:1.22em; } h4,h5,h6 { font-size:1.05em; } [data-markdown-block]:first-child h1 { margin-top:0; }
    p { margin:0 0 .8em; } p:last-child { margin-bottom:0; } ul,ol { padding-left:1.6em; margin:.4em 0 .8em; } li { padding-left:.15em; margin:.35em 0; } li p { margin:.4em 0; }
    blockquote { margin:0; padding:2px 0 2px 16px; border-left:3px solid var(--border); color:var(--muted); }
    code,pre { font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-size:.88em; } :not(pre)>code { border-radius:4px; background:var(--soft); padding:2px 4px; }
    .code-block,.diagram-block { margin:0; border:1px solid var(--border); border-radius:14px; background:var(--soft); overflow:hidden; }
    .code-toolbar { display:flex; align-items:center; justify-content:space-between; gap:12px; min-height:44px; padding:0 14px; color:var(--muted); border-bottom:1px solid var(--border); font-size:.72em; font-weight:600; line-height:1.4; }
    .code-toolbar>span { overflow-wrap:anywhere; } .copy-code { appearance:none; border:0; background:none; color:var(--accent); font:inherit; min-height:44px; padding:8px 0 8px 10px; flex-shrink:0; cursor:pointer; } .copy-icon { display:inline-block; position:relative; width:12px; height:14px; margin-right:3px; vertical-align:-2px; } .copy-icon::before,.copy-icon::after { content:""; position:absolute; width:8px; height:10px; border:1px solid currentColor; border-radius:2px; } .copy-icon::before { left:0; top:0; } .copy-icon::after { left:3px; top:3px; background:var(--soft); } button:focus-visible,[tabindex]:focus-visible { outline:2px solid var(--accent); outline-offset:2px; }
    pre { margin:0; padding:16px; overflow-x:auto; white-space:pre; line-height:1.6; tab-size:4; } pre code { font-size:1em; padding:0; background:none; }
    .hljs-keyword,.hljs-selector-tag,.hljs-literal,.hljs-built_in,.hljs-type { color:var(--keyword); } .hljs-string,.hljs-regexp,.hljs-addition,.hljs-doctag { color:var(--string); } .hljs-number,.hljs-symbol,.hljs-bullet,.hljs-attr,.hljs-template-variable { color:var(--number); } .hljs-title,.hljs-section,.hljs-name,.hljs-selector-class { color:var(--title); } .hljs-comment,.hljs-quote,.hljs-meta { color:var(--muted); } .hljs-emphasis { font-style:italic; } .hljs-strong { font-weight:700; }
    .math { overflow-wrap:normal; } .math-display { overflow-x:auto; overflow-y:hidden; padding:10px 2px; } .katex-display { margin:.35em 0; } .math-display>.katex-display { width:max-content; min-width:100%; } .math-display>.katex-display>.katex { display:inline-block; width:max-content; white-space:nowrap; } .math-error { color:var(--muted); white-space:pre-wrap; font-family:ui-monospace,Menlo,monospace; font-size:.9em; }
    .mermaid-diagram { overflow-x:auto; padding:20px 12px; line-height:1.4; } .mermaid-diagram svg { display:block; max-width:100%; height:auto; margin:auto; } .mermaid-diagram .node rect,.mermaid-diagram .node polygon,.mermaid-diagram .node circle { fill:var(--paper)!important; stroke:var(--accent)!important; } .mermaid-diagram text,.mermaid-diagram .nodeLabel,.mermaid-diagram .label { fill:var(--ink)!important; color:var(--ink)!important; } .mermaid-diagram .flowchart-link,.mermaid-diagram .messageLine0,.mermaid-diagram .messageLine1 { stroke:var(--muted)!important; } .mermaid-diagram marker path { fill:var(--muted)!important; } .render-error { font-size:.8em; color:var(--muted); margin:0 0 8px; } .diagram-source { white-space:pre-wrap; padding:0; }
    .table-scroll { overflow-x:auto; border:1px solid var(--border); border-radius:10px; } table { border-collapse:collapse; min-width:100%; } th,td { border-bottom:1px solid var(--border); padding:10px 14px; min-width:100px; vertical-align:top; } th { background:var(--soft); font-weight:600; } tr:last-child td { border-bottom:0; }
    .document-image { margin:0; } .document-image img { display:block; max-width:100%; height:auto; border-radius:10px; } .document-image img[role=button] { cursor:zoom-in; } .image-placeholder { border:1px solid var(--border); border-radius:10px; padding:16px; color:var(--muted); font-size:.88em; } .link { color:var(--accent); text-decoration:underline; cursor:pointer; } hr { border:0; border-top:1px solid var(--border); margin:24px 0; }
    body.printing { color-scheme:light; --paper:#fff; --ink:#171717; --muted:#626262; --soft:#f4f4f4; --border:#bbb; --accent:#185f9c; --keyword:#91366e; --string:#316943; --number:#88551f; --title:#285a91; font-size:11pt; } body.printing main { padding:0; width:523.28px; max-width:100%; }
    body.printing table { table-layout:fixed; width:100%; } body.printing th,body.printing td { min-width:0; overflow-wrap:anywhere; }
    @media print { :root { color-scheme:light; } body { font-size:11pt; } main { padding:0; max-width:none; } h1,h2,h3,h4,h5,h6 { break-after:avoid; } p { orphans:3; widows:3; } pre { white-space:pre-wrap; overflow-wrap:anywhere; overflow:visible; } .copy-code { display:none!important; } .code-block { overflow:visible; } .diagram-block,.math-display,figure,tr { break-inside:avoid; } .table-scroll { overflow:visible; } table { table-layout:fixed; width:100%; } th,td { min-width:0; overflow-wrap:anywhere; } thead { display:table-header-group; } .math-display { overflow:visible; } .document-image img { max-height:650pt; object-fit:contain; } .mermaid-diagram svg { max-height:640px; } }
    """#
}

private func escape(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}

extension MarkdownDocument {
    var requiresEnhancedRendering: Bool {
        func hasMath(_ text: AttributedString) -> Bool { text.runs.contains { $0[MarkdownMathAttribute.self] != nil } }
        func needs(_ block: MarkdownBlock) -> Bool {
            switch block {
            case .codeBlock, .mathBlock: true
            case .heading(_, let text), .paragraph(let text): hasMath(text)
            case .blockQuote(let children): children.contains(where: needs)
            case .unorderedList(let items), .orderedList(_, let items): items.contains { hasMath($0.text) || $0.children.contains(where: needs) }
            case .table(let table): table.header.contains(where: hasMath) || table.rows.contains { $0.contains(where: hasMath) }
            case .image, .thematicBreak: false
            }
        }
        return blocks.contains(where: needs)
    }
}
