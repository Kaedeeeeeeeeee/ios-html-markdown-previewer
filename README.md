# iOS HTML / Markdown Previewer

Local-first iOS/iPadOS app for previewing HTML, Markdown, and zipped HTML report packages.

The current planning document is in `ios-html-markdown-previewer-plan.md`.

## Current Status

M0 technical validation is in progress. The initial SwiftUI/Xcode project validates:

- document type declarations for HTML, Markdown, and ZIP
- safe WKWebView configuration with external HTTP/HTTPS resource blocking
- ZIP import and local HTML package resource loading

See `docs/m0-validation-report.md` for the latest validation notes.

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
