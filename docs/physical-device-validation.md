# Physical Device Validation

Issue: #1

This validation must run on a physical iPhone because simulator source-app behavior does not reliably represent Files, Mail, AirDrop, iCloud Drive, or messaging app "Open In" menus.

## Build

- Commit:
- Build source: local archive / TestFlight / Xcode run
- Device:
- iOS version:
- App version:

Copy `docs/physical-device-validation-result-template.md` before each run and keep the completed result with the release evidence. Suggested path:
`docs/physical-device-validation-results/YYYY-MM-DD-device-build.md`.

To create a pre-filled validation run folder with the current commit, app
version, sample package, and device list snapshot, run:

```sh
scripts/prepare-physical-device-validation-run.sh --device <physical-iPhone>
```

This creates a draft result under `DerivedData/PhysicalDeviceValidationRun/`.
Complete the draft during the physical-device session, then keep it with the
release evidence or copy it into `docs/physical-device-validation-results/`.

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

The staged folder also includes `physical-device-validation-result-template.md` so the tester can keep notes beside the sample files.

If you distribute `HTMLPreviewerValidationSamples.zip` to a device, first expand it in Files. Use the individual files in the expanded folder for the source matrix. Do not use the outer distribution ZIP as the app's ZIP-import test file; use `zip-report.zip`.

To serve the samples from the Mac for physical-device Safari downloads, run:

```sh
scripts/serve-validation-samples.sh
```

Open the printed device URL on an iPhone on the same network, then download or share the individual sample files. Use those downloaded individual files for the Safari download row. This browser delivery helper is only for moving samples onto the device; it does not replace the source-app matrix.

Use this extension mapping for the source matrix:

| Extension | Primary sample |
|---|---|
| `.html` | `basic-report.html` |
| `.htm` | `legacy-report.htm` |
| `.md` | `markdown-notes.md` |
| `.markdown` | `markdown-reference.markdown` |
| `.zip` | `zip-report.zip` |

## Source Matrix

For release completion, the Files local row must be Pass for `.html`, `.htm`, `.md`, `.markdown`, and `.zip`. Use Not available only for source apps that are actually unavailable in the test setup, and record the caveat in Notes.

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
