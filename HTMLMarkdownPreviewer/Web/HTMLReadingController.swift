import Foundation
import WebKit

/// App-owned reading tools run in a separate JavaScript world. Page JavaScript and
/// the preview's content rules remain controlled solely by HTMLPreviewConfiguration.
@MainActor
final class HTMLReadingController {
    static let contentWorld = WKContentWorld.world(name: "com.kaede.htmlmarkdownpreviewer.reading")

    enum DocumentKind: Equatable { case html, markdown }

    private let state: DocumentReadingState
    private let documentKind: DocumentKind
    private let entryURL: URL
    private let handlerName = "reading_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private weak var webView: WKWebView?
    private var messageHandler: ReadingMessageHandler?
    private var sessionID: String?
    private var sessionURL: URL?
    private var generation = 0
    private var searchRevision = 0
    private var lastPositionSequence = -1
    private var pendingPositionSnapshot: [String: Any]?
    private var lastQuery: String?
    private var lastNavigationID: UUID?
    private var isSearching = false

    init(state: DocumentReadingState, entryURL: URL, documentKind: DocumentKind = .html) {
        self.state = state
        self.documentKind = documentKind
        self.entryURL = entryURL.standardizedFileURL
    }

    func attach(to webView: WKWebView) {
        guard self.webView !== webView else { return }
        detach()
        self.webView = webView
        let handler = ReadingMessageHandler(owner: self)
        messageHandler = handler
        webView.configuration.userContentController.add(
            handler, contentWorld: Self.contentWorld, name: handlerName
        )
    }

    func navigationDidStart() {
        generation += 1
        searchRevision += 1
        lastPositionSequence = -1
        pendingPositionSnapshot = nil
        sessionID = nil
        sessionURL = nil
        lastQuery = nil
        lastNavigationID = nil
        isSearching = false
        state.resetContent()
    }

    func navigationDidFinish(in webView: WKWebView) {
        attach(to: webView)
        navigationDidStart()
        let generation = generation
        let sessionID = UUID().uuidString
        self.sessionID = sessionID
        sessionURL = webView.url?.standardizedFileURL
        var arguments: [String: Any] = ["sessionID": sessionID, "handlerName": handlerName, "isMarkdown": documentKind == .markdown]
        if isEntryPage, let position = state.position {
            arguments["restorePosition"] = [
                "anchorID": position.anchorID as Any? ?? NSNull(),
                "progress": position.progress
            ]
        } else {
            arguments["restorePosition"] = NSNull()
        }

        webView.callDocumentJavaScript(
            Self.installScript,
            arguments: arguments,
            in: nil,
            in: Self.contentWorld
        ) { [weak self] result in
            guard let self, self.generation == generation,
                  self.sessionID == sessionID, self.webView === webView,
                  case let .success(value) = result,
                  let snapshot = value as? [String: Any] else { return }
            self.state.headings = (snapshot["headings"] as? [[String: Any]] ?? []).compactMap { item in
                guard let id = item["id"] as? String,
                      let title = item["title"] as? String,
                      let level = item["level"] as? Int else { return nil }
                return DocumentHeading(id: id, title: title, level: level)
            }
            self.updatePosition(from: snapshot)
            if let pending = self.pendingPositionSnapshot {
                self.updatePosition(from: pending)
                self.pendingPositionSnapshot = nil
            }
            self.state.isReady = true
            self.synchronize()
        }
    }

    /// Applies reader typography without throwing away the current query, outline,
    /// structural block anchor, or the WebView's enhancement state.
    func applyMarkdownAppearance(fontScale: Double, lineSpacing: Double, baseSize: Double) async throws {
        guard documentKind == .markdown, state.isReady, let webView, let sessionID else { return }
        let generation = generation
        let value = try await webView.callDocumentJavaScript(
            "return await globalThis.__htmlPreviewReading?.reflow(fontScale, lineSpacing, baseSize, sessionID) ?? null;",
            arguments: ["fontScale": fontScale, "lineSpacing": lineSpacing,
                        "baseSize": baseSize, "sessionID": sessionID],
            contentWorld: Self.contentWorld
        )
        guard self.generation == generation, self.sessionID == sessionID,
              let snapshot = value as? [String: Any] else { return }
        updatePosition(from: snapshot)
    }

