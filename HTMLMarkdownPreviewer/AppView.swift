import SwiftUI

struct AppView: View {
    private let store: DocumentLibraryStore
    private let importService: DocumentImportService

    @State private var documents: [PreviewDocument] = []
    @State private var path: [PreviewDocument] = []
    @State private var isImporterPresented = false
    @State private var errorMessage: String?

    init(store: DocumentLibraryStore = DocumentLibraryStore()) {
        self.store = store
        self.importService = DocumentImportService(store: store)
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
                if !documents.isEmpty {
                    EditButton()
                }
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
                errorMessage = error.localizedDescription
            }
        }
        .onOpenURL { url in
            importURL(url, source: .externalOpen)
        }
        .onAppear(perform: reloadDocuments)
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
            errorMessage = error.localizedDescription
        }
    }

    private func reloadDocuments() {
        do {
            documents = try store.loadDocuments()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markOpened(_ document: PreviewDocument) {
        do {
            _ = try store.markOpened(document)
            documents = try store.loadDocuments()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteDocuments(at offsets: IndexSet) {
        do {
            for document in offsets.map({ documents[$0] }) {
                try store.delete(document)
            }
            documents = try store.loadDocuments()
        } catch {
            errorMessage = error.localizedDescription
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
