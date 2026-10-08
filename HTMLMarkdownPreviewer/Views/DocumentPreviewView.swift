import SwiftUI
import WebKit

struct DocumentPreviewView: View {
    let store: DocumentLibraryStore
    private let inputDocument: PreviewDocument
    private let isReadingObscured: Bool
    private let isReadingSelected: (() -> Bool)?
    private let onReadingFinished: (TimeInterval) -> Void

    @State private var reviewReading = ReviewReadingSession()
    @State private var isReaderVisible = false
    @State private var sharePresentation = SharePresentationContext()

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
    @State private var searchEditingSession = DocumentSearchEditingSession()
    @State private var readingSheet: ReadingSheet?
    @State private var readingSaveTask: Task<Void, Never>?
    @State private var previewLoadTask: Task<Void, Never>?
    @State private var isFullScreen = false
    @State private var isAppearancePresented = false
    @State private var packageNavigation: PackageNavigationState?
    @State private var packageCatalog: PackagePageCatalog?
    @State private var isPackagePagesPresented = false
    @State private var previewGeneration = UUID()
    @State private var pendingPackageFragment: String?
    @State private var readerWidth: CGFloat = 0
    @AppStorage("reading.htmlZoom") private var htmlZoom = 1.0
    @AppStorage("reading.markdownFontScale") private var markdownFontScale = 1.0
    @AppStorage("reading.markdownLineSpacing") private var markdownLineSpacing = 4.0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    init(document: PreviewDocument, store: DocumentLibraryStore,
         isReadingObscured: Bool = false,
         isReadingSelected: (() -> Bool)? = nil,
         onReadingFinished: @escaping (TimeInterval) -> Void = { _ in }) {
        self.store = store
        self.inputDocument = document
        self.isReadingObscured = isReadingObscured
        self.isReadingSelected = isReadingSelected
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
        // A constant container keeps the reader's identity when the outline column appears.
        HStack(spacing: 0) {
            previewContent
                .modifier(ReaderFoldObserver(reading: reading))
            if usesOutlineColumn && readingSheet == .contents {
                Divider()
                // A wide reader keeps the outline beside the document, so several
                // headings can be visited without reopening it.
                DocumentOutlineView(reading: reading, staysOpenAfterSelection: true) {
                    readingSheet = nil
                }
                .frame(width: 280)
                .transition(.move(edge: .trailing))
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.onChange(of: proxy.size.width, initial: true) { _, width in readerWidth = width }
            }
        }
        .modifier(SharePresentationModifier(presentation: sharePresentation))
        .navigationTitle(document.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !isFullScreen {
                VStack(spacing: 0) {
                    if let status = previewStatus {
                        PreviewStatusBar(status: status, showsDescription: !usesCompactSearchLayout)
                    }
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
                DocumentSearchBar(reading: reading, editingSession: searchEditingSession,
                                  usesCompactLayout: usesCompactSearchLayout) {
                    reading.query = ""
                    isSearchPresented = false
                }
            } else if !isFullScreen, !usesSystemPreviewToolbar {
                previewActions
            }
        }
        .toolbar(isFullScreen ? .hidden : .visible, for: .navigationBar)
        .toolbar(isFullScreen || isSearchPresented ? .hidden : .automatic, for: .bottomBar)
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
            if #available(iOS 27.1, *), !isFullScreen, !isSearchPresented {
                systemPreviewToolbar
            }
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
        .onChange(of: previewMode) {
            loadPreview()
        }
        .onChange(of: isSearchPresented) {
            if isSearchPresented { searchEditingSession.beginEditing() }
            else { searchEditingSession.endEditing() }
        }
        .onChange(of: inputDocument.displayName) {
            // Renaming in the library must not recreate the reader or reset its position.
            guard inputDocument.id == document.id else { return }
            document.displayName = inputDocument.displayName
        }
        .onChange(of: reading.position) {
            readingSaveTask?.cancel()
            readingSaveTask = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                saveReadingPosition()
            }
        }
        .onChange(of: reading.isReady) { applyPackageMarkdownAnchor() }
        #if DEBUG
        .onChange(of: reading.isReady) { _, isReady in
            if isReady { applyScreenshotReaderArguments() }
        }
        #endif
        .onAppear {
            isReaderVisible = true
            startPreviewLoadingIfNeeded()
            reviewReading.setActive(canAccumulateReviewReadingTime)
        }
        .onChange(of: canAccumulateReviewReadingTime) {
            reviewReading.setActive(canAccumulateReviewReadingTime)
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active { saveReadingPosition() }
        }
        .onDisappear {
            // A split column can report disappearance while its document is
            // still selected and on screen. The selection owns this session.
            guard isReadingSelected?() != true else { return }
            searchEditingSession.endEditing()
            sharePresentation.cancelExport()
            previewLoadTask?.cancel()
            previewLoadTask = nil
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
        .sheet(item: compactReadingSheet) { _ in
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
        isReaderVisible && scenePhase == .active && isReviewContentReady && !isReadingObscured
            && !isInteractiveConfirmationPresented && !isDetailsPresented && !isExporting && !isSharing && exportError == nil
            && (readingSheet == nil || usesOutlineColumn) && !isAppearancePresented && !isPackagePagesPresented
    }

    #if DEBUG
    /// Screenshot captures open reader tools without driving each display's touches.
    private func applyScreenshotReaderArguments() {
        guard ProcessInfo.processInfo.environment["HTML_PREVIEWER_UI_TESTS"] == "1" else { return }
        let arguments = CommandLine.arguments
        if let argument = arguments.first(where: { $0.hasPrefix("--screenshot-reader-query=") }) {
            // Match a reader typing after the keyboard has resized the viewport.
            isSearchPresented = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                reading.query = String(argument.dropFirst("--screenshot-reader-query=".count))
                guard arguments.contains("--screenshot-reader-submit") else { return }
                // Like the keyboard's Search key: dismiss it and reveal the result.
                try? await Task.sleep(for: .seconds(1.5))
                searchEditingSession.endEditing()
                reading.navigate(to: .match(max(0, reading.selectedMatch)))
            }
        }
        if arguments.contains("--screenshot-reader-outline") { readingSheet = .contents }
    }
    #endif

