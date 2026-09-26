import SwiftUI
import WebKit

struct HTMLPreviewView: View {
    let fileURL: URL
    let readAccessRootURL: URL
    let mode: HTMLPreviewMode
    var readingState: DocumentReadingState? = nil
    var pageZoom: Double = 1
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
                    pageZoom: ReadingAppearance.normalizedHTMLZoom(pageZoom),
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
            // Reading zoom remains available even if a page disables pinch gestures.
            loadedConfiguration.ignoresViewportScaleLimits = true
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
    let pageZoom: Double
    let onPreviewReady: (WKWebView?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(mode: mode, fileURL: fileURL, readingState: readingState,
                    pageZoom: pageZoom, onPreviewReady: onPreviewReady)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = HTMLReadingWebView(frame: .zero, configuration: configuration)
        let coordinator = context.coordinator
        webView.onLayout = { [weak coordinator] webView in
            coordinator?.viewDidLayout(webView)
        }
        webView.navigationDelegate = context.coordinator.navigationPolicy
        context.coordinator.readingController?.attach(to: webView)
        webView.loadFileURL(fileURL, allowingReadAccessTo: readAccessRootURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Keep JavaScript state, navigation history, and reading tools alive.
        context.coordinator.setPageZoom(pageZoom, in: webView)
        context.coordinator.scheduleReadingUpdate()
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        (webView as? HTMLReadingWebView)?.onLayout = nil
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
        private var desiredPageZoom: Double
        private var appliedPageZoom: Double?
        private var pendingPageZoom: Double?
        private struct NaturalZoom {
            let scale: CGFloat
            let minimumScale: CGFloat
        }
        private var historyZoom: [WKBackForwardListItem: NaturalZoom] = [:]
        private var navigationGeneration = 0
        private var navigationFinished = false
        private var isPreparing = false
        private var baselineScale: CGFloat?
        private var baselineMinimumScale: CGFloat?
        private var viewportSize: CGSize = .zero
        private var zoomRevision = 0
        private var needsReadingPreparation = true

        lazy var navigationPolicy = WebNavigationPolicy(mode: mode) { [weak self] webView in
            guard let self else { return }
            if let webView {
                self.navigationFinished = true
                self.prepareZoom(in: webView)
            } else {
                self.navigationGeneration += 1
                self.zoomRevision += 1
                self.needsReadingPreparation = true
                self.navigationFinished = false
                self.appliedPageZoom = nil
                self.pendingPageZoom = nil
                self.baselineScale = nil
                self.baselineMinimumScale = nil
                self.isPreparing = false
                self.readingController?.navigationDidStart()
                self.onPreviewReady(nil)
            }
        }

        init(
            mode: HTMLPreviewMode,
            fileURL: URL,
            readingState: DocumentReadingState?,
            pageZoom: Double,
            onPreviewReady: @escaping (WKWebView?) -> Void
        ) {
            self.mode = mode
            self.desiredPageZoom = pageZoom
            self.onPreviewReady = onPreviewReady
            readingController = readingState.map { HTMLReadingController(state: $0, entryURL: fileURL) }
        }

        func setPageZoom(_ scale: Double, in webView: WKWebView) {
            desiredPageZoom = scale
            guard baselineScale != nil, appliedPageZoom != scale, pendingPageZoom != scale else { return }
            applyPageZoom(in: webView)
        }

        func viewDidLayout(_ webView: WKWebView) {
            guard navigationFinished else { return }
            if baselineScale == nil {
                prepareZoom(in: webView)
            } else if abs(viewportSize.width - webView.bounds.width) > 0.5
                        || abs(viewportSize.height - webView.bounds.height) > 0.5 {
                // Hiding reader controls changes height without changing width.
                // WebKit can reset optical zoom during either viewport resize.
                prepareZoom(in: webView)
            }
        }

        private func prepareZoom(in webView: WKWebView) {
            guard !isPreparing, webView.window != nil,
                  webView.bounds.width > 0, webView.bounds.height > 0 else { return }
            isPreparing = true
            let generation = navigationGeneration
            // WebKit establishes its natural fit scale after viewport layout.
            // Preserve that baseline for pages both with and without viewport meta.
            webView.callDocumentJavaScript(
                "await new Promise(resolve => { setTimeout(resolve, 250); requestAnimationFrame(() => requestAnimationFrame(resolve)); }); return null;",
                in: nil, in: HTMLReadingController.contentWorld
            ) { [weak self] _ in
                guard let self, self.navigationGeneration == generation else { return }
                self.isPreparing = false
                let scrollView = webView.scrollView
                if let oldMinimum = self.baselineMinimumScale, oldMinimum > 0,
                   let baseline = self.baselineScale {
                    self.baselineScale = baseline * scrollView.minimumZoomScale / oldMinimum
                } else if let item = webView.backForwardList.currentItem,
                          let original = self.historyZoom[item], original.minimumScale > 0 {
                    // Back/forward can restore a previously enlarged native scale.
                    // Reuse the page's natural baseline instead of multiplying it again.
                    self.baselineScale = original.scale * scrollView.minimumZoomScale / original.minimumScale
                } else {
                    self.baselineScale = scrollView.zoomScale
                }
                self.baselineMinimumScale = scrollView.minimumZoomScale
                if let item = webView.backForwardList.currentItem, let scale = self.baselineScale {
                    let items = Set(webView.backForwardList.backList + webView.backForwardList.forwardList + [item])
                    self.historyZoom = self.historyZoom.filter { items.contains($0.key) }
                    self.historyZoom[item] = NaturalZoom(scale: scale, minimumScale: scrollView.minimumZoomScale)
                }
                self.viewportSize = webView.bounds.size
                self.applyPageZoom(in: webView)
            }
        }

        private func applyPageZoom(in webView: WKWebView) {
            guard let baselineScale, baselineScale.isFinite, baselineScale > 0 else { return }
            let scrollView = webView.scrollView
            let target = baselineScale * desiredPageZoom
            let current = scrollView.zoomScale
            appliedPageZoom = nil
            pendingPageZoom = desiredPageZoom
            zoomRevision += 1
            scrollView.maximumZoomScale = max(scrollView.maximumZoomScale, baselineScale * ReadingAppearance.htmlZoomRange.upperBound)
            if current > 0, abs(current - target) > 0.001 {
                let inset = scrollView.adjustedContentInset
                let rect = CGRect(
                    x: (scrollView.contentOffset.x + inset.left) / current,
                    y: (scrollView.contentOffset.y + inset.top) / current,
                    width: (scrollView.bounds.width - inset.left - inset.right) / target,
                    height: (scrollView.bounds.height - inset.top - inset.bottom) / target
                )
                // WebKit requires the animated zoom lifecycle to commit a native
                // optical scale; a nonanimated setter can retain its old scale.
                scrollView.zoom(to: rect, animated: true)
            }
            confirmZoom(in: webView, target: target, generation: navigationGeneration,
                        revision: zoomRevision, attempt: 0, stableSamples: 0)
        }

        private func confirmZoom(in webView: WKWebView, target: CGFloat, generation: Int,
                                 revision: Int, attempt: Int, stableSamples: Int) {
            guard navigationGeneration == generation, zoomRevision == revision else { return }
            webView.callDocumentJavaScript(
                "return window.visualViewport?.scale ?? 1;",
                in: nil, in: HTMLReadingController.contentWorld
            ) { [weak self] result in
                guard let self, self.navigationGeneration == generation,
                      self.zoomRevision == revision else { return }
                let scrollView = webView.scrollView
                let animating: Bool
                if #available(iOS 17.4, *) { animating = scrollView.isZoomAnimating }
                else { animating = false }
                let visualScale: Double?
                if case let .success(value) = result { visualScale = value as? Double }
                else { visualScale = nil }
                let settled = !animating && !scrollView.isZooming && !scrollView.isZoomBouncing
                    && abs(scrollView.zoomScale - target) < 0.005
                    && visualScale.map { abs($0 - target) < 0.005 } == true
                let samples = settled ? stableSamples + 1 : 0
                if samples >= 2 {
                    self.appliedPageZoom = self.pendingPageZoom
                    self.pendingPageZoom = nil
                    if self.needsReadingPreparation {
                        self.needsReadingPreparation = false
                        self.readingController?.navigationDidFinish(in: webView)
                        self.onPreviewReady(webView)
                    }
                    return
                }
                guard attempt < 50 else {
                    // Keep the document readable if WebKit cannot confirm the
                    // requested scale. Leave it unapplied so changing the
                    // preference can retry without continuously forcing pinch.
                    self.pendingPageZoom = nil
                    if self.needsReadingPreparation {
                        self.needsReadingPreparation = false
                        self.readingController?.navigationDidFinish(in: webView)
                        self.onPreviewReady(webView)
                    }
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self, weak webView] in
                    guard let self, let webView else { return }
                    self.confirmZoom(in: webView, target: target, generation: generation,
                                     revision: revision, attempt: attempt + 1, stableSamples: samples)
                }
            }
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
            navigationGeneration += 1
            zoomRevision += 1
            navigationFinished = false
            appliedPageZoom = nil
            pendingPageZoom = nil
            historyZoom.removeAll()
            updateTask?.cancel()
            updateTask = nil
            readingController?.detach()
            onPreviewReady(nil)
        }
    }
}

/// Observe the real SwiftUI viewport without replacing WebKit's scroll delegate.
private final class HTMLReadingWebView: WKWebView {
    var onLayout: ((WKWebView) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
    }
}
