# App Store Screenshots

These marketing screenshots are generated with:

```sh
scripts/capture-release-screenshots.sh
```

The command captures a separate, genuinely localized source set for each of
`en-US`, `zh-Hans`, and `ja`, on both iPhone and iPad simulators. It then places
those real app screenshots in a deterministic marketing canvas with matching
localized headlines. The interface itself is never redrawn.

Each locale contains six iPhone and six iPad images:

1. `01-html-report` — a locally processed HTML report.
2. `02-batch-import` — multi-file import counts and any failure reasons.
3. `03-json-preview` — read-only JSON structure and source controls.
4. `04-markdown-preview` — Markdown reading notes, tables, and code.
5. `05-library` — filename search, pinned files, and reopening documents.
6. `06-yaml-preview` — collapsible YAML configuration structure and source controls.

Filenames use the `iphone-` or `ipad-` prefix, for example
`zh-Hans/iphone-03-json-preview.png`. Each locale contains 12 images; the
three localized sets total 36 images. The final `en-US` set is also mirrored
byte-for-byte into this directory under the same filenames for release audits.

JSON is read-only standard JSON, without JSONC or PDF export. Batch import
processes duplicate-file decisions individually and reports imported, skipped,
and failed files. Library search means filename search, not cross-file full-text
search. Captions must reflect these implemented boundaries.

## Dimensions

- iPhone 6.9-inch portrait: **1320 × 2868**.
- iPad 13-inch portrait: **2064 × 2752**.

Both sizes were verified against [Apple's screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
on 2026-09-21 and match the repository's release audits.

## Capture isolation and output

The capture script builds Debug into `DerivedData/ScreenshotCapture/` and
passes `HTML_PREVIEWER_UI_TESTS=1` through `SIMCTL_CHILD_` on every launch. The
sample/reset arguments therefore operate on the isolated UI-test library and
preferences, preserving the normal app library. Only simulators are used.

The 1.7 source captures and contact sheets are stored under
`DerivedData/Release1.7/ScreenshotSources/<locale>/` and
`DerivedData/Release1.7/ScreenshotPreviews/`. Review the current sources and
contact sheets for language, rendered content, and absence of loading or
transition screens before uploading. Historical 1.2–1.4 folders and verification
reports describe their respective releases and are not current 1.7 evidence.

Marketing copy lives in `copy.json`. The 1.7 set follows the six-image order
above and uses actual localized app UI. Keep capture/build provenance with the
1.7 release evidence; generating promotional canvases does not establish an
App Store upload or release.

Override `OUT_DIR`, `SOURCE_OUT_DIR` (the parent of the three locale directories),
`PREVIEW_OUT_DIR`, `COPY_FILE`, `DERIVED_DATA`, `IPHONE_DEVICE`, `IPAD_DEVICE`,
`IPHONE_RUNTIME_VERSION`, or `IPAD_RUNTIME_VERSION` to use another simulator
setup. `CAPTURE_LOCALES` can restrict recapture to a space-separated subset; all
three source sets must exist before composition.

Pass explicit existing simulator device IDs with `IPHONE_DEVICE` and
`IPAD_DEVICE`. The compositor preserves native portrait screenshot aspect ratio
within the fixed marketing canvas. Canvas dimensions are independent of the
source simulator resolution. Previous release evidence remains in
[`verification-1.4.md`](verification-1.4.md),
[`verification-1.3.md`](verification-1.3.md), and
[`verification-1.2.md`](verification-1.2.md).

To regenerate the marketing canvases from existing localized sources:

```sh
xcrun swift scripts/generate-app-store-screenshots.swift \
  --source-dir /Users/user/html_preview/DerivedData/Release1.7/ScreenshotSources \
  --output-dir docs/app-store-screenshots \
  --copy-file docs/app-store-screenshots/copy.json \
  --preview-dir /Users/user/html_preview/DerivedData/Release1.7/ScreenshotPreviews
```

Add `--locales en-US` (or a comma-separated subset) to compose one completed
locale while another locale is still being captured.
