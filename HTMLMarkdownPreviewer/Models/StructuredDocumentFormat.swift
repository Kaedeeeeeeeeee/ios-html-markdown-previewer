import Foundation

/// YAML and JSON use the same native reader, with independent parsers.
enum StructuredDocumentFormat: String, Sendable {
    case yaml, json
    var title: String { rawValue.uppercased() }
}

struct StructuredSourceRange: Decodable, Sendable {
    let start: Int
    let end: Int
}

extension YAMLDocument {
    /// Strings copy their decoded value. JSON collections copy an exact source
    /// slice, retaining numeric precision, whitespace, and member order.
    func copyValue(for row: YAMLRow) -> String? {
        guard row.isCollection else { return row.value }
        guard let range = row.sourceRange else { return nil }
        let bytes = Array(source.utf8)
        guard range.start >= 0, range.end >= range.start, range.end <= bytes.count else { return nil }
        return String(decoding: bytes[range.start..<range.end], as: UTF8.self)
    }
}
