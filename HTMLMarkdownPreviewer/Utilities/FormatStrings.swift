import Foundation

/// Text for the Mermaid, CSV, and SVG readers.
enum FormatStrings {
    private static func text(_ key: String, _ fallback: String) -> String {
        NSLocalizedString(key, tableName: "Formats", bundle: .main, value: fallback, comment: "")
    }

    static var mermaidEmpty: String { text("mermaid.empty", "This Mermaid file is empty.") }
    static var csvEmpty: String { text("csv.empty", "This table file is empty.") }
    static var svgUnavailable: String {
        text("svg.unavailable", "This SVG image could not be displayed. Choose Raw Text to read its source.")
    }

    static func csvSummary(rows: Int, columns: Int) -> String {
        String.localizedStringWithFormat(text("csv.summary", "%1$ld rows · %2$ld columns"), rows, columns)
    }

    static func csvTruncated(shown: Int, total: Int) -> String {
        String.localizedStringWithFormat(
            text("csv.truncated", "Showing the first %1$ld of %2$ld rows. Choose Raw Text to read every row."),
            shown, total
        )
    }
}
