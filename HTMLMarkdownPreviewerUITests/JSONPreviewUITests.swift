import XCTest
import UIKit

@MainActor
final class JSONPreviewUITests: XCTestCase {
    func testSampleSearchFindsCollapsedFieldsAndSourceModeSurvivesRelaunch() {
        let app = launch(sample: true)
        XCTAssertTrue(app.buttons["json-options-menu"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["json-value-$.requestId"].label, "9007199254740993")
        let report = app.buttons["json-toggle-$.report"]
        XCTAssertTrue(report.exists)
        // First-level collections are initially expanded; explicitly collapse
        // this one before proving search can reveal its nested fields.
        if app.staticTexts["json-value-$.report.minutes"].exists { report.tap() }
        find("247", app: app)
        XCTAssertTrue(wait { app.staticTexts["json-match-count"].label == "1 of 1" })
        XCTAssertTrue(wait { app.staticTexts["json-value-$.report.minutes"].isHittable })
        screenshot("JSON 01 search reveals nested field", app)
        app.buttons["json-search-clear"].tap()
        app.buttons["Source"].tap()
        XCTAssertTrue(element("json-source-content", app).waitForExistence(timeout: 5))
        screenshot("JSON 02 source and line numbers", app)
        navigateHome(app)
        let recent = app.buttons["recent-document-api-response.json"]
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        recent.tap()
        XCTAssertTrue(element("json-source-content", app).waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(recent.waitForExistence(timeout: 10))
        recent.tap()
        XCTAssertTrue(element("json-source-content", app).waitForExistence(timeout: 10))
        app.buttons["Structure"].tap()
        XCTAssertEqual(app.staticTexts["json-value-$.requestId"].label, "9007199254740993")
    }

    func testSystemPasteDetectsJSONAndCopiesExactNumberAndCollection() {
        let app = launch()
        let source = #"{"id":9007199254740993,"nested":{"name":"中文 / 日本語","enabled":true}}"#
        paste(source, name: "JSON Copy QA", app: app)
        XCTAssertTrue(app.staticTexts["json-value-$.id"].waitForExistence(timeout: 10))
        let number = app.staticTexts["json-value-$.id"]
        number.press(forDuration: 1.1)
        tapMenuAction("json-copy-value", app: app)
        assertCopiedText("9007199254740993", filename: "JSON Copy QA.json", app: app)
        number.press(forDuration: 1.1)
        tapMenuAction("json-copy-path", app: app)
        assertCopiedText("$.id", filename: "JSON Copy QA.json", app: app)
        let nested = app.buttons["json-toggle-$.nested"]
        XCTAssertTrue(nested.exists)
        nested.press(forDuration: 1.1)
        tapMenuAction("json-copy-value", app: app)
        assertCopiedText(#"{"name":"中文 / 日本語","enabled":true}"#, filename: "JSON Copy QA.json", app: app)
        app.buttons["json-options-menu"].tap()
        tapMenuAction("json-copy-source", app: app)
        assertCopiedText(source, filename: "JSON Copy QA.json", app: app)
        screenshot("JSON 03 pasted response and exact copying", app)
    }

    func testInvalidJSONShowsErrorLineAndPreservesOriginalSharing() {
        let app = launch()
        let source = "{\n  \"value\": 1,\n}"
        paste("```json\n\(source)\n```", name: "Broken JSON QA", app: app)
        XCTAssertTrue(app.staticTexts["json-error-location"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["json-error-location"].label.contains("Line 3"))
        app.buttons["json-show-error"].tap()
        XCTAssertTrue(element("json-source-line-3", app).waitForExistence(timeout: 5))
        screenshot("JSON 04 syntax error keeps readable source", app)
        app.buttons["json-options-menu"].tap()
        tapMenuAction("json-copy-source", app: app)
        assertCopiedText(source, filename: "Broken JSON QA.json", app: app)
        app.buttons["share-file-button"].tap()
        XCTAssertFalse(app.buttons["Export PDF"].isEnabled)
        app.buttons["Share Original File"].tap()
        let save = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR (label CONTAINS %@ AND label CONTAINS %@) OR (label CONTAINS %@ AND label CONTAINS %@)", "Save to Files", "ファイル", "保存", "文件", "存储")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10))
    }

    func testLocalizedStructureSourceAndLargeText() {
        let chinese = launch(sample: true, language: "zh-Hans", locale: "zh_CN")
        XCTAssertTrue(chinese.buttons["json-options-menu"].waitForExistence(timeout: 10))
        screenshot("JSON 05 Chinese structure", chinese)
        chinese.buttons["源码"].tap()
        XCTAssertTrue(element("json-source-content", chinese).waitForExistence(timeout: 5))
        screenshot("JSON 06 Chinese source", chinese)
        chinese.terminate()
        let japanese = launch(sample: true, language: "ja", locale: "ja_JP", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(japanese.buttons["json-options-menu"].waitForExistence(timeout: 10))
        XCTAssertTrue(japanese.textFields["json-search-field"].isHittable)
        japanese.buttons["ソース"].tap()
        XCTAssertTrue(element("json-source-line-1", japanese).waitForExistence(timeout: 5))
        screenshot("JSON 07 Japanese accessibility text size", japanese)
    }

    private func launch(sample: Bool = false, language: String = "en", locale: String = "en_US", extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HTML_PREVIEWER_UI_TESTS"] = "1"
        app.launchArguments = ["--screenshot-reset-library", "-AppleLanguages", "(\(language))", "-AppleLocale", locale] + extra
        if sample { app.launchArguments.append("--screenshot-sample=json") }
        app.launch()
        return app
    }

    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: 15) == .completed
    }

    private func navigateHome(_ app: XCUIApplication) {
        let systemBack = app.buttons.matching(identifier: "BackButton").firstMatch
        let legacyBack = app.navigationBars.buttons.matching(NSPredicate(
            format: "label == %@ AND identifier != %@", "HTML Previewer", "document-title-button"
        )).firstMatch
        XCTAssertTrue(wait {
            (systemBack.exists && systemBack.isHittable) || (legacyBack.exists && legacyBack.isHittable)
        }, "The document must expose a native library back button")
        (systemBack.exists && systemBack.isHittable ? systemBack : legacyBack).tap()
        XCTAssertTrue(app.buttons["paste-preview-button"].waitForExistence(timeout: 5),
                      "Back must return to the document library")
    }

    private func find(_ text: String, app: XCUIApplication) {
        let field = app.textFields["json-search-field"]
        XCTAssertTrue(field.isHittable)
        field.tap()
        field.typeText(text + "\n")
        XCTAssertTrue(wait { field.value as? String == text })
    }

    private func paste(_ source: String, name: String, app: XCUIApplication) {
        XCTAssertTrue(app.buttons["paste-preview-button"].waitForExistence(timeout: 10))
        app.buttons["paste-preview-button"].tap()
        let runner = XCUIApplication(bundleIdentifier: Bundle.main.bundleIdentifier!)
        runner.activate()
        XCTAssertTrue(runner.wait(for: .runningForeground, timeout: 5))
        UIPasteboard.general.setItems([["public.utf8-plain-text": source]], options: [.localOnly: true])
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        let button = app.buttons["paste-system-button"]
        XCTAssertTrue(wait { button.isEnabled })
        tapPaste(button)
        XCTAssertTrue(wait { app.textViews["paste-text-editor"].value as? String == source })
        let nameField = app.textFields["paste-name-field"]
        for _ in 0..<5 where !nameField.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.78))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.30)))
        }
        XCTAssertTrue(nameField.isHittable)
        XCTAssertTrue(app.buttons["JSON"].isSelected)
        nameField.tap()
        nameField.typeText(name)
        app.buttons["paste-open-button"].tap()
    }

    private func tapPaste(_ button: XCUIElement) {
        button.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: min(48, button.frame.width / 2), dy: 0)).tap()
    }

    private func tapMenuAction(_ id: String, app: XCUIApplication) {
        let button = app.buttons[id]
        XCTAssertTrue(wait { button.exists && button.isHittable })
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(wait { !button.exists })
    }

    private func assertCopiedText(_ text: String, filename: String, app: XCUIApplication) {
        navigateHome(app)
        XCTAssertTrue(wait { app.buttons["paste-preview-button"].isHittable })
        app.buttons["paste-preview-button"].tap()
        let button = app.buttons["paste-system-button"]
        XCTAssertTrue(wait { button.isEnabled })
        tapPaste(button)
        XCTAssertTrue(wait { app.textViews["paste-text-editor"].value as? String == text })
        app.buttons["paste-cancel-button"].tap()
        app.buttons["recent-document-\(filename)"].tap()
        XCTAssertTrue(app.buttons["json-options-menu"].waitForExistence(timeout: 10))
    }

    private func screenshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
