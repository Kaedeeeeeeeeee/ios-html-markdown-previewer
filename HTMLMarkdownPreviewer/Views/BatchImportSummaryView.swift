import SwiftUI

struct BatchImportSummaryView: View {
    let summary: BatchImportSummary
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    countRow(BatchImportStrings.imported, count: summary.importedCount,
                             image: "checkmark.circle", identifier: "batch-import-imported-count")
                    countRow(BatchImportStrings.skipped, count: summary.skippedCount,
                             image: "arrow.right.circle", identifier: "batch-import-skipped-count")
                    countRow(BatchImportStrings.failed, count: summary.failures.count,
                             image: "exclamationmark.circle", identifier: "batch-import-failed-count")
                } footer: {
                    if summary.importedCount > 0 { Text(BatchImportStrings.libraryHint) }
                }

                if !summary.failures.isEmpty {
                    Section(BatchImportStrings.failures) {
                        ForEach(summary.failures) { failure in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(failure.filename).font(.headline)
                                Text(failure.message)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("batch-import-failure-\(failure.filename)")
                        }
                    }
                }
            }
            .navigationTitle(BatchImportStrings.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(BatchImportStrings.done, action: onDone)
                        .accessibilityIdentifier("batch-import-done")
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func countRow(_ title: String, count: Int, image: String, identifier: String) -> some View {
        HStack {
            Label(title, systemImage: image)
            Spacer()
            Text(count.formatted()).monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(String(count))
        .accessibilityIdentifier(identifier)
    }
}
