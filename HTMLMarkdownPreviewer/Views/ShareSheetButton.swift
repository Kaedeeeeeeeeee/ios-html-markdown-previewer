import SwiftUI
import UIKit
import Observation

struct ShareSheetButton: UIViewRepresentable {
    let fileURL: URL
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    var shareTitle: String = AppStrings.Actions.shareOriginalFile
    var exportPDF: (@MainActor () async throws -> URL)?
    var onExporting: (Bool) -> Void = { _ in }
    var onExportError: (Error) -> Void = { _ in }
    var onSharing: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        button.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 21), forImageIn: .normal)
        button.accessibilityLabel = accessibilityLabel
        button.accessibilityIdentifier = accessibilityIdentifier
        button.showsMenuAsPrimaryAction = true
        configure(button, coordinator: context.coordinator)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        configure(button, coordinator: context.coordinator)
        button.isEnabled = context.environment.isEnabled
        button.accessibilityLabel = accessibilityLabel
        button.accessibilityIdentifier = accessibilityIdentifier
    }

    static func dismantleUIView(_ uiView: UIButton, coordinator: Coordinator) {
        coordinator.exportTask?.cancel()
    }

    private func configure(_ button: UIButton, coordinator: Coordinator) {
        let original = UIAction(title: shareTitle, image: UIImage(systemName: "doc")) { [weak button] _ in
            guard let button else { return }
            coordinator.share(fileURL, from: button, onSharing: onSharing)
        }
        let pdf = UIAction(
            title: AppStrings.Actions.exportPDF,
            image: UIImage(systemName: "doc.richtext"),
            attributes: exportPDF == nil ? .disabled : []
        ) { [weak button] _ in
            guard let button, let exportPDF else { return }
            coordinator.export(
                from: { [weak button] in button },
                makePDF: exportPDF,
                onExporting: onExporting,
                onError: onExportError,
                onSharing: onSharing
            )
        }
        button.menu = UIMenu(children: [original, pdf])
    }

    @MainActor
    final class Coordinator: NSObject {
        var exportTask: Task<Void, Never>?

        func share(_ fileURL: URL, from sender: UIView, isTemporary: Bool = false,
                   onSharing: @escaping (Bool) -> Void) {
            guard sender.window != nil,
                  let presentingViewController = sender.nearestViewController?.topMostPresentedViewController else {
                if isTemporary { PDFExportService.removeExport(at: fileURL) }
                return
            }

            let activityViewController = UIActivityViewController(
                activityItems: [fileURL],
                applicationActivities: nil
            )
            activityViewController.completionWithItemsHandler = { _, _, _, _ in
                Task { @MainActor in
                    onSharing(false)
                    if isTemporary { PDFExportService.removeExport(at: fileURL) }
                }
            }

            if let popoverPresentationController = activityViewController.popoverPresentationController {
                popoverPresentationController.sourceView = sender
                popoverPresentationController.sourceRect = sender.bounds
                popoverPresentationController.permittedArrowDirections = .any
            }

            onSharing(true)
            presentingViewController.present(activityViewController, animated: true)
        }

        func export(
            from sourceView: @escaping @MainActor () -> UIView?,
            makePDF: @escaping @MainActor () async throws -> URL,
            onExporting: @escaping (Bool) -> Void,
            onError: @escaping (Error) -> Void,
            onSharing: @escaping (Bool) -> Void
        ) {
            export(makePDF: makePDF, onExporting: onExporting, onError: onError) { fileURL in
                guard let sender = sourceView(), sender.window != nil else {
                    PDFExportService.removeExport(at: fileURL)
                    return
                }
                self.share(fileURL, from: sender, isTemporary: true, onSharing: onSharing)
            }
        }

        func export(
            makePDF: @escaping @MainActor () async throws -> URL,
            onExporting: @escaping (Bool) -> Void,
            onError: @escaping (Error) -> Void,
            present: @escaping @MainActor (URL) -> Void
        ) {
            guard exportTask == nil else { return }
            onExporting(true)
            exportTask = Task { @MainActor in
                defer {
                    onExporting(false)
                    exportTask = nil
                }
                do {
                    // Let the menu dismiss and the progress indicator appear before printing.
                    await Task.yield()
                    let fileURL = try await makePDF()
                    guard !Task.isCancelled else {
                        PDFExportService.removeExport(at: fileURL)
                        return
                    }
                    present(fileURL)
                } catch is CancellationError {
                    // Leaving the preview cancels an unfinished export.
                } catch {
                    if !Task.isCancelled { onError(error) }
                }
            }
        }
    }
}

