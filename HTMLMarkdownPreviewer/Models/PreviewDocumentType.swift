import Foundation

enum PreviewDocumentType: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case html
    case markdown
    case zipPackage
    case plainText
    case unsupported

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .html:
            AppStrings.DocumentTypes.html
        case .markdown:
            AppStrings.DocumentTypes.markdown
        case .zipPackage:
            AppStrings.DocumentTypes.zip
        case .plainText:
            AppStrings.DocumentTypes.text
        case .unsupported:
            AppStrings.DocumentTypes.unsupported
        }
    }

    var systemImage: String {
        switch self {
        case .html:
            "chevron.left.forwardslash.chevron.right"
        case .markdown:
            "text.alignleft"
        case .zipPackage:
            "archivebox"
        case .plainText:
            "doc.text"
        case .unsupported:
            "questionmark.document"
        }
    }
}
