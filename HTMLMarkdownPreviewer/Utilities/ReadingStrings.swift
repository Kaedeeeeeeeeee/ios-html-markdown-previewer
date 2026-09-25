import Foundation

enum ReadingStrings {
    private static func text(_ key: String, _ fallback: String) -> String {
        NSLocalizedString(key, tableName: "Reading", bundle: .main, value: fallback, comment: "")
    }

    static let tools = text("reading.tools", "Reading Tools")
    static let find = text("reading.find", "Find in Document")
    static let contents = text("reading.contents", "Table of Contents")
    static let beginning = text("reading.beginning", "Back to Beginning")
    static let searchPlaceholder = text("reading.searchPlaceholder", "Find text")
    static let noMatches = text("reading.noMatches", "No matches")
    static let previous = text("reading.previous", "Previous Match")
    static let next = text("reading.next", "Next Match")
    static let closeSearch = text("reading.closeSearch", "Close Search")
    static let noHeadings = text("reading.noHeadings", "No Headings")
    static let noHeadingsDescription = text("reading.noHeadingsDescription", "Headings in this document will appear here.")

    static func matchCount(current: Int, total: Int) -> String {
        String(format: text("reading.matchCount", "%ld of %ld"), current, total)
    }
}
