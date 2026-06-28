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

Release device build preflight:

```sh
scripts/release-device-build.sh
```

Archive preflight:

```sh
scripts/archive-preflight.sh
```

Signed archive creation:

```sh
DEVELOPMENT_TEAM=<Apple Team ID> scripts/create-signed-archive.sh
```

Public App Store page verification:

```sh
scripts/verify-public-pages.sh
```

Release packet staging:

```sh
scripts/prepare-release-packet.sh
```

Physical-device validation sample staging:

```sh
scripts/prepare-validation-samples.sh
```

Physical-device validation sample browser delivery:

```sh
scripts/serve-validation-samples.sh
```

## Release Materials

- App Store listing draft: `docs/app-store-listing.md`
- App Store Connect handoff: `docs/app-store-connect-handoff.md`
- Release checklist: `docs/release-checklist.md`
- Final archive/TestFlight smoke template: `docs/final-archive-smoke-test-template.md`
- Release packet staging: `scripts/prepare-release-packet.sh`
- Local release audit: `scripts/release-audit.sh`
- Public App Store page verification: `scripts/verify-public-pages.sh`
- Generic iOS Release build preflight: `scripts/release-device-build.sh`
- Generic iOS archive preflight: `scripts/archive-preflight.sh`
- Signed Release archive helper: `scripts/create-signed-archive.sh`
- Physical-device validation sample staging: `scripts/prepare-validation-samples.sh`
- Physical-device validation browser delivery: `scripts/serve-validation-samples.sh`
- Screenshot set: `docs/app-store-screenshots/`
- Privacy manifest: `HTMLMarkdownPreviewer/PrivacyInfo.xcprivacy`
- App icon: `HTMLMarkdownPreviewer/Assets.xcassets/AppIcon.appiconset/`
