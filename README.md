# HTML Previewer

Local-first iOS/iPadOS app for previewing HTML, Markdown, and zipped HTML report packages.

The product and implementation plan is in `ios-html-markdown-previewer-plan.md`.

## Current Status

MVP implementation is complete for the local core flow:

- Document type declarations for HTML, Markdown, and ZIP.
- App file picker import.
- Safe WKWebView preview with JavaScript disabled and external HTTP/HTTPS resources blocked by default.
- Native Markdown reading view for common Markdown.
- ZIP package import with local CSS/image resource loading.
- Recent files, details, raw text fallback, delete cleanup, and built-in samples.
- App icon, privacy manifest, App Store listing draft, and screenshot assets.

Remaining release gates are external to simulator-only local development:

- Physical-device open/share validation from Files, Mail, AirDrop, iCloud Drive, Safari downloads, and one messaging app. See `docs/physical-device-validation.md`.
- App Store Connect paid-download setup, privacy labels, upload, and final archive/TestFlight smoke test. See `docs/app-store-submission-runbook.md`.
- First usability test round with an external participant. See `docs/usability-testing/`.

## Build

```sh
xcodegen generate
xcodebuild test \
  -project HTMLMarkdownPreviewer.xcodeproj \
  -scheme HTMLMarkdownPreviewer \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath DerivedData
```

## Release Materials

- App Store listing draft: `docs/app-store-listing.md`
- Release checklist: `docs/release-checklist.md`
- Screenshot set: `docs/app-store-screenshots/`
- Privacy manifest: `HTMLMarkdownPreviewer/PrivacyInfo.xcprivacy`
- App icon: `HTMLMarkdownPreviewer/Assets.xcassets/AppIcon.appiconset/`
