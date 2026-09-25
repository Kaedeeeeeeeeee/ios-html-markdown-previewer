import SwiftUI
import UIKit

struct ShareSheetButton: UIViewRepresentable {
    let fileURL: URL
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    var shareTitle: String = AppStrings.Actions.shareOriginalFile
    var exportPDF: (@MainActor () async throws -> URL)?
    var onExporting: (Bool) -> Void = { _ in }
    var onExportError: (Error) -> Void = { _ in }

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
            coordinator.share(fileURL, from: button)
        }
        let pdf = UIAction(
            title: AppStrings.Actions.exportPDF,
            image: UIImage(systemName: "doc.richtext"),
            attributes: exportPDF == nil ? .disabled : []
        ) { [weak button] _ in
            guard let button, let exportPDF else { return }
            coordinator.export(
                from: button,
                makePDF: exportPDF,
                onExporting: onExporting,
                onError: onExportError
            )
        }
        button.menu = UIMenu(children: [original, pdf])
    }

    @MainActor
    final class Coordinator: NSObject {
        var exportTask: Task<Void, Never>?

        func share(_ fileURL: URL, from sender: UIButton, isTemporary: Bool = false) {
            guard let presentingViewController = sender.nearestViewController?.topMostPresentedViewController else {
                if isTemporary { PDFExportService.removeExport(at: fileURL) }
                return
            }

            let activityViewController = UIActivityViewController(
                activityItems: [fileURL],
                applicationActivities: nil
            )
            if isTemporary {
                activityViewController.completionWithItemsHandler = { _, _, _, _ in
                    Task { @MainActor in PDFExportService.removeExport(at: fileURL) }
                }
            }

            if let popoverPresentationController = activityViewController.popoverPresentationController {
                popoverPresentationController.sourceView = sender
                popoverPresentationController.sourceRect = sender.bounds
                popoverPresentationController.permittedArrowDirections = [.up, .down]
            }

            presentingViewController.present(activityViewController, animated: true)
        }

        func export(
            from sender: UIButton,
            makePDF: @escaping @MainActor () async throws -> URL,
            onExporting: @escaping (Bool) -> Void,
            onError: @escaping (Error) -> Void
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
                    share(fileURL, from: sender, isTemporary: true)
                } catch is CancellationError {
                    // Leaving the preview cancels an unfinished export.
                } catch {
                    onError(error)
                }
            }
        }
    }
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
