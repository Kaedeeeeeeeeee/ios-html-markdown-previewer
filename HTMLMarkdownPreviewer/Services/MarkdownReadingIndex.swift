import Foundation

/// Positions are based on document structure, never on title text, so repeated
/// headings and identical paragraphs remain distinct navigation destinations.
struct MarkdownReadingIndex {
    struct StoredAnchor: Equatable {
        let blockID: String
        let fraction: Double

        init(blockID: String, fraction: Double) {
            self.blockID = blockID
            self.fraction = fraction.isFinite ? min(1, max(0, fraction)) : 0
        }

        init?(_ value: String?) {
            guard let value else { return nil }
            let parts = value.split(separator: "@", maxSplits: 1).map(String.init)
            guard let block = parts.first, block.hasPrefix("markdown-block-"),
                  Int(block.dropFirst("markdown-block-".count)) != nil else { return nil }
            let fraction = parts.count == 2 ? Double(parts[1]) ?? 0 : 0
            self.init(blockID: block, fraction: fraction)
        }

        var encoded: String { "\(blockID)@\(fraction)" }
    }

    struct Element: Equatable {
        let id: String
        let blockID: String
        let text: String
    }

    struct Match: Equatable {
        let elementID: String
        let blockID: String
        let range: Range<String.Index>
    }

    struct SearchTarget: Hashable {
        let index: Int
        let elementID: String
        let range: NSRange

        var anchorID: String { "markdown-match-\(index)-\(elementID)-\(range.location)-\(range.length)" }
    }

    let headings: [DocumentHeading]
    let elements: [Element]
    let blockIDs: [String]

    init(document: MarkdownDocument) {
        var headings: [DocumentHeading] = []
        var elements: [Element] = []
        blockIDs = document.blocks.indices.map(Self.blockID)

        func visit(_ block: MarkdownBlock, path: String, blockID: String) {
            func append(_ text: AttributedString, id: String) {
                elements.append(Element(id: id, blockID: blockID, text: String(text.characters)))
            }

            switch block {
            case .heading(let level, let text):
                headings.append(DocumentHeading(id: path, title: String(text.characters), level: level))
                append(text, id: path)
            case .paragraph(let text):
                append(text, id: path)
            case .blockQuote(let children):
                for (offset, child) in children.enumerated() {
                    visit(child, path: Self.childID(path, offset: offset), blockID: blockID)
                }
            case .codeBlock(_, let code):
                elements.append(Element(id: path, blockID: blockID, text: code))
            case .unorderedList(let items), .orderedList(_, let items):
                for (offset, item) in items.enumerated() {
                    let itemID = Self.itemID(path, offset: offset)
                    append(item.text, id: itemID)
                    for (childOffset, child) in item.children.enumerated() {
                        visit(child, path: Self.childID(itemID, offset: childOffset), blockID: blockID)
                    }
                }
            case .table(let table):
                for (column, cell) in table.header.enumerated() {
                    append(cell, id: Self.cellID(path, row: -1, column: column))
                }
                for (row, cells) in table.rows.enumerated() {
                    for (column, cell) in cells.enumerated() {
                        append(cell, id: Self.cellID(path, row: row, column: column))
                    }
                }
            case .image, .thematicBreak:
                break
            }
        }

        for (offset, block) in document.blocks.enumerated() {
            let blockID = Self.blockID(offset)
            visit(block, path: blockID, blockID: blockID)
        }
        self.headings = headings
        self.elements = elements
    }

    func matches(for query: String) -> [Match] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return elements.flatMap { element in
            var matches: [Match] = []
            var searchStart = element.text.startIndex
            while searchStart < element.text.endIndex,
                  let range = element.text.range(
                    of: query,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchStart..<element.text.endIndex
                  ), !range.isEmpty {
                matches.append(Match(elementID: element.id, blockID: element.blockID, range: range))
                searchStart = range.upperBound
            }
            return matches
        }
    }

    func blockID(containing elementID: String) -> String? {
        elements.first { $0.id == elementID }?.blockID
    }

    func target(for match: Match, at offset: Int) -> SearchTarget? {
        guard let element = elements.first(where: { $0.id == match.elementID }) else { return nil }
        return SearchTarget(index: offset, elementID: match.elementID, range: NSRange(match.range, in: element.text))
    }

    static func blockID(_ offset: Int) -> String { "markdown-block-\(offset)" }
    static func elementAnchorID(_ id: String) -> String { "markdown-text-\(id)" }
    static func childID(_ parent: String, offset: Int) -> String { "\(parent)-child-\(offset)" }
    static func itemID(_ parent: String, offset: Int) -> String { "\(parent)-item-\(offset)" }
    static func cellID(_ parent: String, row: Int, column: Int) -> String {
        "\(parent)-row-\(row)-column-\(column)"
    }
}
