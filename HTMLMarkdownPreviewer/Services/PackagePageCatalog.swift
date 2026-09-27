import Foundation
import Markdown

/// Only local, regular HTML and Markdown files are pages; assets never appear in the picker.
/// This value can be used from a background task. Title reads are capped at 64 KiB per file.
struct PackagePageCatalog: Sendable {
    private static let titleByteLimit = 64 * 1_024
    private let rootURL: URL
    private let entryURL: URL

    init(rootURL: URL, entryURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
        self.entryURL = entryURL
    }

    func load() throws -> [PackagePage] {
        try Task.checkCancellation()
        guard let root = validatedRoot() else { return [] }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey]
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles],
            errorHandler: { _, error in enumerationError = error; return false }
        ) else { return [] }

        var pages: [PackagePage] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true || values.isHidden == true || Self.isExcludedComponent(url.lastPathComponent) {
                // Foundation does not descend into symlinks. Calling skipDescendants on a
                // non-directory can instead skip the next real directory in enumeration order.
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if values.isRegularFile == true, let page = resolve(url: url) {
                pages.append(page)
            }
        }
        if let enumerationError { throw enumerationError }
        return pages.sorted { lhs, rhs in
            if lhs.isEntry != rhs.isEntry { return lhs.isEntry }
            let folderOrder = Self.naturalCompare(lhs.folderPath, rhs.folderPath)
            if folderOrder != .orderedSame { return folderOrder == .orderedAscending }
            let fileOrder = Self.naturalCompare(lhs.fileURL.lastPathComponent, rhs.fileURL.lastPathComponent)
            if fileOrder != .orderedSame { return fileOrder == .orderedAscending }
            return lhs.relativePath < rhs.relativePath
        }
    }

    func resolve(url: URL) -> PackagePage? {
        guard let validatedURL = validatedFileURL(url),
              let relativePath = relativePath(forValidatedURL: validatedURL),
              let type = Self.pageType(for: validatedURL) else { return nil }
        return PackagePage(
            relativePath: relativePath,
            title: title(for: validatedURL, type: type),
            fileURL: validatedURL,
            documentType: type,
            isEntry: validatedFileURL(entryURL) == validatedURL
        )
    }

    func page(relativePath: String) -> PackagePage? {
        guard Self.isValidRelativePath(relativePath), let root = validatedRoot() else { return nil }
        return resolve(url: root.appendingPathComponent(relativePath))
    }

    func relativePath(for url: URL) -> String? {
        guard let validatedURL = validatedFileURL(url) else { return nil }
        return relativePath(forValidatedURL: validatedURL)
    }

    /// Use the returned URL for loading, retaining page-local queries and anchors without loading an unchecked path.
    func validatedNavigationURL(_ url: URL) -> URL? {
        guard let fileURL = validatedFileURL(url),
              var safeComponents = URLComponents(url: fileURL, resolvingAgainstBaseURL: false),
              let originalComponents = URLComponents(url: url.absoluteURL, resolvingAgainstBaseURL: true) else { return nil }
        safeComponents.percentEncodedQuery = originalComponents.percentEncodedQuery
        safeComponents.percentEncodedFragment = originalComponents.percentEncodedFragment
        return safeComponents.url
    }

    static func isValidRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { component in
            !component.isEmpty && component != "." && component != ".." && !isExcludedComponent(String(component))
        }
    }

    private func validatedRoot() -> URL? {
        guard rootURL.isFileURL,
              rootURL.host == nil || rootURL.host == "" || rootURL.host == "localhost",
              let values = try? rootURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true else { return nil }
        return rootURL.resolvingSymlinksInPath().standardizedFileURL
    }

    private func validatedFileURL(_ url: URL) -> URL? {
        guard url.isFileURL, url.user == nil, url.password == nil, url.port == nil,
              url.host == nil || url.host == "" || url.host == "localhost",
              !url.path.contains("\\"), !url.path.contains("\0"),
              let root = validatedRoot() else { return nil }
        // Resolving the root allows system aliases such as /var -> /private/var, but no package symlinks.
        let lexicalURL = URL(fileURLWithPath: url.path).standardizedFileURL
        let resolvedURL = lexicalURL.resolvingSymlinksInPath().standardizedFileURL
        let prefix = root.path + "/"
        guard resolvedURL.path.hasPrefix(prefix), Self.pageType(for: resolvedURL) != nil else { return nil }

        let lexicalRoot = rootURL.path + "/"
        let relativePath: String
        if lexicalURL.path.hasPrefix(lexicalRoot) {
            relativePath = String(lexicalURL.path.dropFirst(lexicalRoot.count))
        } else if lexicalURL.path.hasPrefix(prefix) {
            relativePath = String(lexicalURL.path.dropFirst(prefix.count))
        } else { return nil }
        guard Self.isValidRelativePath(relativePath) else { return nil }

        var current = root
        for component in relativePath.split(separator: "/") {
            current.appendPathComponent(String(component))
            guard let values = try? current.resourceValues(forKeys: [.isSymbolicLinkKey, .isHiddenKey]),
                  values.isSymbolicLink != true, values.isHidden != true else { return nil }
        }
        guard current.standardizedFileURL == resolvedURL,
              (try? resolvedURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
        return resolvedURL
    }

    private func relativePath(forValidatedURL url: URL) -> String? {
        guard let root = validatedRoot() else { return nil }
        return String(url.path.dropFirst(root.path.count + 1))
    }

    private func title(for url: URL, type: PreviewDocumentType) -> String {
        let fallback = url.deletingPathExtension().lastPathComponent
        guard let handle = try? FileHandle(forReadingFrom: url) else { return fallback }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.titleByteLimit), !data.isEmpty else { return fallback }
        var text: String
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            text = String(data: data, encoding: .utf16) ?? ""
        } else {
            // A byte cap can split the last scalar. Replacement decoding preserves all earlier title text.
            text = String(decoding: data, as: UTF8.self)
        }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let title: String?
        if type == .html {
            title = Self.htmlTitle(in: text)
        } else {
            title = Document(parsing: text).children.compactMap { heading -> String? in
                guard let heading = heading as? Heading else { return nil }
                return Self.markdownTitleText(heading)
            }.first
        }
        guard let title else { return fallback }
        let cleaned = Self.cleanedTitle(title)
        return cleaned.isEmpty ? fallback : String(cleaned.prefix(160))
    }

    private static func htmlTitle(in source: String) -> String? {
        // Comments can contain examples of <title>; they must not become the visible page name.
        let source = source.replacingOccurrences(of: "(?s)<!--.*?-->", with: "", options: .regularExpression)
        guard let expression = try? NSRegularExpression(pattern: "<title\\b[^>]*>(.*?)</title\\s*>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let range = Range(match.range(at: 1), in: source) else { return nil }
        let plain = String(source[range]).replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        // CommonMark already has a complete HTML entity table. Escape Markdown punctuation so only
        // entities are decoded; no HTML parser, WebKit process or remote resources are involved.
        // Keep &, # and ; intact so numeric references (for example &#x65E5;) still decode.
        let punctuation = CharacterSet(charactersIn: "\\`*_{}[]()<>!|~")
        let escaped = cleanedTitle(plain).unicodeScalars.map { scalar in
            (punctuation.contains(scalar) ? "\\" : "") + String(scalar)
        }.joined()
        let paragraph = Document(parsing: "title " + escaped).child(at: 0) as? Paragraph
        return paragraph.map { String($0.plainText.dropFirst(6)) }
    }

    private static func cleanedTitle(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines.union(.controlCharacters))
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func markdownTitleText(_ markup: Markup) -> String {
        switch markup {
        case let text as Markdown.Text: return text.string
        case let code as InlineCode: return code.code
        case let link as SymbolLink: return link.destination ?? ""
        case is InlineHTML: return ""
        case is SoftBreak, is LineBreak: return " "
        default: return markup.children.map(markdownTitleText).joined()
        }
    }

    private static func pageType(for url: URL) -> PreviewDocumentType? {
        switch url.pathExtension.lowercased() {
        case "html", "htm": .html
        case "md", "markdown": .markdown
        default: nil
        }
    }

    private static func isExcludedComponent(_ component: String) -> Bool {
        component.hasPrefix(".") || component.lowercased() == "__macosx"
            || ["$recycle.bin", "system volume information"].contains(component.lowercased())
    }

    private static func naturalCompare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: [.numeric, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
