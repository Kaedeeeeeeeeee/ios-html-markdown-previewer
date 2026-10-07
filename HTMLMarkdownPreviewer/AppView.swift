import StoreKit
import SwiftUI

struct AppView: View {
    private let store: DocumentLibraryStore
    private let batchImportStager: BatchImportStager
    private let sampleProvider: BuiltInSampleProvider

    @State private var reviewPrompt: ReviewPromptController
    @Environment(\.requestReview) private var requestReview

    @AppStorage("home.samplesExpanded") private var areSamplesExpanded = false
    @State private var documents: [PreviewDocument] = []
    @State private var selectedDocumentID: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var isImporterPresented = false
    @State private var importPickerScope: ImportPickerScope = .previewDocument
    @State private var isSettingsPresented = false
    @State private var isPastePreviewPresented = false
    @State private var pastedImport: PreparedDocumentImport?
    @State private var pendingImport: PreparedDocumentImport?
    @State private var importQueue: [BatchImportSession] = []
    @State private var preparationQueue: [BatchImportSourceRequest] = []
    @State private var isPreparingImports = false
    @State private var preparationCompletedCount = 0
    @State private var preparationTotalCount = 0
    @State private var activeImportSession: BatchImportSession?
    @State private var inFlightImportID: UUID?
    @State private var nextImportReview: PreparedDocumentImport?
    @State private var batchImportSummary: BatchImportSummary?
    @State private var pendingBatchImportSummary: BatchImportSummary?
    @State private var isBatchSummaryDismissing = false
    @State private var deferredImportError: String?
    @State private var isImportReviewDismissing = false
    @State private var renameDocument: PreviewDocument?
    @State private var searchText = ""
    @State private var selectedFilter: DocumentLibraryFilter = .all
    @State private var errorMessage: String?
    @State private var didHandleLaunchArguments = false

