import SwiftUI
import WebKit

struct HTMLPreviewView: View {
    let fileURL: URL
    let readAccessRootURL: URL
    let mode: HTMLPreviewMode
    var onPreviewReady: (WKWebView?) -> Void = { _ in }

    @State private var configuration: WKWebViewConfiguration?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let configuration {
                HTMLWebView(
                    fileURL: fileURL,
                    readAccessRootURL: readAccessRootURL,
                    mode: mode,
                    configuration: configuration,
                    onPreviewReady: onPreviewReady
                )
                .id("\(fileURL.path)-\(mode)")
            } else if let errorMessage {
                ContentUnavailableView(
                    AppStrings.Errors.cannotOpenHTMLTitle,
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
        onPreviewReady(nil)
        configuration = nil
        errorMessage = nil

        do {
            let loadedConfiguration = try await HTMLPreviewConfiguration.make(mode: mode)
            guard !Task.isCancelled else { return }
            configuration = loadedConfiguration
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
    let onPreviewReady: (WKWebView?) -> Void

    func makeCoordinator() -> WebNavigationPolicy {
        WebNavigationPolicy(mode: mode, onPreviewReady: onPreviewReady)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.loadFileURL(fileURL, allowingReadAccessTo: readAccessRootURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
