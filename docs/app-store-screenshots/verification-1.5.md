# Screenshot verification — 1.5

Captured and visually verified on 2026-09-30 (Asia/Tokyo).

The store set contains five iPhone and five iPad images for each of `en-US`,
`zh-Hans`, and `ja`. All six contact sheets were reviewed. The 10 root-level
compatibility PNGs are byte-identical to the English copies.

## Capture provenance

The 12 Markdown and ZIP images (`03` and `04`) are fresh native captures of
**1.5 (10)**. The app source is commit
`dfea35dfbb45d4aaeb7c9b1c65e13e29aba71559` plus the release version/build changes.
The capture build used Debug and an isolated UI-test library through
`HTML_PREVIEWER_UI_TESTS=1`. No production Swift source changed during capture.

The remaining 18 home, HTML, and Settings sources are retained from the
1.4 captures documented in `verification-1.4.md`. Those screens are unchanged;
their provenance remains 1.4 (8). All 30 canvases were regenerated using the
existing compositor, with localized Markdown and ZIP feature captions updated.

| Simulator | Runtime | Native capture | Store canvas |
| --- | --- | --- | --- |
| iPhone 18 Pro | iOS 27.0 | 1206 × 2622 | 1320 × 2868 |
| iPad Pro 12.9-inch (6th generation) | iOS 18.5 | 2048 × 2732 | 2064 × 2752 |

## Visual checks

- Markdown shows syntax-colored code, the copy action, and rendered inline and
  display mathematics. The iPad viewport also contains the complete Mermaid
  flowchart; the iPhone viewport ends near the diagram section heading.
- The iPhone ZIP image shows the package navigation bar, the three-page count,
  and links to the HTML detail and Markdown appendix pages.
- The iPad ZIP image shows the page picker with all three entries and its search
  field. Each locale uses localized UI and sample content.
- Captions and device frames fit the canvases. No blank/loading content,
  wrong-language sample, or screenshot transition remains.
- New iPhone captures use dark appearance; new iPad captures use light
  appearance. Original appearance settings were preserved.

## Local evidence and restoration

Evidence is in `/Users/user/html_preview/DerivedData/Release1.5/`:

- `ScreenshotSources/`: all 30 native sources, including retained images.
- `ScreenshotPreviews/`: six reviewed contact sheets.
- `screenshot-verification.json`: image dimensions and SHA-256 hashes.
- `screenshot-build-provenance.json`: capture build metadata and source hashes.

Only simulators `F56A2968-F35C-4455-8A34-43DCC6CDC319` and
`9216FE52-CA0E-4113-8ED5-19B4BF9755CE` were used. Status-bar overrides were
cleared and both simulators returned to their original shutdown state. No
physical device was used for these captures. Capture evidence is separate from
Release archive validation, App Store upload processing, and review status.
