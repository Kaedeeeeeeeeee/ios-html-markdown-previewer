import Foundation
import ZIPFoundation

struct ZipImportLimits: Sendable {
    var maxArchiveBytes: UInt64 = 100 * 1_024 * 1_024
    var maxFileCount: Int = 5_000
    var maxSingleFileBytes: UInt64 = 100 * 1_024 * 1_024
    var maxTotalUncompressedBytes: UInt64 = 300 * 1_024 * 1_024
}

struct ZipImportResult: Sendable {
    let rootURL: URL
    let entryFileURL: URL
    let extractedFileCount: Int
    let totalUncompressedBytes: UInt64
}

enum ZipImportError: Error, Equatable {
    case invalidArchive
    case unsafePath(String)
    case unsupportedEntry(String)
    case duplicatePath(String)
    case caseConflictingPath(String)
    case archiveTooLarge
    case tooManyFiles(Int)
    case singleFileTooLarge(String)
    case expandedSizeTooLarge
    case missingEntryFile
}

final class ZipImportService {
    private let fileManager: FileManager
    private let limits: ZipImportLimits

    init(fileManager: FileManager = .default, limits: ZipImportLimits = ZipImportLimits()) {
        self.fileManager = fileManager
        self.limits = limits
    }

    func importArchive(from archiveURL: URL, to destinationRootURL: URL) throws -> ZipImportResult {
        try validateArchiveSize(archiveURL)
        let archive = try Archive(url: archiveURL, accessMode: .read)

        let temporaryRootURL = fileManager.temporaryDirectory
            .appendingPathComponent("zip-import-\(UUID().uuidString)", isDirectory: true)

        do {
            try fileManager.createDirectory(at: temporaryRootURL, withIntermediateDirectories: true)
            let summary = try extract(archive: archive, to: temporaryRootURL)
            let entryPath = try selectEntryFile(from: summary.extractedRelativePaths)

            if fileManager.fileExists(atPath: destinationRootURL.path) {
                try fileManager.removeItem(at: destinationRootURL)
            }

            try fileManager.createDirectory(
                at: destinationRootURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: temporaryRootURL, to: destinationRootURL)

            return ZipImportResult(
                rootURL: destinationRootURL,
                entryFileURL: destinationRootURL.appendingPathComponent(entryPath),
                extractedFileCount: summary.fileCount,
                totalUncompressedBytes: summary.totalUncompressedBytes
            )
        } catch {
            try? fileManager.removeItem(at: temporaryRootURL)
            throw error
        }
    }

    private func validateArchiveSize(_ archiveURL: URL) throws {
        let archiveFileSize = try archiveURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
            .map(UInt64.init) ?? 0
        guard archiveFileSize <= limits.maxArchiveBytes else {
            throw ZipImportError.archiveTooLarge
        }
    }

    private func extract(archive: Archive, to rootURL: URL) throws -> ExtractionSummary {
        var summary = ExtractionSummary()
        var normalizedPaths = Set<String>()
        var lowercasePaths = Set<String>()

        for entry in archive {
            guard !shouldSkip(entry.path) else {
                continue
            }

            let normalizedPath = try normalize(entry.path)
            guard normalizedPaths.insert(normalizedPath).inserted else {
                throw ZipImportError.duplicatePath(normalizedPath)
            }

            let lowercasedPath = normalizedPath.lowercased()
            guard lowercasePaths.insert(lowercasedPath).inserted else {
                throw ZipImportError.caseConflictingPath(normalizedPath)
            }

            switch entry.type {
            case .directory:
                let directoryURL = rootURL.appendingPathComponent(normalizedPath, isDirectory: true)
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            case .file:
                try validateFileEntry(entry, normalizedPath: normalizedPath, summary: &summary)
                let fileURL = rootURL.appendingPathComponent(normalizedPath)
                try fileManager.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                _ = try archive.extract(entry, to: fileURL)
                summary.extractedRelativePaths.append(normalizedPath)
            case .symlink:
                throw ZipImportError.unsupportedEntry(normalizedPath)
            }
        }

        return summary
    }

    private func validateFileEntry(
        _ entry: Entry,
        normalizedPath: String,
        summary: inout ExtractionSummary
    ) throws {
        let uncompressedSize = UInt64(entry.uncompressedSize)
        guard uncompressedSize <= limits.maxSingleFileBytes else {
            throw ZipImportError.singleFileTooLarge(normalizedPath)
        }

        let nextFileCount = summary.fileCount + 1
        guard nextFileCount <= limits.maxFileCount else {
            throw ZipImportError.tooManyFiles(nextFileCount)
        }

        let nextTotalSize = summary.totalUncompressedBytes + uncompressedSize
        guard nextTotalSize >= summary.totalUncompressedBytes,
              nextTotalSize <= limits.maxTotalUncompressedBytes else {
            throw ZipImportError.expandedSizeTooLarge
        }

        summary.fileCount = nextFileCount
        summary.totalUncompressedBytes = nextTotalSize
    }

    private func selectEntryFile(from paths: [String]) throws -> String {
        let sortedPaths = paths.sorted { lhs, rhs in
            if lhs.split(separator: "/").count != rhs.split(separator: "/").count {
                return lhs.split(separator: "/").count < rhs.split(separator: "/").count
            }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }

        if sortedPaths.contains("index.html") {
            return "index.html"
        }

        if sortedPaths.contains("index.htm") {
            return "index.htm"
        }

        if let rootHTML = sortedPaths.first(where: { path in
            !path.contains("/") && isHTML(path)
        }) {
            return rootHTML
        }

        if let nestedHTML = sortedPaths.first(where: isHTML) {
            return nestedHTML
        }

        if let rootMarkdown = sortedPaths.first(where: { path in
            !path.contains("/") && isMarkdown(path)
        }) {
            return rootMarkdown
        }

        if let nestedMarkdown = sortedPaths.first(where: isMarkdown) {
            return nestedMarkdown
        }

        throw ZipImportError.missingEntryFile
    }

    private func normalize(_ path: String) throws -> String {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("\\"),
              !path.contains("\\") else {
            throw ZipImportError.unsafePath(path)
        }

        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty else {
            throw ZipImportError.unsafePath(path)
        }

        for part in parts where part == "." || part == ".." {
            throw ZipImportError.unsafePath(path)
        }

        return parts.joined(separator: "/")
    }

    private func shouldSkip(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        return parts.contains("__MACOSX") || parts.last == ".DS_Store"
    }

    private func isHTML(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ext == "html" || ext == "htm"
    }

    private func isMarkdown(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }
}

private struct ExtractionSummary {
    var fileCount = 0
    var totalUncompressedBytes: UInt64 = 0
    var extractedRelativePaths: [String] = []
}
