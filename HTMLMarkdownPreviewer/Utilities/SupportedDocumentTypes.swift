import UniformTypeIdentifiers

enum SupportedDocumentTypes {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")
    static let xhtml = UTType(filenameExtension: "xhtml") ?? .html

    static let all: [UTType] = [
        .html,
        xhtml,
        markdown,
        .zip
    ]
}