// Keep the toolbar control native so SwiftUI can lay out its title and symbol
// horizontally or vertically. UIKit is only responsible for presenting sharing.
struct SystemShareSheetButton: View {
    let presentation: SharePresentationContext
    let fileURL: URL
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    var shareTitle: String = AppStrings.Actions.shareOriginalFile
    var exportPDF: (@MainActor () async throws -> URL)?
    var onExporting: (Bool) -> Void = { _ in }
    var onExportError: (Error) -> Void = { _ in }
    var onSharing: (Bool) -> Void = { _ in }

    var body: some View {
        Menu {
            Button {
                presentation.share(fileURL, onSharing: onSharing)
            } label: {
                Label(shareTitle, systemImage: "doc")
            }
            Button {
                guard let exportPDF else { return }
                presentation.coordinator.export(
                    makePDF: exportPDF,
                    onExporting: onExporting,
                    onError: onExportError
                ) { fileURL in
                    presentation.share(fileURL, isTemporary: true, onSharing: onSharing)
                }
            } label: {
                Label(AppStrings.Actions.exportPDF, systemImage: "doc.richtext")
            }
            .disabled(exportPDF == nil)
        } label: {
            Label(accessibilityLabel, systemImage: "square.and.arrow.up")
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

@MainActor
@Observable
final class SharePresentationContext {
    var activity: ShareActivity?
    private var activeActivity: ShareActivity?
    let coordinator = ShareSheetButton.Coordinator()

    func share(_ fileURL: URL, isTemporary: Bool = false, onSharing: @escaping (Bool) -> Void) {
        guard activeActivity == nil else {
            if isTemporary { PDFExportService.removeExport(at: fileURL) }
            return
        }
        let request = ShareActivity(fileURL: fileURL, isTemporary: isTemporary, onSharing: onSharing)
        activeActivity = request
        onSharing(true)
        activity = request
    }

    func dismissActivity(id: UUID) {
        guard activeActivity?.id == id else { return }
        activity = nil
    }

    func activityDidDismiss() {
        guard let request = activeActivity else { return }
        activeActivity = nil
        activity = nil
        request.onSharing(false)
        if request.isTemporary { PDFExportService.removeExport(at: request.fileURL) }
    }

    func cancelExport() {
        coordinator.exportTask?.cancel()
        activity = nil
        activityDidDismiss()
    }
}

struct ShareActivity: Identifiable {
    let id = UUID()
    let fileURL: URL
    let isTemporary: Bool
    let onSharing: (Bool) -> Void
}

// SwiftUI presents in the selected reader's scene. A native toolbar can extract
// its Menu without mounting any background UIView in that scene's window.
struct SharePresentationModifier: ViewModifier {
    let presentation: SharePresentationContext

    func body(content: Content) -> some View {
        @Bindable var presentation = presentation
        return content.sheet(item: $presentation.activity, onDismiss: presentation.activityDidDismiss) { activity in
            ActivityShareSheet(activity: activity) {
                presentation.dismissActivity(id: activity.id)
            }
        }
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activity: ShareActivity
    let onCompletion: @MainActor () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [activity.fileURL], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in onCompletion() }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private extension UIResponder {
    var nearestViewController: UIViewController? {
        if let viewController = self as? UIViewController {
            return viewController
        }

        return next?.nearestViewController
    }
}

private extension UIViewController {
    var topMostPresentedViewController: UIViewController {
        var viewController = self

        while let presentedViewController = viewController.presentedViewController {
            viewController = presentedViewController
        }

        return viewController
    }
}
