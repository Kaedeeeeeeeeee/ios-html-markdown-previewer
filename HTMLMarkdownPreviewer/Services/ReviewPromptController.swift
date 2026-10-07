import Foundation
import Observation

/// Local engagement only. A request is an attempt, not proof that StoreKit showed a prompt or received a rating.
@MainActor
@Observable
final class ReviewPromptController {
    static let minimumReadingSeconds: TimeInterval = 30
    static let minimumReadings = 5
    static let minimumReadingDays = 3
    static let requestCooldown: TimeInterval = 120 * 24 * 60 * 60
    static let storageKey = "reviews.engagement.v1"

    private(set) var pendingRequestID: UUID?
    private var state: Engagement
    private let defaults: UserDefaults
    private let version: String
    private let isEnabled: Bool
    private let calendar: Calendar

    private struct Engagement: Codable {
        var completedReadings = 0
        var readingDays = Set<String>()
        var latestReadingDay: String?
        var documentsReadOnLatestDay = Set<UUID>()
        var lastRequestedAt: Date?
        var lastRequestedVersion: String?
    }

    init(defaults: UserDefaults = .standard,
         version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
         isEnabled: Bool = true,
         calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.defaults = defaults
        self.version = version
        self.isEnabled = isEnabled
        self.calendar = calendar
        self.state = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(Engagement.self, from: $0) } ?? Engagement()
    }

    func recordCompletedReading(documentID: UUID, source: ImportSource,
                                activeSeconds: TimeInterval, at date: Date = Date()) {
        guard isEnabled, source != .bundledSample,
              activeSeconds.isFinite, activeSeconds >= Self.minimumReadingSeconds else { return }

        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let day = "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
        if state.latestReadingDay != day {
            state.latestReadingDay = day
            state.documentsReadOnLatestDay.removeAll()
        }
        // Reopening the same document on the same day isn't additional engagement.
        guard !state.documentsReadOnLatestDay.contains(documentID) else { return }
        if state.completedReadings < Self.minimumReadings || state.readingDays.count < Self.minimumReadingDays {
            state.documentsReadOnLatestDay.insert(documentID)
            state.completedReadings = min(Self.minimumReadings, state.completedReadings + 1)
            if state.readingDays.count < Self.minimumReadingDays { state.readingDays.insert(day) }
            save()
        }
        if canRequest(at: date) { pendingRequestID = UUID() }
    }

    func canRequest(at date: Date = Date()) -> Bool {
        guard isEnabled, !version.isEmpty,
              state.completedReadings >= Self.minimumReadings,
              state.readingDays.count >= Self.minimumReadingDays,
              state.lastRequestedVersion != version else { return false }
        if let lastRequestedAt = state.lastRequestedAt {
            return date.timeIntervalSince(lastRequestedAt) >= Self.requestCooldown
        }
        return true
    }

    /// Consume only immediately before calling StoreKit; a canceled delay must not consume the opportunity.
    func consumeRequest(_ id: UUID, at date: Date = Date()) -> Bool {
        guard pendingRequestID == id, canRequest(at: date) else { return false }
        state.lastRequestedAt = date
        state.lastRequestedVersion = version
        state.completedReadings = 0
        state.readingDays.removeAll()
        pendingRequestID = nil
        save()
        return true
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

/// Monotonic time excludes background, loading, and covered-reader intervals.
struct ReviewReadingSession {
    private var startedAt: TimeInterval?
    private(set) var activeSeconds: TimeInterval = 0

    mutating func setActive(_ isActive: Bool, at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if isActive {
            if startedAt == nil { startedAt = uptime }
        } else if let startedAt {
            activeSeconds += max(0, uptime - startedAt)
            self.startedAt = nil
        }
    }
}
