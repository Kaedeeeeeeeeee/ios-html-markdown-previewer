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
    var originalFileRelativePath: String
    var entryFileRelativePath: String
    var entryDocumentType: PreviewDocumentType
    var fileSize: Int64
    var extractedFileCount: Int?
    var totalUncompressedBytes: UInt64?
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
        originalFileRelativePath: String? = nil,
        entryFileRelativePath: String,
        entryDocumentType: PreviewDocumentType? = nil,
        fileSize: Int64,
        extractedFileCount: Int? = nil,
        totalUncompressedBytes: UInt64? = nil,
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
        self.originalFileRelativePath = originalFileRelativePath ?? entryFileRelativePath
        self.entryFileRelativePath = entryFileRelativePath
        self.entryDocumentType = entryDocumentType ?? type
        self.fileSize = fileSize
        self.extractedFileCount = extractedFileCount
        self.totalUncompressedBytes = totalUncompressedBytes
        self.lastOpenedAt = lastOpenedAt
        self.preferredPreviewMode = preferredPreviewMode
    }
}