    init(store: DocumentLibraryStore = DocumentLibraryStore()) {
        self.store = store
        self.batchImportStager = BatchImportStager(libraryRootURL: store.importsURL.deletingLastPathComponent())
        self.sampleProvider = BuiltInSampleProvider()
        let environment = ProcessInfo.processInfo.environment
        self._reviewPrompt = State(initialValue: ReviewPromptController(
            isEnabled: environment["HTML_PREVIEWER_UI_TESTS"] != "1" && environment["XCTestConfigurationFilePath"] == nil
        ))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedDocumentID) {
                Section {
                    Button {
                        presentImporter(scope: .previewDocument)
                    } label: {
                        Label(AppStrings.Actions.openFile, systemImage: "doc.badge.plus")
                    }
                    .accessibilityIdentifier("open-file-button")

                    Button {
                        presentImporter(scope: .zipPackage)
                    } label: {
                        Label(AppStrings.Actions.openZIPPackage, systemImage: "archivebox")
                    }
                    .accessibilityIdentifier("open-zip-package-button")

                    Button {
                        isPastePreviewPresented = true
                    } label: {
                        Label(PasteStrings.title, systemImage: "doc.on.clipboard")
                    }
                    .accessibilityIdentifier("paste-preview-button")
                } footer: {
                    Text(BatchImportStrings.selectionHint)
                }

                if documents.isEmpty {
                    Section(AppStrings.Home.samples) {
                        sampleRows
                    }

                    ContentUnavailableView(
                        AppStrings.Home.noRecentFiles,
                        systemImage: "tray",
                        description: Text(AppStrings.Home.noRecentFilesDescription)
                    )
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        documentRows(pinnedDocuments)
                        documentRows(recentDocuments)

                        if filteredDocuments.isEmpty {
                            ContentUnavailableView {
                                Label(LibraryStrings.noResults, systemImage: "doc.text.magnifyingglass")
                            } description: {
                                Text(LibraryStrings.noResultsDescription)
                            } actions: {
                                Button(LibraryStrings.clearFilters) {
                                    searchText = ""
                                    selectedFilter = .all
                                }
                                .accessibilityIdentifier("library-clear-filters")
                            }
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        HStack(spacing: 12) {
                            Text(AppStrings.Home.recent)
                                .accessibilityIdentifier("library-recent-heading")
                            Spacer(minLength: 0)
                            libraryFilterMenu
                        }
                        .textCase(nil)
                    }

                    Section {
                        DisclosureGroup(isExpanded: $areSamplesExpanded) {
                            sampleRows
                        } label: {
                            Text(AppStrings.Home.samples)
                                .accessibilityIdentifier("samples-disclosure")
                        }
                    }
                }
            }
            .background {
                ReviewPromptRequestView(controller: reviewPrompt, isAvailable: isReviewRequestAvailable) {
                    requestReview()
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: LibraryStrings.searchPlaceholder)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(AppStrings.App.title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(AppStrings.Accessibility.settings)
                    .accessibilityIdentifier("settings-button")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if !documents.isEmpty { EditButton() }
                }
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 400)
        } detail: {
            documentDetail
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $isSettingsPresented, onDismiss: processImportQueue) {
            SettingsView(clearImportedFiles: clearImportedFiles)
        }
        .sheet(isPresented: $isPastePreviewPresented, onDismiss: openPastedDocument) {
            PastePreviewView(store: store) { prepared in
                pastedImport = prepared
            }
        }
        .sheet(item: $renameDocument, onDismiss: processImportQueue) { document in
            RenameDocumentView(document: document) { name in
                _ = try store.rename(document, to: name)
                reloadDocuments()
            }
        }
        .sheet(item: $pendingImport, onDismiss: importReviewDidDismiss) { prepared in
            DuplicateImportView(
                prepared: prepared,
                onResolve: { resolvePendingImport(prepared, as: $0) },
                onCancel: { cancelImport(prepared) },
                cancelTitle: activeImportSession?.isBatch == true ? BatchImportStrings.skip : AppStrings.Actions.cancel
            )
            .interactiveDismissDisabled()
        }
        .sheet(item: $batchImportSummary, onDismiss: batchSummaryDidDismiss) { summary in
            BatchImportSummaryView(summary: summary) {
                isBatchSummaryDismissing = true
                batchImportSummary = nil
            }
        }
        .disabled(isPreparingImports || inFlightImportID != nil)
        .overlay {
            if isPreparingImports || inFlightImportID != nil {
                VStack(spacing: 12) {
                    if isPreparingImports {
                        ProgressView(value: Double(preparationCompletedCount), total: Double(max(preparationTotalCount, 1)))
                        Text(BatchImportStrings.preparing(preparationCompletedCount, total: preparationTotalCount))
                            .font(.subheadline)
                    } else if let session = activeImportSession {
                        ProgressView(value: Double(session.outcomes.count), total: Double(max(session.items.count, 1)))
                        Text(BatchImportStrings.processing(session.outcomes.count, total: session.items.count))
                            .font(.subheadline)
                    }
                }
                .padding(24)
                .frame(maxWidth: 300)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(isPreparingImports ? "batch-import-preparing" : "batch-import-processing")
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: importPickerScope.allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importURLs(urls, source: .fileImporter)
            case .failure(let error):
                showError(error)
            }
        }
        .onOpenURL { url in
            importURL(url, source: .externalOpen)
        }
        .onChange(of: selectedDocumentID) { _, documentID in
            if let document = documents.first(where: { $0.id == documentID }) {
                markOpened(document)
            }
        }
        .onChange(of: isImporterPresented) { _, isPresented in
            if !isPresented { processImportQueue() }
        }
        .onChange(of: errorMessage) { _, message in
            if message == nil { processImportQueue() }
        }
        .onAppear {
            reloadDocuments()
            handleLaunchArgumentsIfNeeded()
        }
        .alert(AppStrings.Errors.cannotOpenFileTitle, isPresented: isErrorPresented) {
            Button(AppStrings.Actions.ok, role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var selectedDocument: PreviewDocument? {
        documents.first { $0.id == selectedDocumentID }
    }

    @ViewBuilder
    private var documentDetail: some View {
        if let document = selectedDocument {
            let identity = DocumentReaderIdentity(document: document)
            DocumentPreviewView(document: document, store: store, isReadingObscured: isReadingObscured,
                                isReadingSelected: { selectedDocument.map(DocumentReaderIdentity.init) == identity }) { activeSeconds in
                // SwiftUI can temporarily hide a column while adapting its layout.
                // Only a changed selection or payload represents a completed reading.
                guard selectedDocument.map(DocumentReaderIdentity.init) != identity else { return }
                reviewPrompt.recordCompletedReading(documentID: document.id, source: document.importSource,
                                                    activeSeconds: activeSeconds)
            }
            .id(identity)
        } else {
            ContentUnavailableView(
                LibraryStrings.selectFile,
                systemImage: "doc.text",
                description: Text(LibraryStrings.selectFileDescription)
            )
            .accessibilityIdentifier("library-detail-placeholder")
        }
    }

    private func reconcileSelection() {
        if let selectedDocumentID, !documents.contains(where: { $0.id == selectedDocumentID }) {
            self.selectedDocumentID = nil
        }
    }

    private var filteredDocuments: [PreviewDocument] {
        selectedFilter.documents(in: documents, matching: searchText)
    }

    private var isReadingObscured: Bool {
        isImporterPresented || isSettingsPresented || isPastePreviewPresented || renameDocument != nil
            || pastedImport != nil || pendingImport != nil || nextImportReview != nil
            || batchImportSummary != nil || pendingBatchImportSummary != nil
            || isBatchSummaryDismissing || isImportReviewDismissing
            || isPreparingImports || inFlightImportID != nil
            || errorMessage != nil || deferredImportError != nil
    }

    private var isReviewRequestAvailable: Bool {
        selectedDocumentID == nil && searchText.isEmpty && !isImporterPresented && !isSettingsPresented && !isPastePreviewPresented
            && pastedImport == nil && renameDocument == nil && pendingImport == nil && nextImportReview == nil
            && batchImportSummary == nil && pendingBatchImportSummary == nil && !isBatchSummaryDismissing
            && !isImportReviewDismissing && !isPreparingImports && inFlightImportID == nil
            && activeImportSession == nil && importQueue.isEmpty && preparationQueue.isEmpty
            && errorMessage == nil && deferredImportError == nil
    }

    private var pinnedDocuments: [PreviewDocument] { filteredDocuments.filter(\.isPinned) }
    private var recentDocuments: [PreviewDocument] { filteredDocuments.filter { !$0.isPinned } }

    private var libraryFilterMenu: some View {
        Menu {
            ForEach(DocumentLibraryFilter.allCases) { filter in
                Button {
                    selectedFilter = filter
                } label: {
                    Label(filter.title, systemImage: selectedFilter == filter ? "checkmark" : filter.systemImage)
                }
                .accessibilityIdentifier("library-filter-\(filter.rawValue)")
            }
        } label: {
            Image(systemName: selectedFilter == .all
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(selectedFilter == .all ? Color.secondary : Color.accentColor)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .accessibilityLabel(LibraryStrings.filter)
        .accessibilityValue(selectedFilter.title)
        .accessibilityIdentifier("library-filter-menu")
    }

    private func documentRows(_ visibleDocuments: [PreviewDocument]) -> some View {
        ForEach(visibleDocuments) { document in
            NavigationLink(value: document.id) {
                DocumentRow(document: document)
            }
            .accessibilityIdentifier("recent-document-\(document.originalFilename)")
            .accessibilityValue(document.isPinned ? LibraryStrings.pinned : "")
            .contextMenu {
                pinButton(for: document)
                renameButton(for: document)
                deleteButton(for: document)
            }
            .swipeActions(edge: .leading) {
                pinButton(for: document).tint(.orange)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                deleteButton(for: document)
                renameButton(for: document).tint(.blue)
            }
        }
        .onDelete { offsets in deleteDocuments(at: offsets, in: visibleDocuments) }
    }

    private func pinButton(for document: PreviewDocument) -> some View {
        Button(document.isPinned ? LibraryStrings.unpin : LibraryStrings.pin, systemImage: document.isPinned ? "pin.slash" : "pin") {
            do {
                _ = try store.setPinned(!document.isPinned, for: document)
                reloadDocuments()
            } catch { showError(error) }
        }
        .accessibilityIdentifier("library-pin-button")
    }

    private func renameButton(for document: PreviewDocument) -> some View {
        Button(LibraryStrings.rename, systemImage: "pencil") { renameDocument = document }
            .accessibilityIdentifier("library-rename-button")
    }

    private func deleteButton(for document: PreviewDocument) -> some View {
        Button(LibraryStrings.delete, systemImage: "trash", role: .destructive) {
            deleteDocuments(at: IndexSet(integer: 0), in: [document])
        }
        .accessibilityIdentifier("library-delete-button")
    }

    private var sampleRows: some View {
        ForEach(BuiltInSample.allCases) { sample in
            Button {
                importSample(sample)
            } label: {
                SampleRow(sample: sample)
            }
            .accessibilityIdentifier("sample-\(sample.rawValue)")
        }
    }

    private var isErrorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private func presentImporter(scope: ImportPickerScope) {
        importPickerScope = scope
        isImporterPresented = true
    }

    private func importURL(_ url: URL, source: ImportSource) {
        importURLs([url], source: source)
    }

    private func importURLs(_ urls: [URL], source: ImportSource) {
        guard !urls.isEmpty else { return }
        preparationQueue.append(BatchImportSourceRequest(urls: urls, source: source))
        guard !isPreparingImports else { return }
        isPreparingImports = true
        Task { @MainActor in
            while !preparationQueue.isEmpty {
                let request = preparationQueue.removeFirst()
                preparationCompletedCount = 0
                preparationTotalCount = request.urls.count
                var items: [BatchImportItem] = []
                for url in request.urls {
                    let result = await batchImportStager.prepare(url: url, source: request.source)
                    items.append(result.item)
                    preparationCompletedCount += 1
                }
                request.releaseAccess()
                importQueue.append(BatchImportSession(items: items))
            }
            isPreparingImports = false
            processImportQueue()
        }
    }

    private func processImportQueue() {
        guard pendingImport == nil, !isImportReviewDismissing,
              batchImportSummary == nil, !isBatchSummaryDismissing,
              !isPastePreviewPresented, !isSettingsPresented, renameDocument == nil,
              !isImporterPresented, !isPreparingImports, inFlightImportID == nil,
              errorMessage == nil else { return }

        if let deferredImportError {
            self.deferredImportError = nil
            errorMessage = deferredImportError
            return
        }
        if let pendingBatchImportSummary {
            self.pendingBatchImportSummary = nil
            batchImportSummary = pendingBatchImportSummary
            return
        }
        if let nextImportReview {
            self.nextImportReview = nil
            if activeImportSession?.nextItem?.id == nextImportReview.id {
                pendingImport = nextImportReview
                return
            }
        }

        if activeImportSession == nil {
            guard !importQueue.isEmpty else { return }
            activeImportSession = importQueue.removeFirst()
        }
        guard let session = activeImportSession else { return }
        guard let item = session.nextItem else {
            activeImportSession = nil
            if session.isBatch {
                selectedDocumentID = nil
                searchText = ""
                selectedFilter = .all
                pendingBatchImportSummary = session.summary
                reloadDocuments()
                // Keep the summary queued behind any library read error.
                if errorMessage == nil {
                    batchImportSummary = pendingBatchImportSummary
                    pendingBatchImportSummary = nil
                }
            } else {
                Task { @MainActor in
                    await Task.yield()
                    processImportQueue()
                }
            }
            return
        }
        switch item {
        case .prepared(let prepared):
            processPreparedImport(prepared, operation: .accept)
        case .failed(let failure):
            // Even a long run of preparation failures yields between files.
            inFlightImportID = item.id
            Task { @MainActor in
                await Task.yield()
                guard inFlightImportID == item.id else { return }
                finishImport(itemID: item.id, outcome: .failed(failure))
                inFlightImportID = nil
                processImportQueue()
            }
        }
    }

    private enum ImportOperation {
        case accept
        case resolve(DocumentImportResolution)
        case discard
    }

    private func processPreparedImport(_ prepared: PreparedDocumentImport, operation: ImportOperation) {
        guard inFlightImportID == nil, activeImportSession?.nextItem?.id == prepared.id else { return }
        inFlightImportID = prepared.id
        Task { @MainActor in
            let result: BatchImportProcessingResult
            switch operation {
            case .accept:
                result = await batchImportStager.accept(prepared)
            case .resolve(let resolution):
                result = await batchImportStager.resolve(prepared, as: resolution)
            case .discard:
                result = await batchImportStager.discard(prepared)
            }
            guard inFlightImportID == prepared.id, activeImportSession?.nextItem?.id == prepared.id else { return }
            switch result {
            case .imported(let document):
                finishImportedDocument(document, prepared: prepared)
            case .review(let refreshed):
                nextImportReview = refreshed
            case .skipped:
                finishImport(itemID: prepared.id, outcome: .skipped)
            case .failure(let message):
                finishImport(itemID: prepared.id, outcome: .failed(BatchImportFailure(
                    filename: prepared.document.originalFilename, message: message
                )))
            }
            // Publish progress, allow UI work, and only then release this item.
            await Task.yield()
            guard inFlightImportID == prepared.id else { return }
            inFlightImportID = nil
            processImportQueue()
        }
    }

    private func resolvePendingImport(_ prepared: PreparedDocumentImport, as resolution: DocumentImportResolution) {
        guard pendingImport?.id == prepared.id, inFlightImportID == nil else { return }
        isImportReviewDismissing = true
        pendingImport = nil
        processPreparedImport(prepared, operation: .resolve(resolution))
    }

    private func cancelImport(_ prepared: PreparedDocumentImport) {
        guard pendingImport?.id == prepared.id, inFlightImportID == nil else { return }
        isImportReviewDismissing = true
        pendingImport = nil
        processPreparedImport(prepared, operation: .discard)
    }

    private func importReviewDidDismiss() {
        isImportReviewDismissing = false
        processImportQueue()
    }

    private func batchSummaryDidDismiss() {
        isBatchSummaryDismissing = false
        processImportQueue()
    }

    private func finishImportedDocument(_ document: PreviewDocument, prepared: PreparedDocumentImport) {
        let shouldOpen = activeImportSession?.isBatch != true
        guard finishImport(itemID: prepared.id, outcome: .imported) else { return }
        if shouldOpen { openDocument(document) }
    }

    @discardableResult
    private func finishImport(itemID: UUID, outcome: BatchImportOutcome) -> Bool {
        guard activeImportSession?.finish(itemID: itemID, outcome: outcome) == true else { return false }
        if activeImportSession?.isBatch == false, case .failed(let failure) = outcome {
            deferredImportError = failure.message
        }
        return true
    }

    private func openDocument(_ document: PreviewDocument) {
        reloadDocuments()
        searchText = ""
        selectedFilter = .all
        // The payload path changes on replacement, refreshing only that reader.
        selectedDocumentID = document.id
    }

    private func importSample(_ sample: BuiltInSample) {
        do {
            let sampleURL = try sampleProvider.makeSampleURL(for: sample)
            importURL(sampleURL, source: .bundledSample)
        } catch {
            showError(error)
        }
    }

    private func openPastedDocument() {
        if let prepared = pastedImport {
            pastedImport = nil
            importQueue.append(BatchImportSession(items: [.prepared(prepared)]))
        }
        processImportQueue()
    }

    private func handleLaunchArgumentsIfNeeded() {
        guard !didHandleLaunchArguments else {
            return
        }

        didHandleLaunchArguments = true
        let arguments = CommandLine.arguments
        if importQueue.isEmpty, preparationQueue.isEmpty, !isPreparingImports,
           activeImportSession == nil, pendingImport == nil, pastedImport == nil {
            try? store.clearAbandonedStaging()
        }

        if arguments.contains("--screenshot-reset-library") {
            for document in documents {
                try? store.delete(document)
            }
            reloadDocuments()
        }

        #if DEBUG
        if ReadingLibraryTestFixtures.handle(arguments: arguments, store: store) {
            reloadDocuments()
        }
        if PackageNavigationTestFixtures.handle(arguments: arguments, store: store) {
            reloadDocuments()
        }
        do {
            if let session = try BatchImportTestFixtures.handle(arguments: arguments, store: store, errorMessage: userFacingMessage) {
                importQueue.append(session)
            }
            reloadDocuments()
            processImportQueue()
        } catch { showError(error) }
        #endif

        #if DEBUG
        if ProcessInfo.processInfo.environment["HTML_PREVIEWER_UI_TESTS"] == "1",
           arguments.contains("--screenshot-library") {
            let provider = BuiltInSampleProvider()
            let service = DocumentImportService(store: store)
            do {
                for sample in BuiltInSample.allCases {
                    _ = try service.importDocument(from: provider.makeSampleURL(for: sample), source: .bundledSample)
                }
                reloadDocuments()
                columnVisibility = .all
            } catch { showError(error) }
        }
        if ProcessInfo.processInfo.environment["HTML_PREVIEWER_UI_TESTS"] == "1",
           let argument = arguments.first(where: { $0.hasPrefix("--screenshot-open-document=") }),
           let document = documents.first(where: {
               $0.originalFilename == String(argument.dropFirst("--screenshot-open-document=".count))
           }) {
            openDocument(document)
        }
        #endif

        if let sample = screenshotSample(from: arguments) {
            importSample(sample)
        }

        if arguments.contains("--screenshot-settings") {
            isSettingsPresented = true
        }
    }

    private func screenshotSample(from arguments: [String]) -> BuiltInSample? {
        guard let argument = arguments.first(where: { $0.hasPrefix("--screenshot-sample=") }) else {
            return nil
        }

        let rawValue = String(argument.dropFirst("--screenshot-sample=".count))
        return BuiltInSample(rawValue: rawValue)
    }

    private func reloadDocuments() {
        do {
            documents = try store.loadDocuments()
            reconcileSelection()
        } catch {
            showError(error)
        }
    }

    private func markOpened(_ document: PreviewDocument) {
        do {
            _ = try store.markOpened(document)
            documents = try store.loadDocuments()
            reconcileSelection()
        } catch {
            showError(error)
        }
    }

    private func deleteDocuments(at offsets: IndexSet, in visibleDocuments: [PreviewDocument]) {
        do {
            // Offsets belong to the displayed section after search/filtering, never the unfiltered library.
            for document in offsets.compactMap({ visibleDocuments.indices.contains($0) ? visibleDocuments[$0] : nil }) {
                try store.delete(document)
            }
            documents = try store.loadDocuments()
            reconcileSelection()
        } catch {
            showError(error)
        }
    }

    private func clearImportedFiles() throws {
        try store.deleteAll()
        documents = try store.loadDocuments()
        reconcileSelection()
        selectedDocumentID = nil
        searchText = ""
        selectedFilter = .all
    }

    private func showError(_ error: Error) {
        errorMessage = userFacingMessage(for: error)
    }

    private func userFacingMessage(for error: Error) -> String {
        BatchImportErrorMessage.message(for: error)
    }
}

// Metadata such as the name, pin and last-opened date is not reader identity.
private struct DocumentReaderIdentity: Hashable {
    let documentID: UUID
    let originalFileRelativePath: String

    init(document: PreviewDocument) {
        documentID = document.id
        originalFileRelativePath = document.originalFileRelativePath
    }
}

private struct SampleRow: View {
    let sample: BuiltInSample

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(sample.title)
                    .font(.body)
                Text(sample.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: sample.documentType.systemImage)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(sample.title): \(sample.subtitle)")
    }
}

private struct DocumentRow: View {
    let document: PreviewDocument

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(document.displayName)
                        .font(.body)
                        .lineLimit(2)
                    if document.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }
                if document.displayName != (document.originalFilename as NSString).deletingPathExtension {
                    Text(document.originalFilename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    Text(typeText)
                    Text(AppFormatters.byteCount(document.fileSize))
                    Text(dateText)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        } icon: {
            Image(systemName: document.type.systemImage)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(document.displayName), \(typeText), \(AppFormatters.byteCount(document.fileSize)), \(dateText)")
    }

    private var typeText: String {
        if document.type == .zipPackage {
            return "\(document.type.displayName) -> \(document.entryDocumentType.displayName)"
        }

        return document.type.displayName
    }

    private var dateText: String {
        AppFormatters.relativeDate(document.lastOpenedAt ?? document.importedAt)
    }
}

#Preview {
    AppView()
}
