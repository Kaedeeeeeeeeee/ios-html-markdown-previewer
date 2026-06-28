import UniformTypeIdentifiers
import XCTest
@testable import HTMLMarkdownPreviewer

final class FileTypeDetectorTests: XCTestCase {
    func testDetectsSupportedExtensionsFromURL() {
        let cases: [(filename: String, expectedType: PreviewDocumentType)] = [
            ("report.html", .html),
            ("legacy.HTM", .html),
            ("README.md", .markdown),
            ("notes.MARKDOWN", .markdown),
            ("package.zip", .zipPackage)
        ]

        for testCase in cases {
            let url = URL(fileURLWithPath: "/tmp/\(testCase.filename)")
            XCTAssertEqual(
                FileTypeDetector.documentType(for: url),
                testCase.expectedType,
                "Expected \(testCase.filename) to detect as \(testCase.expectedType)."
            )
        }
    }

    func testDetectsSupportedExtensionsFromPath() {
        XCTAssertEqual(FileTypeDetector.documentType(forPath: "folder/report.HTML"), .html)
        XCTAssertEqual(FileTypeDetector.documentType(forPath: "folder/README.Markdown"), .markdown)
        XCTAssertEqual(FileTypeDetector.documentType(forPath: "folder/export.ZIP"), .zipPackage)
    }

    func testDetectsSupportedUTTypes() {
        XCTAssertEqual(FileTypeDetector.documentType(for: .html), .html)
        XCTAssertEqual(FileTypeDetector.documentType(for: SupportedDocumentTypes.markdown), .markdown)
        XCTAssertEqual(FileTypeDetector.documentType(for: .zip), .zipPackage)
    }

    func testImportPickerScopesSeparateDocumentAndZipEntries() {
        XCTAssertTrue(ImportPickerScope.previewDocument.allowedContentTypes.contains(.html))
        XCTAssertTrue(ImportPickerScope.previewDocument.allowedContentTypes.contains(SupportedDocumentTypes.markdown))
        XCTAssertFalse(ImportPickerScope.previewDocument.allowedContentTypes.contains(.zip))

        XCTAssertEqual(ImportPickerScope.zipPackage.allowedContentTypes, [.zip])
        XCTAssertTrue(SupportedDocumentTypes.all.contains(.zip))
    }

    func testFallsBackToUnsupportedForUnknownOrMissingExtension() {
        XCTAssertEqual(FileTypeDetector.documentType(forPath: "folder/report.txt"), .unsupported)
        XCTAssertEqual(FileTypeDetector.documentType(forPath: "folder/report"), .unsupported)
        XCTAssertEqual(FileTypeDetector.documentType(forPathExtension: "pdf"), .unsupported)
        XCTAssertEqual(FileTypeDetector.documentType(for: UTType.plainText), .unsupported)
    }
}
