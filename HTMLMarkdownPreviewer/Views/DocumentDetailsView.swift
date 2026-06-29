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
                    detailsRow("Name", value: document.originalFilename)
                    detailsRow("Type", value: document.type.displayName)
                    detailsRow("Entry Type", value: document.entryDocumentType.displayName)
                    detailsRow("Size", value: ByteCountFormatter.string(fromByteCount: document.fileSize, countStyle: .file))
                }

                Section("Import") {
                    detailsRow("Source", value: document.importSource.displayName)
                    detailsRow("Imported", value: formatted(document.importedAt))
                    if let lastOpenedAt = document.lastOpenedAt {
                        detailsRow("Last Opened", value: formatted(lastOpenedAt))
                    }
                    detailsRow("Local Copy", value: "Stored in App")
                }

                Section("Preview") {
                    detailsRow("Mode", value: previewMode.displayName)
                    detailsRow("External URLs", value: externalURLText)
                    detailsRow("Entry Path", value: document.entryFileRelativePath)
                    detailsRow("Root Path", value: document.localRootRelativePath)
                }

                if document.type == .zipPackage {
                    Section("ZIP") {
                        if let extractedFileCount = document.extractedFileCount {
                            detailsRow("Files", value: "\(extractedFileCount)")
                        }
                        if let totalUncompressedBytes = document.totalUncompressedBytes {
                            detailsRow("Expanded", value: ByteCountFormatter.string(fromByteCount: Int64(totalUncompressedBytes), countStyle: .file))
                        }
                    }
                }
            }
            .accessibilityIdentifier("document-details-screen")
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("document-details-done-button")
                }
            }
        }
    }

    private func detailsRow(_ title: String, value: String) -> some View {
        LabeledContent {
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        } label: {
            Text(title)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private var externalURLText: String {
        guard let count = document.externalURLCount else {
            return "Not scanned"
        }

        if count == 0 {
            return "None detected"
        }

        return "\(count) detected"
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
