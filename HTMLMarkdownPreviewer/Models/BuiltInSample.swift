import Foundation

enum BuiltInSample: String, CaseIterable, Identifiable, Sendable {
    case html
    case markdown
    case zipPackage

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .html:
            "HTML Sample"
        case .markdown:
            "Markdown Sample"
        case .zipPackage:
            "ZIP Report Sample"
        }
    }

    var subtitle: String {
        switch self {
        case .html:
            "Single-file HTML"
        case .markdown:
            "Formatted Markdown"
        case .zipPackage:
            "HTML with local assets"
        }
    }

    var filename: String {
        switch self {
        case .html:
            "sample.html"
        case .markdown:
            "sample.md"
        case .zipPackage:
            "sample-report.zip"
        }
    }

    var documentType: PreviewDocumentType {
        switch self {
        case .html:
            .html
        case .markdown:
            .markdown
        case .zipPackage:
            .zipPackage
        }
    }
}
