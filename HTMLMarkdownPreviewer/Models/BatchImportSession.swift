import Foundation

/// A picker selection is staged before review so no security-scoped URL has to
/// remain accessible while the user decides what to do with a duplicate.
struct BatchImportSession: Identifiable {
    let id = UUID()
    let items: [BatchImportItem]
    private(set) var outcomes: [BatchImportOutcome] = []

    var isBatch: Bool { items.count > 1 }
    var isComplete: Bool { outcomes.count == items.count }
    var nextItem: BatchImportItem? {
        isComplete ? nil : items[outcomes.count]
    }

    init(items: [BatchImportItem]) {
        self.items = items
    }

    static func prepare(
        urls: [URL],
        source: ImportSource,
        service: DocumentImportService,
        errorMessage: (Error) -> String
    ) -> BatchImportSession {
        BatchImportSession(items: urls.map { url in
            do {
                return .prepared(try service.prepareImport(from: url, source: source))
            } catch {
                return .failed(BatchImportFailure(filename: url.lastPathComponent, message: errorMessage(error)))
            }
        })
    }

    /// A duplicate sheet can dismiss after an action has already completed.
    /// Matching the current ID prevents a second callback from counting twice.
    @discardableResult
    mutating func finish(itemID: UUID, outcome: BatchImportOutcome) -> Bool {
        guard nextItem?.id == itemID else { return false }
        outcomes.append(outcome)
        return true
    }

    var summary: BatchImportSummary {
        BatchImportSummary(
            id: id,
            totalCount: items.count,
            importedCount: outcomes.filter { if case .imported = $0 { true } else { false } }.count,
            skippedCount: outcomes.filter { if case .skipped = $0 { true } else { false } }.count,
            failures: outcomes.compactMap { if case .failed(let failure) = $0 { failure } else { nil } }
        )
    }
}

enum BatchImportItem: Identifiable {
    case prepared(PreparedDocumentImport)
    case failed(BatchImportFailure)

    var id: UUID {
        switch self {
        case .prepared(let prepared): prepared.id
        case .failed(let failure): failure.id
        }
    }
}

enum BatchImportOutcome {
    case imported
    case skipped
    case failed(BatchImportFailure)
}

struct BatchImportFailure: Identifiable, Equatable {
    let id = UUID()
    let filename: String
    let message: String
}

struct BatchImportSummary: Identifiable {
    let id: UUID
    let totalCount: Int
    let importedCount: Int
    let skippedCount: Int
    let failures: [BatchImportFailure]
}
