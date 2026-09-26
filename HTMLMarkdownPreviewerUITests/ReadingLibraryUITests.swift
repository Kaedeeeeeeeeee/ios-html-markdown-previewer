import UIKit
import XCTest

/// This suite is safe to run against an existing physical-device library.
/// Every test owns a UUID-scoped fixture and cleans up only that exact scope.
@MainActor
final class ReadingLibraryUITests: XCTestCase {
    func testHTMLPageZoomPersistsAndFullScreenCanRestore() throws {
        try withFixture { app, fixture in
            try openDocument(fixture.htmlFilename, app: app)
            let marker = app.staticTexts["HTML layout marker"]
            try require(marker.waitForExistence(timeout: 30), "HTML fixture should render")
            let originalHeight = marker.frame.height
            screenshot("HTML normal reading before display changes", app: app)

            try openAppearance(app)
            let originalZoom = try displayedValue("html-zoom-value", app: app)
            try tap("html-zoom-in", app: app)
            try tap("html-zoom-in", app: app)
            let increasedZoom = try displayedValue("html-zoom-value", app: app)
            XCTAssertNotEqual(increasedZoom, originalZoom)
            screenshot("HTML page zoom controls", app: app)
            try tap("reading-appearance-done", app: app)
            try require(wait { marker.exists && marker.frame.height > originalHeight + 1 }, "Page zoom should visibly enlarge HTML text")
            let enlargedHeight = marker.frame.height

            try tap("reading-tools-menu", app: app)
            try tap("reading-fullscreen-button", app: app)
            try require(wait { app.buttons["reading-fullscreen-exit"].isHittable }, "Full screen must retain an accessible restore button")
            XCTAssertFalse(app.buttons["document-title-button"].exists)
            XCTAssertFalse(app.buttons["preview-mode-menu"].exists)
            try require(wait { marker.exists && abs(marker.frame.height - enlargedHeight) <= 1 },
                        "Entering full screen must retain the enlarged text height within 1 point")
            screenshot("HTML full screen with visible restore control", app: app)
            try tap("reading-fullscreen-exit", app: app)
            try require(wait { app.buttons["document-title-button"].exists && app.buttons["preview-mode-menu"].isHittable }, "Restoring full screen should bring navigation and the action dock back")
            try require(wait { marker.exists && abs(marker.frame.height - enlargedHeight) <= 1 },
                        "Leaving full screen must retain the enlarged text height within 1 point")

            try navigateHome(app)
            relaunch(app)
            try openDocument(fixture.htmlFilename, app: app)
            try openAppearance(app)
            XCTAssertEqual(try displayedValue("html-zoom-value", app: app), increasedZoom)
            try tap("reading-appearance-reset", app: app)
            XCTAssertEqual(try displayedValue("html-zoom-value", app: app), originalZoom)
            try tap("reading-appearance-done", app: app)
            try require(wait { marker.exists && abs(marker.frame.height - originalHeight) <= 1 },
                        "Resetting page zoom should restore the original rendered text height within 1 point")
            screenshot("HTML reopened and display settings reset", app: app)
        }
    }

