import SwiftUI
import UIKit

struct YAMLPreviewView: View {
    let fileURL: URL
    let reading: DocumentReadingState
    var format: StructuredDocumentFormat = .yaml
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var usesCompactControls: Bool {
        if #available(iOS 27.1, *) { return verticalSizeClass == .compact }
        return false
    }

    /// Short heights and wide readers both have room for one row of controls.
    private var usesHorizontalControls: Bool {
        usesCompactControls || horizontalSizeClass == .regular
    }

    /// iOS 27.1 hosts these actions in the system toolbar, which can sit
    /// beside the reader and keeps the ellipsis for the system overflow menu.
    private var usesToolbarOptions: Bool {
        if #available(iOS 27.1, *) { return true }
        return false
    }

    private var controlsLayout: AnyLayout {
        usesHorizontalControls ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 10))
    }

    private var searchLayout: AnyLayout {
        usesHorizontalControls ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 8))
    }

    private var optionsTitle: String { format == .json ? JSONStrings.options : YAMLStrings.options }
    private var syntaxErrorTitle: String { format == .json ? JSONStrings.syntaxError : YAMLStrings.syntaxError }
    private var emptyTitle: String { format == .json ? JSONStrings.empty : YAMLStrings.empty }

    @State private var document: YAMLDocument?
    @State private var loadError: String?
    @State private var mode: YAMLPreviewMode = .structure
    @State private var sheetIndex = 0
    @State private var collapsed = Set<String>()
    @State private var query = ""
    @State private var resultIndex = 0
    @State private var visibleID: String?
    @State private var scrollRequest = ScrollRequest(target: "")
    @State private var copied = false
    @State private var copyTask: Task<Void, Never>?
    @State private var contentFold: ReaderFoldBand?
    @FocusState private var isSearchFocused: Bool

    private struct ScrollRequest: Equatable {
        let id = UUID()
        let target: String
        var anchor: UnitPoint = .topLeading
    }

    private var searchScrollAnchor: UnitPoint {
        if #available(iOS 27.1, *) {
            // A fold across the middle would cut the centered row in half.
            if let contentFold { return UnitPoint(x: 0, y: max(0.05, contentFold.top - 0.12)) }
            return UnitPoint(x: 0, y: 0.5)
        }
        return .topLeading
    }

    private var sheet: YAMLSheet? {
        guard let document, document.sheets.indices.contains(sheetIndex) else { return nil }
        return document.sheets[sheetIndex]
    }
    private var issue: YAMLIssue? { sheet?.issue ?? document?.issue }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var resultIDs: [String] {
        guard !trimmedQuery.isEmpty else { return [] }
        if mode == .source {
            return document?.lines.filter { $0.text.localizedStandardContains(trimmedQuery) }.map(\.id) ?? []
        }
        return visibleRows.filter { $0.matches(trimmedQuery) }.map(\.id)
    }
    private var selectedResult: String? {
        resultIDs.indices.contains(resultIndex) ? resultIDs[resultIndex] : nil
    }
    private var visibleRows: [YAMLRow] {
        guard let rows = sheet?.rows else { return [] }
        let rootIsCollection = rows.first?.isExpandable == true
        // Preserve the tree context without laying out unrelated branches during search.
        // The saved collapse state is untouched, so clearing search restores it.
        var searchIDs = Set<String>()
        if !trimmedQuery.isEmpty {
            for row in rows where row.matches(trimmedQuery) {
                searchIDs.insert(row.id)
                searchIDs.formUnion(row.parents)
            }
        }
        return rows.filter { row in
            if rootIsCollection && row.depth == 0 { return false }
            if !trimmedQuery.isEmpty { return searchIDs.contains(row.id) }
            return !row.parents.contains(where: { collapsed.contains($0) })
        }
    }

    var body: some View {
        Group {
            if let document {
                VStack(spacing: 0) {
                    controls(document)
                    if let issue { diagnostic(issue) }
                    searchBar
                    content(document)
                }
            } else if let loadError {
                ContentUnavailableView(AppStrings.Errors.cannotOpenFileTitle, systemImage: "doc.text",
                                       description: Text(loadError))
            } else {
                ProgressView()
            }
        }
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            if copied {
                Label(YAMLStrings.copied, systemImage: "checkmark")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(16)
                    .accessibilityIdentifier("\(format.rawValue)-copied-feedback")
                    .allowsHitTesting(false)
            }
        }
        .task(id: fileURL) {
            let url = fileURL
            let selectedFormat = format
            let task = Task.detached(priority: .userInitiated) {
                switch selectedFormat {
                case .json: return try JSONRenderService().render(fileURL: url)
                case .yaml: return try YAMLRenderService().render(fileURL: url)
                }
            }
            do {
                let parsed = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                try Task.checkCancellation()
                document = parsed
                if let saved = YAMLReadingLocation(reading.position, format: format),
                   parsed.sheets.indices.contains(saved.documentIndex)
                    || (parsed.sheets.isEmpty && saved.documentIndex == 0 && saved.mode == .source) {
                    sheetIndex = saved.documentIndex
                    mode = saved.mode
                    resetCollapse()
                    if let row = sheet?.rows.first(where: { $0.id == saved.target }) {
                        collapsed.subtract(row.parents)
                    }
                    requestScroll(saved.target)
                } else {
                    mode = issue == nil ? .structure : .source
                    resetCollapse()
                }
                if issue != nil { mode = .source }
                reading.isReady = true
            } catch is CancellationError {
                return
            } catch {
                loadError = error.localizedDescription
            }
        }
        .toolbar {
            if #available(iOS 27.1, *), let document {
                ToolbarItem(placement: .bottomBar) {
                    optionsMenu(document)
                }
            }
        }
        .onChange(of: query) { resetSearch() }
        .onChange(of: visibleID) { persistLocation() }
        .onDisappear { copyTask?.cancel() }
    }

    private func controls(_ document: YAMLDocument) -> some View {
        controlsLayout {
            HStack {
                if document.sheets.count > 1 {
                    Menu {
                        ForEach(document.sheets, id: \.index) { sheet in
                            Button {
                                selectSheet(sheet.index)
                            } label: {
                                Label(YAMLStrings.document(sheet.index, count: document.sheets.count),
                                      systemImage: sheet.index == sheetIndex ? "checkmark" : "doc.text")
                            }
                            .accessibilityIdentifier("\(format.rawValue)-document-\(sheet.index)")
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(YAMLStrings.document(sheetIndex, count: document.sheets.count))
                            Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                        }
                    }
                    .accessibilityIdentifier("\(format.rawValue)-document-menu")
                } else if !usesCompactControls {
                    Text(format.title).fontWeight(.semibold)
                }
                if !usesCompactControls {
                    Spacer()
                    if let root = sheet?.rows.first {
                        Text(YAMLStrings.kind(root.kind, count: root.count))
                            .foregroundStyle(.secondary)
                    }
                }
                if !usesToolbarOptions {
                    optionsMenu(document)
                }
            }
            .font(.subheadline)
            .fixedSize(horizontal: usesCompactControls, vertical: false)

            Picker(format.title, selection: Binding(get: { mode }, set: { candidate in
                if candidate != .structure || issue == nil { selectMode(candidate) }
            })) {
                Text(YAMLStrings.structure).tag(YAMLPreviewMode.structure).disabled(issue != nil)
                Text(YAMLStrings.source).tag(YAMLPreviewMode.source)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: usesHorizontalControls && !usesCompactControls ? 300 : .infinity)
            .accessibilityIdentifier("\(format.rawValue)-view-picker")
            .layoutPriority(1)
        }
        .padding(.horizontal, 16).padding(.bottom, usesCompactControls ? 4 : 12)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func diagnostic(_ issue: YAMLIssue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(issue.code == "syntax" ? syntaxErrorTitle : YAMLStrings.structure,
                  systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
            Text(format == .json ? JSONStrings.issue(issue) : YAMLStrings.issue(issue))
                .font(.footnote).accessibilityIdentifier("\(format.rawValue)-error-location")
            if issue.code == "syntax" {
                Text(issue.message).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(format.rawValue)-error-message")
                Button(YAMLStrings.showError) { showSource(line: issue.line) }
                    .font(.footnote.weight(.semibold))
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("\(format.rawValue)-show-error")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.orange.opacity(0.1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(format.rawValue)-diagnostic")
    }

    private func optionsMenu(_ document: YAMLDocument) -> some View {
        Menu {
            Button(YAMLStrings.expandAll, systemImage: "arrow.down.right.and.arrow.up.left") { collapsed.removeAll() }
                .disabled(mode != .structure || issue != nil)
                .accessibilityIdentifier("\(format.rawValue)-expand-all")
            Button(YAMLStrings.collapseAll, systemImage: "arrow.up.left.and.arrow.down.right") {
                collapsed = Set((sheet?.rows ?? []).filter { $0.depth > 0 && $0.isExpandable }.map(\.id))
            }
            .disabled(mode != .structure || issue != nil || !trimmedQuery.isEmpty)
            .accessibilityIdentifier("\(format.rawValue)-collapse-all")
            Divider()
            Button(YAMLStrings.copySource, systemImage: "doc.on.doc") { copy(document.source) }
                .disabled(document.issue?.code == "sizeLimit")
                .accessibilityIdentifier("\(format.rawValue)-copy-source")
        } label: {
            if usesToolbarOptions {
                Label(optionsTitle, systemImage: "list.bullet.indent")
            } else {
                Image(systemName: "ellipsis.circle").font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .accessibilityLabel(optionsTitle)
        .accessibilityIdentifier("\(format.rawValue)-options-menu")
    }

    private var searchBar: some View {
        // AnyLayout moves the same field subtree instead of replacing its first responder.
        searchLayout {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(mode == .source ? YAMLStrings.searchSource : YAMLStrings.search, text: $query)
                    .font(.subheadline)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isSearchFocused)
                    .onSubmit { isSearchFocused = false }
                    .accessibilityIdentifier("\(format.rawValue)-search-field")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel(YAMLStrings.clearSearch)
                    .accessibilityIdentifier("\(format.rawValue)-search-clear")
                }
            }
            .padding(.horizontal, 10)
            .frame(minWidth: usesCompactControls ? 120 : nil, maxWidth: .infinity,
                   minHeight: usesCompactControls ? 44 : 40)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            if !trimmedQuery.isEmpty {
                HStack {
                    Text(YAMLStrings.results(resultIndex, count: resultIDs.count))
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("\(format.rawValue)-match-count")
                    if !usesHorizontalControls { Spacer() }
                    Button { moveResult(forward: false) } label: {
                        Image(systemName: "chevron.up")
                            .frame(width: usesCompactControls ? 44 : 40, height: usesCompactControls ? 44 : 32)
                    }
                        .accessibilityLabel(YAMLStrings.previous).accessibilityIdentifier("\(format.rawValue)-previous-result")
                    Button { moveResult(forward: true) } label: {
                        Image(systemName: "chevron.down")
                            .frame(width: usesCompactControls ? 44 : 40, height: usesCompactControls ? 44 : 32)
                    }
                        .accessibilityLabel(YAMLStrings.next).accessibilityIdentifier("\(format.rawValue)-next-result")
                }
                .disabled(resultIDs.isEmpty)
                .fixedSize(horizontal: usesHorizontalControls, vertical: false)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, usesCompactControls ? 4 : 10)
    }

    private func content(_ document: YAMLDocument) -> some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView(mode == .source ? [.vertical, .horizontal] : [.vertical]) {
                    contentRows(document, viewportWidth: viewport.size.width)
                    .scrollTargetLayout()
                    .padding(.bottom, 20)
                    .frame(minWidth: viewport.size.width,
                           maxWidth: mode == .structure ? .infinity : nil,
                           minHeight: viewport.size.height, alignment: .topLeading)
                }
                .defaultScrollAnchor(.topLeading)
                .scrollPosition(id: $visibleID, anchor: .topLeading)
                .scrollDismissesKeyboard(.interactively)
                .id(mode) // Source and tree use different row heights and scroll geometry.
                .accessibilityIdentifier(mode == .source ? "\(format.rawValue)-source-content" : "\(format.rawValue)-structure-content")
                .onChange(of: FoldGeometry.horizontalBand(in: viewport), initial: true) { _, fold in
                    contentFold = fold
                    if fold != nil, let selectedResult { requestScroll(selectedResult, anchor: searchScrollAnchor) }
                }
                .onChange(of: viewport.size) {
                    if #available(iOS 27.1, *), isSearchFocused, let selectedResult {
                        // Folding and software-keyboard changes can retain a
                        // visible ancestor while pushing its selected value out
                        // of the reduced viewport. Remeasure the active result.
                        requestScroll(selectedResult, anchor: searchScrollAnchor)
                    }
                }
                .onChange(of: scrollRequest, initial: true) {
                    let request = scrollRequest
                    Task { @MainActor in
                        // Let a source/structure switch and search expansion settle.
                        try? await Task.sleep(for: .milliseconds(100))
                        guard request == scrollRequest else { return }
                        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(request.target, anchor: request.anchor) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func contentRows(_ document: YAMLDocument, viewportWidth: CGFloat) -> some View {
        if mode == .structure && !trimmedQuery.isEmpty && visibleRows.count <= 200 {
            // Exact heights keep scrollTo reliable when Dynamic Type wraps each row.
            // Bound eager layout so broad searches and large documents remain lazy.
            VStack(alignment: .leading, spacing: 0) {
                rows(document, viewportWidth: viewportWidth)
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                rows(document, viewportWidth: viewportWidth)
            }
        }
    }

    @ViewBuilder
    private func rows(_ document: YAMLDocument, viewportWidth: CGFloat) -> some View {
        if mode == .source {
            ForEach(document.lines) { line in
                sourceLine(line)
                    // Short lines must be full-width scroll targets;
                    // otherwise a bidirectional scroll view can align
                    // their narrow bounds in the middle of the viewport.
                    .frame(minWidth: viewportWidth, alignment: .leading)
                    .id(line.id)
            }
            if document.isSourceTruncated {
                Text(YAMLStrings.sourceLimited).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 320, alignment: .leading)
                    .padding(16)
            }
        } else if issue != nil || sheet?.rows.isEmpty != false {
            Text(emptyTitle).foregroundStyle(.secondary).padding(20)
        } else {
            ForEach(visibleRows) { row in
                treeRow(row, keyColumnWidth: viewportWidth >= 480 ? min(220, viewportWidth * 0.3) : nil)
                    .id(row.id)
            }
        }
    }

    /// A key column width puts key, value and type on one line in wide readers.
    private func treeRow(_ row: YAMLRow, keyColumnWidth: CGFloat?) -> some View {
        let depth = max(0, row.depth - ((sheet?.rows.first?.isCollection == true) ? 1 : 0))
        let isMatch = !trimmedQuery.isEmpty && row.matches(trimmedQuery)
        let selected = selectedResult == row.id
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 10) {
                if row.isExpandable {
                    Button {
                        if collapsed.contains(row.id) { collapsed.remove(row.id) } else { collapsed.insert(row.id) }
                    } label: {
                        Image(systemName: collapsed.contains(row.id) && trimmedQuery.isEmpty ? "chevron.right" : "chevron.down")
                            .font(.caption.weight(.semibold)).frame(width: 28, height: 30)
                    }
                    .accessibilityLabel("\(collapsed.contains(row.id) ? YAMLStrings.expandAll : YAMLStrings.collapseAll): \(row.label)")
                    .accessibilityIdentifier("\(format.rawValue)-toggle-\(row.path)")
                    .disabled(!trimmedQuery.isEmpty)
                } else {
                    Image(systemName: row.kind == .alias ? "link" : "circle.fill")
                        .font(.system(size: row.kind == .alias ? 12 : 5))
                        .foregroundStyle(.tertiary).frame(width: 28, height: 30)
                }
                VStack(alignment: .leading, spacing: 5) {
                    if let keyColumnWidth {
                        // Wide readers keep key, value and type on one line,
                        // so the value sits beside its key instead of below it.
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            rowKey(row)
                                .frame(width: keyColumnWidth, alignment: .leading)
                            if !row.isCollection { rowValue(row) }
                            Spacer(minLength: 0)
                            rowKind(row)
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            rowKey(row)
                            Spacer(minLength: 0)
                            rowKind(row)
                        }
                        if !row.isCollection { rowValue(row) }
                    }
                    if !row.anchor.isEmpty {
                        Text("&\(row.anchor)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    if !row.tag.isEmpty {
                        Text(row.tag).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    if isMatch {
                        Text(row.path).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12 + CGFloat(min(depth, 8)) * 14).padding(.trailing, 16).padding(.vertical, 9)
        .background(selected ? Color.accentColor.opacity(0.15) : isMatch ? Color.yellow.opacity(0.12) : Color.clear)
        .overlay(alignment: .bottom) { Divider().padding(.leading, 16) }
        .contextMenu {
            if !row.isCollection || row.sourceRange != nil {
                Button(YAMLStrings.copyValue, systemImage: "doc.on.doc") {
                    if let text = document?.copyValue(for: row) { copy(text) }
                }
                .accessibilityIdentifier("\(format.rawValue)-copy-value")
            }
            Button(YAMLStrings.copyPath, systemImage: "point.3.connected.trianglepath.dotted") { copy(row.path) }
                .accessibilityIdentifier("\(format.rawValue)-copy-path")
            Button(YAMLStrings.viewSource, systemImage: "text.alignleft") { showSource(line: row.line) }
                .accessibilityIdentifier("\(format.rawValue)-show-source")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(format.rawValue)-row-\(row.path)")
    }

    private func rowKey(_ row: YAMLRow) -> some View {
        Text(row.depth == 0 ? YAMLStrings.root : row.label.isEmpty ? "\"\"" : row.label)
            .font(.system(.subheadline, design: .monospaced).weight(.medium))
            .foregroundStyle(.primary)
    }

    private func rowValue(_ row: YAMLRow) -> some View {
        Text(row.value.isEmpty ? "\"\"" : row.value)
            .font(.system(.subheadline, design: .monospaced))
            .foregroundStyle(row.kind == .string ? Color.primary : Color.accentColor)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("\(format.rawValue)-value-\(row.path)")
    }

    private func rowKind(_ row: YAMLRow) -> some View {
        Text(YAMLStrings.kind(row.kind, count: row.count))
            .font(.caption2).foregroundStyle(.secondary)
    }

    private func sourceLine(_ line: YAMLSourceLine) -> some View {
        let selected = line.id == selectedResult
        let error = issue?.code == "syntax" && issue?.line == line.number
        return HStack(alignment: .top, spacing: 12) {
            Text(String(line.number)).foregroundStyle(error ? Color.orange : Color.secondary)
                .frame(width: 46, alignment: .trailing)
                .accessibilityHidden(true)
            Text(styledLine(line)).fixedSize(horizontal: true, vertical: true)
                .textSelection(.enabled)
                .frame(minWidth: 1, alignment: .leading)
        }
        .font(.system(.subheadline, design: .monospaced))
        .padding(.vertical, 5).padding(.trailing, 16)
        .background(error ? Color.orange.opacity(0.12) : selected ? Color.accentColor.opacity(0.12) : Color.clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(YAMLStrings.line(line.number)): \(line.text)")
        .accessibilityIdentifier("\(format.rawValue)-source-line-\(line.number)")
    }

    private func styledLine(_ line: YAMLSourceLine) -> AttributedString {
        var result = AttributedString()
        for token in line.tokens {
            var fragment = AttributedString(token.text)
            fragment.foregroundColor = color(for: token.style)
            result.append(fragment)
        }
        if result.characters.isEmpty { result = AttributedString(" ") }
        if !trimmedQuery.isEmpty {
            var remaining = result.startIndex..<result.endIndex
            while let match = result[remaining].range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) {
                result[match].backgroundColor = Color.yellow.opacity(0.35)
                guard match.upperBound < result.endIndex else { break }
                remaining = match.upperBound..<result.endIndex
            }
        }
        return result
    }

    private func color(for style: String) -> Color {
        if style.contains("comment") { return .secondary }
        if style.contains("attr") { return .accentColor }
        if style.contains("string") { return .green }
        if style.contains("number") || style.contains("literal") { return .purple }
        if style.contains("meta") || style.contains("type") || style.contains("bullet") { return .orange }
        return .primary
    }

    private func resetCollapse() {
        collapsed = Set((sheet?.rows ?? []).filter { $0.depth >= 2 && $0.isExpandable }.map(\.id))
    }
    private func selectSheet(_ index: Int) {
        guard sheetIndex != index else { return }
        sheetIndex = index
        if issue != nil { mode = .source }
        visibleID = nil
        resetCollapse()
        scrollToStartOrResult()
    }
    private func selectMode(_ candidate: YAMLPreviewMode) {
        guard mode != candidate else { return }
        mode = candidate
        visibleID = nil
        scrollToStartOrResult()
    }
    private func scrollToStartOrResult() {
        resetSearch()
        if trimmedQuery.isEmpty {
            requestScroll(mode == .source ? "\(format.rawValue)-line-\(sheet?.startLine ?? 1)" : visibleRows.first?.id ?? "")
        }
        persistLocation()
    }
    private func resetSearch() {
        resultIndex = 0
        if let selectedResult { requestScroll(selectedResult, anchor: searchScrollAnchor) }
    }
    private func moveResult(forward: Bool) {
        guard !resultIDs.isEmpty else { return }
        resultIndex = (resultIndex + (forward ? 1 : resultIDs.count - 1)) % resultIDs.count
        if let selectedResult { requestScroll(selectedResult, anchor: searchScrollAnchor) }
    }
    private func requestScroll(_ target: String, anchor: UnitPoint = .topLeading) {
        guard !target.isEmpty else { return }
        scrollRequest = ScrollRequest(target: target, anchor: anchor)
    }
    private func showSource(line: Int) {
        query = ""
        mode = .source
        visibleID = nil
        requestScroll("\(format.rawValue)-line-\(line)")
    }
    private func persistLocation() {
        guard document != nil else { return }
        let target = visibleID ?? (mode == .source ? "\(format.rawValue)-line-\(sheet?.startLine ?? 1)" : visibleRows.first?.id ?? "")
        reading.position = YAMLReadingLocation(documentIndex: sheetIndex, mode: mode, target: target, format: format).position
    }
    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        copied = true
        copyTask?.cancel()
        copyTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            copied = false
        }
    }
}
