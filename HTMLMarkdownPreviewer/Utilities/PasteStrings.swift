import Foundation

enum PasteStrings {
    private static func localized(_ key: String, defaultValue: String) -> String {
        NSLocalizedString(key, tableName: "Paste", bundle: .main, value: defaultValue, comment: "")
    }

    static let title = localized("paste.title", defaultValue: "Paste to Preview")
    static let content = localized("paste.content", defaultValue: "Content")
    static let placeholder = localized("paste.placeholder", defaultValue: "Paste HTML or Markdown text here.")
    static let contentHint = localized("paste.contentHint", defaultValue: "Paste HTML or Markdown content. Text stays on this device.")
    static let document = localized("paste.document", defaultValue: "Document")
    static let format = localized("paste.format", defaultValue: "Format")
    static let name = localized("paste.name", defaultValue: "Name (optional)")
    static let defaultDocumentName = localized("paste.defaultName", defaultValue: "Pasted Document")
    static let documentHint = localized("paste.documentHint", defaultValue: "The format is suggested from your text. You can change it before saving to Recent Files.")
    static let preview = localized("paste.preview", defaultValue: "Preview")
    static let preparing = localized("paste.preparing", defaultValue: "Preparing Preview…")
    static let cannotPreview = localized("paste.cannotPreview", defaultValue: "Cannot Preview Text")
    static let emptyContent = localized("paste.error.empty", defaultValue: "Paste or enter some HTML or Markdown text first.")
    static let webAddressOnly = localized("paste.error.webAddress", defaultValue: "Paste the HTML or Markdown content itself. Opening web links is not supported here.")
    static let contentTooLarge = localized("paste.error.tooLarge", defaultValue: "This text is larger than 2 MB. Open it as a file instead.")
    static let importSource = localized("paste.importSource", defaultValue: "Pasted Text")
}
