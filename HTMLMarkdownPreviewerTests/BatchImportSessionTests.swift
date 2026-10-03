import Foundation
import XCTest
@testable import HTMLMarkdownPreviewer

final class BatchImportSessionTests: XCTestCase {
    @MainActor
    func testBackgroundStagerReturnsOwnedCopyAndRecoversAfterFailure() async throws {
        let root = try temporaryDirectory()
        let store = DocumentLibraryStore(rootURL: root.appendingPathComponent("library"))
        let stager = BatchImportStager(libraryRootURL: store.importsURL.deletingLastPathComponent())
        let invalid = try source("broken.zip", "not a ZIP", in: root)
        let failed = await stager.prepare(url: invalid, source: .fileImporter)
        guard case .failure(let filename, _) = failed else { return XCTFail("Invalid archive should fail without stopping the stager") }
        XCTAssertEqual(filename, "broken.zip")

        let original = try source("report.md", "# Background copy", in: root)
        let result = await stager.prepare(url: original, source: .fileImporter)
        try FileManager.default.removeItem(at: original)
        guard case .prepared(let prepared) = result.item else { return XCTFail("Later file should prepare successfully") }
        let document = try DocumentImportService(store: store).resolve(prepared, as: .keepBoth)
        XCTAssertEqual(try String(contentsOf: store.entryFileURL(for: document), encoding: .utf8), "# Background copy")
        XCTAssertEqual(try stagedChildren(store), [])
    }

    @MainActor
    func testActorCommitsEarlierFileBeforeReviewingNextDuplicate() async throws {
        let root = try temporaryDirectory()
        let store = DocumentLibraryStore(rootURL: root.appendingPathComponent("library"))
        let stager = BatchImportStager(libraryRootURL: store.importsURL.deletingLastPathComponent())
        let firstURL = try source("report.md", "# Earlier", in: temporaryDirectory())
        let secondURL = try source("report.md", "# Later", in: temporaryDirectory())
        let first = await stager.prepare(url: firstURL, source: .fileImporter)
        let second = await stager.prepare(url: secondURL, source: .fileImporter)
        guard case .prepared(let firstPrepared) = first.item,
              case .prepared(let secondPrepared) = second.item else { return XCTFail("Both files should stage before either commits") }

        let firstResult = await stager.accept(firstPrepared)
        guard case .imported(let original) = firstResult else { return XCTFail("First file should commit automatically") }
        let secondResult = await stager.accept(secondPrepared)
        guard case .review(let review) = secondResult else { return XCTFail("Second file should see the first commit and require review") }
        XCTAssertEqual(review.duplicate?.document.id, original.id)
        let updatedResult = await stager.resolve(review, as: .updateExisting)
        guard case .imported(let updated) = updatedResult else { return XCTFail("Reviewed update should commit") }
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(try store.loadDocuments().count, 1)
        XCTAssertEqual(try String(contentsOf: store.entryFileURL(for: updated), encoding: .utf8), "# Later")
        XCTAssertEqual(try stagedChildren(store), [])
    }

