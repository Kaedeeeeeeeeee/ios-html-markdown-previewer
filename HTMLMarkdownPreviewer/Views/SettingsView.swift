import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private let zipLimits = ZipImportLimits()

    var body: some View {
        NavigationStack {
            List {
                Section("HTML") {
                    settingsRow("Default Mode", value: PreviewMode.safePreview.displayName)
                    settingsRow("Safe JavaScript", value: "Disabled")
                    settingsRow("Safe External Resources", value: "Blocked")
                }

                Section("ZIP Limits") {
                    settingsRow("Archive", value: byteCount(zipLimits.maxArchiveBytes))
                    settingsRow("Single File", value: byteCount(zipLimits.maxSingleFileBytes))
                    settingsRow("Expanded", value: byteCount(zipLimits.maxTotalUncompressedBytes))
                    settingsRow("Files", value: "\(zipLimits.maxFileCount)")
                }

                Section("Privacy") {
                    settingsRow("Processing", value: "On Device")
                    settingsRow("Account", value: "None")
                    settingsRow("Ads", value: "None")
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

    private func settingsRow(_ title: String, value: String) -> some View {
        LabeledContent(title, value: value)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title): \(value)")
    }
}

#Preview {
    SettingsView()
}
