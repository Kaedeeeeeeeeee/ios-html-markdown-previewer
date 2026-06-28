import SwiftUI

struct DocumentPreviewView: View {
    let document: PreviewDocument
    let store: DocumentLibraryStore

    @State private var state: PreviewContentState = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView()
            case .markdown(let markdownDocument):
                MarkdownPreviewView(document: markdownDocument)
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
            ToolbarItem(placement: .topBarTrailing) {
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
    }

    private func loadPreview() {
        do {
            let entryFileURL = store.entryFileURL(for: document)
            switch document.entryDocumentType {
            case .markdown:
                state = .markdown(try MarkdownRenderService().render(fileURL: entryFileURL))
            case .html:
                state = .rawText(try String(contentsOf: entryFileURL, encoding: .utf8))
            case .zipPackage, .plainText, .unsupported:
                state = .unsupported
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private enum PreviewContentState {
    case loading
    case markdown(MarkdownDocument)
    case rawText(String)
    case unsupported
    case failed(String)
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
