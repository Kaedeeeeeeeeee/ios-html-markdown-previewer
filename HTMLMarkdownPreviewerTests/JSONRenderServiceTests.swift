import Foundation
import XCTest
@testable import HTMLMarkdownPreviewer

final class JSONRenderServiceTests: XCTestCase {
    func testPasteDetectionUsesStrictJSONNumbersAndOnlyAutomaticContainers() {
        for source in [#"{"value":1e400}"#, "[9007199254740993123456789]", " \r\n {}\t ", "\u{FEFF}[true]"] {
            XCTAssertTrue(JSONRenderService.isValidContainer(source), source)
        }
        for source in ["", "1e400", "true", #""text""#, "null", "[1,]", #"{"value":01}"#,
                       "{/*comment*/}", "[1] trailing", "{]", "[{]"] {
            XCTAssertFalse(JSONRenderService.isValidContainer(source), source)
        }
    }

    func testPasteDetectionKeepsBoundedContainersInJSONWhenStructureIsTooComplex() {
        let deep = String(repeating: "[", count: JSONRenderService.maximumDepth + 1)
            + "0" + String(repeating: "]", count: JSONRenderService.maximumDepth + 1)
        XCTAssertTrue(JSONRenderService.isValidContainer(deep))
        let many = "[" + Array(repeating: "0", count: JSONRenderService.maximumNodes).joined(separator: ",") + "]"
        XCTAssertTrue(JSONRenderService.isValidContainer(many))
        let longPath = "{\"" + String(repeating: "x", count: 33_000) + "\":0}"
        XCTAssertTrue(JSONRenderService.isValidContainer(longPath))
        let tooLarge = "[\"" + String(repeating: "x", count: JSONRenderService.maximumUTF8Bytes) + "\"]"
        XCTAssertFalse(JSONRenderService.isValidContainer(tooLarge))
    }

    func testTypedValuesPreserveOrderAndExactNumberLexemes() throws {
        let source = #"{"z":9007199254740993123456789,"a":-0.0012300e+400,"enabled":true,"off":false,"none":null,"quoted":"false"}"#
        let result = JSONRenderService().render(text: source)
        XCTAssertNil(result.issue)
        let rows = try XCTUnwrap(result.sheets.first?.rows)
        XCTAssertEqual(rows.map(\.label), ["$", "z", "a", "enabled", "off", "none", "quoted"])
        XCTAssertEqual(rows.map(\.kind), [.object, .number, .number, .boolean, .boolean, .null, .string])
        XCTAssertEqual(rows[1].value, "9007199254740993123456789")
        XCTAssertEqual(rows[2].value, "-0.0012300e+400")
        XCTAssertEqual(result.source, source)
        XCTAssertEqual(result.copyValue(for: rows[0]), source)
    }

    func testUnicodeAndEveryJSONEscapeDecodeWithoutChangingSource() throws {
        let source = #"{"text":"\"\\\/\b\f\n\r\t\u4e2d\u6587\uD83D\uDE42 café 🌏","\u006b":"value"}"#
        let result = JSONRenderService().render(text: source)
        XCTAssertNil(result.issue)
        let rows = try XCTUnwrap(result.sheets.first?.rows)
        XCTAssertEqual(rows[1].value, "\"\\/\u{08}\u{0C}\n\r\t中文🙂 café 🌏")
        XCTAssertEqual(result.copyValue(for: rows[1]), rows[1].value)
        XCTAssertEqual(rows[2].path, "$.k")
        XCTAssertEqual(result.source, source)
        XCTAssertEqual(result.lines.map(\.text).joined(separator: "\n"), source)
        XCTAssertTrue(result.lines[0].tokens.contains { $0.style == "attr" })
        XCTAssertTrue(result.lines[0].tokens.contains { $0.style == "string" })
    }

