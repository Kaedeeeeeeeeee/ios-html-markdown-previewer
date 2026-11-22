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

    static var mermaidSampleTitle: String { text("sample.mermaid.title", "Agent workflow") }
    static var mermaidSampleSubtitle: String { text("sample.mermaid.subtitle", "Mermaid · A diagram file drawn offline") }
    static var csvSampleTitle: String { text("sample.csv.title", "Benchmark results") }
    static var csvSampleSubtitle: String { text("sample.csv.subtitle", "CSV · A readable table with aligned numbers") }
    static var svgSampleTitle: String { text("sample.svg.title", "Weekly chart") }
    static var svgSampleSubtitle: String { text("sample.svg.subtitle", "SVG · A vector image, shown safely") }

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
