import Foundation

enum BuiltInSample: String, CaseIterable, Identifiable, Sendable {
    case html
    case markdown
    case yaml
    case json
    case mermaid
    case csv
    case svg
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
        case .yaml:
            YAMLStrings.sampleTitle
        case .json:
            JSONStrings.sampleTitle
        case .mermaid:
            FormatStrings.mermaidSampleTitle
        case .csv:
            FormatStrings.csvSampleTitle
        case .svg:
            FormatStrings.svgSampleTitle
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
        case .yaml:
            YAMLStrings.sampleSubtitle
        case .json:
            JSONStrings.sampleSubtitle
        case .mermaid:
            FormatStrings.mermaidSampleSubtitle
        case .csv:
            FormatStrings.csvSampleSubtitle
        case .svg:
            FormatStrings.svgSampleSubtitle
        case .zipPackage:
            AppStrings.Samples.zipSubtitle
        }
    }

    var filename: String {
        switch self {
        case .html:
            "weekend-plan.html"
        case .markdown:
            "reading-notes.md"
        case .yaml:
            "app-config.yaml"
        case .json:
            "api-response.json"
        case .mermaid:
            "agent-workflow.mmd"
        case .csv:
            "benchmark-results.csv"
        case .svg:
            "weekly-chart.svg"
        case .zipPackage:
            "reading-week.zip"
        }
    }

    var documentType: PreviewDocumentType {
        switch self {
        case .html:
            .html
        case .markdown:
            .markdown
        case .yaml:
            .yaml
        case .json:
            .json
        case .mermaid:
            .mermaid
        case .csv:
            .csv
        case .svg:
            .svg
        case .zipPackage:
            .zipPackage
        }
    }
}