    func testRootScalarsAndEmptyCollectionsAreValid() throws {
        let examples: [(String, YAMLRow.Kind, String)] = [
            (#""hello""#, .string, "hello"), ("-0", .number, "-0"), ("true", .boolean, "true"),
            ("false", .boolean, "false"), ("null", .null, "null"), ("{}", .object, ""), ("[]", .array, "")
        ]
        for (source, kind, expected) in examples {
            let result = JSONRenderService().render(text: source)
            XCTAssertNil(result.issue, source)
            let rows = try XCTUnwrap(result.sheets.first?.rows)
            XCTAssertEqual(rows.count, 1, source)
            XCTAssertEqual(rows[0].kind, kind, source)
            XCTAssertEqual(rows[0].value, expected, source)
            XCTAssertEqual(rows[0].path, "$", source)
            XCTAssertEqual(rows[0].id, "json-0-0", source)
        }
    }

    func testNestedPathsRepeatedKeysAndCollectionCopyRemainUnambiguous() throws {
        let source = #"{"a.b":[{"sp ace":"first","sp ace":"second","quote\"key":1}],"":{},"$":5}"#
        let result = JSONRenderService().render(text: source)
        let rows = try XCTUnwrap(result.sheets.first?.rows)
        let repeated = rows.filter { $0.path == #"$["a.b"][0]["sp ace"]"# }
        XCTAssertEqual(repeated.map(\.value), ["first", "second"])
        XCTAssertEqual(Set(repeated.map(\.id)).count, 2)
        XCTAssertTrue(rows.contains { $0.path == #"$["a.b"][0]["quote\"key"]"# })
        XCTAssertTrue(rows.contains { $0.path == #"$[""]"# && $0.kind == .object })
        let array = try XCTUnwrap(rows.first { $0.kind == .array })
        let copied = try XCTUnwrap(result.copyValue(for: array))
        XCTAssertEqual(copied, #"[{"sp ace":"first","sp ace":"second","quote\"key":1}]"#)
        XCTAssertNil(JSONRenderService().render(text: copied).issue)
        XCTAssertEqual(array.parents, ["json-0-0"])
    }

    func testStrictGrammarRejectsJSONCAndMalformedTokens() {
        let invalid = ["", " ", "{\"a\":1,}", "[1,]", "// comment\n{}", "{/*comment*/}",
                       "{a:1}", "{'a':1}", "[undefined]", "NaN", "Infinity", "+1", ".1", "01", "-01",
                       "1.", "1e", "1e+", "1e-", "--1", "0x10", "true false", "null{}", "[1 2]",
                       "{\"a\" 1}", "[True]", "\u{00A0}null", "\"line\nbreak\"",
                       #""\x20""#, #""\uD800""#, #""\uDC00""#, #""\uD800\u0041""#, #""\uZZZZ""#]
        for source in invalid {
            let result = JSONRenderService().render(text: source)
            XCTAssertEqual(result.issue?.code, "syntax", source)
            XCTAssertTrue(result.sheets.isEmpty, source)
            XCTAssertEqual(result.source, source)
            XCTAssertFalse(result.lines.isEmpty, source)
        }
    }

    func testSourcePositionsCountUnicodeScalarsAndCRLFOnce() throws {
        let source = "{\r\n  \"a\": [\r\n    1,\r\n    true\r\n  ]\r\n}"
        let result = JSONRenderService().render(text: source)
        let rows = try XCTUnwrap(result.sheets.first?.rows)
        let bool = try XCTUnwrap(rows.first { $0.kind == .boolean })
        XCTAssertEqual(bool.line, 4)
        XCTAssertEqual(bool.column, 5)
        XCTAssertEqual(result.lines[3].id, "json-line-4")
        XCTAssertEqual(result.lines[3].text, "    true")
        let problem = try XCTUnwrap(JSONRenderService().render(text: "[\"中文🙂\", ?]").issue)
        XCTAssertEqual(problem.line, 1)
        XCTAssertEqual(problem.column, 9)
        let error = try XCTUnwrap(JSONRenderService().render(text: "{\r\n  \"a\": 1,\r\n}").issue)
        XCTAssertEqual(error.line, 3)
        XCTAssertEqual(error.column, 1)
    }

    func testDepthBoundaryAndNodeLimitKeepReadableSource() throws {
        let depth = JSONRenderService.maximumDepth
        let valid = String(repeating: "[", count: depth) + "0" + String(repeating: "]", count: depth)
        XCTAssertNil(JSONRenderService().render(text: valid).issue)
        let result = JSONRenderService().render(text: "[" + valid + "]")
        XCTAssertEqual(result.issue?.code, "depthLimit")
        XCTAssertFalse(result.lines.isEmpty)
        XCTAssertTrue(result.sheets.isEmpty)
        let array = "[" + Array(repeating: "0", count: JSONRenderService.maximumNodes).joined(separator: ",") + "]"
        XCTAssertEqual(JSONRenderService().render(text: array).issue?.code, "nodeLimit")
        let longKey = "{\"" + String(repeating: "x", count: 33_000) + "\":1}"
        XCTAssertEqual(JSONRenderService().render(text: longKey).issue?.code, "nodeLimit")
    }

    func testSizeAndSourceExcerptLimitsDoNotAlterOriginalFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = Data(repeating: 32, count: JSONRenderService.maximumUTF8Bytes + 10)
        try bytes.write(to: url)
        let result = try JSONRenderService().render(fileURL: url)
        XCTAssertEqual(result.issue?.code, "sizeLimit")
        XCTAssertTrue(result.isSourceTruncated)
        XCTAssertLessThanOrEqual(result.source.utf8.count, JSONRenderService.maximumSourceCharacters)
        XCTAssertEqual(try Data(contentsOf: url), bytes)

        let source = #"{"value":""# + String(repeating: "x", count: 250_000) + #""}"#
        let excerpt = JSONRenderService().render(text: source)
        XCTAssertNil(excerpt.issue)
        XCTAssertTrue(excerpt.isSourceTruncated)
        XCTAssertEqual(excerpt.source, source)
        XCTAssertLessThanOrEqual(excerpt.lines.map(\.text).joined(separator: "\n").count, JSONRenderService.maximumSourceCharacters)
    }

    func testFileReaderAllowsUTF8BOMAndRejectsInvalidEncoding() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([0xEF, 0xBB, 0xBF] + Array("{\"a\":1}".utf8)).write(to: url)
        XCTAssertNil(try JSONRenderService().render(fileURL: url).issue)
        try Data([0x22, 0xFF, 0x22]).write(to: url)
        let result = try JSONRenderService().render(fileURL: url)
        XCTAssertEqual(result.issue?.code, "encoding")
        XCTAssertTrue(result.sheets.isEmpty)
        XCTAssertFalse(result.lines.isEmpty)
    }

    func testJSONReadingLocationsRoundTripAndStaySeparateFromYAML() {
        for mode in YAMLPreviewMode.allCases {
            let target = mode == .source ? "json-line-14" : "json-0-4"
            let position = YAMLReadingLocation(documentIndex: 0, mode: mode, target: target, format: .json).position
            XCTAssertEqual(YAMLReadingLocation(position, format: .json)?.target, target)
            XCTAssertNil(YAMLReadingLocation(position))
        }
        let yaml = YAMLReadingLocation(documentIndex: 0, mode: .source, target: "yaml-line-1").position
        XCTAssertNil(YAMLReadingLocation(yaml, format: .json))
    }
}
