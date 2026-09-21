import Foundation

struct MarkdownDocument: Equatable, Sendable {
    var blocks: [MarkdownBlock]
}

enum MarkdownBlock: Equatable, Sendable, Identifiable {
    case heading(level: Int, text: AttributedString)
    case paragraph(AttributedString)
    case blockQuote([MarkdownBlock])
    case codeBlock(language: String?, code: String)
    case unorderedList([MarkdownListItem])
    case orderedList(start: Int, items: [MarkdownListItem])
    case table(MarkdownTable)
    case image(MarkdownImage)
    case thematicBreak

    var id: String {
        switch self {
        case .heading(let level, let text):
            "heading-\(level)-\(text.characters)"
        case .paragraph(let text):
            "paragraph-\(text.characters)"
        case .blockQuote(let blocks):
            "blockquote-\(blocks.count)-\(blocks.map(\.id).joined(separator: "-"))"
        case .codeBlock(let language, let code):
            "code-\(language ?? "plain")-\(code.hashValue)"
        case .unorderedList(let items):
            "ul-\(items.map(\.id).joined(separator: "-"))"
        case .orderedList(let start, let items):
            "ol-\(start)-\(items.map(\.id).joined(separator: "-"))"
        case .table(let table):
            "table-\(table.header)-\(table.rows)-\(table.columnAlignments)"
        case .image(let image):
            "image-\(image.source)-\(image.altText)"
        case .thematicBreak:
            "thematic-break"
        }
    }
}

struct MarkdownTable: Equatable, Sendable {
    enum ColumnAlignment: Equatable, Sendable {
        case leading
        case center
        case trailing
    }

    let columnAlignments: [ColumnAlignment]
    let header: [AttributedString]
    let rows: [[AttributedString]]

    init(columnAlignments: [ColumnAlignment], header: [AttributedString], rows: [[AttributedString]]) {
        let columnCount = max(header.count, rows.map(\.count).max() ?? 0)
        self.columnAlignments = Array(columnAlignments.prefix(columnCount))
            + Array(repeating: .leading, count: max(0, columnCount - columnAlignments.count))
        self.header = header + Array(repeating: AttributedString(), count: columnCount - header.count)
        self.rows = rows.map { row in
            row + Array(repeating: AttributedString(), count: columnCount - row.count)
        }
    }
}

struct MarkdownListItem: Equatable, Sendable, Identifiable {
    var text: AttributedString
    var children: [MarkdownBlock]

    var id: String {
        "item-\(text.characters)-\(children.map(\.id).joined(separator: "-"))"
    }
}

struct MarkdownImage: Equatable, Sendable {
    enum SourceKind: Equatable, Sendable {
        case local(URL)
        case remoteBlocked(String)
        case unsupported(String)
    }

    var source: String
    var altText: String
    var title: String?
    var kind: SourceKind
}
