import SwiftUI
import WebKit

struct DocumentPreviewView: View {
    let store: DocumentLibraryStore
    private let onReadingFinished: (TimeInterval) -> Void

    @State private var reviewReading = ReviewReadingSession()
    @State private var isReaderVisible = false

    @State private var document: PreviewDocument
    @State private var state: PreviewContentState = .loading
    @State private var previewMode: PreviewMode
    @State private var isInteractiveConfirmationPresented = false
    @State private var isDetailsPresented = false
    @State private var loadedWebView: WKWebView?
    @State private var isExporting = false
    @State private var isSharing = false
    @State private var exportError: String?
    @State private var reading: DocumentReadingState
    @State private var isSearchPresented = false
    @State private var readingSheet: ReadingSheet?
    @State private var readingSaveTask: Task<Void, Never>?
    @State private var isFullScreen = false
    @State private var isAppearancePresented = false
    @State private var packageNavigation: PackageNavigationState?
    @State private var packageCatalog: PackagePageCatalog?
    @State private var isPackagePagesPresented = false
    @State private var previewGeneration = UUID()
    @State private var pendingPackageFragment: String?
    @AppStorage("reading.htmlZoom") private var htmlZoom = 1.0
    @AppStorage("reading.markdownFontScale") private var markdownFontScale = 1.0
    @AppStorage("reading.markdownLineSpacing") private var markdownLineSpacing = 4.0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(document: PreviewDocument, store: DocumentLibraryStore,
         onReadingFinished: @escaping (TimeInterval) -> Void = { _ in }) {
        self.store = store
        self.onReadingFinished = onReadingFinished
        self._document = State(initialValue: document)
        self._previewMode = State(initialValue: document.preferredPreviewMode)
        self._reading = State(initialValue: DocumentReadingState(position: store.readingPosition(for: document)))
    }

