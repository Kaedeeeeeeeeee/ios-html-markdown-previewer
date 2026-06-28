# Physical Device Validation Result Template

Copy this template for each physical-device validation run. Suggested path:
`docs/physical-device-validation-results/YYYY-MM-DD-device-build.md`.

Issue: #1

## Run Metadata

- Date:
- Tester:
- Commit:
- Build source: Xcode run / local archive / TestFlight
- App version:
- Device:
- iOS version:
- Region/language:
- Network state: Wi-Fi / cellular / offline

## Source Apps Tested

| Source | App/version | Account state | Notes |
|---|---|---|---|
| Files local |  |  |  |
| iCloud Drive |  |  |  |
| Mail attachment |  |  |  |
| AirDrop |  |  |  |
| Messaging app |  |  |  |
| Safari download |  |  |  |

## External Open Matrix

Use:

- `basic-report.html` for `.html`
- `legacy-report.htm` for `.htm`
- `markdown-notes.md` for `.md`
- `markdown-reference.markdown` for `.markdown`
- `zip-report.zip` for `.zip`

Mark each cell as Pass, Fail, Not available, or Not tested. Include exact source-app wording if HTML Previewer appears under a different menu label.

| Source | .html | .htm | .md | .markdown | .zip | Notes |
|---|---|---|---|---|---|---|
| Files local |  |  |  |  |  |  |
| iCloud Drive |  |  |  |  |  |  |
| Mail attachment |  |  |  |  |  |  |
| AirDrop |  |  |  |  |  |  |
| Messaging app |  |  |  |  |  |  |
| Safari download |  |  |  |  |  |  |

## Import And Preview Checks

Run these checks for at least one successful import per document type.

| Check | Pass/Fail | Evidence/notes |
|---|---|---|
| App appears as an open/share target |  |  |
| File imports into app sandbox |  |  |
| App navigates to preview after import |  |  |
| HTML Safe Preview renders local content |  |  |
| Markdown renders formatted content |  |  |
| ZIP opens the selected entry HTML |  |  |
| ZIP loads same-package CSS/images |  |  |
| Recent list shows imported file |  |  |
| Recent item reopens successfully |  |  |
| Delete removes recent item and imported data |  |  |

## Safety And Error Path Checks

| Sample | Expected result | Pass/Fail | Notes |
|---|---|---|---|
| `external-resource.html` | Safe Preview blocks remote http/https resources by default |  |  |
| `interactive-trusted.html` | Safe Preview disables JavaScript; Interactive mode works only after user switches |  |  |
| `broken.zip` | App shows a clear invalid ZIP error and leaves no broken recent item |  |  |

## Source-Specific Caveats

Record any source-specific behavior that should be documented in App Review notes, support docs, or follow-up issues.

| Source | Caveat | User impact | Follow-up |
|---|---|---|---|
|  |  |  |  |

## Blocking Failures

| Priority | Failure | Source/file | Reproduction steps | Follow-up issue |
|---|---|---|---|---|
| P0/P1/P2 |  |  |  |  |

Priority guide:

- P0: Blocks opening or previewing supported files from common source apps.
- P1: Supported flow works only through confusing or fragile steps that need product/docs changes.
- P2: Source-specific polish or documentation gap that does not block submission.

## Result

- Overall status: pending / passed / failed
- Can close #1: yes / no
- Can continue App Store submission: yes / no
- Follow-up issues:

## Issue Comment Draft

```text
Physical-device validation result:

- Commit:
- Build source:
- Device/iOS:
- Sources tested:
- Overall status:

Passed:
- 

Caveats:
- 

Blocking failures:
- 

Follow-ups:
- 
```
