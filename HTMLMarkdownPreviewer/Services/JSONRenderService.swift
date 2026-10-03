import Foundation

/// Strict, local JSON parsing. Numbers remain source lexemes, objects retain
/// member order (including repeated keys), and imported text is never executed.
struct JSONRenderService {
    static let maximumUTF8Bytes = 2_000_000
    static let maximumSourceCharacters = 200_000
    static let maximumSourceLines = 20_000
    static let maximumDepth = 64
    static let maximumNodes = 12_000

    /// Paste detection uses the same grammar as the reader without generating
    /// source highlighting or converting numbers to Foundation numeric types.
    /// Scalars require an explicit JSON choice so ordinary prose stays text.
    static func isValidContainer(_ text: String) -> Bool {
        guard text.utf8.count <= maximumUTF8Bytes else { return false }
        let bytes = Array(text.utf8)
        let isWhitespace: (UInt8) -> Bool = { $0 == 32 || $0 == 9 || $0 == 10 || $0 == 13 }
        let content = bytes.dropFirst(bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0)
            .drop(while: isWhitespace)
        guard let first = content.first, first == 123 || first == 91,
              let last = content.last(where: { !isWhitespace($0) }),
              last == (first == 123 ? 125 : 93) else { return false }
        var parser = StrictJSONParser(text)
        do {
            _ = try parser.parse()
            return true
        } catch let problem as StrictJSONParser.Problem {
            // Keep large/deep containers in the JSON reader, which explains the
            // structure limit and preserves the readable source.
            return problem.code == "depthLimit" || problem.code == "nodeLimit"
        } catch { return false }
    }

    func render(fileURL: URL) throws -> YAMLDocument {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        // A bounded read also handles files that grow after the import.
        let bytes = try handle.read(upToCount: Self.maximumUTF8Bytes + 1) ?? Data()
        guard bytes.count <= Self.maximumUTF8Bytes else {
            return document(source: String(decoding: bytes.prefix(Self.maximumSourceCharacters), as: UTF8.self),
                            issue: issue("sizeLimit"), truncated: true)
        }
        guard let text = String(data: bytes, encoding: .utf8) else {
            return document(source: String(decoding: bytes, as: UTF8.self), issue: issue("encoding"))
        }
        return render(text: text)
    }

    func render(text: String) -> YAMLDocument {
        guard text.utf8.count <= Self.maximumUTF8Bytes else {
            return document(source: String(text.prefix(Self.maximumSourceCharacters)),
                            issue: issue("sizeLimit"), truncated: true)
        }
        var parser = StrictJSONParser(text)
        do {
            let rows = try parser.parse()
            let sheet = YAMLSheet(index: 0, startLine: 1, endLine: parser.line, rows: rows, issue: nil)
            return document(source: text, sheets: [sheet])
        } catch let problem as StrictJSONParser.Problem {
            let message = problem.code == "syntax" ? JSONStrings.syntaxMessage(problem.reason) : ""
            return document(source: text, issue: YAMLIssue(code: problem.code, message: message,
                                                          line: problem.line, column: problem.column))
        } catch {
            return document(source: text, issue: issue("runtime"))
        }
    }

    private func issue(_ code: String) -> YAMLIssue {
        YAMLIssue(code: code, message: "", line: 1, column: 1)
    }

    private func document(source: String, sheets: [YAMLSheet] = [], issue: YAMLIssue? = nil,
                          truncated: Bool = false) -> YAMLDocument {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let excerpt = String(normalized.prefix(Self.maximumSourceCharacters))
        let pieces = excerpt.components(separatedBy: "\n")
        let lines = pieces.prefix(Self.maximumSourceLines).enumerated().map { index, text in
            YAMLSourceLine(number: index + 1, tokens: JSONSourceHighlight.tokens(text), format: .json)
        }
        return YAMLDocument(source: source, sheets: sheets, issue: issue, lines: lines,
                            isSourceTruncated: truncated || excerpt.count < normalized.count
                            || pieces.count > Self.maximumSourceLines)
    }
}

private struct StrictJSONParser {
    struct Problem: Error {
        let code: String
        let reason: String
        let line: Int
        let column: Int
    }

    private let bytes: [UInt8]
    private var offset = 0
    private(set) var line = 1
    private var column = 1
    private var afterCarriageReturn = false
    private var rows: [YAMLRow] = []
    private var pathBytes = 0

    init(_ text: String) { bytes = Array(text.utf8) }
    private var current: UInt8? { offset < bytes.count ? bytes[offset] : nil }

    mutating func parse() throws -> [YAMLRow] {
        // RFC 8259 permits parsers to ignore an initial UTF-8 BOM.
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { offset = 3 }
        whitespace()
        try value(label: "$", path: "$", depth: 0, parents: [])
        whitespace()
        guard current == nil else { throw problem("trailingContent") }
        return rows
    }

