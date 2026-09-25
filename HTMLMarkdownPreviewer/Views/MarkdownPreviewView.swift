import SwiftUI

struct MarkdownPreviewView: View {
    let document: MarkdownDocument
    var readingState: DocumentReadingState? = nil

    @State private var blockedLink: BlockedMarkdownLink?
    @State private var index: MarkdownReadingIndex
    @State private var matches: [MarkdownReadingIndex.Match] = []
    @State private var frames: [String: CGRect] = [:]
    @State private var scrollAccess = MarkdownScrollAccess()
    @State private var hasPrepared = false
    @State private var pendingRestoration: ReadingPosition?
    @State private var didRequestRestoreAnchor = false
    @State private var isRestoring = false
    @State private var pendingJump: (elementID: String, blockID: String)?
    @State private var matchRects: [MarkdownReadingIndex.SearchTarget: CGRect] = [:]
    @State private var pendingMatch: MarkdownReadingIndex.SearchTarget?

    private let coordinateSpace = "markdown-reading-viewport"
    private let contentID = "markdown-reading-content"

    init(document: MarkdownDocument, readingState: DocumentReadingState? = nil) {
        self.document = document
        self.readingState = readingState
        _index = State(initialValue: MarkdownReadingIndex(document: document))
    }

    var body: some View {
        let highlight = self.highlight
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(document.blocks.enumerated()), id: \.offset) { offset, block in
                            let blockID = MarkdownReadingIndex.blockID(offset)
                            MarkdownBlockView(block: block, path: blockID, highlight: highlight)
                                .id(blockID)
                                .background(frameReader(for: blockID))
                        }
                    }
                    .frame(maxWidth: 680, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity)
                    .id(contentID)
                    .background(frameReader(for: contentID))
                    .background {
                        MarkdownScrollProbe { scrollView in
                            scrollAccess.scrollView = scrollView
                            restoreIfPossible(proxy: proxy, viewportHeight: viewport.size.height)
                        }
                    }
                }
                .coordinateSpace(name: coordinateSpace)
                .onPreferenceChange(MarkdownReadingFrames.self) { values in
                    frames = values
                    if isRestoring {
                        restoreIfPossible(proxy: proxy, viewportHeight: viewport.size.height)
                    } else if hasPrepared {
                        recordPosition(viewportHeight: viewport.size.height)
                    }
                    completeJumpIfPossible(proxy: proxy)
                }
                .onPreferenceChange(MarkdownSearchRects.self) { values in
                    matchRects = values
                    revealSelectedMatch(viewportHeight: viewport.size.height)
                }
                .onAppear { prepare(proxy: proxy, viewportHeight: viewport.size.height) }
                .onChange(of: document) { _, _ in
                    hasPrepared = false
                    prepare(proxy: proxy, viewportHeight: viewport.size.height)
                }
                .onChange(of: readingState?.query ?? "") { _, _ in
                    updateMatches(proxy: proxy)
                }
                .onChange(of: readingState?.navigationRequest) { _, request in
                    guard let request else { return }
                    navigate(request.target, proxy: proxy)
                }
            }
        }
        .background(Color(.systemBackground))
        .environment(\.openURL, OpenURLAction { url in
            blockedLink = MarkdownLinkPolicy.blockedLink(for: url)
            return .handled
        })
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
    }

    private var highlight: MarkdownSearchHighlight {
        let selected = readingState?.selectedMatch ?? -1
        let target = matches.indices.contains(selected) ? index.target(for: matches[selected], at: selected) : nil
        return MarkdownSearchHighlight(matches: matches, selected: selected, target: target)
    }

    private func frameReader(for id: String) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: MarkdownReadingFrames.self,
                value: [id: geometry.frame(in: .named(coordinateSpace))]
            )
        }
    }

    private func prepare(proxy: ScrollViewProxy, viewportHeight: CGFloat) {
        guard !hasPrepared else { return }
        hasPrepared = true
        index = MarkdownReadingIndex(document: document)
        readingState?.headings = index.headings
        pendingRestoration = readingState?.position
        isRestoring = pendingRestoration != nil
        didRequestRestoreAnchor = false
        updateMatches(proxy: proxy, jumpToFirst: false)
        readingState?.isReady = true
        restoreIfPossible(proxy: proxy, viewportHeight: viewportHeight)
    }

    private func updateMatches(proxy: ScrollViewProxy, jumpToFirst: Bool = true) {
        matches = index.matches(for: readingState?.query ?? "")
        readingState?.matchCount = matches.count
        readingState?.selectedMatch = matches.isEmpty ? -1 : 0
        if jumpToFirst, !matches.isEmpty {
            navigate(.match(0), proxy: proxy)
        }
    }

    private func navigate(_ target: ReadingNavigationRequest.Target, proxy: ScrollViewProxy) {
        pendingRestoration = nil
        isRestoring = false
        pendingJump = nil
        pendingMatch = nil
        switch target {
        case .heading(let id):
            guard let blockID = index.blockID(containing: id) else { return }
            jump(to: id, blockID: blockID, proxy: proxy)
        case .match(let selection):
            guard matches.indices.contains(selection) else { return }
            readingState?.selectedMatch = selection
            let match = matches[selection]
            pendingMatch = index.target(for: match, at: selection)
            if let pendingMatch, matchRects[pendingMatch] != nil,
               let scrollView = scrollAccess.scrollView {
                revealSelectedMatch(viewportHeight: scrollView.bounds.height)
                return
            }
            jump(to: match.elementID, blockID: match.blockID, proxy: proxy)
        case .beginning:
            if let first = index.blockIDs.first { proxy.scrollTo(first, anchor: .top) }
            readingState?.position = ReadingPosition(progress: 0)
        }
    }

    private func jump(to elementID: String, blockID: String, proxy: ScrollViewProxy) {
        // The outer destination materializes an off-screen lazy block. Once it
        // exists, the nested destination can reveal a quote, list item or cell.
        pendingJump = (elementID, blockID)
        proxy.scrollTo(blockID, anchor: .top)
        completeJumpIfPossible(proxy: proxy)
    }

    private func completeJumpIfPossible(proxy: ScrollViewProxy) {
        guard let jump = pendingJump, frames[jump.blockID] != nil else { return }
        pendingJump = nil
        proxy.scrollTo(MarkdownReadingIndex.elementAnchorID(jump.elementID), anchor: .top)
    }

    private func revealSelectedMatch(viewportHeight: CGFloat) {
        guard let target = pendingMatch, let rect = matchRects[target],
              let scrollView = scrollAccess.scrollView, viewportHeight > 0 else { return }
        pendingMatch = nil
        if rect.minY < 12 || rect.maxY > viewportHeight - 12 {
            let offset = scrollView.contentOffset.y + rect.minY - viewportHeight * 0.35
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: clampedOffset(offset, in: scrollView)),
                animated: false
            )
        }
    }

    private func restoreIfPossible(proxy: ScrollViewProxy, viewportHeight: CGFloat) {
        guard hasPrepared, isRestoring, let position = pendingRestoration,
              let scrollView = scrollAccess.scrollView,
              let contentFrame = frames[contentID], contentFrame.height > 0 else { return }
        if position.progress <= 0, position.anchorID == nil
            || MarkdownReadingIndex.StoredAnchor(position.anchorID)?.blockID == index.blockIDs.first {
            scrollView.setContentOffset(CGPoint(x: 0, y: -scrollView.adjustedContentInset.top), animated: false)
            pendingRestoration = nil
            isRestoring = false
            return
        }
        let anchor = MarkdownReadingIndex.StoredAnchor(position.anchorID)
        if let anchor, index.blockIDs.contains(anchor.blockID) {
            guard let blockFrame = frames[anchor.blockID] else {
                if !didRequestRestoreAnchor {
                    didRequestRestoreAnchor = true
                    proxy.scrollTo(anchor.blockID, anchor: .top)
                }
                return
            }
            let desiredOffset = scrollView.contentOffset.y + blockFrame.minY
                + blockFrame.height * anchor.fraction
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: clampedOffset(desiredOffset, in: scrollView)),
                animated: false
            )
        } else {
            let maximum = max(0, scrollView.contentSize.height - viewportHeight)
            scrollView.setContentOffset(CGPoint(x: 0, y: maximum * position.progress), animated: false)
        }
        pendingRestoration = nil
        isRestoring = false
    }

    private func clampedOffset(_ value: CGFloat, in scrollView: UIScrollView) -> CGFloat {
        let minimum = -scrollView.adjustedContentInset.top
        let maximum = max(minimum, scrollView.contentSize.height - scrollView.bounds.height
                          + scrollView.adjustedContentInset.bottom)
        return min(maximum, max(minimum, value))
    }

    private func recordPosition(viewportHeight: CGFloat) {
        guard let readingState, let contentFrame = frames[contentID], viewportHeight > 0 else { return }
        let blocks = index.blockIDs.compactMap { id -> (String, CGRect)? in
            guard let frame = frames[id], frame.height > 0 else { return nil }
            return (id, frame)
        }
        let firstVisible = blocks.first { $0.1.maxY > 0 } ?? blocks.last
        let anchor = firstVisible.map { id, frame in
            MarkdownReadingIndex.StoredAnchor(
                blockID: id,
                fraction: Double(max(0, -frame.minY) / frame.height)
            ).encoded
        }
        let range = max(0, contentFrame.height - viewportHeight)
        let progress = range > 0 ? Double(max(0, -contentFrame.minY) / range) : 0
        let position = ReadingPosition(anchorID: anchor, progress: progress)
        if position != readingState.position { readingState.position = position }
    }
}

