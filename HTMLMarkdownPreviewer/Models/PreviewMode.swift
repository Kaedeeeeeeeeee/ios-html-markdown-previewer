import Foundation

enum PreviewMode: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case safePreview
    case interactive
    case rawText

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .safePreview:
            "Safe Preview"
        case .interactive:
            "Interactive"
        case .rawText:
            "Raw Text"
        }
    }

    var systemImage: String {
        switch self {
        case .safePreview:
            "lock.shield"
        case .interactive:
            "bolt"
        case .rawText:
            "doc.text"
        }
    }
}
