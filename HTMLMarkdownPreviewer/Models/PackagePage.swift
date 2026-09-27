import Foundation

/// A readable page in the extracted package. Identity stays relative to the package root.
struct PackagePage: Identifiable, Hashable, Sendable {
    let relativePath: String
    let title: String
    let fileURL: URL
    let documentType: PreviewDocumentType
    let isEntry: Bool

    var id: String { relativePath }

    var folderPath: String {
        relativePath.split(separator: "/").dropLast().joined(separator: "/")
    }
}
