import Foundation
import WebKit

/// App-owned reading tools run in a separate JavaScript world. Page JavaScript and
/// the preview's content rules remain controlled solely by HTMLPreviewConfiguration.
@MainActor
final class HTMLReadingController {
    static let contentWorld = WKContentWorld.world(name: "com.kaede.htmlmarkdownpreviewer.reading")

    private let state: DocumentReadingState
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

    init(state: DocumentReadingState, entryURL: URL) {
        self.state = state
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
        var arguments: [String: Any] = ["sessionID": sessionID, "handlerName": handlerName]
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
        const excluded = 'script,style,noscript,template,textarea,input,select,option,[contenteditable="true"],[aria-hidden="true"]';
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
        let positionSequence = 0;
        let operationRevision = 0;
        const pendingScrolls = new Set();
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
        const headings = Array.from(document.querySelectorAll('h1,h2,h3,h4,h5,h6'))
            .filter(visible)
            .map((element, index) => ({
                element, id: `heading-${index}`,
                title: (element.innerText || '').replace(/\s+/g, ' ').trim(),
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
        function position() {
            const extent = Math.max(0, scrollingRoot.scrollHeight - scrollingRoot.clientHeight);
            const y = Math.max(0, scrollingRoot.scrollTop);
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
            const windowLeftFraction = fraction(scrollingRoot.scrollLeft, scrollingRoot.scrollWidth - scrollingRoot.clientWidth, true);
            const anchorID = scrolls.length || windowLeftFraction
                ? positionPrefix + JSON.stringify({ heading: headingID, scrolls, windowLeftFraction })
                : headingID;
            return { sessionID: token, sequence: ++positionSequence, anchorID, progress: fraction(y, extent) };
        }
        function snapshot() {
            return { ...position(), matchCount: ranges.length, selectedMatch };
        }
        function notify() {
            if (!disposed && !highlightSuspensions) globalThis.webkit?.messageHandlers[handlerName]?.postMessage(position());
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
            for (const range of ranges) highlight.add(range);
            CSS.highlights.set(matchStyleName, highlight);
        }
        function clippedRects(range) {
            const viewport = usableViewport(null, range.startContainer.parentElement);
            const clip = { ...viewport };
            for (let element = range.startContainer.parentElement; element; element = element.parentElement) {
                if (element === scrollingRoot || element === document.documentElement) continue;
                const css = getComputedStyle(element);
                const box = viewportFor(element);
                if (css.overflowX !== 'visible') { clip.left = Math.max(clip.left, box.left); clip.right = Math.min(clip.right, box.right); }
                if (css.overflowY !== 'visible') { clip.top = Math.max(clip.top, box.top); clip.bottom = Math.min(clip.bottom, box.bottom); }
            }
            return Array.from(range.getClientRects()).map(rect => ({
                left: Math.max(rect.left, clip.left), right: Math.min(rect.right, clip.right),
                top: Math.max(rect.top, clip.top), bottom: Math.min(rect.bottom, clip.bottom)
            })).filter(rect => rect.right > rect.left && rect.bottom > rect.top);
        }
        function paintCurrent() {
            if (highlightSuspensions || disposed) return;
            if (hasHighlights) {
                CSS.highlights.delete(currentStyleName);
                if (selectedMatch >= 0) CSS.highlights.set(currentStyleName, new Highlight(ranges[selectedMatch]));
                return;
            }
            // Safari 17.0/17.1: draw only the selected range without modifying text.
            fallbackOverlay?.remove();
            fallbackOverlay = null;
            if (selectedMatch < 0) return;
            const overlay = document.createElement('div');
            overlay.setAttribute('data-html-previewer-reading-overlay', '');
            overlay.setAttribute('aria-hidden', 'true');
            overlay.style.cssText = 'position:fixed;inset:0;overflow:hidden;pointer-events:none;z-index:2147483647;contain:strict;';
            for (const rect of clippedRects(ranges[selectedMatch])) {
                const part = document.createElement('div');
                part.style.cssText = `position:absolute;left:${rect.left}px;top:${rect.top}px;width:${rect.right - rect.left}px;height:${rect.bottom - rect.top}px;background:rgba(255,152,47,.42);border-radius:2px;`;
                overlay.appendChild(part);
            }
            document.documentElement.appendChild(overlay);
            fallbackOverlay = overlay;
        }
        function onScroll(event) {
            if (disposed || highlightSuspensions) return;
            registerScroller(event.target);
            // Persist every actual scroll event; the Swift store debounces disk writes.
            // The slower visual fallback can be redrawn on a separate throttle.
            notify();
            if (scrollTimer !== null) return;
            scrollTimer = setTimeout(() => { scrollTimer = null; paintCurrent(); }, 80);
        }
        function targetRect(range) {
            return Array.from(range.getClientRects()).find(rect => rect.width > 0 && rect.height > 0) || range.getBoundingClientRect();
        }
        function nearestDelta(start, end, near, far) {
            if (start < near) return start - near;
            if (end > far) return end - far;
            return 0;
        }
        function isCurrent(revision) { return !disposed && revision === operationRevision; }
        function beginOperation() {
            operationRevision++;
            for (const cancel of Array.from(pendingScrolls)) cancel();
            return operationRevision;
        }
        async function scrollToPosition(element, left, top, revision) {
            if (!isCurrent(revision)) return false;
            const scroller = element || scrollingRoot;
            const maxLeft = Math.max(0, scroller.scrollWidth - scroller.clientWidth);
            const maxTop = Math.max(0, scroller.scrollHeight - scroller.clientHeight);
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
                const eventTarget = element || document;
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
                    const geometry = [scroller.scrollLeft, scroller.scrollTop,
                        scroller.clientWidth, scroller.clientHeight, scroller.scrollWidth, scroller.scrollHeight];
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
            const target = range.startContainer.parentElement;
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
            const rootLeft = scrollingRoot.scrollLeft;
            const rootTop = scrollingRoot.scrollTop;
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
                    if (node.tagName === 'BR' && visible(node)) text += '\n';
                    continue;
                }
                const parent = node.parentElement;
                if (!parent || !node.data.length) continue;
                if (!visibility.has(parent)) visibility.set(parent, visible(parent));
                if (!visibility.get(parent)) continue;
                const block = parent.closest(blockSelector);
                if (previousBlock && previousBlock !== block) text += '\n';
                previousBlock = block;
                segments.push({ node, start: text.length, end: text.length + node.data.length });
                text += node.data;
            }
            const escaped = needle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/\s+/g, '\\s+');
            const expression = new RegExp(escaped, 'giu');
            let match;
            let segmentIndex = 0;
            while ((match = expression.exec(text)) !== null) {
                const start = match.index;
                const end = start + match[0].length;
                while (segmentIndex < segments.length && segments[segmentIndex].end <= start) segmentIndex++;
                const first = segments[segmentIndex];
                if (!first || first.start > start) continue;
                let endIndex = segmentIndex;
                while (endIndex < segments.length && segments[endIndex].end < end) endIndex++;
                const last = segments[endIndex];
                if (!last || last.start >= end) continue;
                const range = document.createRange();
                range.setStart(first.node, start - first.start);
                range.setEnd(last.node, end - last.start);
                if (range.getClientRects().length) ranges.push(range);
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
            if (operation === 'heading') await revealHeading(value, revision);
            else if (operation === 'match') await select(value, revision);
            else if (operation === 'beginning') {
                await Promise.all(Array.from(scrollContainers.keys()).map(element => scrollToPosition(element, 0, 0, revision)));
                if (isCurrent(revision)) await scrollToPosition(null, 0, 0, revision);
            }
            if (!isCurrent(revision)) return null;
            paintCurrent();
            notify();
            return snapshot();
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
            document.removeEventListener('scroll', onScroll, true);
            window.removeEventListener('resize', onScroll);
            clearHighlights();
            style.remove();
        }
        async function initialize() {
            const revision = operationRevision;
            if (!restorePosition) return;
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
                await scrollToPosition(null,
                    left * Math.max(0, scrollingRoot.scrollWidth - scrollingRoot.clientWidth),
                    progress * Math.max(0, scrollingRoot.scrollHeight - scrollingRoot.clientHeight), revision);
            } else if (typeof anchor === 'string') {
                // Existing heading-N positions remain valid.
                await revealHeading(anchor, revision);
            }
        }
        document.addEventListener('scroll', onScroll, { capture: true, passive: true });
        window.addEventListener('resize', onScroll, { passive: true });
        return { search, navigate, dispose, snapshot, initialize, suspendHighlights, resumeHighlights,
            headings: headings.map(({ id, title, level }) => ({ id, title, level })) };
    })();
    globalThis.__htmlPreviewReading = reader;
    await reader.initialize();
    if (globalThis.__htmlPreviewReading !== reader) return null;
    return { ...reader.snapshot(), headings: reader.headings };
    """#
}
