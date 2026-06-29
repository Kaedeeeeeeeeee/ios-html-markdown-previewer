import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var clearImportedFiles: () throws -> Void = {}

    private let zipLimits = ZipImportLimits()

    @State private var isClearConfirmationPresented = false
    @State private var clearErrorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("HTML") {
                    settingsRow("Default Mode", value: PreviewMode.safePreview.displayName)
                    settingsRow("Safe JavaScript", value: "Disabled")
                    settingsRow("Safe External Resources", value: "Blocked")
                }

                Section("Storage") {
                    settingsRow("Imported Files", value: "Stored in App")

                    Button(role: .destructive) {
                        isClearConfirmationPresented = true
                    } label: {
                        Label("Clear Imported Files", systemImage: "trash")
                    }
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("clear-imported-files-button")
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
            .accessibilityIdentifier("settings-screen")
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("settings-done-button")
                }
            }
        }
        .confirmationDialog("Clear Imported Files?", isPresented: $isClearConfirmationPresented) {
            Button("Clear Imported Files", role: .destructive) {
                clearImports()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes imported copies, extracted ZIP contents, and recent-file metadata from this app.")
        }
        .alert("Cannot Clear Imported Files", isPresented: isClearErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(clearErrorMessage ?? "")
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

    private var isClearErrorPresented: Binding<Bool> {
        Binding(
            get: { clearErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    clearErrorMessage = nil
                }
            }
        )
    }

    private func clearImports() {
        do {
            try clearImportedFiles()
        } catch {
            clearErrorMessage = error.localizedDescription
        }
    }
}

#Preview {
    SettingsView()
}
