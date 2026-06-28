import SwiftUI

struct AppView: View {
    private let store: DocumentLibraryStore
    private let importService: DocumentImportService
    private let sampleProvider: BuiltInSampleProvider

    @State private var documents: [PreviewDocument] = []
    @State private var path: [PreviewDocument] = []
    @State private var isImporterPresented = false
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
                        isImporterPresented = true
                    } label: {
                        Label("Open File", systemImage: "doc.badge.plus")
                    }
                }

                Section("Samples") {
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
                        "No Recent Files",
                        systemImage: "tray",
                        description: Text("Open an HTML, Markdown, or ZIP file.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    Section("Recent") {
                        ForEach(documents) { document in
                            NavigationLink(value: document) {
                                DocumentRow(document: document)
                            }
                        }
                        .onDelete(perform: deleteDocuments)
                    }
                }
            }
            .navigationTitle("HTML Previewer")
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
                    .accessibilityLabel("Settings")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if !documents.isEmpty {
                        EditButton()
                    }
                }
            }
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView()
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: SupportedDocumentTypes.all,
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
        .alert("Cannot Open File", isPresented: isErrorPresented) {
            Button("OK", role: .cancel) {}
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

    private func showError(_ error: Error) {
        errorMessage = userFacingMessage(for: error)
    }

    private func userFacingMessage(for error: Error) -> String {
        if let importError = error as? DocumentImportError {
            switch importError {
            case .unsupportedFileType:
                return "Current version supports HTML, Markdown, and ZIP files."
            }
        }

        if let zipError = error as? ZipImportError {
            switch zipError {
            case .invalidArchive:
                return "The ZIP package could not be read."
            case .unsafePath, .unsupportedEntry, .duplicatePath, .caseConflictingPath:
                return "The ZIP package contains unsafe or conflicting paths."
            case .archiveTooLarge:
                return "The ZIP package is over the 100 MB limit."
            case .tooManyFiles:
                return "The ZIP package contains too many files."
            case .singleFileTooLarge:
                return "The ZIP package contains a file over the 100 MB limit."
            case .expandedSizeTooLarge:
                return "The ZIP package expands beyond the 300 MB limit."
            case .missingEntryFile:
                return "No previewable HTML or Markdown entry was found in this ZIP package."
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
                    Text(ByteCountFormatter.string(fromByteCount: document.fileSize, countStyle: .file))
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
    }

    private var typeText: String {
        if document.type == .zipPackage {
            return "\(document.type.displayName) -> \(document.entryDocumentType.displayName)"
        }

        return document.type.displayName
    }

    private var dateText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: document.lastOpenedAt ?? document.importedAt, relativeTo: Date())
    }
}

#Preview {
    AppView()
}
