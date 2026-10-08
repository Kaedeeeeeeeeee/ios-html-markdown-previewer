import SwiftUI
import WebKit

/// A single local document keeps inline mathematics in the same text flow as its
/// paragraph and gives searching, reading positions and printing one layout.
struct MarkdownRichPreviewView: View {
    let document: MarkdownDocument
    var readingState: DocumentReadingState? = nil
    var fontScale: Double = ReadingAppearance.defaultFontScale
    var lineSpacing: Double = ReadingAppearance.defaultLineSpacing
    var onPreviewReady: (WKWebView?) -> Void = { _ in }
    var onOpenLocalLink: (URL) -> Bool = { _ in false }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var page: MarkdownRichPage?
    @State private var errorMessage: String?
    @State private var isReady = false
    @State private var blockedLink: BlockedMarkdownLink?
    @State private var presentedImage: MarkdownRichImagePresentation?

    var body: some View {
        Group {
            if let errorMessage {
                ContentUnavailableView(
                    AppStrings.Errors.previewUnavailableTitle,
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if let page {
                MarkdownRichWebView(
                    page: page,
                    document: document,
                    readingState: readingState,
                    query: readingState?.query ?? "",
                    navigationRequest: readingState?.navigationRequest,
                    fold: readingState?.fold,
                    appearance: typography,
                    onPreviewReady: { webView in
                        isReady = webView != nil
                        onPreviewReady(webView)
                    },
                    onError: { _ in errorMessage = MarkdownEnhancementStrings.loadingError },
                    onLink: { if !onOpenLocalLink($0) { blockedLink = MarkdownLinkPolicy.blockedLink(for: $0) } },
                    onImage: { presentedImage = $0 }
                )
                .id(page.id)
                .overlay {
                    if !isReady { ProgressView() }
                }
            } else {
                ProgressView()
            }
        }
        .background(Color(.systemBackground))
        .task(id: document) {
            isReady = false
            errorMessage = nil
            onPreviewReady(nil)
            do {
                let configuration = try await MarkdownWebResources.makeConfiguration()
                try Task.checkCancellation()
                let files = try MarkdownRichPageFiles(html: MarkdownEnhancedHTMLRenderer().render(document, title: ""))
                page = MarkdownRichPage(files: files, configuration: configuration)
            } catch is CancellationError {
                return
            } catch {
                errorMessage = MarkdownEnhancementStrings.loadingError
            }
        }
        .alert(item: $blockedLink) { link in
            Alert(
                title: Text(link.title),
                message: Text(link.message),
                primaryButton: .default(Text(AppStrings.Actions.copyLink)) {
                    UIPasteboard.general.string = link.url.absoluteString
                },
                secondaryButton: .cancel(Text(AppStrings.Actions.ok))
            )
        }
        .fullScreenCover(item: $presentedImage) { image in
            MarkdownImageViewer(image: image.image, caption: image.caption)
        }
    }

    private var typography: MarkdownRichTypography {
        let category: UIContentSizeCategory = switch dynamicTypeSize {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        return MarkdownRichTypography(
            fontScale: ReadingAppearance.normalizedFontScale(fontScale),
            lineSpacing: ReadingAppearance.normalizedLineSpacing(lineSpacing),
            baseSize: Double(UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits).pointSize)
        )
    }
}

private struct MarkdownRichImagePresentation: Identifiable {
    let id = UUID()
    let image: UIImage
    let caption: String
}

private struct MarkdownRichTypography: Equatable {
    let fontScale: Double
    let lineSpacing: Double
    let baseSize: Double
}

private struct MarkdownRichPage: Identifiable {
    let id = UUID()
    let files: MarkdownRichPageFiles
    let configuration: WKWebViewConfiguration
}

/// Only this generated document is readable by its WebView. Its directory lives
/// until both the SwiftUI page and its native coordinator have released it.
private final class MarkdownRichPageFiles: @unchecked Sendable {
    let directory: URL
    let entryURL: URL

    init(html: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownRichPreviews", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        entryURL = directory.appendingPathComponent("index.html")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try html.write(to: entryURL, atomically: true, encoding: .utf8)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct MarkdownRichWebView: UIViewRepresentable {
    let page: MarkdownRichPage
    let document: MarkdownDocument
    let readingState: DocumentReadingState?
    let query: String
    let navigationRequest: ReadingNavigationRequest?
    let fold: ReaderFoldBand?
    let appearance: MarkdownRichTypography
    let onPreviewReady: (WKWebView?) -> Void
    let onError: (String) -> Void
    let onLink: (URL) -> Void
    let onImage: (MarkdownRichImagePresentation) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(page: page, document: document, state: readingState, appearance: appearance,
                    onPreviewReady: onPreviewReady, onError: onError, onLink: onLink, onImage: onImage)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = page.configuration
        configuration.userContentController.add(context.coordinator, contentWorld: .page, name: "markdownAction")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.navigationDelegate = context.coordinator
        context.coordinator.attach(webView)
        webView.loadFileURL(page.files.entryURL, allowingReadAccessTo: page.files.directory)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(appearance: appearance)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "markdownAction", contentWorld: .page)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let page: MarkdownRichPage
        private let reader: HTMLReadingController
        private let state: DocumentReadingState
        private let actions: MarkdownRichActions
        private let onPreviewReady: (WKWebView?) -> Void
        private let onError: (String) -> Void
        private let onLink: (URL) -> Void
        private let onImage: (MarkdownRichImagePresentation) -> Void
        private weak var webView: WKWebView?
        private var appearance: MarkdownRichTypography
        private var appliedAppearance: MarkdownRichTypography?
        private var loadTask: Task<Void, Never>?
        private var updateTask: Task<Void, Never>?
        private var stopped = false

        init(page: MarkdownRichPage, document: MarkdownDocument, state: DocumentReadingState?,
             appearance: MarkdownRichTypography, onPreviewReady: @escaping (WKWebView?) -> Void,
             onError: @escaping (String) -> Void, onLink: @escaping (URL) -> Void,
             onImage: @escaping (MarkdownRichImagePresentation) -> Void) {
            self.page = page
            self.state = state ?? DocumentReadingState()
            reader = HTMLReadingController(state: self.state, entryURL: page.files.entryURL, documentKind: .markdown)
            actions = MarkdownRichActions(document: document)
            self.appearance = appearance
            self.onPreviewReady = onPreviewReady
            self.onError = onError
            self.onLink = onLink
            self.onImage = onImage
        }

        func attach(_ webView: WKWebView) {
            self.webView = webView
            reader.attach(to: webView)
        }

        func update(appearance: MarkdownRichTypography) {
            self.appearance = appearance
            guard state.isReady, !stopped else { return }
            reader.synchronize()
            guard appliedAppearance != appearance else { return }
            updateTask?.cancel()
            updateTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.reader.applyMarkdownAppearance(
                        fontScale: appearance.fontScale, lineSpacing: appearance.lineSpacing, baseSize: appearance.baseSize
                    )
                    try Task.checkCancellation()
                    guard !self.stopped, self.appearance == appearance else { return }
                    self.appliedAppearance = appearance
                    self.reader.synchronize()
                } catch {
                    // A replaced/disposed WebView may cancel an in-flight reflow.
                    // It must not replace the still-readable document with an alert.
                }
            }
        }

