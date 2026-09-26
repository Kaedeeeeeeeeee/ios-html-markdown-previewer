import Foundation

enum AppearanceStrings {
    private static func text(_ key: String, _ fallback: String) -> String {
        NSLocalizedString(key, tableName: "Appearance", bundle: .main, value: fallback, comment: "")
    }

    static let appearance = text("appearance.title", "Appearance")
    static let pageZoom = text("appearance.pageZoom", "Page Zoom")
    static let fontSize = text("appearance.fontSize", "Font Size")
    static let lineSpacing = text("appearance.lineSpacing", "Line Spacing")
    static let reset = text("appearance.reset", "Reset to Default")
    static let done = text("appearance.done", "Done")
    static let preview = text("appearance.preview", "Reading Preview")
    static let savedDefaults = text("appearance.savedDefaults", "These settings apply to all documents of this type.")
    static let fullScreen = text("appearance.fullScreen", "Full Screen Reading")
    static let showControls = text("appearance.showControls", "Show Reading Controls")
    static let decreaseFontSize = text("appearance.decreaseFontSize", "Decrease Font Size")
    static let increaseFontSize = text("appearance.increaseFontSize", "Increase Font Size")
    static let decreaseLineSpacing = text("appearance.decreaseLineSpacing", "Decrease Line Spacing")
    static let increaseLineSpacing = text("appearance.increaseLineSpacing", "Increase Line Spacing")
    static let decreasePageZoom = text("appearance.decreasePageZoom", "Zoom Out Page")
    static let increasePageZoom = text("appearance.increasePageZoom", "Zoom In Page")
    static let openImage = text("appearance.openImage", "Open Full Screen Image")
    static let imageHint = text("appearance.imageHint", "Opens the image for zooming.")
    static let closeImage = text("appearance.closeImage", "Close Image")
    static let zoomIn = text("appearance.zoomIn", "Zoom In")
    static let zoomOut = text("appearance.zoomOut", "Zoom Out")
    static let resetImageZoom = text("appearance.resetImageZoom", "Fit Image to Screen")
    static let imageZoomHint = text("appearance.imageZoomHint", "Pinch to zoom, drag to move, or double-tap to zoom.")
    static let title = appearance
}
