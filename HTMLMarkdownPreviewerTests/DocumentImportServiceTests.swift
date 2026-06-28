import Foundation
import XCTest
@testable import HTMLMarkdownPreviewer

final class DocumentImportServiceTests: XCTestCase {
    private let fixedID = UUID(uuidString: "6A13AF59-137A-4A02-A6F6-ACD16F6219B4")!
    private let fixedDate = Date(timeIntervalSince1970: 1_718_100_000)

    func testImportsSingleHTMLIntoSandboxAndWritesMetadata() throws {
        let rootURL = try makeTemporaryDirectory()
        let sourceURL = try makeFixtureFile(named: "report.html", contents: "<h1>Report</h1>")
        let store = DocumentLibraryStore(rootURL: rootURL)
        let service = makeService(store: store)

        let document = try service.importDocument(from: sourceURL, source: .fileImporter)

        XCTAssertEqual(document.id, fixedID)
        XCTAssertEqual(document.displayName, "report")
        XCTAssertEqual(document.originalFilename, "report.html")
        XCTAssertEqual(document.type, .html)
        XCTAssertEqual(document.entryDocumentType, .html)
        XCTAssertEqual(document.importSource, .fileImporter)
        XCTAssertEqual(document.importedAt, fixedDate)
        XCTAssertEqual(document.localRootRelativePath, "Imports/\(fixedID.uuidString)")
        XCTAssertEqual(document.originalFileRelativePath, "original/report.html")
        XCTAssertEqual(document.entryFileRelativePath, "original/report.html")
        XCTAssertEqual(try String(contentsOf: store.entryFileURL(for: document), encoding: .utf8), "<h1>Report</h1>")

        let metadataURL = store.documentRootURL(for: document).appendingPathComponent("metadata.json")
        let decodedDocument = try JSONDecoder().decode(PreviewDocument.self, from: Data(contentsOf: metadataURL))
        XCTAssertEqual(decodedDocument, document)
        XCTAssertEqual(try store.loadDocuments(), [document])
    }

    func testImportsZIPAndStoresEntryMetadata() throws {
        let rootURL = try makeTemporaryDirectory()
        let styleData = "body { color: red; }".data(using: .utf8)!
        let htmlData = "<link rel=\"stylesheet\" href=\"assets/style.css\">".data(using: .utf8)!
        let archiveURL = try makeArchive(files: [
            "assets/style.css": styleData,
            "index.html": htmlData
        ])
        let store = DocumentLibraryStore(rootURL: rootURL)
        let service = makeService(store: store)

        let document = try service.importDocument(from: archiveURL, source: .externalOpen)

        XCTAssertEqual(document.type, .zipPackage)
        XCTAssertEqual(document.entryDocumentType, .html)
        XCTAssertEqual(document.importSource, .externalOpen)
        XCTAssertEqual(document.originalFileRelativePath, "original/fixture.zip")
        XCTAssertEqual(document.entryFileRelativePath, "extracted/index.html")
        XCTAssertEqual(document.extractedFileCount, 2)
        XCTAssertEqual(document.totalUncompressedBytes, UInt64(styleData.count + htmlData.count))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.originalFileURL(for: document).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.entryFileURL(for: document).path))
    }

    func testRejectsUnsupportedFilesBeforeCreatingImportRoot() throws {
        let rootURL = try makeTemporaryDirectory()
        let sourceURL = try makeFixtureFile(named: "report.pdf", contents: "%PDF")
        let store = DocumentLibraryStore(rootURL: rootURL)
        let service = makeService(store: store)

        XCTAssertThrowsError(try service.importDocument(from: sourceURL, source: .fileImporter)) { error in
            XCTAssertEqual(error as? DocumentImportError, .unsupportedFileType("report.pdf"))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.documentRootURL(for: fixedID).path))
        XCTAssertEqual(try store.loadDocuments(), [])
    }

    func testCleansDocumentRootAfterZIPImportFailure() throws {
        let rootURL = try makeTemporaryDirectory()
        let archiveURL = try makeArchive(files: ["../escape.html": Data([1])])
        let store = DocumentLibraryStore(rootURL: rootURL)
        let service = makeService(store: store)

        XCTAssertThrowsError(try service.importDocument(from: archiveURL, source: .fileImporter))

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.documentRootURL(for: fixedID).path))
        XCTAssertEqual(try store.loadDocuments(), [])
    }

    func testMarkOpenedPersistsAndSortsRecentDocuments() throws {
        let rootURL = try makeTemporaryDirectory()
        let store = DocumentLibraryStore(rootURL: rootURL)
        var older = makeDocument(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            displayName: "Older",
            importedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = makeDocument(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            displayName: "Newer",
            importedAt: Date(timeIntervalSince1970: 200)
        )
        try store.save(older)
        try store.save(newer)

        older = try store.markOpened(older, at: Date(timeIntervalSince1970: 300))

        XCTAssertEqual(try store.loadDocuments().map(\.id), [older.id, newer.id])
        XCTAssertEqual(try store.loadDocuments().first?.lastOpenedAt, Date(timeIntervalSince1970: 300))
    }

    func testDeleteRemovesDocumentRoot() throws {
        let rootURL = try makeTemporaryDirectory()
        let store = DocumentLibraryStore(rootURL: rootURL)
        let document = makeDocument(id: fixedID)
        try store.save(document)

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.documentRootURL(for: document).path))

        try store.delete(document)

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.documentRootURL(for: document).path))
        XCTAssertEqual(try store.loadDocuments(), [])
    }

    private func makeService(store: DocumentLibraryStore) -> DocumentImportService {
        DocumentImportService(
            store: store,
            uuidProvider: { self.fixedID },
            dateProvider: { self.fixedDate }
        )
    }

    private func makeDocument(
        id: UUID,
        displayName: String = "Document",
        importedAt: Date = Date(timeIntervalSince1970: 100)
    ) -> PreviewDocument {
        PreviewDocument(
            id: id,
            displayName: displayName,
            originalFilename: "\(displayName).md",
            fileExtension: "md",
            type: .markdown,
            importSource: .fileImporter,
            importedAt: importedAt,
            localRootRelativePath: "Imports/\(id.uuidString)",
            entryFileRelativePath: "original/\(displayName).md",
            fileSize: 128
        )
    }

    private func makeFixtureFile(named filename: String, contents: String) throws -> URL {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent(filename)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
