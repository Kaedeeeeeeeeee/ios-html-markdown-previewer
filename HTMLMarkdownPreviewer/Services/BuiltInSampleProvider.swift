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
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        :root {
          color-scheme: dark;
          --ink: #f8fbff;
          --muted: #9fb1ca;
          --panel: rgba(18, 35, 61, .78);
          --line: rgba(148, 190, 255, .18);
          --blue: #2f8cff;
          --cyan: #6ee7ff;
          --violet: #8b5cf6;
        }
        * { box-sizing: border-box; }
        body {
          margin: 0;
          min-height: 100vh;
          overflow-x: hidden;
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif;
          color: var(--ink);
          background:
            radial-gradient(circle at 82% 6%, rgba(47, 140, 255, .34), transparent 34%),
            radial-gradient(circle at 12% 48%, rgba(139, 92, 246, .22), transparent 36%),
            #07111f;
        }
        body::before {
          content: "";
          position: fixed;
          inset: 0;
          pointer-events: none;
          opacity: .18;
          background-image:
            linear-gradient(var(--line) 1px, transparent 1px),
            linear-gradient(90deg, var(--line) 1px, transparent 1px);
          background-size: 36px 36px;
          mask-image: linear-gradient(to bottom, black, transparent 78%);
        }
        main { position: relative; width: min(100%, 760px); margin: 0 auto; padding: 24px 20px 36px; }
        .eyebrow {
          display: inline-flex;
          align-items: center;
          gap: 8px;
          padding: 7px 11px;
          border: 1px solid rgba(110, 231, 255, .3);
          border-radius: 999px;
          background: rgba(9, 25, 45, .7);
          color: #c9f7ff;
          font-size: 12px;
          font-weight: 700;
          letter-spacing: .08em;
          text-transform: uppercase;
        }
        .eyebrow::before {
          content: "";
          width: 7px;
          height: 7px;
          border-radius: 50%;
          background: var(--cyan);
          box-shadow: 0 0 16px var(--cyan);
          animation: pulse 2s ease-in-out infinite;
        }
        h1 { max-width: 600px; margin: 18px 0 10px; font-size: clamp(34px, 8vw, 62px); line-height: .98; letter-spacing: -.045em; }
        .intro { max-width: 590px; margin: 0; color: var(--muted); font-size: 16px; line-height: 1.55; }
        .stage {
          position: relative;
          height: 245px;
          margin: 24px 0 14px;
          overflow: hidden;
          border: 1px solid var(--line);
          border-radius: 26px;
          background: linear-gradient(145deg, rgba(18, 35, 61, .88), rgba(7, 17, 31, .72));
          box-shadow: 0 24px 80px rgba(0, 0, 0, .32), inset 0 1px rgba(255, 255, 255, .06);
        }
        .stage-copy { position: absolute; z-index: 2; top: 22px; left: 22px; }
        .stage-copy strong { display: block; font-size: 21px; letter-spacing: -.02em; }
        .stage-copy span { display: block; margin-top: 5px; color: var(--muted); font-size: 13px; }
        .orbit-system { position: absolute; width: 280px; height: 280px; right: -26px; bottom: -33px; animation: float 6s ease-in-out infinite; }
        .orbit { transform-origin: 140px 140px; animation: orbit 14s linear infinite; }
        .orbit.reverse { animation-direction: reverse; animation-duration: 10s; }
        .dash { stroke-dasharray: 7 11; animation: dash 7s linear infinite; }
        .metrics { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; }
        .metric {
          min-width: 0;
          padding: 14px;
          border: 1px solid var(--line);
          border-radius: 18px;
          background: var(--panel);
          backdrop-filter: blur(18px);
        }
        .metric small { display: block; overflow: hidden; color: var(--muted); font-size: 10px; letter-spacing: .08em; text-overflow: ellipsis; text-transform: uppercase; }
        .metric strong { display: block; margin-top: 8px; font-size: clamp(20px, 6vw, 30px); letter-spacing: -.04em; }
        .metric em { display: block; margin-top: 4px; color: #76efb8; font-size: 11px; font-style: normal; }
        .chart-card {
          display: grid;
          grid-template-columns: minmax(0, 1fr) 92px;
          gap: 14px;
          align-items: end;
          margin-top: 10px;
          padding: 16px;
          border: 1px solid var(--line);
          border-radius: 20px;
          background: rgba(11, 25, 44, .88);
        }
        .chart-card h2 { margin: 0; font-size: 14px; }
        .chart-card p { margin: 4px 0 12px; color: var(--muted); font-size: 11px; }
        .sparkline { display: block; width: 100%; height: 66px; }
        .bars { display: flex; align-items: end; gap: 5px; height: 88px; }
        .bar { flex: 1; height: var(--height); border-radius: 6px 6px 2px 2px; background: linear-gradient(to top, var(--violet), var(--cyan)); transform-origin: bottom; animation: grow 1.4s cubic-bezier(.2,.8,.2,1) both; }
        .bar:nth-child(2) { animation-delay: .12s; }
        .bar:nth-child(3) { animation-delay: .24s; }
        .bar:nth-child(4) { animation-delay: .36s; }
        .footer { display: flex; align-items: center; justify-content: space-between; margin-top: 14px; color: var(--muted); font-size: 11px; }
        .stack { display: flex; gap: 6px; }
        .stack span { padding: 5px 8px; border-radius: 999px; background: rgba(255,255,255,.06); color: #dce9fb; }
        @keyframes orbit { to { transform: rotate(360deg); } }
        @keyframes dash { to { stroke-dashoffset: -90; } }
        @keyframes float { 50% { transform: translateY(-9px) scale(1.015); } }
        @keyframes pulse { 50% { opacity: .46; box-shadow: 0 0 5px var(--cyan); } }
        @keyframes grow { from { transform: scaleY(.08); opacity: .25; } }
        @media (prefers-reduced-motion: reduce) {
          *, *::before, *::after { animation-duration: .001ms !important; animation-iteration-count: 1 !important; }
        }
      </style>
    </head>
    <body>
      <main>
        <div class="eyebrow">Safe local preview</div>
        <h1>\(AppStrings.SampleContent.htmlHeading)</h1>
        <p class="intro">\(AppStrings.SampleContent.htmlLocalRendering) \(AppStrings.SampleContent.htmlExternalResources)</p>

        <section class="stage" aria-label="Animated CSS and SVG visualization">
          <div class="stage-copy">
            <strong>Render pulse</strong>
            <span>CSS motion · inline SVG · responsive grid</span>
          </div>
          <svg class="orbit-system" viewBox="0 0 280 280" role="img" aria-label="Animated orbital data graphic">
            <defs>
              <radialGradient id="core" cx="45%" cy="38%">
                <stop offset="0" stop-color="#d9fbff"/>
                <stop offset=".35" stop-color="#6ee7ff"/>
                <stop offset="1" stop-color="#2f8cff"/>
              </radialGradient>
              <linearGradient id="ring" x1="0" y1="0" x2="1" y2="1">
                <stop stop-color="#6ee7ff"/>
                <stop offset="1" stop-color="#8b5cf6"/>
              </linearGradient>
              <filter id="glow"><feGaussianBlur stdDeviation="5" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
            </defs>
            <circle cx="140" cy="140" r="94" fill="none" stroke="rgba(148,190,255,.16)"/>
            <circle class="dash" cx="140" cy="140" r="112" fill="none" stroke="url(#ring)" stroke-width="1.5"/>
            <g class="orbit">
              <ellipse cx="140" cy="140" rx="124" ry="55" fill="none" stroke="rgba(110,231,255,.42)" transform="rotate(-22 140 140)"/>
              <circle cx="34" cy="185" r="7" fill="#6ee7ff" filter="url(#glow)"/>
            </g>
            <g class="orbit reverse">
              <ellipse cx="140" cy="140" rx="78" ry="126" fill="none" stroke="rgba(139,92,246,.55)" transform="rotate(48 140 140)"/>
              <circle cx="73" cy="71" r="6" fill="#a78bfa" filter="url(#glow)"/>
            </g>
            <circle cx="140" cy="140" r="44" fill="rgba(47,140,255,.12)" stroke="rgba(110,231,255,.3)"/>
            <circle cx="140" cy="140" r="25" fill="url(#core)" filter="url(#glow)"/>
            <path d="M131 140l7 7 13-17" fill="none" stroke="#07111f" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>
          </svg>
        </section>

        <section class="metrics" aria-label="Preview metrics">
          <article class="metric"><small>Layout</small><strong>98</strong><em>+12.4%</em></article>
          <article class="metric"><small>Assets</small><strong>24</strong><em>local</em></article>
          <article class="metric"><small>Network</small><strong>0</strong><em>blocked</em></article>
        </section>

        <section class="chart-card">
          <div>
            <h2>Rendering performance</h2>
            <p>A complete visual scene in one local HTML file.</p>
            <svg class="sparkline" viewBox="0 0 260 66" preserveAspectRatio="none" aria-label="Rising performance line chart">
              <defs><linearGradient id="area" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#2f8cff" stop-opacity=".48"/><stop offset="1" stop-color="#2f8cff" stop-opacity="0"/></linearGradient></defs>
              <path d="M0 57 C28 48 38 54 62 39 S104 45 126 30 S166 36 186 19 S226 23 260 5 L260 66 L0 66Z" fill="url(#area)"/>
              <path class="dash" d="M0 57 C28 48 38 54 62 39 S104 45 126 30 S166 36 186 19 S226 23 260 5" fill="none" stroke="#6ee7ff" stroke-width="3" stroke-linecap="round"/>
            </svg>
          </div>
          <div class="bars" aria-hidden="true">
            <span class="bar" style="--height:42%"></span>
            <span class="bar" style="--height:66%"></span>
            <span class="bar" style="--height:54%"></span>
            <span class="bar" style="--height:88%"></span>
          </div>
        </section>
        <div class="footer"><span>sample.html</span><div class="stack"><span>CSS</span><span>SVG</span><span>Offline</span></div></div>
      </main>
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
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <link rel="stylesheet" href="assets/style.css">
    </head>
    <body>
      <main>
        <header>
          <div>
            <span class="kicker">Local package · Q3</span>
            <h1>\(AppStrings.SampleContent.zipHeading)</h1>
            <p>\(AppStrings.SampleContent.zipLocalAssets)</p>
          </div>
          <span class="status">Ready</span>
        </header>
        <section class="summary">
          <article><small>Reports</small><strong>128</strong><span>+18%</span></article>
          <article><small>Complete</small><strong>94%</strong><span>+6.2%</span></article>
          <article><small>Assets</small><strong>24</strong><span>local</span></article>
        </section>
        <section class="chart">
          <div class="chart-heading"><div><small>ACTIVITY</small><h2>Weekly overview</h2></div><span>Jul 8–14</span></div>
          <img src="images/pixel.svg" alt="\(AppStrings.SampleContent.zipImageAlt)">
        </section>
        <footer><span><i></i> All resources loaded from this ZIP</span><code>index.html + CSS + SVG</code></footer>
      </main>
    </body>
    </html>
    """
    }

    static let zipCSS = """
    :root { color-scheme: light; --ink:#13213a; --muted:#74829a; --blue:#2378f3; --violet:#7357e8; --line:#dde6f3; }
    * { box-sizing: border-box; }
    body { margin: 0; min-height: 100vh; font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: linear-gradient(155deg, #edf5ff, #f7f5ff 52%, #eef9ff); color: var(--ink); }
    main { width: min(100%, 760px); margin: 0 auto; padding: 24px 18px 32px; }
    header { display: flex; justify-content: space-between; gap: 16px; align-items: flex-start; padding: 22px; color: white; border-radius: 24px; background: radial-gradient(circle at 88% 0, rgba(101,227,255,.65), transparent 32%), linear-gradient(135deg, #1769e8, #6438d8); box-shadow: 0 18px 50px rgba(47, 85, 164, .24); }
    .kicker { font-size: 11px; font-weight: 700; letter-spacing: .1em; text-transform: uppercase; opacity: .78; }
    h1 { margin: 9px 0 6px; font-size: clamp(29px, 7vw, 46px); line-height: 1; letter-spacing: -.04em; }
    header p { max-width: 520px; margin: 0; font-size: 13px; line-height: 1.45; opacity: .78; }
    .status { flex: none; padding: 7px 10px; border: 1px solid rgba(255,255,255,.38); border-radius: 999px; background: rgba(255,255,255,.16); font-size: 11px; font-weight: 700; }
    .summary { display: grid; grid-template-columns: repeat(3, 1fr); gap: 9px; margin-top: 12px; }
    .summary article { min-width: 0; padding: 14px; border: 1px solid rgba(221,230,243,.9); border-radius: 17px; background: rgba(255,255,255,.82); box-shadow: 0 10px 28px rgba(42, 73, 121, .07); }
    .summary small { display: block; color: var(--muted); font-size: 10px; }
    .summary strong { display: block; margin: 6px 0 2px; font-size: clamp(21px, 6vw, 31px); letter-spacing: -.04em; }
    .summary span { color: #119b6c; font-size: 10px; font-weight: 700; }
    .chart { margin-top: 12px; padding: 17px; border: 1px solid var(--line); border-radius: 20px; background: rgba(255,255,255,.92); box-shadow: 0 14px 35px rgba(42, 73, 121, .08); }
    .chart-heading { display: flex; justify-content: space-between; align-items: flex-end; gap: 12px; }
    .chart-heading small { color: var(--blue); font-size: 9px; font-weight: 800; letter-spacing: .13em; }
    .chart-heading h2 { margin: 4px 0 0; font-size: 17px; }
    .chart-heading > span { color: var(--muted); font-size: 10px; }
    img { display: block; width: 100%; height: auto; margin-top: 12px; }
    footer { display: flex; justify-content: space-between; gap: 10px; align-items: center; margin-top: 12px; padding: 0 4px; color: var(--muted); font-size: 9px; }
    footer i { display: inline-block; width: 7px; height: 7px; margin-right: 5px; border-radius: 50%; background: #22c58b; box-shadow: 0 0 0 4px rgba(34,197,139,.12); }
    code { padding: 5px 7px; border-radius: 7px; background: rgba(35,120,243,.08); color: #3f5d89; font-size: 8px; }
    """

    static let zipSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="720" height="300" viewBox="0 0 720 300" role="img" aria-label="Weekly activity chart">
      <defs>
        <linearGradient id="fill" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#2378f3" stop-opacity=".28"/><stop offset="1" stop-color="#2378f3" stop-opacity="0"/></linearGradient>
        <linearGradient id="stroke" x1="0" y1="0" x2="1" y2="0"><stop stop-color="#2378f3"/><stop offset="1" stop-color="#7357e8"/></linearGradient>
      </defs>
      <g stroke="#e5ebf4" stroke-width="1">
        <path d="M48 34H694M48 94H694M48 154H694M48 214H694"/>
      </g>
      <path d="M48 211 C94 201 116 168 157 179 S229 140 266 151 S330 111 374 124 S447 72 489 93 S554 61 594 70 S655 39 694 46 L694 252 L48 252Z" fill="url(#fill)"/>
      <path d="M48 211 C94 201 116 168 157 179 S229 140 266 151 S330 111 374 124 S447 72 489 93 S554 61 594 70 S655 39 694 46" fill="none" stroke="url(#stroke)" stroke-width="7" stroke-linecap="round"/>
      <g fill="#fff" stroke="#2378f3" stroke-width="5"><circle cx="157" cy="179" r="7"/><circle cx="266" cy="151" r="7"/><circle cx="374" cy="124" r="7"/><circle cx="489" cy="93" r="7"/><circle cx="594" cy="70" r="7"/><circle cx="694" cy="46" r="7"/></g>
      <g fill="#7c899c" font-family="-apple-system, sans-serif" font-size="15" text-anchor="middle"><text x="48" y="284">MON</text><text x="157" y="284">TUE</text><text x="266" y="284">WED</text><text x="374" y="284">THU</text><text x="489" y="284">FRI</text><text x="594" y="284">SAT</text><text x="694" y="284">SUN</text></g>
    </svg>
    """
}
