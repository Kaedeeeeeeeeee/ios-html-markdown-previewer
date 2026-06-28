import WebKit

enum HTMLPreviewMode {
    case safePreview
    case interactive
}

enum HTMLPreviewConfiguration {
    @MainActor
    static func make(mode: HTMLPreviewMode) async throws -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = mode == .interactive
        configuration.defaultWebpagePreferences = preferences

        if mode == .safePreview {
            let ruleList = try await ContentRuleListCompiler.compileExternalNetworkBlocker()
            configuration.userContentController.add(ruleList)
        }

        return configuration
    }
}

enum ContentRuleListCompiler {
    @MainActor
    static func compileExternalNetworkBlocker() async throws -> WKContentRuleList {
        try await compile(
            identifier: ContentBlockerRules.externalNetworkIdentifier,
            encodedRules: ContentBlockerRules.externalNetworkRules
        )
    }

    @MainActor
    static func compile(identifier: String, encodedRules: String) async throws -> WKContentRuleList {
        try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: encodedRules
            ) { ruleList, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let ruleList else {
                    continuation.resume(throwing: HTMLPreviewError.contentRuleListMissing)
                    return
                }

                continuation.resume(returning: ruleList)
            }
        }
    }
}

enum HTMLPreviewError: Error {
    case contentRuleListMissing
}
