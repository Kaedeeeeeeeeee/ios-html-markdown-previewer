import Foundation

extension BuiltInSampleProvider {
    static var zipDetailsHTML: String {
        let days = [AppStrings.SampleDesign.zipMonday, AppStrings.SampleDesign.zipTuesday,
                    AppStrings.SampleDesign.zipWednesday, AppStrings.SampleDesign.zipThursday,
                    AppStrings.SampleDesign.zipFriday, AppStrings.SampleDesign.zipSaturday,
                    AppStrings.SampleDesign.zipSunday]
        let durations = [18, 32, 24, 45, 36, 52, 40]
        let rows = zip(days, durations).map { day, duration in
            "<tr><th scope=\"row\">\(escaped(day))</th><td><span class=\"day-meter\" style=\"--day-width:\(Double(duration) / 52 * 100)%\" aria-hidden=\"true\"></span></td><td>\(duration) <span>\(escaped(PackageSampleStrings.minutes))</span></td></tr>"
        }.joined(separator: "\n")
        return """
        <!doctype html>
        <html lang="\(sampleLanguage)">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="color-scheme" content="light dark">
          <title>\(escaped(PackageSampleStrings.detailsTitle))</title>
          <link rel="stylesheet" href="../assets/style.css">
        </head>
        <body>
          <main>
            <a class="package-back" href="../index.html"><span aria-hidden="true">‹</span> \(escaped(PackageSampleStrings.backToOverview))</a>
            <header class="document-header">
              <p class="eyebrow">\(escaped(PackageSampleStrings.detailsEyebrow))</p>
              <h1>\(escaped(PackageSampleStrings.detailsTitle))</h1>
              <p class="intro">\(escaped(PackageSampleStrings.detailsIntro))</p>
              <p class="dateline">\(escaped(AppStrings.SampleDesign.zipPeriod))</p>
            </header>
            <div class="detail-metrics">
              <section class="detail-metric panel"><h2>\(escaped(PackageSampleStrings.average))</h2><p><strong>35.3</strong> <span>\(escaped(PackageSampleStrings.minutes))</span></p></section>
              <section class="detail-metric panel"><h2>\(escaped(PackageSampleStrings.longest))</h2><p><strong>52</strong> <span>\(escaped(PackageSampleStrings.minutes))</span></p></section>
            </div>
            <section id="daily-rhythm" class="daily-rhythm">
              <h2 class="section-label">\(escaped(PackageSampleStrings.dailyHeading))</h2>
              <div class="daily-table panel"><table>
                <thead><tr><th scope="col">\(escaped(PackageSampleStrings.day))</th><th aria-label="\(escaped(AppStrings.SampleDesign.zipChartHeading))"></th><th scope="col">\(escaped(PackageSampleStrings.duration))</th></tr></thead>
                <tbody>\(rows)</tbody>
              </table></div>
            </section>
            <aside class="note"><h2>\(escaped(PackageSampleStrings.takeaway))</h2><p>\(escaped(PackageSampleStrings.takeawayBody))</p></aside>
            <figure class="reading-chart detail-chart panel">
              <figcaption>\(escaped(AppStrings.SampleDesign.zipChartHeading))</figcaption>
              <img src="../images/pixel.svg" width="560" height="180" alt="\(escaped(AppStrings.SampleDesign.zipChartAlt))">
              <p class="caption">\(escaped(AppStrings.SampleDesign.zipRhythm))</p>
            </figure>
            <nav class="package-contents" aria-label="\(escaped(PackageSampleStrings.continueReading))">
              <div class="package-links panel">\(zipPageLink(number: "03", title: PackageSampleStrings.notesTitle, subtitle: PackageSampleStrings.continueReading, href: "../appendix/notes.md"))</div>
            </nav>
            <footer><p>\(escaped(PackageSampleStrings.detailsFooter))</p><span>\(escaped(AppStrings.SampleDesign.sampleLabel)) · ZIP · 02 / 03</span></footer>
          </main>
        </body>
        </html>
        """
    }

