#if DEBUG
import Foundation

/// Seeds and removes only this test run's ZIP; never resets the user's library.
enum PackageNavigationTestFixtures {
    static func handle(arguments: [String], store: DocumentLibraryStore) -> Bool {
        guard ProcessInfo.processInfo.environment["HTML_PREVIEWER_UI_TESTS"] == "1" else { return false }
        for action in ["fixture", "cleanup"] {
            let prefix = "--package-\(action)="
            guard let argument = arguments.first(where: { $0.hasPrefix(prefix) }),
                  let token = UUID(uuidString: String(argument.dropFirst(prefix.count))) else { continue }
            let filename = "QA-Package-\(token.uuidString).zip"
            let documents = (try? store.loadDocuments()) ?? []
            if action == "cleanup" {
                for document in documents where document.originalFilename == filename { try? store.delete(document) }
                return true
            }
            guard !documents.contains(where: { $0.originalFilename == filename }) else { return false }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PackageQA-\(token.uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            do {
                let sample = try BuiltInSampleProvider(rootURL: directory).makeSampleURL(for: .zipPackage)
                let archive = directory.appendingPathComponent(filename)
                try FileManager.default.copyItem(at: sample, to: archive)
                _ = try DocumentImportService(store: store).importDocument(from: archive, source: .bundledSample)
                return true
            } catch { return false }
        }
        return false
    }
}
#endif
