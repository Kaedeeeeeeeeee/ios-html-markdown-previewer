import Foundation

enum PreviewDocumentType: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case html
    case markdown
    case yaml
    case json
    case mermaid
    case csv
    case svg
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
        case .yaml:
            "YAML"
        case .json:
            "JSON"
        case .mermaid:
            "Mermaid"
        case .csv:
            "CSV"
        case .svg:
            "SVG"
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
        case .yaml:
            "list.bullet.indent"
        case .json:
            "curlybraces"
        case .mermaid:
            "point.3.connected.trianglepath.dotted"
        case .csv:
            "tablecells"
        case .svg:
            "photo"
        case .zipPackage:
            "archivebox"
        case .plainText:
            "doc.text"
        case .unsupported:
            "questionmark.document"
        }
    }

    /// Documents read through a rendered view with a source-text alternative,
    /// rather than the HTML safe/interactive modes.
    var offersRenderedAndSourceModes: Bool {
        switch self {
        case .markdown, .mermaid, .csv, .svg: true
        case .html, .yaml, .json, .zipPackage, .plainText, .unsupported: false
        }
    }
}
