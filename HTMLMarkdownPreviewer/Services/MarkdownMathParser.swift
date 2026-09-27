import Foundation
import Markdown

/// Protects LaTeX before CommonMark interprets its backslashes, underscores or pipes.
///
/// Supported delimiters: inline `$...$` and `\(...\)` (one line), and display
/// `$$...$$` / `\[...\]` (including multiple lines). The render service also
/// handles fenced `math` blocks. Single-dollar delimiters require a non-space
/// interior, and a closer cannot be followed by a digit; ordinary prices such
/// as `$5 and $10` therefore remain literal while `$2 + 2$` is valid math.
///
/// CommonMark's own source ranges protect code, HTML and link destinations.
/// Tokens are local to one render and use a prefix absent from the source, so
/// neither concurrent renders nor document text can inject a formula entry.
struct MarkdownMathParser {
    struct Entry {
        let source: String
        let display: Bool
        let isMath: Bool
    }

    let markdown: String
    private let prefix: String
    private let entries: [String: Entry]

    init(_ source: String) {
        let bytes = Array(source.utf8)
        let original = Document(parsing: source)
        let protected = Self.protectedBytes(in: original, source: source, bytes: bytes)
        var prefix = "MDMATH" + UUID().uuidString.replacingOccurrences(of: "-", with: "") + "X"
        while source.contains(prefix) { prefix += "X" }
        self.prefix = prefix

        var entries: [String: Entry] = [:]
        var output = ""
        var cursor = 0
        var unchangedStart = 0
        var failedSearches: [[UInt8]: Int] = [:]

        func token(for entry: Entry) -> String {
            let key = prefix + String(entries.count) + "END"
            entries[key] = entry
            return key
        }

        while cursor < bytes.count {
            if Self.matches([92, 41], at: cursor, in: bytes) || Self.matches([92, 93], at: cursor, in: bytes),
               !protected.startAndEnd[cursor], !Self.isEscaped(cursor, in: bytes) {
                output += String(decoding: bytes[unchangedStart..<cursor], as: UTF8.self)
                output += token(for: Entry(
                    source: String(decoding: bytes[cursor..<(cursor + 2)], as: UTF8.self), display: false, isMath: false
                ))
                cursor += 2
                unchangedStart = cursor
                continue
            }
            guard !protected.startAndEnd[cursor], let delimiter = Self.delimiter(at: cursor, in: bytes),
                  !Self.isEscaped(cursor, in: bytes) else {
                cursor += 1
                continue
            }
            let bodyStart = cursor + delimiter.open.count
            if delimiter.open == [36],
               (bodyStart >= bytes.count || Self.isWhitespace(bytes[bodyStart])) {
                cursor += 1
                continue
            }

            var end = bodyStart
            var closing: Int?
            // Repeated unclosed openers should not rescan the same long line
            // or document quadratically.
            let alreadyFailed = bodyStart < (failedSearches[delimiter.open] ?? 0)
            while !alreadyFailed && end < bytes.count {
                if protected.hardBoundary[end] || (!delimiter.display && (bytes[end] == 10 || bytes[end] == 13)) { break }
                if !protected.startAndEnd[end], Self.matches(delimiter.close, at: end, in: bytes), !Self.isEscaped(end, in: bytes) {
                    if delimiter.open != [36] || (
                        end > bodyStart && !Self.isWhitespace(bytes[end - 1]) &&
                        (end + 1 == bytes.count || !Self.isDigit(bytes[end + 1])) &&
                        (end + 1 == bytes.count || bytes[end + 1] != 36)
                    ) {
                        closing = end
                        break
                    }
                    // Do not scan repeatedly across an invalid closer. It may
                    // instead be the opener of the next valid expression.
                    if delimiter.open == [36] { break }
                }
                end += 1
            }
            if closing == nil && !alreadyFailed { failedSearches[delimiter.open] = end }

            if let closing {
                let raw = String(decoding: bytes[bodyStart..<closing], as: UTF8.self)
                let body = delimiter.display
                    ? Self.removingContainerPrefixes(from: raw, opener: cursor, bytes: bytes)
                    : raw
                if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    output += String(decoding: bytes[unchangedStart..<cursor], as: UTF8.self)
                    output += token(for: Entry(source: body, display: delimiter.display, isMath: true))
                    cursor = closing + delimiter.close.count
                    unchangedStart = cursor
                    continue
                }
            }

            // A failed display opener must not be retried as the second `$` of
            // `$$`. Backslash delimiters also survive CommonMark's escaping.
            if delimiter.open.first == 92 {
                output += String(decoding: bytes[unchangedStart..<cursor], as: UTF8.self)
                output += token(for: Entry(
                    source: String(decoding: delimiter.open, as: UTF8.self), display: false, isMath: false
                ))
                cursor += delimiter.open.count
                unchangedStart = cursor
            } else {
                cursor += delimiter.open.count
            }
        }
        output += String(decoding: bytes[unchangedStart..<bytes.count], as: UTF8.self)
        markdown = output
        self.entries = entries
    }

    func attributedText(_ text: String) -> AttributedString {
        var result = AttributedString()
        var position = text.startIndex
        while position < text.endIndex,
              let start = text.range(of: prefix, range: position..<text.endIndex),
              let end = text.range(of: "END", range: start.upperBound..<text.endIndex) {
            result.append(AttributedString(String(text[position..<start.lowerBound])))
            let token = String(text[start.lowerBound..<end.upperBound])
            if let entry = entries[token] {
                var value = AttributedString(entry.source)
                if entry.isMath {
                    value.markdownMath = entry.source
                    value[MarkdownMathOccurrenceAttribute.self] = Int(token.dropFirst(prefix.count).dropLast(3))
                    if entry.display { value[MarkdownDisplayMathAttribute.self] = true }
                }
                result.append(value)
            } else {
                result.append(AttributedString(token))
            }
            position = end.upperBound
        }
        result.append(AttributedString(String(text[position...])))
        return result
    }

    private struct Delimiter {
        let open: [UInt8]
        let close: [UInt8]
        let display: Bool
    }

    private static func delimiter(at position: Int, in bytes: [UInt8]) -> Delimiter? {
        if matches([36, 36], at: position, in: bytes) {
            return Delimiter(open: [36, 36], close: [36, 36], display: true)
        }
        if bytes[position] == 36 { return Delimiter(open: [36], close: [36], display: false) }
        if matches([92, 40], at: position, in: bytes) {
            return Delimiter(open: [92, 40], close: [92, 41], display: false)
        }
        if matches([92, 91], at: position, in: bytes) {
            return Delimiter(open: [92, 91], close: [92, 93], display: true)
        }
        return nil
    }

    private static func matches(_ pattern: [UInt8], at position: Int, in bytes: [UInt8]) -> Bool {
        position + pattern.count <= bytes.count && bytes[position..<(position + pattern.count)].elementsEqual(pattern)
    }

    private static func isEscaped(_ position: Int, in bytes: [UInt8]) -> Bool {
        var backslashes = 0
        var previous = position
        while previous > 0 && bytes[previous - 1] == 92 {
            backslashes += 1
            previous -= 1
        }
        return !backslashes.isMultiple(of: 2)
    }

    private static func isWhitespace(_ value: UInt8) -> Bool { value == 32 || value == 9 || value == 10 || value == 13 }
    private static func isDigit(_ value: UInt8) -> Bool { (48...57).contains(value) }

    private static func removingContainerPrefixes(from body: String, opener: Int, bytes: [UInt8]) -> String {
        let lineStart = bytes[..<opener].lastIndex(of: 10).map { $0 + 1 } ?? 0
        let prefix = Array(bytes[lineStart..<opener])
        // Only structural prefixes are removed, never preceding prose or LaTeX.
        guard !prefix.isEmpty,
              prefix.allSatisfy({ isWhitespace($0) || [62, 45, 43, 42, 46, 41].contains($0) || isDigit($0) }) else {
            return body
        }
        return body.components(separatedBy: "\n").enumerated().map { index, line in
            guard index > 0 else { return line }
            let lineBytes = Array(line.utf8)
            guard lineBytes.count >= prefix.count else { return line }
            let candidate = lineBytes.prefix(prefix.count)
            guard candidate.allSatisfy({ $0 == 32 || $0 == 9 || $0 == 62 }) else { return line }
            return String(decoding: lineBytes.dropFirst(prefix.count), as: UTF8.self)
        }.joined(separator: "\n")
    }

    private struct ProtectedRegions {
        let startAndEnd: [Bool]
        let hardBoundary: [Bool]
    }

    private static func protectedBytes(in document: Document, source: String, bytes: [UInt8]) -> ProtectedRegions {
        // Source omitted by CommonMark (notably multi-line reference
        // definitions) must never receive placeholders either.
        var result = Array(repeating: true, count: bytes.count)
        var hardBoundary = Array(repeating: false, count: bytes.count)
        var lineStarts = [0]
        for (index, byte) in bytes.enumerated() where byte == 10 { lineStarts.append(index + 1) }

        func offset(_ location: SourceLocation) -> Int? {
            guard location.line > 0, location.line <= lineStarts.count, location.column > 0 else { return nil }
            return min(bytes.count, lineStarts[location.line - 1] + location.column - 1)
        }

        func range(_ markup: Markup) -> Range<Int>? {
            guard let range = markup.range, let start = offset(range.lowerBound), let end = offset(range.upperBound),
                  start <= end else { return nil }
            return start..<end
        }

        func protect(_ range: Range<Int>) {
            for index in range { result[index] = true }
        }

        for block in document.children {
            if let range = range(block) {
                for index in range { result[index] = false }
            }
        }

        func visit(_ markup: Markup) {
            if markup is CodeBlock || markup is InlineCode || markup is HTMLBlock || markup is InlineHTML || markup is Markdown.Image {
                if let range = range(markup) {
                    protect(range)
                    if markup is CodeBlock || markup is HTMLBlock {
                        for index in range { hardBoundary[index] = true }
                    }
                }
                return
            }
            if let link = markup as? Link, let fullRange = range(link) {
                // Explicit labels can contain math; only the label's actual
                // children are eligible. Autolinks remain entirely literal.
                protect(fullRange)
                if fullRange.lowerBound < bytes.count, bytes[fullRange.lowerBound] == 91 {
                    for child in link.children {
                        if let childRange = range(child) {
                            for index in childRange where fullRange.contains(index) { result[index] = false }
                        }
                    }
                    for child in link.children { visit(child) }
                }
                return
            }
            for child in markup.children { visit(child) }
        }
        visit(document)

        // Bare URLs need protecting even when the parser leaves them as plain
        // text. Malformed reference-like definitions are left literal too.
        let patterns = [#"(?m)^[ \t]{0,3}\[[^\]\r\n]+\]:[^\r\n]*"#,
                        #"(?i)\b(?:[a-z][a-z0-9+.-]*://|mailto:)[^\s<>\[\]{}\"()]+"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                guard let stringRange = Range(match.range, in: source) else { continue }
                let lower = source.utf8.distance(from: source.utf8.startIndex, to: stringRange.lowerBound)
                let upper = source.utf8.distance(from: source.utf8.startIndex, to: stringRange.upperBound)
                protect(lower..<upper)
            }
        }
        return ProtectedRegions(startAndEnd: result, hardBoundary: hardBoundary)
    }
}

/// Internal marker consumed when splitting a paragraph into display blocks.
struct MarkdownDisplayMathAttribute: AttributedStringKey {
    typealias Value = Bool
    static let name = "com.kaede.markdown.display-math"
}

/// Keeps adjacent equal formulas as distinct attributed runs.
private struct MarkdownMathOccurrenceAttribute: AttributedStringKey {
    typealias Value = Int
    static let name = "com.kaede.markdown.math-occurrence"
}
