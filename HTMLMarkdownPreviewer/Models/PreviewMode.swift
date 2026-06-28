import Foundation

enum PreviewMode: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case safePreview
    case interactive
    case rawText

    var id: String {
        rawValue
    }
}
