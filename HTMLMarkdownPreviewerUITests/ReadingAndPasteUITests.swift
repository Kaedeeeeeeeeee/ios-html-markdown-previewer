import UIKit
import XCTest

@MainActor
final class ReadingAndPasteUITests: XCTestCase {
    func testLongTitleAndBottomActionsStayAccessibleDuringReadingAndSearch() {
        let app = launchFresh()
        let name = "週末の読書ノート—跨语言阅读记录—A longer document title for a quieter Saturday"
        let sections = (1...8).map { index in
            "## Chapter \(index)\n\n" + String(repeating: "A quieter Saturday leaves room for reading. ", count: 10)
        }.joined(separator: "\n\n")
        paste("# Weekend reading\n\n\(sections)\n\nThe final reading note.", name: name, app: app)
        XCTAssertTrue(app.staticTexts["Weekend reading"].waitForExistence(timeout: 10))

        let title = app.buttons["document-title-button"]
        XCTAssertTrue(eventuallyHittable(title))
        XCTAssertTrue(title.label.contains(name))
        XCTAssertLessThan(title.frame.maxY, app.frame.height * 0.3)

        let actionIDs = ["reading-tools-menu", "preview-mode-menu", "share-file-button", "file-details-button"]
        let actions = actionIDs.map { app.buttons[$0] }
        for action in actions {
            XCTAssertTrue(eventuallyHittable(action), "Missing accessible bottom action: \(action.identifier)")
            XCTAssertGreaterThan(action.frame.minY, app.frame.height * 0.6)
            XCTAssertGreaterThan(action.frame.minY, title.frame.maxY)
        }
        let rowY = actions[0].frame.midY
        for action in actions.dropFirst() {
            XCTAssertLessThan(abs(action.frame.midY - rowY), 24, "The four actions should share one row")
        }
        XCTAssertGreaterThan(actions[3].frame.maxX, app.frame.maxX - app.frame.width * 0.2)
        for (left, right) in zip(actions, actions.dropFirst()) {
            XCTAssertLessThanOrEqual(left.frame.maxX, right.frame.minX + 1, "Bottom actions must not overlap")
        }
        screenshot("Long multilingual title with four bottom-right actions", app: app)

        let fullFilename = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Name: \(name).md")
        ).firstMatch
        title.tap()
        XCTAssertTrue(fullFilename.waitForExistence(timeout: 5))
        app.buttons["document-details-done-button"].tap()
        XCTAssertTrue(eventuallyHittable(app.buttons["file-details-button"]))
        app.buttons["file-details-button"].tap()
        XCTAssertTrue(fullFilename.waitForExistence(timeout: 5))
        app.buttons["document-details-done-button"].tap()

        openSearch(app)
        app.textFields["reading-search-field"].tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        let keyboardContinue = keyboard.buttons["Continue"]
        if keyboardContinue.exists {
            keyboardContinue.tap()
        }
        XCTAssertTrue(wait { keyboard.keys.count > 0 }, "The normal keyboard should be available after onboarding")
        app.textFields["reading-search-field"].typeText("Saturday")
        waitForLabel("1 of 80", identifier: "reading-match-count", app: app)
        for identifier in actionIDs {
            XCTAssertFalse(app.buttons[identifier].exists, "Search should replace the action dock")
        }
        XCTAssertFalse(app.descendants(matching: .any)["preview-actions"].exists)
        XCTAssertTrue(app.buttons["reading-search-close"].isHittable)
        screenshot("Search replaces bottom actions above the keyboard", app: app)
        app.buttons["reading-search-close"].tap()
        XCTAssertTrue(wait { !app.keyboards.firstMatch.exists })
        XCTAssertFalse(app.textFields["reading-search-field"].exists)
        for action in actions {
            XCTAssertTrue(eventuallyHittable(action))
        }
        let contentScrollView = app.scrollViews.firstMatch
        XCTAssertTrue(contentScrollView.exists)
        let finalNote = app.staticTexts["The final reading note."]
        for _ in 0..<20 {
            if finalNote.exists && finalNote.isHittable && finalNote.frame.maxY < actions[0].frame.minY {
                break
            }
            contentScrollView.swipeUp()
        }
        XCTAssertTrue(finalNote.exists && finalNote.isHittable)
        XCTAssertLessThan(finalNote.frame.maxY, actions[0].frame.minY, "The final text should scroll fully above the floating actions")
        screenshot("Final reading note clears the bottom action dock", app: app)
    }

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
        // A cold WebKit process launch on older retained simulators can exceed 10 seconds.
        XCTAssertTrue(app.staticTexts["Local HTML report"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Interactive"].exists)
        XCTAssertTrue(app.staticTexts["UNSAFE SCRIPT EXECUTED"].waitForExistence(timeout: 10))
        app.buttons["preview-mode-menu"].tap()
        app.buttons["Safe Preview"].tap()
        XCTAssertTrue(app.staticTexts["Safe script remains blocked"].waitForExistence(timeout: 10))
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
        XCTAssertTrue(app.staticTexts["Safe Preview"].waitForExistence(timeout: 10))
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
        tapSystemPaste(app)
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
        tapSystemPaste(app)
        XCTAssertTrue(eventuallyEnabled(app.buttons["paste-open-button"]))
        let nameField = app.textFields["paste-name-field"]
        scrollTo(nameField, app: app)
        nameField.tap()
        nameField.typeText(name)
        app.buttons["paste-open-button"].tap()
    }

    private func tapSystemPaste(_ app: XCUIApplication) {
        let button = app.buttons["paste-system-button"]
        // On iOS 18, Form exposes the whole row as the PasteButton's accessibility
        // frame even though the native control only occupies its leading edge.
        button.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: min(48, button.frame.width / 2), dy: 0))
            .tap()
    }

    private func openSearch(_ app: XCUIApplication) {
        XCTAssertTrue(eventuallyEnabled(app.buttons["reading-tools-menu"]))
        app.buttons["reading-tools-menu"].tap()
        app.buttons["reading-find-button"].tap()
        XCTAssertTrue(app.textFields["reading-search-field"].waitForExistence(timeout: 5))
    }

    private func setPasteboard(_ text: String, app: XCUIApplication) {
        // Prepare clipboard content from a foreground app on every OS, matching
        // a real copy-and-paste flow without relying on simulator background access.
        guard let runnerIdentifier = Bundle.main.bundleIdentifier else {
            XCTFail("Missing UI test runner bundle identifier")
            return
        }
        let runner = XCUIApplication(bundleIdentifier: runnerIdentifier)
        runner.activate()
        XCTAssertTrue(runner.wait(for: .runningForeground, timeout: 5))

        UIPasteboard.general.setItems(
            [["public.utf8-plain-text": text]],
            options: [.localOnly: true]
        )
        XCTAssertEqual(UIPasteboard.general.string, text)

        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
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
