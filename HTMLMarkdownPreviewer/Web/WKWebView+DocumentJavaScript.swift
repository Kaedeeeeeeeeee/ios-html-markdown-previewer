import WebKit

@MainActor
extension WKWebView {
    // Use WebKit's public Objective-C entry point directly. The Swift overlay
    // links libswiftWebKit, which is absent from older supported iOS runtimes.
    // This preserves named arguments, isolated content worlds, and promise results.
    func callDocumentJavaScript(
        _ functionBody: String,
        arguments: [String: Any] = [:],
        in frame: WKFrameInfo? = nil,
        in contentWorld: WKContentWorld,
        completionHandler: (@MainActor @Sendable (Result<Any?, Error>) -> Void)? = nil
    ) {
        __callAsyncJavaScript(
            functionBody, arguments: arguments, inFrame: frame, in: contentWorld
        ) { value, error in
            if let error {
                completionHandler?(.failure(error))
            } else {
                completionHandler?(.success(value))
            }
        }
    }

    func callDocumentJavaScript(
        _ functionBody: String,
        arguments: [String: Any] = [:],
        in frame: WKFrameInfo? = nil,
        contentWorld: WKContentWorld
    ) async throws -> Any? {
        let result: DocumentJavaScriptResult = try await withCheckedThrowingContinuation { continuation in
            __callAsyncJavaScript(
                functionBody, arguments: arguments, inFrame: frame, in: contentWorld
            ) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: DocumentJavaScriptResult(value: value))
                }
            }
        }
        return result.value
    }
}

// WebKit values stay on the main actor while the continuation carries the result.
@MainActor
private final class DocumentJavaScriptResult {
    let value: Any?

    init(value: Any?) {
        self.value = value
    }
}
