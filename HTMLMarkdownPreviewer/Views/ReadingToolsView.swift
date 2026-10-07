import SwiftUI
import UIKit
import Observation

/// The reader owns editing intent because a split column can replace its host.
@MainActor
@Observable
final class DocumentSearchEditingSession {
    var wantsFocus = false

    func beginEditing() {
        wantsFocus = true
    }
    func endEditing() {
        wantsFocus = false
    }
}

struct DocumentSearchBar: View {
    @Bindable var reading: DocumentReadingState
    @Bindable var editingSession: DocumentSearchEditingSession
    var usesCompactLayout = false
    let onClose: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if #available(iOS 27.1, *) {
                // Keep one native text field and its first responder through reflow.
                ResponsiveSearchLayout(prefersCompact: usesCompactLayout, hasQuery: hasQuery) {
                    HStack(spacing: 10) {
                        searchIcon
                        searchField.frame(minWidth: 120, idealWidth: 160)
                    }
                    matchCount
                        .opacity(hasQuery ? 1 : 0)
                        .accessibilityHidden(!hasQuery)
                    matchButton(forward: false)
                        .opacity(hasQuery ? 1 : 0)
                        .allowsHitTesting(hasQuery)
                        .accessibilityHidden(!hasQuery)
                    matchButton(forward: true)
                        .opacity(hasQuery ? 1 : 0)
                        .allowsHitTesting(hasQuery)
                        .accessibilityHidden(!hasQuery)
                    closeButton
                }
            } else {
                standardLayout
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .onAppear {
            if #unavailable(iOS 27.1) { isFocused = true }
        }
    }

    private var hasQuery: Bool {
        !reading.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var standardLayout: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                searchIcon
                searchField
                closeButton
            }
            if hasQuery {
                HStack {
                    matchCount
                    Spacer()
                    matchButton(forward: false)
                    matchButton(forward: true)
                }
            }
        }
    }

    private var searchIcon: some View {
        Image(systemName: "magnifyingglass")
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var searchField: some View {
        if #available(iOS 27.1, *) {
            MigratingSearchField(text: $reading.query, wantsFocus: $editingSession.wantsFocus,
                                 placeholder: ReadingStrings.searchPlaceholder, onSubmit: submitSearch)
                .accessibilityIdentifier("reading-search-field")
        } else {
            TextField(ReadingStrings.searchPlaceholder, text: $reading.query)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .focused($isFocused)
            .onSubmit(submitSearch)
            .accessibilityIdentifier("reading-search-field")
        }
    }

    private func dismissKeyboard() {
        editingSession.endEditing()
        isFocused = false
    }

    private func submitSearch() {
        dismissKeyboard()
        if reading.matchCount > 0 {
            reading.navigate(to: .match(max(0, reading.selectedMatch)))
        }
    }

    private var closeButton: some View {
        Button {
            dismissKeyboard()
            onClose()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: usesCompactLayout ? 44 : 36, height: usesCompactLayout ? 44 : 36)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(ReadingStrings.closeSearch)
        .accessibilityIdentifier("reading-search-close")
    }

    private var matchCount: some View {
        Text(reading.matchCount == 0 ? ReadingStrings.noMatches
             : ReadingStrings.matchCount(current: max(0, reading.selectedMatch + 1), total: reading.matchCount))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .accessibilityIdentifier("reading-match-count")
    }

    private func matchButton(forward: Bool) -> some View {
        Button {
            dismissKeyboard()
            reading.moveMatch(forward: forward)
        } label: {
            Image(systemName: forward ? "chevron.down" : "chevron.up")
                .frame(width: 44, height: usesCompactLayout ? 44 : 36)
                .contentShape(Rectangle())
        }
        .disabled(reading.matchCount == 0)
        .accessibilityLabel(forward ? ReadingStrings.next : ReadingStrings.previous)
        .accessibilityIdentifier(forward ? "reading-next-match" : "reading-previous-match")
    }
}

