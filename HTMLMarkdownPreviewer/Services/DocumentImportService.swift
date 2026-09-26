import Foundation

enum DocumentImportError: Error, Equatable, LocalizedError {
    case unsupportedFileType(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let filename):
            "Current version cannot preview \(filename)."
        }
    }
}

final class DocumentImportService {
    private let store: DocumentLibraryStore
    private let zipImportService: ZipImportService
    private let externalReferenceScanner: ExternalReferenceScanner
    private let fileManager: FileManager
    private let uuidProvider: () -> UUID
    private let dateProvider: () -> Date

    init(
        store: DocumentLibraryStore = DocumentLibraryStore(),
        zipImportService: ZipImportService = ZipImportService(),
        externalReferenceScanner: ExternalReferenceScanner = ExternalReferenceScanner(),
        fileManager: FileManager = .default,
        uuidProvider: @escaping () -> UUID = UUID.init,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.zipImportService = zipImportService
        self.externalReferenceScanner = externalReferenceScanner
        self.fileManager = fileManager
        self.uuidProvider = uuidProvider
        self.dateProvider = dateProvider
    }

    func importDocument(from sourceURL: URL, source: ImportSource) throws -> PreviewDocument {
        let prepared = try prepareImport(from: sourceURL, source: source)
        return try resolve(prepared, as: .keepBoth)
    }

    func prepareImport(from sourceURL: URL, source: ImportSource) throws -> PreparedDocumentImport {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let detectedType = FileTypeDetector.documentType(for: sourceURL)
        guard detectedType != .unsupported, detectedType != .plainText else {
            throw DocumentImportError.unsupportedFileType(sourceURL.lastPathComponent)
        }

        let documentID = uuidProvider()
        let documentRootURL = store.stagedDocumentRootURL(for: documentID)
        let originalDirectoryURL = documentRootURL.appendingPathComponent("original", isDirectory: true)
        let extractedDirectoryURL = documentRootURL.appendingPathComponent("extracted", isDirectory: true)

        do {
            try fileManager.createDirectory(at: originalDirectoryURL, withIntermediateDirectories: true)
            let originalFilename = sanitizedFilename(sourceURL.lastPathComponent)
            let originalFileURL = originalDirectoryURL.appendingPathComponent(originalFilename)
            try fileManager.copyItem(at: sourceURL, to: originalFileURL)

            let fileSize = try originalFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
                .map(Int64.init) ?? 0

            let document: PreviewDocument
            if detectedType == .zipPackage {
                let zipResult = try zipImportService.importArchive(
                    from: originalFileURL,
                    to: extractedDirectoryURL
                )
                let entryRelativePath = try relativePath(of: zipResult.entryFileURL, from: documentRootURL)
                let entryType = FileTypeDetector.documentType(for: zipResult.entryFileURL)

                document = PreviewDocument(
                    id: documentID,
                    displayName: displayName(for: sourceURL),
                    originalFilename: sourceURL.lastPathComponent,
                    fileExtension: sourceURL.pathExtension.lowercased(),
                    type: .zipPackage,
                    importSource: source,
                    importedAt: dateProvider(),
                    localRootRelativePath: store.relativeStagedRootPath(for: documentID),
                    originalFileRelativePath: "original/\(originalFilename)",
                    entryFileRelativePath: entryRelativePath,
                    entryDocumentType: entryType,
                    fileSize: fileSize,
                    externalURLCount: externalURLCount(for: zipResult.entryFileURL, type: entryType),
                    extractedFileCount: zipResult.extractedFileCount,
                    totalUncompressedBytes: zipResult.totalUncompressedBytes
                )
            } else {
                document = PreviewDocument(
                    id: documentID,
                    displayName: displayName(for: sourceURL),
                    originalFilename: sourceURL.lastPathComponent,
                    fileExtension: sourceURL.pathExtension.lowercased(),
                    type: detectedType,
                    importSource: source,
                    importedAt: dateProvider(),
                    localRootRelativePath: store.relativeStagedRootPath(for: documentID),
                    originalFileRelativePath: "original/\(originalFilename)",
                    entryFileRelativePath: "original/\(originalFilename)",
                    entryDocumentType: detectedType,
                    fileSize: fileSize,
                    externalURLCount: externalURLCount(for: originalFileURL, type: detectedType)
                )
            }

            return PreparedDocumentImport(document: document, duplicate: try duplicate(for: document))
        } catch {
            try? fileManager.removeItem(at: documentRootURL)
            throw error
        }
    }