    @MainActor
    func testActorRechecksUpdateTargetAndRequiresReviewWhenItsIdentityChanges() async throws {
        let root = try temporaryDirectory()
        let store = DocumentLibraryStore(rootURL: root.appendingPathComponent("library"))
        let service = DocumentImportService(store: store)
        let stager = BatchImportStager(libraryRootURL: store.importsURL.deletingLastPathComponent())
        let original = try service.importDocument(from: source("report.md", "# Original", in: root), source: .fileImporter)
        let incomingURL = try source("report.md", "# Incoming", in: temporaryDirectory())
        let staged = await stager.prepare(url: incomingURL, source: .fileImporter)
        guard case .prepared(let prepared) = staged.item else { return XCTFail("Incoming file should stage") }
        let accepted = await stager.accept(prepared)
        guard case .review(let reviewed) = accepted else { return XCTFail("Original duplicate should be reviewed") }
        XCTAssertEqual(reviewed.duplicate?.document.id, original.id)

        // Another library action replaces the candidate while review is open.
        try store.delete(original)
        let changed = try service.importDocument(from: source("report.md", "# Changed target", in: root), source: .fileImporter)
        let result = await stager.resolve(reviewed, as: .updateExisting)
        guard case .review(let refreshed) = result else { return XCTFail("An unreviewed target must not be overwritten") }
        XCTAssertEqual(refreshed.duplicate?.document.id, changed.id)
        XCTAssertEqual(try String(contentsOf: store.entryFileURL(for: changed), encoding: .utf8), "# Changed target")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.stagedDocumentRootURL(for: prepared.id).path))
        let skipped = await stager.discard(refreshed)
        guard case .skipped = skipped else { return XCTFail("Changed review should remain skippable") }
        XCTAssertEqual(try store.loadDocuments().map(\.id), [changed.id])
        XCTAssertEqual(try stagedChildren(store), [])
    }

    @MainActor
    func testActorMissingReviewedTargetFailsCleansStagingAndAllowsNextFile() async throws {
        let root = try temporaryDirectory()
        let store = DocumentLibraryStore(rootURL: root.appendingPathComponent("library"))
        let service = DocumentImportService(store: store)
        let stager = BatchImportStager(libraryRootURL: store.importsURL.deletingLastPathComponent())
        let original = try service.importDocument(from: source("report.md", "# Original", in: root), source: .fileImporter)
        let incoming = await stager.prepare(url: try source("report.md", "# Incoming", in: temporaryDirectory()), source: .fileImporter)
        guard case .prepared(let prepared) = incoming.item else { return XCTFail("Incoming file should stage") }
        let accepted = await stager.accept(prepared)
        guard case .review(let reviewed) = accepted else { return XCTFail("Duplicate should be reviewed") }
        try store.delete(original)
        let failed = await stager.resolve(reviewed, as: .updateExisting)
        guard case .failure = failed else { return XCTFail("Deleted target must not silently become a new import") }
        XCTAssertEqual(try stagedChildren(store), [])

        let next = await stager.prepare(url: try source("next.md", "# Next", in: root), source: .fileImporter)
        guard case .prepared(let nextPrepared) = next.item else { return XCTFail("Next file should stage") }
        let imported = await stager.accept(nextPrepared)
        guard case .imported(let document) = imported else { return XCTFail("The next file should still import") }
        XCTAssertEqual(document.originalFilename, "next.md")
        XCTAssertEqual(try store.loadDocuments().map(\.originalFilename), ["next.md"])
        XCTAssertEqual(try stagedChildren(store), [])
    }

    func testPreparationFailureDoesNotStopRemainingFilesAndSourcesAreNoLongerNeeded() throws {
        let root = try temporaryDirectory()
        let sources = root.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let store = DocumentLibraryStore(rootURL: root.appendingPathComponent("library"))
        let service = DocumentImportService(store: store)
        let urls = try [
            source("first.md", "# First", in: sources),
            source("broken.zip", "This is not a ZIP file", in: sources),
            source("last.yaml", "name: last", in: sources)
        ]
        var session = prepare(urls, service: service)
        XCTAssertTrue(session.isBatch)
        XCTAssertEqual(session.items.count, 3)
        XCTAssertTrue(try store.loadDocuments().isEmpty, "Staging must not modify the library before review")
        try FileManager.default.removeItem(at: sources)

        while let item = session.nextItem {
            switch item {
            case .prepared(let prepared):
                let document = try service.resolve(prepared, as: .keepBoth)
                XCTAssertTrue(FileManager.default.fileExists(atPath: store.entryFileURL(for: document).path))
                XCTAssertTrue(session.finish(itemID: item.id, outcome: .imported))
            case .failed(let failure):
                XCTAssertEqual(failure.filename, "broken.zip")
                session.finish(itemID: item.id, outcome: .failed(failure))
            }
        }
        XCTAssertTrue(session.isComplete)
        XCTAssertEqual(session.summary.importedCount, 2)
        XCTAssertEqual(session.summary.skippedCount, 0)
        XCTAssertEqual(session.summary.failures.map(\.filename), ["broken.zip"])
        XCTAssertEqual(Set(try store.loadDocuments().map(\.originalFilename)), ["first.md", "last.yaml"])
        XCTAssertEqual(try stagedChildren(store), [])
    }

    func testDuplicateUpdateKeepBothAndSkipCleanStagingAndPreserveSelectedContents() throws {
        let root = try temporaryDirectory()
        let store = DocumentLibraryStore(rootURL: root.appendingPathComponent("library"))
        let service = DocumentImportService(store: store)
        let original = try service.importDocument(from: source("report.md", "# Original", in: root), source: .fileImporter)
        var session = prepare(try [
            source("report.md", "# Update", in: temporaryDirectory()),
            source("report.md", "# Keep Both", in: temporaryDirectory()),
            source("report.md", "# Skip", in: temporaryDirectory())
        ], service: service)

        let update = try nextPrepared(session, service: service)
        let updated = try service.resolve(update, as: .updateExisting)
        XCTAssertEqual(updated.id, original.id)
        session.finish(itemID: update.id, outcome: .imported)

        let keep = try nextPrepared(session, service: service)
        XCTAssertEqual(keep.duplicate?.document.id, original.id)
        _ = try service.resolve(keep, as: .keepBoth)
        session.finish(itemID: keep.id, outcome: .imported)

        let skip = try nextPrepared(session, service: service)
        try service.discard(skip)
        session.finish(itemID: skip.id, outcome: .skipped)

        let documents = try store.loadDocuments()
        XCTAssertEqual(documents.count, 2)
        XCTAssertEqual(Set(try documents.map { try String(contentsOf: store.entryFileURL(for: $0), encoding: .utf8) }), ["# Update", "# Keep Both"])
        XCTAssertEqual(session.summary.importedCount, 2)
        XCTAssertEqual(session.summary.skippedCount, 1)
        XCTAssertTrue(session.summary.failures.isEmpty)
        XCTAssertEqual(try stagedChildren(store), [])
    }

    func testDuplicateIsRefreshedAgainstEarlierImportInSameSelection() throws {
        let root = try temporaryDirectory()
        let store = DocumentLibraryStore(rootURL: root.appendingPathComponent("library"))
        let service = DocumentImportService(store: store)
        var session = prepare(try [
            source("report.md", "# Earlier", in: temporaryDirectory()),
            source("report.md", "# Later", in: temporaryDirectory())
        ], service: service)
        let first = try nextPrepared(session, service: service)
        XCTAssertNil(first.duplicate)
        let original = try service.resolve(first, as: .keepBoth)
        session.finish(itemID: first.id, outcome: .imported)
        let second = try nextPrepared(session, service: service)
        XCTAssertEqual(second.duplicate?.document.id, original.id)
        let replaced = try service.resolve(second, as: .updateExisting)
        session.finish(itemID: second.id, outcome: .imported)
        XCTAssertEqual(try store.loadDocuments().count, 1)
        XCTAssertEqual(try String(contentsOf: store.entryFileURL(for: replaced), encoding: .utf8), "# Later")
        XCTAssertEqual(try stagedChildren(store), [])
    }

    func testResolveFailureCanBeRecordedAndNextFileStillImports() throws {
        let root = try temporaryDirectory()
        let store = DocumentLibraryStore(rootURL: root.appendingPathComponent("library"))
        let service = DocumentImportService(store: store)
        let original = try service.importDocument(from: source("report.md", "# Original", in: root), source: .fileImporter)
        var session = prepare(try [
            source("report.md", "# Updated", in: temporaryDirectory()),
            source("next.md", "# Next", in: root)
        ], service: service)
        let first = try nextPrepared(session, service: service)
        try store.delete(original)
        XCTAssertThrowsError(try service.resolve(first, as: .updateExisting))
        session.finish(itemID: first.id, outcome: .failed(BatchImportFailure(filename: "report.md", message: "Missing saved file")))
        let second = try nextPrepared(session, service: service)
        _ = try service.resolve(second, as: .keepBoth)
        session.finish(itemID: second.id, outcome: .imported)
        XCTAssertEqual(session.summary.importedCount, 1)
        XCTAssertEqual(session.summary.failures.count, 1)
        XCTAssertEqual(try store.loadDocuments().map(\.originalFilename), ["next.md"])
        XCTAssertEqual(try stagedChildren(store), [])
    }

    func testStaleOrRepeatedCallbackCannotAdvanceAnotherFile() {
        let first = BatchImportFailure(filename: "first.zip", message: "Invalid ZIP")
        let second = BatchImportFailure(filename: "second.zip", message: "Invalid ZIP")
        var session = BatchImportSession(items: [.failed(first), .failed(second)])
        XCTAssertFalse(session.finish(itemID: second.id, outcome: .skipped))
        XCTAssertTrue(session.finish(itemID: first.id, outcome: .failed(first)))
        XCTAssertFalse(session.finish(itemID: first.id, outcome: .failed(first)))
        XCTAssertEqual(session.nextItem?.id, second.id)
        XCTAssertTrue(session.finish(itemID: second.id, outcome: .failed(second)))
        XCTAssertTrue(session.isComplete)
        XCTAssertNil(session.nextItem)
        XCTAssertFalse(session.finish(itemID: second.id, outcome: .failed(second)))
        XCTAssertEqual(session.summary.failures.count, 2)
    }

    func testSingleSelectionKeepsSingleFileBehaviorAndEmptySelectionCompletes() {
        let failure = BatchImportFailure(filename: "bad.zip", message: "Invalid ZIP")
        XCTAssertFalse(BatchImportSession(items: [.failed(failure)]).isBatch)
        let empty = BatchImportSession(items: [])
        XCTAssertFalse(empty.isBatch)
        XCTAssertTrue(empty.isComplete)
        XCTAssertNil(empty.nextItem)
    }

    func testMultipleZIPPackagesStageAndCommitIndependently() throws {
        let root = try temporaryDirectory()
        let store = DocumentLibraryStore(rootURL: root.appendingPathComponent("library"))
        let service = DocumentImportService(store: store)
        let sample = try BuiltInSampleProvider(rootURL: root.appendingPathComponent("samples")).makeSampleURL(for: .zipPackage)
        let second = root.appendingPathComponent("second.zip")
        try FileManager.default.copyItem(at: sample, to: second)
        var session = prepare([sample, second], service: service)
        while let item = session.nextItem {
            let prepared = try nextPrepared(session, service: service)
            let document = try service.resolve(prepared, as: .keepBoth)
            XCTAssertEqual(document.type, .zipPackage)
            XCTAssertTrue(FileManager.default.fileExists(atPath: store.entryFileURL(for: document).path))
            session.finish(itemID: item.id, outcome: .imported)
        }
        XCTAssertEqual(session.summary.importedCount, 2)
        XCTAssertEqual(try store.loadDocuments().count, 2)
        XCTAssertEqual(try stagedChildren(store), [])
    }

    private func prepare(_ urls: [URL], service: DocumentImportService) -> BatchImportSession {
        BatchImportSession.prepare(urls: urls, source: .fileImporter, service: service) { $0.localizedDescription }
    }

    private func nextPrepared(_ session: BatchImportSession, service: DocumentImportService) throws -> PreparedDocumentImport {
        guard let item = session.nextItem, case .prepared(let prepared) = item else {
            throw NSError(domain: "BatchImportSessionTests.ExpectedPreparedFile", code: 1)
        }
        return try service.refreshDuplicate(for: prepared)
    }

    private func source(_ name: String, _ content: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func stagedChildren(_ store: DocumentLibraryStore) throws -> [String] {
        guard FileManager.default.fileExists(atPath: store.stagingURL.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: store.stagingURL.path)
    }
}
