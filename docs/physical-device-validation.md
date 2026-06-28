# Physical Device Validation

Issue: #1

This validation must run on a physical iPhone because simulator source-app behavior does not reliably represent Files, Mail, AirDrop, iCloud Drive, or messaging app "Open In" menus.

## Build

- Commit:
- Build source: local archive / TestFlight / Xcode run
- Device:
- iOS version:
- App version:

## Test Files

Use the files in `docs/usability-testing/samples/`:

- `basic-report.html`
- `markdown-notes.md`
- `zip-report.zip`
- `external-resource.html`
- `interactive-trusted.html`
- `broken.zip`

Also test extensions:

- `.html`
- `.htm`
- `.md`
- `.markdown`
- `.zip`

## Source Matrix

| Source | .html | .htm | .md | .markdown | .zip | Notes |
|---|---|---|---|---|---|---|
| Files local |  |  |  |  |  |  |
| iCloud Drive |  |  |  |  |  |  |
| Mail attachment |  |  |  |  |  |  |
| AirDrop |  |  |  |  |  |  |
| Messaging app |  |  |  |  |  |  |
| Safari download |  |  |  |  |  |  |

## Pass Criteria

- HTML Previewer appears as an available open/share target for each supported file type in the tested source apps.
- Opening a supported file imports it into the app sandbox and navigates to preview.
- ZIP packages open the selected entry file and load same-package CSS/images.
- Invalid ZIP produces the expected user-facing error.
- Recent files show the imported document and can reopen it.

## Result

- Overall status: pending / passed / failed
- Blocking failures:
- Caveats by source app:
- Follow-up issue links:
