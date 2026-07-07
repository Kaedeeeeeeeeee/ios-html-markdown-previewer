import Foundation

enum ImportSource: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case fileImporter
    case externalOpen
    case zipArchive
    case bundledSample

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .fileImporter:
            AppStrings.ImportSources.filePicker
        case .externalOpen:
            AppStrings.ImportSources.externalOpen
        case .zipArchive:
            AppStrings.ImportSources.zipArchive
        case .bundledSample:
            AppStrings.ImportSources.builtInSample
        }
    }
}
