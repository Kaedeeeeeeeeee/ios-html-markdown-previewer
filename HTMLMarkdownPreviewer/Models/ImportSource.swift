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
            "File Picker"
        case .externalOpen:
            "External Open"
        case .zipArchive:
            "ZIP Archive"
        case .bundledSample:
            "Built-in Sample"
        }
    }
}
