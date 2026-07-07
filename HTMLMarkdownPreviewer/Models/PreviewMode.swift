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
            AppStrings.PreviewModes.safePreview
        case .interactive:
            AppStrings.PreviewModes.interactive
        case .rawText:
            AppStrings.PreviewModes.rawText
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
