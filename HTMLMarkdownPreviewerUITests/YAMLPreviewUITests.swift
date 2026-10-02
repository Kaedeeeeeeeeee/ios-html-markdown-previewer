import XCTest
import UIKit

@MainActor
final class YAMLPreviewUITests: XCTestCase {
    func testStructureSourceSearchMultipleDocumentsAndReopen() {
        let app = launch(sample: true)
        XCTAssertTrue(app.buttons["yaml-toggle-services.web"].waitForExistence(timeout: 10))
        app.buttons["yaml-toggle-services.web"].tap()
        XCTAssertTrue(app.staticTexts["yaml-value-services.web.port"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["yaml-value-services.web.port"].label, "8080")
        app.buttons["yaml-toggle-services.web"].tap()
        XCTAssertFalse(app.staticTexts["yaml-value-services.web.port"].exists)
        find("8080", app: app)
        XCTAssertTrue(wait { app.staticTexts["yaml-match-count"].label == "1 of 1" })
        XCTAssertTrue(wait { app.staticTexts["yaml-value-services.web.port"].isHittable })
        screenshot("YAML search reveals collapsed port", app)
        app.buttons["yaml-search-clear"].tap()

        app.buttons["yaml-document-menu"].tap()
        app.buttons["yaml-document-1"].tap()
        app.buttons["yaml-toggle-services.web"].tap()
        XCTAssertEqual(app.staticTexts["yaml-value-services.web.port"].label, "3000")
        app.buttons["Source"].tap()
        XCTAssertTrue(sourceLine(27, app).waitForExistence(timeout: 5))
        XCTAssertTrue(waitForVisibleSourceLine(27, app: app),
                      "Confirm the second document is visible before saving its reading position.")
        screenshot("Second YAML document source", app)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let recent = app.buttons["recent-document-app-config.yaml"]
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        recent.tap()
        XCTAssertTrue(element("yaml-source-content", app).waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["yaml-document-menu"].label, "Document 2 of 2")
        XCTAssertTrue(waitForVisibleSourceLine(27, app: app))
        screenshot("YAML source reading position survives reopening", app)
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(recent.waitForExistence(timeout: 10))
        recent.tap()
        XCTAssertTrue(element("yaml-source-content", app).waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["yaml-document-menu"].label, "Document 2 of 2")
        XCTAssertTrue(waitForVisibleSourceLine(27, app: app))
        screenshot("YAML source and selected document survive relaunch", app)
    }

    func testSystemPasteAutoDetectsYAMLFenceAndCopiesValuePathAndSource() {
        let app = launch()
        let yaml = "# Keep this comment\nservices:\n  web:\n    port: 8080\n    enabled: true\n    name: 中文配置"
        paste("```yaml\n\(yaml)\n```", name: "YAML Paste QA", app: app)
        XCTAssertTrue(app.buttons["yaml-toggle-services.web"].waitForExistence(timeout: 10))
        app.buttons["yaml-toggle-services.web"].tap()
        let port = app.staticTexts["yaml-value-services.web.port"]
        XCTAssertTrue(port.waitForExistence(timeout: 5))
        port.press(forDuration: 1.1)
        tapMenuAction("yaml-copy-value", app: app)
        assertCopiedText("8080", filename: "YAML Paste QA.yaml", app: app)
        if !port.exists { app.buttons["yaml-toggle-services.web"].tap() }
        port.press(forDuration: 1.1)
        tapMenuAction("yaml-copy-path", app: app)
        assertCopiedText("services.web.port", filename: "YAML Paste QA.yaml", app: app)
        if !port.exists { app.buttons["yaml-toggle-services.web"].tap() }
        port.press(forDuration: 1.1)
        tapMenuAction("yaml-show-source", app: app)
        XCTAssertTrue(wait { self.sourceLine(4, app).isHittable })
        app.buttons["yaml-options-menu"].tap()
        tapMenuAction("yaml-copy-source", app: app)
        assertCopiedText(yaml, filename: "YAML Paste QA.yaml", app: app)
        screenshot("Pasted YAML source preserves comments and Unicode", app)
    }

    func testInvalidYAMLPointsToErrorKeepsSourceAndAllowsOriginalSharing() {
        let app = launch()
        let yaml = "app:\n  name: Demo\n port: 8080"
        paste(yaml, name: "Broken YAML QA", manualYAML: true, app: app)
        XCTAssertTrue(app.staticTexts["yaml-error-location"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["yaml-error-location"].label.contains("Line 3"))
        app.buttons["yaml-show-error"].tap()
        XCTAssertTrue(wait { self.sourceLine(3, app).isHittable })
        XCTAssertTrue(sourceLine(3, app).label.contains("port: 8080"))
        screenshot("YAML syntax error line and readable source", app)
        app.buttons["yaml-options-menu"].tap()
        tapMenuAction("yaml-copy-source", app: app)
        assertCopiedText(yaml, filename: "Broken YAML QA.yaml", app: app)
        app.buttons["share-file-button"].tap()
        app.buttons["Share Original File"].tap()
        let saveToFiles = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ OR (label CONTAINS %@ AND label CONTAINS %@) OR (label CONTAINS %@ AND label CONTAINS %@)",
            "Save to Files", "ファイル", "保存", "文件", "存储")).firstMatch
        XCTAssertTrue(saveToFiles.waitForExistence(timeout: 10))
        screenshot("Original YAML remains shareable after syntax error", app)
    }

