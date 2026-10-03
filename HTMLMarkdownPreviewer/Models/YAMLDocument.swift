import Foundation

enum YAMLPreviewMode: String, CaseIterable, Identifiable, Sendable {
    case structure, source
    var id: String { rawValue }
    var title: String { self == .structure ? YAMLStrings.structure : YAMLStrings.source }
}

struct YAMLDocument: Sendable {
    let source: String
    let sheets: [YAMLSheet]
    let issue: YAMLIssue?
    let lines: [YAMLSourceLine]
    let isSourceTruncated: Bool
}

struct YAMLSheet: Decodable, Sendable {
    let index: Int
    let startLine: Int
    let endLine: Int
    let rows: [YAMLRow]
    let issue: YAMLIssue?
}

struct YAMLRow: Decodable, Identifiable, Sendable {
    enum Kind: String, Decodable, Sendable { case object, array, string, number, boolean, null, alias }
    let id: String
    let label: String
    let path: String
    let depth: Int
    let parents: [String]
    let kind: Kind
    let value: String
    let line: Int
    let column: Int
    let count: Int
    let anchor: String
    let tag: String
    /// Byte offsets into the original UTF-8 source, used by JSON to copy
    /// collections without re-encoding numbers or storing every subtree twice.
    let sourceRange: StructuredSourceRange?

    var isCollection: Bool { kind == .object || kind == .array }
    var isExpandable: Bool { isCollection && count > 0 }
    func matches(_ query: String) -> Bool {
        label.localizedStandardContains(query) || path.localizedStandardContains(query)
            || value.localizedStandardContains(query)
    }
}

struct YAMLIssue: Decodable, Sendable {
    let code: String
    let message: String
    let line: Int
    let column: Int
}

struct YAMLSourceLine: Identifiable, Sendable {
    let number: Int
    var tokens: [YAMLSourceToken]
    var format: StructuredDocumentFormat = .yaml
    var id: String { "\(format.rawValue)-line-\(number)" }
    var text: String { tokens.map(\.text).joined() }
}

struct YAMLSourceToken: Sendable {
    let text: String
    let style: String
}

/// Uses the existing per-document reading store. The identifier includes the
/// selected YAML document and view; source lines never collide with tree rows.
struct YAMLReadingLocation {
    let documentIndex: Int
    let mode: YAMLPreviewMode
    let target: String
    let format: StructuredDocumentFormat

    init(documentIndex: Int, mode: YAMLPreviewMode, target: String, format: StructuredDocumentFormat = .yaml) {
        self.documentIndex = documentIndex
        self.mode = mode
        self.target = target
        self.format = format
    }

    init?(_ position: ReadingPosition?, format: StructuredDocumentFormat = .yaml) {
        guard let encoded = position?.anchorID else { return nil }
        let parts = encoded.split(separator: ":", maxSplits: 3).map(String.init)
        guard parts.count == 4, parts[0] == format.rawValue, let index = Int(parts[1]), index >= 0,
              let mode = YAMLPreviewMode(rawValue: parts[2]),
              parts[3].hasPrefix(mode == .source ? "\(format.rawValue)-line-" : "\(format.rawValue)-\(index)-") else { return nil }
        self.init(documentIndex: index, mode: mode, target: parts[3], format: format)
    }

    var position: ReadingPosition {
        ReadingPosition(anchorID: "\(format.rawValue):\(documentIndex):\(mode.rawValue):\(target)", progress: 0)
    }
}
