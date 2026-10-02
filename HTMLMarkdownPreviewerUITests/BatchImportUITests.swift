import XCTest

/// The queue is injected after staging; all review, failure, summary, and
/// navigation behavior uses the production import path. Existing files survive.
@MainActor
final class BatchImportUITests: XCTestCase {
    func testBatchContinuesThroughFailureAndDuplicateChoicesThenReturnsToLibrary() throws {
        try withFixture { app, prefix in
            try require(app.staticTexts.matching(identifier: prefix + "Update.md").firstMatch.waitForExistence(timeout: 15), "First duplicate should be reviewed after the failed file")
            XCTAssertFalse(app.alerts.firstMatch.exists, "Batch failures belong in the final summary")
            XCTAssertFalse(app.buttons["document-title-button"].exists, "Batch successes should not navigate to individual documents")
            app.buttons["duplicate-update-button"].tap()

            try require(app.staticTexts.matching(identifier: prefix + "Keep.md").firstMatch.waitForExistence(timeout: 10), "Review must continue to the next duplicate")
            app.buttons["duplicate-keep-both-button"].tap()

            try require(app.staticTexts.matching(identifier: prefix + "Skip.md").firstMatch.waitForExistence(timeout: 10), "Third duplicate should be reviewed")
            let skip = app.buttons["duplicate-cancel-button"]
            XCTAssertEqual(skip.label, "Skip This File")
            skip.tap()

            try require(app.buttons["batch-import-done"].waitForExistence(timeout: 10), "Skipping one file should finish the remaining batch")
            assertCount("batch-import-imported-count", equals: "4", app: app)
            assertCount("batch-import-skipped-count", equals: "1", app: app)
            assertCount("batch-import-failed-count", equals: "1", app: app)
            XCTAssertTrue(element("batch-import-failure-" + prefix + "Unsupported.bin", app: app).exists)
            attachScreenshot("Batch import results with a failure and a skipped duplicate", app: app)
            app.buttons["batch-import-done"].tap()
            try require(app.buttons["open-file-button"].waitForExistence(timeout: 10), "Summary should return to the library")
            XCTAssertFalse(app.buttons["document-title-button"].exists)

            try search(prefix + "Update", app: app)
            XCTAssertEqual(rows(prefix + "Update.md", app: app).count, 1)
            rows(prefix + "Update.md", app: app).firstMatch.tap()
            try require(app.staticTexts["Batch Update replacement"].waitForExistence(timeout: 10), "Update should replace saved contents")
            try navigateHome(app)

            try search(prefix + "Keep", app: app)
            XCTAssertEqual(rows(prefix + "Keep.md", app: app).count, 2, "Keep Both should preserve two copies")
            try search(prefix + "Skip", app: app)
            XCTAssertEqual(rows(prefix + "Skip.md", app: app).count, 1)
            rows(prefix + "Skip.md", app: app).firstMatch.tap()
            try require(app.staticTexts["Batch Skip original"].waitForExistence(timeout: 10), "Skip must preserve the saved original")
            XCTAssertFalse(app.staticTexts["Batch Skip replacement"].exists)
            try navigateHome(app)

            try search(prefix + "Last", app: app)
            try require(rows(prefix + "Last.md", app: app).firstMatch.waitForExistence(timeout: 5), "File after skipped duplicate should still import")
            rows(prefix + "Last.md", app: app).firstMatch.tap()
            try require(app.staticTexts["Batch last file"].waitForExistence(timeout: 10), "Last file must have readable contents")
        }
    }

    func testAllFailedBatchStillPresentsCompleteSummary() throws {
        try withFixture(scenario: "all-failed") { app, prefix in
            try require(app.buttons["batch-import-done"].waitForExistence(timeout: 15), "Even an entirely failed batch should finish")
            assertCount("batch-import-imported-count", equals: "0", app: app)
            assertCount("batch-import-skipped-count", equals: "0", app: app)
            assertCount("batch-import-failed-count", equals: "2", app: app)
            XCTAssertTrue(element("batch-import-failure-" + prefix + "Unsupported.bin", app: app).exists)
            XCTAssertTrue(element("batch-import-failure-" + prefix + "Broken.zip", app: app).exists)
            XCTAssertFalse(app.alerts.firstMatch.exists)
            app.buttons["batch-import-done"].tap()
            try require(app.buttons["open-file-button"].waitForExistence(timeout: 10), "Failed batch should return to a usable library")
        }
    }

    func testSingleSelectionOpensDocumentWithoutBatchSummary() throws {
        try withFixture(scenario: "single") { app, _ in
            try require(app.staticTexts["Batch single preview"].waitForExistence(timeout: 15), "A single selected file should open immediately")
            XCTAssertTrue(app.buttons["document-title-button"].exists)
            XCTAssertFalse(app.buttons["batch-import-done"].exists)
        }
    }

    private var baseArguments: [String] { ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"] }

    private func withFixture(scenario: String? = nil, body: (XCUIApplication, String) throws -> Void) throws {
        continueAfterFailure = false
        let token = UUID().uuidString
        let prefix = "QA-BatchImport-\(token)-"
        let app = XCUIApplication()
        app.launchEnvironment["HTML_PREVIEWER_UI_TESTS"] = "1"
        app.launchArguments = baseArguments + ["--batch-import-fixture=\(token)"]
        if let scenario { app.launchArguments.append("--batch-import-scenario=\(scenario)") }
        app.launch()
        defer {
            app.terminate()
            app.launchArguments = baseArguments + ["--batch-import-cleanup=\(token)"]
            app.launch()
            XCTAssertTrue(app.buttons["open-file-button"].waitForExistence(timeout: 15))
            XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "recent-document-\(prefix)")).firstMatch.exists)
        }
        try body(app, prefix)
    }

    private func assertCount(_ identifier: String, equals count: String, app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let row = element(identifier, app: app)
        XCTAssertTrue(row.exists, file: file, line: line)
        XCTAssertEqual(row.value as? String, count, file: file, line: line)
    }

    private func element(_ identifier: String, app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func rows(_ filename: String, app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(identifier: "recent-document-\(filename)")
    }

    private func search(_ text: String, app: XCUIApplication) throws {
        let field = app.searchFields.firstMatch
        if !field.isHittable { app.swipeDown() }
        try require(field.waitForExistence(timeout: 5), "Library search should be available")
        field.tap()
        if let old = field.value as? String, old != field.placeholderValue, !old.isEmpty {
            // A tap can place the caret inside a long filename. Clear the
            // whole query rather than backspacing only its prefix.
            let clear = field.buttons.matching(NSPredicate(format: "label IN %@", ["Clear text", "Clear Text", "Clear"])).firstMatch
            if clear.exists && clear.isHittable { clear.tap() }
            else { field.typeKey("a", modifierFlags: .command) }
        }
        field.typeText(text)
        let exactQuery = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in field.value as? String == text }, object: nil)
        try require(XCTWaiter.wait(for: [exactQuery], timeout: 5) == .completed, "Library search must contain the exact query")
        if app.keyboards.buttons["Search"].exists { app.keyboards.buttons["Search"].tap() }
    }

    private func navigateHome(_ app: XCUIApplication) throws {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        try require(back.waitForExistence(timeout: 5), "Preview should provide Back")
        back.tap()
        try require(app.buttons["open-file-button"].waitForExistence(timeout: 10), "Back should return to the library")
    }

    private func require(_ condition: Bool, _ message: String) throws {
        guard condition else {
            XCTFail(message)
            throw NSError(domain: "BatchImportUITests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