    static var zipNotesMarkdown: String {
        """
        # \(PackageSampleStrings.notesTitle)

        [← \(PackageSampleStrings.backToOverview)](../index.html)

        \(PackageSampleStrings.notesIntro)

        > \(PackageSampleStrings.notesQuote)

        ## \(PackageSampleStrings.nextHeading)

        - \(PackageSampleStrings.nextOne)
        - \(PackageSampleStrings.nextTwo)
        - \(PackageSampleStrings.nextThree)

        ## \(PackageSampleStrings.methodHeading)

        \(PackageSampleStrings.methodIntro)

        $$
        \\bar{x} = \\frac{247}{7} \\approx 35.3
        $$

        ## \(PackageSampleStrings.codeHeading)

        ```swift
        let minutes = [18, 32, 24, 45, 36, 52, 40]
        let total = minutes.reduce(0, +)
        let average = Double(total) / Double(minutes.count)
        ```

        ---

        [\(PackageSampleStrings.viewDetails) →](../chapters/details.html#daily-rhythm)

        *\(AppStrings.SampleDesign.sampleLabel) · ZIP · 03 / 03*
        """
    }

    static func zipPageLink(number: String, title: String, subtitle: String, href: String) -> String {
        """
        <a class="package-page" href="\(escaped(href))"><span class="item-number" aria-hidden="true">\(number)</span><span class="page-copy"><strong>\(escaped(title))</strong><span>\(escaped(subtitle))</span></span><span class="page-chevron" aria-hidden="true">›</span></a>
        """
    }

    static let zipPagesCSS = """
    .package-contents { margin: 0 0 28px; }
    .package-links { padding: 0 18px; }
    .package-page { display: grid; grid-template-columns: 24px minmax(0, 1fr) 12px; gap: 12px; align-items: center; min-height: 78px; padding: 16px 0; color: var(--ink); text-decoration: none; -webkit-tap-highlight-color: transparent; }
    .package-page + .package-page { border-top: .5px solid var(--line); }
    .package-page .item-number { align-self: start; }
    .page-copy strong { display: block; font-size: .92rem; font-weight: 600; }
    .page-copy > span { display: block; margin-top: 4px; color: var(--secondary); font-size: .74rem; line-height: 1.45; }
    .page-chevron { color: var(--secondary); font-size: 1.45rem; font-weight: 300; }
    .package-page:active .page-copy strong { color: var(--accent); }
    .package-page:focus-visible, .package-back:focus-visible { outline: 2px solid var(--accent); outline-offset: 4px; border-radius: 8px; }
    .package-back { display: inline-flex; gap: 6px; align-items: center; margin: 0 0 26px; color: var(--accent); font-size: .8rem; text-decoration: none; }
    .package-back > span { font-size: 1.4rem; line-height: 1; }
    .detail-metrics { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; margin-bottom: 28px; }
    .detail-metric { padding: 18px; }
    .detail-metric h2 { color: var(--secondary); font-size: .72rem; font-weight: 500; }
    .detail-metric p { margin-top: 8px; }
    .detail-metric strong { color: var(--accent); font-size: 2rem; line-height: 1.2; letter-spacing: -.035em; font-variant-numeric: tabular-nums; }
    .detail-metric span { color: var(--secondary); font-size: .7rem; }
    .daily-table { padding: 6px 18px; }
    .daily-table table { border-collapse: collapse; width: 100%; table-layout: fixed; }
    .daily-table th, .daily-table td { padding: 11px 0; font-size: .8rem; text-align: left; font-variant-numeric: tabular-nums; }
    .daily-table thead th { color: var(--secondary); font-size: .65rem; font-weight: 500; }
    .daily-table th:first-child { width: 40px; }
    .daily-table th:last-child, .daily-table td:last-child { width: 84px; text-align: right; }
    .daily-table tbody tr + tr { border-top: .5px solid var(--line); }
    .daily-table tbody th { font-weight: 500; }
    .daily-table td > span:not(.day-meter) { color: var(--secondary); font-size: .65rem; }
    .day-meter { display: block; width: var(--day-width); height: 5px; border-radius: 4px; background: var(--accent); opacity: .7; }
    .detail-chart { margin-top: 28px; }
    .detail-chart + .package-contents { margin-top: 28px; margin-bottom: 0; }
    @media print { .package-page, .detail-metric, .daily-table tr { break-inside: avoid; } .package-back { margin-bottom: 18px; } }
    """
}
