import SwiftUI
import UniformTypeIdentifiers

struct AppView: View {
    @State private var isImporterPresented = false
    @State private var status = "Ready for M0 validation"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Open File") {
                        isImporterPresented = true
                    }
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("M0 Scope") {
                    Label("Document Types registered", systemImage: "doc.badge.gearshape")
                    Label("Safe WKWebView blocks external resources", systemImage: "lock.shield")
                    Label("ZIP packages load local CSS and images", systemImage: "archivebox")
                }
            }
            .navigationTitle("HTML Previewer")
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: SupportedDocumentTypes.all,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                status = "Selected \(urls.first?.lastPathComponent ?? "file")"
            case .failure(let error):
                status = "Import failed: \(error.localizedDescription)"
            }
        }
        .onOpenURL { url in
            status = "Opened \(url.lastPathComponent)"
        }
    }
}

#Preview {
    AppView()
}

