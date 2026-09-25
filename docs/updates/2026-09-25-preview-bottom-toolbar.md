# Preview actions at the bottom right — 2026-09-25

The document preview now places reading tools, preview mode, sharing/PDF export,
and file details in one bottom-right capsule. Each action has a 44-point target.
The surface uses native Liquid Glass on iOS 26 and later, with a material fallback
on earlier supported versions.

The top navigation area keeps the back button and a two-line document title.
Tapping the title opens details with the complete filename. Home-only settings
and edit actions no longer occupy the preview navigation bar.

Search replaces the capsule instead of stacking another toolbar above the
keyboard. The bottom safe-area inset lets the final document content scroll clear
of the floating controls. Existing accessibility labels, modes, and share/PDF
actions are preserved. No new localized strings were needed.

## Validation

- Build passed on iPhone 18 Pro / iOS 27.
- Five iPhone UI tests passed: long title and four actions, HTML reading and mode
  persistence, built-in samples/settings, original-file sharing, and repeated PDF
  export from the relocated button.
- The long-title test was strengthened and passed again. It dismisses the system
  keyboard's first-run introduction if present, types a search query, verifies 80
  matches, and confirms the final paragraph scrolls completely above the capsule.
- Native screenshots of the two-line title, normal keyboard, and final paragraph
  were reviewed. Evidence is under `DerivedData/BottomToolbarQA/`.
- iPad validation passed on a replacement iPad Air 11-inch (M3), iOS 26.5:
  two UI tests, zero failures. They cover the long title, four bottom actions,
  title/details sheets, keyboard/search transitions, final paragraph clearance,
  and repeated HTML PDF export with the native share popover.
- iPad screenshots were reviewed, including the popover's anchor to the relocated
  share button. Evidence is under `DerivedData/BottomToolbarQA/ipad-verified/`.
- Earlier iPad attempts did not execute tests. After scoped simulator cleanup,
  the replacement device stalled during system-service initialization. Process
  sampling identified a blocked `dasd`; restarting only that simulator's service
  completed boot and allowed the tests to run. See
  `2026-09-25-simulator-cleanup.md` for diagnosis and cleanup evidence.
- `git diff --check` passed. Existing Simplified/Traditional Chinese, English,
  and Japanese action labels are reused.

iPhone result bundles:

- `~/Library/Developer/XcodeBuildMCP/workspaces/html_preview-0a68f0590b32/result-bundles/test_sim_2026-09-25T05-17-02-933Z_pid64081_9dbf2ca2.xcresult`
- `~/Library/Developer/XcodeBuildMCP/workspaces/html_preview-0a68f0590b32/result-bundles/test_sim_2026-09-25T05-31-06-936Z_pid64081_e37f941d.xcresult`

iPad result bundle (two passed, 164.9 seconds, diagnostics enabled on failure):

- `~/Library/Developer/XcodeBuildMCP/workspaces/html_preview-0a68f0590b32/result-bundles/test_sim_2026-09-25T06-08-59-166Z_pid64081_2f9d9de9.xcresult`

API reference: [Apple — Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views).

No physical-device installation, push, or release was performed for this change.
