import Foundation

enum YAMLStrings {
    private static func text(_ key: String, _ fallback: String) -> String {
        NSLocalizedString(key, tableName: "YAML", bundle: .main, value: fallback, comment: "")
    }
    static var structure: String { text("structure", "Structure") }
    static var source: String { text("source", "Source") }
    static var search: String { text("search", "Find keys or values") }
    static var searchSource: String { text("searchSource", "Find in source") }
    static var clearSearch: String { text("clearSearch", "Clear search") }
    static var previous: String { text("previous", "Previous result") }
    static var next: String { text("next", "Next result") }
    static var noMatches: String { text("noMatches", "No matches") }
    static var copyValue: String { text("copyValue", "Copy Value") }
    static var copyPath: String { text("copyPath", "Copy Field Path") }
    static var copySource: String { text("copySource", "Copy Source") }
    static var viewSource: String { text("viewSource", "Show Source Line") }
    static var expandAll: String { text("expandAll", "Expand All") }
    static var collapseAll: String { text("collapseAll", "Collapse All") }
    static var options: String { text("options", "YAML options") }
    static var copied: String { text("copied", "Copied") }
    static var syntaxError: String { text("syntaxError", "YAML syntax error") }
    static var showError: String { text("showError", "Show Error Line") }
    static var empty: String { text("empty", "Empty YAML document") }
    static var sourceLimited: String { text("sourceLimited", "Showing a source excerpt. Share the original file to access all content.") }
    static var sizeLimit: String { text("sizeLimit", "This file is larger than 2 MB. A source excerpt is available; the original file is preserved.") }
    static var depthLimit: String { text("depthLimit", "This YAML is too deeply nested for structure preview. You can still read the source.") }
    static var nodeLimit: String { text("nodeLimit", "This YAML has too many fields for structure preview. You can still read the source.") }
    static var documentLimit: String { text("documentLimit", "Structure preview supports up to 100 documents per file. You can still read the source.") }
    static var runtimeError: String { text("runtime", "Structure preview is unavailable. The source remains readable.") }
    static var sampleTitle: String { text("sampleTitle", "App configuration") }
    static var sampleSubtitle: String { text("sampleSubtitle", "YAML · Nested fields & multiple documents") }
    static var root: String { text("root", "Document") }
    static func document(_ index: Int, count: Int) -> String {
        String(format: text("documentCount", "Document %d of %d"), index + 1, count)
    }
    static func results(_ index: Int, count: Int) -> String {
        count == 0 ? noMatches : String(format: text("resultCount", "%d of %d"), index + 1, count)
    }
    static func location(line: Int, column: Int) -> String {
        String(format: text("location", "Line %d, column %d"), line, column)
    }
    static func line(_ number: Int) -> String { String(format: text("line", "Line %d"), number) }
    static func kind(_ kind: YAMLRow.Kind, count: Int = 0) -> String {
        let label = text("kind.\(kind.rawValue)", kind.rawValue.capitalized)
        return kind == .object || kind == .array ? "\(label) · \(count)" : label
    }
    static func issue(_ issue: YAMLIssue) -> String {
        switch issue.code {
        case "sizeLimit": sizeLimit
        case "depthLimit": depthLimit
        case "nodeLimit": nodeLimit
        case "documentLimit": documentLimit
        case "syntax": location(line: issue.line, column: issue.column)
        default: runtimeError
        }
    }
}
