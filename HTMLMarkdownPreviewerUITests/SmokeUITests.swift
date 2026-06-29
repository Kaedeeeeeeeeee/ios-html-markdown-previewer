import XCTest

@MainActor
final class SmokeUITests: XCTestCase {
    func testBuiltInSamplesAndSettingsSmoke() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--screenshot-reset-library"]
        app.launch()
        XCTAssertTrue(app.navigationBars["HTML Previewer"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["open-file-button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["open-zip-package-button"].waitForExistence(timeout: 5))

        openSettingsAndVerifyReleaseClaims(app: app)

        openSample(identifier: "sample-html", app: app)
        XCTAssertTrue(app.staticTexts["Safe Preview"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(identifier: "Scripts and external network resources are blocked. Relative assets are best effort for single files.").firstMatch.exists)
        navigateHome(app: app)

        openSample(identifier: "sample-markdown", app: app)
        XCTAssertTrue(app.staticTexts["Markdown Preview Sample"].waitForExistence(timeout: 10))
        navigateHome(app: app)

        openSample(identifier: "sample-zipPackage", app: app)
        XCTAssertTrue(app.staticTexts["Safe Preview"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(identifier: "Scripts and external network resources are blocked.").firstMatch.exists)
        navigateHome(app: app)

        let recentZIPSample = app.buttons["recent-document-sample-report.zip"]
        XCTAssertTrue(scrollUntilExists(recentZIPSample, app: app), "Missing recent ZIP sample row")
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
        XCTAssertTrue(scrollUntilHittable(sample, app: app), "Missing sample button: \(identifier)")
        sample.tap()
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
}