    func resolve(_ prepared: PreparedDocumentImport, as resolution: DocumentImportResolution) throws -> PreviewDocument {
        do {
            switch resolution {
            case .keepBoth:
                var document = prepared.document
                document.displayName = try availableDisplayName(for: document)
                return try store.commitStagedDocument(document)
            case .updateExisting:
                guard let duplicate = prepared.duplicate else {
                    return try store.commitStagedDocument(prepared.document)
                }
                // Recheck immediately before saving: a pending import must not restore a stale position.
                guard let current = try store.loadDocuments().first(where: { $0.id == duplicate.document.id }) else {
                    throw DocumentLibraryError.documentNoLongerExists
                }
                let sameContent = hasIdenticalContents(prepared.document, current)
                return try store.replaceContents(
                    of: current,
                    with: prepared.document,
                    preservingReadingPosition: sameContent
                )
            }
        } catch {
            try? discard(prepared)
            throw error
        }
    }

    func discard(_ prepared: PreparedDocumentImport) throws {
        try store.discardStagedDocument(prepared.document)
    }

    func refreshDuplicate(for prepared: PreparedDocumentImport) throws -> PreparedDocumentImport {
        PreparedDocumentImport(document: prepared.document, duplicate: try duplicate(for: prepared.document))
    }

    private func duplicate(for incoming: PreviewDocument) throws -> DocumentImportDuplicate? {
        let candidates = try store.loadDocuments().filter {
            $0.type == incoming.type && (incoming.importSource != .bundledSample || $0.importSource == .bundledSample)
        }
        // Prefer the same filename when several copies exist, then match identical contents under a different name.
        let matchingNames = candidates.filter {
            $0.originalFilename.localizedStandardCompare(incoming.originalFilename) == .orderedSame
        }
        if let identical = (matchingNames + candidates).first(where: { hasIdenticalContents(incoming, $0) }) {
            return DocumentImportDuplicate(document: identical, hasIdenticalContents: true)
        }
        return matchingNames.first.map { DocumentImportDuplicate(document: $0, hasIdenticalContents: false) }
    }

    private func hasIdenticalContents(_ lhs: PreviewDocument, _ rhs: PreviewDocument) -> Bool {
        guard lhs.fileSize == rhs.fileSize else { return false }
        return fileManager.contentsEqual(
            atPath: store.originalFileURL(for: lhs).path,
            andPath: store.originalFileURL(for: rhs).path
        )
    }

    private func availableDisplayName(for document: PreviewDocument) throws -> String {
        let names = try store.loadDocuments().map(\.displayName)
        func exists(_ candidate: String) -> Bool {
            names.contains { $0.localizedStandardCompare(candidate) == .orderedSame }
        }
        guard exists(document.displayName) else { return document.displayName }
        var suffix = 2
        while exists("\(document.displayName) (\(suffix))") { suffix += 1 }
        return "\(document.displayName) (\(suffix))"
    }

    private func sanitizedFilename(_ filename: String) -> String {
        let trimmedFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeFilename = trimmedFilename.map { character in
            character == "/" || character == "\\" || character == ":" ? "-" : character
        }

        let result = String(safeFilename)
        return result.isEmpty ? "document" : result
    }

    private func displayName(for sourceURL: URL) -> String {
        let filename = sourceURL.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return filename.isEmpty ? sourceURL.lastPathComponent : filename
    }

    private func externalURLCount(for fileURL: URL, type: PreviewDocumentType) -> Int? {
        guard type == .html || type == .markdown else {
            return nil
        }

        return try? externalReferenceScanner.countExternalURLs(in: fileURL)
    }

    private func relativePath(of fileURL: URL, from rootURL: URL) throws -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"

        guard filePath.hasPrefix(prefix) else {
            throw DocumentImportError.unsupportedFileType(fileURL.lastPathComponent)
        }

        return String(filePath.dropFirst(prefix.count))
    }
}

struct ExternalReferenceScanner {
    func countExternalURLs(in fileURL: URL) throws -> Int {
        let text = try TextFileReader().readText(from: fileURL)
        return countExternalURLs(in: text)
    }

    func countExternalURLs(in text: String) -> Int {
        Self.externalURLExpression.matches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        ).count
    }

    private static let externalURLExpression = try! NSRegularExpression(
        pattern: #"https?://[^\s"'<>)]+"#,
        options: [.caseInsensitive]
    )
}
