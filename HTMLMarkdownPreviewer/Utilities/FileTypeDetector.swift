import Foundation
import UniformTypeIdentifiers

enum FileTypeDetector {
    static func documentType(for url: URL) -> PreviewDocumentType {
        documentType(forPathExtension: url.pathExtension)
    }

    static func documentType(forPath path: String) -> PreviewDocumentType {
        documentType(forPathExtension: URL(fileURLWithPath: path).pathExtension)
    }

    static func documentType(forPathExtension pathExtension: String) -> PreviewDocumentType {
        let normalizedExtension = pathExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: ".").union(.whitespacesAndNewlines))
            .lowercased()

        switch normalizedExtension {
        case "html", "htm":
            return .html
        case "md", "markdown":
            return .markdown
        case "zip":
            return .zipPackage
        default:
            break
        }

        guard let type = UTType(filenameExtension: normalizedExtension) else {
            return .unsupported
        }

        return documentType(for: type)
    }

    static func documentType(for type: UTType) -> PreviewDocumentType {
        if type.conforms(to: .html) {
            return .html
        }

        if type == SupportedDocumentTypes.markdown || type.conforms(to: SupportedDocumentTypes.markdown) {
            return .markdown
        }

        if type.conforms(to: .zip) {
            return .zipPackage
        }

        return .unsupported
    }
}
