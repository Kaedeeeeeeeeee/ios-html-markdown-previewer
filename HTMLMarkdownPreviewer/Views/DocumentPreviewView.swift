import SwiftUI
import WebKit

struct DocumentPreviewView: View {
    let store: DocumentLibraryStore

    @State private var document: PreviewDocument
    @State private var state: PreviewContentState = .loading
    @State private var previewMode: PreviewMode
    @State private var isInteractiveConfirmationPresented = false
    @State private var isDetailsPresented = false
    @State private var loadedWebView: WKWebView?
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var reading: DocumentReadingState
    @State private var isSearchPresented = false
    @State private var readingSheet: ReadingSheet?
    @State private var readingSaveTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    init(document: PreviewDocument, store: DocumentLibraryStore) {
        self.store = store
        self._document = State(initialValue: document)
        self._previewMode = State(initialValue: document.preferredPreviewMode)
        self._reading = State(initialValue: DocumentReadingState(position: store.readingPosition(for: document)))
    }

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView()
            case .markdown(let markdownDocument):
                MarkdownPreviewView(document: markdownDocument, readingState: reading)
            case .html(let fileURL, let readAccessRootURL, let mode):
                HTMLPreviewView(fileURL: fileURL, readAccessRootURL: readAccessRootURL, mode: mode, readingState: reading) {
                    loadedWebView = $0
                }
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSearchPresented, supportsReadingTools {
                DocumentSearchBar(reading: reading) {
                    reading.query = ""
                    isSearchPresented = false
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if supportsReadingTools {
                    Menu {
                        Button {
                            isSearchPresented = true
                        } label: {
                            Label(ReadingStrings.find, systemImage: "magnifyingglass")
                        }
                        .accessibilityIdentifier("reading-find-button")
                        Button {
                            readingSheet = .contents
                        } label: {
                            Label(ReadingStrings.contents, systemImage: "list.bullet.indent")
                        }
                        .accessibilityIdentifier("reading-contents-button")
                        Button {
                            reading.navigate(to: .beginning)
                        } label: {
                            Label(ReadingStrings.beginning, systemImage: "arrow.up.to.line")
                        }
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .disabled(!reading.isReady)
                    .accessibilityLabel(ReadingStrings.tools)
                    .accessibilityIdentifier("reading-tools-menu")
                }
                if supportsPreviewModeMenu {
                    Menu {
                        previewModeButtons
                    } label: {
                        Image(systemName: previewModeIcon)
                    }
                    .accessibilityLabel(AppStrings.Accessibility.previewMode)
                    .accessibilityHint(AppStrings.Accessibility.previewModeHint)
                    .accessibilityIdentifier("preview-mode-menu")
                }

                ShareSheetButton(
                    fileURL: store.originalFileURL(for: document),
                    accessibilityLabel: AppStrings.Accessibility.shareFile,
                    accessibilityIdentifier: "share-file-button",
                    shareTitle: document.type == .zipPackage
                        ? AppStrings.Actions.shareZIPPackage : AppStrings.Actions.shareOriginalFile,
                    exportPDF: canExportPDF ? exportPDF : nil,
                    onExporting: { isExporting = $0 },
                    onExportError: { exportError = $0.localizedDescription }
                )

                Button {
                    isDetailsPresented = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel(AppStrings.Accessibility.fileDetails)
                .accessibilityIdentifier("file-details-button")
            }
        }
        .disabled(isExporting)
        .overlay {
            if isExporting {
                ProgressView(AppStrings.Actions.preparingPDF)
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("pdf-export-progress")
            }
        }
        .alert(AppStrings.Errors.cannotExportPDFTitle, isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button(AppStrings.Actions.ok, role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .onAppear {
            if case .loading = state { loadPreview() }
        }
        .onChange(of: previewMode) {
            loadPreview()
        }
        .onChange(of: reading.position) {
            readingSaveTask?.cancel()
            readingSaveTask = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                saveReadingPosition()
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active { saveReadingPosition() }
        }
        .onDisappear {
            readingSaveTask?.cancel()
            saveReadingPosition()
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
        .sheet(item: $readingSheet) { _ in
            DocumentOutlineView(reading: reading)
        }
    }

    private func loadPreview() {
        saveReadingPosition()
        reading.resetContent()
        loadedWebView = nil
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

    private var supportsReadingTools: Bool {
        switch state {
        case .markdown, .html: true
        default: false
        }
    }

    private func saveReadingPosition() {
        guard let position = reading.position else { return }
        // A failed position write must not interrupt reading the original document.
        try? store.updateReadingPosition(position, for: document)
    }

    private var canExportPDF: Bool {
        switch state {
        case .markdown: true
        case .html: loadedWebView != nil
        default: false
        }
    }

    @MainActor
    private func exportPDF() async throws -> URL {
        let exporter = PDFExportService()
        switch state {
        case .html:
            guard let loadedWebView else { throw PDFExportError.previewNotReady }
            return try await exporter.export(webView: loadedWebView, title: document.displayName)
        case .markdown(let markdown):
            return try await exporter.export(markdown: markdown, title: document.displayName)
        default:
            throw PDFExportError.previewNotReady
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
                    AppStrings.PreviewModes.renderedPreview,
                    systemImage: previewMode == .rawText ? "text.alignleft" : "checkmark.circle"
                )
            }

            Button {
                setPreviewMode(.rawText)
            } label: {
                Label(AppStrings.PreviewModes.rawText, systemImage: previewMode == .rawText ? "checkmark.circle" : "doc.text")
            }
        } else {
            Button {
                setPreviewMode(.safePreview)
            } label: {
                Label(
                    AppStrings.PreviewModes.safePreview,
                    systemImage: previewMode == .safePreview ? "checkmark.shield" : "lock.shield"
                )
            }

            Button {
                isInteractiveConfirmationPresented = true
            } label: {
                Label(
                    AppStrings.PreviewModes.interactive,
                    systemImage: previewMode == .interactive ? "checkmark.circle" : "bolt"
                )
            }

            Button {
                setPreviewMode(.rawText)
            } label: {
                Label(AppStrings.PreviewModes.rawText, systemImage: previewMode == .rawText ? "checkmark.circle" : "doc.text")
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

private enum ReadingSheet: String, Identifiable {
    case contents
    var id: String { rawValue }
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(status.title): \(status.message)")
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
