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
                Section(AppStrings.Settings.htmlSection) {
                    settingsRow(AppStrings.Settings.defaultMode, value: PreviewMode.safePreview.displayName)
                    settingsRow(AppStrings.Settings.safeJavaScript, value: AppStrings.Settings.disabled)
                    settingsRow(AppStrings.Settings.safeExternalResources, value: AppStrings.Settings.blocked)
                }

                Section(AppStrings.Settings.storageSection) {
                    settingsRow(AppStrings.Settings.importedFiles, value: AppStrings.Settings.storedInApp)

                    Button(role: .destructive) {
                        isClearConfirmationPresented = true
                    } label: {
                        Label(AppStrings.Actions.clearImportedFiles, systemImage: "trash")
                    }
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("clear-imported-files-button")
                }

                Section(AppStrings.Settings.zipLimitsSection) {
                    settingsRow(AppStrings.Settings.archive, value: byteCount(zipLimits.maxArchiveBytes))
                    settingsRow(AppStrings.Settings.singleFile, value: byteCount(zipLimits.maxSingleFileBytes))
                    settingsRow(AppStrings.Settings.expanded, value: byteCount(zipLimits.maxTotalUncompressedBytes))
                    settingsRow(AppStrings.Settings.files, value: "\(zipLimits.maxFileCount)")
                }

                Section(AppStrings.Settings.privacySection) {
                    settingsRow(AppStrings.Settings.processing, value: AppStrings.Settings.onDevice)
                    settingsRow(AppStrings.Settings.account, value: AppStrings.Settings.none)
                    settingsRow(AppStrings.Settings.ads, value: AppStrings.Settings.none)
                }
            }
            .accessibilityIdentifier("settings-screen")
            .navigationTitle(AppStrings.Settings.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppStrings.Actions.done) {
                        dismiss()
                    }
                    .accessibilityIdentifier("settings-done-button")
                }
            }
        }
        .confirmationDialog(AppStrings.Settings.clearImportedFilesTitle, isPresented: $isClearConfirmationPresented) {
            Button(AppStrings.Actions.clearImportedFiles, role: .destructive) {
                clearImports()
            }
            Button(AppStrings.Actions.cancel, role: .cancel) {}
        } message: {
            Text(AppStrings.Settings.clearImportedFilesConfirmation)
        }
        .alert(AppStrings.Errors.cannotClearImportedFilesTitle, isPresented: isClearErrorPresented) {
            Button(AppStrings.Actions.ok, role: .cancel) {}
        } message: {
            Text(clearErrorMessage ?? "")
        }
    }

    private func byteCount(_ value: UInt64) -> String {
        AppFormatters.byteCount(Int64(value))
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
