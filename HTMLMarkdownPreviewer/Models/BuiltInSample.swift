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
            AppStrings.Samples.htmlTitle
        case .markdown:
            AppStrings.Samples.markdownTitle
        case .zipPackage:
            AppStrings.Samples.zipTitle
        }
    }

    var subtitle: String {
        switch self {
        case .html:
            AppStrings.Samples.htmlSubtitle
        case .markdown:
            AppStrings.Samples.markdownSubtitle
        case .zipPackage:
            AppStrings.Samples.zipSubtitle
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
