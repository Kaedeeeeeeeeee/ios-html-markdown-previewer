import SwiftUI
import UIKit

struct ShareSheetButton: UIViewRepresentable {
    let fileURL: URL
    let accessibilityLabel: String
    let accessibilityIdentifier: String

    func makeCoordinator() -> Coordinator {
        Coordinator(fileURL: fileURL)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        button.accessibilityLabel = accessibilityLabel
        button.accessibilityIdentifier = accessibilityIdentifier
        button.addTarget(context.coordinator, action: #selector(Coordinator.share(_:)), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.fileURL = fileURL
        button.accessibilityLabel = accessibilityLabel
        button.accessibilityIdentifier = accessibilityIdentifier
    }

    @MainActor
    final class Coordinator: NSObject {
        var fileURL: URL

        init(fileURL: URL) {
            self.fileURL = fileURL
        }

        @objc func share(_ sender: UIButton) {
            guard let presentingViewController = sender.nearestViewController?.topMostPresentedViewController else {
                return
            }

            let activityViewController = UIActivityViewController(
                activityItems: [fileURL],
                applicationActivities: nil
            )

            if let popoverPresentationController = activityViewController.popoverPresentationController {
                popoverPresentationController.sourceView = sender
                popoverPresentationController.sourceRect = sender.bounds
                popoverPresentationController.permittedArrowDirections = [.up, .down]
            }

            presentingViewController.present(activityViewController, animated: true)
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
