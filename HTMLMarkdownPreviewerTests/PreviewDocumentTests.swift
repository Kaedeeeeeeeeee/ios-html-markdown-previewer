import XCTest
@testable import HTMLMarkdownPreviewer

final class PreviewDocumentTests: XCTestCase {
    func testPreviewDocumentCodableRoundTripPreservesValues() throws {
        let document = PreviewDocument(
            id: UUID(uuidString: "5F0A871A-5F2A-4AB3-8E9B-A0C9E2B63E75")!,
            displayName: "Quarterly Report",
            originalFilename: "report.html",
            fileExtension: "html",
            type: .html,
            importSource: .fileImporter,
            importedAt: Date(timeIntervalSince1970: 1_718_000_000),
            localRootRelativePath: "Imports/report/original",
            entryFileRelativePath: "report.html",
            fileSize: 12_345,
            lastOpenedAt: Date(timeIntervalSince1970: 1_718_003_600),
            preferredPreviewMode: .safePreview
        )

        let data = try JSONEncoder().encode(document)
        let decodedDocument = try JSONDecoder().decode(PreviewDocument.self, from: data)

        XCTAssertEqual(decodedDocument, document)
    }

    func testPreviewDocumentHashableUsesDocumentValues() {
        let id = UUID(uuidString: "FC4E2DA4-C23D-4B5B-9C86-93606562A62D")!
        let document = PreviewDocument(
            id: id,
            displayName: "README",
            originalFilename: "README.md",
            fileExtension: "md",
            type: .markdown,
            importSource: .externalOpen,
            importedAt: Date(timeIntervalSince1970: 1_718_000_000),
            localRootRelativePath: "Imports/readme/original",
            entryFileRelativePath: "README.md",
            fileSize: 512,
            preferredPreviewMode: .rawText
        )
        let duplicate = PreviewDocument(
            id: id,
            displayName: "README",
            originalFilename: "README.md",
            fileExtension: "md",
            type: .markdown,
            importSource: .externalOpen,
            importedAt: Date(timeIntervalSince1970: 1_718_000_000),
            localRootRelativePath: "Imports/readme/original",
            entryFileRelativePath: "README.md",
            fileSize: 512,
            preferredPreviewMode: .rawText
        )

        XCTAssertEqual(Set([document, duplicate]).count, 1)
    }
}
