# App Store Screenshots

These marketing screenshots are generated with:

```sh
scripts/capture-release-screenshots.sh
```

The command captures a separate, genuinely localized source set for each of
`en-US`, `zh-Hans`, and `ja`, on both iPhone and iPad simulators. It then places
those real app screenshots in a deterministic marketing canvas with matching
localized headlines. The interface itself is never redrawn.

Each locale contains five iPhone and five iPad images:

1. `01-home` — opening files and choosing a built-in example.
2. `02-html-safe-preview` — the animated weekend plan in Interactive mode.
   The legacy filename is retained for upload compatibility.
3. `03-markdown-preview` — the redesigned reading notes, including a table.
4. `04-zip-report-preview` — the redesigned reading journal and local chart.
5. `05-settings` — native preview, storage, and privacy settings.

Filenames use the `iphone-` or `ipad-` prefix, for example
`zh-Hans/iphone-02-html-safe-preview.png`.

The final `en-US` screenshots are also mirrored byte-for-byte into this directory
under the legacy root filenames used by release audits.

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

Sources are written to `DerivedData/AppStoreScreenshotSources/<locale>/`.
Screenshots use dark appearance and a fixed 09:41 status bar. Contact sheets are
written to `DerivedData/AppStoreScreenshotPreviews/`. Review the sources and
contact sheets for the correct language, rendered sample, and absence of loading
or transition screens before uploading.

Marketing copy lives in `copy.json`. The 1.3 set shows the paste entry, animated weekend plan, reading notes,
reading journal, bottom-right preview actions, and current Interactive default.
The HTML and Settings captions describe the available preview modes.

Override `OUT_DIR`, `SOURCE_OUT_DIR` (the parent of the three locale directories),
`PREVIEW_OUT_DIR`, `COPY_FILE`, `DERIVED_DATA`, `IPHONE_DEVICE`, `IPAD_DEVICE`,
`IPHONE_RUNTIME_VERSION`, or `IPAD_RUNTIME_VERSION` to use another simulator
setup. `CAPTURE_LOCALES` can restrict recapture to a space-separated subset; all
three source sets must exist before composition.

The 1.3 capture uses the retained iPhone 18 Pro on iOS 27.0 and iPad Air 11-inch
(M3) on iOS 26.5. Pass their device IDs with `IPHONE_DEVICE` and `IPAD_DEVICE`.
The compositor accepts native portrait screenshots and preserves their aspect
ratio while fitting the entire device into the fixed marketing canvas. The
App Store canvas sizes above are independent of the source simulator resolution.
The completed set and its build provenance are recorded in
[`verification-1.3.md`](verification-1.3.md). Previous capture evidence remains in
[`verification-1.2.md`](verification-1.2.md).

To regenerate the marketing canvases from existing localized sources:

```sh
xcrun swift scripts/generate-app-store-screenshots.swift \
  --source-dir DerivedData/AppStoreScreenshotSources \
  --output-dir docs/app-store-screenshots \
  --copy-file docs/app-store-screenshots/copy.json \
  --preview-dir DerivedData/AppStoreScreenshotPreviews
```

Add `--locales en-US` (or a comma-separated subset) to compose one completed
locale while another locale is still being captured.
