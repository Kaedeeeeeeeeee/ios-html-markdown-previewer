import Foundation

final class DocumentLibraryStore {
    private let fileManager: FileManager
    private let rootURL: URL
    private let metadataFilename = "metadata.json"
    private let metadataWriter: (Data, URL) throws -> Void

    init(
        rootURL: URL? = nil,
        fileManager: FileManager = .default,
        metadataWriter: @escaping (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: [.atomic])
        }
    ) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? Self.defaultRootURL(fileManager: fileManager)
        self.metadataWriter = metadataWriter
    }

    var importsURL: URL {
        rootURL.appendingPathComponent("Imports", isDirectory: true)
    }

    var stagingURL: URL {
        rootURL.appendingPathComponent("Staging", isDirectory: true)
    }

    func stagedDocumentRootURL(for documentID: UUID) -> URL {
        stagingURL.appendingPathComponent(documentID.uuidString, isDirectory: true)
    }

    func relativeStagedRootPath(for documentID: UUID) -> String {
        "Staging/\(documentID.uuidString)"
    }

    func loadDocuments() throws -> [PreviewDocument] {
        guard fileManager.fileExists(atPath: importsURL.path) else {
            return []
        }

        let documentRootURLs = try fileManager.contentsOfDirectory(
            at: importsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let documents = documentRootURLs.compactMap { documentRootURL -> PreviewDocument? in
            guard (try? documentRootURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }

            let metadataURL = documentRootURL.appendingPathComponent(metadataFilename)
            guard let data = try? Data(contentsOf: metadataURL) else {
                return nil
            }

            return try? JSONDecoder().decode(PreviewDocument.self, from: data)
        }

        return documents.sorted { lhs, rhs in
            let lhsDate = lhs.lastOpenedAt ?? lhs.importedAt
            let rhsDate = rhs.lastOpenedAt ?? rhs.importedAt
            return lhsDate > rhsDate
        }
    }

    func save(_ document: PreviewDocument) throws {
        let documentRootURL = documentRootURL(for: document)
        try fileManager.createDirectory(at: documentRootURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try metadataWriter(data, metadataURL(for: document))
    }

    func setPinned(_ isPinned: Bool, for document: PreviewDocument, at date: Date = Date()) throws -> PreviewDocument {
        var updated = latestStoredDocument(for: document)
        updated.pinnedAt = isPinned ? updated.pinnedAt ?? date : nil
        try save(updated)
        return updated
    }

    static func validatedDisplayName(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw DocumentLibraryError.emptyName }
        guard name.count <= 120 else { throw DocumentLibraryError.nameTooLong }
        guard name != ".", name != "..",
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw DocumentLibraryError.invalidName
        }
        return name
    }

    func rename(_ document: PreviewDocument, to name: String) throws -> PreviewDocument {
        var updated = latestStoredDocument(for: document)
        updated.displayName = try Self.validatedDisplayName(name)
        try save(updated)
        return updated
    }

    /// Files stay staged until the user makes a decision. Only committed roots appear in the library.
    func commitStagedDocument(_ document: PreviewDocument) throws -> PreviewDocument {
        let stagedRoot = documentRootURL(for: document)
        let destination = documentRootURL(for: document.id)
        var committed = document
        committed.localRootRelativePath = relativeDocumentRootPath(for: document.id)
        try fileManager.createDirectory(at: importsURL, withIntermediateDirectories: true)
        try fileManager.moveItem(at: stagedRoot, to: destination)
        do {
            try save(committed)
            return committed
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    /// The metadata write is the commit point: until it succeeds, the old payload remains readable.
    func replaceContents(
        of document: PreviewDocument,
        with stagedDocument: PreviewDocument,
        preservingReadingPosition: Bool
    ) throws -> PreviewDocument {
        let root = documentRootURL(for: document)
        guard let data = try? Data(contentsOf: metadataURL(for: document)),
              let current = try? JSONDecoder().decode(PreviewDocument.self, from: data),
              current.id == document.id else {
            throw DocumentLibraryError.documentNoLongerExists
        }
        let contentDirectoryName = "content-\(stagedDocument.id.uuidString)"
        let newContentRoot = root.appendingPathComponent(contentDirectoryName, isDirectory: true)
        let previousChildren = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        try fileManager.moveItem(at: documentRootURL(for: stagedDocument), to: newContentRoot)

        let updated = PreviewDocument(
            id: current.id,
            displayName: current.displayName,
            originalFilename: stagedDocument.originalFilename,
            fileExtension: stagedDocument.fileExtension,
            type: stagedDocument.type,
            importSource: stagedDocument.importSource,
            importedAt: stagedDocument.importedAt,
            localRootRelativePath: current.localRootRelativePath,
            originalFileRelativePath: "\(contentDirectoryName)/\(stagedDocument.originalFileRelativePath)",
            entryFileRelativePath: "\(contentDirectoryName)/\(stagedDocument.entryFileRelativePath)",
            entryDocumentType: stagedDocument.entryDocumentType,
            fileSize: stagedDocument.fileSize,
            externalURLCount: stagedDocument.externalURLCount,
            extractedFileCount: stagedDocument.extractedFileCount,
            totalUncompressedBytes: stagedDocument.totalUncompressedBytes,
            lastOpenedAt: current.lastOpenedAt,
            preferredPreviewMode: current.preferredPreviewMode,
            readingPosition: preservingReadingPosition ? current.readingPosition : nil,
            pinnedAt: current.pinnedAt
        )
        do {
            try save(updated)
        } catch {
            try? fileManager.removeItem(at: newContentRoot)
            throw error
        }
        // Cleanup is deliberately after the atomic metadata swap. Failed cleanup cannot lose the document.
        for child in previousChildren where child.lastPathComponent != metadataFilename {
            try? fileManager.removeItem(at: child)
        }
        return updated
    }

    func discardStagedDocument(_ document: PreviewDocument) throws {
        let stagedRoot = stagedDocumentRootURL(for: document.id)
        if fileManager.fileExists(atPath: stagedRoot.path) {
            try fileManager.removeItem(at: stagedRoot)
        }
    }

    func clearAbandonedStaging() throws {
        if fileManager.fileExists(atPath: stagingURL.path) {
            try fileManager.removeItem(at: stagingURL)
        }
    }

    func markOpened(_ document: PreviewDocument, at date: Date = Date()) throws -> PreviewDocument {
        var updatedDocument = latestStoredDocument(for: document)
        updatedDocument.lastOpenedAt = date
        try save(updatedDocument)
        return updatedDocument
    }

    func updatePreferredPreviewMode(_ mode: PreviewMode, for document: PreviewDocument) throws -> PreviewDocument {
        var updatedDocument = latestStoredDocument(for: document)
        updatedDocument.preferredPreviewMode = mode
        try save(updatedDocument)
        return updatedDocument
    }

    func readingPosition(for document: PreviewDocument) -> ReadingPosition? {
        latestStoredDocument(for: document).readingPosition
    }

    func updateReadingPosition(_ position: ReadingPosition, for document: PreviewDocument) throws {
        // Merge with disk so an older navigation value never overwrites mode or recency.
        var updatedDocument = latestStoredDocument(for: document)
        // A disappearing preview may still reference the payload replaced by a duplicate import.
        guard updatedDocument.entryFileRelativePath == document.entryFileRelativePath else { return }
        let normalized = ReadingPosition(anchorID: position.anchorID, progress: position.progress)
        guard updatedDocument.readingPosition != normalized else { return }
        updatedDocument.readingPosition = normalized
        try save(updatedDocument)
    }

    func delete(_ document: PreviewDocument) throws {
        let documentRootURL = documentRootURL(for: document)
        if fileManager.fileExists(atPath: documentRootURL.path) {
            try fileManager.removeItem(at: documentRootURL)
        }
    }

    func deleteAll() throws {
        if fileManager.fileExists(atPath: importsURL.path) {
            try fileManager.removeItem(at: importsURL)
        }
    }

    func documentRootURL(for documentID: UUID) -> URL {
        importsURL.appendingPathComponent(documentID.uuidString, isDirectory: true)
    }

    func documentRootURL(for document: PreviewDocument) -> URL {
        appending(relativePath: document.localRootRelativePath, to: rootURL)
    }

    func originalFileURL(for document: PreviewDocument) -> URL {
        appending(relativePath: document.originalFileRelativePath, to: documentRootURL(for: document))
    }

    func entryFileURL(for document: PreviewDocument) -> URL {
        appending(relativePath: document.entryFileRelativePath, to: documentRootURL(for: document))
    }

    func readAccessRootURL(for document: PreviewDocument) -> URL {
        if document.type == .zipPackage {
            // Both first imports and replacements keep original/ and extracted/ in the same payload root.
            return originalFileURL(for: document).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("extracted", isDirectory: true)
        }
        return entryFileURL(for: document).deletingLastPathComponent()
    }

    func relativeDocumentRootPath(for documentID: UUID) -> String {
        "Imports/\(documentID.uuidString)"
    }

    private func metadataURL(for document: PreviewDocument) -> URL {
        documentRootURL(for: document).appendingPathComponent(metadataFilename)
    }

    private func latestStoredDocument(for document: PreviewDocument) -> PreviewDocument {
        guard let data = try? Data(contentsOf: metadataURL(for: document)),
              let storedDocument = try? JSONDecoder().decode(PreviewDocument.self, from: data) else {
            return document
        }

        return storedDocument
    }

    private func appending(relativePath: String, to baseURL: URL) -> URL {
        relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .reduce(baseURL) { url, component in
                url.appendingPathComponent(String(component))
            }
    }

    private static func defaultRootURL(fileManager: FileManager) -> URL {
        let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        return applicationSupportURL.appendingPathComponent(
            Bundle.main.bundleIdentifier ?? "HTMLMarkdownPreviewer",
            isDirectory: true
        )
    }
}
