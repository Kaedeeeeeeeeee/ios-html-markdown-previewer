import Foundation
import XCTest
@testable import HTMLMarkdownPreviewer

final class YAMLRenderServiceTests: XCTestCase {
    func testBundledParserRunsInJavaScriptCoreAndKeepsTypedSourceLines() throws {
        let source = "# 保留注释\r\napp:\r\n  port: 8080\r\n  mode: on\r\n  enabled: true\r\n  id: 9007199254740993\r\n  title: \"false\"\r\n  notes: |\r\n    第一行\r\n    第二行\r\n"
        let result = YAMLRenderService().render(text: source)
        XCTAssertNil(result.issue)
        let sheet = try XCTUnwrap(result.sheets.first)
        XCTAssertNil(sheet.issue)
        XCTAssertEqual(result.source, source)
        XCTAssertEqual(sheet.rows.first { $0.path == "app.port" }?.value, "8080")
        XCTAssertEqual(sheet.rows.first { $0.path == "app.port" }?.line, 3)
        XCTAssertEqual(sheet.rows.first { $0.path == "app.mode" }?.kind, .string)
        XCTAssertEqual(sheet.rows.first { $0.path == "app.enabled" }?.kind, .boolean)
        XCTAssertEqual(sheet.rows.first { $0.path == "app.id" }?.value, "9007199254740993")
        XCTAssertEqual(sheet.rows.first { $0.path == "app.title" }?.kind, .string)
        XCTAssertEqual(sheet.rows.first { $0.path == "app.notes" }?.value, "第一行\n第二行\n")
        XCTAssertEqual(result.lines.map(\.text).joined(separator: "\n"), source.replacingOccurrences(of: "\r\n", with: "\n"))
        XCTAssertTrue(result.lines[0].tokens.contains { $0.style.contains("comment") })
        XCTAssertTrue(result.lines[2].tokens.contains { $0.style.contains("attr") })
        XCTAssertFalse(result.isSourceTruncated)
    }

    func testSourceTextIsNotExecutedAndSpecialCharactersSurviveHighlighting() throws {
        let source = "title: '<script>globalThis.PWNED = true</script>'\nvalue: \"& < > \\\" 中文 🙂\"\n"
        let result = YAMLRenderService().render(text: source)
        XCTAssertNil(result.issue)
        XCTAssertNil(result.sheets.first?.issue)
        XCTAssertEqual(result.lines.map(\.text).joined(separator: "\n"), source)
        XCTAssertEqual(result.sheets.first?.rows.first { $0.path == "title" }?.value, "<script>globalThis.PWNED = true</script>")
    }

    func testMultiDocumentAndRecursiveAliasesRemainBoundedReferences() throws {
        let result = YAMLRenderService().render(text: "self: &self [*self]\n---\nname: next\n")
        XCTAssertEqual(result.sheets.count, 2)
        XCTAssertNil(result.sheets[0].issue)
        XCTAssertEqual(result.sheets[0].rows.count, 3)
        XCTAssertEqual(result.sheets[0].rows.last?.kind, .alias)
        XCTAssertEqual(result.sheets[0].rows.last?.value, "*self")
        XCTAssertEqual(result.sheets[1].startLine, 2)
        let keyAnchor = YAMLRenderService().render(text: "&name title: Demo\ncopy: *name\n")
        XCTAssertNil(keyAnchor.sheets.first?.issue)
        XCTAssertEqual(keyAnchor.sheets.first?.rows.last?.value, "*name")
        XCTAssertEqual(YAMLRenderService().render(text: "*missing: value\n").sheets.first?.issue?.line, 1)
        XCTAssertEqual(YAMLRenderService().render(text: "copy: *later\nvalue: &later Demo\n").sheets.first?.issue?.line, 1)
    }

    func testSyntaxErrorKeepsSourceAndPointsToTheProblemLine() throws {
        let source = "app:\n  name: Demo\n port: 8080"
        let result = YAMLRenderService().render(text: source)
        let issue = try XCTUnwrap(result.sheets.first?.issue)
        XCTAssertEqual(issue.code, "syntax")
        XCTAssertEqual(issue.line, 3)
        XCTAssertGreaterThanOrEqual(issue.column, 1)
        XCTAssertEqual(result.source, source)
        XCTAssertEqual(result.lines[2].text, " port: 8080")
        XCTAssertNotNil(YAMLRenderService().render(text: "key: 1\nkey: 2").sheets.first?.issue)
        XCTAssertNotNil(YAMLRenderService().render(text: "web: *missing").sheets.first?.issue)
    }

    func testQuotedKeysArrayPathsAndMultilineSearch() throws {
        let result = YAMLRenderService().render(text: "\"a.b\":\n  - name: 测试\n    description: |\n      A quiet morning\n      Keep this note\n")
        let rows = try XCTUnwrap(result.sheets.first?.rows)
        XCTAssertTrue(rows.contains { $0.path == "[\"a.b\"][0].name" && $0.value == "测试" })
        XCTAssertTrue(rows.contains { $0.matches("quiet morning") })
        XCTAssertTrue(rows.contains { $0.matches("DESCRIPTION") })
    }

