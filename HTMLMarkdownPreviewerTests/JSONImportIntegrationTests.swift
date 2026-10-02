import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import HTMLMarkdownPreviewer

final class JSONImportIntegrationTests: XCTestCase {
    func testFileImportPreservesOriginalBytesAndReopensFromPersistedLibrary() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Response.JSON")
        let bytes = Data([0xEF, 0xBB, 0xBF]) + Data("{\r\n  \"id\": 9007199254740993,\r\n  \"active\": true\r\n}".utf8)
        try bytes.write(to: source)
        let library = root.appendingPathComponent("Library")
        let store = DocumentLibraryStore(rootURL: library)
        let document = try DocumentImportService(store: store).importDocument(from: source, source: .externalOpen)
        XCTAssertEqual(document.type, .json)
        XCTAssertEqual(document.entryDocumentType, .json)
        XCTAssertNil(document.externalURLCount)
        XCTAssertEqual(try Data(contentsOf: store.originalFileURL(for: document)), bytes)

        let reopened = DocumentLibraryStore(rootURL: library)
        let saved = try XCTUnwrap(reopened.loadDocuments().first)
        XCTAssertEqual(DocumentLibraryFilter.json.documents(in: [saved], matching: "Response"), [saved])
        let preview = try JSONRenderService().render(fileURL: reopened.entryFileURL(for: saved))
        XCTAssertNil(preview.issue)
        XCTAssertEqual(preview.sheets.first?.rows.first(where: { $0.label == "id" })?.value, "9007199254740993")
    }

    func testInvalidJSONRemainsReadableAndShareableAfterImport() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("broken.json")
        let text = "{\n  \"value\": 1,\n}"
        try text.write(to: source, atomically: true, encoding: .utf8)
        let store = DocumentLibraryStore(rootURL: root.appendingPathComponent("Library"))
        let document = try DocumentImportService(store: store).importDocument(from: source, source: .fileImporter)
        let preview = try JSONRenderService().render(fileURL: store.entryFileURL(for: document))
        XCTAssertNotNil(preview.issue)
        XCTAssertEqual(preview.source, text)
        XCTAssertEqual(try String(contentsOf: store.originalFileURL(for: document), encoding: .utf8), text)
    }

    func testJSONImportPickerAndDocumentAssociation() throws {
        XCTAssertEqual(FileTypeDetector.documentType(for: .json), .json)
        XCTAssertEqual(FileTypeDetector.documentType(forPath: "folder/response.JSON"), .json)
        XCTAssertTrue(ImportPickerScope.previewDocument.allowedContentTypes.contains(.json))
        XCTAssertFalse(ImportPickerScope.zipPackage.allowedContentTypes.contains(.json))
        let declarations = try XCTUnwrap(Bundle.main.infoDictionary?["CFBundleDocumentTypes"] as? [[String: Any]])
        XCTAssertTrue(declarations.contains { ($0["LSItemContentTypes"] as? [String])?.contains(UTType.json.identifier) == true })
        XCTAssertEqual(FileTypeDetector.documentType(forPath: "config.jsonc"), .unsupported)
    }

    func testPasteRecognizesJSONContainersAndFencesWithoutChangingMarkdownOrScalars() throws {
        let json = #"{"message":"日本語 / 中文","id":9007199254740993}"#
        XCTAssertEqual(PastedDocumentImportService.suggestedFormat(for: json), .json)
        XCTAssertEqual(PastedDocumentImportService.suggestedFormat(for: "[1, true, null]"), .json)
        XCTAssertEqual(PastedDocumentImportService.suggestedFormat(for: #"{"value":1e400}"#), .json)
        XCTAssertEqual(PastedDocumentImportService.suggestedFormat(for: "```json\n\(json)\n```"), .json)
        XCTAssertEqual(PastedDocumentImportService.suggestedFormat(for: "[Notes](notes.md)"), .markdown)
        XCTAssertEqual(PastedDocumentImportService.suggestedFormat(for: "123"), .markdown)
        XCTAssertEqual(PastedDocumentImportService.suggestedFormat(for: #""Notes""#), .markdown)
        let prepared = try PastedDocumentImportService.prepare(text: "```\n\(json)\n```", name: "Response.JSON", format: .json)
        XCTAssertEqual(prepared.content, json)
        XCTAssertEqual(prepared.filename, "Response.json")
        let invalid = try PastedDocumentImportService.prepare(text: "```json\n{broken}\n```", name: "broken", format: .json)
        XCTAssertEqual(invalid.content, "{broken}")
        XCTAssertEqual(try PastedDocumentImportService.prepare(text: "```\n{\"value\":1e400}\n```", name: "large", format: .json).content, #"{"value":1e400}"#)
        XCTAssertEqual(try PastedDocumentImportService.prepare(text: "```\ntrue\n```", name: "scalar", format: .json).content, "true")
    }

    func testPastedJSONPreservesSourceThroughImportAndDuplicateUpdate() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DocumentLibraryStore(rootURL: root.appendingPathComponent("Library"))
        let paste = PastedDocumentImportService(store: store, temporaryRootURL: root.appendingPathComponent("Paste"))
        let first = try paste.importDocument(text: #"{"count":1}"#, name: "Response", format: .json)
        let text = #"{"count":2,"precise":12345678901234567890}"#
        let prepared = try paste.prepareImport(text: text, name: "Response.json", format: .json)
        XCTAssertEqual(prepared.duplicate?.document.id, first.id)
        let updated = try DocumentImportService(store: store).resolve(prepared, as: .updateExisting)
        XCTAssertEqual(updated.id, first.id)
        XCTAssertEqual(updated.importSource, .pastedText)
        XCTAssertEqual(try store.loadDocuments().count, 1)
        XCTAssertEqual(try String(contentsOf: store.originalFileURL(for: updated), encoding: .utf8), text)
    }
}
