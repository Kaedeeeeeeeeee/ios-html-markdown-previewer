import Foundation

final class DocumentLibraryStore {
    private let transactionLock: NSRecursiveLock
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
        let canonicalRoot = (rootURL ?? Self.defaultRootURL(fileManager: fileManager))
            .standardizedFileURL.resolvingSymlinksInPath()
        self.rootURL = canonicalRoot
        self.transactionLock = LibraryTransactionLocks.shared.lock(for: canonicalRoot)
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
        transactionLock.lock()
        defer { transactionLock.unlock() }
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
        transactionLock.lock()
        defer { transactionLock.unlock() }
        let documentRootURL = documentRootURL(for: document)
        try fileManager.createDirectory(at: documentRootURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try metadataWriter(data, metadataURL(for: document))
    }

    func setPinned(_ isPinned: Bool, for document: PreviewDocument, at date: Date = Date()) throws -> PreviewDocument {
        transactionLock.lock()
        defer { transactionLock.unlock() }
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
        transactionLock.lock()
        defer { transactionLock.unlock() }
        var updated = latestStoredDocument(for: document)
        updated.displayName = try Self.validatedDisplayName(name)
        try save(updated)
        return updated
    }

    /// Files stay staged until the user makes a decision. Only committed roots appear in the library.
    func commitStagedDocument(_ document: PreviewDocument) throws -> PreviewDocument {
        transactionLock.lock()
        defer { transactionLock.unlock() }
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
        transactionLock.lock()
        defer { transactionLock.unlock() }
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
            // A new extracted payload may have different pages, anchors and content at the same paths.
            savedPackagePageRelativePath: nil,
            packageReadingPositions: nil,
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
        transactionLock.lock()
        defer { transactionLock.unlock() }
        let stagedRoot = stagedDocumentRootURL(for: document.id)
        if fileManager.fileExists(atPath: stagedRoot.path) {
            try fileManager.removeItem(at: stagedRoot)
        }
    }

    func clearAbandonedStaging() throws {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        if fileManager.fileExists(atPath: stagingURL.path) {
            try fileManager.removeItem(at: stagingURL)
        }
    }

    func markOpened(_ document: PreviewDocument, at date: Date = Date()) throws -> PreviewDocument {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        var updatedDocument = latestStoredDocument(for: document)
        updatedDocument.lastOpenedAt = date
        try save(updatedDocument)
        return updatedDocument
    }

    func updatePreferredPreviewMode(_ mode: PreviewMode, for document: PreviewDocument) throws -> PreviewDocument {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        var updatedDocument = latestStoredDocument(for: document)
        updatedDocument.preferredPreviewMode = mode
        try save(updatedDocument)
        return updatedDocument
    }

    func readingPosition(for document: PreviewDocument) -> ReadingPosition? {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        return latestStoredDocument(for: document).readingPosition
    }

    func updateReadingPosition(_ position: ReadingPosition, for document: PreviewDocument) throws {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        // Merge with disk so an older navigation value never overwrites mode or recency.
        var updatedDocument = latestStoredDocument(for: document)
        // A disappearing preview may still reference the payload replaced by a duplicate import.
        guard updatedDocument.entryFileRelativePath == document.entryFileRelativePath else { return }
        let normalized = ReadingPosition(anchorID: position.anchorID, progress: position.progress)
        guard updatedDocument.readingPosition != normalized else { return }
        updatedDocument.readingPosition = normalized
        try save(updatedDocument)
    }

    func savedPackagePageRelativePath(for document: PreviewDocument) -> String? {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        let current = latestStoredDocument(for: document)
        guard current.type == .zipPackage, let path = current.savedPackagePageRelativePath,
              packageCatalog(for: current).page(relativePath: path) != nil else { return nil }
        return path
    }

    func packageReadingPosition(forPage relativePath: String, in document: PreviewDocument) -> ReadingPosition? {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        let current = latestStoredDocument(for: document)
        guard current.type == .zipPackage, PackagePageCatalog.isValidRelativePath(relativePath) else { return nil }
        let catalog = packageCatalog(for: current)
        guard let page = catalog.page(relativePath: relativePath) else { return nil }
        let position = current.packageReadingPositions?[relativePath] ?? (page.isEntry ? current.readingPosition : nil)
        return position.map { ReadingPosition(anchorID: $0.anchorID, progress: $0.progress) }
    }

    /// Selection is saved even before a page reports a position. A nil position preserves that page's last position.
    func updatePackageReadingState(
        pageRelativePath: String,
        position: ReadingPosition? = nil,
        for document: PreviewDocument
    ) throws {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        guard document.type == .zipPackage,
              fileManager.fileExists(atPath: metadataURL(for: document).path),
              PackagePageCatalog.isValidRelativePath(pageRelativePath) else { return }
        // Merge with disk so page callbacks cannot undo a rename, pin, preview mode or another page's position.
        var current = latestStoredDocument(for: document)
        guard current.type == .zipPackage, current.entryFileRelativePath == document.entryFileRelativePath,
              let page = packageCatalog(for: current).page(relativePath: pageRelativePath) else { return }
        let before = current
        current.savedPackagePageRelativePath = pageRelativePath
        if let position {
            let normalized = ReadingPosition(anchorID: position.anchorID, progress: position.progress)
            var positions = current.packageReadingPositions ?? [:]
            positions[pageRelativePath] = normalized
            current.packageReadingPositions = positions
            if page.isEntry { current.readingPosition = normalized }
        }
        guard current != before else { return }
        try save(current)
    }

    private func packageCatalog(for document: PreviewDocument) -> PackagePageCatalog {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        return PackagePageCatalog(rootURL: readAccessRootURL(for: document), entryURL: entryFileURL(for: document))
    }

    func delete(_ document: PreviewDocument) throws {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        let documentRootURL = documentRootURL(for: document)
        if fileManager.fileExists(atPath: documentRootURL.path) {
            try fileManager.removeItem(at: documentRootURL)
        }
    }

    func deleteAll() throws {
        transactionLock.lock()
        defer { transactionLock.unlock() }
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
        transactionLock.lock()
        defer { transactionLock.unlock() }
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

/// Stores for the same canonical library share a recursive transaction lock. Nested
/// helpers (including save) can reenter it; independent libraries remain independent.
/// Weak entries avoid retaining a lock for every temporary/test library forever.
private final class LibraryTransactionLocks: @unchecked Sendable {
    static let shared = LibraryTransactionLocks()
    private let registryLock = NSLock()
    private var locks: [String: WeakLock] = [:]

    private final class WeakLock {
        weak var value: NSRecursiveLock?
        init(_ value: NSRecursiveLock) { self.value = value }
    }

    func lock(for root: URL) -> NSRecursiveLock {
        registryLock.lock()
        defer { registryLock.unlock() }
        let key = root.path
        if let existing = locks[key]?.value { return existing }
        locks = locks.filter { $0.value.value != nil }
        let lock = NSRecursiveLock()
        locks[key] = WeakLock(lock)
        return lock
    }
}
