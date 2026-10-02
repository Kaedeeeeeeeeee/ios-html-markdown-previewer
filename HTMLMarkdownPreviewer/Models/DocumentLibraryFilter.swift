import Foundation

enum DocumentLibraryFilter: String, CaseIterable, Identifiable {
    case all, html, markdown, yaml, json, zip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: LibraryStrings.allFiles
        case .html: PreviewDocumentType.html.displayName
        case .markdown: PreviewDocumentType.markdown.displayName
        case .yaml: PreviewDocumentType.yaml.displayName
        case .json: PreviewDocumentType.json.displayName
        case .zip: PreviewDocumentType.zipPackage.displayName
        }
    }

    var systemImage: String {
        switch self {
        case .all: "doc.on.doc"
        case .html: PreviewDocumentType.html.systemImage
        case .markdown: PreviewDocumentType.markdown.systemImage
        case .yaml: PreviewDocumentType.yaml.systemImage
        case .json: PreviewDocumentType.json.systemImage
        case .zip: PreviewDocumentType.zipPackage.systemImage
        }
    }

    func matches(_ document: PreviewDocument) -> Bool {
        switch self {
        case .all: true
        case .html: document.type == .html
        case .markdown: document.type == .markdown
        case .yaml: document.type == .yaml
        case .json: document.type == .json
        case .zip: document.type == .zipPackage
        }
    }

    func documents(in documents: [PreviewDocument], matching query: String) -> [PreviewDocument] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return documents.filter { document in
            matches(document) && (trimmed.isEmpty ||
                document.displayName.localizedStandardContains(trimmed) ||
                document.originalFilename.localizedStandardContains(trimmed))
        }
    }
}
