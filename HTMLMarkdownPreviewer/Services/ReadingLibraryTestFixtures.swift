#if DEBUG
import UIKit

/// Scoped fixtures for simulator and physical-device UI tests. No existing
/// document is reset, modified, or removed without this run's UUID prefix.
@MainActor
enum ReadingLibraryTestFixtures {
    static func handle(arguments: [String], store: DocumentLibraryStore) -> Bool {
        guard ProcessInfo.processInfo.environment["HTML_PREVIEWER_UI_TESTS"] == "1" else { return false }

        if let token = token(for: "--reading-library-cleanup=", in: arguments) {
            let prefix = filenamePrefix(token)
            var changed = false
            for document in (try? store.loadDocuments()) ?? [] where document.originalFilename.hasPrefix(prefix) {
                do {
                    try store.delete(document)
                    changed = true
                } catch {
                    // Cleanup failure leaves this run's fixture available for inspection.
                }
            }
            return restoreAppearance(token) || changed
        }

        guard let token = token(for: "--reading-library-fixture=", in: arguments) else { return false }
        captureAppearanceAndUseDefaults(token)
        let prefix = filenamePrefix(token)
        let existing = Set(((try? store.loadDocuments()) ?? []).map(\.originalFilename))
        var changed = false
        for kind in ["HTML", "Markdown"] {
            let fileExtension = kind == "HTML" ? "html" : "md"
            let filename = "\(prefix)\(kind).\(fileExtension)"
            guard !existing.contains(filename) else { continue }
            do {
                try createDocument(kind: kind, filename: filename, token: token, store: store)
                changed = true
            } catch {
                // The UI test reports a missing fixture instead of changing unrelated data.
            }
        }
        return changed
    }

    private static func token(for argumentPrefix: String, in arguments: [String]) -> UUID? {
        guard let argument = arguments.first(where: { $0.hasPrefix(argumentPrefix) }) else { return nil }
        return UUID(uuidString: String(argument.dropFirst(argumentPrefix.count)))
    }

    private static func filenamePrefix(_ token: UUID) -> String {
        "QA-ReadingLibrary-\(token.uuidString)-"
    }

    private static let appearanceDefaults: [String: Double] = [
        "reading.htmlZoom": 1,
        "reading.markdownFontScale": 1,
        "reading.markdownLineSpacing": 4
    ]

    private static func appearanceBackupKey(_ token: UUID) -> String {
        "reading-library-qa-appearance-backup.\(token.uuidString)"
    }

    private static var fixtureDefaults: UserDefaults {
        // Match HTMLMarkdownPreviewerApp.defaultAppStorage for UI-test launches.
        // Never fall back to the user's normal preferences if isolation fails.
        let suiteName = "\(Bundle.main.bundleIdentifier ?? "HTMLMarkdownPreviewer").UITests"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated UI test preferences")
        }
        return defaults
    }

    private static func captureAppearanceAndUseDefaults(_ token: UUID) {
        let defaults = fixtureDefaults
        let backupKey = appearanceBackupKey(token)
        guard defaults.dictionary(forKey: backupKey) == nil else { return }
        var savedValues: [String: Any] = [:]
        for key in appearanceDefaults.keys {
            if let value = defaults.object(forKey: key) { savedValues[key] = value }
        }
        defaults.set(["values": savedValues], forKey: backupKey)
        for (key, value) in appearanceDefaults { defaults.set(value, forKey: key) }
    }

    private static func restoreAppearance(_ token: UUID) -> Bool {
        let defaults = fixtureDefaults
        let backupKey = appearanceBackupKey(token)
        guard let backup = defaults.dictionary(forKey: backupKey),
              let values = backup["values"] as? [String: Any] else { return false }
        for key in appearanceDefaults.keys {
            if let value = values[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        defaults.removeObject(forKey: backupKey)
        return true
    }

    private static func createDocument(kind: String, filename: String, token: UUID, store: DocumentLibraryStore) throws {
        let documentID = UUID()
        let rootURL = store.documentRootURL(for: documentID)
        let originalURL = rootURL.appendingPathComponent("original", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: originalURL, withIntermediateDirectories: true)
            let content = kind == "HTML" ? html(token: token) : markdown(token: token)
            let contentURL = originalURL.appendingPathComponent(filename)
            try content.write(to: contentURL, atomically: true, encoding: .utf8)
            if kind == "Markdown" {
                try landscapePNG().write(to: originalURL.appendingPathComponent("qa-landscape.png"), options: .atomic)
            }
            try store.save(PreviewDocument(
                id: documentID,
                displayName: "\(filenamePrefix(token))\(kind)",
                originalFilename: filename,
                fileExtension: kind == "HTML" ? "html" : "md",
                type: kind == "HTML" ? .html : .markdown,
                importSource: .bundledSample,
                localRootRelativePath: store.relativeDocumentRootPath(for: documentID),
                originalFileRelativePath: "original/\(filename)",
                entryFileRelativePath: "original/\(filename)",
                fileSize: Int64(content.utf8.count)
            ))
        } catch {
            try? FileManager.default.removeItem(at: rootURL)
            throw error
        }
    }

    private static func html(token: UUID) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>body{font:16px -apple-system;line-height:1.5;padding:18px;color:#173a35;background:#f5faf8}h1{font-size:24px}p{max-width:44rem}</style>
        </head><body><h1>QA HTML \(token.uuidString)</h1><p>HTML layout marker</p>
        <p>A local report keeps its typography while the reader adjusts page zoom. The document stays available without a network connection.</p>
        <h2>Details</h2><p>Full screen makes room for the report. The restore button brings navigation and reading controls back.</p>
        </body></html>
        """
    }

    private static func markdown(token: UUID) -> String {
        """
        # QA Markdown \(token.uuidString)

        Markdown layout marker. Read a little more comfortably with larger text and breathing room between lines. These settings apply to this document type and remain after reopening it.

        ![QA local landscape](qa-landscape.png)

        QA image footer

        ## Reading notes

        The landscape is stored beside this document. Tap it to inspect the picture, then close the viewer to continue reading.
        """
    }

    private static func landscapePNG() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 360))
        return renderer.pngData { context in
            UIColor(red: 0.86, green: 0.95, blue: 0.93, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 360))
            UIColor(red: 0.28, green: 0.55, blue: 0.44, alpha: 1).setFill()
            let hills = UIBezierPath()
            hills.move(to: CGPoint(x: 0, y: 280))
            hills.addCurve(to: CGPoint(x: 600, y: 240), controlPoint1: CGPoint(x: 180, y: 60), controlPoint2: CGPoint(x: 360, y: 350))
            hills.addLine(to: CGPoint(x: 600, y: 360))
            hills.addLine(to: CGPoint(x: 0, y: 360))
            hills.close()
            hills.fill()
            UIColor(red: 0.96, green: 0.77, blue: 0.37, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 430, y: 50, width: 66, height: 66)).fill()
        }
    }
}
#endif
