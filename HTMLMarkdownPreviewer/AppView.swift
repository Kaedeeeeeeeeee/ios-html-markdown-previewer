import SwiftUI

struct AppView: View {
    private let store: DocumentLibraryStore
    private let importService: DocumentImportService
    private let sampleProvider: BuiltInSampleProvider

    @AppStorage("home.samplesExpanded") private var areSamplesExpanded = false
    @State private var documents: [PreviewDocument] = []
    @State private var path: [PreviewDocument] = []
    @State private var isImporterPresented = false
    @State private var importPickerScope: ImportPickerScope = .previewDocument
    @State private var isSettingsPresented = false
    @State private var isPastePreviewPresented = false
    @State private var pastedImport: PreparedDocumentImport?
    @State private var pendingImport: PreparedDocumentImport?
    @State private var importQueue: [PreparedDocumentImport] = []
    @State private var isImportReviewDismissing = false
    @State private var renameDocument: PreviewDocument?
    @State private var searchText = ""
    @State private var selectedFilter: DocumentLibraryFilter = .all
    @State private var errorMessage: String?
    @State private var didHandleLaunchArguments = false

    init(store: DocumentLibraryStore = DocumentLibraryStore()) {
        self.store = store
        self.importService = DocumentImportService(store: store)
        self.sampleProvider = BuiltInSampleProvider()
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
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
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: LibraryStrings.searchPlaceholder)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(AppStrings.App.title)
            .navigationDestination(for: PreviewDocument.self) { document in
                DocumentPreviewView(document: document, store: store)
                    .onAppear {
                        markOpened(document)
                    }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if path.isEmpty {
                        Button {
                            isSettingsPresented = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel(AppStrings.Accessibility.settings)
                        .accessibilityIdentifier("settings-button")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if path.isEmpty, !documents.isEmpty { EditButton() }
                }
            }
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
                DuplicateImportView(prepared: prepared) { resolution in
                    resolvePendingImport(prepared, as: resolution)
                } onCancel: {
                    cancelImport(prepared)
                }
                .interactiveDismissDisabled()
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: importPickerScope.allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    return
                }
                importURL(url, source: .fileImporter)
            case .failure(let error):
                showError(error)
            }
        }
        .onOpenURL { url in
            importURL(url, source: .externalOpen)
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

    private var filteredDocuments: [PreviewDocument] {
        selectedFilter.documents(in: documents, matching: searchText)
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
            NavigationLink(value: document) {
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
        do {
            importQueue.append(try importService.prepareImport(from: url, source: source))
            processImportQueue()
        } catch {
            showError(error)
        }
    }

    private func processImportQueue() {
        guard pendingImport == nil, !isImportReviewDismissing,
              !isPastePreviewPresented, !isSettingsPresented, renameDocument == nil,
              !isImporterPresented, errorMessage == nil, !importQueue.isEmpty else { return }
        acceptPreparedImport(importQueue.removeFirst())
    }

    private func acceptPreparedImport(_ queuedImport: PreparedDocumentImport) {
        let prepared: PreparedDocumentImport
        do {
            // Earlier queued imports or library actions may have changed the best duplicate match.
            prepared = try importService.refreshDuplicate(for: queuedImport)
        } catch {
            try? importService.discard(queuedImport)
            showError(error)
            return
        }
        if let duplicate = prepared.duplicate {
            if prepared.document.importSource == .bundledSample, duplicate.document.importSource == .bundledSample {
                // Samples are app-managed: reopen identical samples, refresh changed samples without accumulating copies.
                if duplicate.hasIdenticalContents {
                    do {
                        try importService.discard(prepared)
                        openDocument(duplicate.document)
                        processImportQueue()
                    } catch { showError(error) }
                } else {
                    resolveImport(prepared, as: .updateExisting)
                }
            } else {
                pendingImport = prepared
            }
        } else {
            resolveImport(prepared, as: .keepBoth)
        }
    }

    private func resolveImport(_ prepared: PreparedDocumentImport, as resolution: DocumentImportResolution) {
        do {
            let document = try importService.resolve(prepared, as: resolution)
            openDocument(document)
        } catch { showError(error) }
        processImportQueue()
    }

    private func resolvePendingImport(_ prepared: PreparedDocumentImport, as resolution: DocumentImportResolution) {
        guard pendingImport?.id == prepared.id else { return }
        isImportReviewDismissing = true
        pendingImport = nil
        resolveImport(prepared, as: resolution)
    }

    private func cancelImport(_ prepared: PreparedDocumentImport) {
        guard pendingImport?.id == prepared.id else { return }
        isImportReviewDismissing = true
        pendingImport = nil
        do { try importService.discard(prepared) } catch { showError(error) }
    }

    private func importReviewDidDismiss() {
        isImportReviewDismissing = false
        processImportQueue()
    }

    private func openDocument(_ document: PreviewDocument) {
        reloadDocuments()
        searchText = ""
        selectedFilter = .all
        // Updating an externally opened file replaces a stale preview rather than stacking it underneath.
        path = [document]
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
            importQueue.append(prepared)
        }
        processImportQueue()
    }

    private func handleLaunchArgumentsIfNeeded() {
        guard !didHandleLaunchArguments else {
            return
        }

        didHandleLaunchArguments = true
        let arguments = CommandLine.arguments
        if importQueue.isEmpty, pendingImport == nil, pastedImport == nil {
            try? store.clearAbandonedStaging()
        }

        #if DEBUG
        if ReadingLibraryTestFixtures.handle(arguments: arguments, store: store) {
            reloadDocuments()
        }
        #endif

        if arguments.contains("--screenshot-reset-library") {
            for document in documents {
                try? store.delete(document)
            }
            reloadDocuments()
        }

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
        } catch {
            showError(error)
        }
    }

    private func markOpened(_ document: PreviewDocument) {
        do {
            _ = try store.markOpened(document)
            documents = try store.loadDocuments()
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
        } catch {
            showError(error)
        }
    }

    private func clearImportedFiles() throws {
        try store.deleteAll()
        documents = try store.loadDocuments()
        path.removeAll()
        searchText = ""
        selectedFilter = .all
    }

    private func showError(_ error: Error) {
        errorMessage = userFacingMessage(for: error)
    }

    private func userFacingMessage(for error: Error) -> String {
        if let importError = error as? DocumentImportError {
            switch importError {
            case .unsupportedFileType:
                return AppStrings.Errors.unsupportedFileType
            }
        }

        if let zipError = error as? ZipImportError {
            switch zipError {
            case .invalidArchive:
                return AppStrings.Errors.zipInvalidArchive
            case .unsafePath, .unsupportedEntry, .duplicatePath, .caseConflictingPath:
                return AppStrings.Errors.zipUnsafeOrConflictingPath
            case .archiveTooLarge:
                return AppStrings.Errors.zipArchiveTooLarge
            case .tooManyFiles:
                return AppStrings.Errors.zipTooManyFiles
            case .singleFileTooLarge:
                return AppStrings.Errors.zipSingleFileTooLarge
            case .expandedSizeTooLarge:
                return AppStrings.Errors.zipExpandedSizeTooLarge
            case .missingEntryFile:
                return AppStrings.Errors.zipMissingEntryFile
            }
        }

        return error.localizedDescription
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