        func stop() {
            stopped = true
            loadTask?.cancel()
            updateTask?.cancel()
            reader.detach()
            webView = nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            loadTask?.cancel()
            updateTask?.cancel()
            appliedAppearance = nil
            reader.navigationDidStart()
            onPreviewReady(nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loadTask = Task { [weak self, weak webView] in
                guard let self, let webView else { return }
                do {
                    try await MarkdownWebResources.waitUntilReady(in: webView)
                    try Task.checkCancellation()
                    let initial = self.appearance
                    _ = try await webView.callDocumentJavaScript(
                        """
                        document.documentElement.style.setProperty('--reader-scale', String(scale));
                        document.documentElement.style.setProperty('--reader-spacing', spacing + 'px');
                        document.documentElement.style.setProperty('--reader-base-size', baseSize + 'px');
                        await Promise.race([document.fonts?.ready || Promise.resolve(), new Promise(resolve => setTimeout(resolve, 2000))]);
                        await new Promise(resolve => { setTimeout(resolve, 250); requestAnimationFrame(() => requestAnimationFrame(resolve)); });
                        return null;
                        """,
                        arguments: ["scale": initial.fontScale, "spacing": initial.lineSpacing, "baseSize": initial.baseSize],
                        contentWorld: HTMLReadingController.contentWorld
                    )
                    try Task.checkCancellation()
                    guard !self.stopped else { return }
                    self.appliedAppearance = initial
                    self.reader.navigationDidFinish(in: webView)
                    let deadline = ContinuousClock.now + .seconds(10)
                    while !self.state.isReady {
                        guard ContinuousClock.now < deadline else { throw PDFExportError.loadTimedOut }
                        try await Task.sleep(for: .milliseconds(30))
                    }
                    try Task.checkCancellation()
                    self.update(appearance: self.appearance)
                    self.onPreviewReady(webView)
                } catch is CancellationError {
                    return
                } catch {
                    guard !self.stopped else { return }
                    self.reader.navigationDidStart()
                    self.onPreviewReady(nil)
                    self.onError(error.localizedDescription)
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            fail(NSError(domain: WKError.errorDomain, code: WKError.webContentProcessTerminated.rawValue))
        }

        private func fail(_ error: Error) {
            guard !stopped else { return }
            loadTask?.cancel()
            updateTask?.cancel()
            reader.navigationDidStart()
            onPreviewReady(nil)
            onError(error.localizedDescription)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if MarkdownWebResources.isEntryNavigation(url, entryURL: page.files.entryURL),
               navigationAction.targetFrame?.isMainFrame == true {
                decisionHandler(.allow)
            } else {
                if navigationAction.navigationType == .linkActivated, actions.links.contains(url.absoluteString) {
                    onLink(url)
                }
                decisionHandler(.cancel)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !stopped, message.frameInfo.isMainFrame, message.webView === webView,
                  let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "copy":
                guard let text = body["text"] as? String, actions.copyValues.contains(text) else { return }
                UIPasteboard.general.string = text
            case "image":
                guard let index = body["index"] as? Int, actions.images.indices.contains(index),
                      case .local(let url) = actions.images[index].kind,
                      url.isFileURL, let image = UIImage(contentsOfFile: url.path) else { return }
                onImage(MarkdownRichImagePresentation(image: image, caption: actions.images[index].altText))
            case "link":
                guard let value = body["url"] as? String, actions.links.contains(value),
                      let url = URL(string: value) else { return }
                onLink(url)
            default:
                break
            }
        }
    }
}

/// The native bridge accepts only values that were present in the parsed model;
/// generated page messages cannot turn into arbitrary file reads or URL opens.
private struct MarkdownRichActions {
    var copyValues = Set<String>()
    var images: [MarkdownImage] = []
    var links = Set<String>()

    init(document: MarkdownDocument) {
        for block in document.blocks { visit(block) }
    }

    private mutating func inline(_ text: AttributedString) {
        for run in text.runs {
            if let url = run.link { links.insert(url.absoluteString) }
            if let math = run[MarkdownMathAttribute.self] { copyValues.insert(math) }
        }
    }

    private mutating func visit(_ block: MarkdownBlock) {
        switch block {
        case .heading(_, let text), .paragraph(let text): inline(text)
        case .codeBlock(_, let code), .mathBlock(let code): copyValues.insert(code)
        case .blockQuote(let children): children.forEach { visit($0) }
        case .orderedList(_, let items), .unorderedList(let items):
            for item in items {
                inline(item.text)
                item.children.forEach { visit($0) }
            }
        case .table(let table):
            table.header.forEach { inline($0) }
            table.rows.forEach { $0.forEach { inline($0) } }
        case .image(let image): images.append(image)
        case .thematicBreak: break
        }
    }
}
