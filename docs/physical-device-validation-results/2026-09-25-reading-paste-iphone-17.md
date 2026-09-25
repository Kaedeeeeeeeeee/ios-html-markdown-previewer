# Reading and paste preview: iPhone 17 validation

Date: 2026-09-25. Result: **14 UI tests passed, 0 failed, 0 skipped**.

## Build and merge

- `codex/reading-paste-preview` was fast-forward merged into local `main` at `1cfd7c3`.
- A fresh development-signed Debug build was built and installed on the user's physical iPhone 17, running iOS 27.0 (24A437).
- App identifier: `com.kaede.htmlmarkdownpreviewer`. Version remains 1.2 (6); this is a local development build, not an App Store release.
- Product source remained unchanged during this device session. Follow-up changes adapt the UI test harness to physical-device clipboard access and system localization.

## Verified behavior

| Coverage | Result |
| --- | --- |
| Paste HTML, switch search results, navigate headings, restore reading position after app relaunch | Pass |
| Safe HTML preview continues to block document scripts | Pass |
| Paste Markdown, switch search results, navigate headings, restore reading position after app relaunch | Pass |
| Reveal matches near the end of a long paragraph and in an offscreen table column | Pass |
| Reject empty and URL-only input; cancel without creating a document | Pass |
| No-match state and closing search | Pass |
| Simplified Chinese, Traditional Chinese, and Japanese paste/outline controls; English core flows | Pass |
| Built-in samples, settings, Chinese Markdown headings, recent-file ordering and disclosure persistence | Pass |
| Original-file sharing and complete ZIP package sharing, including the ZIP filename in Save to Files | Pass |
| HTML, Markdown, and ZIP PDF export; repeated HTML PDF export | Pass |

The final complete run contains six reading/paste tests and eight existing smoke tests. Its result bundle identifies the destination as a physical iPhone 17 on platform `iOS`, not a simulator.

## Test-harness corrections

The first device run passed 3/14 tests. Four paste tests could not prepare their clipboard fixtures because iOS denied clipboard access from the background test runner; seven existing smoke tests assumed English while the device used Japanese.

- On physical devices, the runner now activates itself, writes and verifies only its own local clipboard fixture, then reactivates the app. Both paste paths wait for the system PasteButton to become enabled before tapping it.
- Smoke tests explicitly request English unless a test specifies another language. Native share-sheet labels also accept Japanese and Simplified/Traditional Chinese.
- No product hooks were added and the preview/search/share assertions were retained. A focused clipboard check passed, followed by the complete 14/14 run.

## Data isolation and handoff

All UI tests use `HTML_PREVIEWER_UI_TESTS=1`, the separate `UITestLibrary`, and separate test preferences. Library resets apply to that test store. The app was not uninstalled.

After testing, the app was launched without test arguments or environment overrides. A device screenshot confirms the normal Japanese home screen, the new paste-preview entry, and the user's existing recent files. Screenshot inspection also confirmed the Chinese paste form, restored HTML position, and visible highlighted match in the last table column.

## Local evidence

Paths are relative to the repository root and are ignored build artifacts:

- `DerivedData/ReadingPasteDeviceQA/iphone-ui-final.xcresult`: final 14/14 result.
- `DerivedData/ReadingPasteDeviceQA/iphone-ui-summary.json`: parsed XCTest summary.
- `DerivedData/ReadingPasteDeviceQA/build-metadata.json`: source commit and installed build metadata.
- `DerivedData/ReadingPasteDeviceQA/screenshots/manifest.json`: 24 exported screenshot attachments.
- `DerivedData/ReadingPasteDeviceQA/normal-home.png`: normal app launch after tests.
- `DerivedData/ReadingPasteDeviceQA/normal-launch.json`: successful normal launch.

The final run used the `HTMLMarkdownPreviewer` scheme, Debug configuration, the physical device destination, `-only-testing:HTMLMarkdownPreviewerUITests`, and `-parallel-testing-enabled NO`. The complete simulator unit/integration evidence remains in [the original report](../reading-paste-verification.md).

No Git push, TestFlight upload, or App Store submission was performed in this session. The external source-app import matrix (Mail, AirDrop, and messaging apps) was outside this reading/paste regression run.
