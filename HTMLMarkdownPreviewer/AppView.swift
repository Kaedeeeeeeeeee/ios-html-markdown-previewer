import SwiftUI

struct AppView: View {
    private let store: DocumentLibraryStore
    private let importService: DocumentImportService
    private let sampleProvider: BuiltInSampleProvider

    @State private var documents: [PreviewDocument] = []
    @State private var path: [PreviewDocument] = []
    @State private var isImporterPresented = false
    @State private var importPickerScope: ImportPickerScope = .previewDocument
    @State private var isSettingsPresented = false
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
                }

                Section(AppStrings.Home.samples) {
                    ForEach(BuiltInSample.allCases) { sample in
                        Button {
                            importSample(sample)
                        } label: {
                            SampleRow(sample: sample)
                        }
                        .accessibilityIdentifier("sample-\(sample.rawValue)")
                    }
                }

                if documents.isEmpty {
                    ContentUnavailableView(
                        AppStrings.Home.noRecentFiles,
                        systemImage: "tray",
                        description: Text(AppStrings.Home.noRecentFilesDescription)
                    )
                    .listRowBackground(Color.clear)
                } else {
                    Section(AppStrings.Home.recent) {
                        ForEach(documents) { document in
                            NavigationLink(value: document) {
                                DocumentRow(document: document)
                            }
                            .accessibilityIdentifier("recent-document-\(document.originalFilename)")
                        }
                        .onDelete(perform: deleteDocuments)
                    }
                }
            }
            .navigationTitle(AppStrings.App.title)
            .navigationDestination(for: PreviewDocument.self) { document in
                DocumentPreviewView(document: document, store: store)
                    .onAppear {
                        markOpened(document)
                    }
            }
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
                    if !documents.isEmpty {
                        EditButton()
                    }
                }
            }
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView(clearImportedFiles: clearImportedFiles)
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
            let document = try importService.importDocument(from: url, source: source)
            reloadDocuments()
            path.append(document)
        } catch {
            showError(error)
        }
    }

    private func importSample(_ sample: BuiltInSample) {
        do {
            let sampleURL = try sampleProvider.makeSampleURL(for: sample)
            importURL(sampleURL, source: .bundledSample)
        } catch {
            showError(error)
        }
    }

    private func handleLaunchArgumentsIfNeeded() {
        guard !didHandleLaunchArguments else {
            return
        }

        didHandleLaunchArguments = true
        let arguments = CommandLine.arguments

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

    private func deleteDocuments(at offsets: IndexSet) {
        do {
            for document in offsets.map({ documents[$0] }) {
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
                Text(document.displayName)
                    .font(.body)
                    .lineLimit(1)
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