    /// Called when the SwiftUI input or a navigation request changes.
    func synchronize() {
        guard state.isReady, let webView, let sessionID else { return }
        if lastQuery != state.query {
            // Reapply an existing query after reload without losing the restored
            // reading position. A newly entered query still jumps to its first hit.
            if lastQuery == nil && state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lastQuery = state.query
            } else {
                search(query: state.query, scrollToFirst: lastQuery != nil, in: webView, sessionID: sessionID)
            }
        }
        guard let request = state.navigationRequest, request.id != lastNavigationID else { return }
        if case .match = request.target, isSearching { return }
        lastNavigationID = request.id
        let operation: String
        let value: Any
        switch request.target {
        case let .heading(id): operation = "heading"; value = id
        case let .match(index): operation = "match"; value = index
        case .beginning: operation = "beginning"; value = NSNull()
        }
        let generation = generation
        let searchRevision = searchRevision
        let query = state.query
        webView.callDocumentJavaScript(
            "return globalThis.__htmlPreviewReading?.navigate(operation, value, sessionID) ?? null;",
            arguments: ["operation": operation, "value": value, "sessionID": sessionID],
            in: nil,
            in: Self.contentWorld
        ) { [weak self] result in
            guard let self, self.generation == generation,
                  self.lastNavigationID == request.id,
                  case let .success(value) = result,
                  let snapshot = value as? [String: Any] else { return }
            if self.searchRevision == searchRevision, self.state.query == query,
               let selected = snapshot["selectedMatch"] as? Int {
                self.state.selectedMatch = selected
            }
            self.updatePosition(from: snapshot)
        }
    }

    func detach() {
        if let webView {
            // Preserve the final offset even if the throttled DOM scroll message
            // has not arrived when the user closes the preview.
            if state.isReady, isEntryPage {
                let scrollView = webView.scrollView
                let inset = scrollView.adjustedContentInset
                let extent = scrollView.contentSize.height - scrollView.bounds.height + inset.top + inset.bottom
                if extent > 0 {
                    state.position = ReadingPosition(
                        anchorID: state.position?.anchorID,
                        progress: Double((scrollView.contentOffset.y + inset.top) / extent)
                    )
                }
            }
            if let sessionID {
                webView.callDocumentJavaScript(
                    "globalThis.__htmlPreviewReading?.dispose(sessionID); return null;",
                    arguments: ["sessionID": sessionID],
                    in: nil,
                    in: Self.contentWorld,
                    completionHandler: nil
                )
            }
            webView.configuration.userContentController.removeScriptMessageHandler(
                forName: handlerName, contentWorld: Self.contentWorld
            )
        }
        webView = nil
        messageHandler = nil
        navigationDidStart()
    }

    private var isEntryPage: Bool {
        guard let url = webView?.url, url.isFileURL,
              let sessionURL, sessionURL.isFileURL else { return false }
        // WebKit may update its URL before delivering didStart. A late result
        // from the previous page must keep that page's original identity.
        return sessionURL.path == entryURL.path && url.standardizedFileURL.path == entryURL.path
    }

    private func search(query: String, scrollToFirst: Bool, in webView: WKWebView, sessionID: String) {
        lastQuery = query
        searchRevision += 1
        let revision = searchRevision
        let generation = generation
        isSearching = true
        state.matchCount = 0
        state.selectedMatch = -1
        webView.callDocumentJavaScript(
            "return globalThis.__htmlPreviewReading?.search(query, sessionID, scrollToFirst) ?? null;",
            arguments: ["query": query, "sessionID": sessionID, "scrollToFirst": scrollToFirst],
            in: nil,
            in: Self.contentWorld
        ) { [weak self] result in
            guard let self, self.generation == generation,
                  self.searchRevision == revision, self.state.query == query else { return }
            self.isSearching = false
            if case let .success(value) = result, let snapshot = value as? [String: Any] {
                self.state.matchCount = snapshot["matchCount"] as? Int ?? 0
                self.state.selectedMatch = snapshot["selectedMatch"] as? Int ?? -1
                self.updatePosition(from: snapshot)
            }
            self.synchronize()
        }
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.webView === webView,
              let snapshot = message.body as? [String: Any],
              let token = snapshot["sessionID"] as? String, token == sessionID else { return }
        if state.isReady {
            updatePosition(from: snapshot)
        } else if let sequence = snapshot["sequence"] as? Int,
                  sequence > (pendingPositionSnapshot?["sequence"] as? Int ?? -1) {
            // Scroll messages and JavaScript completions use different WebKit
            // channels. Keep a newer message even if installation is still pending.
            pendingPositionSnapshot = snapshot
        }
    }

    private func updatePosition(from snapshot: [String: Any]) {
        // A ZIP can link to another local page. Its offset must never overwrite
        // the entry page's saved position, which is restored on the next opening.
        guard isEntryPage, snapshot["sessionID"] as? String == sessionID,
              let sequence = snapshot["sequence"] as? Int, sequence > lastPositionSequence,
              let progress = snapshot["progress"] as? Double,
              progress.isFinite else { return }
        lastPositionSequence = sequence
        state.position = ReadingPosition(anchorID: snapshot["anchorID"] as? String, progress: progress)
    }
}

@MainActor
private final class ReadingMessageHandler: NSObject, WKScriptMessageHandler {
    weak var owner: HTMLReadingController?

    init(owner: HTMLReadingController) {
        self.owner = owner
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.receive(message)
    }
}

