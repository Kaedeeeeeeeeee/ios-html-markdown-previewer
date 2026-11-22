import Foundation

/// Reads comma-, semicolon-, tab-, or pipe-separated text as a table in the
/// Markdown reader. Cells stay plain text: nothing in a cell is interpreted as
/// Markdown or HTML.
struct CSVRenderService {
    /// The native table lays out every cell at once, so very long files show
    /// their first rows and point to the raw text for the rest.
    static let maximumDisplayedRows = 500

    func render(fileURL: URL) throws -> MarkdownDocument {
        let text = try TextFileReader().readText(from: fileURL)
        let isTabSeparated = fileURL.pathExtension.lowercased() == "tsv"
        return render(text: text, delimiter: isTabSeparated ? "\t" : nil)
    }

    func render(text: String, delimiter: Character? = nil) -> MarkdownDocument {
        let delimiter = delimiter ?? Self.detectDelimiter(in: text)
        let records = Self.parse(text, delimiter: delimiter)
        guard let header = records.first else {
            return MarkdownDocument(blocks: [.paragraph(AttributedString(FormatStrings.csvEmpty))])
        }

        let rows = Array(records.dropFirst())
        let columnCount = max(header.count, rows.map(\.count).max() ?? 0)
        let shownRows = Array(rows.prefix(Self.maximumDisplayedRows))
        let alignments = (0..<columnCount).map { column in
            Self.isNumericColumn(column, in: shownRows) ? MarkdownTable.ColumnAlignment.trailing : .leading
        }
        let table = MarkdownTable(
            columnAlignments: alignments,
            header: header.map { AttributedString($0) },
            rows: shownRows.map { $0.map { AttributedString($0) } }
        )

        var blocks: [MarkdownBlock] = [
            .paragraph(AttributedString(FormatStrings.csvSummary(rows: rows.count, columns: columnCount))),
            .table(table)
        ]
        if rows.count > shownRows.count {
            blocks.append(.paragraph(AttributedString(
                FormatStrings.csvTruncated(shown: shownRows.count, total: rows.count)
            )))
        }
        return MarkdownDocument(blocks: blocks)
    }

    /// Picks the candidate that splits the first few records most consistently.
    /// Delimiters inside quoted fields are ignored.
    static func detectDelimiter(in text: String) -> Character {
        let candidates: [Character] = [",", "\t", ";", "|"]
        let sample = String(text.prefix(16_384))
        var best: (delimiter: Character, score: Int) = (",", 0)
        for candidate in candidates {
            let records = parse(sample, delimiter: candidate, limit: 10)
            guard let first = records.first, first.count > 1 else { continue }
            let consistent = records.filter { $0.count == first.count }.count
            let score = consistent * first.count
            if score > best.score { best = (candidate, score) }
        }
        return best.delimiter
    }

    /// RFC 4180 parsing, also accepting bare LF/CR line endings and a leading
    /// byte-order mark. Empty lines between records are skipped.
    static func parse(_ text: String, delimiter: Character, limit: Int? = nil) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var fieldStarted = false
        var iterator = (text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text).makeIterator()
        var pending: Character?

        func endRecord() {
            record.append(field)
            if !(record.count == 1 && record[0].isEmpty && !fieldStarted) {
                records.append(record)
            }
            record = []
            field = ""
            fieldStarted = false
        }

        while let character = pending ?? iterator.next() {
            pending = nil
            if let limit, records.count >= limit { break }

            if inQuotes {
                if character == "\"" {
                    let next = iterator.next()
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        inQuotes = false
                        pending = next
                    }
                } else {
                    field.append(character)
                }
                continue
            }

            switch character {
            case "\"" where field.isEmpty:
                inQuotes = true
                fieldStarted = true
            case delimiter:
                record.append(field)
                field = ""
                fieldStarted = true
            // Swift treats "\r\n" as one Character.
            case "\n", "\r", "\r\n":
                endRecord()
            default:
                field.append(character)
                fieldStarted = true
            }
        }

        if !field.isEmpty || !record.isEmpty || fieldStarted {
            endRecord()
        }
        if let limit { return Array(records.prefix(limit)) }
        return records
    }

    private static func isNumericColumn(_ column: Int, in rows: [[String]]) -> Bool {
        var sawNumber = false
        for row in rows where column < row.count {
            let value = row[column].trimmingCharacters(in: .whitespaces)
            if value.isEmpty { continue }
            guard isNumber(value) else { return false }
            sawNumber = true
        }
        return sawNumber
    }

    private static func isNumber(_ value: String) -> Bool {
        value.range(
            of: #"^[-+]?[$€£¥]?(?:\d{1,3}(?:,\d{3})+|\d+)?(?:\.\d+)?%?$"#,
            options: .regularExpression
        ) != nil && value.contains(where: \.isNumber)
    }
}