/// UIKit reports window detachment separately from a user ending editing.
/// Restoring on attachment avoids a timer or focusing on every size change.
@available(iOS 27.1, *)
private struct MigratingSearchField: UIViewRepresentable {
    @Binding var text: String
    @Binding var wantsFocus: Bool
    let placeholder: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> SearchTextField {
        let field = SearchTextField()
        field.delegate = context.coordinator
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.returnKeyType = .search
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.accessibilityIdentifier = "reading-search-field"
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: SearchTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholder = placeholder
        // Do not replace marked text or reset the insertion point while typing.
        if field.text != text, field.markedTextRange == nil { field.text = text }
        field.wantsFocus = wantsFocus
        field.applyFocusIntent()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SearchTextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 160, height: max(22, uiView.font?.lineHeight ?? 22))
    }

    static func dismantleUIView(_ field: SearchTextField, coordinator: Coordinator) {
        // SwiftUI may dismantle the old host before attaching its replacement.
        // The reader's intent survives that teardown, but not a prior user blur.
        field.cancelBlurConfirmation()
        field.isChangingHost = true
        field.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: MigratingSearchField
        init(parent: MigratingSearchField) { self.parent = parent }

        @objc func textChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            (field as? SearchTextField)?.cancelBlurConfirmation()
            (field as? SearchTextField)?.wantsFocus = true
            if !parent.wantsFocus { parent.wantsFocus = true }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            guard let field = textField as? SearchTextField else { return }
            if !parent.wantsFocus {
                field.cancelBlurConfirmation()
                field.wantsFocus = false
                return
            }
            // UIKit can deliver an old end callback after editing has begun again.
            guard !field.isFirstResponder, !field.isChangingHost, field.window != nil else { return }
            field.confirmBlurAfterHierarchyUpdate { [weak self] in
                guard let self else { return }
                if self.parent.wantsFocus { self.parent.wantsFocus = false }
            }
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            (field as? SearchTextField)?.cancelBlurConfirmation()
            parent.wantsFocus = false
            (field as? SearchTextField)?.wantsFocus = false
            field.resignFirstResponder()
            parent.onSubmit()
            return true
        }
    }

    final class SearchTextField: UITextField {
        // Editing intent is independent of software keyboard visibility: a
        // hardware keyboard can keep typing while the software keyboard is hidden.
        var wantsFocus = false
        var isChangingHost = false
        private var blurConfirmationID: UUID?
        private var resignationDepth = 0

        func cancelBlurConfirmation() {
            blurConfirmationID = nil
        }

        func confirmBlurAfterHierarchyUpdate(onConfirmed: @escaping @MainActor () -> Void) {
            let confirmationID = UUID()
            blurConfirmationID = confirmationID
            // removeFromSuperview resigns before willMove(toWindow:). Confirm
            // once the synchronous hierarchy update has finished, without a timer.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.blurConfirmationID == confirmationID else { return }
                self.blurConfirmationID = nil
                guard !self.isFirstResponder, !self.isChangingHost, self.window != nil else {
                    return
                }
                self.wantsFocus = false
                onConfirmed()
            }
        }

        override func resignFirstResponder() -> Bool {
            resignationDepth += 1
            defer { resignationDepth -= 1 }
            let result = super.resignFirstResponder()
            return result
        }

        override func willMove(toSuperview newSuperview: UIView?) {
            if superview !== newSuperview { cancelBlurConfirmation() }
            super.willMove(toSuperview: newSuperview)
        }

        override func willMove(toWindow newWindow: UIWindow?) {
            if window !== newWindow { cancelBlurConfirmation() }
            isChangingHost = window != newWindow
            super.willMove(toWindow: newWindow)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                isChangingHost = false
                applyFocusIntent()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // An attached hosting view may become eligible after its first layout.
            applyFocusIntent()
        }

        func applyFocusIntent() {
            guard window != nil, !isChangingHost else { return }
            if wantsFocus, !isFirstResponder {
                // Do not grab focus back during a genuine user blur or inside
                // UIKit's unfinished resignation callback.
                guard resignationDepth == 0, blurConfirmationID == nil else { return }
                becomeFirstResponder()
            }
            else if !wantsFocus, isFirstResponder { resignFirstResponder() }
        }
    }
}

/// Change positions without replacing the field when keyboard/size classes change.
/// If the compact row cannot fit, use the original two-row arrangement.
private struct ResponsiveSearchLayout: Layout {
    var prefersCompact: Bool
    var hasQuery: Bool

