# Screenshot verification — 1.2

Verified on 2026-09-21. The three locale directories contain 30 final PNGs:
five iPhone and five iPad images each for `en-US`, `zh-Hans`, and `ja`.
The 10 root-level compatibility PNGs are byte-identical to their `en-US` copies.

## Source and dimensions

All 30 source images were captured from the native app on simulators, using
the actual locale for both the interface and built-in sample content. Every
launch set `HTML_PREVIEWER_UI_TESTS=1`, keeping resets within the isolated test
library and preferences. No physical device was used for this capture set.

| Simulator | Runtime | PNG dimensions |
| --- | --- | --- |
| iPhone 18 Pro Max | iOS 27.0 | 1320 × 2868 |
| iPad Pro 13-inch (M5) | iOS 27.0 | 2064 × 2752 |

Both the source and final PNG dimensions were checked. The final sizes match
[Apple's screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).
The compositor only adds the marketing background, text, and device frame; it
does not redraw the app interface.

## Build provenance

- All six `03-markdown-preview` source images were recaptured with **1.2 (6)**,
  after the Markdown view identity fix in `cbfcad4`.
- The other 24 source images were captured with **1.2 (5)** from `a848b40`.
  Their product views and sample content did not change in `cbfcad4`.
- All 30 marketing images and the 10 English compatibility copies were then
  recomposed from that final source set.

## Visual review

Reviewed all six locale/device contact sheets and the native sources where
needed. Each sample image shows the new localized example, with no loading
screen, unintended home screen, missing chart, or layout overlap. Long documents
continue naturally below the visible viewport.

All six build 6 Markdown sources were checked directly. In particular, both
Chinese headings `留下来的想法` and `读下一章之前` are visible on iPhone and iPad.
The reading table and following section are present in all three languages.

The Settings screenshot retains the real native sheet and scroll position:
some lower rows are below the viewport, and the iPad privacy section is below
the initial sheet fold. No interface content was patched into the image.

Supplemental OCR matched 19 of 30 expected primary headings automatically.
The remaining 11 were checked visually because OCR misread CJK characters or
small text in the iPad Settings sheet; the OCR result is not a rendering failure.

## Local evidence

- Native sources: `DerivedData/AppStoreScreenshotSources/<locale>/`.
- Six contact sheets: `DerivedData/AppStoreScreenshotPreviews/`.
- Dimensions and SHA-256 hashes for all sources/outputs, including the English
  compatibility equality checks:
  `DerivedData/AppStoreScreenshotVerification/final-manifest.json`.
- Supplemental OCR text:
  `DerivedData/AppStoreScreenshotVerification/source-ocr-en-US,zh-Hans,ja.json`.
- Build 6 Markdown capture log:
  `DerivedData/AppStoreScreenshotVerification/capture-markdown-build6.log`.

The capture shell script passed `bash -n`; the compositor passed Swift parsing
and successfully generated the complete final set. These checks cover local
artifacts; App Store upload and submission are verified separately.
