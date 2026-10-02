import Foundation

enum JSONStrings {
    private static func text(_ key: String, _ fallback: String) -> String {
        NSLocalizedString(key, tableName: "JSON", bundle: .main, value: fallback, comment: "")
    }
    static var options: String { text("options", "JSON options") }
    static var syntaxError: String { text("syntaxError", "JSON syntax error") }
    static var empty: String { text("empty", "Empty JSON document") }
    static var sampleTitle: String { text("sampleTitle", "API response") }
    static var sampleSubtitle: String { text("sampleSubtitle", "JSON · Structured data & exact values") }

    static func issue(_ issue: YAMLIssue) -> String {
        switch issue.code {
        case "sizeLimit": YAMLStrings.sizeLimit
        case "depthLimit": text("depthLimit", "This JSON is too deeply nested for structure preview. You can still read the source.")
        case "nodeLimit": text("nodeLimit", "This JSON has too many fields or overly long field paths for structure preview. You can still read the source.")
        case "encoding": text("encoding", "This file is not valid UTF-8. The source preview may contain replacement characters; the original file is preserved.")
        case "syntax": YAMLStrings.location(line: issue.line, column: issue.column)
        default: YAMLStrings.runtimeError
        }
    }

    static func syntaxMessage(_ reason: String) -> String {
        let fallback: String
        switch reason {
        case "expectedValue": fallback = "Expected a JSON value. Comments and trailing commas are not supported."
        case "expectedKey": fallback = "Expected a double-quoted object key. Trailing commas are not supported."
        case "expectedColon": fallback = "Expected a colon after the object key."
        case "expectedObjectEnd": fallback = "Expected a comma or closing brace."
        case "expectedArrayEnd": fallback = "Expected a comma or closing bracket."
        case "trailingContent": fallback = "Unexpected content after the JSON value."
        case "controlCharacter": fallback = "Control characters inside strings must be escaped."
        case "unterminatedString": fallback = "The string is missing its closing double quote."
        case "invalidEscape": fallback = "This string contains an invalid JSON escape."
        case "invalidUnicode": fallback = "This string contains an invalid Unicode escape or surrogate pair."
        case "invalidNumber": fallback = "Invalid JSON number. Check leading zeros, fraction digits, and the exponent."
        default: fallback = "This file does not contain valid JSON."
        }
        return text("error.\(reason)", fallback)
    }
}
