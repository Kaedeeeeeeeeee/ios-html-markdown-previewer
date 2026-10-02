import UIKit
import XCTest

@MainActor
final class ReadingAndPasteUITests: XCTestCase {
    func testEnhancedMarkdownCopiesExactCodeAndKeepsMathDiagramSearchAndPosition() throws {
        continueAfterFailure = false
        let token = UUID().uuidString
        let name = "QA-ReadingLibrary-\(token)-Enhanced"
        let app = XCUIApplication()
        app.launchEnvironment["HTML_PREVIEWER_UI_TESTS"] = "1"
        let arguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchArguments = arguments + ["--reading-library-fixture=\(token)"]
        app.launch()
        defer {
            app.terminate()
            app.launchArguments = arguments + ["--reading-library-cleanup=\(token)"]
            app.launch()
            XCTAssertTrue(app.buttons["paste-preview-button"].waitForExistence(timeout: 15))
            XCTAssertFalse(app.buttons["recent-document-\(name).md"].exists)
        }
        let code = "let result = 42\n\tprint(\"日本語 + 中文: \\(result)\")\n"
        let middle = (1...5).map {
            "## Section \($0)\n\n" + String(repeating: "Offline study notes retain their reading position. ", count: 12)
        }.joined(separator: "\n\n")
        let markdown = """
        # Enhanced study notes

        ```swift
        \(code)```

        ## Formula study

        An inline formula $E = mc^2$ stays in this sentence.

        $$
        x^2 + y^2 = z^2
        $$

        ## Diagram study

        ```mermaid
        flowchart LR
          AlphaNode[Idea] --> ReviewNode[Review] --> FinishNode[Done]
        ```

        \(middle)

        ## Final enhanced decision

        This final enhanced reading position stays after reopening.
        """
        paste(markdown, name: name, app: app)
        let ready = app.buttons["reading-tools-menu"]
        let readiness = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in ready.exists && ready.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [readiness], timeout: 45), .completed)
        XCTAssertTrue(app.webViews.firstMatch.exists)
        let copy = app.webViews.buttons["Copy Code"].firstMatch
        XCTAssertTrue(eventuallyHittable(copy))
        copy.tap()
        // The WebKit integration test verifies the feedback text and ARIA label
        // at the click. A remote accessibility snapshot can arrive after its
        // 1.8-second lifetime; the exact native paste round-trip below verifies
        // that this user interaction actually copied the original code.
        screenshot("Enhanced Markdown syntax colors after copying code", app: app)

        // Round-trip the actual copy through the app's public system PasteButton;
        // this verifies its native bridge without a test-only clipboard reader.
        app.navigationBars.buttons["HTML Previewer"].tap()
        app.buttons["paste-preview-button"].tap()
        XCTAssertTrue(eventuallyEnabled(app.buttons["paste-system-button"]))
        tapSystemPaste(app)
        let editor = app.textViews["paste-text-editor"]
        XCTAssertTrue(wait { (editor.value as? String) == code }, "Copied code must preserve tabs, Unicode and the trailing newline exactly.")
        screenshot("Copied enhanced code pasted with original whitespace", app: app)
        app.buttons["paste-cancel-button"].tap()
        let row = app.buttons["recent-document-\(name).md"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let reopenedReadiness = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in ready.exists && ready.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reopenedReadiness], timeout: 45), .completed)

        openSearch(app)
        app.textFields["reading-search-field"].typeText("x^2\n")
        waitForLabel("1 of 1", identifier: "reading-match-count", app: app)
        XCTAssertFalse(app.staticTexts["This formula could not be displayed. Its source is shown below."].exists)
        screenshot("LaTeX formula revealed by canonical-source search", app: app)
        closeSearch(app)
        openSearch(app)
        app.textFields["reading-search-field"].typeText("AlphaNode\n")
        waitForLabel("1 of 1", identifier: "reading-match-count", app: app)
        XCTAssertFalse(app.staticTexts["This diagram could not be displayed. Its source is shown below."].exists)
        screenshot("Offline Mermaid diagram revealed by source search", app: app)
        closeSearch(app)

        openContents(app)
        let heading = app.buttons["Final enhanced decision"]
        scrollTo(heading, app: app)
        heading.tap()
        let finalText = app.staticTexts["This final enhanced reading position stays after reopening."]
        XCTAssertTrue(eventuallyHittable(finalText))
        screenshot("Enhanced Markdown outline jumps to final section", app: app)
        app.navigationBars.buttons["HTML Previewer"].tap()
        app.terminate()
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        XCTAssertTrue(finalText.waitForExistence(timeout: 45))
        XCTAssertTrue(eventuallyHittable(finalText), "Enhanced Markdown should reopen at the structural block saved before relaunch.")
        screenshot("Enhanced Markdown saved position after relaunch", app: app)
    }

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
        let keyboardContinue = keyboard.buttons["Continue"]
        if keyboardContinue.exists {
            keyboardContinue.tap()
        }
        // Third-party keyboards can expose their keys as Other elements.
        // Verify text entry and results rather than Apple's keyboard AX type.
        app.textFields["reading-search-field"].typeText("Saturday")
        waitForLabel("1 of 80", identifier: "reading-match-count", app: app)
        for identifier in actionIDs {
            XCTAssertFalse(app.buttons[identifier].exists, "Search should replace the action dock")
        }
        XCTAssertFalse(app.descendants(matching: .any)["preview-actions"].exists)
        XCTAssertTrue(app.buttons["reading-search-close"].isHittable)
        screenshot("Search replaces bottom actions above the keyboard", app: app)
        closeSearch(app)
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
        closeSearch(app)
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
        closeSearch(app)
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
        closeSearch(app)
        openContents(app)
        let finalHeading = app.buttons.matching(NSPredicate(format: "label == %@", "Final destination")).firstMatch
        scrollTo(finalHeading, app: app)
        finalHeading.tap()
        XCTAssertTrue(eventuallyHittable(app.staticTexts["Final destination"]))
        app.navigationBars.buttons["HTML Previewer"].tap()
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let recent = app.buttons["recent-document-HTML QA.html"]
        let recentReady = eventuallyHittable(recent)
        if !recentReady {
            attachInterfaceSnapshot("HTML resume recent document is not ready", app: app)
        }
        XCTAssertTrue(recentReady)
        recent.tap()
        let reopened = app.buttons["document-title-button"].waitForExistence(timeout: 10)
        if !reopened || app.buttons["document-title-button"].label != "HTML QA" {
            attachInterfaceSnapshot("HTML resume preview navigation failed", app: app)
        }
        XCTAssertTrue(reopened, "The recent HTML document should open its preview.")
        XCTAssertEqual(app.buttons["document-title-button"].label, "HTML QA")
        // The native status exposes either its title or its combined VoiceOver label.
        let safeStatus = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ OR label BEGINSWITH %@", "Safe Preview", "Safe Preview:")
        ).firstMatch
        let safePreviewRestored = safeStatus.waitForExistence(timeout: 10)
        if !safePreviewRestored {
            attachInterfaceSnapshot("HTML resume missing Safe Preview status", app: app)
        }
        XCTAssertTrue(safePreviewRestored)
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
        XCTAssertTrue(wait { (app.textViews["paste-text-editor"].value as? String) == "https://example.com/report" })
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
        closeSearch(app)
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
        XCTAssertTrue(wait { (app.textViews["paste-text-editor"].value as? String) == text },
                      "The system paste control must use the text just copied in the foreground runner.")
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
        let menu = app.buttons["reading-tools-menu"]
        XCTAssertTrue(eventuallyHittable(menu))
        menu.press(forDuration: 0.2)
        let find = app.buttons["reading-find-button"]
        XCTAssertTrue(eventuallyHittable(find))
        find.press(forDuration: 0.2)
        XCTAssertTrue(eventuallyHittable(app.textFields["reading-search-field"]))
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

    private func closeSearch(_ app: XCUIApplication) {
        let close = app.buttons["reading-search-close"]
        XCTAssertTrue(eventuallyHittable(close))
        // CI recorded a 50-ms tap without the close action taking effect.
        // Use a normal short press and verify the public state transition
        // before querying the controls that replace the search bar.
        close.press(forDuration: 0.2)
        XCTAssertTrue(wait { !app.textFields["reading-search-field"].exists }, "Closing search must remove its input field.")
        XCTAssertTrue(eventuallyEnabled(app.buttons["reading-tools-menu"]))
    }

    private func openContents(_ app: XCUIApplication) {
        let menu = app.buttons["reading-tools-menu"]
        XCTAssertTrue(eventuallyHittable(menu))
        menu.press(forDuration: 0.2)
        let contents = app.buttons["reading-contents-button"]
        XCTAssertTrue(eventuallyHittable(contents))
        // The CI recording showed this menu still open after a 50-ms tap.
        // Issue one normal short press, then require the actual sheet transition.
        contents.press(forDuration: 0.2)
        let opened = eventuallyHittable(app.buttons["reading-contents-done"])
        if !opened {
            attachInterfaceSnapshot("Reading contents sheet did not open", app: app)
        }
        XCTAssertTrue(opened, "The contents action must present its navigable sheet.")
    }

    private func eventuallyEnabled(_ element: XCUIElement) -> Bool {
        wait { element.exists && element.isEnabled }
    }

    private func eventuallyHittable(_ element: XCUIElement) -> Bool {
        wait { element.exists && element.isHittable }
    }

    private func wait(_ predicate: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        // Hosted CI accessibility snapshots can themselves take over 20 seconds.
        // Keep the condition exact while allowing the cross-process read to finish.
        return XCTWaiter.wait(for: [expectation], timeout: 45) == .completed
    }

    private func waitForLabel(_ label: String, identifier: String, app: XCUIApplication) {
        let element = app.staticTexts[identifier]
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND label == %@", label), object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 45), .completed)
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

    private func attachInterfaceSnapshot(_ name: String, app: XCUIApplication) {
        screenshot(name, app: app)
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = "\(name) accessibility hierarchy"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
