import Foundation

final class DocumentLibraryStore {
    private let fileManager: FileManager
    private let rootURL: URL
    private let metadataFilename = "metadata.json"

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? Self.defaultRootURL(fileManager: fileManager)
    }

    var importsURL: URL {
        rootURL.appendingPathComponent("Imports", isDirectory: true)
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
        try data.write(to: metadataURL(for: document), options: [.atomic])
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
