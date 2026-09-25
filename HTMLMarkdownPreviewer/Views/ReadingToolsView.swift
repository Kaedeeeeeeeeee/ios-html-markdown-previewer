import SwiftUI

struct DocumentSearchBar: View {
    @Bindable var reading: DocumentReadingState
    let onClose: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(ReadingStrings.searchPlaceholder, text: $reading.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isFocused)
                    .onSubmit {
                        isFocused = false
                        if reading.matchCount > 0 {
                            reading.navigate(to: .match(max(0, reading.selectedMatch)))
                        }
                    }
                    .accessibilityIdentifier("reading-search-field")
                Button {
                    isFocused = false
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel(ReadingStrings.closeSearch)
                .accessibilityIdentifier("reading-search-close")
            }
            if !reading.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack {
                    Text(reading.matchCount == 0 ? ReadingStrings.noMatches
                         : ReadingStrings.matchCount(current: max(0, reading.selectedMatch + 1), total: reading.matchCount))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .accessibilityIdentifier("reading-match-count")
                    Spacer()
                    matchButton(forward: false)
                    matchButton(forward: true)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .onAppear { isFocused = true }
    }

    private func matchButton(forward: Bool) -> some View {
        Button {
            isFocused = false
            reading.moveMatch(forward: forward)
        } label: {
            Image(systemName: forward ? "chevron.down" : "chevron.up")
                .frame(width: 44, height: 36)
        }
        .disabled(reading.matchCount == 0)
        .accessibilityLabel(forward ? ReadingStrings.next : ReadingStrings.previous)
        .accessibilityIdentifier(forward ? "reading-next-match" : "reading-previous-match")
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