    private mutating func value(label: String, path: String, depth: Int, parents: [String]) throws {
        guard depth <= JSONRenderService.maximumDepth else { throw problem(code: "depthLimit") }
        pathBytes += path.utf8.count
        // Bound repeated field-path storage as well as the tree itself.
        guard rows.count < JSONRenderService.maximumNodes, pathBytes <= 4_000_000 else {
            throw problem(code: "nodeLimit")
        }
        guard let byte = current else { throw problem("expectedValue") }
        let start = offset, startLine = line, startColumn = column, index = rows.count
        let id = "json-0-\(index)"
        let kind: YAMLRow.Kind
        switch byte {
        case 123: kind = .object
        case 91: kind = .array
        case 34: kind = .string
        case 45, 48...57: kind = .number
        case 116, 102: kind = .boolean
        case 110: kind = .null
        default: throw problem("expectedValue")
        }
        // Reserve the parent before parsing children so display order is stable.
        rows.append(YAMLRow(id: id, label: label, path: path, depth: depth, parents: parents,
                            kind: kind, value: "", line: startLine, column: startColumn,
                            count: 0, anchor: "", tag: "", sourceRange: nil))
        let text: String
        let count: Int
        switch kind {
        case .object:
            count = try object(path: path, depth: depth, parents: parents + [id]); text = ""
        case .array:
            count = try array(path: path, depth: depth, parents: parents + [id]); text = ""
        case .string: text = try string(); count = 0
        case .number: text = try number(); count = 0
        case .boolean: text = try literal(byte == 116 ? "true" : "false"); count = 0
        case .null: text = try literal("null"); count = 0
        case .alias: throw problem("expectedValue")
        }
        rows[index] = YAMLRow(id: id, label: label, path: path, depth: depth, parents: parents,
                              kind: kind, value: text, line: startLine, column: startColumn,
                              count: count, anchor: "", tag: "",
                              sourceRange: StructuredSourceRange(start: start, end: offset))
    }

    private mutating func object(path: String, depth: Int, parents: [String]) throws -> Int {
        advance(); whitespace()
        if current == 125 { advance(); return 0 }
        var count = 0
        while true {
            guard current == 34 else { throw problem("expectedKey") }
            let key = try string()
            whitespace()
            guard current == 58 else { throw problem("expectedColon") }
            advance(); whitespace()
            let childPath = try fieldPath(key, parent: path)
            try value(label: key, path: childPath, depth: depth + 1, parents: parents)
            count += 1
            whitespace()
            if current == 125 { advance(); return count }
            guard current == 44 else { throw problem("expectedObjectEnd") }
            advance(); whitespace()
        }
    }

    private mutating func array(path: String, depth: Int, parents: [String]) throws -> Int {
        advance(); whitespace()
        if current == 93 { advance(); return 0 }
        var count = 0
        while true {
            try value(label: "[\(count)]", path: "\(path)[\(count)]", depth: depth + 1, parents: parents)
            count += 1
            whitespace()
            if current == 93 { advance(); return count }
            guard current == 44 else { throw problem("expectedArrayEnd") }
            advance(); whitespace()
        }
    }

    private mutating func string() throws -> String {
        advance() // opening quote
        var output: [UInt8] = []
        while let byte = current {
            if byte == 34 { advance(); return String(decoding: output, as: UTF8.self) }
            guard byte >= 0x20 else { throw problem("controlCharacter") }
            if byte != 92 { output.append(byte); advance(); continue }
            advance()
            guard let escaped = current else { throw problem("unterminatedString") }
            let escapeLine = line, escapeColumn = column
            advance()
            switch escaped {
            case 34, 92, 47: output.append(escaped)
            case 98: output.append(8)
            case 102: output.append(12)
            case 110: output.append(10)
            case 114: output.append(13)
            case 116: output.append(9)
            case 117:
                let first = try hexQuad()
                let scalar: UInt32
                if (0xD800...0xDBFF).contains(first) {
                    guard current == 92 else { throw problem("invalidUnicode") }
                    advance()
                    guard current == 117 else { throw problem("invalidUnicode") }
                    advance()
                    let second = try hexQuad()
                    guard (0xDC00...0xDFFF).contains(second) else { throw problem("invalidUnicode") }
                    scalar = 0x10000 + ((first - 0xD800) << 10) + second - 0xDC00
                } else {
                    guard !(0xDC00...0xDFFF).contains(first) else { throw problem("invalidUnicode") }
                    scalar = first
                }
                guard let unicode = UnicodeScalar(scalar) else { throw problem("invalidUnicode") }
                output.append(contentsOf: String(unicode).utf8)
            default: throw Problem(code: "syntax", reason: "invalidEscape", line: escapeLine, column: escapeColumn)
            }
        }
        throw problem("unterminatedString")
    }