private extension HTMLReadingController {
    static let installScript = #"""
    globalThis.__htmlPreviewReading?.dispose();
    const reader = (() => {
        const token = sessionID;
        const positionPrefix = 'html-reading-v1:';
        const matchStyleName = 'html-previewer-reading-matches';
        const currentStyleName = 'html-previewer-reading-current';
        const excluded = 'script,style,noscript,template,textarea,input,select,option,[contenteditable="true"],[aria-hidden="true"]' + (isMarkdown ? ',[data-reading-ignore]' : '');
        const blockSelector = 'address,article,aside,blockquote,dd,div,dl,dt,figcaption,figure,footer,form,h1,h2,h3,h4,h5,h6,header,li,main,nav,p,pre,section,table,td,th,tr';
        const hasHighlights = typeof Highlight === 'function' && !!globalThis.CSS?.highlights;
        const scrollingRoot = document.scrollingElement || document.documentElement;
        const scrollableOverflow = new Set(['auto', 'scroll', 'hidden', 'overlay']);
        const scrollContainers = new Map();
        const occluders = [];
        let disposed = false;
        let scrollTimer = null;
        let selectedMatch = -1;
        let ranges = [];
        let fallbackOverlay = null;
        let highlightSuspensions = 0;
        let reflowDepth = 0;
        let positionSequence = 0;
        let operationRevision = 0;
        let activeNavigationRevision = null;
        let navigationViewportChanged = false;
        const pendingScrolls = new Set();
        let knownViewport = null;
        let viewportAnchor = null;
        let viewportRecovery = null;
        let resizeTimer = null;
        const style = document.createElement('style');
        style.textContent = `
          ::highlight(${matchStyleName}) { background-color: #ffe083; color: #171717; }
          ::highlight(${currentStyleName}) { background-color: #ff982f; color: #171717; }
          @media print {
            ::highlight(${matchStyleName}), ::highlight(${currentStyleName}) { background-color: transparent; color: inherit; }
            [data-html-previewer-reading-overlay] { display: none !important; }
          }`;
        document.documentElement.appendChild(style);

        function visible(element) {
            if (!element || element.closest(excluded) || !element.getClientRects().length) return false;
            for (let parent = element; parent; parent = parent.parentElement) {
                const css = getComputedStyle(parent);
                if (css.display === 'none' || css.visibility === 'hidden' || css.visibility === 'collapse' || css.opacity === '0') return false;
            }
            return true;
        }
        function scrollAxes(element) {
            if (element === scrollingRoot || element === document.documentElement) return { x: false, y: false };
            const css = getComputedStyle(element);
            return {
                x: element.scrollWidth > element.clientWidth + 1 && scrollableOverflow.has(css.overflowX),
                y: element.scrollHeight > element.clientHeight + 1 && scrollableOverflow.has(css.overflowY)
            };
        }
        function pathFor(element) {
            const path = [];
            for (let current = element; current && current !== document.documentElement; current = current.parentElement) {
                const parent = current.parentElement;
                if (!parent || path.length >= 64) return null;
                const tag = current.localName;
                path.unshift({ tag, index: Array.from(parent.children).filter(child => child.localName === tag).indexOf(current) });
            }
            return path.length ? path : null;
        }
        function elementAtPath(path) {
            // Saved data is only traversed as validated child indexes, never run as
            // a selector or script supplied by the HTML document.
            if (!Array.isArray(path) || !path.length || path.length > 64) return null;
            let element = document.documentElement;
            for (const step of path) {
                if (!step || typeof step.tag !== 'string' || !/^[a-z][a-z0-9-]*$/.test(step.tag) ||
                    !Number.isSafeInteger(step.index) || step.index < 0) return null;
                element = Array.from(element.children).filter(child => child.localName === step.tag)[step.index];
                if (!element) return null;
            }
            return element;
        }
        function registerScroller(element) {
            if (!(element instanceof HTMLElement) || scrollContainers.has(element)) return;
            const axes = scrollAxes(element);
            if ((!axes.x && !axes.y) || !visible(element)) return;
            const path = pathFor(element);
            if (path) scrollContainers.set(element, { path, id: element.id || null });
        }
        for (const element of document.querySelectorAll('*')) {
            registerScroller(element);
            const position = getComputedStyle(element).position;
            if (position === 'fixed' || position === 'sticky') occluders.push(element);
        }
        function headingTitle(element) {
            if (!isMarkdown) return (element.innerText || '').replace(/\s+/g, ' ').trim();
            const title = element.getAttribute('data-reading-heading-title');
            if (title !== null) return title.replace(/\s+/g, ' ').trim();
            const clone = element.cloneNode(true);
            for (const ignored of clone.querySelectorAll('[data-reading-ignore]')) ignored.remove();
            for (const atomic of clone.querySelectorAll('[data-reading-atomic]')) {
                atomic.textContent = atomic.getAttribute('data-reading-text') || '';
            }
            return (clone.textContent || '').replace(/\s+/g, ' ').trim();
        }
        const markdownBlocks = isMarkdown
            ? Array.from(document.querySelectorAll('[data-markdown-block]')).filter(visible) : [];
        const headings = Array.from(document.querySelectorAll('h1,h2,h3,h4,h5,h6'))
            .filter(visible)
            .map((element, index) => ({
                element, id: isMarkdown ? (element.getAttribute('data-reading-heading-id') || element.id || `heading-${index}`) : `heading-${index}`,
                title: headingTitle(element),
                level: Number(element.tagName.slice(1))
            })).filter(item => item.title);

        function viewportFor(element) {
            if (!element) {
                const view = window.visualViewport;
                const width = scrollingRoot.clientWidth || innerWidth;
                const height = scrollingRoot.clientHeight || innerHeight;
                const visibleWidth = Math.min(view?.width || width, width);
                const visibleHeight = Math.min(view?.height || height, height);
                // WebKit can report a stale visual offset equal to page scroll.
                // DOM rects use layout-viewport coordinates; an equally sized
                // visual viewport has no offset, while zoom can legitimately pan.
                const left = Math.min(Math.max(0, view?.offsetLeft || 0), width - visibleWidth);
                const top = Math.min(Math.max(0, view?.offsetTop || 0), height - visibleHeight);
                return { left, top, right: left + visibleWidth,
                    bottom: top + visibleHeight, scaleX: 1, scaleY: 1 };
            }
            const rect = element.getBoundingClientRect();
            const scaleX = element.offsetWidth ? rect.width / element.offsetWidth : 1;
            const scaleY = element.offsetHeight ? rect.height / element.offsetHeight : 1;
            const left = rect.left + element.clientLeft * scaleX;
            const top = rect.top + element.clientTop * scaleY;
            return { left, top, right: left + element.clientWidth * scaleX, bottom: top + element.clientHeight * scaleY, scaleX: scaleX || 1, scaleY: scaleY || 1 };
        }
        function usableViewport(element, target) {
            const box = viewportFor(element);
            const original = { ...box };
            const width = box.right - box.left;
            const height = box.bottom - box.top;
            for (const cover of occluders) {
                if (!cover.isConnected || cover.contains(target) || !visible(cover)) continue;
                const rect = cover.getBoundingClientRect();
                const overlapsX = rect.right > original.left && rect.left < original.right;
                const overlapsY = rect.bottom > original.top && rect.top < original.bottom;
                if (overlapsX && rect.width >= width * .5 && rect.height < height * .5) {
                    if (rect.top <= original.top + 1 && rect.bottom > original.top) box.top = Math.max(box.top, rect.bottom);
                    if (rect.bottom >= original.bottom - 1 && rect.top < original.bottom) box.bottom = Math.min(box.bottom, rect.top);
                }
                if (overlapsY && rect.height >= height * .5 && rect.width < width * .5) {
                    if (rect.left <= original.left + 1 && rect.right > original.left) box.left = Math.max(box.left, rect.right);
                    if (rect.right >= original.right - 1 && rect.left < original.right) box.right = Math.min(box.right, rect.left);
                }
            }
            if (element) {
                const css = getComputedStyle(element);
                box.top += (parseFloat(css.scrollPaddingTop) || 0) * box.scaleY;
                box.bottom -= (parseFloat(css.scrollPaddingBottom) || 0) * box.scaleY;
                box.left += (parseFloat(css.scrollPaddingLeft) || 0) * box.scaleX;
                box.right -= (parseFloat(css.scrollPaddingRight) || 0) * box.scaleX;
            }
            if (box.bottom - box.top > 32) { box.top += 12; box.bottom -= 12; }
            if (box.right - box.left > 32) { box.left += 12; box.right -= 12; }
            return box;
        }
        function fraction(value, extent, signed = false) {
            return extent > 0 ? Math.min(1, Math.max(signed ? -1 : 0, value / extent)) : 0;
        }
        function rootScrollGeometry() {
            const box = viewportFor(null);
            const visual = window.visualViewport;
            return {
                left: Number.isFinite(visual?.pageLeft) ? visual.pageLeft : scrollingRoot.scrollLeft,
                top: Number.isFinite(visual?.pageTop) ? visual.pageTop : scrollingRoot.scrollTop,
                maxLeft: Math.max(0, scrollingRoot.scrollWidth - (box.right - box.left)),
                maxTop: Math.max(0, scrollingRoot.scrollHeight - (box.bottom - box.top))
            };
        }
        function position() {
            const root = rootScrollGeometry();
            const extent = root.maxTop;
            const y = Math.max(0, root.top);
            if (isMarkdown) {
                const viewportTop = viewportFor(null).top;
                const block = markdownBlocks.find(element => element.getBoundingClientRect().bottom > viewportTop) || markdownBlocks.at(-1);
                const rect = block?.getBoundingClientRect();
                const blockFraction = rect?.height > 0 ? Math.min(1, Math.max(0, (viewportTop - rect.top) / rect.height)) : 0;
                const anchorID = block ? `${block.getAttribute('data-markdown-block')}@${blockFraction}` : null;
                return { sessionID: token, sequence: ++positionSequence, anchorID, progress: fraction(y, extent) };
            }
            let headingID = null;
            let nearestTop = -Infinity;
            for (const heading of headings) {
                const rect = heading.element.getBoundingClientRect();
                const box = usableViewport(null, heading.element);
                if (rect.top <= box.top + 32 && rect.top > nearestTop) {
                    nearestTop = rect.top;
                    headingID = heading.id;
                }
            }
            const scrolls = [];
            for (const [element, descriptor] of scrollContainers) {
                if (!element.isConnected) continue;
                const topFraction = fraction(element.scrollTop, element.scrollHeight - element.clientHeight);
                const leftFraction = fraction(element.scrollLeft, element.scrollWidth - element.clientWidth, true);
                if (topFraction || leftFraction) scrolls.push({ ...descriptor, topFraction, leftFraction });
            }
            const windowLeftFraction = fraction(root.left, root.maxLeft, true);
            const anchorID = scrolls.length || windowLeftFraction
                ? positionPrefix + JSON.stringify({ heading: headingID, scrolls, windowLeftFraction })
                : headingID;
            return { sessionID: token, sequence: ++positionSequence, anchorID, progress: fraction(y, extent) };
        }
        // Cache DOM references and geometry in the isolated world only. Original
        // HTML ids, attributes, content and styles are never changed for anchoring.
        const reflowBlocks = isMarkdown ? markdownBlocks : Array.from(document.querySelectorAll(
            'p,h1,h2,h3,h4,h5,h6,pre,li,blockquote,td,th,figure'
        ));
        function viewportDimensions() {
            // WebKit can reflow the DOM and emit scroll before innerWidth/
            // innerHeight and visualViewport receive the new native view size.
            // Detect that layout change before a scroll sample can overwrite
            // the stable paragraph anchor with its post-reflow fraction.
            return { width: scrollingRoot.clientWidth || innerWidth,
                height: scrollingRoot.clientHeight || innerHeight };
        }
        function viewportChanged() {
            const size = viewportDimensions();
            return knownViewport && (Math.abs(size.width - knownViewport.width) > .5 || Math.abs(size.height - knownViewport.height) > .5);
        }
        function captureViewportAnchor() {
            const box = viewportFor(null);
            const root = rootScrollGeometry();
            const element = reflowBlocks.find(element => {
                const rect = element.getBoundingClientRect();
                if (!(rect.height > 0 && rect.bottom > box.top && rect.top < box.bottom
                    && rect.right > box.left && rect.left < box.right) || !visible(element)) return false;
                // Floating reader chrome cannot locate a paragraph in document
                // flow. Check the candidate itself and every ancestor, including
                // headings/paragraphs inside fixed or sticky containers.
                for (let parent = element; parent; parent = parent.parentElement) {
                    const positioning = getComputedStyle(parent).position;
                    if (positioning === 'fixed' || positioning === 'sticky') return false;
                    // Independent vertical panes retain their own native offset.
                    if (scrollAxes(parent).y) return false;
                }
                return true;
            });
            const rect = element?.getBoundingClientRect();
            const focusedRange = ranges[selectedMatch];
            return {
                element,
                // Retain search focus only while it is part of the user's current
                // viewport. A previous selection may have been scrolled away.
                focusedRange: focusedRange && clippedRects(focusedRange).length ? focusedRange : null,
                fraction: rect?.height > 0 ? Math.min(1, Math.max(0, (box.top - rect.top) / rect.height)) : 0,
                gap: rect ? Math.max(0, rect.top - box.top) : 0,
                progress: fraction(root.top, root.maxTop),
                leftFraction: fraction(root.left, root.maxLeft, true)
            };
        }
        function rememberViewport() {
            if (disposed || viewportRecovery || reflowDepth || isCurrent(activeNavigationRevision) || viewportChanged()) return;
            knownViewport = viewportDimensions();
            viewportAnchor = captureViewportAnchor();
        }
        function snapshot() {
            return { ...position(), matchCount: ranges.length, selectedMatch };
        }
        function notify() {
            if (!disposed && !highlightSuspensions && !reflowDepth && !viewportRecovery) {
                rememberViewport();
                globalThis.webkit?.messageHandlers[handlerName]?.postMessage(position());
            }
        }
        function clearHighlights() {
            if (hasHighlights) {
                CSS.highlights.delete(matchStyleName);
                CSS.highlights.delete(currentStyleName);
            }
            fallbackOverlay?.remove();
            fallbackOverlay = null;
        }
        function paintMatches() {
            if (!hasHighlights || highlightSuspensions || disposed || !ranges.length) return;
            const highlight = new Highlight();
            for (const range of ranges) if (!range.__markdownAtomic && !range.__markdownParts) highlight.add(range);
            CSS.highlights.set(matchStyleName, highlight);
        }
        function rangeElement(range) {
            return range.__markdownAtomic || range.__markdownTarget || range.startContainer.parentElement;
        }
        function rangeRects(range) {
            if (range.__markdownAtomic) return Array.from(range.__markdownAtomic.getClientRects());
            if (range.__markdownParts) {
                return range.__markdownParts.flatMap(part => Array.from((part.atomic || part.range).getClientRects()));
            }
            return Array.from(range.getClientRects());
        }
        function clippedRects(range) {
            const target = rangeElement(range);
            const viewport = usableViewport(null, target);
            const clip = { ...viewport };
            for (let element = target; element; element = element.parentElement) {
                if (element === scrollingRoot || element === document.documentElement) continue;
                const css = getComputedStyle(element);
                const box = viewportFor(element);
                if (css.overflowX !== 'visible') { clip.left = Math.max(clip.left, box.left); clip.right = Math.min(clip.right, box.right); }
                if (css.overflowY !== 'visible') { clip.top = Math.max(clip.top, box.top); clip.bottom = Math.min(clip.bottom, box.bottom); }
            }
            return rangeRects(range).map(rect => ({
                left: Math.max(rect.left, clip.left), right: Math.min(rect.right, clip.right),
                top: Math.max(rect.top, clip.top), bottom: Math.min(rect.bottom, clip.bottom)
            })).filter(rect => rect.right > rect.left && rect.bottom > rect.top);
        }
        function paintCurrent() {
            if (highlightSuspensions || disposed) return;
            fallbackOverlay?.remove();
            fallbackOverlay = null;
            const atomic = selectedMatch >= 0 && (ranges[selectedMatch].__markdownAtomic || ranges[selectedMatch].__markdownParts);
            if (hasHighlights) {
                CSS.highlights.delete(currentStyleName);
                if (selectedMatch >= 0 && !atomic) CSS.highlights.set(currentStyleName, new Highlight(ranges[selectedMatch]));
                if (!atomic) return;
            }
            // Safari 17.0/17.1 and atomic diagrams use overlays without rewriting
            // document content. A formula match outlines its complete expression.
            if (selectedMatch < 0) return;
            const overlay = document.createElement('div');
            overlay.setAttribute('data-html-previewer-reading-overlay', '');
            overlay.setAttribute('aria-hidden', 'true');
            overlay.style.cssText = 'position:fixed;inset:0;overflow:hidden;pointer-events:none;z-index:2147483647;contain:strict;';
            for (const rect of clippedRects(ranges[selectedMatch])) {
                const part = document.createElement('div');
                part.style.cssText = `position:absolute;left:${rect.left}px;top:${rect.top}px;width:${rect.right - rect.left}px;height:${rect.bottom - rect.top}px;${atomic ? 'box-sizing:border-box;border:2px solid #ff982f;background:rgba(255,152,47,.12)' : 'background:rgba(255,152,47,.42)'};border-radius:2px;`;
                overlay.appendChild(part);
            }
            document.documentElement.appendChild(overlay);
            fallbackOverlay = overlay;
        }
        function onScroll(event) {
            if (disposed || highlightSuspensions) return;
            if (viewportChanged()) { onResize(); return; }
            registerScroller(event.target);
            // Persist every actual scroll event; the Swift store debounces disk writes.
            // The slower visual fallback can be redrawn on a separate throttle.
            notify();
            if (scrollTimer !== null) return;
            scrollTimer = setTimeout(() => { scrollTimer = null; paintCurrent(); }, 80);
        }
        function cancelViewportRecovery() {
            clearTimeout(resizeTimer);
            resizeTimer = null;
            viewportRecovery = null;
        }
        function onUserInteraction() {
            if (!viewportRecovery) return;
            beginOperation();
            knownViewport = viewportDimensions();
            rememberViewport();
            notify();
        }
        function onKeyboardNavigation(event) {
            if (!event.isTrusted || event.defaultPrevented || !viewportRecovery) return;
            if (!['PageDown', 'PageUp', 'Home', 'End', 'ArrowDown', 'ArrowUp', 'ArrowLeft', 'ArrowRight', ' '].includes(event.key)) return;
            const target = event.target;
            if (target instanceof HTMLElement && (target.isContentEditable || target.closest('input,textarea,select'))) return;
            // Cancel the queued reader scroll; let the browser perform the key's
            // normal action without preventing or rewriting the keyboard event.
            onUserInteraction();
        }
        function onResize() {
            if (disposed || !knownViewport) return;
            if (!viewportChanged()) { paintCurrent(); return; }
            if (isCurrent(activeNavigationRevision)) {
                // A delayed resize event must not cancel a newer explicit reader
                // action or restart its old search/paragraph restoration.
                knownViewport = viewportDimensions();
                navigationViewportChanged = true;
                return;
            }
            // Resize is delivered after layout. The last stable scroll sample is
            // the only reliable source of a pre-reflow paragraph/block anchor.
            const saved = viewportRecovery?.saved || viewportAnchor;
            const revision = beginOperation();
            knownViewport = viewportDimensions();
            viewportRecovery = { saved, revision };
            resizeTimer = setTimeout(async () => {
                resizeTimer = null;
                if (!isCurrent(revision)) return;
                const focusedRange = saved?.focusedRange;
                if (focusedRange && focusedRange === ranges[selectedMatch] && visible(rangeElement(focusedRange))) {
                    // Reuse nested scroller/occluder handling and the minimum
                    // movement needed to reveal the same selected result.
                    await scrollToRange(focusedRange, false, revision);
                } else {
                    const root = rootScrollGeometry();
                    const element = saved?.element;
                    let top = (saved?.progress || 0) * root.maxTop;
                    if (element?.isConnected && visible(element)) {
                        const rect = element.getBoundingClientRect();
                        top = root.top + rect.top - viewportFor(null).top + rect.height * saved.fraction - saved.gap;
                    }
                    await scrollToPosition(null, (saved?.leftFraction || 0) * root.maxLeft, top, revision);
                }
                if (!isCurrent(revision)) return;
                viewportRecovery = null;
                rememberViewport();
                paintCurrent();
                notify();
            }, 120);
        }
        function targetRect(range) {
            if (range.__markdownAtomic) return range.__markdownAtomic.getBoundingClientRect();
            return rangeRects(range).find(rect => rect.width > 0 && rect.height > 0) || range.getBoundingClientRect();
        }
        function nearestDelta(start, end, near, far) {
            if (start < near) return start - near;
            if (end > far) return end - far;
            return 0;
        }
        function isCurrent(revision) { return !disposed && revision === operationRevision; }
        function beginOperation() {
            cancelViewportRecovery();
            operationRevision++;
            for (const cancel of Array.from(pendingScrolls)) cancel();
            return operationRevision;
        }
        async function scrollToPosition(element, left, top, revision) {
            if (!isCurrent(revision)) return false;
            const scroller = element || scrollingRoot;
            const root = element ? null : rootScrollGeometry();
            const maxLeft = root ? root.maxLeft : Math.max(0, scroller.scrollWidth - scroller.clientWidth);
            const maxTop = root ? root.maxTop : Math.max(0, scroller.scrollHeight - scroller.clientHeight);
            const rtl = getComputedStyle(scroller).direction === 'rtl';
            const targetLeft = Math.min(rtl ? 0 : maxLeft, Math.max(rtl ? -maxLeft : 0, left));
            const targetTop = Math.min(maxTop, Math.max(0, top));
            (element || window).scrollTo({ left: targetLeft, top: targetTop, behavior: 'instant' });
            // WKWebView can apply a root scroll in its UI process after this JS
            // turn returns. Do not publish the pre-scroll offset as a final result.
            // Render frames confirm the actual target; the bound also covers an
            // offscreen view (paused RAF), scroll snapping, or a removed scroller.
            return await new Promise(resolve => {
                let frame = null;
                let finished = false;
                let deadline = null;
                let stableFrames = 0;
                let previousGeometry = null;
                const eventTarget = element || window.visualViewport || document;
                const finish = () => {
                    if (finished) return;
                    finished = true;
                    if (frame !== null) cancelAnimationFrame(frame);
                    clearTimeout(deadline);
                    eventTarget.removeEventListener('scroll', didScroll);
                    pendingScrolls.delete(finish);
                    resolve(isCurrent(revision));
                };
                const didScroll = () => {
                    // A UI-process scroll can briefly overwrite the synchronous
                    // DOM offset. A scroll event starts a new frame confirmation.
                    stableFrames = 0;
                    previousGeometry = null;
                };
                const nextFrame = () => {
                    frame = null;
                    if (!isCurrent(revision)) { finish(); return; }
                    const root = element ? null : rootScrollGeometry();
                    const geometry = root
                        ? [root.left, root.top, root.maxLeft, root.maxTop, scroller.scrollWidth, scroller.scrollHeight]
                        : [scroller.scrollLeft, scroller.scrollTop, scroller.clientWidth, scroller.clientHeight, scroller.scrollWidth, scroller.scrollHeight];
                    const reached = Math.abs(geometry[0] - targetLeft) <= 1 && Math.abs(geometry[1] - targetTop) <= 1;
                    const unchanged = previousGeometry && geometry.every((value, index) => value === previousGeometry[index]);
                    stableFrames = reached ? (unchanged ? stableFrames + 1 : 1) : 0;
                    previousGeometry = geometry;
                    if (stableFrames >= 2) finish();
                    if (!finished) frame = requestAnimationFrame(nextFrame);
                };
                pendingScrolls.add(finish);
                eventTarget.addEventListener('scroll', didScroll, { passive: true });
                deadline = setTimeout(finish, 1000);
                frame = requestAnimationFrame(nextFrame);
            });
        }
        async function scrollToRange(range, alignToStart = false, revision = operationRevision) {
            if (range.__markdownAtomic || range.__markdownParts) alignToStart = true;
            const target = rangeElement(range);
            // Resolve the actual text rectangle, not its potentially very wide td/pre.
            // Re-measure after each inner scroller changes before moving its parent.
            for (let element = target; element; element = element.parentElement) {
                const axes = scrollAxes(element);
                if (!axes.x && !axes.y) continue;
                registerScroller(element);
                const rect = targetRect(range);
                const box = usableViewport(element, target);
                const left = element.scrollLeft + (axes.x ? nearestDelta(rect.left, rect.right, box.left, box.right) / box.scaleX : 0);
                const top = element.scrollTop + (axes.y ? (alignToStart ? rect.top - box.top : nearestDelta(rect.top, rect.bottom, box.top, box.bottom)) / box.scaleY : 0);
                if (!await scrollToPosition(element, left, top, revision)) return;
            }
            if (!isCurrent(revision)) return;
            const rect = targetRect(range);
            const box = usableViewport(null, target);
            const top = alignToStart ? rect.top - box.top : nearestDelta(rect.top, rect.bottom, box.top, box.bottom);
            const root = rootScrollGeometry();
            const rootLeft = root.left;
            const rootTop = root.top;
            const destinationLeft = rootLeft + nearestDelta(rect.left, rect.right, box.left, box.right);
            const destinationTop = rootTop + top;
            await scrollToPosition(null, destinationLeft, destinationTop, revision);
        }
        async function select(index, revision) {
            if (!Number.isInteger(index) || index < 0 || index >= ranges.length) return;
            selectedMatch = index;
            await scrollToRange(ranges[index], false, revision);
            if (isCurrent(revision)) paintCurrent();
        }
        async function search(query, expectedToken, scrollToFirst) {
            if (disposed || expectedToken !== token) return null;
            const revision = beginOperation();
            ranges = [];
            selectedMatch = -1;
            clearHighlights();
            const needle = query.trim();
            if (!needle) return snapshot();
            const segments = [];
            let text = '';
            let previousBlock = null;
            const visibility = new WeakMap();
            // Include BR elements in DOM order so "receipt<br>number" indexes as
            // two words, while retaining exact offsets into the original text nodes.
            const walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT);
            while (walker.nextNode()) {
                const node = walker.currentNode;
                if (node.nodeType === Node.ELEMENT_NODE) {
                    if (isMarkdown && node.hasAttribute('data-reading-atomic') && visible(node)
                        && !node.parentElement?.closest('[data-reading-atomic]')) {
                        const source = node.getAttribute('data-reading-text') || '';
                        // Inline math shares its paragraph's text flow. Only a
                        // real block boundary contributes a search separator.
                        const block = node.closest(blockSelector);
                        if (previousBlock && previousBlock !== block) text += '\n';
                        previousBlock = block;
                        segments.push({ node, atomic: node, start: text.length, end: text.length + source.length });
                        text += source;
                    } else if (node.tagName === 'BR' && visible(node)
                        && !(isMarkdown && node.closest('[data-reading-atomic]'))) text += '\n';
                    continue;
                }
                const parent = node.parentElement;
                if (!parent || !node.data.length || (isMarkdown && parent.closest('[data-reading-atomic]'))) continue;
                if (!visibility.has(parent)) visibility.set(parent, visible(parent));
                if (!visibility.get(parent)) continue;
                const block = parent.closest(blockSelector);
                if (previousBlock && previousBlock !== block) text += '\n';
                previousBlock = block;
                segments.push({ node, start: text.length, end: text.length + node.data.length });
                text += node.data;
            }
            // Native Markdown search ignores diacritics. Keep that behavior on
            // enhanced pages while preserving original UTF-16 DOM range offsets.
            const fold = value => value.normalize('NFD').replace(/\p{M}/gu, '');
            const searchNeedle = isMarkdown ? fold(needle) : needle;
            let searchableText = text;
            let offsets = null;
            if (isMarkdown && fold(text) !== text) {
                searchableText = '';
                offsets = [];
                let cursor = 0;
                for (const character of text) {
                    const folded = fold(character);
                    if (!folded.length && offsets.length) offsets[offsets.length - 1].end = cursor + character.length;
                    for (let unit = 0; unit < folded.length; unit++) offsets.push({ start: cursor, end: cursor + character.length });
                    searchableText += folded;
                    cursor += character.length;
                }
            }
            if (!searchNeedle) return snapshot();
            const escaped = searchNeedle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/\s+/g, '\\s+');
            const expression = new RegExp(escaped, 'giu');
            let match;
            let segmentIndex = 0;
            while ((match = expression.exec(searchableText)) !== null) {
                const start = offsets ? offsets[match.index].start : match.index;
                const end = offsets ? offsets[match.index + match[0].length - 1].end : match.index + match[0].length;
                while (segmentIndex < segments.length && segments[segmentIndex].end <= start) segmentIndex++;
                const first = segments[segmentIndex];
                if (!first || first.start > start) continue;
                let endIndex = segmentIndex;
                while (endIndex < segments.length && segments[endIndex].end < end) endIndex++;
                const last = segments[endIndex];
                if (!last || last.start >= end) continue;
                const range = document.createRange();
                if (first === last && first.atomic) {
                    // Canonical formula/diagram source is indexed once, rather than
                    // duplicated hidden MathML and visual glyph descendants.
                    range.selectNodeContents(first.atomic);
                    range.__markdownAtomic = first.atomic;
                } else {
                    if (first.atomic) range.setStartBefore(first.atomic);
                    else range.setStart(first.node, start - first.start);
                    if (last.atomic) range.setEndAfter(last.atomic);
                    else range.setEnd(last.node, end - last.start);
                    const matchedSegments = segments.slice(segmentIndex, endIndex + 1);
                    if (matchedSegments.some(segment => segment.atomic)) {
                        // A mixed phrase may begin/end beside a formula, or span
                        // several. Keep its real text ranges plus complete atomic
                        // boxes; generated MathML must not distort the outline.
                        range.__markdownTarget = first.atomic || first.node.parentElement;
                        range.__markdownParts = matchedSegments.map(segment => {
                            if (segment.atomic) return { atomic: segment.atomic };
                            const part = document.createRange();
                            part.setStart(segment.node, Math.max(start, segment.start) - segment.start);
                            part.setEnd(segment.node, Math.min(end, segment.end) - segment.start);
                            return { range: part };
                        });
                    }
                }
                if (rangeRects(range).some(rect => rect.width > 0 && rect.height > 0)) ranges.push(range);
            }
            paintMatches();
            if (ranges.length) {
                if (scrollToFirst) await select(0, revision);
                else { selectedMatch = 0; paintCurrent(); }
            }
            if (disposed) return null;
            notify();
            return snapshot();
        }
        async function revealHeading(id, revision) {
            const heading = headings.find(item => item.id === id);
            if (!heading) return;
            const range = document.createRange();
            range.selectNodeContents(heading.element);
            await scrollToRange(range, true, revision);
        }
        async function navigate(operation, value, expectedToken) {
            if (disposed || expectedToken !== token) return null;
            const revision = beginOperation();
            activeNavigationRevision = revision;
            // The DOM may already have the new size before its resize event is
            // delivered. Claim that viewport now so the event cannot reuse an
            // anchor captured before this newer navigation request.
            knownViewport = viewportDimensions();
            viewportAnchor = null;
            try {
                do {
                    navigationViewportChanged = false;
                    if (operation === 'heading') await revealHeading(value, revision);
                    else if (operation === 'match') await select(value, revision);
                    else if (operation === 'beginning') {
                        await Promise.all(Array.from(scrollContainers.keys()).map(element => scrollToPosition(element, 0, 0, revision)));
                        if (isCurrent(revision)) await scrollToPosition(null, 0, 0, revision);
                    }
                    // If size changed during the asynchronous native scroll,
                    // remeasure the same explicit target in the final layout.
                } while (isCurrent(revision) && navigationViewportChanged);
                if (!isCurrent(revision)) return null;
                paintCurrent();
                notify();
                return snapshot();
            } finally {
                if (activeNavigationRevision === revision) {
                    activeNavigationRevision = null;
                    if (isCurrent(revision)) {
                        knownViewport = viewportDimensions();
                        rememberViewport();
                    }
                }
            }
        }
        function suspendHighlights() {
            if (disposed) return;
            highlightSuspensions++;
            clearHighlights();
        }
        function resumeHighlights() {
            if (disposed || !highlightSuspensions) return;
            highlightSuspensions--;
            if (!highlightSuspensions) { paintMatches(); paintCurrent(); }
        }
        function dispose(expectedToken) {
            if (expectedToken && expectedToken !== token) return;
            disposed = true;
            for (const cancel of Array.from(pendingScrolls)) cancel();
            clearTimeout(scrollTimer);
            cancelViewportRecovery();
            document.removeEventListener('touchstart', onUserInteraction, true);
            document.removeEventListener('wheel', onUserInteraction, true);
            document.removeEventListener('keydown', onKeyboardNavigation, true);
            document.removeEventListener('scroll', onScroll, true);
            window.removeEventListener('resize', onResize);
            window.visualViewport?.removeEventListener('scroll', onScroll);
            window.visualViewport?.removeEventListener('resize', onResize);
            clearHighlights();
            style.remove();
        }
        async function restoreMarkdown(saved, revision) {
            const anchor = typeof saved?.anchorID === 'string' ? /^((?:markdown-block-)\d+)(?:@([0-9.eE+-]+))?$/.exec(saved.anchorID) : null;
            const block = anchor && markdownBlocks.find(element => element.getAttribute('data-markdown-block') === anchor[1]);
            const progress = Math.min(1, Math.max(0, Number(saved?.progress) || 0));
            if (block && !(progress <= 0 && block === markdownBlocks[0])) {
                const fraction = Math.min(1, Math.max(0, Number(anchor[2]) || 0));
                const rect = block.getBoundingClientRect();
                await scrollToPosition(null, 0, rootScrollGeometry().top + rect.top - viewportFor(null).top + rect.height * fraction, revision);
            } else {
                await scrollToPosition(null, 0, progress * rootScrollGeometry().maxTop, revision);
            }
        }
        async function reflow(fontScale, lineSpacing, baseSize, expectedToken) {
            if (!isMarkdown || disposed || expectedToken !== token) return null;
            const saved = position();
            const revision = beginOperation();
            reflowDepth++;
            try {
                document.documentElement.style.setProperty('--reader-scale', String(Math.min(1.8, Math.max(.8, Number(fontScale) || 1))));
                document.documentElement.style.setProperty('--reader-spacing', `${Math.min(12, Math.max(0, Number(lineSpacing) || 0))}px`);
                document.documentElement.style.setProperty('--reader-base-size', `${Math.min(96, Math.max(12, Number(baseSize) || 17))}px`);
                await Promise.race([document.fonts?.ready || Promise.resolve(), new Promise(resolve => setTimeout(resolve, 2000))]);
                await new Promise(resolve => { setTimeout(resolve, 250); requestAnimationFrame(() => requestAnimationFrame(resolve)); });
                if (isCurrent(revision)) await restoreMarkdown(saved, revision);
            } finally {
                reflowDepth--;
            }
            if (!isCurrent(revision)) return null;
            paintCurrent();
            notify();
            return snapshot();
        }
        async function initialize() {
            const revision = operationRevision;
            if (!restorePosition) return;
            if (isMarkdown) { await restoreMarkdown(restorePosition, revision); return; }
            let saved = null;
            const anchor = restorePosition.anchorID;
            if (typeof anchor === 'string' && anchor.startsWith(positionPrefix)) {
                try { saved = JSON.parse(anchor.slice(positionPrefix.length)); } catch {}
            }
            if (saved && Array.isArray(saved.scrolls)) {
                for (const item of saved.scrolls) {
                    const element = elementAtPath(item?.path);
                    if (!element || (item.id && item.id !== element.id)) continue;
                    registerScroller(element);
                    if (!scrollContainers.has(element)) continue;
                    const top = Math.min(1, Math.max(0, Number(item.topFraction) || 0));
                    const left = Math.min(1, Math.max(-1, Number(item.leftFraction) || 0));
                    if (!await scrollToPosition(element,
                        left * Math.max(0, element.scrollWidth - element.clientWidth),
                        top * Math.max(0, element.scrollHeight - element.clientHeight), revision)) return;
                }
            }
            const progress = Math.min(1, Math.max(0, Number(restorePosition.progress) || 0));
            const left = saved ? Math.min(1, Math.max(-1, Number(saved.windowLeftFraction) || 0)) : 0;
            if (progress > 0 || saved) {
                const root = rootScrollGeometry();
                await scrollToPosition(null, left * root.maxLeft, progress * root.maxTop, revision);
            } else if (typeof anchor === 'string') {
                // Existing heading-N positions remain valid.
                await revealHeading(anchor, revision);
            }
        }
        document.addEventListener('touchstart', onUserInteraction, { capture: true, passive: true });
        document.addEventListener('wheel', onUserInteraction, { capture: true, passive: true });
        document.addEventListener('keydown', onKeyboardNavigation, { capture: true, passive: true });
        document.addEventListener('scroll', onScroll, { capture: true, passive: true });
        window.addEventListener('resize', onResize, { passive: true });
        window.visualViewport?.addEventListener('scroll', onScroll, { passive: true });
        window.visualViewport?.addEventListener('resize', onResize, { passive: true });
        return { search, navigate, dispose, snapshot, initialize, reflow, rememberViewport, suspendHighlights, resumeHighlights,
            headings: headings.map(({ id, title, level }) => ({ id, title, level })) };
    })();
    globalThis.__htmlPreviewReading = reader;
    await reader.initialize();
    reader.rememberViewport();
    if (globalThis.__htmlPreviewReading !== reader) return null;
    return { ...reader.snapshot(), headings: reader.headings };
    """#
}
