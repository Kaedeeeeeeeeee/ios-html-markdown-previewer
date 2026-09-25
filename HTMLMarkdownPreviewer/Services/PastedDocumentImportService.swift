import Foundation

enum PastedDocumentFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown
    case html

    var id: String { rawValue }
    var displayName: String { self == .html ? "HTML" : "Markdown" }
    var fileExtension: String { self == .html ? "html" : "md" }
}

enum PastedDocumentError: Error, Equatable, LocalizedError {
    case emptyContent
    case webAddressOnly
    case contentTooLarge

    var errorDescription: String? {
        switch self {
        case .emptyContent: PasteStrings.emptyContent
        case .webAddressOnly: PasteStrings.webAddressOnly
        case .contentTooLarge: PasteStrings.contentTooLarge
        }
    }
}

struct PreparedPastedDocument: Equatable, Sendable {
    let content: String
    let filename: String
    let format: PastedDocumentFormat
}

/// Accepts text supplied by an explicit user action. This service never reads the pasteboard.
final class PastedDocumentImportService {
    static let maximumUTF8Bytes = 2_000_000

    private let importService: DocumentImportService
    private let temporaryRootURL: URL
    private let fileManager: FileManager

    init(
        store: DocumentLibraryStore,
        temporaryRootURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.importService = DocumentImportService(store: store, fileManager: fileManager)
        self.temporaryRootURL = temporaryRootURL ?? fileManager.temporaryDirectory
            .appendingPathComponent("PastedDocuments", isDirectory: true)
        self.fileManager = fileManager
    }

    func importDocument(text: String, name: String, format: PastedDocumentFormat) throws -> PreviewDocument {
        let prepared = try Self.prepare(text: text, name: name, format: format)
        let directory = temporaryRootURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent(prepared.filename)
        try prepared.content.write(to: fileURL, atomically: true, encoding: .utf8)
        return try importService.importDocument(from: fileURL, source: .pastedText)
    }

    static func prepare(text: String, name: String, format: PastedDocumentFormat) throws -> PreparedPastedDocument {
        guard text.utf8.count <= maximumUTF8Bytes else {
            throw PastedDocumentError.contentTooLarge
        }

        let normalized = normalizedLineEndings(text)
        var content = normalized
        if let fence = outerFence(in: normalized),
           fence.format == format || (fence.format == nil && format == .html && looksLikeHTML(fence.content)) {
            content = fence.content
        }

        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { throw PastedDocumentError.emptyContent }
        guard !isOnlyWebAddress(trimmedContent) else { throw PastedDocumentError.webAddressOnly }

        return PreparedPastedDocument(
            content: content,
            filename: safeName(name) + "." + format.fileExtension,
            format: format
        )
    }

    static func suggestedFormat(for text: String) -> PastedDocumentFormat {
        // Avoid parsing an oversized clipboard payload merely to update the format picker.
        guard text.utf8.count <= maximumUTF8Bytes else { return .markdown }
        let normalized = normalizedLineEndings(text)
        if let fence = outerFence(in: normalized) {
            if let format = fence.format { return format }
            return looksLikeHTML(fence.content) ? .html : .markdown
        }
        return looksLikeHTML(normalized) ? .html : .markdown
    }

    private static func normalizedLineEndings(_ text: String) -> String {
        let text = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        return text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func looksLikeHTML(_ text: String) -> Bool {
        let prefix = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4096))
        return prefix.range(
            of: #"(?is)^(?:<!--.*?-->\s*)*(?:<!doctype\s+html\b|<(?:html|head|body|title|meta|link|style|script|div|section|article|main|header|footer|nav|aside|h[1-6]|p|span|a|img|svg|table|ul|ol|form|button|input|details)(?:\s|/?>))"#,
            options: .regularExpression
        ) != nil
    }

    private static func isOnlyWebAddress(_ text: String) -> Bool {
        text.range(
            of: #"(?i)^(?:[a-z][a-z0-9+.-]*://|mailto:|www\.)\S+$"#,
            options: .regularExpression
        ) != nil
    }

    private static func outerFence(in text: String) -> (content: String, format: PastedDocumentFormat?)? {
        let lines = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
        guard lines.count >= 2, let first = lines.first, let marker = first.first,
              marker == "`" || marker == "~" else { return nil }
        let markerCount = first.prefix(while: { $0 == marker }).count
        guard markerCount >= 3 else { return nil }

        let language = first.dropFirst(markerCount).trimmingCharacters(in: .whitespaces).lowercased()
        let format: PastedDocumentFormat?
        switch language {
        case "html", "htm", "xhtml": format = .html
        case "markdown", "md": format = .markdown
        case "": format = nil
        default: return nil
        }

        func isClosingFence(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.count >= markerCount && trimmed.allSatisfy { $0 == marker }
        }

        guard let last = lines.last, isClosingFence(last) else { return nil }
        let innerLines = lines.dropFirst().dropLast()
        // Multiple separate code blocks must remain separate Markdown blocks.
        guard !innerLines.contains(where: isClosingFence) else { return nil }
        return (innerLines.joined(separator: "\n"), format)
    }

    private static func safeName(_ name: String) -> String {
        var sanitized = String(name.map { character -> Character in
            let isControl = character.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
            return isControl || "/\\:".contains(character) ? "-" : character
        }).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        let knownExtensions = ["html", "htm", "xhtml", "md", "markdown"]
        if knownExtensions.contains((sanitized as NSString).pathExtension.lowercased()) {
            sanitized = (sanitized as NSString).deletingPathExtension
        }

        // Keep Unicode names while reserving room under the filesystem's filename byte limit.
        var result = ""
        for character in sanitized {
            guard result.utf8.count + String(character).utf8.count <= 160 else { break }
            result.append(character)
        }
        return result.isEmpty ? PasteStrings.defaultDocumentName : result
    }
}
