import Foundation

enum BatchImportStrings {
    private static func text(_ key: String, _ fallback: String) -> String {
        NSLocalizedString(key, tableName: "BatchImport", bundle: .main, value: fallback, comment: "")
    }

    static let title = text("batch.title", "Import Complete")
    static let imported = text("batch.imported", "Imported")
    static let skipped = text("batch.skipped", "Skipped")
    static let failed = text("batch.failed", "Failed")
    static let failures = text("batch.failures", "Files That Could Not Be Imported")
    static let libraryHint = text("batch.libraryHint", "Imported files are ready in your library.")
    static let skip = text("batch.skip", "Skip This File")
    static let done = text("batch.done", "View Library")
    static let skipHint = text("batch.skipHint", "Cancel skips this file and continues with the remaining files.")
    static let selectionHint = text("batch.selectionHint", "You can select more than one file.")

    static func preparing(_ completed: Int, total: Int) -> String {
        String(format: text("batch.preparing", "Preparing files… %1$ld of %2$ld"), locale: .current, completed, total)
    }

    static func processing(_ completed: Int, total: Int) -> String {
        String(format: text("batch.processing", "Importing files… %1$ld of %2$ld"), locale: .current, completed, total)
    }
}
