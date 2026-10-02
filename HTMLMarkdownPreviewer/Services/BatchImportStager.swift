import Foundation

/// Copying, ZIP extraction, duplicate comparisons, and commits run serially away
/// from the UI. Only immutable values cross the actor boundary. Each final
/// duplicate check and its commit share one actor call without suspension.
actor BatchImportStager {
    private let service: DocumentImportService

    init(libraryRootURL: URL) {
        service = DocumentImportService(store: DocumentLibraryStore(rootURL: libraryRootURL))
    }

    func prepare(url: URL, source: ImportSource) -> BatchImportStagingResult {
        do {
            return .document(try service.prepareImport(from: url, source: source).document)
        } catch {
            return .failure(filename: url.lastPathComponent, message: BatchImportErrorMessage.message(for: error))
        }
    }

    func accept(_ queuedImport: PreparedDocumentImport) -> BatchImportProcessingResult {
        do {
            let prepared = try service.refreshDuplicate(for: queuedImport)
            if let duplicate = prepared.duplicate {
                if prepared.document.importSource == .bundledSample,
                   duplicate.document.importSource == .bundledSample {
                    if duplicate.hasIdenticalContents {
                        try service.discard(prepared)
                        return .imported(duplicate.document)
                    }
                    return .imported(try service.resolve(prepared, as: .updateExisting))
                }
                return .review(prepared)
            }
            return .imported(try service.resolve(prepared, as: .keepBoth))
        } catch {
            try? service.discard(queuedImport)
            return .failure(message: BatchImportErrorMessage.message(for: error))
        }
    }

    func resolve(_ reviewedImport: PreparedDocumentImport, as resolution: DocumentImportResolution) -> BatchImportProcessingResult {
        do {
            let prepared = try service.refreshDuplicate(for: reviewedImport)
            if case .updateExisting = resolution,
               reviewedImport.duplicate?.document.id != prepared.duplicate?.document.id {
                // A new best match must not silently replace a different file
                // from the one the user reviewed. Keep its staging for review.
                guard prepared.duplicate != nil else { throw DocumentLibraryError.documentNoLongerExists }
                return .review(prepared)
            }
            return .imported(try service.resolve(prepared, as: resolution))
        } catch {
            try? service.discard(reviewedImport)
            return .failure(message: BatchImportErrorMessage.message(for: error))
        }
    }

    func discard(_ prepared: PreparedDocumentImport) -> BatchImportProcessingResult {
        do {
            try service.discard(prepared)
            return .skipped
        } catch {
            return .failure(message: BatchImportErrorMessage.message(for: error))
        }
    }
}

enum BatchImportProcessingResult: Sendable {
    case imported(PreviewDocument)
    case review(PreparedDocumentImport)
    case skipped
    case failure(message: String)
}

enum BatchImportStagingResult: Sendable {
    case document(PreviewDocument)
    case failure(filename: String, message: String)

    var item: BatchImportItem {
        switch self {
        case .document(let document): .prepared(PreparedDocumentImport(document: document, duplicate: nil))
        case .failure(let filename, let message): .failed(BatchImportFailure(filename: filename, message: message))
        }
    }
}

struct BatchImportSourceRequest {
    let urls: [URL]
    let source: ImportSource
    private let accessedURLs: [URL]

    init(urls: [URL], source: ImportSource) {
        self.urls = urls
        self.source = source
        // Begin access before leaving the picker callback, including for files
        // waiting behind another selection. Each successful start is balanced.
        accessedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
    }

    func releaseAccess() {
        for url in accessedURLs { url.stopAccessingSecurityScopedResource() }
    }
}

enum BatchImportErrorMessage {
    static func message(for error: Error) -> String {
        if let importError = error as? DocumentImportError {
            switch importError {
            case .unsupportedFileType: return AppStrings.Errors.unsupportedFileType
            }
        }
        if let zipError = error as? ZipImportError {
            switch zipError {
            case .invalidArchive: return AppStrings.Errors.zipInvalidArchive
            case .unsafePath, .unsupportedEntry, .duplicatePath, .caseConflictingPath:
                return AppStrings.Errors.zipUnsafeOrConflictingPath
            case .archiveTooLarge: return AppStrings.Errors.zipArchiveTooLarge
            case .tooManyFiles: return AppStrings.Errors.zipTooManyFiles
            case .singleFileTooLarge: return AppStrings.Errors.zipSingleFileTooLarge
            case .expandedSizeTooLarge: return AppStrings.Errors.zipExpandedSizeTooLarge
            case .missingEntryFile: return AppStrings.Errors.zipMissingEntryFile
            }
        }
        return error.localizedDescription
    }
}
