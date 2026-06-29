# HTML Previewer

Local-first iOS/iPadOS app for previewing HTML, Markdown, and zipped HTML report packages.

The product and implementation plan is in `ios-html-markdown-previewer-plan.md`.

## Current Status

MVP implementation is complete for the local core flow:

- Document type declarations for HTML, Markdown, and ZIP.
- Separate app file picker entries for HTML/Markdown files and ZIP report packages.
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

The signed archive helper validates App Store/TestFlight distribution signing by default. Use
`ALLOW_DEVELOPMENT_SIGNING=YES` only for local physical-device smoke builds.

Archive physical-device smoke helper:

```sh
scripts/run-archive-device-smoke.sh --device <device-id-or-name>
```

The helper records install, launch, and launch-screenshot artifacts under
`DerivedData/PhysicalDeviceSmoke/`.

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

Physical-device validation run draft:

```sh
scripts/prepare-physical-device-validation-run.sh --device <physical-iPhone>
```

Physical-device validation sample browser delivery:

```sh
scripts/serve-validation-samples.sh
```

First-round usability test packet:

```sh
scripts/prepare-usability-test-packet.sh
```

Final archive/TestFlight smoke run draft:

```sh
scripts/prepare-final-smoke-run.sh --device <physical-iPhone>
```

Final submission preflight:

```sh
scripts/final-submission-preflight.sh
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
- Distribution-signed Release archive helper: `scripts/create-signed-archive.sh`
- Archive physical-device smoke helper: `scripts/run-archive-device-smoke.sh`
- Final archive/TestFlight smoke run draft: `scripts/prepare-final-smoke-run.sh`
- Physical-device validation sample staging: `scripts/prepare-validation-samples.sh`
- Physical-device validation run draft: `scripts/prepare-physical-device-validation-run.sh`
- Physical-device validation browser delivery: `scripts/serve-validation-samples.sh`
- First-round usability test packet: `scripts/prepare-usability-test-packet.sh`
- Final submission preflight: `scripts/final-submission-preflight.sh`
- Screenshot set: `docs/app-store-screenshots/`
- Privacy manifest: `HTMLMarkdownPreviewer/PrivacyInfo.xcprivacy`
- App icon: `HTMLMarkdownPreviewer/Assets.xcassets/AppIcon.appiconset/`
