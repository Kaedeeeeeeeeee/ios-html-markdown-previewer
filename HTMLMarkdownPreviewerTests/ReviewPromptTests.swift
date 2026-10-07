import XCTest
@testable import HTMLMarkdownPreviewer

@MainActor
final class ReviewPromptTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let day: TimeInterval = 24 * 60 * 60
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        suiteName = "ReviewPromptTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func controller(version: String = "1.7", enabled: Bool = true) -> ReviewPromptController {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return ReviewPromptController(defaults: defaults, version: version, isEnabled: enabled, calendar: calendar)
    }

    private func read(_ controller: ReviewPromptController, dayOffset: Double = 0,
                      id: UUID = UUID(), seconds: TimeInterval = 30, source: ImportSource = .fileImporter) {
        controller.recordCompletedReading(documentID: id, source: source, activeSeconds: seconds,
                                          at: start.addingTimeInterval(dayOffset * day))
    }

    private func qualify(_ controller: ReviewPromptController, offset: Double = 0) {
        for delta in [0.0, 0, 1, 1, 2] { read(controller, dayOffset: offset + delta) }
    }

    func testFiveReadingsMustAlsoSpanThreeDates() {
        let prompt = controller()
        for _ in 0..<5 { read(prompt) }
        XCTAssertFalse(prompt.canRequest(at: start))
        read(prompt, dayOffset: 1)
        XCTAssertNil(prompt.pendingRequestID)
        read(prompt, dayOffset: 2)
        XCTAssertTrue(prompt.canRequest(at: start.addingTimeInterval(2 * day)))
        XCTAssertNotNil(prompt.pendingRequestID)
    }

    func testThreeDatesAreInsufficientBeforeFifthReading() {
        let prompt = controller()
        for delta in [0.0, 1, 2, 2] { read(prompt, dayOffset: delta) }
        XCTAssertNil(prompt.pendingRequestID)
        read(prompt, dayOffset: 2, source: .pastedText)
        XCTAssertNotNil(prompt.pendingRequestID)
    }

    func testShortReadingsSamplesAndInvalidDurationsDoNotCount() {
        let prompt = controller()
        for delta in [0.0, 1, 2, 3, 4] {
            read(prompt, dayOffset: delta, seconds: 29.99)
            read(prompt, dayOffset: delta, seconds: 300, source: .bundledSample)
            read(prompt, dayOffset: delta, seconds: .infinity)
            read(prompt, dayOffset: delta, seconds: .nan)
        }
        XCTAssertNil(defaults.data(forKey: ReviewPromptController.storageKey))
        XCTAssertNil(prompt.pendingRequestID)
    }

    func testSameDocumentCountsOncePerLocalDate() {
        let prompt = controller()
        let id = UUID()
        for delta in [0.0, 1, 2] {
            for _ in 0..<5 { read(prompt, dayOffset: delta, id: id) }
        }
        XCTAssertNil(prompt.pendingRequestID)
        read(prompt, dayOffset: 2)
        read(prompt, dayOffset: 2)
        XCTAssertNotNil(prompt.pendingRequestID)
    }

    func testLocalDatesRespectTimeZoneAcrossMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 60 * 60)!
        let prompt = ReviewPromptController(defaults: defaults, version: "1.7", calendar: calendar)
        let beforeMidnight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 23, minute: 59))!
        let id = UUID()
        let thirdDate = beforeMidnight.addingTimeInterval(day + 120)
        for date in [beforeMidnight, beforeMidnight.addingTimeInterval(120), thirdDate] {
            prompt.recordCompletedReading(documentID: id, source: .fileImporter, activeSeconds: 30, at: date)
        }
        for _ in 0..<2 {
            prompt.recordCompletedReading(documentID: UUID(), source: .fileImporter, activeSeconds: 30,
                                          at: thirdDate)
        }
        XCTAssertNotNil(prompt.pendingRequestID)
    }

    func testEngagementPersistsButLaunchAloneDoesNotCreateRequest() {
        qualify(controller())
        let restored = controller()
        XCTAssertTrue(restored.canRequest(at: start.addingTimeInterval(2 * day)))
        XCTAssertNil(restored.pendingRequestID)
        read(restored, dayOffset: 3)
        XCTAssertNotNil(restored.pendingRequestID)
    }

    func testOnlyCurrentOpportunityCanBeConsumedAndSameVersionNeverRepeats() throws {
        let prompt = controller()
        qualify(prompt)
        let id = try XCTUnwrap(prompt.pendingRequestID)
        XCTAssertFalse(prompt.consumeRequest(UUID(), at: start.addingTimeInterval(2 * day)))
        XCTAssertEqual(prompt.pendingRequestID, id)
        XCTAssertTrue(prompt.consumeRequest(id, at: start.addingTimeInterval(2 * day)))
        XCTAssertFalse(prompt.consumeRequest(id, at: start.addingTimeInterval(2 * day)))
        let restored = controller()
        qualify(restored, offset: 400)
        XCTAssertFalse(restored.canRequest(at: start.addingTimeInterval(402 * day)))
        XCTAssertNil(restored.pendingRequestID)
    }

    func testNewVersionRequiresAdditionalEngagementAndFullCooldown() throws {
        let old = controller()
        qualify(old)
        let requestedAt = start.addingTimeInterval(2 * day)
        XCTAssertTrue(old.consumeRequest(try XCTUnwrap(old.pendingRequestID), at: requestedAt))
        let updated = controller(version: "1.8")
        XCTAssertFalse(updated.canRequest(at: requestedAt.addingTimeInterval(400 * day)))
        qualify(updated, offset: 3)
        XCTAssertFalse(updated.canRequest(at: requestedAt.addingTimeInterval(120 * day - 1)))
        XCTAssertTrue(updated.canRequest(at: requestedAt.addingTimeInterval(120 * day)))
        XCTAssertNil(updated.pendingRequestID)
        read(updated, dayOffset: 122)
        XCTAssertNotNil(updated.pendingRequestID)
    }

    func testDisabledTestsAndMissingVersionNeverRequest() {
        let disabled = controller(enabled: false)
        qualify(disabled)
        XCTAssertNil(defaults.data(forKey: ReviewPromptController.storageKey))
        XCTAssertNil(disabled.pendingRequestID)
        let missingVersion = controller(version: "")
        qualify(missingVersion)
        XCTAssertFalse(missingVersion.canRequest(at: start.addingTimeInterval(2 * day)))
        XCTAssertNil(missingVersion.pendingRequestID)
    }

    func testForegroundClockPausesAndRepeatedActiveSignalsDoNotRestartIt() {
        var session = ReviewReadingSession()
        session.setActive(true, at: 100)
        session.setActive(true, at: 105)
        session.setActive(false, at: 110)
        session.setActive(false, at: 500)
        session.setActive(true, at: 600)
        session.setActive(false, at: 620)
        XCTAssertEqual(session.activeSeconds, 30)
    }
}
