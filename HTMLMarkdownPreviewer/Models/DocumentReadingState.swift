import Foundation
import Observation

struct DocumentHeading: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let level: Int
}

struct ReadingPosition: Codable, Hashable, Sendable {
    var anchorID: String?
    var progress: Double

    init(anchorID: String? = nil, progress: Double) {
        self.anchorID = anchorID
        self.progress = progress.isFinite ? min(1, max(0, progress)) : 0
    }
}

struct ReadingNavigationRequest: Equatable {
    enum Target: Equatable {
        case heading(String)
        case match(Int)
        case beginning
    }

    let id = UUID()
    let target: Target
}

@MainActor
@Observable
final class DocumentReadingState {
    var query = ""
    var headings: [DocumentHeading] = []
    var matchCount = 0
    var selectedMatch = -1
    var isReady = false
    var position: ReadingPosition?
    var navigationRequest: ReadingNavigationRequest?

    init(position: ReadingPosition? = nil) {
        self.position = position
    }

    func navigate(to target: ReadingNavigationRequest.Target) {
        navigationRequest = ReadingNavigationRequest(target: target)
    }

    func moveMatch(forward: Bool) {
        guard matchCount > 0 else { return }
        let next = selectedMatch < 0 ? 0
            : (selectedMatch + (forward ? 1 : matchCount - 1)) % matchCount
        selectedMatch = next
        navigate(to: .match(next))
    }

    func resetContent() {
        headings = []
        matchCount = 0
        selectedMatch = -1
        isReady = false
        navigationRequest = nil
    }
}
