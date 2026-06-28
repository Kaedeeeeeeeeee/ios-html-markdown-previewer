import XCTest

@MainActor
final class SmokeUITests: XCTestCase {
    func testBuiltInSamplesAndSettingsSmoke() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--screenshot-reset-library"]
        app.launch()
        XCTAssertTrue(app.navigationBars["HTML Previewer"].waitForExistence(timeout: 10))

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

        XCTAssertTrue(app.staticTexts["Recent"].waitForExistence(timeout: 5))
    }

    private func openSettingsAndVerifyReleaseClaims(app: XCUIApplication) {
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["Safe JavaScript: Disabled"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Safe External Resources: Blocked"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Processing: On Device"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Account: None"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Ads: None"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["HTML Previewer"].waitForExistence(timeout: 5))
    }

    private func openSample(identifier: String, app: XCUIApplication) {
        let sample = app.buttons[identifier]
        XCTAssertTrue(sample.waitForExistence(timeout: 5), "Missing sample button: \(identifier)")
        sample.tap()
    }

    private func navigateHome(app: XCUIApplication) {
        let backButton = app.navigationBars.buttons["HTML Previewer"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 10))
        backButton.tap()
        XCTAssertTrue(app.navigationBars["HTML Previewer"].waitForExistence(timeout: 5))
    }
}