    /// Leaves the document at least a comfortable reading width beside a 280-point outline.
    private var usesOutlineColumn: Bool {
        horizontalSizeClass == .regular && readerWidth >= 640
    }

    private var compactReadingSheet: Binding<ReadingSheet?> {
        Binding(get: { usesOutlineColumn ? nil : readingSheet },
                set: { readingSheet = $0 })
    }

    private var usesSystemPreviewToolbar: Bool {
        if #available(iOS 27.1, *) { true } else { false }
    }

    private var usesCompactSearchLayout: Bool {
        usesSystemPreviewToolbar && isSearchPresented && verticalSizeClass == .compact
    }

    @available(iOS 27.1, *)
    @ToolbarContentBuilder
    private var systemPreviewToolbar: some ToolbarContent {
        if supportsReadingTools {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    isSearchPresented = true
                } label: {
                    Label(ReadingStrings.find, systemImage: "magnifyingglass")
                }
                .disabled(!reading.isReady)
                .accessibilityIdentifier("reading-find-toolbar-button")
            }
            .previewActionPriority(isPrimary: true)
            ToolbarItem(placement: .bottomBar) {
                readingToolsMenu(usesSystemLabel: true)
            }
            .previewActionPriority(isPrimary: true)
        }
        if supportsPreviewModeMenu {
            ToolbarItem(placement: .bottomBar) {
                previewModeMenu(usesSystemLabel: true)
            }
            .previewActionPriority(isPrimary: false)
        }
        ToolbarItem(placement: .bottomBar) {
            SystemShareSheetButton(
                presentation: sharePresentation,
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
        }
        .previewActionPriority(isPrimary: true)
        ToolbarItem(placement: .bottomBar) {
            Button {
                isDetailsPresented = true
            } label: {
                Label(AppStrings.Accessibility.fileDetails, systemImage: "info.circle")
            }
            .accessibilityIdentifier("file-details-button")
        }
        .previewActionPriority(isPrimary: false)
    }

    private func readingToolsMenu(usesSystemLabel: Bool) -> some View {
        Menu {
            Button {
                isSearchPresented = true
            } label: {
                Label(ReadingStrings.find, systemImage: "magnifyingglass")
            }
            .accessibilityIdentifier("reading-find-button")
            Button {
                // A wide reader's outline is a column; the same command closes it.
                withAnimation(.snappy) {
                    readingSheet = usesOutlineColumn && readingSheet == .contents ? nil : .contents
                }
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
            if usesSystemLabel {
                Label(ReadingStrings.tools, systemImage: "doc.text.magnifyingglass")
            } else {
                Image(systemName: "doc.text.magnifyingglass")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .disabled(!reading.isReady)
        .accessibilityLabel(ReadingStrings.tools)
        .accessibilityIdentifier("reading-tools-menu")
    }

    private func previewModeMenu(usesSystemLabel: Bool) -> some View {
        Menu {
            previewModeButtons
        } label: {
            if usesSystemLabel {
                Label(AppStrings.Accessibility.previewMode, systemImage: previewModeIcon)
            } else {
                Image(systemName: previewModeIcon)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .accessibilityLabel(AppStrings.Accessibility.previewMode)
        .accessibilityHint(AppStrings.Accessibility.previewModeHint)
        .accessibilityIdentifier("preview-mode-menu")
    }

    private var previewActions: some View {
        HStack(spacing: 4) {
            if supportsReadingTools {
                readingToolsMenu(usesSystemLabel: false)
            }
            if supportsPreviewModeMenu {
                previewModeMenu(usesSystemLabel: false)
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

    private func startPreviewLoadingIfNeeded() {
        guard case .loading = state, previewLoadTask == nil else { return }
        // This task belongs to the document/payload identity, not SwiftUI's
        // transient column presentation. A real selection change cancels it.
        previewLoadTask = Task { @MainActor in
            defer { previewLoadTask = nil }
            await preparePackage()
            guard !Task.isCancelled, isReadingSelected?() != false else { return }
            loadPreview()
        }
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
        guard !Task.isCancelled, isReadingSelected?() != false, let pages, !pages.isEmpty else { return }
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

private extension ToolbarContent {
    @MainActor
    @available(iOS 27.1, *)
    func previewActionPriority(isPrimary: Bool) -> some ToolbarContent {
        // Priority is optional so older CI toolchains can compile the native toolbar.
        // Full iPhone Duo release support still requires the iOS 27.1 SDK.
        #if compiler(>=6.4)
        self.visibilityPriority(isPrimary ? .high : .low)
        #else
        self
        #endif
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

/// One line by default so short displays keep their height for the document.
/// The complete explanation stays one tap (or VoiceOver action) away.
private struct PreviewStatusBar: View {
    let status: PreviewStatus
    var showsDescription = true
    @State private var isExpanded = false

    var body: some View {
        HStack(alignment: isDetailed ? .top : .firstTextBaseline, spacing: 8) {
            Image(systemName: status.systemImage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            if isDetailed {
                VStack(alignment: .leading, spacing: 2) {
                    title
                    message.fixedSize(horizontal: false, vertical: true)
                }
            } else {
                title.layoutPriority(1)
                if showsDescription { message.lineLimit(1) }
            }
            Spacer(minLength: 0)
            if showsDescription {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(status.title): \(status.message)")
        .accessibilityAction { toggle() }
    }

    private var isDetailed: Bool { isExpanded && showsDescription }

    private var title: some View {
        Text(status.title).font(.footnote.weight(.semibold))
    }

    private var message: some View {
        Text(status.message).font(.caption).foregroundStyle(.secondary)
    }

    private func toggle() {
        guard showsDescription else { return }
        withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
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
