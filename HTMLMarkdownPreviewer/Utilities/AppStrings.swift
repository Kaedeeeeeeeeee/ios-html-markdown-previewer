import Foundation

enum AppStrings {
    private static func localized(_ key: String, defaultValue: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: defaultValue, comment: "")
    }

    enum Actions {
        static let ok = AppStrings.localized("action.ok", defaultValue: "OK")
        static let cancel = AppStrings.localized("action.cancel", defaultValue: "Cancel")
        static let copyLink = AppStrings.localized("action.copyLink", defaultValue: "Copy Link")
        static let done = AppStrings.localized("action.done", defaultValue: "Done")
        static let openFile = AppStrings.localized("action.openFile", defaultValue: "Open File")
        static let openZIPPackage = AppStrings.localized("action.openZIPPackage", defaultValue: "Open ZIP Package")
        static let clearImportedFiles = AppStrings.localized(
            "action.clearImportedFiles",
            defaultValue: "Clear Imported Files"
        )
    }

    enum App {
        static let title = AppStrings.localized("app.title", defaultValue: "HTML Previewer")
    }

    enum Accessibility {
        static let settings = AppStrings.localized("accessibility.settings", defaultValue: "Settings")
        static let previewMode = AppStrings.localized("accessibility.previewMode", defaultValue: "Preview Mode")
        static let previewModeHint = AppStrings.localized(
            "accessibility.previewMode.hint",
            defaultValue: "Choose rendered, safe, interactive, or raw text preview."
        )
        static let shareFile = AppStrings.localized("accessibility.shareFile", defaultValue: "Share File")
        static let fileDetails = AppStrings.localized("accessibility.fileDetails", defaultValue: "File Details")
        static let markdownImage = AppStrings.localized("accessibility.markdownImage", defaultValue: "Markdown image")
    }

    enum Home {
        static let samples = AppStrings.localized("home.section.samples", defaultValue: "Samples")
        static let recent = AppStrings.localized("home.section.recent", defaultValue: "Recent")
        static let noRecentFiles = AppStrings.localized("home.empty.title", defaultValue: "No Recent Files")
        static let noRecentFilesDescription = AppStrings.localized(
            "home.empty.description",
            defaultValue: "Open an HTML, Markdown, or ZIP file."
        )
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
        static let title = AppStrings.localized("settings.title", defaultValue: "Settings")
        static let htmlSection = AppStrings.localized("settings.section.html", defaultValue: "HTML")
        static let storageSection = AppStrings.localized("settings.section.storage", defaultValue: "Storage")
        static let zipLimitsSection = AppStrings.localized("settings.section.zipLimits", defaultValue: "ZIP Limits")
        static let privacySection = AppStrings.localized("settings.section.privacy", defaultValue: "Privacy")
        static let defaultMode = AppStrings.localized("settings.row.defaultMode", defaultValue: "Default Mode")
        static let safeJavaScript = AppStrings.localized("settings.row.safeJavaScript", defaultValue: "Safe JavaScript")
        static let safeExternalResources = AppStrings.localized(
            "settings.row.safeExternalResources",
            defaultValue: "Safe External Resources"
        )
        static let importedFiles = AppStrings.localized("settings.row.importedFiles", defaultValue: "Imported Files")
        static let archive = AppStrings.localized("settings.row.archive", defaultValue: "Archive")
        static let singleFile = AppStrings.localized("settings.row.singleFile", defaultValue: "Single File")
        static let expanded = AppStrings.localized("settings.row.expanded", defaultValue: "Expanded")
        static let files = AppStrings.localized("settings.row.files", defaultValue: "Files")
        static let processing = AppStrings.localized("settings.row.processing", defaultValue: "Processing")
        static let account = AppStrings.localized("settings.row.account", defaultValue: "Account")
        static let ads = AppStrings.localized("settings.row.ads", defaultValue: "Ads")
        static let disabled = AppStrings.localized("settings.value.disabled", defaultValue: "Disabled")
        static let blocked = AppStrings.localized("settings.value.blocked", defaultValue: "Blocked")
        static let storedInApp = AppStrings.localized("settings.value.storedInApp", defaultValue: "Stored in App")
        static let onDevice = AppStrings.localized("settings.value.onDevice", defaultValue: "On Device")
        static let none = AppStrings.localized("settings.value.none", defaultValue: "None")
        static let clearImportedFilesTitle = AppStrings.localized(
            "settings.clearImportedFiles.title",
            defaultValue: "Clear Imported Files?"
        )
        static let clearImportedFilesConfirmation = String(
            localized: "settings.clearImportedFiles.confirmation",
            defaultValue: "This removes imported copies, extracted ZIP contents, and recent-file metadata from this app."
        )
    }

    enum Details {
        static let title = AppStrings.localized("details.title", defaultValue: "Details")
        static let fileSection = AppStrings.localized("details.section.file", defaultValue: "File")
        static let importSection = AppStrings.localized("details.section.import", defaultValue: "Import")
        static let previewSection = AppStrings.localized("details.section.preview", defaultValue: "Preview")
        static let zipSection = AppStrings.localized("details.section.zip", defaultValue: "ZIP")
        static let name = AppStrings.localized("details.row.name", defaultValue: "Name")
        static let type = AppStrings.localized("details.row.type", defaultValue: "Type")
        static let entryType = AppStrings.localized("details.row.entryType", defaultValue: "Entry Type")
        static let size = AppStrings.localized("details.row.size", defaultValue: "Size")
        static let source = AppStrings.localized("details.row.source", defaultValue: "Source")
        static let imported = AppStrings.localized("details.row.imported", defaultValue: "Imported")
        static let lastOpened = AppStrings.localized("details.row.lastOpened", defaultValue: "Last Opened")
        static let localCopy = AppStrings.localized("details.row.localCopy", defaultValue: "Local Copy")
        static let mode = AppStrings.localized("details.row.mode", defaultValue: "Mode")
        static let externalURLs = AppStrings.localized("details.row.externalURLs", defaultValue: "External URLs")
        static let entryPath = AppStrings.localized("details.row.entryPath", defaultValue: "Entry Path")
        static let rootPath = AppStrings.localized("details.row.rootPath", defaultValue: "Root Path")
        static let notScanned = AppStrings.localized("details.externalURLs.notScanned", defaultValue: "Not scanned")
        static let noneDetected = AppStrings.localized("details.externalURLs.noneDetected", defaultValue: "None detected")

        static func detectedExternalURLs(_ count: Int) -> String {
            let format = AppStrings.localized("details.externalURLs.detected", defaultValue: "%d detected")
            return String.localizedStringWithFormat(format, count)
        }
    }

    enum PreviewModes {
        static let safePreview = AppStrings.localized("previewMode.safePreview", defaultValue: "Safe Preview")
        static let interactive = AppStrings.localized("previewMode.interactive", defaultValue: "Interactive")
        static let rawText = AppStrings.localized("previewMode.rawText", defaultValue: "Raw Text")
        static let renderedPreview = AppStrings.localized("previewMode.renderedPreview", defaultValue: "Rendered Preview")
    }

    enum DocumentTypes {
        static let html = AppStrings.localized("documentType.html", defaultValue: "HTML")
        static let markdown = AppStrings.localized("documentType.markdown", defaultValue: "Markdown")
        static let zip = AppStrings.localized("documentType.zip", defaultValue: "ZIP")
        static let text = AppStrings.localized("documentType.text", defaultValue: "Text")
        static let unsupported = AppStrings.localized("documentType.unsupported", defaultValue: "Unsupported")
    }

    enum ImportSources {
        static let filePicker = AppStrings.localized("importSource.filePicker", defaultValue: "File Picker")
        static let externalOpen = AppStrings.localized("importSource.externalOpen", defaultValue: "External Open")
        static let zipArchive = AppStrings.localized("importSource.zipArchive", defaultValue: "ZIP Archive")
        static let builtInSample = AppStrings.localized("importSource.builtInSample", defaultValue: "Built-in Sample")
    }

    enum Samples {
        static let htmlTitle = AppStrings.localized("sample.html.title", defaultValue: "HTML Sample")
        static let markdownTitle = AppStrings.localized("sample.markdown.title", defaultValue: "Markdown Sample")
        static let zipTitle = AppStrings.localized("sample.zip.title", defaultValue: "ZIP Report Sample")
        static let htmlSubtitle = AppStrings.localized("sample.html.subtitle", defaultValue: "Single-file HTML")
        static let markdownSubtitle = AppStrings.localized("sample.markdown.subtitle", defaultValue: "Formatted Markdown")
        static let zipSubtitle = AppStrings.localized("sample.zip.subtitle", defaultValue: "HTML with local assets")
    }

    enum SampleContent {
        static let htmlHeading = AppStrings.localized("sampleContent.html.heading", defaultValue: "HTML Preview Sample")
        static let htmlLocalRendering = AppStrings.localized(
            "sampleContent.html.localRendering",
            defaultValue: "This file is rendered locally in safe preview mode."
        )
        static let htmlExternalResources = AppStrings.localized(
            "sampleContent.html.externalResources",
            defaultValue: "Inline styles work, while external network resources are blocked by default."
        )
        static let markdownHeading = AppStrings.localized(
            "sampleContent.markdown.heading",
            defaultValue: "Markdown Preview Sample"
        )
        static let markdownIntro = AppStrings.localized(
            "sampleContent.markdown.intro",
            defaultValue: "This sample shows the built-in Markdown reader."
        )
        static let markdownHeadings = AppStrings.localized(
            "sampleContent.markdown.headings",
            defaultValue: "Headings and paragraphs"
        )
        static let markdownInlineStyles = AppStrings.localized(
            "sampleContent.markdown.inlineStyles",
            defaultValue: "**Bold**, *emphasis*, and `inline code`"
        )
        static let markdownLists = AppStrings.localized(
            "sampleContent.markdown.lists",
            defaultValue: "Ordered and unordered lists"
        )
        static let markdownRemoteImages = AppStrings.localized(
            "sampleContent.markdown.remoteImages",
            defaultValue: "Remote images are not loaded by default."
        )
        static let zipHeading = AppStrings.localized("sampleContent.zip.heading", defaultValue: "ZIP Report Sample")
        static let zipLocalAssets = AppStrings.localized(
            "sampleContent.zip.localAssets",
            defaultValue: "This HTML file uses CSS and an image stored inside the ZIP package."
        )
        static let zipImageAlt = AppStrings.localized("sampleContent.zip.imageAlt", defaultValue: "Local sample image")
    }

    enum MarkdownImages {
        static let localUnavailable = AppStrings.localized(
            "markdown.image.localUnavailable",
            defaultValue: "Local image unavailable"
        )
        static let remoteBlocked = AppStrings.localized(
            "markdown.image.remoteBlocked",
            defaultValue: "Remote image blocked"
        )
        static let unsupported = AppStrings.localized("markdown.image.unsupported", defaultValue: "Unsupported image")
    }
}