private struct MarkdownReadingFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct MarkdownSearchRects: PreferenceKey {
    static let defaultValue: [MarkdownReadingIndex.SearchTarget: CGRect] = [:]

    static func reduce(
        value: inout [MarkdownReadingIndex.SearchTarget: CGRect],
        nextValue: () -> [MarkdownReadingIndex.SearchTarget: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct MarkdownMatchGeometry: View {
    let text: AttributedString
    let path: String
    let highlight: MarkdownSearchHighlight
    let font: UIFont
    var lineSpacing: CGFloat = 0
    var alignment: NSTextAlignment = .natural

    @State private var measuredRequest: MarkdownTextLayout.Request?
    @State private var measuredRect: CGRect?

    var body: some View {
        GeometryReader { geometry in
            if let target = highlight.target, target.elementID == path {
                let request = MarkdownTextLayout.Request(
                    text: text, range: target.range, width: geometry.size.width,
                    font: font, lineSpacing: lineSpacing, alignment: alignment
                )
                Color.clear
                    .onChange(of: request, initial: true) { _, request in
                        measuredRect = MarkdownTextLayout.matchRect(for: request)
                        measuredRequest = request
                    }
                    .overlay(alignment: .topLeading) {
                        if measuredRequest == request, let measuredRect {
                            // Padding participates in layout, making this a real
                            // destination for horizontal ScrollViewReader too.
                            Color.clear
                                .frame(width: max(1, measuredRect.width), height: measuredRect.height)
                                .id(target.anchorID)
                                .padding(.leading, max(0, measuredRect.minX))
                                .padding(.top, max(0, measuredRect.minY))
                                .preference(key: MarkdownSearchRects.self, value: [
                                    target: measuredRect.offsetBy(
                                        dx: geometry.frame(in: .named("markdown-reading-viewport")).minX,
                                        dy: geometry.frame(in: .named("markdown-reading-viewport")).minY
                                    )
                                ])
                        }
                    }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

@MainActor
private final class MarkdownScrollAccess {
    weak var scrollView: UIScrollView?
}

/// Access only this preview's enclosing scroll view; leave its delegate,
/// scrolling behavior and the app's other views untouched.
private struct MarkdownScrollProbe: UIViewRepresentable {
    let onResolve: (UIScrollView) -> Void

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.onResolve = onResolve
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: Probe, context: Context) { uiView.onResolve = onResolve }

    final class Probe: UIView {
        var onResolve: ((UIScrollView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self else { return }
                var ancestor = self.superview
                while let view = ancestor {
                    if let scrollView = view as? UIScrollView {
                        self.onResolve?(scrollView)
                        return
                    }
                    ancestor = view.superview
                }
            }
        }
    }
}

private struct MarkdownSearchHighlight {
    private let matchesByElement: [String: [(index: Int, range: Range<String.Index>)]]
    let selected: Int
    let target: MarkdownReadingIndex.SearchTarget?

    init(matches: [MarkdownReadingIndex.Match], selected: Int, target: MarkdownReadingIndex.SearchTarget?) {
        var grouped: [String: [(index: Int, range: Range<String.Index>)]] = [:]
        for (index, match) in matches.enumerated() {
            grouped[match.elementID, default: []].append((index, match.range))
        }
        self.matchesByElement = grouped
        self.selected = selected
        self.target = target
    }

    func text(_ value: AttributedString, id: String) -> AttributedString {
        var result = value
        let plain = String(value.characters)
        for match in matchesByElement[id] ?? [] {
            let startOffset = plain.distance(from: plain.startIndex, to: match.range.lowerBound)
            let endOffset = plain.distance(from: plain.startIndex, to: match.range.upperBound)
            let start = result.characters.index(result.startIndex, offsetBy: startOffset)
            let end = result.characters.index(result.startIndex, offsetBy: endOffset)
            result[start..<end].backgroundColor = match.index == selected
                ? Color.orange.opacity(0.55) : Color.yellow.opacity(0.32)
            result[start..<end].foregroundColor = .primary
        }
        return result
    }
}

struct BlockedMarkdownLink: Identifiable, Equatable {
    enum Reason: Equatable {
        case externalWebURL
        case unsupportedURL
    }

    let url: URL
    let reason: Reason

    var id: String {
        "\(reason)-\(url.absoluteString)"
    }

    var title: String {
        switch reason {
        case .externalWebURL:
            AppStrings.Security.externalMarkdownLinkTitle
        case .unsupportedURL:
            AppStrings.Security.unsupportedMarkdownLinkTitle
        }
    }

    var message: String {
        switch reason {
        case .externalWebURL:
            AppStrings.Security.externalMarkdownLinkMessage
        case .unsupportedURL:
            AppStrings.Security.unsupportedMarkdownLinkMessage
        }
    }
}

enum MarkdownLinkPolicy {
    static func blockedLink(for url: URL) -> BlockedMarkdownLink {
        if let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return BlockedMarkdownLink(url: url, reason: .externalWebURL)
        }

        return BlockedMarkdownLink(url: url, reason: .unsupportedURL)
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let path: String
    let highlight: MarkdownSearchHighlight
    @State private var revealedHorizontalTarget: MarkdownReadingIndex.SearchTarget?

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(highlight.text(text, id: path))
                .id(MarkdownReadingIndex.elementAnchorID(path))
                .font(font(forHeadingLevel: level))
                .fontWeight(level <= 2 ? .bold : .semibold)
                .textSelection(.enabled)
                .background(MarkdownMatchGeometry(text: text, path: path, highlight: highlight, font: uiFont(forHeadingLevel: level)))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, level == 1 ? 0 : 12)
        case .paragraph(let text):
            Text(highlight.text(text, id: path))
                .id(MarkdownReadingIndex.elementAnchorID(path))
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)
                .background(MarkdownMatchGeometry(text: text, path: path, highlight: highlight,
                                                  font: .preferredFont(forTextStyle: .body), lineSpacing: 4))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .blockQuote(let blocks):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { offset, child in
                        MarkdownBlockView(block: child, path: MarkdownReadingIndex.childID(path, offset: offset), highlight: highlight)
                    }
                }
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 8) {
                if let language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(highlight.text(AttributedString(code), id: path))
                            .id(MarkdownReadingIndex.elementAnchorID(path))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .background(MarkdownMatchGeometry(
                                text: AttributedString(code), path: path, highlight: highlight,
                                font: .monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
                                                           weight: .regular)
                            ))
                    }
                    .onPreferenceChange(MarkdownSearchRects.self) { values in
                        guard let target = highlight.target, target.elementID == path else {
                            revealedHorizontalTarget = nil
                            return
                        }
                        guard values[target] != nil, target != revealedHorizontalTarget else { return }
                        revealedHorizontalTarget = target
                        proxy.scrollTo(target.anchorID, anchor: .center)
                    }
                }
            }
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        case .unorderedList(let items):
            MarkdownListView(items: items, start: nil, path: path, highlight: highlight)
        case .orderedList(let start, let items):
            MarkdownListView(items: items, start: start, path: path, highlight: highlight)
        case .table(let table):
            MarkdownTableView(table: table, path: path, highlight: highlight)
        case .image(let image):
            MarkdownImageView(image: image)
        case .thematicBreak:
            Divider()
        }
    }

    private func font(forHeadingLevel level: Int) -> Font {
        switch level {
        case 1: .largeTitle.bold()
        case 2: .title2.bold()
        case 3: .title3.weight(.semibold)
        default: .headline
        }
    }

    private func uiFont(forHeadingLevel level: Int) -> UIFont {
        let style: UIFont.TextStyle = switch level {
        case 1: .largeTitle
        case 2: .title2
        case 3: .title3
        default: .headline
        }
        return .systemFont(ofSize: UIFont.preferredFont(forTextStyle: style).pointSize,
                           weight: level <= 2 ? .bold : .semibold)
    }
}

