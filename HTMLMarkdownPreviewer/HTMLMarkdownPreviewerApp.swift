import SwiftUI

@main
struct HTMLMarkdownPreviewerApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.environment["HTML_PREVIEWER_UI_TESTS"] == "1" {
                AppView(store: DocumentLibraryStore(rootURL: uiTestLibraryURL))
                    .defaultAppStorage(uiTestDefaults)
            } else {
                AppView()
            }
            #else
            AppView()
            #endif
        }
    }

    #if DEBUG
    private var uiTestLibraryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "HTMLMarkdownPreviewer", isDirectory: true)
            .appendingPathComponent("UITestLibrary", isDirectory: true)
    }

    private var uiTestDefaults: UserDefaults {
        let suiteName = "\(Bundle.main.bundleIdentifier ?? "HTMLMarkdownPreviewer").UITests"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated UI test preferences")
        }
        return defaults
    }
    #endif
}
