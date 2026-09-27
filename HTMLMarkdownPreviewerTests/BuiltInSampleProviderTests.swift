import Foundation
import XCTest
@testable import HTMLMarkdownPreviewer

final class BuiltInSampleProviderTests: XCTestCase {
    func testCreatesPreviewableSamples() throws {
        let sampleRootURL = try makeTemporaryDirectory()
        let importRootURL = try makeTemporaryDirectory()
        let provider = BuiltInSampleProvider(rootURL: sampleRootURL)
        let store = DocumentLibraryStore(rootURL: importRootURL)
        var nextUUID = 0
        let service = DocumentImportService(
            store: store,
            uuidProvider: {
                defer { nextUUID += 1 }
                return UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", nextUUID + 1))")!
            },
            dateProvider: { Date(timeIntervalSince1970: 1_718_200_000) }
        )

        for sample in BuiltInSample.allCases {
            let sampleURL = try provider.makeSampleURL(for: sample)
            XCTAssertTrue(FileManager.default.fileExists(atPath: sampleURL.path))
            XCTAssertEqual(FileTypeDetector.documentType(for: sampleURL), sample.documentType)

            if sample == .html {
                let html = try String(contentsOf: sampleURL, encoding: .utf8)
                XCTAssertFalse(html.contains("http://"))
                XCTAssertFalse(html.contains("https://"))
            }

            let document = try service.importDocument(from: sampleURL, source: .bundledSample)
            XCTAssertEqual(document.importSource, .bundledSample)
            XCTAssertEqual(document.preferredPreviewMode, sample == .markdown ? .safePreview : .interactive)

            if sample == .zipPackage {
                XCTAssertEqual(document.type, .zipPackage)
                XCTAssertEqual(document.entryDocumentType, .html)
                XCTAssertEqual(document.extractedFileCount, 5)
            } else {
                XCTAssertEqual(document.type, sample.documentType)
                XCTAssertEqual(document.entryDocumentType, sample.documentType)
            }
        }

        XCTAssertEqual(try store.loadDocuments().count, BuiltInSample.allCases.count)
    }

    func testZIPSampleContainsThreeLinkedLocalizedPagesAndSharedRelativeAssets() throws {
        let sampleRoot = try makeTemporaryDirectory()
        let importRoot = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: sampleRoot)
            try? FileManager.default.removeItem(at: importRoot)
        }
        let provider = BuiltInSampleProvider(rootURL: sampleRoot)
        let store = DocumentLibraryStore(rootURL: importRoot)
        let archive = try provider.makeSampleURL(for: .zipPackage)
        let document = try DocumentImportService(store: store).importDocument(from: archive, source: .bundledSample)
        let entry = store.entryFileURL(for: document)
        let root = entry.deletingLastPathComponent()
        let pages = try PackagePageCatalog(rootURL: root, entryURL: entry).load()
        XCTAssertEqual(Set(pages.map(\.relativePath)), ["index.html", "chapters/details.html", "appendix/notes.md"])
        XCTAssertEqual(pages.first?.relativePath, "index.html")
        XCTAssertEqual(pages.first(where: { $0.relativePath == "chapters/details.html" })?.title, PackageSampleStrings.detailsTitle)
        XCTAssertEqual(pages.first(where: { $0.relativePath == "appendix/notes.md" })?.title, PackageSampleStrings.notesTitle)

        let overview = try String(contentsOf: entry, encoding: .utf8)
        let detailsURL = root.appendingPathComponent("chapters/details.html")
        let details = try String(contentsOf: detailsURL, encoding: .utf8)
        let notes = try String(contentsOf: root.appendingPathComponent("appendix/notes.md"), encoding: .utf8)
        XCTAssertTrue(overview.contains("href=\"chapters/details.html\""))
        XCTAssertTrue(overview.contains("href=\"appendix/notes.md\""))
        XCTAssertTrue(details.contains("<meta charset=\"utf-8\">"))
        XCTAssertTrue(details.contains("href=\"../appendix/notes.md\""))
        XCTAssertTrue(details.contains("href=\"../index.html\""))
        XCTAssertTrue(notes.contains("](../index.html)"))
        XCTAssertTrue(notes.contains("](../chapters/details.html#daily-rhythm)"))
        XCTAssertTrue(notes.contains("\\frac{247}{7}"))
        XCTAssertTrue(notes.contains("```swift"))
        for path in ["../assets/style.css", "../images/pixel.svg"] {
            let asset = try XCTUnwrap(URL(string: path, relativeTo: detailsURL)?.absoluteURL)
            XCTAssertTrue(FileManager.default.fileExists(atPath: asset.path))
        }
    }
}
