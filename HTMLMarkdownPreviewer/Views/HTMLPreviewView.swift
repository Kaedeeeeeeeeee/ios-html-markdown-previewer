import SwiftUI
import WebKit

struct HTMLPreviewView: View {
    let fileURL: URL
    let readAccessRootURL: URL
    let mode: HTMLPreviewMode

    @State private var configuration: WKWebViewConfiguration?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let configuration {
                HTMLWebView(
                    fileURL: fileURL,
                    readAccessRootURL: readAccessRootURL,
                    mode: mode,
                    configuration: configuration
                )
                .id("\(fileURL.path)-\(mode)")
            } else if let errorMessage {
                ContentUnavailableView(
                    "Cannot Open HTML",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ProgressView()
            }
        }
        .task(id: mode) {
            await loadConfiguration()
        }
    }

    @MainActor
    private func loadConfiguration() async {
        configuration = nil
        errorMessage = nil

        do {
            configuration = try await HTMLPreviewConfiguration.make(mode: mode)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct HTMLWebView: UIViewRepresentable {
    let fileURL: URL
    let readAccessRootURL: URL
    let mode: HTMLPreviewMode
    let configuration: WKWebViewConfiguration

    func makeCoordinator() -> WebNavigationPolicy {
        WebNavigationPolicy(mode: mode)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.loadFileURL(fileURL, allowingReadAccessTo: readAccessRootURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
