# Screenshot verification — 1.3

Verified on 2026-09-25. The three locale directories contain 30 final PNGs:
five iPhone and five iPad images each for `en-US`, `zh-Hans`, and `ja`.
The 10 root-level compatibility PNGs are byte-identical to their `en-US` copies.

## Native sources and dimensions

All 30 source images were newly captured from the native app, with the interface
and built-in content using the corresponding locale. Every launch used
`HTML_PREVIEWER_UI_TESTS=1`, so resets operated on the isolated test library and
preferences. No physical device or additional simulator was used.

| Existing simulator | Runtime | Native source | App Store canvas |
| --- | --- | --- | --- |
| iPhone 18 Pro | iOS 27.0 | 1206 × 2622 | 1320 × 2868 |
| iPad Air 11-inch (M3) | iOS 26.5 | 1640 × 2360 | 2064 × 2752 |

The compositor preserves the native screenshot's aspect ratio and fits the
complete device inside the marketing canvas. It adds the existing background,
localized copy, and frame; it does not redraw the interface. The canvas sizes
and five-image inventory are unchanged from the previous release.

The legacy `02-html-safe-preview` filename is retained for upload compatibility;
its current native image and caption correctly show Interactive mode.

## Build provenance

- Capture build: **1.3 (7)**, Debug, built with the iOS Simulator 27.0 SDK.
- Working tree based on `be080b30bc5a439daa538642dbb9c8a29f5c0100`, including the
  reading/paste features, animated sample, Interactive default and bottom actions.
- This capture build predates the subsequent WebKit compatibility bridge fix.
  At final screenshot verification, the only changed existing product files
  were `HTMLReadingController.swift`, `PDFExportService.swift` and the Xcode
  project. All captured view, sample, string-catalog and app-copy source hashes
  still matched. The bridge fix does not change the photographed interface.
- Screenshot evidence is separate from final release-binary compatibility and
  App Store upload verification. It does not claim to test that later binary.

## Visual review

All six locale/device contact sheets were reviewed, with native HTML and Settings
sources checked directly where needed. The current set shows:

- Paste to Preview on Home.
- The localized animated weekend illustration in Interactive mode.
- The bottom-right action capsule in HTML, Markdown and ZIP previews.
- Markdown headings and tables, and the ZIP report's local chart.
- Interactive as the default in Settings, with the Safe Preview distinctions.

Marketing captions fit their canvases. All device frames and bottom controls
remain inside the final images. No loading screen, wrong-language sample,
missing chart or accidental app transition was found. Native scroll boundaries
and the iPad Settings sheet are retained. The Japanese iPhone Home empty-state
title uses the system's native ellipsis at this source device width; it was not
replaced or patched in the image.

## Validation and local evidence

- 30 native sources and 30 outputs checked for expected inventory and dimensions.
- 10 English compatibility copies checked byte-for-byte.
- SHA-256 manifest: `DerivedData/Release1.3/screenshot-verification.json`.
- Native sources: `DerivedData/Release1.3/ScreenshotSources/<locale>/`.
- Six contact sheets: `DerivedData/Release1.3/ScreenshotPreviews/`.
- Build metadata and source hashes:
  `DerivedData/Release1.3/screenshot-build-provenance.json`.
- Post-capture source comparison:
  `DerivedData/Release1.3/screenshot-final-source-comparison.json`.
- Capture log: `DerivedData/Release1.3/screenshot-capture.log`.
- Capture script exited successfully; Swift compositor parsing, full generation,
  shell syntax and `git diff --check` passed.

No screenshots were uploaded or committed during this capture task. Both
simulators were released for the remaining release tests after capture.
