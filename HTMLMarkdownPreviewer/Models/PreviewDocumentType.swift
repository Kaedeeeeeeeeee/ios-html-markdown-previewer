import Foundation

enum PreviewDocumentType: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case html
    case markdown
    case zipPackage
    case plainText
    case unsupported

    var id: String {
        rawValue
    }
}
