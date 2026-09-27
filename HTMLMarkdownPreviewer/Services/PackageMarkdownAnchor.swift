import Foundation

/// Maps familiar Markdown heading links to the reader's stable structural heading IDs.
enum PackageMarkdownAnchor {
    static func headingID(for fragment: String, headings: [DocumentHeading]) -> String? {
        let decoded = (fragment.removingPercentEncoding ?? fragment).precomposedStringWithCanonicalMapping
        guard !decoded.isEmpty else { return nil }
        if let exact = headings.first(where: { $0.id == decoded }) { return exact.id }

        var used: Set<String> = []
        for heading in headings {
            let base = slug(heading.title)
            var candidate = base
            var suffix = 1
            while used.contains(candidate) {
                candidate = "\(base)-\(suffix)"
                suffix += 1
            }
            used.insert(candidate)
            if candidate == decoded { return heading.id }
        }
        return nil
    }

    private static func slug(_ title: String) -> String {
        let lettersAndNumbers = CharacterSet.alphanumerics.union(.nonBaseCharacters)
        return title.lowercased().precomposedStringWithCanonicalMapping.unicodeScalars.compactMap { scalar in
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { return "-" }
            if lettersAndNumbers.contains(scalar) || scalar == "-" || scalar == "_" { return String(scalar) }
            return nil
        }.joined()
    }
}
