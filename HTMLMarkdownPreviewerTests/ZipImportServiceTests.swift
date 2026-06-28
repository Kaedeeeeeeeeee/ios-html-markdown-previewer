import Foundation
import XCTest
import ZIPFoundation
@testable import HTMLMarkdownPreviewer

final class ZipImportServiceTests: XCTestCase {
    func testRejectsPathTraversal() throws {
        let archiveURL = try makeArchive(files: ["../escape.html": "<p>bad</p>".data(using: .utf8)!])
        let destinationURL = try makeTemporaryDirectory().appendingPathComponent("import", isDirectory: true)

        XCTAssertThrowsError(try ZipImportService().importArchive(from: archiveURL, to: destinationURL)) { error in
            XCTAssertEqual(error as? ZipImportError, .unsafePath("../escape.html"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testRejectsDuplicateNormalizedPath() throws {
        let archiveURL = try makeArchive(files: [
            "index.html": "<p>one</p>".data(using: .utf8)!,
            "folder/../index.html": "<p>two</p>".data(using: .utf8)!
        ])
        let destinationURL = try makeTemporaryDirectory().appendingPathComponent("import", isDirectory: true)

        XCTAssertThrowsError(try ZipImportService().importArchive(from: archiveURL, to: destinationURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testRejectsCaseConflictingPath() throws {
        let archiveURL = try makeArchive(files: [
            "assets/logo.png": Data([1]),
            "assets/LOGO.png": Data([2]),
            "index.html": "<img src=\"assets/logo.png\">".data(using: .utf8)!
        ])
        let destinationURL = try makeTemporaryDirectory().appendingPathComponent("import", isDirectory: true)

        XCTAssertThrowsError(try ZipImportService().importArchive(from: archiveURL, to: destinationURL)) { error in
            guard case .caseConflictingPath(let path) = error as? ZipImportError else {
                XCTFail("Expected caseConflictingPath, got \(error)")
                return
            }
            XCTAssertTrue(["assets/logo.png", "assets/LOGO.png"].contains(path))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testRejectsArchiveFileOverConfiguredSizeLimit() throws {
        let archiveURL = try makeArchive(files: [
            "index.html": "<p>root</p>".data(using: .utf8)!
        ])
        let destinationURL = try makeTemporaryDirectory().appendingPathComponent("import", isDirectory: true)
        let service = ZipImportService(limits: ZipImportLimits(maxArchiveBytes: 1))

        XCTAssertThrowsError(try service.importArchive(from: archiveURL, to: destinationURL)) { error in
            XCTAssertEqual(error as? ZipImportError, .archiveTooLarge)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testSelectsRootIndexHTMLAndSkipsMacOSMetadata() throws {
        let archiveURL = try makeArchive(files: [
            "__MACOSX/._index.html": Data([0]),
            ".DS_Store": Data([0]),
            "nested/report.html": "<p>nested</p>".data(using: .utf8)!,
            "index.html": "<p>root</p>".data(using: .utf8)!
        ])
        let destinationURL = try makeTemporaryDirectory().appendingPathComponent("import", isDirectory: true)

        let result = try ZipImportService().importArchive(from: archiveURL, to: destinationURL)

        XCTAssertEqual(result.entryFileURL.lastPathComponent, "index.html")
        XCTAssertEqual(result.extractedFileCount, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.appendingPathComponent("__MACOSX").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.appendingPathComponent(".DS_Store").path))
    }

    func testCleansTemporaryDirectoryAfterImportFailure() throws {
        let tempRoot = FileManager.default.temporaryDirectory
        let before = try zipImportTemporaryDirectories(in: tempRoot)
        let archiveURL = try makeArchive(files: ["../../escape.html": Data([1])])
        let destinationURL = try makeTemporaryDirectory().appendingPathComponent("import", isDirectory: true)

        XCTAssertThrowsError(try ZipImportService().importArchive(from: archiveURL, to: destinationURL))

        let after = try zipImportTemporaryDirectories(in: tempRoot)
        XCTAssertEqual(before, after)
    }

    private func zipImportTemporaryDirectories(in root: URL) throws -> Set<String> {
        let urls = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )
        return Set(urls.map(\.lastPathComponent).filter { $0.hasPrefix("zip-import-") })
    }
}

func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("HTMLMarkdownPreviewerTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makeArchive(files: [String: Data]) throws -> URL {
    let url = try makeTemporaryDirectory().appendingPathComponent("fixture.zip")
    try makeArchive(at: url, files: files)
    return url
}

func makeArchive(at url: URL, files: [String: Data]) throws {
    let archive = try Archive(url: url, accessMode: .create)

    for (path, data) in files {
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(data.count),
            compressionMethod: .deflate
        ) { position, size in
            let start = data.index(data.startIndex, offsetBy: Int(position))
            let end = data.index(start, offsetBy: size)
            return data.subdata(in: start..<end)
        }
    }
}
