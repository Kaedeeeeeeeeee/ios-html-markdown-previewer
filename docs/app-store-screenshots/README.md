# App Store Screenshots

These marketing screenshots were generated with:

```sh
scripts/capture-release-screenshots.sh
```

The command captures one English source set from the iPhone and iPad simulators,
then places those real screenshots in a deterministic marketing canvas. It
generates storefront-specific headlines for:

- `en-US`
- `zh-Hans`
- `ja`

Current output set:

- `en-US/iphone-01-home.png`
- `en-US/iphone-02-html-safe-preview.png`
- `en-US/iphone-03-markdown-preview.png`
- `en-US/iphone-04-zip-report-preview.png`
- `en-US/iphone-05-settings.png`
- `en-US/ipad-01-home.png`
- `en-US/ipad-02-html-safe-preview.png`
- `en-US/ipad-03-markdown-preview.png`
- `en-US/ipad-04-zip-report-preview.png`
- `en-US/ipad-05-settings.png`
- `zh-Hans/...`
- `ja/...`

The script also mirrors the final `en-US` marketing screenshots into the root
screenshot directory as `iphone-01-home.png`, `ipad-01-home.png`, and the other
legacy filenames used by release audits.

Captured dimensions:

- iPhone: 1320 x 2868
- iPad: 2064 x 2752

These dimensions match Apple's App Store Connect screenshot specifications for 6.9-inch iPhone portrait screenshots and 13-inch iPad portrait screenshots:
https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications

The source capture uses simulator launch arguments to reset the local library,
open built-in samples, and show Settings. Source screenshots are written to
`DerivedData/AppStoreScreenshotSources/en-US/`. Final contact sheets for visual
review are written to `DerivedData/AppStoreScreenshotPreviews/`.

Marketing copy lives in `copy.json`. The app UI inside every marketing image is
intentionally English; the headline and supporting line are localized for each
storefront.

Override `OUT_DIR`, `SOURCE_OUT_DIR`, `PREVIEW_OUT_DIR`, `COPY_FILE`,
`CAPTURE_LANGUAGE`, `CAPTURE_APPLE_LOCALE`, `IPHONE_DEVICE`, `IPAD_DEVICE`,
`IPHONE_RUNTIME_VERSION`, or `IPAD_RUNTIME_VERSION` when capturing on a
different simulator setup.

To regenerate the marketing canvases from an existing source set without
launching the simulators:

```sh
xcrun swift scripts/generate-app-store-screenshots.swift \
  --source-dir DerivedData/AppStoreScreenshotSources/en-US \
  --output-dir docs/app-store-screenshots \
  --copy-file docs/app-store-screenshots/copy.json \
  --preview-dir DerivedData/AppStoreScreenshotPreviews
```
