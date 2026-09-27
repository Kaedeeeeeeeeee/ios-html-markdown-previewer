import Foundation
import XCTest
@testable import HTMLMarkdownPreviewer

final class PackageNavigationTests: XCTestCase {
    private var workspace: URL!

    override func setUpWithError() throws {
        workspace = try makeTemporaryDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workspace)
    }

    func testCatalogFindsOnlyPagesWithEntryFirstThenNaturalFolderAndFilenameOrder() throws {
        let root = workspace.appendingPathComponent("extracted")
        let fixtures = [
            "docs10/end.HTML": "<title>End</title>", "docs2/chapter10.md": "# Chapter ten",
            "docs2/chapter2.MARKDOWN": "# Chapter two", "front.htm": "<title>Front</title>",
            "index.html": "<title>Home</title>", "assets/photo.png": "image",
            "assets/app.js": "code", "plain.txt": "text", "__MACOSX/hidden.html": "metadata",
            ".private/secret.md": "# Hidden", "visible/.hidden.html": "hidden"
        ]
        for (path, content) in fixtures { try write(content, at: root.appendingPathComponent(path)) }
        let catalog = PackagePageCatalog(rootURL: root, entryURL: root.appendingPathComponent("index.html"))
        let pages = try catalog.load()
        XCTAssertEqual(pages.map(\.relativePath), [
            "index.html", "front.htm", "docs2/chapter2.MARKDOWN", "docs2/chapter10.md", "docs10/end.HTML"
        ])
        XCTAssertEqual(pages.map(\.isEntry), [true, false, false, false, false])
        XCTAssertEqual(pages[2].folderPath, "docs2")
        XCTAssertEqual(pages[2].documentType, .markdown)
        XCTAssertEqual(try catalog.load(), pages, "Ordering must not depend on filesystem enumeration order")
    }

    func testHTMLTitleIsPlainDecodedBoundedTextAndMarkdownUsesRealFirstHeading() throws {
        let root = workspace.appendingPathComponent("extracted")
        try write("<!-- <title>Wrong</title> --><title>  Notes &amp; Caf&eacute; &#x65E5; &copy; <b>2026</b>\n *literal* </title>",
                  at: root.appendingPathComponent("index.html"))
        try write("\u{FEFF}```md\n# Wrong\n```\n\n# **Research** &amp; [notes](https://example.com)\n", at: root.appendingPathComponent("notes.md"))
        try write("Heading with `code` and <b>formatted text</b>\n====\n", at: root.appendingPathComponent("setext.md"))
        try write("No heading", at: root.appendingPathComponent("fallback.md"))
        try write("<title>  </title>", at: root.appendingPathComponent("empty.html"))
        let catalog = PackagePageCatalog(rootURL: root, entryURL: root.appendingPathComponent("index.html"))
        XCTAssertEqual(catalog.page(relativePath: "index.html")?.title, "Notes & Café 日 © 2026 *literal*")
        XCTAssertEqual(catalog.page(relativePath: "notes.md")?.title, "Research & notes")
        XCTAssertEqual(catalog.page(relativePath: "setext.md")?.title, "Heading with code and formatted text")
        XCTAssertEqual(catalog.page(relativePath: "fallback.md")?.title, "fallback")
        XCTAssertEqual(catalog.page(relativePath: "empty.html")?.title, "empty")
    }

    func testTitleReadIsBoundedAndSupportsUTF16AndUTF8BOM() throws {
        let root = workspace.appendingPathComponent("extracted")
        try write(String(repeating: " ", count: 65_536) + "<title>Too late</title>", at: root.appendingPathComponent("large.html"))
        try write("<title>" + String(repeating: "界", count: 500) + "</title>", at: root.appendingPathComponent("long.html"))
        try write("\u{FEFF}# 日本語のページ", at: root.appendingPathComponent("bom.md"))
        let utf16 = root.appendingPathComponent("utf16.htm")
        try XCTUnwrap("<title>中文页面</title>".data(using: .utf16)).write(to: utf16)
        let catalog = PackagePageCatalog(rootURL: root, entryURL: root.appendingPathComponent("large.html"))
        XCTAssertEqual(catalog.page(relativePath: "large.html")?.title, "large")
        XCTAssertEqual(catalog.page(relativePath: "long.html")?.title.count, 160)
        XCTAssertEqual(catalog.page(relativePath: "bom.md")?.title, "日本語のページ")
        XCTAssertEqual(catalog.page(relativePath: "utf16.htm")?.title, "中文页面")
    }

    func testRelativeLinksKeepQueryAndAnchorButCannotEscapeTheExtractedRoot() throws {
        let root = workspace.appendingPathComponent("extracted")
        let home = root.appendingPathComponent("index.html")
        try write("<title>Home</title>", at: home)
        let detail = root.appendingPathComponent("reports/detail one.html")
        try write("<title>Detail</title>", at: detail)
        try write("outside", at: workspace.appendingPathComponent("outside.html"))
        try write("sibling", at: workspace.appendingPathComponent("extracted-other/page.html"))
        let catalog = PackagePageCatalog(rootURL: root, entryURL: home)
        let requested = try XCTUnwrap(URL(string: "../index.html?view=compact#summary", relativeTo: detail)).absoluteURL
        let validated = try XCTUnwrap(catalog.validatedNavigationURL(requested))
        XCTAssertEqual(catalog.resolve(url: requested)?.relativePath, "index.html")
        XCTAssertEqual(validated.path, home.resolvingSymlinksInPath().path)
        XCTAssertEqual(validated.query, "view=compact")
        XCTAssertEqual(validated.fragment, "summary")
        XCTAssertEqual(catalog.page(relativePath: "reports/detail one.html")?.fileURL.lastPathComponent, "detail one.html")
        for url in [
            URL(string: "../../outside.html", relativeTo: detail)!.absoluteURL,
            workspace.appendingPathComponent("extracted-other/page.html"),
            URL(string: "https://example.com/index.html")!,
            URL(string: "file://remotehost" + home.path)!,
            URL(string: "javascript:alert(1)")!
        ] {
            XCTAssertNil(catalog.resolve(url: url), url.absoluteString)
            XCTAssertNil(catalog.validatedNavigationURL(url), url.absoluteString)
        }
        for path in ["../outside.html", "/index.html", "reports/../index.html", "reports\\detail.html", "reports//detail.html", ".private/secret.md", "__MACOSX/index.html"] {
            XCTAssertNil(catalog.page(relativePath: path), path)
        }
    }

    func testCatalogAndDirectResolutionRejectFileAndDirectorySymlinks() throws {
        let root = workspace.appendingPathComponent("extracted")
        try write("Home", at: root.appendingPathComponent("index.html"))
        try write("Inside", at: root.appendingPathComponent("pages/inside.md"))
        let outside = workspace.appendingPathComponent("outside")
        try write("Outside", at: outside.appendingPathComponent("secret.html"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias.html"), withDestinationURL: root.appendingPathComponent("index.html"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("outside"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("inside"), withDestinationURL: root.appendingPathComponent("pages"))
        let catalog = PackagePageCatalog(rootURL: root, entryURL: root.appendingPathComponent("index.html"))
        XCTAssertEqual(try catalog.load().map(\.relativePath), ["index.html", "pages/inside.md"])
        for path in ["alias.html", "outside/secret.html", "inside/inside.md"] {
            XCTAssertNil(catalog.page(relativePath: path), path)
            XCTAssertNil(catalog.relativePath(for: root.appendingPathComponent(path)), path)
        }
    }

    func testLegacyMetadataWithoutPackageStateDecodesAndEntryUsesLegacyPosition() throws {
        let store = makeStore()
        var original = try importPackage(store: store)
        original.readingPosition = ReadingPosition(anchorID: "overview", progress: 0.6)
        try store.save(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "savedPackagePageRelativePath")
        object.removeValue(forKey: "packageReadingPositions")
        let decoded = try JSONDecoder().decode(PreviewDocument.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.savedPackagePageRelativePath)
        XCTAssertNil(decoded.packageReadingPositions)
        XCTAssertEqual(store.packageReadingPosition(forPage: "index.html", in: decoded), original.readingPosition)
        XCTAssertNil(store.packageReadingPosition(forPage: "chapters/detail.md", in: decoded))
    }

    func testPageSelectionAndIndependentPositionsSurviveReloadAndMergeLatestMetadata() throws {
        let store = makeStore()
        let original = try importPackage(store: store)
        let homePosition = ReadingPosition(anchorID: "overview", progress: 0.25)
        let detailPosition = ReadingPosition(anchorID: "markdown-block-2@0.5", progress: 0.7)
        try store.updatePackageReadingState(pageRelativePath: "index.html", position: homePosition, for: original)
        try store.updatePackageReadingState(pageRelativePath: "chapters/detail.md", position: detailPosition, for: original)
        _ = try store.rename(original, to: "My report")
        _ = try store.setPinned(true, for: original)
        _ = try store.updatePreferredPreviewMode(.safePreview, for: original)
        try store.updatePackageReadingState(pageRelativePath: "index.html", position: nil, for: original)
        let reopened = makeStore()
        let saved = try XCTUnwrap(reopened.loadDocuments().first)
        XCTAssertEqual(reopened.savedPackagePageRelativePath(for: original), "index.html")
        XCTAssertEqual(reopened.packageReadingPosition(forPage: "index.html", in: original), homePosition)
        XCTAssertEqual(reopened.packageReadingPosition(forPage: "chapters/detail.md", in: original), detailPosition)
        XCTAssertEqual(saved.entryFileRelativePath, original.entryFileRelativePath)
        XCTAssertEqual(saved.originalFileRelativePath, original.originalFileRelativePath)
        XCTAssertEqual(saved.entryDocumentType, .html)
        XCTAssertEqual(saved.displayName, "My report")
        XCTAssertTrue(saved.isPinned)
        XCTAssertEqual(saved.preferredPreviewMode, .safePreview)
    }

    func testInvalidOrMissingPagesCannotBeSavedAndProgressIsNormalized() throws {
        let store = makeStore()
        let original = try importPackage(store: store)
        var position = ReadingPosition(progress: 0)
        position.progress = .infinity
        try store.updatePackageReadingState(pageRelativePath: "chapters/detail.md", position: position, for: original)
        XCTAssertEqual(store.packageReadingPosition(forPage: "chapters/detail.md", in: original)?.progress, 0)
        for path in ["../outside.html", "missing.md", "assets/style.css", "https://example.com/page.html"] {
            try store.updatePackageReadingState(pageRelativePath: path, position: ReadingPosition(progress: 1), for: original)
        }
        XCTAssertEqual(store.savedPackagePageRelativePath(for: original), "chapters/detail.md")
        XCTAssertEqual(try store.loadDocuments().first?.packageReadingPositions?.count, 1)
        try FileManager.default.removeItem(at: store.readAccessRootURL(for: original).appendingPathComponent("chapters/detail.md"))
        XCTAssertNil(store.savedPackagePageRelativePath(for: original))
        XCTAssertNil(store.packageReadingPosition(forPage: "chapters/detail.md", in: original))
    }

    func testDuplicateReplacementClearsPackageStateAndOldPreviewCannotRestoreIt() throws {
        let store = makeStore()
        let original = try importPackage(store: store)
        try store.updatePackageReadingState(pageRelativePath: "chapters/detail.md", position: ReadingPosition(progress: 0.8), for: original)
        let source = workspace.appendingPathComponent("replacement/report.zip")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makeArchive(at: source, files: ["index.html": Data("<title>New home</title>".utf8)])
        let importer = DocumentImportService(store: store)
        let prepared = try importer.prepareImport(from: source, source: .fileImporter)
        let updated = try importer.resolve(prepared, as: .updateExisting)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertNil(updated.savedPackagePageRelativePath)
        XCTAssertNil(updated.packageReadingPositions)
        try store.updatePackageReadingState(pageRelativePath: "index.html", position: ReadingPosition(progress: 0.9), for: original)
        XCTAssertNil(try store.loadDocuments().first?.savedPackagePageRelativePath)
        XCTAssertNil(try store.loadDocuments().first?.packageReadingPositions)
        XCTAssertEqual(PackagePageCatalog(rootURL: store.readAccessRootURL(for: updated), entryURL: store.entryFileURL(for: updated)).page(relativePath: "index.html")?.title, "New home")
    }

    func testIdenticalZIPReplacementAlsoResetsPackagePathsAndDeletedPackageIsNotRecreated() throws {
        let store = makeStore()
        let original = try importPackage(store: store)
        try store.updatePackageReadingState(pageRelativePath: "chapters/detail.md", position: ReadingPosition(progress: 0.8), for: original)
        let importer = DocumentImportService(store: store)
        let prepared = try importer.prepareImport(from: store.originalFileURL(for: original), source: .fileImporter)
        XCTAssertTrue(try XCTUnwrap(prepared.duplicate?.hasIdenticalContents))
        let updated = try importer.resolve(prepared, as: .updateExisting)
        XCTAssertNil(updated.savedPackagePageRelativePath)
        XCTAssertNil(updated.packageReadingPositions)
        try store.delete(updated)
        try store.updatePackageReadingState(pageRelativePath: "index.html", position: ReadingPosition(progress: 1), for: updated)
        XCTAssertTrue(try store.loadDocuments().isEmpty)
    }

    @MainActor
    func testSessionBackHistoryRetainsPageQueriesAndAnchors() throws {
        let home = navigationPage("index.html", title: "Home", isEntry: true)
        let detail = navigationPage("chapters/detail.html", title: "Detail")
        let notes = navigationPage("appendix/notes.md", title: "Notes")
        let navigation = PackageNavigationState(pages: [home, detail, notes], selected: home)
        XCTAssertFalse(navigation.canGoBack)
        XCTAssertFalse(navigation.goBack())
        XCTAssertFalse(navigation.select(home), "Selecting the current location should not create duplicate history")
        let homeAnchor = try XCTUnwrap(URL(string: home.fileURL.absoluteString + "#overview"))
        navigation.didFinish(url: homeAnchor)
        XCTAssertFalse(navigation.canGoBack, "A same-page anchor is not a new package page")
        let detailURL = try XCTUnwrap(URL(string: detail.fileURL.absoluteString + "?view=compact#findings"))
        XCTAssertTrue(navigation.select(detail, url: detailURL))
        XCTAssertTrue(navigation.select(notes))
        XCTAssertTrue(navigation.goBack())
        XCTAssertEqual(navigation.current.page, detail)
        XCTAssertEqual(navigation.current.url, detailURL)
        XCTAssertTrue(navigation.goBack())
        XCTAssertEqual(navigation.current.page, home)
        XCTAssertEqual(navigation.current.url, homeAnchor)
        XCTAssertFalse(navigation.canGoBack)
    }

    @MainActor
    func testLateFinishFromPreviousPageCannotChangeTheCurrentLocation() throws {
        let home = navigationPage("index.html", title: "Home", isEntry: true)
        let detail = navigationPage("chapters/detail.html", title: "Detail")
        let navigation = PackageNavigationState(pages: [home, detail], selected: home)
        navigation.select(detail)
        navigation.didFinish(url: try XCTUnwrap(URL(string: home.fileURL.absoluteString + "#late")))
        navigation.didFinish(url: try XCTUnwrap(URL(string: "https://example.com/chapters/detail.html")))
        XCTAssertEqual(navigation.current.page, detail)
        XCTAssertEqual(navigation.current.url, detail.fileURL)
        XCTAssertEqual(navigation.history.count, 1)
    }

    @MainActor
    func testPackageSessionHistoryIsBoundedWithoutLosingMostRecentBackDestination() {
        let home = navigationPage("index.html", title: "Home", isEntry: true)
        let detail = navigationPage("chapters/detail.html", title: "Detail")
        let navigation = PackageNavigationState(pages: [home, detail], selected: home)
        for index in 0..<120 { navigation.select(index.isMultiple(of: 2) ? detail : home) }
        XCTAssertEqual(navigation.history.count, 100)
        XCTAssertEqual(navigation.current.page, home)
        XCTAssertTrue(navigation.goBack())
        XCTAssertEqual(navigation.current.page, detail)
        for _ in 0..<99 { XCTAssertTrue(navigation.goBack()) }
        XCTAssertFalse(navigation.goBack())
        XCTAssertFalse(navigation.canGoBack)
    }

    func testMarkdownAnchorsResolveUnicodePunctuationAndPercentEncodingToStableIDs() {
        let headings = [
            DocumentHeading(id: "markdown-block-0", title: "Hello, World!", level: 1),
            DocumentHeading(id: "markdown-block-2", title: "中文：方法与结果", level: 2),
            DocumentHeading(id: "markdown-block-4", title: "日本語の手順（確認）", level: 2),
            DocumentHeading(id: "markdown-block-6", title: "Café & notes", level: 2),
            DocumentHeading(id: "markdown-block-8", title: "API_v2 - Code", level: 2)
        ]
        XCTAssertEqual(PackageMarkdownAnchor.headingID(for: "hello-world", headings: headings), "markdown-block-0")
        XCTAssertEqual(PackageMarkdownAnchor.headingID(for: "中文方法与结果", headings: headings), "markdown-block-2")
        XCTAssertEqual(PackageMarkdownAnchor.headingID(for: "%E4%B8%AD%E6%96%87%E6%96%B9%E6%B3%95%E4%B8%8E%E7%BB%93%E6%9E%9C", headings: headings), "markdown-block-2")
        XCTAssertEqual(PackageMarkdownAnchor.headingID(for: "日本語の手順確認", headings: headings), "markdown-block-4")
        XCTAssertEqual(PackageMarkdownAnchor.headingID(for: "caf%C3%A9--notes", headings: headings), "markdown-block-6")
        XCTAssertEqual(PackageMarkdownAnchor.headingID(for: "cafe\u{301}--notes", headings: headings), "markdown-block-6")
        XCTAssertEqual(PackageMarkdownAnchor.headingID(for: "api_v2---code", headings: headings), "markdown-block-8")
        XCTAssertEqual(PackageMarkdownAnchor.headingID(for: "markdown-block-4", headings: headings), "markdown-block-4")
        XCTAssertNil(PackageMarkdownAnchor.headingID(for: "missing", headings: headings))
        XCTAssertNil(PackageMarkdownAnchor.headingID(for: "", headings: headings))
    }

    func testRepeatedMarkdownHeadingSlugsUseUniqueSuffixesIncludingExistingNumberedTitles() {
        let headings = [
            DocumentHeading(id: "first", title: "Details", level: 1),
            DocumentHeading(id: "numbered", title: "Details-1", level: 2),
            DocumentHeading(id: "second", title: "Details", level: 2),
            DocumentHeading(id: "third", title: "Details", level: 2)
        ]
        XCTAssertEqual(PackageMarkdownAnchor.headingID(for: "details", headings: headings), "first")
        XCTAssertEqual(PackageMarkdownAnchor.headingID(for: "details-1", headings: headings), "numbered")
        XCTAssertEqual(PackageMarkdownAnchor.headingID(for: "details-2", headings: headings), "second")
        XCTAssertEqual(PackageMarkdownAnchor.headingID(for: "details-3", headings: headings), "third")
    }

    private func makeStore() -> DocumentLibraryStore {
        DocumentLibraryStore(rootURL: workspace.appendingPathComponent("library"))
    }

    private func navigationPage(_ path: String, title: String, isEntry: Bool = false) -> PackagePage {
        PackagePage(relativePath: path, title: title, fileURL: workspace.appendingPathComponent(path),
                    documentType: path.hasSuffix(".md") ? .markdown : .html, isEntry: isEntry)
    }

    private func write(_ text: String, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func importPackage(store: DocumentLibraryStore) throws -> PreviewDocument {
        let source = workspace.appendingPathComponent(UUID().uuidString).appendingPathComponent("report.zip")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makeArchive(at: source, files: [
            "index.html": Data("<title>Home</title><h1>Overview</h1>".utf8),
            "chapters/detail.md": Data("# Details\n\nLonger content".utf8),
            "assets/style.css": Data("h1 { color: blue; }".utf8)
        ])
        return try DocumentImportService(store: store).importDocument(from: source, source: .fileImporter)
    }
}
