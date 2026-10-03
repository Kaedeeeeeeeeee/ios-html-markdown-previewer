import UniformTypeIdentifiers

enum SupportedDocumentTypes {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")
    static let xhtml = UTType(filenameExtension: "xhtml") ?? .html
    static let yaml = UTType(importedAs: "public.yaml", conformingTo: .plainText)

    static let previewDocuments: [UTType] = [
        .html,
        xhtml,
        markdown,
        yaml,
        .json
    ]

    static let zipPackages: [UTType] = [
        .zip
    ]

    static let all: [UTType] = [
        previewDocuments,
        zipPackages
    ].flatMap { $0 }
}

enum ImportPickerScope: Sendable {
    case previewDocument
    case zipPackage

    var allowedContentTypes: [UTType] {
        switch self {
        case .previewDocument:
            SupportedDocumentTypes.previewDocuments
        case .zipPackage:
            SupportedDocumentTypes.zipPackages
        }
    }
}
