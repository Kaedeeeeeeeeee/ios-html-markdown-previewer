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
                XCTAssertTrue(html.contains("<svg"))
                XCTAssertTrue(html.contains("@keyframes"))
                XCTAssertTrue(html.contains("prefers-reduced-motion"))
                XCTAssertFalse(html.contains("http://"))
                XCTAssertFalse(html.contains("https://"))
            }

            let document = try service.importDocument(from: sampleURL, source: .bundledSample)
            XCTAssertEqual(document.importSource, .bundledSample)

            if sample == .zipPackage {
                XCTAssertEqual(document.type, .zipPackage)
                XCTAssertEqual(document.entryDocumentType, .html)
                XCTAssertEqual(document.extractedFileCount, 3)
            } else {
                XCTAssertEqual(document.type, sample.documentType)
                XCTAssertEqual(document.entryDocumentType, sample.documentType)
            }
        }

        XCTAssertEqual(try store.loadDocuments().count, BuiltInSample.allCases.count)
    }
}