    func testMarkdownAppearancePersistsAndLocalImageOpens() throws {
        try withFixture { app, fixture in
            try openDocument(fixture.markdownFilename, app: app)
            let paragraph = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Markdown layout marker.")).firstMatch
            try require(paragraph.waitForExistence(timeout: 15), "Markdown fixture should render")
            let originalHeight = paragraph.frame.height

            try openAppearance(app)
            let originalFont = try displayedValue("markdown-font-value", app: app)
            let originalSpacing = try displayedValue("markdown-spacing-value", app: app)
            try tap("markdown-font-in", app: app)
            try tap("markdown-font-in", app: app)
            try tap("markdown-spacing-in", app: app)
            try tap("markdown-spacing-in", app: app)
            let largerFont = try displayedValue("markdown-font-value", app: app)
            let widerSpacing = try displayedValue("markdown-spacing-value", app: app)
            XCTAssertNotEqual(largerFont, originalFont)
            XCTAssertNotEqual(widerSpacing, originalSpacing)
            screenshot("Markdown font size and line spacing controls", app: app)
            try tap("reading-appearance-done", app: app)
            try require(wait { paragraph.exists && paragraph.frame.height > originalHeight + 1 }, "Larger type and line spacing should change the rendered paragraph")

            try navigateHome(app)
            relaunch(app)
            try openDocument(fixture.markdownFilename, app: app)
            try openAppearance(app)
            XCTAssertEqual(try displayedValue("markdown-font-value", app: app), largerFont)
            XCTAssertEqual(try displayedValue("markdown-spacing-value", app: app), widerSpacing)
            try tap("reading-appearance-done", app: app)

            let imageButton = app.buttons["markdown-image-open-qa-landscape.png"]
            try scrollTo(imageButton, app: app)
            // A partially visible image can be hittable while its center sits
            // under the floating action dock. Move that center into clear content.
            let navigationBottom = app.navigationBars.firstMatch.frame.maxY
            let dock = element("preview-actions", app: app)
            try require(dock.waitForExistence(timeout: 5), "Reading action dock should be visible before opening the image")
            let clearTop = max(navigationBottom + 24, app.frame.minY + app.frame.height * 0.2)
            let clearBottom = min(dock.frame.minY - 24, app.frame.minY + app.frame.height * 0.7)
            for _ in 0..<8 {
                let centerY = imageButton.frame.midY
                if imageButton.isHittable && centerY >= clearTop && centerY <= clearBottom { break }
                let startY: CGFloat = centerY > clearBottom ? 0.65 : 0.4
                let endY: CGFloat = centerY > clearBottom ? 0.4 : 0.65
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
                    .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY)))
            }
            try require(imageButton.isHittable && imageButton.frame.midY >= clearTop && imageButton.frame.midY <= clearBottom,
                        "The image center should be visible between navigation and the floating action dock")
            imageButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            try require(element("markdown-image-viewer", app: app).waitForExistence(timeout: 10), "Local image should open in its viewer")
            let originalImageZoom = try displayedValue("markdown-image-zoom-reset", app: app)
            try tap("markdown-image-zoom-in", app: app)
            try require(wait { self.value(of: self.element("markdown-image-zoom-reset", app: app)) != originalImageZoom }, "Image zoom should change")
            screenshot("Local Markdown image enlarged in viewer", app: app)
            try tap("markdown-image-zoom-reset", app: app)
            XCTAssertEqual(try displayedValue("markdown-image-zoom-reset", app: app), originalImageZoom)
            let imageViewer = element("markdown-image-viewer", app: app)
            imageViewer.pinch(withScale: 1.6, velocity: 1)
            try require(wait { self.value(of: self.element("markdown-image-zoom-reset", app: app)) != originalImageZoom }, "A two-finger pinch should enlarge the image")
            screenshot("Local Markdown image responds to pinch zoom", app: app)
            try tap("markdown-image-zoom-reset", app: app)
            XCTAssertEqual(try displayedValue("markdown-image-zoom-reset", app: app), originalImageZoom)
            try tap("markdown-image-close", app: app)
            try require(wait { !self.element("markdown-image-viewer", app: app).exists }, "Closing the image should return to the document")
            screenshot("Markdown returns to reading after closing image", app: app)
        }
    }

    func testLibraryPinRenameSearchAndTypeFilterPersist() throws {
        try withFixture { app, fixture in
            try searchLibrary(fixture.token, app: app)
            let htmlRow = row(fixture.htmlFilename, app: app)
            let markdownRow = row(fixture.markdownFilename, app: app)
            try require(htmlRow.waitForExistence(timeout: 10) && markdownRow.exists, "Both scoped fixtures should appear")

            try contextAction("library-pin-button", on: htmlRow, app: app)
            try require(wait { htmlRow.exists && markdownRow.exists && htmlRow.frame.minY < markdownRow.frame.minY }, "Pinned document should sort above the unpinned fixture")
            screenshot("Pinned QA report in the filtered document library", app: app)

            try contextAction("library-rename-button", on: htmlRow, app: app)
            let renamedTitle = "QA renamed \(fixture.token)"
            let nameField = app.textFields["library-rename-field"]
            try require(nameField.waitForExistence(timeout: 5), "Rename should present a name field")
            try replaceText(in: nameField, with: renamedTitle, app: app)
            try tap("library-rename-save", app: app)
            try searchLibrary(renamedTitle, app: app)
            try require(row(fixture.htmlFilename, app: app).waitForExistence(timeout: 5), "Search should find the updated display name")
            XCTAssertFalse(row(fixture.markdownFilename, app: app).exists)

            try chooseFilter("markdown", app: app)
            try require(wait { !self.row(fixture.htmlFilename, app: app).exists }, "Markdown filter must exclude an HTML report")
            try chooseFilter("html", app: app)
            try require(row(fixture.htmlFilename, app: app).waitForExistence(timeout: 5), "HTML filter should show the matching report")
            screenshot("Renamed report found with filename search and HTML filter", app: app)
            try chooseFilter("all", app: app)

            relaunch(app)
            try searchLibrary(renamedTitle, app: app)
            let savedRow = row(fixture.htmlFilename, app: app)
            try require(savedRow.waitForExistence(timeout: 5), "Renamed report should survive relaunch")
            savedRow.press(forDuration: 1)
            let pinAction = app.buttons["library-pin-button"]
            try require(pinAction.waitForExistence(timeout: 5), "Pinned report should expose its context action")
            XCTAssertEqual(pinAction.label, "Unpin")
            pinAction.tap()
        }
    }

    func testDuplicateImportUpdateKeepBothAndCancel() throws {
        try withFixture { app, fixture in
            let name = fixture.prefix + "Duplicate"
            let filename = name + ".md"
            try paste("# QA revision one\n\nOriginal report.", name: name, app: app)
            try require(app.staticTexts["QA revision one"].waitForExistence(timeout: 10), "First report should open")
            try navigateHome(app)

            try paste("# QA revision two\n\nUpdated report.", name: name, app: app)
            try tap("duplicate-update-button", app: app)
            try require(app.staticTexts["QA revision two"].waitForExistence(timeout: 10), "Update should open the replacement content")
            try navigateHome(app)
            try searchLibrary(name, app: app)
            XCTAssertEqual(rows(filename, app: app).count, 1, "Updating should retain one library record")
            screenshot("Duplicate update keeps a single QA document", app: app)
            relaunch(app)

            try paste("# QA revision three\n\nA second copy.", name: name, app: app)
            try tap("duplicate-keep-both-button", app: app)
            try require(app.staticTexts["QA revision three"].waitForExistence(timeout: 10), "Keep Both should open the new copy")
            try navigateHome(app)
            try searchLibrary(name, app: app)
            XCTAssertEqual(rows(filename, app: app).count, 2, "Keep Both should leave two records")
            screenshot("Keep Both preserves both QA document copies", app: app)
            relaunch(app)

            try paste("# QA revision four\n\nThis import must be cancelled.", name: name, app: app)
            try tap("duplicate-cancel-button", app: app)
            try searchLibrary(name, app: app)
            XCTAssertEqual(rows(filename, app: app).count, 2, "Cancel should not add another copy")

            // Verify both retained payloads, not only the number of rows.
            var retainedHeadings = Set<String>()
            for index in 0..<2 {
                let candidate = rows(filename, app: app).element(boundBy: index)
                try require(candidate.waitForExistence(timeout: 5), "Retained copy should be available")
                candidate.tap()
                try require(wait { app.staticTexts["QA revision two"].exists || app.staticTexts["QA revision three"].exists }, "Only the updated and retained revisions should remain")
                if app.staticTexts["QA revision two"].exists { retainedHeadings.insert("two") }
                if app.staticTexts["QA revision three"].exists { retainedHeadings.insert("three") }
                XCTAssertFalse(app.staticTexts["QA revision four"].exists)
                try navigateHome(app)
                try searchLibrary(name, app: app)
            }
            XCTAssertEqual(retainedHeadings, Set(["two", "three"]))
        }
    }

    private struct Fixture {
        let token = UUID().uuidString
        var prefix: String { "QA-ReadingLibrary-\(token)-" }
        var htmlFilename: String { prefix + "HTML.html" }
        var markdownFilename: String { prefix + "Markdown.md" }
    }

    private enum TestFailure: Error { case requirement(String) }

    private var baseArguments: [String] { ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"] }

    private func withFixture(_ body: (XCUIApplication, Fixture) throws -> Void) throws {
        continueAfterFailure = true
        let fixture = Fixture()
        let app = XCUIApplication()
        app.launchEnvironment["HTML_PREVIEWER_UI_TESTS"] = "1"
        app.launchArguments = baseArguments + ["--reading-library-fixture=\(fixture.token)"]
        app.launch()
        defer {
            app.terminate()
            app.launchArguments = baseArguments + ["--reading-library-cleanup=\(fixture.token)"]
            app.launch()
            XCTAssertTrue(app.buttons["paste-preview-button"].waitForExistence(timeout: 15), "App should return to its library after scoped cleanup")
            XCTAssertFalse(row(fixture.htmlFilename, app: app).exists)
            XCTAssertFalse(row(fixture.markdownFilename, app: app).exists)
            XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "recent-document-\(fixture.prefix)")).firstMatch.exists)
        }
        do {
            try require(app.buttons["paste-preview-button"].waitForExistence(timeout: 15), "Fixture launch should leave the library visible")
            try body(app, fixture)
        } catch {
            screenshot("Reading and library QA failure", app: app)
            throw error
        }
    }

    private func relaunch(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments = baseArguments
        app.launch()
        XCTAssertTrue(app.buttons["paste-preview-button"].waitForExistence(timeout: 15))
    }

    private func row(_ filename: String, app: XCUIApplication) -> XCUIElement {
        rows(filename, app: app).firstMatch
    }

    private func rows(_ filename: String, app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(identifier: "recent-document-\(filename)")
    }

    private func openDocument(_ filename: String, app: XCUIApplication) throws {
        try searchLibrary(filename, app: app)
        let documentRow = row(filename, app: app)
        try require(documentRow.waitForExistence(timeout: 10), "Missing QA document: \(filename)")
        documentRow.tap()
    }

    private func navigateHome(_ app: XCUIApplication) throws {
        let back = app.navigationBars.buttons["HTML Previewer"]
        try require(back.waitForExistence(timeout: 5), "Document should have a library back button")
        back.tap()
        try require(app.buttons["paste-preview-button"].waitForExistence(timeout: 5), "Back should return to the library")
    }

    private func openAppearance(_ app: XCUIApplication) throws {
        // A newly relaunched WebKit process can take longer than ordinary UI
        // interactions before rendered reading controls become available.
        let menu = app.buttons["reading-tools-menu"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            menu.exists && menu.isEnabled && menu.isHittable
        }, object: nil)
        try require(XCTWaiter.wait(for: [ready], timeout: 45) == .completed,
                    "Rendered reading controls should become ready after launch")
        try tap("reading-tools-menu", app: app)
        try tap("reading-appearance-button", app: app)
        try require(app.buttons["reading-appearance-done"].waitForExistence(timeout: 5), "Reading appearance sheet should open")
    }

    private func searchLibrary(_ query: String, app: XCUIApplication) throws {
        let field = app.searchFields.firstMatch
        for _ in 0..<3 where !field.exists || !field.isHittable { app.swipeDown() }
        try require(field.waitForExistence(timeout: 5), "Library search field should be available")
        try replaceText(in: field, with: query, app: app)
        field.typeText("\n")
        try require(wait { !app.keyboards.firstMatch.exists }, "Submitting library search should dismiss the keyboard")
    }

    private func chooseFilter(_ kind: String, app: XCUIApplication) throws {
        try tap("library-filter-menu", app: app)
        try tap("library-filter-\(kind)", app: app)
    }

    private func contextAction(_ identifier: String, on documentRow: XCUIElement, app: XCUIApplication) throws {
        try require(documentRow.exists && documentRow.isHittable, "QA row should be available for its context action")
        documentRow.press(forDuration: 1)
        try tap(identifier, app: app)
    }

    private func replaceText(in field: XCUIElement, with text: String, app: XCUIApplication) throws {
        field.tap()
        let keyboardContinue = app.keyboards.buttons["Continue"]
        if keyboardContinue.exists { keyboardContinue.tap() }
        if field.value as? String == text { return }
        if let existing = field.value as? String, !existing.isEmpty, existing != field.placeholderValue {
            // Tapping a populated long field can put the caret in the middle.
            // Backspacing `existing.count` characters would leave its suffix.
            let clear = field.buttons.matching(NSPredicate(
                format: "label IN %@", ["Clear text", "Clear Text", "Clear", "テキストを消去", "清除文本", "清除文字"]
            )).firstMatch
            if clear.exists && clear.isHittable {
                clear.tap()
            } else {
                // XCTest supports keyboard modifier events on iOS. Select all
                // independently of the localized edit menu and its overflow.
                field.typeKey("a", modifierFlags: .command)
            }
        }
        field.typeText(text)
        try require(wait { field.value as? String == text }, "Text field should contain exactly the requested value")
    }

    private func paste(_ text: String, name: String, app: XCUIApplication) throws {
        try tap("paste-preview-button", app: app)
        try require(app.buttons["paste-system-button"].waitForExistence(timeout: 5), "Paste screen should appear")
        guard let runnerIdentifier = Bundle.main.bundleIdentifier else { throw TestFailure.requirement("Missing UI test runner identifier") }
        let runner = XCUIApplication(bundleIdentifier: runnerIdentifier)
        runner.activate()
        try require(runner.wait(for: .runningForeground, timeout: 5), "Runner should be foreground to copy fixture text")
        UIPasteboard.general.setItems([["public.utf8-plain-text": text]], options: [.localOnly: true])
        app.activate()
        try require(app.wait(for: .runningForeground, timeout: 5), "App should return to paste preview")
        let pasteButton = app.buttons["paste-system-button"]
        try require(wait { pasteButton.exists && pasteButton.isEnabled }, "System Paste should accept fixture text")
        pasteButton.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: min(48, pasteButton.frame.width / 2), dy: 0)).tap()
        try require(wait { app.buttons["paste-open-button"].isEnabled }, "Pasted fixture should be ready to preview")
        let nameField = app.textFields["paste-name-field"]
        try scrollTo(nameField, app: app)
        try replaceText(in: nameField, with: name, app: app)
        try tap("paste-open-button", app: app)
    }

    private func element(_ identifier: String, app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func displayedValue(_ identifier: String, app: XCUIApplication) throws -> String {
        let target = element(identifier, app: app)
        try require(target.waitForExistence(timeout: 5), "Missing displayed value: \(identifier)")
        return value(of: target)
    }

    private func value(of target: XCUIElement) -> String {
        (target.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? target.label
    }

    private func tap(_ identifier: String, app: XCUIApplication) throws {
        let button = app.buttons[identifier]
        try require(wait { button.exists && button.isEnabled && button.isHittable }, "Missing enabled control: \(identifier)")
        button.tap()
    }

    private func scrollTo(_ target: XCUIElement, app: XCUIApplication) throws {
        for _ in 0..<8 {
            if target.exists && target.isHittable { return }
            app.swipeUp()
        }
        try require(target.exists && target.isHittable, "Expected content should scroll into view")
    }

    private func wait(_ predicate: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 12) == .completed
    }

    private func require(_ condition: Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(condition, message, file: file, line: line)
        guard condition else { throw TestFailure.requirement(message) }
    }

    private func screenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
