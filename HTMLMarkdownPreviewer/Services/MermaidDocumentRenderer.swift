import Foundation

/// A standalone `.mmd` / `.mermaid` file is read as one Mermaid block, so it
/// uses the same offline, strict-security renderer as diagrams in Markdown.
struct MermaidDocumentRenderer {
    func render(fileURL: URL) throws -> MarkdownDocument {
        render(source: try TextFileReader().readText(from: fileURL))
    }

    func render(source: String) -> MarkdownDocument {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return MarkdownDocument(blocks: [.paragraph(AttributedString(FormatStrings.mermaidEmpty))])
        }
        return MarkdownDocument(blocks: [.codeBlock(language: "mermaid", code: Self.unwrappingFence(trimmed))])
    }

    /// Agents sometimes save a diagram with its Markdown fence still around it.
    static func unwrappingFence(_ source: String) -> String {
        let lines = source.components(separatedBy: .newlines)
        guard lines.count >= 2,
              let first = lines.first?.trimmingCharacters(in: .whitespaces),
              first.hasPrefix("```") || first.hasPrefix("~~~"),
              ["", "mermaid"].contains(first.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased()),
              let last = lines.last?.trimmingCharacters(in: .whitespaces),
              last == String(first.prefix(3)) else {
            return source
        }
        return lines.dropFirst().dropLast().joined(separator: "\n")
    }
}
