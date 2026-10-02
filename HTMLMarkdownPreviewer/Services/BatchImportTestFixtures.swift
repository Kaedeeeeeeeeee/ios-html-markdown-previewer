#if DEBUG
import Foundation

/// Exercises the same staged queue as the document picker. Fixtures are scoped
/// to an explicit UUID and never reset or remove another document library.
enum BatchImportTestFixtures {
    static func handle(
        arguments: [String],
        store: DocumentLibraryStore,
        errorMessage: (Error) -> String
    ) throws -> BatchImportSession? {
        guard ProcessInfo.processInfo.environment["HTML_PREVIEWER_UI_TESTS"] == "1" else { return nil }
        if let token = token(for: "--batch-import-cleanup=", in: arguments) {
            let prefix = filenamePrefix(token)
            for document in try store.loadDocuments() where document.originalFilename.hasPrefix(prefix) {
                try store.delete(document)
            }
            return nil
        }
        guard let token = token(for: "--batch-import-fixture=", in: arguments) else { return nil }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchImportQA-\(token.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let prefix = filenamePrefix(token)
        let service = DocumentImportService(store: store)
        func write(_ name: String, _ content: String) throws -> URL {
            let url = directory.appendingPathComponent(prefix + name)
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        }
        let urls: [URL]
        if arguments.contains("--batch-import-scenario=all-failed") {
            urls = [try write("Unsupported.bin", "\(token)"), try write("Broken.zip", "not an archive \(token)")]
        } else if arguments.contains("--batch-import-scenario=single") {
            urls = [try write("Single.md", "# Batch single preview\n\n\(token)")]
        } else {
            for name in ["Update", "Keep", "Skip"] {
                _ = try service.importDocument(
                    from: write("\(name).md", "# Batch \(name) original\n\n\(token)"), source: .fileImporter
                )
            }
            urls = [
                try write("First.html", "<h1>Batch first file</h1><p>\(token)</p>"),
                try write("Unsupported.bin", "\(token)"),
                try write("Update.md", "# Batch Update replacement\n\n\(token)"),
                try write("Keep.md", "# Batch Keep replacement\n\n\(token)"),
                try write("Skip.md", "# Batch Skip replacement\n\n\(token)"),
                try write("Last.md", "# Batch last file\n\n\(token)")
            ]
        }
        // Sources disappear immediately afterwards, proving review only uses
        // the app-owned staged copies, including after a duplicate is skipped.
        return BatchImportSession.prepare(urls: urls, source: .fileImporter, service: service, errorMessage: errorMessage)
    }

    private static func filenamePrefix(_ token: UUID) -> String { "QA-BatchImport-\(token.uuidString)-" }

    private static func token(for prefix: String, in arguments: [String]) -> UUID? {
        guard let argument = arguments.first(where: { $0.hasPrefix(prefix) }) else { return nil }
        return UUID(uuidString: String(argument.dropFirst(prefix.count)))
    }
}
#endif