    private var previewContent: some View {
        let generation = previewGeneration
        return Group {
            switch state {
            case .loading:
                ProgressView()
            case .markdown(let markdownDocument):
                if markdownDocument.requiresEnhancedRendering {
                    MarkdownRichPreviewView(document: markdownDocument, readingState: reading,
                                            fontScale: markdownFontScale, lineSpacing: markdownLineSpacing,
                                            onPreviewReady: { webView in
                                                if generation == previewGeneration { loadedWebView = webView }
                                            }, onOpenLocalLink: openPackageLink)
                        .id(generation)
                } else {
                    MarkdownPreviewView(document: markdownDocument, readingState: reading,
                                        fontScale: markdownFontScale, lineSpacing: markdownLineSpacing,
                                        onOpenLocalLink: openPackageLink)
                        .id(generation)
                }
            case .html(let fileURL, let readAccessRootURL, let mode):
                HTMLPreviewView(fileURL: fileURL, readAccessRootURL: readAccessRootURL, mode: mode,
                                readingState: reading, pageZoom: htmlZoom,
                                onPreviewReady: { webView in
                                    if generation == previewGeneration { loadedWebView = webView }
                                }, onLocalPageNavigation: packageLinkHandler,
                                onPageFinished: { url in
                                    if generation == previewGeneration { packageNavigation?.didFinish(url: url) }
                                })
                    .id(generation)
            case .rawText(let text):
                RawTextPreview(text: text)
                    .id(generation)
            case .yaml(let fileURL):
                YAMLPreviewView(fileURL: fileURL, reading: reading)
                    .id(generation)
            case .json(let fileURL):
                YAMLPreviewView(fileURL: fileURL, reading: reading, format: .json)
                    .id(generation)
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
    }

    var body: some View {
        previewContent
        .navigationTitle(document.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !isFullScreen {
                VStack(spacing: 0) {
                    if let status = previewStatus { PreviewStatusBar(status: status) }
                    if let packageNavigation {
                        PackageNavigationBar(navigation: packageNavigation, onBack: goBackInPackage) {
                            isPackagePagesPresented = true
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isFullScreen, isSearchPresented, supportsReadingTools {
                DocumentSearchBar(reading: reading) {
                    reading.query = ""
                    isSearchPresented = false
                }
            } else if !isFullScreen {
                previewActions
            }
        }
        .toolbar(isFullScreen ? .hidden : .visible, for: .navigationBar)
        .statusBarHidden(isFullScreen)
        .overlay(alignment: .bottomTrailing) {
            if isFullScreen {
                Button {
                    isFullScreen = false
                } label: {
                    Label(AppearanceStrings.showControls, systemImage: "arrow.down.right.and.arrow.up.left")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 19, weight: .medium))
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .modifier(PreviewActionsSurface())
                .accessibilityIdentifier("reading-fullscreen-exit")
                .padding(16)
            }
        }
        .accessibilityAction(.escape) {
            if isFullScreen { isFullScreen = false } else { dismiss() }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    isDetailsPresented = true
                } label: {
                    Text(document.displayName)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(AppStrings.Accessibility.fileDetails)
                .accessibilityIdentifier("document-title-button")
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
        .task {
            if case .loading = state {
                await preparePackage()
                guard !Task.isCancelled else { return }
                loadPreview()
            }
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
        .onChange(of: reading.isReady) { applyPackageMarkdownAnchor() }
        .onAppear {
            isReaderVisible = true
            reviewReading.setActive(canAccumulateReviewReadingTime)
        }
        .onChange(of: canAccumulateReviewReadingTime) {
            reviewReading.setActive(canAccumulateReviewReadingTime)
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active { saveReadingPosition() }
        }
        .onDisappear {
            isReaderVisible = false
            reviewReading.setActive(false)
            if isReviewContentReady { onReadingFinished(reviewReading.activeSeconds) }
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
        .sheet(isPresented: $isAppearancePresented) {
            ReadingAppearanceView(isHTML: activeDocumentType == .html,
                                  htmlZoom: $htmlZoom, fontScale: $markdownFontScale,
                                  lineSpacing: $markdownLineSpacing)
        }
        .sheet(isPresented: $isPackagePagesPresented) {
            PackagePagesView(pages: packageNavigation?.pages ?? [],
                             selectedPath: packageNavigation?.current.page.relativePath ?? "",
                             prefersLargePresentation: horizontalSizeClass == .regular,
                             onSelect: selectPackagePage)
        }
    }

    private var isReviewContentReady: Bool {
        switch state {
        case .rawText: true
        case .markdown, .html, .yaml, .json: reading.isReady
        case .loading, .unsupported, .failed: false
        }
    }

    private var canAccumulateReviewReadingTime: Bool {
        isReaderVisible && scenePhase == .active && isReviewContentReady
            && !isInteractiveConfirmationPresented && !isDetailsPresented && !isExporting && !isSharing && exportError == nil
            && readingSheet == nil && !isAppearancePresented && !isPackagePagesPresented
    }

    private var previewActions: some View {
        HStack(spacing: 4) {
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
                    Divider()
                    Button {
                        isAppearancePresented = true
                    } label: {
                        Label(AppearanceStrings.appearance, systemImage: "textformat.size")
                    }
                    .accessibilityIdentifier("reading-appearance-button")
                    Button {
                        isSearchPresented = false
                        isFullScreen = true
                    } label: {
                        Label(AppearanceStrings.fullScreen, systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .accessibilityIdentifier("reading-fullscreen-button")
                    Divider()
                    Button {
                        reading.navigate(to: .beginning)
                    } label: {
                        Label(ReadingStrings.beginning, systemImage: "arrow.up.to.line")
                    }
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
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
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
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
                onExportError: { exportError = $0.localizedDescription },
                onSharing: { isSharing = $0 }
            )
            .frame(width: 44, height: 44)

            Button {
                isDetailsPresented = true
            } label: {
                Image(systemName: "info.circle")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(AppStrings.Accessibility.fileDetails)
            .accessibilityIdentifier("file-details-button")
        }
        .font(.system(size: 21))
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .padding(6)
        .modifier(PreviewActionsSurface())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("preview-actions")
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func loadPreview() {
        saveReadingPosition()
        previewGeneration = UUID()
        reading.resetContent()
        loadedWebView = nil
        do {
            let entryFileURL = packageNavigation?.current.page.fileURL ?? activeEntryFileURL
            switch activeDocumentType {
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
                        fileURL: activeEntryFileURL,
                        readAccessRootURL: readAccessRootURL(for: document),
                        mode: previewMode.htmlPreviewMode
                    )
                }
            case .yaml:
                state = .yaml(fileURL: entryFileURL)
            case .json:
                state = .json(fileURL: entryFileURL)
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
        // A failed position write must not interrupt reading the original document.
        if let page = packageNavigation?.current.page {
            try? store.updatePackageReadingState(pageRelativePath: page.relativePath, position: reading.position, for: document)
        } else if let position = reading.position {
            try? store.updateReadingPosition(position, for: document)
        }
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
            return try await exporter.export(webView: loadedWebView, title: exportTitle)
        case .markdown(let markdown):
            return try await exporter.export(markdown: markdown, title: exportTitle)
        default:
            throw PDFExportError.previewNotReady
        }
    }

    private var previewModeIcon: String {
        activeDocumentType == .markdown && previewMode != .rawText ? "text.alignleft" : previewMode.systemImage
    }

    private var supportsPreviewModeMenu: Bool {
        activeDocumentType == .html || activeDocumentType == .markdown
    }

    @ViewBuilder
    private var previewModeButtons: some View {
        if activeDocumentType == .markdown {
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

        guard activeDocumentType == .html else {
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
        store.readAccessRootURL(for: document)
    }

    private var packageLinkHandler: ((URL) -> Bool)? {
        guard document.type == .zipPackage else { return nil }
        return { url in openPackageLink(url) }
    }

    private var activeEntryFileURL: URL { packageNavigation?.current.url ?? store.entryFileURL(for: document) }
    private var activeDocumentType: PreviewDocumentType { packageNavigation?.current.page.documentType ?? document.entryDocumentType }
    private var exportTitle: String { packageNavigation?.current.page.title ?? document.displayName }

    private func preparePackage() async {
        guard document.type == .zipPackage, packageNavigation == nil else { return }
        let catalog = PackagePageCatalog(rootURL: store.readAccessRootURL(for: document), entryURL: store.entryFileURL(for: document))
        let task = Task.detached(priority: .userInitiated) { try catalog.load() }
        let pages = try? await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
        guard !Task.isCancelled, let pages, !pages.isEmpty else { return }
        packageCatalog = catalog
        let saved = store.savedPackagePageRelativePath(for: document)
        let selected = pages.first(where: { $0.relativePath == saved }) ?? pages.first(where: \.isEntry) ?? pages[0]
        packageNavigation = PackageNavigationState(pages: pages, selected: selected)
        reading = DocumentReadingState(position: store.packageReadingPosition(forPage: selected.relativePath, in: document))
    }

    private func selectPackagePage(_ page: PackagePage) {
        guard let packageNavigation, page.relativePath != packageNavigation.current.page.relativePath else { return }
        saveReadingPosition()
        packageNavigation.select(page)
        reloadPackagePage()
    }

    private func openPackageLink(_ url: URL) -> Bool {
        let candidate = url.scheme == nil ? URL(string: url.relativeString, relativeTo: activeEntryFileURL)?.absoluteURL : url
        guard let packageCatalog, let packageNavigation,
              let candidate,
              let resolved = packageCatalog.validatedNavigationURL(candidate),
              let page = packageCatalog.resolve(url: resolved) else { return false }
        if page.relativePath == packageNavigation.current.page.relativePath,
           resolved.query == packageNavigation.current.url.query, page.documentType == .markdown {
            pendingPackageFragment = resolved.fragment
            applyPackageMarkdownAnchor()
            return true
        }
        saveReadingPosition()
        guard packageNavigation.select(page, url: resolved) else { return true }
        reloadPackagePage(followAnchor: resolved.fragment != nil)
        return true
    }

    private func goBackInPackage() {
        guard let packageNavigation, packageNavigation.canGoBack else { return }
        saveReadingPosition()
        packageNavigation.goBack()
        reloadPackagePage()
    }

    private func reloadPackagePage(followAnchor: Bool = false) {
        guard let page = packageNavigation?.current.page else { return }
        readingSaveTask?.cancel()
        isSearchPresented = false
        readingSheet = nil
        loadedWebView = nil
        pendingPackageFragment = followAnchor ? packageNavigation?.current.url.fragment : nil
        reading = DocumentReadingState(position: followAnchor ? nil : store.packageReadingPosition(forPage: page.relativePath, in: document))
        loadPreview()
    }

    private func applyPackageMarkdownAnchor() {
        guard activeDocumentType == .markdown, reading.isReady, let fragment = pendingPackageFragment else { return }
        pendingPackageFragment = nil
        if fragment.isEmpty { reading.navigate(to: .beginning) }
        else if let id = PackageMarkdownAnchor.headingID(for: fragment, headings: reading.headings) {
            reading.navigate(to: .heading(id))
        }
    }
}

private struct PreviewActionsSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        }
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
    case yaml(fileURL: URL)
    case json(fileURL: URL)
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