    func testComplexityLimitsProvideReadableSourceWithoutCrashing() {
        let deep = YAMLRenderService().render(text: String(repeating: "[", count: 100) + "1" + String(repeating: "]", count: 100))
        XCTAssertEqual(deep.issue?.code, "depthLimit")
        XCTAssertFalse(deep.lines.isEmpty)
        let many = YAMLRenderService().render(text: String(repeating: "- 1\n", count: 13_000))
        XCTAssertEqual(many.issue?.code, "nodeLimit")
        let documents = YAMLRenderService().render(text: String(repeating: "---\na: 1\n", count: 101))
        XCTAssertEqual(documents.issue?.code, "documentLimit")
        let large = YAMLRenderService().render(text: String(repeating: "界", count: 700_000))
        XCTAssertEqual(large.issue?.code, "sizeLimit")
        XCTAssertTrue(large.isSourceTruncated)
        XCTAssertLessThanOrEqual(large.source.count, YAMLRenderService.maximumSourceCharacters)
    }

    func testImportFileAndLibraryFilteringPreserveOriginalYMLBytes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("Config.YML")
        let original = Data("# comment\r\napp: Demo\r\n".utf8)
        try original.write(to: input)
        let store = DocumentLibraryStore(rootURL: root.appendingPathComponent("library"))
        let document = try DocumentImportService(store: store).importDocument(from: input, source: .fileImporter)
        XCTAssertEqual(document.type, .yaml)
        XCTAssertEqual(try Data(contentsOf: store.originalFileURL(for: document)), original)
        XCTAssertEqual(DocumentLibraryFilter.yaml.documents(in: [document], matching: "config"), [document])
        XCTAssertEqual(DocumentLibraryFilter.markdown.documents(in: [document], matching: ""), [])
        XCTAssertNil(try YAMLRenderService().render(fileURL: store.entryFileURL(for: document)).issue)

        let large = root.appendingPathComponent("large.yaml")
        try Data(repeating: 32, count: 2_100_000).write(to: large)
        let excerpt = try YAMLRenderService().render(fileURL: large)
        XCTAssertEqual(excerpt.issue?.code, "sizeLimit")
        XCTAssertTrue(excerpt.isSourceTruncated)
        XCTAssertEqual(try large.resourceValues(forKeys: [.fileSizeKey]).fileSize, 2_100_000)
    }

    func testReadingLocationsRoundTripAndRejectOtherReaderAnchors() {
        for mode in YAMLPreviewMode.allCases {
            let target = mode == .source ? "yaml-line-14" : "yaml-1-4"
            let position = YAMLReadingLocation(documentIndex: 1, mode: mode, target: target).position
            let decoded = YAMLReadingLocation(position)
            XCTAssertEqual(decoded?.documentIndex, 1)
            XCTAssertEqual(decoded?.mode, mode)
            XCTAssertEqual(decoded?.target, target)
        }
        XCTAssertNil(YAMLReadingLocation(ReadingPosition(anchorID: "markdown-block-4", progress: 0.5)))
        XCTAssertNil(YAMLReadingLocation(ReadingPosition(anchorID: "yaml:1:source:yaml-1-4", progress: 0)))
    }

    func testLargeValidConfigurationsRemainReadableNearLimits() throws {
        let fixtures = [
            ("many fields", (0..<11_500).map { "field_\($0): value_\($0)" }.joined(separator: "\n"), 11_501),
            ("near two MB", (0..<380).map { "field_\($0): \(String(repeating: "x", count: 5_000))" }.joined(separator: "\n"), 381)
        ]
        var timings = [[String: Any]]()
        for (name, source, expectedRows) in fixtures {
            let start = Date()
            let result = YAMLRenderService().render(text: source)
            let seconds = Date().timeIntervalSince(start)
            XCTAssertNil(result.issue, name)
            let sheet = try XCTUnwrap(result.sheets.first)
            XCTAssertNil(sheet.issue, name)
            XCTAssertEqual(sheet.rows.count, expectedRows, name)
            XCTAssertEqual(result.source, source, name)
            XCTAssertFalse(result.lines.isEmpty, name)
            XCTAssertTrue(result.isSourceTruncated, name)
            XCTAssertLessThanOrEqual(result.lines.map(\.text).joined(separator: "\n").count,
                                     YAMLRenderService.maximumSourceCharacters, name)
            timings.append(["fixture": name, "utf8Bytes": source.utf8.count,
                            "rows": sheet.rows.count, "elapsedSeconds": seconds])
        }
        let data = try JSONSerialization.data(withJSONObject: timings, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "YAML large configuration timings"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
