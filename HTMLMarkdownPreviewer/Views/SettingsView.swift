import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private let zipLimits = ZipImportLimits()

    var body: some View {
        NavigationStack {
            List {
                Section("HTML") {
                    LabeledContent("Default Mode", value: PreviewMode.safePreview.displayName)
                    LabeledContent("Safe JavaScript", value: "Disabled")
                    LabeledContent("Safe External Resources", value: "Blocked")
                }

                Section("ZIP Limits") {
                    LabeledContent("Archive", value: byteCount(zipLimits.maxArchiveBytes))
                    LabeledContent("Single File", value: byteCount(zipLimits.maxSingleFileBytes))
                    LabeledContent("Expanded", value: byteCount(zipLimits.maxTotalUncompressedBytes))
                    LabeledContent("Files", value: "\(zipLimits.maxFileCount)")
                }

                Section("Privacy") {
                    LabeledContent("Processing", value: "On Device")
                    LabeledContent("Account", value: "None")
                    LabeledContent("Ads", value: "None")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func byteCount(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }
}

#Preview {
    SettingsView()
}
