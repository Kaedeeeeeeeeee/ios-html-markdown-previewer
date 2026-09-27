import Foundation

enum PackageNavigationStrings {
    private static func text(_ key: String, _ fallback: String) -> String {
        NSLocalizedString(key, tableName: "PackageNavigation", bundle: .main, value: fallback, comment: "")
    }
    static let pages = text("pages", "Package Pages")
    static let search = text("search", "Find a page")
    static let back = text("back", "Previous Page")
    static let entry = text("entry", "Entry")
    static let current = text("current", "Current")
    static let noResults = text("noResults", "No Matching Pages")
    static let noResultsDetail = text("noResultsDetail", "Try another page title or filename.")
    static let description = text("description", "Open any page in this package. Your place is saved for each page.")
    static func count(_ value: Int) -> String {
        String(format: text("count", "%ld pages"), value)
    }
}
