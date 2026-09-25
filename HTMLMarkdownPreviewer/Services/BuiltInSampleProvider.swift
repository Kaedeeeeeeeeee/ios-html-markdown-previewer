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

extension BuiltInSampleProvider {
    static var htmlSample: String {
        """
        <!doctype html>
        <html lang="\(sampleLanguage)">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="color-scheme" content="light dark">
          <title>\(escaped(AppStrings.SampleDesign.htmlTitle))</title>
          <style>\(sampleCSS)\(htmlMotionCSS)</style>
        </head>
        <body>
          <main>
            <header class="document-header">
              <p class="eyebrow">\(escaped(AppStrings.SampleDesign.htmlEyebrow))</p>
              <h1>\(escaped(AppStrings.SampleDesign.htmlTitle))</h1>
              <p class="intro">\(escaped(AppStrings.SampleDesign.htmlIntro))</p>
              <p class="dateline">\(escaped(AppStrings.SampleDesign.htmlDate))</p>
            </header>
            \(htmlMotionScene)
            <section aria-labelledby="plan-heading">
              <h2 class="section-label" id="plan-heading">\(escaped(AppStrings.SampleDesign.htmlSection))</h2>
              <ol class="schedule panel">
                <li id="coffee-stop">
                  <time datetime="09:30">09:30</time>
                  <div><h3>\(escaped(AppStrings.SampleDesign.htmlStopOne))</h3><p>\(escaped(AppStrings.SampleDesign.htmlStopOneDetail))</p></div>
                </li>
                <li id="river-stop">
                  <time datetime="11:00">11:00</time>
                  <div><h3>\(escaped(AppStrings.SampleDesign.htmlStopTwo))</h3><p>\(escaped(AppStrings.SampleDesign.htmlStopTwoDetail))</p></div>
                </li>
                <li id="book-stop">
                  <time datetime="14:00">14:00</time>
                  <div><h3>\(escaped(AppStrings.SampleDesign.htmlStopThree))</h3><p>\(escaped(AppStrings.SampleDesign.htmlStopThreeDetail))</p></div>
                </li>
              </ol>
              <p class="caption">\(escaped(AppStrings.SampleDesign.htmlSummary))</p>
            </section>
            <aside class="note">
              <h2>\(escaped(AppStrings.SampleDesign.htmlNoteTitle))</h2>
              <p>\(escaped(AppStrings.SampleDesign.htmlNote))</p>
            </aside>
            <details class="packing-note">
              <summary>\(escaped(AppStrings.SampleDesign.htmlPackingTitle))</summary>
              <p>\(escaped(AppStrings.SampleDesign.htmlPackingBody))</p>
            </details>
            <footer><p>\(escaped(AppStrings.SampleDesign.htmlFooter))</p><span>\(escaped(AppStrings.SampleDesign.sampleLabel)) · HTML</span></footer>
          </main>
        </body>
        </html>
        """
    }

