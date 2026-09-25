import XCTest
@testable import HTMLMarkdownPreviewer

final class ReadingPersistenceTests: XCTestCase {
    private func document() -> PreviewDocument {
        PreviewDocument(displayName: "Reading", originalFilename: "reading.md", fileExtension: "md",
                        type: .markdown, importSource: .fileImporter, localRootRelativePath: "Imports/reading",
                        entryFileRelativePath: "original/reading.md", fileSize: 128)
    }

    func testVersion12MetadataWithoutReadingPositionStillLoads() throws {
        let original = document()
        let data = try JSONEncoder().encode(original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "readingPosition")
        let legacyData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(PreviewDocument.self, from: legacyData)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertNil(decoded.readingPosition)
    }

    func testPositionSurvivesStoreReloadAndStaleModeUpdates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DocumentLibraryStore(rootURL: root)
        let original = document()
        try store.save(original)
        let openedAt = Date(timeIntervalSince1970: 123456)
        _ = try store.markOpened(original, at: openedAt)
        let position = ReadingPosition(anchorID: "markdown-block-9@0.5", progress: 0.73)
        try store.updateReadingPosition(position, for: original)
        _ = try store.updatePreferredPreviewMode(.rawText, for: original)
        let reopenedStore = DocumentLibraryStore(rootURL: root)
        let restored = try XCTUnwrap(reopenedStore.loadDocuments().first)
        XCTAssertEqual(restored.readingPosition, position)
        XCTAssertEqual(restored.preferredPreviewMode, .rawText)
        XCTAssertEqual(restored.lastOpenedAt, openedAt)
        XCTAssertEqual(reopenedStore.readingPosition(for: original), position)
    }

    func testSavingReadingPositionPreservesLatestModeAndNormalizesProgress() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DocumentLibraryStore(rootURL: root)
        let original = document()
        try store.save(original)
        _ = try store.updatePreferredPreviewMode(.interactive, for: original)
        var position = ReadingPosition(progress: 0)
        position.progress = .infinity
        try store.updateReadingPosition(position, for: original)
        let restored = try XCTUnwrap(store.loadDocuments().first)
        XCTAssertEqual(restored.preferredPreviewMode, .interactive)
        XCTAssertEqual(restored.readingPosition?.progress, 0)
        XCTAssertEqual(ReadingPosition(progress: -0.2).progress, 0)
        XCTAssertEqual(ReadingPosition(progress: 1.2).progress, 1)
    }

    @MainActor
    func testSearchNavigationWrapsInBothDirectionsAndEmptyResultsDoNotNavigate() {
        let reading = DocumentReadingState()
        reading.moveMatch(forward: true)
        XCTAssertNil(reading.navigationRequest)
        reading.matchCount = 3
        reading.moveMatch(forward: true)
        XCTAssertEqual(reading.navigationRequest?.target, .match(0))
        reading.moveMatch(forward: false)
        XCTAssertEqual(reading.selectedMatch, 2)
        reading.moveMatch(forward: true)
        XCTAssertEqual(reading.selectedMatch, 0)
    }

    func testReadingCatalogContainsAllFourAppLanguages() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("HTMLMarkdownPreviewer/Reading.xcstrings")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: [String: Any]])
        XCTAssertFalse(strings.isEmpty)
        for (key, entry) in strings {
            let locales = try XCTUnwrap(entry["localizations"] as? [String: Any])
            for locale in ["en", "zh-Hans", "zh-Hant", "ja"] {
                XCTAssertNotNil(locales[locale], "Missing \(locale) for \(key)")
            }
        }
    }
}
