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
- `legacy-report.htm`
- `markdown-notes.md`
- `markdown-reference.markdown`
- `zip-report.zip`
- `external-resource.html`
- `interactive-trusted.html`
- `broken.zip`

To stage only the files needed for device testing, run:

```sh
scripts/prepare-validation-samples.sh
```

This creates:

- `DerivedData/ValidationSamples/HTMLPreviewerValidationSamples/`
- `DerivedData/ValidationSamples/HTMLPreviewerValidationSamples.zip`

If you distribute `HTMLPreviewerValidationSamples.zip` to a device, first expand it in Files. Use the individual files in the expanded folder for the source matrix. Do not use the outer distribution ZIP as the app's ZIP-import test file; use `zip-report.zip`.

Use this extension mapping for the source matrix:

| Extension | Primary sample |
|---|---|
| `.html` | `basic-report.html` |
| `.htm` | `legacy-report.htm` |
| `.md` | `markdown-notes.md` |
| `.markdown` | `markdown-reference.markdown` |
| `.zip` | `zip-report.zip` |

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
