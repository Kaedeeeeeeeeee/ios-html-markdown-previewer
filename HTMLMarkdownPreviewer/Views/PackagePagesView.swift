import SwiftUI

struct PackageNavigationBar: View {
    let navigation: PackageNavigationState
    let onBack: () -> Void
    let onPages: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onBack) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 48)
            }
            .disabled(!navigation.canGoBack)
            .accessibilityLabel(PackageNavigationStrings.back)
            .accessibilityIdentifier("package-back-button")
            Button(action: onPages) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(navigation.current.page.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(navigation.current.page.relativePath)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "square.stack")
                        .font(.system(size: 18))
                    Text("\(navigation.pages.count)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
                .padding(.trailing, 12)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("\(PackageNavigationStrings.pages), \(navigation.current.page.title), \(PackageNavigationStrings.count(navigation.pages.count))")
            .accessibilityValue(navigation.current.page.relativePath)
            .accessibilityIdentifier("package-pages-button")
        }
        .buttonStyle(.plain)
        .tint(.accentColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }
}

struct PackagePagesView: View {
    let pages: [PackagePage]
    let selectedPath: String
    let prefersLargePresentation: Bool
    let onSelect: (PackagePage) -> Void
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [PackagePage] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? pages : pages.filter {
            $0.title.localizedStandardContains(query) || $0.relativePath.localizedStandardContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filtered) { page in
                        Button {
                            onSelect(page)
                            dismiss()
                        } label: {
                            HStack(alignment: .center, spacing: 14) {
                                Image(systemName: page.documentType == .markdown ? "text.alignleft" : "chevron.left.forwardslash.chevron.right")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(page.relativePath == selectedPath ? Color.accentColor : .secondary)
                                    .frame(width: 40, height: 44)
                                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 11))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(page.title)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text(page.relativePath)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    if page.isEntry {
                                        Text(PackageNavigationStrings.entry)
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                                if page.relativePath == selectedPath {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                        .accessibilityLabel(PackageNavigationStrings.current)
                                }
                            }
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("package-page-\(page.relativePath)")
                        .accessibilityValue(page.relativePath == selectedPath ? PackageNavigationStrings.current : "")
                    }
                } header: {
                    Text(PackageNavigationStrings.count(pages.count))
                } footer: {
                    Text(PackageNavigationStrings.description)
                }
            }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView(PackageNavigationStrings.noResults, systemImage: "doc.text.magnifyingglass",
                                           description: Text(PackageNavigationStrings.noResultsDetail))
                }
            }
            .searchable(text: $search, prompt: PackageNavigationStrings.search)
            .navigationTitle(PackageNavigationStrings.pages)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.Actions.done) { dismiss() }
                        .accessibilityIdentifier("package-pages-done")
                }
            }
        }
        .presentationDetents(prefersLargePresentation ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
