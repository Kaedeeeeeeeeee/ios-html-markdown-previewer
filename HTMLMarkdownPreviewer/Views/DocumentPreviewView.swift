import SwiftUI

struct DocumentPreviewView: View {
    let store: DocumentLibraryStore

    @State private var document: PreviewDocument
    @State private var state: PreviewContentState = .loading
    @State private var previewMode: PreviewMode
    @State private var isInteractiveConfirmationPresented = false
    @State private var isDetailsPresented = false

    init(document: PreviewDocument, store: DocumentLibraryStore) {
        self.store = store
        self._document = State(initialValue: document)
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
                    AppStrings.Errors.previewUnavailableTitle,
                    systemImage: "doc.badge.questionmark",
                    description: Text(AppStrings.Errors.unsupportedEntryType)
                )
            case .failed(let message):
                ContentUnavailableView(
                    AppStrings.Errors.cannotOpenFileTitle,
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            }
        }
        .navigationTitle(document.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let status = previewStatus {
                PreviewStatusBar(status: status)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if supportsPreviewModeMenu {
                    Menu {
                        previewModeButtons
                    } label: {
                        Image(systemName: previewModeIcon)
                    }
                    .accessibilityLabel("Preview Mode")
                    .accessibilityIdentifier("preview-mode-menu")
                }

                ShareLink(item: store.entryFileURL(for: document)) {
                    Image(systemName: "square.and.arrow.up")
                }

                Button {
                    isDetailsPresented = true
                } label: {
                    Image(systemName: "info.circle")
                }
            }
        }
        .onAppear(perform: loadPreview)
        .onChange(of: previewMode) {
            loadPreview()
        }
        .confirmationDialog(AppStrings.Security.interactiveModeTitle, isPresented: $isInteractiveConfirmationPresented) {
            Button(AppStrings.Security.useInteractiveMode) {
                setPreviewMode(.interactive)
            }
            Button(AppStrings.Actions.cancel, role: .cancel) {}
        } message: {
            Text(AppStrings.Security.interactiveModeConfirmation)
        }
        .sheet(isPresented: $isDetailsPresented) {
            DocumentDetailsView(document: document, store: store, previewMode: previewMode)
        }
    }

    private func loadPreview() {
        do {
            let entryFileURL = store.entryFileURL(for: document)
            switch document.entryDocumentType {
            case .markdown:
                if previewMode == .rawText {
                    state = .rawText(try TextFileReader().readText(from: entryFileURL))
                } else {
                    state = .markdown(try MarkdownRenderService().render(
                        fileURL: entryFileURL,
                        readAccessRootURL: readAccessRootURL(for: document)
                    ))
                }
            case .html:
                if previewMode == .rawText {
                    state = .rawText(try TextFileReader().readText(from: entryFileURL))
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
        previewMode.systemImage
    }

    private var supportsPreviewModeMenu: Bool {
        document.entryDocumentType == .html || document.entryDocumentType == .markdown
    }

    @ViewBuilder
    private var previewModeButtons: some View {
        if document.entryDocumentType == .markdown {
            Button {
                setPreviewMode(.safePreview)
            } label: {
                Label(
                    "Rendered Preview",
                    systemImage: previewMode == .rawText ? "text.alignleft" : "checkmark.circle"
                )
            }

            Button {
                setPreviewMode(.rawText)
            } label: {
                Label("Raw Text", systemImage: previewMode == .rawText ? "checkmark.circle" : "doc.text")
            }
        } else {
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
        }
    }

    private var previewStatus: PreviewStatus? {
        if previewMode == .rawText {
            return PreviewStatus(
                title: PreviewMode.rawText.displayName,
                message: AppStrings.Security.rawTextStatus,
                systemImage: PreviewMode.rawText.systemImage
            )
        }

        guard document.entryDocumentType == .html else {
            return nil
        }

        switch previewMode {
        case .safePreview:
            return PreviewStatus(
                title: PreviewMode.safePreview.displayName,
                message: document.type == .zipPackage
                    ? AppStrings.Security.safeHTMLZipStatus
                    : AppStrings.Security.safeHTMLSingleFileStatus,
                systemImage: PreviewMode.safePreview.systemImage
            )
        case .interactive:
            return PreviewStatus(
                title: PreviewMode.interactive.displayName,
                message: AppStrings.Security.interactiveHTMLStatus,
                systemImage: PreviewMode.interactive.systemImage
            )
        case .rawText:
            return nil
        }
    }

    private func setPreviewMode(_ mode: PreviewMode) {
        guard previewMode != mode else {
            return
        }

        previewMode = mode
        persistPreviewMode(mode)
    }

    private func persistPreviewMode(_ mode: PreviewMode) {
        do {
            document = try store.updatePreferredPreviewMode(mode, for: document)
        } catch {
            state = .failed(error.localizedDescription)
        }
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

private struct PreviewStatus: Equatable {
    let title: String
    let message: String
    let systemImage: String
}

private struct PreviewStatusBar: View {
    let status: PreviewStatus

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: status.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title)
                    .font(.footnote.weight(.semibold))
                Text(status.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial)
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
