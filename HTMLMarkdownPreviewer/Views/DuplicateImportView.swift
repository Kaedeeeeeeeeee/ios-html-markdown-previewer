import SwiftUI

struct DuplicateImportView: View {
    let prepared: PreparedDocumentImport
    let onResolve: (DocumentImportResolution) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(LibraryStrings.alreadyInLibrary)
                                .font(.headline)
                            Text(prepared.duplicate?.hasIdenticalContents == true ? LibraryStrings.sameContent : LibraryStrings.sameFilename)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(.tint)
                    }
                    .padding(.vertical, 8)
                }

                if let existing = prepared.duplicate?.document {
                    Section(LibraryStrings.existingFile) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(existing.displayName).font(.headline)
                            Text(existing.originalFilename)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(AppFormatters.byteCount(existing.fileSize))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    Button {
                        onResolve(.updateExisting)
                    } label: {
                        Label(LibraryStrings.updateExisting, systemImage: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityIdentifier("duplicate-update-button")

                    Button {
                        onResolve(.keepBoth)
                    } label: {
                        Label(LibraryStrings.keepBoth, systemImage: "plus.square.on.square")
                    }
                    .accessibilityIdentifier("duplicate-keep-both-button")
                } header: {
                    Text(prepared.document.originalFilename)
                } footer: {
                    Text(LibraryStrings.updateHint)
                }
            }
            .navigationTitle(LibraryStrings.importFile)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.Actions.cancel, action: onCancel)
                        .accessibilityIdentifier("duplicate-cancel-button")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
