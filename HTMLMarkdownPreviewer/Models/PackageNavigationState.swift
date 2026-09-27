import Foundation
import Observation

/// Page history belongs to one open package. Each page's reading position is
/// persisted separately by the document owner before changing this selection.
@MainActor
@Observable
final class PackageNavigationState {
    struct Location: Equatable {
        let page: PackagePage
        let url: URL
    }

    let pages: [PackagePage]
    private(set) var current: Location
    private(set) var history: [Location] = []

    init(pages: [PackagePage], selected: PackagePage) {
        self.pages = pages
        current = Location(page: selected, url: selected.fileURL)
    }

    var canGoBack: Bool { !history.isEmpty }

    @discardableResult
    func select(_ page: PackagePage, url: URL? = nil) -> Bool {
        let next = Location(page: page, url: url ?? page.fileURL)
        guard next != current else { return false }
        history.append(current)
        // Imported packages may contain long link chains; session history stays bounded.
        if history.count > 100 { history.removeFirst(history.count - 100) }
        current = next
        return true
    }

    @discardableResult
    func goBack() -> Bool {
        guard let previous = history.popLast() else { return false }
        current = previous
        return true
    }

    func didFinish(url: URL) {
        // Same-page anchors remain WebKit navigation, not a new package page.
        guard url.isFileURL, url.standardizedFileURL.path == current.page.fileURL.standardizedFileURL.path else { return }
        current = Location(page: current.page, url: url)
    }
}
