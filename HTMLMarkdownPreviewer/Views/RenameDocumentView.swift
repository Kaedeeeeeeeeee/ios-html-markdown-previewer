import SwiftUI

struct RenameDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool
    let document: PreviewDocument
    let onSave: (String) throws -> Void
    @State private var name: String
    @State private var errorMessage: String?

    init(document: PreviewDocument, onSave: @escaping (String) throws -> Void) {
        self.document = document
        self.onSave = onSave
        _name = State(initialValue: document.displayName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(LibraryStrings.displayName, text: $name)
                        .focused($isNameFocused)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(save)
                        .accessibilityIdentifier("library-rename-field")
                } header: {
                    Text(LibraryStrings.displayName)
                } footer: {
                    Text(LibraryStrings.renameHint)
                }

                Section(LibraryStrings.originalFile) {
                    Label(document.originalFilename, systemImage: document.type.systemImage)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("library-rename-error")
                }
            }
            .navigationTitle(LibraryStrings.rename)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.Actions.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(LibraryStrings.save, action: save)
                        .disabled((try? DocumentLibraryStore.validatedDisplayName(name)) == nil)
                        .accessibilityIdentifier("library-rename-save")
                }
            }
            .onChange(of: name) { _, newValue in
                do {
                    _ = try DocumentLibraryStore.validatedDisplayName(newValue)
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { isNameFocused = true }
    }

    private func save() {
        do {
            try onSave(name)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
