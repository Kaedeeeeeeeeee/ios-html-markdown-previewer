import SwiftUI

struct DocumentDetailsView: View {
    let document: PreviewDocument
    let store: DocumentLibraryStore
    let previewMode: PreviewMode

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(AppStrings.Details.fileSection) {
                    detailsRow(AppStrings.Details.name, value: document.originalFilename)
                    detailsRow(AppStrings.Details.type, value: document.type.displayName)
                    detailsRow(AppStrings.Details.entryType, value: document.entryDocumentType.displayName)
                    detailsRow(AppStrings.Details.size, value: AppFormatters.byteCount(document.fileSize))
                }

                Section(AppStrings.Details.importSection) {
                    detailsRow(AppStrings.Details.source, value: document.importSource.displayName)
                    detailsRow(AppStrings.Details.imported, value: formatted(document.importedAt))
                    if let lastOpenedAt = document.lastOpenedAt {
                        detailsRow(AppStrings.Details.lastOpened, value: formatted(lastOpenedAt))
                    }
                    detailsRow(AppStrings.Details.localCopy, value: AppStrings.Settings.storedInApp)
                }

                Section(AppStrings.Details.previewSection) {
                    detailsRow(AppStrings.Details.mode, value: previewMode.displayName)
                    detailsRow(AppStrings.Details.externalURLs, value: externalURLText)
                    detailsRow(AppStrings.Details.entryPath, value: document.entryFileRelativePath)
                    detailsRow(AppStrings.Details.rootPath, value: document.localRootRelativePath)
                }

                if document.type == .zipPackage {
                    Section(AppStrings.Details.zipSection) {
                        if let extractedFileCount = document.extractedFileCount {
                            detailsRow(AppStrings.Settings.files, value: "\(extractedFileCount)")
                        }
                        if let totalUncompressedBytes = document.totalUncompressedBytes {
                            detailsRow(
                                AppStrings.Settings.expanded,
                                value: AppFormatters.byteCount(Int64(totalUncompressedBytes))
                            )
                        }
                    }
                }
            }
            .accessibilityIdentifier("document-details-screen")
            .navigationTitle(AppStrings.Details.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppStrings.Actions.done) {
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
        AppFormatters.dateTime(date)
    }

    private var externalURLText: String {
        guard let count = document.externalURLCount else {
            return AppStrings.Details.notScanned
        }

        if count == 0 {
            return AppStrings.Details.noneDetected
        }

        return AppStrings.Details.detectedExternalURLs(count)
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
