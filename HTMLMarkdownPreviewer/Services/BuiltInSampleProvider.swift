import Foundation
import ZIPFoundation

final class BuiltInSampleProvider {
    private let fileManager: FileManager
    private let rootURL: URL

    init(
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? fileManager.temporaryDirectory
            .appendingPathComponent("HTMLMarkdownPreviewerBuiltInSamples", isDirectory: true)
    }

    func makeSampleURL(for sample: BuiltInSample) throws -> URL {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let sampleURL = rootURL.appendingPathComponent(sample.filename)

        if fileManager.fileExists(atPath: sampleURL.path) {
            try fileManager.removeItem(at: sampleURL)
        }

        switch sample {
        case .html:
            try Self.htmlSample.write(to: sampleURL, atomically: true, encoding: .utf8)
        case .markdown:
            try Self.markdownSample.write(to: sampleURL, atomically: true, encoding: .utf8)
        case .zipPackage:
            try writeZipSample(to: sampleURL)
        }

        return sampleURL
    }

    private func writeZipSample(to url: URL) throws {
        let archive = try Archive(url: url, accessMode: .create)
        let files: [(path: String, data: Data)] = [
            ("index.html", Self.zipHTML.data(using: .utf8)!),
            ("assets/style.css", Self.zipCSS.data(using: .utf8)!),
            ("images/pixel.svg", Self.zipSVG.data(using: .utf8)!)
        ]

        for file in files {
            try archive.addEntry(
                with: file.path,
                type: .file,
                uncompressedSize: Int64(file.data.count),
                compressionMethod: .deflate
            ) { position, size in
                let start = file.data.index(file.data.startIndex, offsetBy: Int(position))
                let end = file.data.index(start, offsetBy: size)
                return file.data.subdata(in: start..<end)
            }
        }
    }
}

private extension BuiltInSampleProvider {
    static var htmlSample: String {
        """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        body { font: -apple-system-body; margin: 32px; line-height: 1.5; }
        h1 { font-size: 28px; }
        code { background: #f2f2f7; padding: 2px 5px; border-radius: 4px; }
      </style>
    </head>
    <body>
      <h1>\(AppStrings.SampleContent.htmlHeading)</h1>
      <p>\(AppStrings.SampleContent.htmlLocalRendering)</p>
      <p>\(AppStrings.SampleContent.htmlExternalResources)</p>
      <p><code>sample.html</code></p>
    </body>
    </html>
    """
    }

    static var markdownSample: String {
        """
    # \(AppStrings.SampleContent.markdownHeading)

    \(AppStrings.SampleContent.markdownIntro)

    - \(AppStrings.SampleContent.markdownHeadings)
    - \(AppStrings.SampleContent.markdownInlineStyles)
    - \(AppStrings.SampleContent.markdownLists)

    > \(AppStrings.SampleContent.markdownRemoteImages)

    ```swift
    let mode = "\(AppStrings.PreviewModes.safePreview)"
    ```
    """
    }

    static var zipHTML: String {
        """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <link rel="stylesheet" href="assets/style.css">
    </head>
    <body>
      <main>
        <h1>\(AppStrings.SampleContent.zipHeading)</h1>
        <p>\(AppStrings.SampleContent.zipLocalAssets)</p>
        <img src="images/pixel.svg" alt="\(AppStrings.SampleContent.zipImageAlt)">
      </main>
    </body>
    </html>
    """
    }

    static let zipCSS = """
    body { margin: 0; font: -apple-system-body; background: #f7f7fb; color: #1d1d1f; }
    main { margin: 32px; padding: 20px; background: white; border: 1px solid #d9d9e3; border-radius: 8px; }
    h1 { font-size: 26px; margin-top: 0; }
    img { width: 56px; height: 56px; }
    """

    static let zipSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="56" height="56" viewBox="0 0 56 56">
      <rect width="56" height="56" rx="10" fill="#2f80ed"/>
      <path d="M16 29h24M28 17v24" stroke="white" stroke-width="5" stroke-linecap="round"/>
    </svg>
    """
}
