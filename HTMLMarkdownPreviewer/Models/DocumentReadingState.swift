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

/// The band a horizontal fold occupies while iPhone Duo is partially open,
/// as fractions of the reader viewport's height (0 is the top edge).
struct ReaderFoldBand: Equatable, Sendable {
    var top: Double
    var bottom: Double

    init?(top: Double, bottom: Double) {
        guard top.isFinite, bottom.isFinite, bottom > 0, top < 1, bottom > top else { return nil }
        self.top = max(0, top)
        self.bottom = min(1, bottom)
    }

    func range(inViewportHeight height: Double) -> ClosedRange<Double> {
        (top * height)...(bottom * height)
    }

    /// The viewport offset where a revealed target should begin. A target is
    /// placed above the fold when it fits there, otherwise below it, so it
    /// never straddles the crease. Without a fold this keeps the usual
    /// position a little above the middle of the viewport.
    static func revealTop(targetHeight: Double, viewportHeight: Double, fold: ReaderFoldBand?,
                          preferredFraction: Double = 0.35, margin: Double = 12) -> Double {
        let preferred = viewportHeight * preferredFraction
        guard let fold else { return preferred }
        let band = fold.range(inViewportHeight: viewportHeight)
        let aboveLimit = band.lowerBound - margin - targetHeight
        if aboveLimit >= margin { return min(preferred, aboveLimit) }
        return max(margin, min(band.upperBound + margin, viewportHeight - margin - targetHeight))
    }

    /// Whether a target already in view crosses the fold.
    func intersects(top: Double, bottom: Double, viewportHeight: Double) -> Bool {
        let band = range(inViewportHeight: viewportHeight)
        return bottom > band.lowerBound && top < band.upperBound
    }
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
    /// Present only while a fold divides the reader into upper and lower parts.
    var fold: ReaderFoldBand?

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
