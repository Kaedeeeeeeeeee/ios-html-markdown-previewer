import SwiftUI

/// Place inside the searchable list so isSearching also covers an empty, focused search field.
struct ReviewPromptRequestView: View {
    let controller: ReviewPromptController
    let isAvailable: Bool
    let onRequest: () -> Void

    @Environment(\.isSearching) private var isSearching
    @Environment(\.scenePhase) private var scenePhase

    private var requestID: UUID? {
        isAvailable && !isSearching && scenePhase == .active ? controller.pendingRequestID : nil
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task(id: requestID) {
                guard let id = requestID else { return }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard !Task.isCancelled, requestID == id, controller.consumeRequest(id) else { return }
                onRequest()
            }
    }
}
