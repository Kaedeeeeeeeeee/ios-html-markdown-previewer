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
            "HTML"
        case .markdown:
            "Markdown"
        case .zipPackage:
            "ZIP"
        case .plainText:
            "Text"
        case .unsupported:
            "Unsupported"
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
