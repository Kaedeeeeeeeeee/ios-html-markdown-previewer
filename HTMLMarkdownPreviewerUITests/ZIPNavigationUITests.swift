import XCTest

@MainActor
final class ZIPNavigationUITests: XCTestCase {
    func testPackagePagesSearchLinksBackAndLastPageSurviveRelaunch() throws {
        continueAfterFailure = false
        let token = UUID().uuidString
        let filename = "QA-Package-\(token).zip"
        let app = XCUIApplication()
        app.launchEnvironment["HTML_PREVIEWER_UI_TESTS"] = "1"
        let arguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchArguments = arguments + ["--package-fixture=\(token)"]
        app.launch()
        defer {
            app.terminate()
            app.launchArguments = arguments + ["--package-cleanup=\(token)"]
            app.launch()
            XCTAssertTrue(app.buttons["paste-preview-button"].waitForExistence(timeout: 15))
            XCTAssertFalse(app.buttons["recent-document-\(filename)"].exists)
        }
        let row = app.buttons["recent-document-\(filename)"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        waitForPage("index.html", app: app)
        XCTAssertFalse(app.buttons["package-back-button"].isEnabled)
        capture("ZIP overview with compact package navigation", app: app)

        app.buttons["package-pages-button"].tap()
        let details = app.buttons["package-page-chapters/details.html"]
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["package-page-index.html"].exists)
        XCTAssertTrue(app.buttons["package-page-appendix/notes.md"].exists)
        capture("Package page picker with titles paths and current page", app: app)
        let search = app.searchFields.firstMatch
        if !search.exists {
            // iOS 27.1 can initially present searchable as a toolbar button.
            let searchButton = app.buttons.matching(NSPredicate(format: "label == %@", "Search")).firstMatch
            XCTAssertTrue(wait { searchButton.exists && searchButton.isHittable },
                          "The page picker must expose a tappable Search button when its field is collapsed")
            searchButton.tap()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("details")
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["package-page-index.html"].exists)
        details.tap()
        waitForPage("chapters/details.html", app: app)
        XCTAssertTrue(app.staticTexts["Reading in detail"].exists)
        XCTAssertTrue(app.buttons["package-back-button"].isEnabled)
        capture("Nested HTML report with relative assets", app: app)

        app.buttons["package-pages-button"].tap()
        let notes = app.buttons["package-page-appendix/notes.md"]
        XCTAssertTrue(notes.waitForExistence(timeout: 10))
        notes.tap()
        waitForPage("appendix/notes.md", app: app)
        XCTAssertTrue(app.staticTexts["Notes & method"].exists)
        capture("Markdown appendix inside the same ZIP", app: app)

        app.buttons["preview-mode-menu"].tap()
        app.buttons["Raw Text"].tap()
        XCTAssertTrue(wait { app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "# Notes & method")).count > 0 })
        XCTAssertEqual(app.buttons["package-pages-button"].value as? String, "appendix/notes.md")
        app.buttons["preview-mode-menu"].tap()
        app.buttons["Rendered Preview"].tap()
        waitForPage("appendix/notes.md", app: app)
        app.buttons["package-back-button"].tap()
        waitForPage("chapters/details.html", app: app)
        capture("Previous page returns to the report", app: app)

        let appendixLink = app.webViews.links.matching(NSPredicate(format: "label CONTAINS %@", "Notes & method")).firstMatch
        reveal(appendixLink, app: app)
        appendixLink.tap()
        waitForPage("appendix/notes.md", app: app)

        navigateHome(app)
        app.terminate()
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        waitForPage("appendix/notes.md", app: app)
        XCTAssertFalse(app.buttons["package-back-button"].isEnabled, "History starts fresh when reopening; the selected page persists.")
        capture("ZIP reopens its last selected page", app: app)

        // Both native and enhanced Markdown should route an allowed relative link
        // back into this package instead of opening a browser or a second window.
        let overview = app.webViews.links.matching(NSPredicate(format: "label CONTAINS %@", "Back to overview")).firstMatch
        reveal(overview, app: app)
        overview.tap()
        waitForPage("index.html", app: app)
        app.buttons["package-back-button"].tap()
        waitForPage("appendix/notes.md", app: app)
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

    private func waitForPage(_ path: String, app: XCUIApplication) {
        XCTAssertTrue(wait(timeout: 45) {
            let pages = app.buttons["package-pages-button"]
            let tools = app.buttons["reading-tools-menu"]
            return pages.exists && pages.value as? String == path && tools.exists && tools.isEnabled
        }, "Expected ready package page: \(path)")
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            if app.webViews.firstMatch.exists { app.webViews.firstMatch.swipeUp() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func wait(timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