private struct MarkdownTableView: View {
    let table: MarkdownTable
    let path: String
    let highlight: MarkdownSearchHighlight
    @State private var revealedHorizontalTarget: MarkdownReadingIndex.SearchTarget?

    @ScaledMetric(relativeTo: .body) private var minimumColumnWidth: CGFloat = 88
    @ScaledMetric(relativeTo: .body) private var maximumColumnWidth: CGFloat = 240

    var body: some View {
        let widths = columnWidths

        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                    tableRow(table.header, widths: widths, row: -1, isHeader: true)
                        .background(Color(.secondarySystemBackground))
                    ForEach(table.rows.indices, id: \.self) { rowIndex in
                        tableRow(table.rows[rowIndex], widths: widths, row: rowIndex, isHeader: false)
                            .background(rowIndex.isMultiple(of: 2) ? Color(.systemBackground) : Color(.tertiarySystemBackground))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                }
                .padding(.bottom, 6)
            }
            .onPreferenceChange(MarkdownSearchRects.self) { values in
                guard let target = highlight.target, target.elementID.hasPrefix(path + "-row-") else {
                    revealedHorizontalTarget = nil
                    return
                }
                guard values[target] != nil, target != revealedHorizontalTarget else { return }
                revealedHorizontalTarget = target
                proxy.scrollTo(target.anchorID, anchor: .center)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func tableRow(_ cells: [AttributedString], widths: [CGFloat], row: Int, isHeader: Bool) -> some View {
        GridRow(alignment: .top) {
            ForEach(cells.indices, id: \.self) { column in
                let cellID = MarkdownReadingIndex.cellID(path, row: row, column: column)
                Text(highlight.text(cells[column], id: cellID))
                    .id(MarkdownReadingIndex.elementAnchorID(cellID))
                    .font(.body)
                    .fontWeight(isHeader ? .semibold : nil)
                    .multilineTextAlignment(textAlignment(for: table.columnAlignments[column]))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: widths[column], alignment: frameAlignment(for: table.columnAlignments[column]))
                    .background(MarkdownMatchGeometry(
                        text: cells[column], path: cellID, highlight: highlight,
                        font: .systemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
                                          weight: isHeader ? .semibold : .regular),
                        alignment: nsTextAlignment(for: table.columnAlignments[column])
                    ))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .accessibilityLabel(accessibilityLabel(for: cells[column], column: column, isHeader: isHeader))
                    .accessibilityAddTraits(isHeader ? .isHeader : [])
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }

    private var columnWidths: [CGFloat] {
        let font = UIFont.boldSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize)
        return table.header.indices.map { column in
            let cells = [table.header[column]] + table.rows.map { $0[column] }
            let textWidth = cells.map { cell in
                (String(cell.characters) as NSString).size(withAttributes: [.font: font]).width
            }.max() ?? 0
            return min(maximumColumnWidth, max(minimumColumnWidth, ceil(textWidth)))
        }
    }

