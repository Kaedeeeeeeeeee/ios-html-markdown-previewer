import XCTest

@MainActor
final class SmokeUITests: XCTestCase {
    func testPreviewShareSheetShowsVisibleOptions() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments = ["--screenshot-reset-library", "--screenshot-sample=html"]
        launch(app)

        XCTAssertTrue(app.buttons["share-file-button"].waitForExistence(timeout: 10))
        tapElement(app.buttons["share-file-button"], app: app)
        tapElement(app.buttons["Share Original File"], app: app)
        XCTAssertTrue(
            waitForAnyLabel(nativeShareOptionLabels, app: app),
            "Share sheet did not show visible share options"
        )
    }

    func testHTMLPDFExportShowsShareSheet() throws {
        assertPDFExport(sample: "html", heading: "A slower Saturday", repeatExport: true)
    }

    func testMarkdownPDFExportShowsShareSheet() throws {
        assertPDFExport(sample: "markdown", heading: "Make room to read")
    }

    func testChineseMarkdownRetainsEqualLengthHeadings() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments = [
            "--screenshot-reset-library", "--screenshot-sample=markdown",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"
        ]
        launch(app)

        XCTAssertTrue(app.staticTexts["留一点时间读书"].waitForExistence(timeout: 10))
        // These two different headings have the same UTF-8 length. Content-derived
        // CharacterView debug descriptions previously gave them identical view IDs.
        XCTAssertTrue(app.staticTexts["留下来的想法"].exists)
        XCTAssertTrue(scrollUntilExists(app.staticTexts["读下一章之前"], app: app))
        XCTAssertTrue(scrollUntilExists(app.staticTexts["一个小提醒"], app: app))
        attachScreenshot(named: "All Chinese Markdown headings remain visible", app: app)
    }

    func testZIPPDFExportShowsShareSheet() throws {
        assertPDFExport(sample: "zipPackage", heading: "A week of reading")
    }

    func testZIPShareOffersCompletePackage() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments = ["--screenshot-reset-library", "--screenshot-sample=zipPackage"]
        launch(app)
        XCTAssertTrue(app.staticTexts["A week of reading"].waitForExistence(timeout: 10))

        tapElement(app.buttons["share-file-button"], app: app)
        XCTAssertFalse(app.buttons["Share Original File"].exists)
        tapElement(app.buttons["Share ZIP Package"], app: app)
        XCTAssertTrue(waitForAnyLabel(nativeShareOptionLabels, app: app))
        attachScreenshot(named: "ZIP package share sheet", app: app)

        // System activities can keep the device language even when the app is tested in English.
        let saveToFiles = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ OR (label CONTAINS %@ AND label CONTAINS %@) OR (label CONTAINS %@ AND label CONTAINS %@) OR (label CONTAINS %@ AND label CONTAINS %@)",
            "Save to Files", "ファイル", "保存", "文件", "存储", "檔案", "儲存"
        )).firstMatch
        tapElement(saveToFiles, app: app)
        let packageName = app.textFields.matching(NSPredicate(
            format: "value == %@ OR value == %@", "reading-week", "reading-week.zip"
        )).firstMatch
        XCTAssertTrue(
            packageName.waitForExistence(timeout: 10),
            "Save to Files should offer reading-week.zip instead of its index.html entry"
        )
        attachScreenshot(named: "ZIP package filename in Save to Files", app: app)
    }

    func testRecentFilesPrecedeCollapsibleSamples() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments = ["--screenshot-reset-library", "--screenshot-sample=html"]
        launch(app)
        navigateHome(app: app)

        let recent = app.buttons["recent-document-weekend-plan.html"]
        let disclosure = app.descendants(matching: .any)["samples-disclosure"].firstMatch
        let sample = app.buttons["sample-html"]
        XCTAssertTrue(recent.waitForExistence(timeout: 10))
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        if sample.exists {
            tapElement(disclosure, app: app)
        }
        XCTAssertTrue(waitUntilAbsent(sample))
        XCTAssertLessThan(recent.frame.maxY, disclosure.frame.minY)
        attachScreenshot(named: "Recent files above collapsed samples", app: app)

        tapElement(disclosure, app: app)
        XCTAssertTrue(sample.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sample-markdown"].exists)
        XCTAssertTrue(app.buttons["sample-zipPackage"].exists)

        app.terminate()
        app.launchArguments = []
        launch(app)
        XCTAssertTrue(app.buttons["sample-html"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["recent-document-weekend-plan.html"].exists)
        tapElement(app.descendants(matching: .any)["samples-disclosure"].firstMatch, app: app)
        XCTAssertTrue(waitUntilAbsent(app.buttons["sample-html"]))
    }

    func testBuiltInSamplesAndSettingsSmoke() throws {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments = ["--screenshot-reset-library"]
        launch(app)
        XCTAssertTrue(app.navigationBars["HTML Previewer"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["open-file-button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["open-zip-package-button"].waitForExistence(timeout: 5))

        openSettingsAndVerifyReleaseClaims(app: app)

        openSample(identifier: "sample-html", app: app)
        XCTAssertTrue(app.staticTexts["Interactive"].waitForExistence(timeout: 10))
        tapElement(app.buttons["preview-mode-menu"], app: app)
        tapElement(app.buttons["Safe Preview"], app: app)
        XCTAssertTrue(app.staticTexts["Safe Preview"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(identifier: "Scripts and external network resources are blocked. Relative assets are best effort for single files.").firstMatch.exists)
        navigateHome(app: app)

        openSample(identifier: "sample-markdown", app: app)
        XCTAssertTrue(app.staticTexts["Make room to read"].waitForExistence(timeout: 10))
        openRawTextMode(app: app)
        XCTAssertTrue(app.staticTexts["Raw Text"].waitForExistence(timeout: 10))
        navigateHome(app: app)

        openSample(identifier: "sample-zipPackage", app: app)
        XCTAssertTrue(app.staticTexts["Interactive"].waitForExistence(timeout: 10))
        navigateHome(app: app)

        let recentZIPSample = app.buttons["recent-document-reading-week.zip"]
        XCTAssertTrue(scrollUntilExists(recentZIPSample, app: app), "Missing recent ZIP sample row")
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        // Environment persists when a test changes launchArguments and relaunches the app.
        app.launchEnvironment["HTML_PREVIEWER_UI_TESTS"] = "1"
        return app
    }

    private func launch(_ app: XCUIApplication) {
        // Pin the app's language for English assertions while retaining explicit locale tests.
        if !app.launchArguments.contains("-AppleLanguages") {
            app.launchArguments += ["-AppleLanguages", "(en)"]
            if !app.launchArguments.contains("-AppleLocale") {
                app.launchArguments += ["-AppleLocale", "en_US"]
            }
        }
        app.launch()
    }

    // The native share controller can retain the device language despite app launch overrides.
    private var nativeShareOptionLabels: [String] {
        ["Copy", "Save to Files", "More", "コピー", "その他", "拷贝", "复制", "更多", "拷貝", "複製"]
    }

    private func openSettingsAndVerifyReleaseClaims(app: XCUIApplication) {
        let settingsButton = app.buttons["settings-button"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        for _ in 0..<2 where !settingsScreenExists(app: app) {
            if settingsButton.isHittable {
                settingsButton.tap()
            }
            if waitForSettingsScreen(app: app) {
                break
            }
        }
        XCTAssertTrue(settingsScreenExists(app: app), "Settings screen did not appear")
        assertLabelExists("Default Mode: Interactive", app: app)
        assertLabelExists("Safe JavaScript: Disabled", app: app)
        assertLabelExists("Safe External Resources: Blocked", app: app)
        assertLabelExists("Imported Files: Stored in App", app: app)
        XCTAssertTrue(scrollUntilExists(app.buttons["clear-imported-files-button"], app: app))
        assertLabelExists("Processing: On Device", app: app)
        assertLabelExists("Account: None", app: app)
        assertLabelExists("Ads: None", app: app)
        app.buttons["settings-done-button"].tap()
        XCTAssertTrue(app.navigationBars["HTML Previewer"].waitForExistence(timeout: 5))
    }

    private func openSample(identifier: String, app: XCUIApplication) {
        let sample = app.buttons[identifier]
        let disclosure = app.descendants(matching: .any)["samples-disclosure"].firstMatch
        // List rows outside the viewport may not exist in the accessibility tree yet.
        // Find an already-expanded sample by scrolling before toggling its disclosure.
        if !sample.exists, disclosure.exists, !scrollUntilHittable(sample, app: app) {
            XCTAssertTrue(scrollUntilHittable(disclosure, app: app), "Missing samples disclosure")
            tapElement(disclosure, app: app)
        }
        XCTAssertTrue(scrollUntilHittable(sample, app: app), "Missing sample button: \(identifier)")
        sample.tap()
    }

    private func assertPDFExport(sample: String, heading: String, repeatExport: Bool = false) {
        continueAfterFailure = false
        let app = makeApp()
        app.launchArguments = ["--screenshot-reset-library", "--screenshot-sample=\(sample)"]
        launch(app)
        XCTAssertTrue(app.staticTexts[heading].waitForExistence(timeout: 10))
        attachScreenshot(named: "\(sample) rendered preview", app: app)
        exportPDFAndVerifyShareSheet(sample: sample, app: app)

        if repeatExport {
            if app.otherElements["PopoverDismissRegion"].exists {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
            } else {
                let close = app.buttons.matching(NSPredicate(
                    format: "label IN %@", ["Close", "閉じる", "关闭", "關閉"]
                )).firstMatch
                tapElement(close, app: app)
            }
            let shareButton = app.buttons["share-file-button"]
            let shareReady = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in shareButton.exists && shareButton.isHittable },
                object: nil
            )
            XCTAssertEqual(XCTWaiter.wait(for: [shareReady], timeout: 10), .completed)
            exportPDFAndVerifyShareSheet(sample: "\(sample) repeated export", app: app)
        }
    }

    private func exportPDFAndVerifyShareSheet(sample: String, app: XCUIApplication) {
        tapElement(app.buttons["share-file-button"], app: app)

        let export = app.buttons["Export PDF"]
        let enabledExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in export.exists && export.isEnabled },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [enabledExpectation], timeout: 10), .completed)
        tapElement(export, app: app)
        XCTAssertTrue(
            waitForAnyLabel(nativeShareOptionLabels, app: app, timeout: 20),
            "Export PDF did not present the native share sheet for \(sample)"
        )
        XCTAssertFalse(app.alerts["Cannot Export PDF"].exists)
        attachScreenshot(named: "\(sample) PDF share sheet", app: app)
    }

    private func waitUntilAbsent(_ element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !element.exists },
            object: nil
        )
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    private func attachScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openRawTextMode(app: XCUIApplication) {
        let modeMenu = app.buttons["preview-mode-menu"]
        XCTAssertTrue(modeMenu.waitForExistence(timeout: 10), "Missing preview mode menu")
        tapElement(modeMenu, app: app)
        let rawTextButton = app.buttons["Raw Text"]
        XCTAssertTrue(rawTextButton.waitForExistence(timeout: 5), "Missing Raw Text menu item")
        tapElement(rawTextButton, app: app)
    }

    private func assertLabelExists(_ label: String, app: XCUIApplication) {
        let element = app.descendants(matching: .any)[label]
        if !element.exists {
            for _ in 0..<4 where !element.exists {
                app.swipeUp()
                _ = element.waitForExistence(timeout: 1)
            }
        }
        XCTAssertTrue(element.exists, "Missing label: \(label)")
    }

    private func scrollUntilHittable(_ element: XCUIElement, app: XCUIApplication) -> Bool {
        for _ in 0..<6 {
            if element.waitForExistence(timeout: 1), element.isHittable {
                return true
            }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    private func scrollUntilExists(_ element: XCUIElement, app: XCUIApplication) -> Bool {
        for _ in 0..<6 {
            if element.waitForExistence(timeout: 1) {
                return true
            }
            app.swipeUp()
        }
        return element.exists
    }

    private func waitForSettingsScreen(app: XCUIApplication) -> Bool {
        for _ in 0..<15 {
            if settingsScreenExists(app: app) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        return settingsScreenExists(app: app)
    }

    private func waitForAnyLabel(
        _ labels: [String],
        app: XCUIApplication,
        timeout: TimeInterval = 10
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                labels.contains { app.descendants(matching: .any)[$0].exists }
            },
            object: nil
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func settingsScreenExists(app: XCUIApplication) -> Bool {
        app.navigationBars["Settings"].exists
            || app.collectionViews["settings-screen"].exists
            || app.staticTexts["Safe JavaScript: Disabled"].exists
    }

    private func navigateHome(app: XCUIApplication) {
        let backButton = app.navigationBars.buttons["HTML Previewer"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 10))
        backButton.tap()
        XCTAssertTrue(app.navigationBars["HTML Previewer"].waitForExistence(timeout: 5))
    }

    private func tapElement(
        _ element: XCUIElement,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Missing tappable element", file: file, line: line)
        if element.isHittable {
            element.tap()
            return
        }

        let frame = element.frame
        XCTAssertFalse(frame.isEmpty, "Element has an empty frame", file: file, line: line)
        let normalized = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        normalized.tap()
    }
}