    func testSourceSearchIncludesCommentsAndNoMatchesStaysUsable() {
        let app = launch(sample: true)
        XCTAssertTrue(app.buttons["yaml-options-menu"].waitForExistence(timeout: 10))
        app.buttons["Source"].tap()
        find("comments stay", app: app)
        XCTAssertTrue(wait { app.staticTexts["yaml-match-count"].label == "1 of 1" })
        XCTAssertTrue(wait { self.sourceLine(1, app).isHittable })
        app.buttons["yaml-search-clear"].tap()
        find("zzzz-no-result-zzzz", app: app)
        XCTAssertTrue(wait { app.staticTexts["yaml-match-count"].label == "No matches" })
        XCTAssertFalse(app.buttons["yaml-next-result"].isEnabled)
        XCTAssertFalse(app.buttons["yaml-previous-result"].isEnabled)
        app.buttons["yaml-search-clear"].tap()
        XCTAssertTrue(element("yaml-source-content", app).exists)
    }

    func testChineseScreenshotsAndYAMLLibraryFilter() {
        let app = launch(sample: true, language: "zh-Hans", locale: "zh_CN")
        XCTAssertTrue(app.buttons["yaml-toggle-services.web"].waitForExistence(timeout: 10))
        app.buttons["yaml-toggle-services.web"].tap()
        XCTAssertEqual(app.staticTexts["yaml-value-services.web.port"].label, "8080")
        screenshot("01 Chinese YAML structure", app)
        find("8080", app: app)
        XCTAssertTrue(wait { app.staticTexts["yaml-match-count"].label == "1 / 1" })
        XCTAssertTrue(wait { app.staticTexts["yaml-value-services.web.port"].isHittable })
        screenshot("02 Chinese YAML field search", app)
        app.buttons["yaml-search-clear"].tap()
        app.buttons["源码"].tap()
        let content = element("yaml-source-content", app)
        for _ in 0..<8 where !sourceLine(1, app).isHittable { content.swipeDown() }
        XCTAssertTrue(sourceLine(1, app).isHittable)
        XCTAssertTrue(sourceLine(1, app).label.contains("comments stay"))
        screenshot("03 Chinese YAML highlighted source", app)
        app.buttons["yaml-document-menu"].tap()
        app.buttons["yaml-document-1"].tap()
        app.buttons["结构"].tap()
        XCTAssertTrue(wait { app.staticTexts["profile"].isHittable })
        app.buttons["yaml-toggle-services.web"].tap()
        XCTAssertEqual(app.staticTexts["yaml-value-services.web.port"].label, "3000")
        screenshot("04 Chinese YAML second document", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["library-filter-menu"].tap()
        app.buttons["YAML"].tap()
        XCTAssertTrue(app.buttons["recent-document-app-config.yaml"].waitForExistence(timeout: 5))
        screenshot("05 Chinese YAML library filter", app)
    }

    func testChineseErrorScreenshotAndJapaneseControls() {
        let app = launch(language: "zh-Hans", locale: "zh_CN")
        paste("app:\n  name: Demo\n port: 8080", name: "错误示例", manualYAML: true, app: app)
        XCTAssertTrue(app.staticTexts["yaml-error-location"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["yaml-error-location"].label.contains("第 3 行"))
        app.buttons["yaml-show-error"].tap()
        XCTAssertTrue(wait { self.sourceLine(3, app).isHittable })
        screenshot("06 Chinese YAML syntax error", app)
        app.terminate()
        let japanese = launch(sample: true, language: "ja", locale: "ja_JP")
        XCTAssertTrue(japanese.buttons["構造"].waitForExistence(timeout: 10))
        XCTAssertTrue(japanese.buttons["ソース"].exists)
        japanese.buttons["ソース"].tap()
        XCTAssertTrue(japanese.textFields["yaml-search-field"].exists)
        screenshot("Japanese YAML controls", japanese)
    }

    func testLargeConfigurationSearchReachesLastField() {
        let app = launch()
        let source = (0..<1_000).map { "field_\($0): value_\($0)" }.joined(separator: "\n")
        paste("```yaml\n\(source)\n```", name: "Large YAML QA", app: app)
        XCTAssertTrue(app.textFields["yaml-search-field"].waitForExistence(timeout: 15))
        find("value_999", app: app)
        XCTAssertTrue(wait { app.staticTexts["yaml-match-count"].label == "1 of 1" })
        XCTAssertTrue(wait { app.staticTexts["yaml-value-field_999"].isHittable })
        XCTAssertEqual(app.staticTexts["yaml-value-field_999"].label, "value_999")
        app.buttons["Source"].tap()
        XCTAssertTrue(wait { self.sourceLine(1_000, app).isHittable })
        screenshot("Large YAML last field found in structure and source", app)
    }

    func testAccessibilityLargeTextKeepsReadingControlsUsable() {
        let app = launch(sample: true, extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.buttons["yaml-options-menu"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["yaml-search-field"].isHittable)
        XCTAssertTrue(app.buttons["Source"].isHittable)
        app.buttons["Source"].tap()
        let first = sourceLine(1, app)
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.label.contains("Line 1"))
        XCTAssertTrue(first.label.contains("comments stay"))
        XCTAssertTrue(app.buttons["Structure"].isHittable)
        screenshot("YAML source accessibility text size", app)
        app.buttons["Structure"].tap()
        find("8080", app: app)
        XCTAssertTrue(wait { app.staticTexts["yaml-value-services.web.port"].isHittable })
        screenshot("YAML search at accessibility text size", app)
    }

    private func launch(sample: Bool = false, language: String = "en", locale: String = "en_US", extraArguments: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HTML_PREVIEWER_UI_TESTS"] = "1"
        app.launchArguments = ["--screenshot-reset-library", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        if sample { app.launchArguments.append("--screenshot-sample=yaml") }
        app.launchArguments += extraArguments
        app.launch()
        return app
    }
    private func element(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    private func sourceLine(_ number: Int, _ app: XCUIApplication) -> XCUIElement {
        element("yaml-source-line-\(number)", app)
    }
    private func waitForVisibleSourceLine(_ number: Int, app: XCUIApplication) -> Bool {
        let viewport = app.scrollViews["yaml-source-content"].firstMatch
        let line = viewport.otherElements["yaml-source-line-\(number)"].firstMatch
        // Source rows are read-only accessibility elements. Their visible
        // geometry verifies restoration; hittability asks for a touch target
        // and can time out while CI collects a slow accessibility snapshot.
        // Restrict the query to the source ScrollView and the row's native type:
        // a full-app Any query can time out resolving a frame after relaunch.
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard line.exists, viewport.exists else { return false }
            let frame = line.frame
            let visible = frame.intersection(viewport.frame)
            return frame.height > 0 && visible.width > 0 && visible.height >= frame.height * 0.9
        }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 45) == .completed
    }
    private func wait(_ predicate: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 45) == .completed
    }
    private func find(_ query: String, app: XCUIApplication) {
        let field = app.textFields["yaml-search-field"]
        XCTAssertTrue(wait { field.isHittable })
        field.tap()
        field.typeText(query + "\n")
        XCTAssertTrue(wait { field.value as? String == query })
    }
    private func tapMenuAction(_ identifier: String, app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(wait { button.exists && button.isHittable })
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        // iOS 18 can return from tap before the context menu has finished
        // dismissing. A following navigation tap is then intercepted by it.
        XCTAssertTrue(wait { !button.exists })
    }
    private func paste(_ source: String, name: String, manualYAML: Bool = false, app: XCUIApplication) {
        XCTAssertTrue(app.buttons["paste-preview-button"].waitForExistence(timeout: 10))
        app.buttons["paste-preview-button"].tap()
        XCTAssertTrue(app.buttons["paste-system-button"].waitForExistence(timeout: 5))
        withRunner(app) { UIPasteboard.general.setItems([["public.utf8-plain-text": source]], options: [.localOnly: true]) }
        let button = app.buttons["paste-system-button"]
        XCTAssertTrue(wait { button.isEnabled })
        button.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: min(48, button.frame.width / 2), dy: 0)).tap()
        XCTAssertTrue(wait { (app.textViews["paste-text-editor"].value as? String) == source })
        XCTAssertLessThan(app.textViews["paste-text-editor"].frame.height, 300,
                          "Long pasted content must scroll within the editor and leave document controls reachable.")
        let nameField = app.textFields["paste-name-field"]
        // Drag the Form's outer margin: a gesture inside TextEditor scrolls
        // the pasted text instead, which never reveals the name on long files.
        for _ in 0..<5 where !nameField.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.78))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.30)))
        }
        XCTAssertTrue(nameField.isHittable)
        if manualYAML {
            let control = app.segmentedControls["paste-format-picker"]
            // SwiftUI Form can expose a segment with the entire row's frame.
            // Select YAML, the third of the four visible format segments.
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.625, dy: 0.5)).tap()
            XCTAssertTrue(app.buttons["YAML"].isSelected)
        }
        nameField.tap()
        nameField.typeText(name)
        app.buttons["paste-open-button"].tap()
    }
    private func withRunner(_ app: XCUIApplication, action: () -> Void) {
        let runner = XCUIApplication(bundleIdentifier: Bundle.main.bundleIdentifier!)
        runner.activate()
        XCTAssertTrue(runner.wait(for: .runningForeground, timeout: 5))
        action()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }
    private func assertCopiedText(_ expected: String, filename: String, app: XCUIApplication) {
        // Verify clipboard contents through the system Paste control. Direct
        // cross-app API reads trigger the runner's iOS paste permission prompt.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(wait { app.buttons["paste-preview-button"].isHittable })
        app.buttons["paste-preview-button"].tap()
        let button = app.buttons["paste-system-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(wait { button.isEnabled })
        button.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: min(48, button.frame.width / 2), dy: 0)).tap()
        XCTAssertTrue(wait { (app.textViews["paste-text-editor"].value as? String) == expected })
        app.buttons["paste-cancel-button"].tap()
        app.buttons["recent-document-\(filename)"].tap()
        XCTAssertTrue(app.buttons["yaml-options-menu"].waitForExistence(timeout: 10))
    }
    private func screenshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
