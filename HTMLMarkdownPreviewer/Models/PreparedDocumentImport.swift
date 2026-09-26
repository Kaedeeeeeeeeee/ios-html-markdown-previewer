import Foundation

struct PreparedDocumentImport: Identifiable {
    let document: PreviewDocument
    let duplicate: DocumentImportDuplicate?
    var id: UUID { document.id }
}

struct DocumentImportDuplicate {
    let document: PreviewDocument
    let hasIdenticalContents: Bool
}

enum DocumentImportResolution {
    case keepBoth
    case updateExisting
}

enum DocumentLibraryError: Error, LocalizedError, Equatable {
    case emptyName
    case nameTooLong
    case invalidName
    case documentNoLongerExists

    var errorDescription: String? {
        switch self {
        case .emptyName: LibraryStrings.emptyName
        case .nameTooLong: LibraryStrings.nameTooLong
        case .invalidName: LibraryStrings.invalidName
        case .documentNoLongerExists: LibraryStrings.documentNoLongerExists
        }
    }
}
