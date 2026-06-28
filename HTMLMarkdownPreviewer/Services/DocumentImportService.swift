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
    private let fileManager: FileManager
    private let uuidProvider: () -> UUID
    private let dateProvider: () -> Date

    init(
        store: DocumentLibraryStore = DocumentLibraryStore(),
        zipImportService: ZipImportService = ZipImportService(),
        fileManager: FileManager = .default,
        uuidProvider: @escaping () -> UUID = UUID.init,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.zipImportService = zipImportService
        self.fileManager = fileManager
        self.uuidProvider = uuidProvider
        self.dateProvider = dateProvider
    }

    func importDocument(from sourceURL: URL, source: ImportSource) throws -> PreviewDocument {
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
        let documentRootURL = store.documentRootURL(for: documentID)
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
                    localRootRelativePath: store.relativeDocumentRootPath(for: documentID),
                    originalFileRelativePath: "original/\(originalFilename)",
                    entryFileRelativePath: entryRelativePath,
                    entryDocumentType: entryType,
                    fileSize: fileSize,
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
                    localRootRelativePath: store.relativeDocumentRootPath(for: documentID),
                    originalFileRelativePath: "original/\(originalFilename)",
                    entryFileRelativePath: "original/\(originalFilename)",
                    entryDocumentType: detectedType,
                    fileSize: fileSize
                )
            }

            try store.save(document)
            return document
        } catch {
            try? fileManager.removeItem(at: documentRootURL)
            throw error
        }
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