    private struct Metrics {
        let size: CGSize
        let field: CGSize
        let count: CGSize
        let previous: CGSize
        let next: CGSize
        let close: CGSize
        let singleRow: Bool
        let firstRowHeight: CGFloat
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        metrics(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = metrics(width: bounds.width, subviews: subviews)
        func place(_ index: Int, x: CGFloat, centerY: CGFloat, size: CGSize) {
            subviews[index].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + centerY),
                                  anchor: .leading, proposal: ProposedViewSize(size))
        }
        let firstCenter = layout.firstRowHeight / 2
        place(0, x: 0, centerY: firstCenter, size: layout.field)
        place(4, x: bounds.width - layout.close.width, centerY: firstCenter, size: layout.close)
        if !hasQuery {
            for index in 1...3 { place(index, x: 0, centerY: firstCenter, size: .zero) }
            return
        }
        if layout.singleRow {
            let countX = layout.field.width + 8
            let previousX = countX + layout.count.width + 8
            place(1, x: countX, centerY: firstCenter, size: layout.count)
            place(2, x: previousX, centerY: firstCenter, size: layout.previous)
            place(3, x: previousX + layout.previous.width + 8, centerY: firstCenter, size: layout.next)
        } else {
            let secondHeight = layout.size.height - layout.firstRowHeight - 8
            let center = layout.firstRowHeight + 8 + secondHeight / 2
            place(1, x: 0, centerY: center, size: layout.count)
            place(3, x: bounds.width - layout.next.width, centerY: center, size: layout.next)
            place(2, x: bounds.width - layout.next.width - 8 - layout.previous.width,
                  centerY: center, size: layout.previous)
        }
    }

    private func metrics(width proposedWidth: CGFloat?, subviews: Subviews) -> Metrics {
        let previous = subviews[2].sizeThatFits(.unspecified)
        let next = subviews[3].sizeThatFits(.unspecified)
        let close = subviews[4].sizeThatFits(.unspecified)
        let naturalCount = subviews[1].sizeThatFits(.unspecified)
        let idealField = subviews[0].sizeThatFits(.unspecified)
        let minimumField = subviews[0].sizeThatFits(ProposedViewSize(width: 0, height: nil)).width
        let controlsWidth = naturalCount.width + previous.width + next.width + close.width + 32
        let idealWidth = hasQuery && prefersCompact ? idealField.width + controlsWidth : max(
            idealField.width + close.width + 10, naturalCount.width + previous.width + next.width + 16
        )
        let width = max(0, proposedWidth ?? idealWidth)
        let singleRow = !hasQuery || (prefersCompact && minimumField + controlsWidth <= width)
        let fieldWidth = max(0, width - (hasQuery && singleRow ? controlsWidth : close.width + 10))
        let field = subviews[0].sizeThatFits(ProposedViewSize(width: fieldWidth, height: nil))
        let countWidth = singleRow ? naturalCount.width : max(0, width - previous.width - next.width - 16)
        let count = subviews[1].sizeThatFits(ProposedViewSize(width: countWidth, height: nil))
        let firstHeight = singleRow && hasQuery
            ? max(max(field.height, close.height), max(count.height, max(previous.height, next.height)))
            : max(field.height, close.height)
        let height = firstHeight + (hasQuery && !singleRow ? 8 + max(count.height, max(previous.height, next.height)) : 0)
        return Metrics(size: CGSize(width: width, height: height), field: CGSize(width: fieldWidth, height: field.height),
                       count: count, previous: previous, next: next, close: close,
                       singleRow: singleRow, firstRowHeight: firstHeight)
    }
}

struct DocumentOutlineView: View {
    let reading: DocumentReadingState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if reading.headings.isEmpty {
                    ContentUnavailableView(ReadingStrings.noHeadings, systemImage: "list.bullet.indent",
                                           description: Text(ReadingStrings.noHeadingsDescription))
                } else {
                    List(reading.headings) { heading in
                        Button {
                            reading.navigate(to: .heading(heading.id))
                            dismiss()
                        } label: {
                            Text(heading.title)
                                .fontWeight(heading.level <= 2 ? .semibold : .regular)
                                .foregroundStyle(.primary)
                                .padding(.leading, CGFloat(max(0, min(5, heading.level - 1))) * 14)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("reading-heading-\(heading.id)")
                    }
                }
            }
            .navigationTitle(ReadingStrings.contents)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.Actions.done) { dismiss() }
                        .accessibilityIdentifier("reading-contents-done")
                }
            }
        }
    }
}