    static var zipHTML: String {
        """
        <!doctype html>
        <html lang="\(sampleLanguage)">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="color-scheme" content="light dark">
          <title>\(escaped(AppStrings.SampleDesign.zipTitle))</title>
          <link rel="stylesheet" href="assets/style.css">
        </head>
        <body>
          <main>
            <header class="document-header report-header">
              <p class="eyebrow">\(escaped(AppStrings.SampleDesign.zipEyebrow))</p>
              <h1>\(escaped(AppStrings.SampleDesign.zipTitle))</h1>
              <p class="intro">\(escaped(AppStrings.SampleDesign.zipIntro))</p>
              <p class="dateline">\(escaped(AppStrings.SampleDesign.zipPeriod))</p>
            </header>
            <section class="reading-total" aria-label="\(escaped(AppStrings.SampleDesign.zipMinutes))">
              <strong>247</strong><span>\(escaped(AppStrings.SampleDesign.zipMinutes))</span>
            </section>
            <figure class="reading-chart panel">
              <figcaption>\(escaped(AppStrings.SampleDesign.zipChartHeading))</figcaption>
              <img src="images/pixel.svg" width="560" height="180" alt="\(escaped(AppStrings.SampleDesign.zipChartAlt))">
              <div class="weekdays" aria-hidden="true">
                <span>\(escaped(AppStrings.SampleDesign.zipMonday))</span><span>\(escaped(AppStrings.SampleDesign.zipTuesday))</span><span>\(escaped(AppStrings.SampleDesign.zipWednesday))</span><span>\(escaped(AppStrings.SampleDesign.zipThursday))</span><span>\(escaped(AppStrings.SampleDesign.zipFriday))</span><span>\(escaped(AppStrings.SampleDesign.zipSaturday))</span><span>\(escaped(AppStrings.SampleDesign.zipSunday))</span>
              </div>
              <p class="caption">\(escaped(AppStrings.SampleDesign.zipRhythm))</p>
            </figure>
            <section class="highlights" aria-labelledby="highlights-heading">
              <h2 class="section-label" id="highlights-heading">\(escaped(AppStrings.SampleDesign.zipHighlights))</h2>
              <div class="highlight"><span class="item-number" aria-hidden="true">01</span><div><h3>\(escaped(AppStrings.SampleDesign.zipHighlightOne))</h3><p>\(escaped(AppStrings.SampleDesign.zipHighlightOneDetail))</p></div></div>
              <div class="highlight"><span class="item-number" aria-hidden="true">02</span><div><h3>\(escaped(AppStrings.SampleDesign.zipHighlightTwo))</h3><p>\(escaped(AppStrings.SampleDesign.zipHighlightTwoDetail))</p></div></div>
            </section>
            <footer><p>\(escaped(AppStrings.SampleDesign.zipFooter))</p><span>\(escaped(AppStrings.SampleDesign.sampleLabel)) · ZIP</span></footer>
          </main>
        </body>
        </html>
        """
    }

    static var zipCSS: String { sampleCSS }

