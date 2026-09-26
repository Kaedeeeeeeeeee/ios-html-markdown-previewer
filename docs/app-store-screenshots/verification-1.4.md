# Screenshot verification — 1.4

Captured on 2026-09-26–27 and verified on 2026-09-27 (Asia/Tokyo).
The three locale directories contain 30 refreshed PNGs: five iPhone and five
iPad images each for `en-US`, `zh-Hans`, and `ja`. The 10 root-level compatibility
PNGs are byte-identical to their `en-US` copies.

## Native sources and dimensions

Every source is a fresh native capture of version **1.4 (8)**. The interface and
built-in sample content use the corresponding app locale. Every launch used
`HTML_PREVIEWER_UI_TESTS=1`, isolating the screenshot library and preferences
from the normal app library. HTML zoom and Markdown font size were at 100%,
with default Markdown spacing. No physical device was used.

| Existing simulator | Runtime | Native source | App Store canvas |
| --- | --- | --- | --- |
| iPhone 18 Pro | iOS 27.0 | 1206 × 2622 | 1320 × 2868 |
| iPad Pro 12.9-inch (6th generation) | iOS 18.5 | 2048 × 2732 | 2064 × 2752 |

Only simulators `F56A2968-F35C-4455-8A34-43DCC6CDC319` and
`9216FE52-CA0E-4113-8ED5-19B4BF9755CE` were operated by this capture task.
The compositor preserves native aspect ratios and fits each complete device
inside the existing marketing canvas. The localized copy, filenames, five-image
inventory, and output dimensions are unchanged. The legacy
`02-html-safe-preview` filename still depicts and describes Interactive mode.

## Build provenance

- Debug capture build: **1.4 (8)**, iOS Simulator 27.0 SDK, minimum iOS 17.0.
- Capture build source commit: `7b669539b58f5b28eec39f1b045fe1a8a1a69107`.
- Reused `DerivedData/ReadingLibraryQA`; no new simulator was created.
- Product, sample, localization, project, capture script, compositor, and copy
  hashes were recorded before capture. All rendered sources matched at final
  verification; the only difference was `PrivacyInfo.xcprivacy`, which gained
  the UserDefaults reason `CA92.1` during release preparation. The release owner
  confirmed this nonvisual declaration is included in the signed/uploaded binary
  and does not require recapture.
- The screenshot task did not edit production Swift files, tests, or marketing
  copy. Screenshot evidence is separate from optimized Release testing and
  App Store binary upload or review status.

## Visual review

All six locale/device contact sheets were reviewed, with native sources checked
for rendered content and localization. The set shows the current file search
and paste entry, localized HTML illustration in Interactive mode, Markdown
headings and tables, ZIP chart, bottom-right actions, and preview-mode settings.

Marketing headings and captions fit their canvases. Device frames and controls
remain inside the composed images. No blank content, missing illustration or
chart, loading view, wrong-language sample, or accidental app transition remains
in the final set. Native scrolling boundaries and the iPad Settings sheet are
retained. The Japanese iPhone Home empty-state title uses a native ellipsis at
this device width, as in 1.3; the image was not patched or redrawn.

## Capture recovery and device restoration

Several `simctl launch` calls stalled and were bounded or stopped before retry.
Capture resumed using the repository's original capture functions, with a local
wrapper that removed the redundant launch termination flag after explicit
termination. Only one capture simulator remained active at a time. The repository
capture script and compositor were not changed.

The first Japanese iPhone HTML and ZIP captures had blank content after the
standard 20-second wait. Those frames were retained separately as failed evidence.
After an iPhone-only restart, fresh launches with a 45-second wait produced the
complete native illustration and chart; those replacement frames were reviewed
before entering the final source set. The initial failure's cause was not
established. No blank frame was accepted as release artwork.

The iPhone was restored to its original dark appearance and the iPad to light.
Both had no original status-bar overrides; all capture overrides were cleared.
Both capture simulators were shut down after capture. Other simulators were not
operated by this task.

## Validation and local evidence

Evidence is under `/Users/user/html_preview/DerivedData/Release1.4/`:

- `screenshot-verification.json`: inventory, dimensions, and SHA-256 hashes for
  30 sources, 30 localized outputs, 10 compatibility copies, and six contact sheets.
- `ScreenshotSources/<locale>/`: complete native sources.
- `ScreenshotPreviews/`: six reviewed contact sheets.
- `screenshot-build-provenance.json`: built-app version and source hashes.
- `screenshot-final-source-comparison.json`: final source hash comparison.
- `screenshot-device-state-before.json` and `screenshot-device-state-after.json`:
  device state evidence.
- `screenshot-build.log` and `screenshot-capture.log`: build, capture, and recovery logs.
- `FailedCaptures/` and `CaptureCandidates/`: excluded early frames and the
  reviewed Japanese iPhone replacement sources.

The build, completed capture sequence, full composition, dimension/hash audit,
shell syntax check, and `git diff --check` passed. This capture task did not
upload screenshots, commit changes, or push Git branches.

## Build9 library refinement

Build9 replaces the file-type card with a compact menu beside the Recent Items heading. The existing store home captures depict the empty library, where neither the old card nor the new menu is displayed. The other four captured screens per device/locale are unchanged. The30 captured images therefore still represent the released screens; their provenance remains build8 rather than being relabeled as new captures. The populated-library header and menu are covered separately by build9 simulator QA.