    private mutating func hexQuad() throws -> UInt32 {
        var number: UInt32 = 0
        for _ in 0..<4 {
            guard let byte = current else { throw problem("invalidUnicode") }
            let digit: UInt32
            switch byte {
            case 48...57: digit = UInt32(byte - 48)
            case 65...70: digit = UInt32(byte - 55)
            case 97...102: digit = UInt32(byte - 87)
            default: throw problem("invalidUnicode")
            }
            number = number * 16 + digit
            advance()
        }
        return number
    }

    private mutating func number() throws -> String {
        let start = offset
        if current == 45 { advance() }
        guard let first = current else { throw problem("invalidNumber") }
        if first == 48 {
            advance()
            if let byte = current, (48...57).contains(byte) { throw problem("invalidNumber") }
        } else if (49...57).contains(first) {
            digits()
        } else { throw problem("invalidNumber") }
        if current == 46 {
            advance()
            guard let byte = current, (48...57).contains(byte) else { throw problem("invalidNumber") }
            digits()
        }
        if current == 101 || current == 69 {
            advance()
            if current == 43 || current == 45 { advance() }
            guard let byte = current, (48...57).contains(byte) else { throw problem("invalidNumber") }
            digits()
        }
        return String(decoding: bytes[start..<offset], as: UTF8.self)
    }

    private mutating func digits() {
        while let byte = current, (48...57).contains(byte) { advance() }
    }

    private mutating func literal(_ expected: String) throws -> String {
        for byte in expected.utf8 {
            guard current == byte else { throw problem("expectedValue") }
            advance()
        }
        return expected
    }

    private func fieldPath(_ key: String, parent: String) throws -> String {
        // Escape ambiguous keys as JSON strings. Simple names keep a readable dot path.
        let identifier = !key.isEmpty && key.utf8.enumerated().allSatisfy { index, byte in
            (65...90).contains(byte) || (97...122).contains(byte) || byte == 95 || byte == 36
                || (index > 0 && (48...57).contains(byte))
        }
        let suffix: String
        if identifier { suffix = "." + key }
        else {
            let encoded = try JSONEncoder().encode(key)
            suffix = "[" + String(decoding: encoded, as: UTF8.self) + "]"
        }
        guard parent.utf8.count + suffix.utf8.count <= 32_768 else { throw problem(code: "nodeLimit") }
        return parent + suffix
    }

    private mutating func whitespace() {
        while let byte = current, byte == 32 || byte == 9 || byte == 10 || byte == 13 { advance() }
    }

    private mutating func advance() {
        guard let byte = current else { return }
        offset += 1
        if byte == 13 { line += 1; column = 1 }
        else if byte == 10 { if !afterCarriageReturn { line += 1 }; column = 1 }
        else if byte & 0xC0 != 0x80 { column += 1 }
        afterCarriageReturn = byte == 13
    }

    private func problem(_ reason: String = "", code: String = "syntax") -> Problem {
        Problem(code: code, reason: reason, line: line, column: column)
    }
}

/// Native token coloring for the bounded source excerpt, including invalid JSON.
/// It never attempts to repair or evaluate the imported source.
private enum JSONSourceHighlight {
    private static func startsToken(_ byte: UInt8) -> Bool {
        byte == 34 || byte == 45 || (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
    }

    static func tokens(_ text: String) -> [YAMLSourceToken] {
        let bytes = Array(text.utf8)
        var offset = 0
        var result: [YAMLSourceToken] = []
        while offset < bytes.count {
            let start = offset
            let style: String
            switch bytes[offset] {
            case 34:
                offset += 1
                while offset < bytes.count {
                    let byte = bytes[offset]; offset += 1
                    if byte == 92 { offset = min(offset + 1, bytes.count) }
                    else if byte == 34 { break }
                }
                var next = offset
                while next < bytes.count && (bytes[next] == 32 || bytes[next] == 9) { next += 1 }
                style = next < bytes.count && bytes[next] == 58 ? "attr" : "string"
            case 45, 48...57:
                offset += 1
                while offset < bytes.count && (bytes[offset] == 43 || bytes[offset] == 45 || bytes[offset] == 46
                    || bytes[offset] == 69 || bytes[offset] == 101 || (48...57).contains(bytes[offset])) { offset += 1 }
                style = "number"
            case 65...90, 97...122:
                offset += 1
                while offset < bytes.count && (97...122).contains(bytes[offset]) { offset += 1 }
                let word = String(decoding: bytes[start..<offset], as: UTF8.self)
                style = ["true", "false", "null"].contains(word) ? "literal" : ""
            default:
                offset += 1
                // Consume punctuation/whitespace together. Token boundaries are
                // ASCII, so a Unicode scalar is never split between tokens.
                while offset < bytes.count && !startsToken(bytes[offset]) { offset += 1 }
                style = ""
            }
            let fragment = String(decoding: bytes[start..<offset], as: UTF8.self)
            result.append(YAMLSourceToken(text: fragment, style: style))
        }
        return result
    }
}
