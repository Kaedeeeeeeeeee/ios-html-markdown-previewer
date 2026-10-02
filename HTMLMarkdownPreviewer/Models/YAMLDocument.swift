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
    var id: String { "yaml-line-\(number)" }
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

    init(documentIndex: Int, mode: YAMLPreviewMode, target: String) {
        self.documentIndex = documentIndex
        self.mode = mode
        self.target = target
    }

    init?(_ position: ReadingPosition?) {
        guard let encoded = position?.anchorID else { return nil }
        let parts = encoded.split(separator: ":", maxSplits: 3).map(String.init)
        guard parts.count == 4, parts[0] == "yaml", let index = Int(parts[1]), index >= 0,
              let mode = YAMLPreviewMode(rawValue: parts[2]),
              parts[3].hasPrefix(mode == .source ? "yaml-line-" : "yaml-\(index)-") else { return nil }
        self.init(documentIndex: index, mode: mode, target: parts[3])
    }

    var position: ReadingPosition {
        ReadingPosition(anchorID: "yaml:\(documentIndex):\(mode.rawValue):\(target)", progress: 0)
    }
}
