import SwiftUI

struct DocumentDetailsView: View {
    let document: PreviewDocument
    let store: DocumentLibraryStore
    let previewMode: PreviewMode

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("File") {
                    LabeledContent("Name", value: document.originalFilename)
                    LabeledContent("Type", value: document.type.displayName)
                    LabeledContent("Entry Type", value: document.entryDocumentType.displayName)
                    LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: document.fileSize, countStyle: .file))
                }

                Section("Import") {
                    LabeledContent("Source", value: document.importSource.displayName)
                    LabeledContent("Imported", value: formatted(document.importedAt))
                    if let lastOpenedAt = document.lastOpenedAt {
                        LabeledContent("Last Opened", value: formatted(lastOpenedAt))
                    }
                    LabeledContent("Local Copy", value: "Stored in App")
                }

                Section("Preview") {
                    LabeledContent("Mode", value: previewMode.displayName)
                    LabeledContent("Entry Path", value: document.entryFileRelativePath)
                    LabeledContent("Root Path", value: document.localRootRelativePath)
                }

                if document.type == .zipPackage {
                    Section("ZIP") {
                        if let extractedFileCount = document.extractedFileCount {
                            LabeledContent("Files", value: "\(extractedFileCount)")
                        }
                        if let totalUncompressedBytes = document.totalUncompressedBytes {
                            LabeledContent("Expanded", value: ByteCountFormatter.string(fromByteCount: Int64(totalUncompressedBytes), countStyle: .file))
                        }
                    }
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

#Preview {
    DocumentDetailsView(
        document: PreviewDocument(
            displayName: "README",
            originalFilename: "README.md",
            fileExtension: "md",
            type: .markdown,
            importSource: .fileImporter,
            localRootRelativePath: "Imports/example",
            entryFileRelativePath: "original/README.md",
            fileSize: 128
        ),
        store: DocumentLibraryStore(),
        previewMode: .safePreview
    )
}
