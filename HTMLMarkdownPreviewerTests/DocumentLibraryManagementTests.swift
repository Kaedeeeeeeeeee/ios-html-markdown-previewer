import Foundation
import XCTest
@testable import HTMLMarkdownPreviewer

final class DocumentLibraryManagementTests: XCTestCase {
    private var workspace: URL!

    override func setUpWithError() throws {
        workspace = try makeTemporaryDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workspace)
    }

    func testLegacyMetadataWithoutPinDecodesAsUnpinned() throws {
        let store = makeStore()
        let document = try importFile("report.html", "<h1>Original</h1>", store: store)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
        object.removeValue(forKey: "pinnedAt")
        object.removeValue(forKey: "readingPosition")
        let decoded = try JSONDecoder().decode(PreviewDocument.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.id, document.id)
        XCTAssertFalse(decoded.isPinned)
        XCTAssertNil(decoded.readingPosition)
    }

    func testRenameAndPinMergeLatestSettingsWithoutRenamingFiles() throws {
        let store = makeStore()
        let original = try importFile("report.html", "<h1>Original</h1>", store: store)
        let originalURL = store.originalFileURL(for: original)
        let position = ReadingPosition(anchorID: "summary", progress: 0.6)
        try store.updateReadingPosition(position, for: original)
        _ = try store.updatePreferredPreviewMode(.rawText, for: original)
        let pinDate = Date(timeIntervalSince1970: 500)
        _ = try store.setPinned(true, for: original, at: pinDate)
        let renamed = try store.rename(original, to: "  週報 / 研究  ")

        XCTAssertEqual(renamed.displayName, "週報 / 研究")
        XCTAssertEqual(renamed.originalFilename, original.originalFilename)
        XCTAssertEqual(store.originalFileURL(for: renamed), originalURL)
        XCTAssertEqual(renamed.readingPosition, position)
        XCTAssertEqual(renamed.preferredPreviewMode, .rawText)
        XCTAssertEqual(renamed.pinnedAt, pinDate)
        XCTAssertEqual(try makeStore().loadDocuments().first, renamed)
        let unpinned = try store.setPinned(false, for: original)
        XCTAssertFalse(unpinned.isPinned)
        XCTAssertEqual(unpinned.displayName, renamed.displayName)
    }

    func testRenameValidationRejectsEmptyControlAndLongNames() throws {
        for name in ["", " \n ", ".", "..", "name\ninside", "bad\u{0000}name", String(repeating: "界", count: 121)] {
            XCTAssertThrowsError(try DocumentLibraryStore.validatedDisplayName(name), name)
        }
        XCTAssertEqual(try DocumentLibraryStore.validatedDisplayName("  旅の記録  "), "旅の記録")
        XCTAssertNoThrow(try DocumentLibraryStore.validatedDisplayName(String(repeating: "界", count: 120)))
    }

    func testSearchCombinesTypeAndOriginalOrDisplayName() throws {
        let store = makeStore()
        let html = try importFile("Café-Report.html", "<h1>Trip</h1>", store: store)
        _ = try store.rename(html, to: "旅行计划")
        let markdown = try importFile("Report.md", "# Note", store: store)
        let documents = try store.loadDocuments()
        XCTAssertEqual(DocumentLibraryFilter.html.documents(in: documents, matching: "CAFE").map(\.id), [html.id])
        XCTAssertEqual(DocumentLibraryFilter.all.documents(in: documents, matching: "计划").map(\.id), [html.id])
        XCTAssertEqual(DocumentLibraryFilter.markdown.documents(in: documents, matching: " Report ").map(\.id), [markdown.id])
        XCTAssertTrue(DocumentLibraryFilter.zip.documents(in: documents, matching: "").isEmpty)
    }

    func testSameNameDifferentContentRequiresDecisionAndCancelLeavesNoStaging() throws {
        let store = makeStore()
        let original = try importFile("report.html", "<h1>Original</h1>", store: store)
        let service = DocumentImportService(store: store)
        let prepared = try service.prepareImport(from: sourceFile("report.html", "<h1>New report</h1>"), source: .externalOpen)

        XCTAssertEqual(prepared.duplicate?.document.id, original.id)
        XCTAssertEqual(prepared.duplicate?.hasIdenticalContents, false)
        XCTAssertEqual(try store.loadDocuments().map(\.id), [original.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.stagedDocumentRootURL(for: prepared.id).path))
        try service.discard(prepared)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.stagedDocumentRootURL(for: prepared.id).path))
        XCTAssertEqual(try read(original, store: store), "<h1>Original</h1>")
    }

    func testIdenticalContentMatchesEvenWithDifferentOriginalName() throws {
        let store = makeStore()
        let original = try importFile("report.html", "<h1>Report</h1>", store: store)
        let service = DocumentImportService(store: store)
        let prepared = try service.prepareImport(from: sourceFile("renamed.html", "<h1>Report</h1>"), source: .fileImporter)
        XCTAssertEqual(prepared.duplicate?.document.id, original.id)
        XCTAssertEqual(prepared.duplicate?.hasIdenticalContents, true)
        try service.discard(prepared)
    }

    func testQueuedImportRefreshesDuplicateAfterEarlierImportCommitsOrIsDeleted() throws {
        let store = makeStore()
        let importer = DocumentImportService(store: store)
        let first = try importer.prepareImport(from: sourceFile("report.md", "# First"), source: .externalOpen)
        let second = try importer.prepareImport(from: sourceFile("report.md", "# Second"), source: .externalOpen)
        XCTAssertNil(first.duplicate)
        XCTAssertNil(second.duplicate)

        let saved = try importer.resolve(first, as: .keepBoth)
        let refreshed = try importer.refreshDuplicate(for: second)
        XCTAssertEqual(refreshed.id, second.id)
        XCTAssertEqual(refreshed.duplicate?.document.id, saved.id)
        XCTAssertEqual(refreshed.duplicate?.hasIdenticalContents, false)

        try store.delete(saved)
        XCTAssertNil(try importer.refreshDuplicate(for: refreshed).duplicate)
        try importer.discard(refreshed)
        XCTAssertEqual(try stagedChildren(store), [])
    }

    func testKeepBothProducesDistinctIDsAndNamesAndLeavesOriginalUntouched() throws {
        let store = makeStore()
        let original = try importFile("report.md", "# Original", store: store)
        let service = PastedDocumentImportService(store: store)
        let importer = DocumentImportService(store: store)
        let first = try importer.resolve(service.prepareImport(text: "# New", name: "report", format: .markdown), as: .keepBoth)
        let second = try importer.resolve(service.prepareImport(text: "# Newest", name: "report", format: .markdown), as: .keepBoth)
        XCTAssertNotEqual(first.id, original.id)
        XCTAssertNotEqual(second.id, first.id)
        XCTAssertEqual(first.displayName, "report (2)")
        XCTAssertEqual(second.displayName, "report (3)")
        XCTAssertEqual(first.originalFilename, original.originalFilename)
        XCTAssertEqual(try read(original, store: store), "# Original")
        XCTAssertEqual(try store.loadDocuments().count, 3)
        XCTAssertEqual(try stagedChildren(store), [])
    }

    func testChangedContentUpdatePreservesIdentityPinTitleAndModeButResetsPosition() throws {
        let store = makeStore()
        let original = try importFile("report.html", "<h1>Original</h1>", store: store)
        _ = try store.rename(original, to: "Custom title")
        _ = try store.setPinned(true, for: original)
        _ = try store.updatePreferredPreviewMode(.safePreview, for: original)
        try store.updateReadingPosition(ReadingPosition(progress: 0.9), for: original)
        let oldURL = store.originalFileURL(for: original)
        let importer = DocumentImportService(store: store)
        let prepared = try importer.prepareImport(from: sourceFile("report.html", "<h1>Updated</h1>"), source: .externalOpen)
        let updated = try importer.resolve(prepared, as: .updateExisting)

        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.displayName, "Custom title")
        XCTAssertTrue(updated.isPinned)
        XCTAssertEqual(updated.preferredPreviewMode, .safePreview)
        XCTAssertNil(updated.readingPosition)
        XCTAssertEqual(try read(updated, store: store), "<h1>Updated</h1>")
        XCTAssertEqual(try store.loadDocuments().count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(try stagedChildren(store), [])
        try store.updateReadingPosition(ReadingPosition(progress: 0.8), for: original)
        XCTAssertNil(try store.loadDocuments().first?.readingPosition, "A disappearing old preview must not restore its stale reading position")
    }

    func testIdenticalContentUpdateKeepsLatestReadingPosition() throws {
        let store = makeStore()
        let original = try importFile("report.md", "# Same", store: store)
        let importer = DocumentImportService(store: store)
        let prepared = try importer.prepareImport(from: sourceFile("report.md", "# Same"), source: .fileImporter)
        let latestPosition = ReadingPosition(anchorID: "markdown-block-3", progress: 0.7)
        try store.updateReadingPosition(latestPosition, for: original)
        let updated = try importer.resolve(prepared, as: .updateExisting)
        XCTAssertEqual(updated.readingPosition, latestPosition)
        XCTAssertEqual(try store.loadDocuments().count, 1)
    }

    func testFailedMetadataCommitPreservesOriginalAndRemovesNewPayload() throws {
        let store = makeStore()
        let original = try importFile("report.html", "<h1>Original</h1>", store: store)
        let failingStore = DocumentLibraryStore(rootURL: workspace.appendingPathComponent("library"), metadataWriter: { _, _ in
            throw CocoaError(.fileWriteOutOfSpace)
        })
        let importer = DocumentImportService(store: failingStore)
        let prepared = try importer.prepareImport(from: sourceFile("report.html", "<h1>Updated</h1>"), source: .fileImporter)
        XCTAssertThrowsError(try importer.resolve(prepared, as: .updateExisting))
        XCTAssertEqual(try store.loadDocuments(), [original])
        XCTAssertEqual(try read(original, store: store), "<h1>Original</h1>")
        let rootChildren = try FileManager.default.contentsOfDirectory(at: store.documentRootURL(for: original), includingPropertiesForKeys: nil)
        XCTAssertEqual(Set(rootChildren.map(\.lastPathComponent)), ["original", "metadata.json"])
        XCTAssertEqual(try stagedChildren(store), [])
    }

    func testDeletedDuplicateDoesNotGetSilentlyRecreated() throws {
        let store = makeStore()
        let original = try importFile("report.md", "# Original", store: store)
        let importer = DocumentImportService(store: store)
        let prepared = try importer.prepareImport(from: sourceFile("report.md", "# Updated"), source: .fileImporter)
        try store.delete(original)
        XCTAssertThrowsError(try importer.resolve(prepared, as: .updateExisting)) {
            XCTAssertEqual($0 as? DocumentLibraryError, .documentNoLongerExists)
        }
        XCTAssertEqual(try store.loadDocuments(), [])
        XCTAssertEqual(try stagedChildren(store), [])
    }

    func testZIPUpdateKeepsRelativeAssetsInsideReadAccessRoot() throws {
        let store = makeStore()
        let firstURL = workspace.appendingPathComponent("first", isDirectory: true)
        let nextURL = workspace.appendingPathComponent("next", isDirectory: true)
        try FileManager.default.createDirectory(at: firstURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nextURL, withIntermediateDirectories: true)
        let firstArchive = firstURL.appendingPathComponent("report.zip")
        let nextArchive = nextURL.appendingPathComponent("report.zip")
        try makeArchive(at: firstArchive, files: ["index.html": Data("<h1>Original</h1>".utf8)])
        try makeArchive(at: nextArchive, files: [
            "index.html": Data("<link rel='stylesheet' href='assets/style.css'><h1>Updated</h1>".utf8),
            "assets/style.css": Data("h1 { color: green; }".utf8)
        ])
        let importer = DocumentImportService(store: store)
        let original = try importer.importDocument(from: firstArchive, source: .fileImporter)
        let prepared = try importer.prepareImport(from: nextArchive, source: .fileImporter)
        let updated = try importer.resolve(prepared, as: .updateExisting)
        let readRoot = store.readAccessRootURL(for: updated)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertTrue(store.entryFileURL(for: updated).path.hasPrefix(readRoot.path + "/"))
        XCTAssertEqual(try String(contentsOf: readRoot.appendingPathComponent("assets/style.css"), encoding: .utf8), "h1 { color: green; }")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.originalFileURL(for: updated).path))
    }

    func testLibraryLocalizationKeysMatchAcrossAllSupportedLanguages() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("HTMLMarkdownPreviewer")
        var expectedKeys: Set<String>?
        for locale in ["en", "zh-Hans", "zh-Hant", "ja"] {
            let file = sourceRoot.appendingPathComponent("\(locale).lproj/Library.strings")
            let strings = try XCTUnwrap(NSDictionary(contentsOf: file) as? [String: String])
            XCTAssertFalse(strings.isEmpty)
            XCTAssertFalse(strings.values.contains(where: \.isEmpty))
            if let expectedKeys { XCTAssertEqual(Set(strings.keys), expectedKeys, locale) }
            else { expectedKeys = Set(strings.keys) }
        }
    }

    private func makeStore() -> DocumentLibraryStore {
        DocumentLibraryStore(rootURL: workspace.appendingPathComponent("library"))
    }

    private func sourceFile(_ name: String, _ contents: String) throws -> URL {
        let directory = workspace.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(name)
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private func importFile(_ name: String, _ contents: String, store: DocumentLibraryStore) throws -> PreviewDocument {
        try DocumentImportService(store: store).importDocument(from: sourceFile(name, contents), source: .fileImporter)
    }

    private func read(_ document: PreviewDocument, store: DocumentLibraryStore) throws -> String {
        try String(contentsOf: store.originalFileURL(for: document), encoding: .utf8)
    }

    private func stagedChildren(_ store: DocumentLibraryStore) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: store.stagingURL.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: store.stagingURL, includingPropertiesForKeys: nil)
    }
}
