import Foundation
import JavaScriptCore

/// The app's own bundled code is evaluated once per context. Imported YAML is
/// passed as a function argument, never interpolated into executable code. Run
/// this service off the main actor; no WebView, network, or clipboard is used.
struct YAMLRenderService {
    static let maximumUTF8Bytes = 2_000_000
    static let maximumSourceLines = 20_000
    static let maximumSourceCharacters = 200_000

    private static let runtime: String? = {
        guard let url = Bundle.main.url(forResource: "yaml-runtime.min", withExtension: "js", subdirectory: "YAML") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    func render(fileURL: URL) throws -> YAMLDocument {
        // Bound file reads too: even a very large received file keeps a useful
        // source excerpt while the unchanged original remains shareable.
        let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        if size > Self.maximumUTF8Bytes {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            let bytes = try handle.read(upToCount: Self.maximumSourceCharacters) ?? Data()
            let source: String
            if bytes.starts(with: [0xFF, 0xFE]) {
                source = String(data: bytes.dropFirst(2), encoding: .utf16LittleEndian) ?? ""
            } else if bytes.starts(with: [0xFE, 0xFF]) {
                source = String(data: bytes.dropFirst(2), encoding: .utf16BigEndian) ?? ""
            } else {
                source = String(decoding: bytes, as: UTF8.self)
            }
            return fallback(source, code: "sizeLimit", truncated: true)
        }
        return render(text: try TextFileReader().readText(from: fileURL))
    }

    func render(text: String) -> YAMLDocument {
        guard text.utf8.count <= Self.maximumUTF8Bytes else {
            return fallback(String(text.prefix(Self.maximumSourceCharacters)), code: "sizeLimit", truncated: true)
        }
        guard let runtime = Self.runtime, let context = JSContext() else { return fallback(text, code: "runtime") }
        context.evaluateScript(runtime)
        guard context.exception == nil,
              let parser = context.objectForKeyedSubscript("YAMLRuntime")?.forProperty("parse"),
              let json = parser.call(withArguments: [text])?.toString(), context.exception == nil,
              let data = json.data(using: .utf8), let result = try? JSONDecoder().decode(ParseResult.self, from: data) else {
            return fallback(text, code: "runtime")
        }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let excerpt = String(normalized.prefix(Self.maximumSourceCharacters))
        let tokens = result.highlighted.flatMap { YAMLHighlightTokens.tokens(html: $0, expectedText: normalized) }
            ?? [YAMLSourceToken(text: excerpt, style: "")]
        let lines = sourceLines(tokens)
        return YAMLDocument(source: text, sheets: result.documents, issue: result.issue,
                            lines: lines, isSourceTruncated: excerpt.count < normalized.count
                            || normalized.reduce(1, { $1 == "\n" ? $0 + 1 : $0 }) > Self.maximumSourceLines)
    }

    private func fallback(_ text: String, code: String, truncated: Bool = false) -> YAMLDocument {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return YAMLDocument(source: text, sheets: [],
                            issue: YAMLIssue(code: code, message: "", line: 1, column: 1),
                            lines: sourceLines([YAMLSourceToken(text: String(normalized.prefix(Self.maximumSourceCharacters)), style: "")]),
                            isSourceTruncated: truncated)
    }

    private func sourceLines(_ tokens: [YAMLSourceToken]) -> [YAMLSourceLine] {
        var lines = [YAMLSourceLine(number: 1, tokens: [])]
        for token in tokens {
            let parts = token.text.components(separatedBy: "\n")
            for (index, part) in parts.enumerated() {
                if index > 0 {
                    guard lines.count < Self.maximumSourceLines else { return lines }
                    lines.append(YAMLSourceLine(number: lines.count + 1, tokens: []))
                }
                if !part.isEmpty { lines[lines.count - 1].tokens.append(YAMLSourceToken(text: part, style: token.style)) }
            }
        }
        return lines
    }

    private struct ParseResult: Decodable {
        let documents: [YAMLSheet]
        let issue: YAMLIssue?
        let highlighted: String?
    }
}

/// highlight.js returns escaped text and span elements. Decode only that markup
/// into native text tokens; no imported text is interpreted as HTML by UIKit.
private final class YAMLHighlightTokens: NSObject, XMLParserDelegate {
    private var styles: [String] = []
    private var result: [YAMLSourceToken] = []

    static func tokens(html: String, expectedText: String) -> [YAMLSourceToken]? {
        let delegate = YAMLHighlightTokens()
        let parser = XMLParser(data: Data(("<root>" + html + "</root>").utf8))
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), delegate.result.map(\.text).joined() == expectedText else { return nil }
        return delegate.result
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        styles.append(attributeDict["class"] ?? styles.last ?? "")
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        _ = styles.popLast()
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        result.append(YAMLSourceToken(text: string, style: styles.last ?? ""))
    }
}
