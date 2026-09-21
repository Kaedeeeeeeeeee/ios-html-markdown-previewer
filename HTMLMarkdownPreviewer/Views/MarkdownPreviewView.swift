import SwiftUI

struct MarkdownPreviewView: View {
    let document: MarkdownDocument

    @State private var blockedLink: BlockedMarkdownLink?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                // A parsed document is read-only. Position distinguishes even identical blocks.
                ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                    MarkdownBlockView(block: block)
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemBackground))
        .environment(\.openURL, OpenURLAction { url in
            blockedLink = MarkdownLinkPolicy.blockedLink(for: url)
            return .handled
        })
        .alert(item: $blockedLink) { link in
            Alert(
                title: Text(link.title),
                message: Text(link.message),
                primaryButton: .default(Text(AppStrings.Actions.copyLink)) {
                    UIPasteboard.general.string = link.url.absoluteString
                },
                secondaryButton: .cancel(Text(AppStrings.Actions.ok))
            )
        }
    }
}

struct BlockedMarkdownLink: Identifiable, Equatable {
    enum Reason: Equatable {
        case externalWebURL
        case unsupportedURL
    }

    let url: URL
    let reason: Reason

    var id: String {
        "\(reason)-\(url.absoluteString)"
    }

    var title: String {
        switch reason {
        case .externalWebURL:
            AppStrings.Security.externalMarkdownLinkTitle
        case .unsupportedURL:
            AppStrings.Security.unsupportedMarkdownLinkTitle
        }
    }

    var message: String {
        switch reason {
        case .externalWebURL:
            AppStrings.Security.externalMarkdownLinkMessage
        case .unsupportedURL:
            AppStrings.Security.unsupportedMarkdownLinkMessage
        }
    }
}

enum MarkdownLinkPolicy {
    static func blockedLink(for url: URL) -> BlockedMarkdownLink {
        if let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return BlockedMarkdownLink(url: url, reason: .externalWebURL)
        }

        return BlockedMarkdownLink(url: url, reason: .unsupportedURL)
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(font(forHeadingLevel: level))
                .fontWeight(level <= 2 ? .bold : .semibold)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, level == 1 ? 0 : 12)
        case .paragraph(let text):
            Text(text)
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .blockQuote(let blocks):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, child in
                        MarkdownBlockView(block: child)
                    }
                }
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 8) {
                if let language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        case .unorderedList(let items):
            MarkdownListView(items: items, start: nil)
        case .orderedList(let start, let items):
            MarkdownListView(items: items, start: start)
        case .table(let table):
            MarkdownTableView(table: table)
        case .image(let image):
            MarkdownImageView(image: image)
        case .thematicBreak:
            Divider()
        }
    }

    private func font(forHeadingLevel level: Int) -> Font {
        switch level {
        case 1: .largeTitle.bold()
        case 2: .title2.bold()
        case 3: .title3.weight(.semibold)
        default: .headline
        }
    }
}

private struct MarkdownTableView: View {
    let table: MarkdownTable

    @ScaledMetric(relativeTo: .body) private var minimumColumnWidth: CGFloat = 88
    @ScaledMetric(relativeTo: .body) private var maximumColumnWidth: CGFloat = 240

    var body: some View {
        let widths = columnWidths

        ScrollView(.horizontal) {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                tableRow(table.header, widths: widths, isHeader: true)
                    .background(Color(.secondarySystemBackground))
                ForEach(table.rows.indices, id: \.self) { rowIndex in
                    tableRow(table.rows[rowIndex], widths: widths, isHeader: false)
                        .background(rowIndex.isMultiple(of: 2) ? Color(.systemBackground) : Color(.tertiarySystemBackground))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            }
            .padding(.bottom, 6)
        }
        .accessibilityElement(children: .contain)
    }

    private func tableRow(_ cells: [AttributedString], widths: [CGFloat], isHeader: Bool) -> some View {
        GridRow(alignment: .top) {
            ForEach(cells.indices, id: \.self) { column in
                Text(cells[column])
                    .font(.body)
                    .fontWeight(isHeader ? .semibold : nil)
                    .multilineTextAlignment(textAlignment(for: table.columnAlignments[column]))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: widths[column], alignment: frameAlignment(for: table.columnAlignments[column]))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .accessibilityLabel(accessibilityLabel(for: cells[column], column: column, isHeader: isHeader))
                    .accessibilityAddTraits(isHeader ? .isHeader : [])
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }

    private var columnWidths: [CGFloat] {
        let font = UIFont.boldSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize)
        return table.header.indices.map { column in
            let cells = [table.header[column]] + table.rows.map { $0[column] }
            let textWidth = cells.map { cell in
                (String(cell.characters) as NSString).size(withAttributes: [.font: font]).width
            }.max() ?? 0
            return min(maximumColumnWidth, max(minimumColumnWidth, ceil(textWidth)))
        }
    }

    private func frameAlignment(for alignment: MarkdownTable.ColumnAlignment) -> Alignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private func textAlignment(for alignment: MarkdownTable.ColumnAlignment) -> TextAlignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private func accessibilityLabel(for cell: AttributedString, column: Int, isHeader: Bool) -> Text {
        if isHeader || table.header[column].characters.isEmpty {
            return Text(cell)
        }
        return Text(table.header[column]) + Text(": ") + Text(cell)
    }
}

private struct MarkdownListView: View {
    let items: [MarkdownListItem]
    let start: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text(marker(for: index))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.text)
                            .font(.body)
                            .textSelection(.enabled)
                        ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                            MarkdownBlockView(block: child)
                        }
                    }
                }
            }
        }
    }

    private func marker(for index: Int) -> String {
        if let start {
            return "\(start + index)."
        }
        return "•"
    }
}

private struct MarkdownImageView: View {
    let image: MarkdownImage

    var body: some View {
        switch image.kind {
        case .local(let url):
            if let uiImage = UIImage(contentsOfFile: url.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(image.altText.isEmpty ? AppStrings.Accessibility.markdownImage : image.altText)
            } else {
                placeholder(AppStrings.MarkdownImages.localUnavailable, detail: image.source)
            }
        case .remoteBlocked(let source):
            placeholder(AppStrings.MarkdownImages.remoteBlocked, detail: source)
        case .unsupported(let source):
            placeholder(AppStrings.MarkdownImages.unsupported, detail: source)
        }
    }

    private func placeholder(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: "photo")
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(detail)")
    }
}

#Preview {
    MarkdownPreviewView(
        document: MarkdownRenderService().render(
            markdown: """
            # Preview

            A paragraph with **strong text**, *emphasis*, and `code`.

            - First
            - Second

            > A quote.

            | Item | Status | Count |
            | :--- | :---: | ---: |
            | **Reports** | Ready | 12 |
            | Notes with a longer description that wraps | Review | 3 |
            """
        )
    )
}
