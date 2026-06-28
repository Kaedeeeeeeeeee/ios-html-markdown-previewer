import Foundation

struct PreviewDocument: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var displayName: String
    var originalFilename: String
    var fileExtension: String
    var type: PreviewDocumentType
    var importSource: ImportSource
    var importedAt: Date
    var localRootRelativePath: String
    var entryFileRelativePath: String
    var fileSize: Int64
    var lastOpenedAt: Date?
    var preferredPreviewMode: PreviewMode

    init(
        id: UUID = UUID(),
        displayName: String,
        originalFilename: String,
        fileExtension: String,
        type: PreviewDocumentType,
        importSource: ImportSource,
        importedAt: Date = Date(),
        localRootRelativePath: String,
        entryFileRelativePath: String,
        fileSize: Int64,
        lastOpenedAt: Date? = nil,
        preferredPreviewMode: PreviewMode = .safePreview
    ) {
        self.id = id
        self.displayName = displayName
        self.originalFilename = originalFilename
        self.fileExtension = fileExtension
        self.type = type
        self.importSource = importSource
        self.importedAt = importedAt
        self.localRootRelativePath = localRootRelativePath
        self.entryFileRelativePath = entryFileRelativePath
        self.fileSize = fileSize
        self.lastOpenedAt = lastOpenedAt
        self.preferredPreviewMode = preferredPreviewMode
    }
}
