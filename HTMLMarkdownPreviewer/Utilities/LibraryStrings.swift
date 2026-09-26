import Foundation

enum LibraryStrings {
    private static func text(_ key: String, _ fallback: String) -> String {
        NSLocalizedString(key, tableName: "Library", bundle: .main, value: fallback, comment: "")
    }

    static let searchPlaceholder = text("library.search", "Search files")
    static let filter = text("library.filter", "File Type")
    static let allFiles = text("library.all", "All Files")
    static let pinned = text("library.pinned", "Pinned")
    static let pin = text("library.pin", "Pin")
    static let unpin = text("library.unpin", "Unpin")
    static let rename = text("library.rename", "Rename")
    static let delete = text("library.delete", "Delete")
    static let save = text("library.save", "Save")
    static let displayName = text("library.displayName", "Display Name")
    static let originalFile = text("library.originalFile", "Original File")
    static let renameHint = text("library.renameHint", "This changes the name in your library. The original file and its links stay unchanged.")
    static let emptyName = text("library.error.emptyName", "Enter a name for this file.")
    static let nameTooLong = text("library.error.longName", "Use a name with 120 characters or fewer.")
    static let invalidName = text("library.error.invalidName", "Use a readable name without line breaks or control characters.")
    static let documentNoLongerExists = text("library.error.missing", "This file is no longer in your library. Import it again to add a new copy.")
    static let noResults = text("library.noResults", "No Matching Files")
    static let noResultsDescription = text("library.noResultsDescription", "Try a different name or file type.")
    static let clearFilters = text("library.clearFilters", "Show All Files")
    static let importFile = text("library.import", "Import File")
    static let alreadyInLibrary = text("library.duplicate.title", "Already in Your Library")
    static let sameContent = text("library.duplicate.sameContent", "A file with identical contents is already saved. Choose whether to update that file or keep another copy.")
    static let sameFilename = text("library.duplicate.sameFilename", "A file with this original filename is already saved, but its contents are different.")
    static let existingFile = text("library.duplicate.existing", "Saved File")
    static let updateExisting = text("library.duplicate.update", "Update Existing")
    static let keepBoth = text("library.duplicate.keepBoth", "Keep Both")
    static let updateHint = text("library.duplicate.hint", "Updating replaces the saved contents and keeps its name, pin, and preview mode. The reading position is reset when contents change.")
}