    /// The external image is a real data chart, keeping the ZIP's relative-asset example useful.
    /// Solid fills also survive WebKit's PDF printing without gradient/blending artifacts.
    static let zipSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="560" height="180" viewBox="0 0 560 180">
      <g stroke="#8e8e93" stroke-opacity=".25" stroke-width="1">
        <path d="M0 24H560M0 96H560M0 168H560"/>
      </g>
      <g fill="#007aff">
        <rect x="18" y="118.15" width="44" height="49.85" rx="6" opacity=".55"/>
        <rect x="98" y="79.38" width="44" height="88.62" rx="6" opacity=".65"/>
        <rect x="178" y="101.54" width="44" height="66.46" rx="6" opacity=".55"/>
        <rect x="258" y="43.38" width="44" height="124.62" rx="6" opacity=".8"/>
        <rect x="338" y="68.31" width="44" height="99.69" rx="6" opacity=".65"/>
        <rect x="418" y="24" width="44" height="144" rx="6"/>
        <rect x="498" y="57.23" width="44" height="110.77" rx="6" opacity=".8"/>
      </g>
    </svg>
    """

    static let sampleCSS = """
    :root {
      color-scheme: light dark;
      --background: #ffffff;
      --surface: #f2f2f7;
      --ink: #1c1c1e;
      --secondary: #636366;
      --line: #d1d1d6;
      --accent: #0066cc;
      --note: #edf5ff;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --background: #000000;
        --surface: #1c1c1e;
        --ink: #f5f5f7;
        --secondary: #a1a1a6;
        --line: #38383a;
        --accent: #64a8ff;
        --note: #101e2e;
      }
    }
    * { box-sizing: border-box; }
    html { font: -apple-system-body; -webkit-text-size-adjust: 100%; }
    body { margin: 0; background: var(--background); color: var(--ink); font-family: -apple-system, BlinkMacSystemFont, sans-serif; line-height: 1.5; }
    main { max-width: 680px; margin: 0 auto; padding: 28px 24px 36px; }
    p, h1, h2, h3, figure { margin: 0; }
    .eyebrow { color: var(--accent); font-size: .7rem; font-weight: 650; letter-spacing: .1em; }
    h1 { margin-top: 12px; font-size: 2rem; font-weight: 700; line-height: 1.12; letter-spacing: -.035em; overflow-wrap: break-word; }
    .intro { margin-top: 12px; color: var(--secondary); font-size: 1rem; line-height: 1.55; }
    .dateline { margin-top: 20px; color: var(--secondary); font-size: .76rem; font-variant-numeric: tabular-nums; }
    .document-header { padding-bottom: 28px; }
    .section-label { margin: 0 0 12px 2px; font-size: .8rem; font-weight: 600; color: var(--secondary); }
    .panel { background: var(--surface); border-radius: 20px; }
    .schedule { list-style: none; padding: 0 20px; margin: 0; }
    .schedule li { display: grid; grid-template-columns: 52px minmax(0, 1fr); gap: 16px; padding: 20px 0; }
    .schedule li + li { border-top: .5px solid var(--line); }
    time { color: var(--accent); font-size: .8rem; font-weight: 600; font-variant-numeric: tabular-nums; padding-top: 2px; }
    h3 { font-size: .94rem; font-weight: 600; line-height: 1.4; }
    .schedule p, .highlight p { margin-top: 6px; color: var(--secondary); font-size: .82rem; line-height: 1.55; }
    .caption { margin: 12px 2px 0; color: var(--secondary); font-size: .72rem; }
    .note { margin-top: 28px; padding: 20px; border-radius: 20px; background: var(--note); }
    .note h2 { font-size: .94rem; font-weight: 600; }
    .note p { margin-top: 8px; color: var(--secondary); font-size: .85rem; line-height: 1.6; }
    footer { margin-top: 28px; padding-top: 20px; border-top: .5px solid var(--line); }
    footer p { color: var(--secondary); font-size: .82rem; }
    footer span { display: block; margin-top: 8px; color: var(--secondary); font-size: .66rem; }
    .report-header { padding-bottom: 20px; }
    .reading-total { display: flex; align-items: baseline; flex-wrap: wrap; gap: 0 12px; margin-bottom: 24px; }
    .reading-total strong { color: var(--accent); font-size: 4rem; font-weight: 700; line-height: 1.1; letter-spacing: -.055em; font-variant-numeric: tabular-nums; }
    .reading-total span { color: var(--secondary); font-size: .85rem; }
    .reading-chart { margin: 0; padding: 20px; break-inside: avoid; }
    figcaption { font-size: .94rem; font-weight: 600; }
    .reading-chart img { display: block; width: 100%; height: auto; margin-top: 20px; }
    .weekdays { display: grid; grid-template-columns: repeat(7, minmax(0, 1fr)); gap: 0; color: var(--secondary); text-align: center; font-size: .6rem; }
    .highlights { margin-top: 28px; }
    .highlight { display: grid; grid-template-columns: 24px minmax(0, 1fr); gap: 12px; padding: 16px 0; }
    .highlight + .highlight { border-top: .5px solid var(--line); }
    .item-number { color: var(--accent); font-size: .76rem; padding-top: 3px; font-variant-numeric: tabular-nums; }
    @media (max-width: 350px) {
      main { padding: 24px 20px 32px; }
      .schedule { padding: 0 16px; }
      .schedule li { grid-template-columns: 46px minmax(0, 1fr); gap: 12px; }
    }
    @media print {
      :root { color-scheme: light; --background: #fff; --surface: #f2f2f7; --ink: #1c1c1e; --secondary: #636366; --line: #d1d1d6; --accent: #0066cc; --note: #edf5ff; }
      html { font-size: 12pt; }
      main { max-width: none; padding: 8px 0; }
      .document-header { padding-bottom: 20px; }
      .schedule li { padding: 16px 0; break-inside: avoid; }
      .note, .highlights, footer { margin-top: 20px; }
      .note, .highlight, footer { break-inside: avoid; }
      h1, h2, h3, figcaption { break-after: avoid; }
      * { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    }
    """

    private static var sampleLanguage: String {
        escaped(Bundle.main.preferredLocalizations.first ?? "en")
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
