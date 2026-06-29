import Foundation

enum AppStrings {
    enum Actions {
        static let ok = String(localized: "action.ok", defaultValue: "OK")
        static let cancel = String(localized: "action.cancel", defaultValue: "Cancel")
        static let copyLink = String(localized: "action.copyLink", defaultValue: "Copy Link")
    }

    enum Errors {
        static let cannotOpenFileTitle = String(
            localized: "error.cannotOpenFile.title",
            defaultValue: "Cannot Open File"
        )
        static let cannotOpenHTMLTitle = String(
            localized: "error.cannotOpenHTML.title",
            defaultValue: "Cannot Open HTML"
        )
        static let previewUnavailableTitle = String(
            localized: "error.previewUnavailable.title",
            defaultValue: "Preview Unavailable"
        )
        static let unsupportedEntryType = String(
            localized: "error.unsupportedEntryType",
            defaultValue: "This entry type is not supported yet."
        )
        static let unsupportedFileType = String(
            localized: "error.unsupportedFileType",
            defaultValue: "Current version supports HTML, Markdown, and ZIP files."
        )
        static let zipInvalidArchive = String(
            localized: "error.zip.invalidArchive",
            defaultValue: "The ZIP package could not be read."
        )
        static let zipUnsafeOrConflictingPath = String(
            localized: "error.zip.unsafeOrConflictingPath",
            defaultValue: "The ZIP package contains unsafe or conflicting paths."
        )
        static let zipArchiveTooLarge = String(
            localized: "error.zip.archiveTooLarge",
            defaultValue: "The ZIP package is over the 100 MB limit."
        )
        static let zipTooManyFiles = String(
            localized: "error.zip.tooManyFiles",
            defaultValue: "The ZIP package contains too many files."
        )
        static let zipSingleFileTooLarge = String(
            localized: "error.zip.singleFileTooLarge",
            defaultValue: "The ZIP package contains a file over the 100 MB limit."
        )
        static let zipExpandedSizeTooLarge = String(
            localized: "error.zip.expandedSizeTooLarge",
            defaultValue: "The ZIP package expands beyond the 300 MB limit."
        )
        static let zipMissingEntryFile = String(
            localized: "error.zip.missingEntryFile",
            defaultValue: "No previewable HTML or Markdown entry was found in this ZIP package."
        )
        static let cannotClearImportedFilesTitle = String(
            localized: "error.cannotClearImportedFiles.title",
            defaultValue: "Cannot Clear Imported Files"
        )

        static func unsupportedEncoding(filename: String) -> String {
            let format = String(
                localized: "error.text.unsupportedEncoding",
                defaultValue: "Cannot decode %@ as text. Export it as UTF-8 or UTF-16 and try again."
            )
            return String(format: format, filename)
        }
    }

    enum Security {
        static let interactiveModeTitle = String(
            localized: "security.html.interactive.title",
            defaultValue: "Use Interactive Mode?"
        )
        static let useInteractiveMode = String(
            localized: "security.html.interactive.use",
            defaultValue: "Use Interactive Mode"
        )
        static let interactiveModeConfirmation = String(
            localized: "security.html.interactive.confirmation",
            defaultValue: "Only use interactive mode for HTML files you trust."
        )
        static let rawTextStatus = String(
            localized: "security.preview.rawText.message",
            defaultValue: "Showing the file source."
        )
        static let safeHTMLZipStatus = String(
            localized: "security.html.safe.zip.message",
            defaultValue: "Scripts and external network resources are blocked."
        )
        static let safeHTMLSingleFileStatus = String(
            localized: "security.html.safe.singleFile.message",
            defaultValue: "Scripts and external network resources are blocked. Relative assets are best effort for single files."
        )
        static let interactiveHTMLStatus = String(
            localized: "security.html.interactive.status",
            defaultValue: "Page scripts can run. External navigation remains blocked."
        )
        static let externalMarkdownLinkTitle = String(
            localized: "security.markdown.externalLink.title",
            defaultValue: "External Link Blocked"
        )
        static let externalMarkdownLinkMessage = String(
            localized: "security.markdown.externalLink.message",
            defaultValue: "Markdown preview keeps web links from opening another app."
        )
        static let unsupportedMarkdownLinkTitle = String(
            localized: "security.markdown.unsupportedLink.title",
            defaultValue: "Link Not Opened"
        )
        static let unsupportedMarkdownLinkMessage = String(
            localized: "security.markdown.unsupportedLink.message",
            defaultValue: "This link type is not supported in Markdown preview."
        )
    }

    enum Settings {
        static let clearImportedFilesConfirmation = String(
            localized: "settings.clearImportedFiles.confirmation",
            defaultValue: "This removes imported copies, extracted ZIP contents, and recent-file metadata from this app."
        )
    }
}
