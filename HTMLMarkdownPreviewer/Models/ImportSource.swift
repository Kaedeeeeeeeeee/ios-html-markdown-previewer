import Foundation

enum ImportSource: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case fileImporter
    case externalOpen
    case zipArchive
    case bundledSample

    var id: String {
        rawValue
    }
}
