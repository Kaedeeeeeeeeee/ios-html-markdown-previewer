# Sharing and reading update — 2026-09-21

Implemented locally; this document does not indicate an App Store release.

## Changes

- The preview share menu offers the original file and PDF export. ZIP sharing uses the original complete archive, preserving resources.
- Rendered HTML and Markdown export to paginated A4 PDFs. HTML prints the current loaded document, including interactive DOM changes and local assets, and preserves background colors using a temporary print-only rule. Markdown uses the same parsed content model, with self-contained images and blocked remote resources.
- Markdown GFM tables retain header cells, alignment, inline formatting, and empty cells. Wide tables scroll horizontally, with Dynamic Type support and column-aware accessibility labels.
- Recent files appear before samples. Samples remain visible for an empty library and become a collapsible section for returning users; the expansion preference persists.
- New controls, errors, and sample table content are translated into English, Japanese, Simplified Chinese, and Traditional Chinese.

## PDF behavior

Use Share → Export PDF after rendered preview is ready. Raw Text mode offers original sharing only. PDFs contain static content and respect the HTML document's print styles; interactive controls and animations do not remain interactive. Temporary PDFs are removed when sharing completes or is cancelled. Source documents are not changed.

## Validation

- iPhone 18 Pro simulator, iOS 27: final run passed all 48 unit/integration tests plus the HTML export/repeated-export UI test (49/49). Earlier UI runs and corrected targeted reruns passed all 7 distinct UI scenarios.
- iPad Pro 12.9 simulator, iPadOS 18.5: 7 UI scenarios and 4 PDF/share integration tests passed initially. After the print-color fix, all 5 PDF/share integration tests and all 3 PDF export UI scenarios passed again (8/8).
- PDF assertions cover real pagination, final-page text, current DOM, local-image pixels, dark-background pixels, and unchanged preview DOM/colors/scroll position after export.
- ZIP recipient roundtrip verifies the complete original archive, CSS, and image bytes.
- UI assertions cover original sharing, ZIP filename in Save to Files, all three PDF input types, repeated export after sharing, sample access, settings, home order, and persisted sample expansion.
- Visually inspected Chinese iPhone home/table screens, iPad table/share screens, and actual generated PDFs.
- All 15 new localization keys have English, Japanese, Simplified Chinese, and Traditional Chinese values. `git diff --check` passed.
- Physical-device follow-up is recorded below. No App Store submission was performed.

## Physical-device follow-up

- Installed development build 1.1 (4) on the user's connected iPhone 17 running iOS 27.0, updating the existing 1.0 (2) app in place.
- Backed up the original library before installation and compared the original Imports directory after testing: byte-for-byte unchanged.
- DEBUG UI tests now use a separate `UITestLibrary` and a separate preferences suite. Normal launches continue to use the user's original library and preferences.
- All 48 unit/integration tests passed on the physical phone. Two earlier Markdown image tests needed real PNG fixtures: nonexistent fixture paths standardize differently on a physical device. Existing in-root images and existing out-of-root rejection are now both exercised.
- All 7 distinct UI scenarios passed on the native phone screen: sample/settings access, HTML export and repeated export after dismissal, Markdown PDF export, original HTML sharing, ZIP PDF export, persisted home section ordering/collapse, and the original ZIP filename in Save to Files. The last scenario passed in a targeted rerun after correcting the system-language selector.
- iPhone Mirroring hid the system sharing controls from XCTest. Native-screen retesting after exiting Mirroring verified these controls. The system Save to Files action retained Japanese even with the app set to English; the test now recognizes that device-language label.
- Retrieved and inspected actual phone-generated HTML, Markdown and ZIP-report PDFs. Content, graphs, tables and footers are complete. The HTML/ZIP samples' decorative gradients have a visible WebKit print rendering difference (hard-edged color area/darker base), so PDF export should not be described as pixel-identical to screen rendering.
- Removed the temporary XCTest runner app and relaunched the installed app normally. Original library files remained byte-for-byte unchanged in the final comparison.

Physical-device evidence is under `DerivedData/PhysicalDeviceQA/`: exported PDFs and rendered first-page PNGs, `pdf-validation.json`, screenshots, library comparisons, and these result bundles:

- `ShareDiagnostics.xcresult`: 48/48 unit/integration tests passed; its sharing UI probe failed while Mirroring was active.
- `NativeUITests.xcresult`: 6/7 native-screen UI scenarios passed, including system sharing screenshots; Save to Files needed the Japanese system-language selector below.
- `HomeTests.xcresult`: persisted home ordering/collapse passed.
- `ZIPSharingFinalTests.xcresult`: ZIP filename check passed (1/1) using the system activity's actual label and element type.

## Local Evidence

Screenshots and actual exported sample PDFs are under `DerivedData/FeatureQA/` (ignored build artifacts):

- `iphone-home-zh.png`, `iphone-markdown-zh.png`
- `ipad-markdown.png`, `ipad-pdf-sharing.png`
- `html-export.pdf`, `markdown-export.pdf`, `zip-report-export.pdf`

Final result bundles:

- iPhone: `/Users/user/Library/Developer/XcodeBuildMCP/workspaces/html_preview-0a68f0590b32/result-bundles/test_sim_2026-09-21T10-46-09-913Z_pid61137_430fc9c6.xcresult`
- iPad: `/Users/user/Library/Developer/XcodeBuildMCP/workspaces/html_preview-0a68f0590b32/result-bundles/test_sim_2026-09-21T10-43-39-921Z_pid61137_243fd0d3.xcresult`
