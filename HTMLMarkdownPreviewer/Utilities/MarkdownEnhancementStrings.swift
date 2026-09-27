import Foundation

enum MarkdownEnhancementStrings {
    private static func text(_ key: String, _ fallback: String) -> String {
        NSLocalizedString(key, tableName: "MarkdownEnhancements", bundle: .main, value: fallback, comment: "")
    }

    static let copy = text("copy", "Copy Code")
    static let copied = text("copied", "Copied")
    static let code = text("code", "Code")
    static let diagram = text("diagram", "Diagram")
    static let source = text("source", "Source")
    static let mathError = text("mathError", "This formula could not be displayed. Its source is shown below.")
    static let diagramError = text("diagramError", "This diagram could not be displayed. Its source is shown below.")
    static let loadingError = text("loadingError", "The offline renderer could not be loaded. Try opening the document again.")
    static let codeHeading = text("sample.codeHeading", "Code that reads clearly")
    static let codeIntro = text("sample.codeIntro", "Syntax colors help you follow the code. Copy keeps the original spacing.")
    static let mathHeading = text("sample.mathHeading", "A little mathematics")
    static let mathIntro = text("sample.mathIntro", "An inline formula, $E = mc^2$, fits naturally into a sentence. Larger ideas get their own line:")
    static let diagramHeading = text("sample.diagramHeading", "From idea to diagram")
    static let diagramIntro = text("sample.diagramIntro", "A Mermaid code block becomes a flowchart, even while offline.")
    static let diagramStart = text("sample.diagramStart", "Write")
    static let diagramRead = text("sample.diagramRead", "Preview")
    static let diagramShare = text("sample.diagramShare", "Share PDF")
}
