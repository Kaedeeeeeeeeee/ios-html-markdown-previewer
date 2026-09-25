import SwiftUI

struct PastePreviewView: View {
    @Environment(\.dismiss) private var dismiss

    let store: DocumentLibraryStore
    let onImported: (PreviewDocument) -> Void

    @State private var text = ""
    @State private var name = ""
    @State private var format: PastedDocumentFormat = .markdown
    @State private var didChooseFormat = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var isTooLarge = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PasteButton(payloadType: String.self) { values in
                        guard let value = values.first else { return }
                        guard value.utf8.count <= PastedDocumentImportService.maximumUTF8Bytes else {
                            errorMessage = PasteStrings.contentTooLarge
                            return
                        }
                        text = value
                    }
                    .accessibilityIdentifier("paste-system-button")

                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 220)
                        .accessibilityLabel(PasteStrings.content)
                        .accessibilityIdentifier("paste-text-editor")
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text(PasteStrings.placeholder)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text(PasteStrings.content)
                } footer: {
                    Text(isTooLarge ? PasteStrings.contentTooLarge : PasteStrings.contentHint)
                        .foregroundStyle(isTooLarge ? Color.red : Color.secondary)
                }

                Section {
                    Picker(PasteStrings.format, selection: formatSelection) {
                        ForEach(PastedDocumentFormat.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("paste-format-picker")

                    TextField(PasteStrings.name, text: $name, prompt: Text(PasteStrings.defaultDocumentName))
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("paste-name-field")
                } header: {
                    Text(PasteStrings.document)
                } footer: {
                    Text(PasteStrings.documentHint)
                }
            }
            .navigationTitle(PasteStrings.title)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.Actions.cancel) { dismiss() }
                        .accessibilityIdentifier("paste-cancel-button")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(PasteStrings.preview) { importText() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTooLarge)
                        .accessibilityIdentifier("paste-open-button")
                }
            }
            .disabled(isImporting)
            .overlay {
                if isImporting {
                    ProgressView(PasteStrings.preparing)
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .onChange(of: text) { _, newValue in
            isTooLarge = newValue.utf8.count > PastedDocumentImportService.maximumUTF8Bytes
            if !didChooseFormat && !isTooLarge {
                format = PastedDocumentImportService.suggestedFormat(for: newValue)
            }
        }
        .alert(PasteStrings.cannotPreview, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(AppStrings.Actions.ok, role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var formatSelection: Binding<PastedDocumentFormat> {
        Binding(
            get: { format },
            set: {
                format = $0
                didChooseFormat = true
            }
        )
    }

    private func importText() {
        guard !isImporting else { return }
        isImporting = true
        Task { @MainActor in
            defer { isImporting = false }
            await Task.yield()
            do {
                let document = try PastedDocumentImportService(store: store)
                    .importDocument(text: text, name: name, format: format)
                onImported(document)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
