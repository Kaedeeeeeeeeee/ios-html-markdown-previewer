import SwiftUI
import WebKit

struct HTMLPreviewView: View {
    let fileURL: URL
    let readAccessRootURL: URL
    let mode: HTMLPreviewMode
    var readingState: DocumentReadingState? = nil
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
                    readingState: readingState,
                    query: readingState?.query ?? "",
                    navigationRequest: readingState?.navigationRequest,
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
    let readingState: DocumentReadingState?
    let query: String
    let navigationRequest: ReadingNavigationRequest?
    let onPreviewReady: (WKWebView?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(mode: mode, fileURL: fileURL, readingState: readingState, onPreviewReady: onPreviewReady)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator.navigationPolicy
        context.coordinator.readingController?.attach(to: webView)
        webView.loadFileURL(fileURL, allowingReadAccessTo: readAccessRootURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.scheduleReadingUpdate()
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
        webView.stopLoading()
        webView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator {
        let readingController: HTMLReadingController?
        private let mode: HTMLPreviewMode
        private let onPreviewReady: (WKWebView?) -> Void
        private var updateTask: Task<Void, Never>?

        lazy var navigationPolicy = WebNavigationPolicy(mode: mode) { [weak self] webView in
            guard let self else { return }
            if let webView {
                self.readingController?.navigationDidFinish(in: webView)
            } else {
                self.readingController?.navigationDidStart()
            }
            self.onPreviewReady(webView)
        }

        init(
            mode: HTMLPreviewMode,
            fileURL: URL,
            readingState: DocumentReadingState?,
            onPreviewReady: @escaping (WKWebView?) -> Void
        ) {
            self.mode = mode
            self.onPreviewReady = onPreviewReady
            readingController = readingState.map { HTMLReadingController(state: $0, entryURL: fileURL) }
        }

        func scheduleReadingUpdate() {
            updateTask?.cancel()
            // Keep observable-model mutations outside UIViewRepresentable's
            // synchronous update pass.
            updateTask = Task { [weak self] in
                guard !Task.isCancelled else { return }
                self?.readingController?.synchronize()
            }
        }

        func stop() {
            updateTask?.cancel()
            updateTask = nil
            readingController?.detach()
            onPreviewReady(nil)
        }
    }
}
