import SwiftUI

struct DocumentPreviewView: View {
    let document: PreviewDocument
    let store: DocumentLibraryStore

    @State private var state: PreviewContentState = .loading
    @State private var previewMode: PreviewMode
    @State private var isInteractiveConfirmationPresented = false

    init(document: PreviewDocument, store: DocumentLibraryStore) {
        self.document = document
        self.store = store
        self._previewMode = State(initialValue: document.preferredPreviewMode)
    }

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView()
            case .markdown(let markdownDocument):
                MarkdownPreviewView(document: markdownDocument)
            case .html(let fileURL, let readAccessRootURL, let mode):
                HTMLPreviewView(fileURL: fileURL, readAccessRootURL: readAccessRootURL, mode: mode)
            case .rawText(let text):
                RawTextPreview(text: text)
            case .unsupported:
                ContentUnavailableView(
                    "Preview Unavailable",
                    systemImage: "doc.badge.questionmark",
                    description: Text("This entry type is not supported yet.")
                )
            case .failed(let message):
                ContentUnavailableView(
                    "Cannot Open File",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            }
        }
        .navigationTitle(document.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if document.entryDocumentType == .html {
                    Menu {
                        Button {
                            setPreviewMode(.safePreview)
                        } label: {
                            Label("Safe Preview", systemImage: previewMode == .safePreview ? "checkmark.shield" : "lock.shield")
                        }

                        Button {
                            isInteractiveConfirmationPresented = true
                        } label: {
                            Label("Interactive Mode", systemImage: previewMode == .interactive ? "checkmark.circle" : "bolt")
                        }

                        Button {
                            setPreviewMode(.rawText)
                        } label: {
                            Label("Raw Text", systemImage: previewMode == .rawText ? "checkmark.circle" : "doc.text")
                        }
                    } label: {
                        Image(systemName: previewModeIcon)
                    }
                }

                Menu {
                    LabeledContent("Type", value: document.type.displayName)
                    LabeledContent("Entry", value: document.entryDocumentType.displayName)
                    LabeledContent("Source", value: document.importSource.displayName)
                    LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: document.fileSize, countStyle: .file))
                    if let extractedFileCount = document.extractedFileCount {
                        LabeledContent("Files", value: "\(extractedFileCount)")
                    }
                } label: {
                    Image(systemName: "info.circle")
                }
            }
        }
        .onAppear(perform: loadPreview)
        .onChange(of: previewMode) {
            loadPreview()
        }
        .confirmationDialog("Use Interactive Mode?", isPresented: $isInteractiveConfirmationPresented) {
            Button("Use Interactive Mode") {
                setPreviewMode(.interactive)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only use interactive mode for HTML files you trust.")
        }
    }

    private func loadPreview() {
        do {
            let entryFileURL = store.entryFileURL(for: document)
            switch document.entryDocumentType {
            case .markdown:
                if previewMode == .rawText {
                    state = .rawText(try String(contentsOf: entryFileURL, encoding: .utf8))
                } else {
                    state = .markdown(try MarkdownRenderService().render(fileURL: entryFileURL))
                }
            case .html:
                if previewMode == .rawText {
                    state = .rawText(try String(contentsOf: entryFileURL, encoding: .utf8))
                } else {
                    state = .html(
                        fileURL: entryFileURL,
                        readAccessRootURL: readAccessRootURL(for: document),
                        mode: previewMode.htmlPreviewMode
                    )
                }
            case .zipPackage, .plainText, .unsupported:
                state = .unsupported
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private var previewModeIcon: String {
        switch previewMode {
        case .safePreview:
            "lock.shield"
        case .interactive:
            "bolt"
        case .rawText:
            "doc.text"
        }
    }

    private func setPreviewMode(_ mode: PreviewMode) {
        previewMode = mode
    }

    private func readAccessRootURL(for document: PreviewDocument) -> URL {
        if document.type == .zipPackage {
            return store.documentRootURL(for: document).appendingPathComponent("extracted", isDirectory: true)
        }

        return store.entryFileURL(for: document).deletingLastPathComponent()
    }
}

private enum PreviewContentState {
    case loading
    case markdown(MarkdownDocument)
    case html(fileURL: URL, readAccessRootURL: URL, mode: HTMLPreviewMode)
    case rawText(String)
    case unsupported
    case failed(String)
}

private extension PreviewMode {
    var htmlPreviewMode: HTMLPreviewMode {
        switch self {
        case .interactive:
            .interactive
        case .safePreview, .rawText:
            .safePreview
        }
    }
}

private struct RawTextPreview: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemBackground))
    }
}

#Preview {
    NavigationStack {
        DocumentPreviewView(
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
            store: DocumentLibraryStore()
        )
    }
}
