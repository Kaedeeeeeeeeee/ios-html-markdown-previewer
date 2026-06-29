import SwiftUI

struct MarkdownPreviewView: View {
    let document: MarkdownDocument

    @State private var blockedLink: BlockedMarkdownLink?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(document.blocks) { block in
                    MarkdownBlockView(block: block)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    ForEach(blocks) { child in
                        MarkdownBlockView(block: child)
                    }
                }
            }
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
                        .padding(12)
                }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        case .unorderedList(let items):
            MarkdownListView(items: items, start: nil)
        case .orderedList(let start, let items):
            MarkdownListView(items: items, start: start)
        case .image(let image):
            MarkdownImageView(image: image)
        case .thematicBreak:
            Divider()
        }
    }

    private func font(forHeadingLevel level: Int) -> Font {
        switch level {
        case 1: .title.bold()
        case 2: .title2.bold()
        case 3: .title3.weight(.semibold)
        default: .headline
        }
    }
}

private struct MarkdownListView: View {
    let items: [MarkdownListItem]
    let start: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text(marker(for: index))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.text)
                            .font(.body)
                            .textSelection(.enabled)
                        ForEach(item.children) { child in
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
                    .accessibilityLabel(image.altText)
            } else {
                placeholder("Local image unavailable", detail: image.source)
            }
        case .remoteBlocked(let source):
            placeholder("Remote image blocked", detail: source)
        case .unsupported(let source):
            placeholder("Unsupported image", detail: source)
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
            """
        )
    )
}
