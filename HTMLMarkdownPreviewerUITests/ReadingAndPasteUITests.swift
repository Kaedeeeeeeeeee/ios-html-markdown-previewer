import UIKit
import XCTest

@MainActor
final class ReadingAndPasteUITests: XCTestCase {
    func testMarkdownSearchRevealsLongParagraphAndOffscreenTableColumn() {
        let app = launchFresh()
        let paragraph = "needle " + String(repeating: "A longer sentence with wide WWW and narrow iii characters. ", count: 100) + " needle"
        let markdown = """
        # Long text and wide table

        \(paragraph)

        After the long paragraph

        | First | Second | Third | Fourth | Fifth | Sixth | Seventh | Last |
        | --- | --- | --- | --- | --- | --- | --- | --- |
        | ordinary | ordinary | ordinary | ordinary | ordinary | ordinary | ordinary | farcolumn |
        """
        paste(markdown, name: "Long QA", app: app)
        openSearch(app)
        app.textFields["reading-search-field"].typeText("needle")
        waitForLabel("1 of 2", identifier: "reading-match-count", app: app)
        app.buttons["reading-next-match"].tap()
        waitForLabel("2 of 2", identifier: "reading-match-count", app: app)
        XCTAssertTrue(eventuallyHittable(app.staticTexts["After the long paragraph"]))
        screenshot("Second match at the end of one long paragraph", app: app)
        app.buttons["reading-search-close"].tap()
        openSearch(app)
        app.textFields["reading-search-field"].typeText("farcolumn\n")
        waitForLabel("1 of 1", identifier: "reading-match-count", app: app)
        let cell = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "farcolumn")).firstMatch
        XCTAssertTrue(eventuallyHittable(cell))
        screenshot("Search reveals last column of a wide table", app: app)
    }

    func testPastedMarkdownSearchOutlineAndResumeAfterRelaunch() {
        let app = launchFresh()
        let middle = (1...12).map { index in
            "## Section \(index)\n\n" + String(repeating: "Reading notes stay on this device. ", count: 10)
        }.joined(separator: "\n\n")
        paste("# Field notes\n\nAn aurora begins here.\n\n\(middle)\n\n## Final decision\n\nThe aurora ends here.\n\nSave the final decision for tomorrow.", name: "Reading QA", app: app)
        XCTAssertTrue(app.staticTexts["Field notes"].waitForExistence(timeout: 10))
        openSearch(app)
        app.textFields["reading-search-field"].typeText("aurora")
        waitForLabel("1 of 2", identifier: "reading-match-count", app: app)
        app.buttons["reading-next-match"].tap()
        waitForLabel("2 of 2", identifier: "reading-match-count", app: app)
        XCTAssertTrue(eventuallyHittable(app.staticTexts["Final decision"]))
        app.buttons["reading-previous-match"].tap()
        waitForLabel("1 of 2", identifier: "reading-match-count", app: app)
        app.buttons["reading-search-close"].tap()
        openContents(app)
        let finalHeading = app.buttons.matching(NSPredicate(format: "label == %@", "Final decision")).firstMatch
        scrollTo(finalHeading, app: app)
        finalHeading.tap()
        XCTAssertTrue(eventuallyHittable(app.staticTexts["Final decision"]))
        screenshot("Markdown directory jump", app: app)
        app.navigationBars.buttons["HTML Previewer"].tap()
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let recent = app.buttons["recent-document-Reading QA.md"]
        XCTAssertTrue(recent.waitForExistence(timeout: 10))
        recent.tap()
        XCTAssertTrue(eventuallyHittable(app.staticTexts["Final decision"]))
        screenshot("Markdown reading position restored after relaunch", app: app)
    }

    func testPastedHTMLSafeSearchOutlineAndResumeAfterRelaunch() {
        let app = launchFresh()
        let middle = (1...10).map { "<h2>Section \($0)</h2><p>" + String(repeating: "Local report text. ", count: 25) + "</p>" }.joined()
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"><style>body{font:18px -apple-system;padding:20px;line-height:1.6}</style></head><body>
        <h1>Local HTML report</h1><p id="safety">Safe script remains blocked</p><p>First compass match.</p>
        \(middle)<h2>Final destination</h2><p>Last compass match.</p><p>Keep this position.</p>
        <script>document.getElementById('safety').textContent='UNSAFE SCRIPT EXECUTED';</script></body></html>
        """
        paste(html, name: "HTML QA", app: app)
        XCTAssertTrue(app.staticTexts["Local HTML report"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Safe script remains blocked"].exists)
        XCTAssertFalse(app.staticTexts["UNSAFE SCRIPT EXECUTED"].exists)
        openSearch(app)
        app.textFields["reading-search-field"].typeText("compass")
        waitForLabel("1 of 2", identifier: "reading-match-count", app: app)
        app.buttons["reading-next-match"].tap()
        waitForLabel("2 of 2", identifier: "reading-match-count", app: app)
        XCTAssertTrue(eventuallyHittable(app.staticTexts["Final destination"]))
        screenshot("HTML second search result", app: app)
        app.buttons["reading-search-close"].tap()
        openContents(app)
        let finalHeading = app.buttons.matching(NSPredicate(format: "label == %@", "Final destination")).firstMatch
        scrollTo(finalHeading, app: app)
        finalHeading.tap()
        XCTAssertTrue(eventuallyHittable(app.staticTexts["Final destination"]))
        app.navigationBars.buttons["HTML Previewer"].tap()
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["recent-document-HTML QA.html"].waitForExistence(timeout: 10))
        app.buttons["recent-document-HTML QA.html"].tap()
        XCTAssertTrue(eventuallyHittable(app.staticTexts["Final destination"]))
        screenshot("HTML reading position restored after relaunch", app: app)
    }

    func testPasteRejectsEmptyAndURLOnlyWithoutCreatingDocument() {
        let app = launchFresh()
        app.buttons["paste-preview-button"].tap()
        XCTAssertTrue(app.buttons["paste-open-button"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["paste-open-button"].isEnabled)
        setPasteboard("https://example.com/report", app: app)
        XCTAssertTrue(eventuallyEnabled(app.buttons["paste-system-button"]))
        app.buttons["paste-system-button"].tap()
        XCTAssertTrue(eventuallyEnabled(app.buttons["paste-open-button"]))
        app.buttons["paste-open-button"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        screenshot("URL-only paste explanation", app: app)
        app.alerts.buttons["OK"].tap()
        app.buttons["paste-cancel-button"].tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "recent-document-")).firstMatch.exists)
    }

    func testSearchNoResultsAndClosingSearchRestoresNormalReading() {
        let app = launchFresh(sample: "markdown")
        XCTAssertTrue(app.staticTexts["Make room to read"].waitForExistence(timeout: 10))
        openSearch(app)
        app.textFields["reading-search-field"].typeText("zzzznotfoundzzzz")
        waitForLabel("No matches", identifier: "reading-match-count", app: app)
        XCTAssertFalse(app.buttons["reading-next-match"].isEnabled)
        app.buttons["reading-search-close"].tap()
        XCTAssertFalse(app.textFields["reading-search-field"].exists)
        XCTAssertTrue(app.staticTexts["Make room to read"].exists)
    }

    func testNewControlsAreLocalizedInChineseAndJapanese() {
        for (language, locale, pasteTitle, findTitle, contentsTitle) in [
            ("zh-Hans", "zh_CN", "粘贴预览", "文内搜索", "目录"),
            ("zh-Hant", "zh_TW", "貼上預覽", "文內搜尋", "目錄"),
            ("ja", "ja_JP", "貼り付けてプレビュー", "文書内を検索", "目次")
        ] {
            let app = launchFresh(language: language, locale: locale)
            XCTAssertEqual(app.buttons["paste-preview-button"].label, pasteTitle)
            app.buttons["paste-preview-button"].tap()
            XCTAssertTrue(app.textViews["paste-text-editor"].waitForExistence(timeout: 5))
            screenshot("Paste controls \(language)", app: app)
            app.buttons["paste-cancel-button"].tap()
            app.buttons["sample-markdown"].tap()
            XCTAssertTrue(eventuallyEnabled(app.buttons["reading-tools-menu"]))
            app.buttons["reading-tools-menu"].tap()
            XCTAssertTrue(app.buttons[findTitle].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons[contentsTitle].exists)
            app.buttons[contentsTitle].tap()
            screenshot("Reading outline \(language)", app: app)
            app.terminate()
        }
    }

    private func launchFresh(sample: String? = nil, language: String = "en", locale: String = "en_US") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HTML_PREVIEWER_UI_TESTS"] = "1"
        app.launchArguments = ["--screenshot-reset-library", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        if let sample { app.launchArguments.append("--screenshot-sample=\(sample)") }
        app.launch()
        return app
    }

    private func paste(_ text: String, name: String, app: XCUIApplication) {
        XCTAssertTrue(app.buttons["paste-preview-button"].waitForExistence(timeout: 10))
        app.buttons["paste-preview-button"].tap()
        XCTAssertTrue(app.buttons["paste-system-button"].waitForExistence(timeout: 5))
        setPasteboard(text, app: app)
        XCTAssertTrue(eventuallyEnabled(app.buttons["paste-system-button"]))
        app.buttons["paste-system-button"].tap()
        XCTAssertTrue(eventuallyEnabled(app.buttons["paste-open-button"]))
        let nameField = app.textFields["paste-name-field"]
        scrollTo(nameField, app: app)
        nameField.tap()
        nameField.typeText(name)
        app.buttons["paste-open-button"].tap()
    }

    private func openSearch(_ app: XCUIApplication) {
        XCTAssertTrue(eventuallyEnabled(app.buttons["reading-tools-menu"]))
        app.buttons["reading-tools-menu"].tap()
        app.buttons["reading-find-button"].tap()
        XCTAssertTrue(app.textFields["reading-search-field"].waitForExistence(timeout: 5))
    }

    private func setPasteboard(_ text: String, app: XCUIApplication) {
        #if !targetEnvironment(simulator)
        // Real devices restrict pasteboard access from background processes.
        // Bring the test runner forward only to prepare its own fixture.
        guard let runnerIdentifier = Bundle.main.bundleIdentifier else {
            XCTFail("Missing UI test runner bundle identifier")
            return
        }
        let runner = XCUIApplication(bundleIdentifier: runnerIdentifier)
        runner.activate()
        XCTAssertTrue(runner.wait(for: .runningForeground, timeout: 5))
        #endif

        UIPasteboard.general.setItems(
            [["public.utf8-plain-text": text]],
            options: [.localOnly: true]
        )
        XCTAssertEqual(UIPasteboard.general.string, text)

        #if !targetEnvironment(simulator)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        #endif
    }

    private func openContents(_ app: XCUIApplication) {
        app.buttons["reading-tools-menu"].tap()
        app.buttons["reading-contents-button"].tap()
        XCTAssertTrue(app.buttons["reading-contents-done"].waitForExistence(timeout: 5))
    }

    private func eventuallyEnabled(_ element: XCUIElement) -> Bool {
        wait { element.exists && element.isEnabled }
    }

    private func eventuallyHittable(_ element: XCUIElement) -> Bool {
        wait { element.exists && element.isHittable }
    }

    private func wait(_ predicate: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 12) == .completed
    }

    private func waitForLabel(_ label: String, identifier: String, app: XCUIApplication) {
        XCTAssertTrue(wait { app.staticTexts[identifier].exists && app.staticTexts[identifier].label == label })
    }

    private func scrollTo(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func screenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