    private func frameAlignment(for alignment: MarkdownTable.ColumnAlignment) -> Alignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private func textAlignment(for alignment: MarkdownTable.ColumnAlignment) -> TextAlignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private func nsTextAlignment(for alignment: MarkdownTable.ColumnAlignment) -> NSTextAlignment {
        switch alignment {
        case .leading: .natural
        case .center: .center
        case .trailing: .right
        }
    }

    private func accessibilityLabel(for cell: AttributedString, column: Int, isHeader: Bool) -> Text {
        if isHeader || table.header[column].characters.isEmpty {
            return Text(cell)
        }
        return Text(table.header[column]) + Text(": ") + Text(cell)
    }
}

private struct MarkdownListView: View {
    let items: [MarkdownListItem]
    let start: Int?
    let path: String
    let highlight: MarkdownSearchHighlight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text(marker(for: index))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 8) {
                        let itemID = MarkdownReadingIndex.itemID(path, offset: index)
                        Text(highlight.text(item.text, id: itemID))
                            .id(MarkdownReadingIndex.elementAnchorID(itemID))
                            .font(.body)
                            .textSelection(.enabled)
                            .background(MarkdownMatchGeometry(text: item.text, path: itemID, highlight: highlight,
                                                              font: .preferredFont(forTextStyle: .body)))
                        ForEach(Array(item.children.enumerated()), id: \.offset) { childOffset, child in
                            MarkdownBlockView(block: child, path: MarkdownReadingIndex.childID(itemID, offset: childOffset), highlight: highlight)
                        }
                    }
                }
            }
        }
    }

    private func marker(for index: Int) -> String {
        if let start {
            return "\(start + index)."
        }
        return "•"
    }
}

private struct MarkdownImageView: View {
    let image: MarkdownImage

    var body: some View {
        switch image.kind {
        case .local(let url):
            if let uiImage = UIImage(contentsOfFile: url.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(image.altText.isEmpty ? AppStrings.Accessibility.markdownImage : image.altText)
            } else {
                placeholder(AppStrings.MarkdownImages.localUnavailable, detail: image.source)
            }
        case .remoteBlocked(let source):
            placeholder(AppStrings.MarkdownImages.remoteBlocked, detail: source)
        case .unsupported(let source):
            placeholder(AppStrings.MarkdownImages.unsupported, detail: source)
        }
    }

    private func placeholder(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: "photo")
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(detail)")
    }
}

#Preview {
    MarkdownPreviewView(
        document: MarkdownRenderService().render(
            markdown: """
            # Preview

            A paragraph with **strong text**, *emphasis*, and `code`.

            - First
            - Second

            > A quote.

            | Item | Status | Count |
            | :--- | :---: | ---: |
            | **Reports** | Ready | 12 |
            | Notes with a longer description that wraps | Review | 3 |
            """
        )
    )
}
