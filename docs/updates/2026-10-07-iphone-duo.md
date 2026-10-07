# iPhone Duo adaptation — 2026-10-07

## Status

The adaptation is implemented locally and builds with the iOS 27.1 SDK.
Native Duo validation and simulator lifecycle restoration are complete within
the recorded scope. The earlier iPhone/iPad regressions passed,
and **12 of 13 targeted Duo UI tests have passed** across the recorded runs.
The remaining HTML search rotation test fails its requested-versus-actual
window/screen geometry check. Native DeviceHub rotation now produces a real
landscape interface; the XCTest geometry mismatch remains a separate unresolved
result. The source keeps strict checks and diagnostics, and the unsuccessful
intermediate-orientation workaround was removed.

Manual Duo checks verified selected HTML/Markdown search results across fold
states, library/reader columns, ZIP page continuity, and original-file/PDF share
sheets. The desktop was subsequently unlocked and native QA resumed on the
same Duo simulator. JSON and YAML selected results were verified above the
software keyboard through the recorded orientation/fold changes. Final
HTML/Markdown active-edit focus and explicit-submit checks also passed.
Both reader placements in actual system Split View and PDF share-sheet
rotation/fold/dismissal passed. At the available divider widths, all four native
actions remained reachable; the divider snapped back to half width and no
system overflow menu surfaced. The PDF sequence
verified sharing presentation/migration; exact rotation during PDF generation
was not established. Equivalent native HTML rotation/selected-match/Back/reopen
interaction has passed; the automated geometry result remains failed. DeviceHub host toolbar layout stalls/crashes were mitigated by
normal host quit/reopen and maximizing its window; they are host environment
events, not iOS app crashes. The precise cause of the XCTest geometry mismatch
has not been established; no general SDK defect is claimed.

Xcode 27.1 RC and its system components are installed alongside the existing
Xcode. The system-default toolchain remains Xcode 27.0.
Changes remain local. No commit, push, App Store upload, or release was performed.

## Implementation

- Use one document selection and `NavigationSplitView` for the library and reader.
- Preserve the current reader while the available space changes; adapt navigation
  through the system container instead of switching between separate view trees.
- Use system toolbar items on iOS 27.1, including titled symbols that work in a
  vertical bar and can be placed in overflow by the system. Keep the existing reading controls on older
  supported systems.
- Preserve reading position, search, zoom, and interactive HTML state during
  viewport changes.
- Keep the iOS 17 minimum deployment target and existing local-only document
  storage, import, export, and sharing behavior.

The reader identity combines the document UUID and payload path. Rename/pin and
window-size changes keep the current reader; replacing the payload creates a new
reader. Navigation uses the system container's compact/regular adaptation, with
initial sidebar visibility set to `.automatic`.

Three simulator findings were fixed:

1. `NavigationSplitView` can temporarily report disappearance while the selected
   detail is still visible. A SwiftUI `.task` could begin already cancelled and
   leave Markdown/ZIP on a permanent spinner. Initial loading now belongs to the
   selected document/payload; real selection changes cancel it and stale results
   are checked before publication. The same selection check keeps reading-session
   visibility consistent.
2. Native Markdown's lazy `scrollTo` could overwrite a precise block offset.
   Width is applied outside the current layout transaction and restoration is
   confirmed after the layout settles. Tests check actual scroll offsets and
   within-block fractions at 390, 280, and 540 point widths.
3. Resize recovery could hide a previously visible search result or overwrite a
   newer explicit navigation. HTML/rich Markdown and native Markdown conditionally
   reveal the current match only when it was visible before resizing. A user who
   has scrolled away retains their reading anchor. Web navigation claims the
   current viewport and retains its revision while delayed resize events settle.

The iOS 27.1 toolbar uses separate native items with text/symbol labels. Four
items were manually verified in the native vertical toolbar in Closed and Open
states. Priority annotations are compiler-gated for older CI toolchains.
Sharing presents through a SwiftUI `.sheet`; background UIKit presentation
anchors were removed after duplicate off-window instances failed to present
reliably on Duo.

The iOS 27.1 search bar uses a responsive custom `Layout` with five stable
children. Native QA confirmed that a Closed → Open transition retained the HTML
query and selected match but lost field focus and the keyboard. The final shared
HTML/Markdown field bridges `UITextField` and keeps editing intent in a
document-owned `DocumentSearchEditingSession`, restoring the first responder
when the field moves between windows. The temporary keyboard observer was
removed. Final native HTML checks then retained keyboard/caret from Closed
landscape to Open portrait and rotated Partially Open. Without tapping the field
again, a software-keyboard `x` changed `Saturday` to `Saturdayx`, and Delete
restored it. On returning Closed, the runtime hid the software keyboard while
caret/editing intent remained; keyboard visibility is not claimed for every
pose. Next intentionally ended editing, after which portrait/Open still showed
the complete selected second match without a keyboard. Native Markdown also accepted software `x`/Delete after Open without refocusing,
retained `quiet` / `1 of 1` / caret / keyboard and the complete match through
Partially Open → Closed, and kept the keyboard dismissed after Search submit
then Open. The final trace-free rebuild passed and the installed entrypoint/debug code
image match the build products.

The shared JSON/YAML reader now uses `AnyLayout` on iOS 27.1 compact-height
windows to combine header controls and the mode picker, and to put search and
result navigation in one row. The same search field survives layout changes;
multi-document selection and options remain available. This addresses a settled
Closed-landscape capture where the keyboard remained visible but the original
four control rows left no visible document content. The build passed in `/tmp/html-duo-27-structured-compact-build.log`.
The selected result is also repositioned when the focused reader viewport
changes, keeping it above the software keyboard. Search/source/reopen passed
on Duo. Root visually verified JSON `247` in Closed landscape and settled
portrait, and YAML document 2 / Source / query `3000` / line 29 in Closed
landscape and Open portrait. The selected row, caret and keyboard remained
visible; the Open YAML sidebar overlay was explicitly hidden before checking
the source line.

Paste and Settings forms keep their navigation bars visible on iOS 27, using
`toolbarMinimizationBehavior(.never, for: .navigationBar)` behind a compiler and
runtime gate. Actual Duo recordings showed the default minimization hiding
Paste's Cancel/Preview and Settings' Done controls after form scrolling. The fix
built successfully. Short-landscape Paste navigation and long-title/search
reading controls passed in the completed LongTitle test; Settings scrolling/Done
and HTML/Markdown/ZIP sample switching passed in the final Smoke test.

## Verified results

The earlier Xcode 27.0 iPhone/iPad targeted runs recorded **43 unit/integration
tests and 10 UI tests passed**, with no remaining failed targeted test in that
recorded set. This is an aggregate of the final results for each test, not a
single full-suite run. Duo results are counted separately below.

| Area | Verified behavior |
| --- | --- |
| HTML / rich Markdown | Paragraph/block continuity, nested scrolling, fixed/sticky content, visible search result after resizing, user-scrolled-away behavior, newer navigation priority, source/JavaScript isolation |
| Native Markdown | Initial restoration, narrower/wider layouts, shorter viewports, selected-match visibility, typography and search geometry |
| Zoom | Eight existing appearance/optical-zoom tests, including height-only changes and reopen restoration |
| Phone UI | Precise second search-match frame remains visible through portrait/landscape rotation; Back/reopen, long titles, keyboard/search controls, sharing, pin/rename/filter |
| Import and formats | HTML/Markdown/ZIP samples, batch duplicate/failure handling, JSON search/source/reopen, YAML multi-document/source/reopen, ZIP page/link/back/relaunch navigation |
| iPad UI | Library and reader visible together; HTML → Markdown → HTML selection, portrait/landscape rotation, library query and reader search preserved |
| Existing review behavior | Ten review-prompt unit tests passed |

All simulator destinations ran sequentially with explicit UDIDs,
`-parallel-testing-enabled NO`, and
`-maximum-concurrent-test-simulator-destinations 1`. Test libraries/fixtures were
isolated and scoped. Existing ASO assets/scripts/project metadata and standalone
review-prompt files were checked against the starting snapshot: 161 unrelated
files remained byte-identical.

The earlier regression result provenance, including failures and the later
passing results that supersede them, is in
[validation-results.json](assets/2026-10-07-iphone-duo/validation-results.json).
Duo automated results are recorded in
[duo-validation-results.json](assets/2026-10-07-iphone-duo/duo-validation-results.json).
The initial 13-test batch was 4 passed / 9 failed; the nine-test rerun was
5 passed / 4 failed; the four-test rerun was 1 passed / 3 failed. After desktop
unlock, the five-test run was 2 passed / 3 failed, the two-test rerun was
1 passed / 1 failed, and the final Smoke run passed its one test. The latest
result per targeted test is therefore **12 passed / 1 failed**, not a single
13-test passing run. Historical failures remain in the manifest.

Passed Duo checks cover JSON/YAML search, source mode and reopening; HTML zoom
and full-screen restoration; Markdown typography, local image opening/zooming/
closing; original-file sharing; HTML repeated PDF export, Markdown/ZIP PDF
export, ZIP package sharing; and ZIP page/search/link/back/relaunch behavior.

The remaining failed test is HTML search rotation, which stops at its strict
geometry check. LongTitle passed after checking overlap only for an existing,
visible native title while retaining complete viewport/toolbar-band assertions
and the final accessible File Details entry. Smoke passed after locating and
expanding the actual Samples disclosure and scrolling the returned library to
its top before asserting the visible Paste entry. The Markdown image test passed
after replacing an incorrect whole-Toolbar accessibility-container occlusion
check with actual visible button/chrome bounds, while preserving real image
interaction and viewport assertions.
[Manual Duo screenshot provenance](assets/2026-10-07-iphone-duo/duo-screenshot-provenance.json)
records the selected raw display captures, poses, hashes, and verification limits.

Manual checks on the iOS 27.1 Duo simulator, reported by the operator and
visually inspected on both displays. These captures predate later compact
controls and test-harness adjustments; each proves its recorded scene on the
build used at capture time and is not tied to the final executable hash:

| Check | Verified behavior |
| --- | --- |
| HTML search | `weekend-plan.html`, query `bookshop`, selected result `1 of 1`: query and highlight retained through Closed → Open → PartiallyOpen with rotation → Closed |
| Native Markdown search | `reading-notes.md`, query `quiet`, selected result `1 of 1`: query and highlight retained through Open → PartiallyOpen → Closed |
| Native toolbar | Four vertical toolbar items visible in Closed and Open states |
| Original HTML sharing | SwiftUI share sheet presented in Closed portrait and remained presented through Open landscape without dismissal |
| HTML PDF sharing | Open-state PDF export presented `weekend-plan` PDF, 38 KB |
| ZIP page continuity | `chapters/details.html` stayed selected through Open → Partially Open → Closed |

Additional root-inspected native keyboard checks, recorded separately in the
Duo manifest, verified these specific scenes:

| Check | Verified behavior |
| --- | --- |
| JSON compact keyboard | Query `247`, `1 of 1`, complete `minutes 247` row/path above the software keyboard in Closed landscape and settled portrait; caret/keyboard retained through rotation |
| YAML Source fold | Document 2, Source, query `3000`, `1 of 1`, line 29 `port: 3000` visible above the keyboard in Closed landscape and Open portrait after Hide Sidebar; caret/keyboard retained |
| HTML focus/typing | Closed landscape → Open portrait → rotated Partially Open retained keyboard/caret; native `x` and Delete worked without refocusing. Closed later hid the keyboard at runtime while caret/editing intent remained |
| HTML native rotation/reopen | After Next ended editing, complete orange second `Saturday` match (`2 of 2`) remained visible in portrait/Open wide with keyboard dismissed; Closed Back → recent file reopened content and four toolbar actions |
| Markdown focus/typing | After Open, software `x`/Delete worked without refocusing; `quiet` / `1 of 1` / caret / keyboard / complete selected match survived Partially Open → Closed; explicit Search submit prevented keyboard return on Open |
| Actual system Split View | Markdown `reading-notes` app left, separate Settings app right: both rendered and four native reading actions were visible; reader-right placement has separately recorded settled/search evidence |
| Right-reader system Split View | HTML right, Settings left: safe areas, Back and four actions visible; Reading Tools → Find → `Saturday` → Next showed complete orange second match (`2 of 2`), and closing Search restored all four actions |
| Available toolbar width | Divider narrowing snapped back to half width; all four actions were reachable. System overflow never surfaced at these widths; the opened Reading Tools menu contains application commands |
| PDF share migration | Final clean build exported `weekend-plan (3)` (38 KB); share sheet survived Open landscape → Open portrait → Closed landscape → Open portrait, then X dismissed successfully. Rotation during generation itself was not established |

The final trace-free source/test-target build is recorded in
`/tmp/html-duo-final-clean-build-20261007.log` and ends with
`TEST BUILD SUCCEEDED`. The installed entrypoint and separately linked Debug
Swift code image match the build products; the exact fingerprints and final
161-file protection audit are recorded in the Duo manifest.
The JSON/YAML adjustment also passed its build in
`/tmp/html-duo-27-structured-compact-build.log`.

## Duo acceptance checklist

- [x] Build with the iOS 27.1 SDK and install on the existing Duo simulator.
- [x] Verify four native vertical toolbar items in Closed and Open states.
- [x] Verify the library and reader together on the wide inner display.
- [x] Preserve HTML and native Markdown query/highlight through the recorded fold transitions.
- [x] Preserve the selected ZIP detail page through the recorded fold transitions.
- [x] Present original-file sharing in Closed and keep the sheet through Open.
- [x] Present HTML PDF export in Open; repeat PDF export in the automated test.
- [x] Verify automated zoom, full-screen restoration, Markdown image interaction, and format reopening.
- [x] Document equivalent native HTML search rotation/selected-match/Back/reopen evidence; the XCTest geometry record remains failed.
- [x] Verify Paste/Settings navigation after scrolling in a short landscape viewport on the final build.
- [x] Verify HTML focus and software-keyboard typing through Open/rotated Partially Open; record runtime keyboard hiding on Closed.
- [x] Verify native Markdown field focus, visible result and software typing through folding; explicit Search submit keeps the keyboard dismissed.
- [x] Verify JSON/YAML compact controls with the keyboard open, including a visible YAML Source match before and after folding.
- [x] Verify actual two-app system Split View with the reader on either side and Settings on the other.
- [x] Verify PDF sharing presentation/migration through native rotation/folding and successful X dismissal; generation-phase rotation was not established.
- [x] Exercise the available native divider widths: four actions stay reachable; divider snaps to half width and no system overflow menu is triggered.

Native UI validation and lifecycle restoration are complete within the recorded
scope. Automated rotation geometry remains unresolved, with equivalent native
interaction verified. System overflow was not triggered at the tested widths;
exact rotation during initial loading or PDF generation was not established.

## Environment

Initial toolchain: Xcode 27.0 (27A266a), Swift 6.4, macOS 27.2.
Earlier verified binary: version 1.7 (12), `iphonesimulator27.0`, minimum iOS 17.0,
device families iPhone and iPad, existing supported orientations preserved.
Installed iOS 27.1 simulator runtime (24A94232) using
`xcodebuild -downloadPlatform iOS -buildVersion 27.1 -architectureVariant arm64`.
Downloaded Xcode 27.1 RC (27A9275) from the authenticated Apple Developer page
and installed it at `/Applications/Xcode-27.1.app`. Gatekeeper assessment passed
with `source=Apple System`; the app reports Xcode 27.1 / build 27A9275.
The archive is retained at
`/Volumes/DevSSD/Downloads/Xcode_27.1_Release_Candidate.xip`.
The default `xcode-select` path remains `/Applications/Xcode.app/Contents/Developer`.
First-launch installation of shared system components completed after macOS
administrator authorization. The final Duo build uses the Xcode 27.1 toolchain
and iOS 27.1 SDK explicitly, without changing the default `xcode-select` path.
An existing iOS 27.1 iPhone Duo simulator was reused and booted for this run.

| Reused existing simulator | UDID | Purpose | Recorded state |
| --- | --- | --- | --- |
| HTML Previewer 1.6 Geometry iOS18.5 / iPhone 16 | `D17454A3-3351-48DD-A61F-395E5E7EE3FF` | Phone, WebKit, native-reader regression | Shutdown |
| Passnote ASO iPad Pro 12.9 / iOS 18.5 | `9216FE52-CA0E-4113-8ED5-19B4BF9755CE` | Regular-width navigation and rotation | Shutdown |
| iPhone Duo / iOS 27.1 | `F90A798B-CBEA-4A0C-AD45-B22F7BF2E2A7` | Actual fold-state, toolbar, search, sharing and targeted UI regression | Shutdown |

The final inventory at 15:23:09 JST on 2026-10-07 confirmed all seven existing
devices were shutdown. Root shut down the reused Duo after completing native QA;
the phone/iPad regression devices stayed shutdown during the resumed session.
This task did not create, clone, erase, or delete a simulator. The app/test
installation and existing simulator data are retained. The exact inventory is
recorded in [duo-lifecycle.json](assets/2026-10-07-iphone-duo/duo-lifecycle.json).

## Screenshots

The first five links below are unmodified iOS 18.5 phone/iPad regression
captures, visually inspected after orientation settled. The following 28 links
are actual Duo manual captures.
[Screenshot provenance](assets/2026-10-07-iphone-duo/screenshot-provenance.json)
records the device, test, timestamp, and result bundle for each image.

- [iPad library and HTML reader](assets/2026-10-07-iphone-duo/ipad-library-reader.png)
- [iPad Markdown search retained after rotation](assets/2026-10-07-iphone-duo/ipad-search-after-rotation.png)
- [Phone landscape with the second match visible](assets/2026-10-07-iphone-duo/iphone-search-landscape.png)
- [Phone search after returning to portrait](assets/2026-10-07-iphone-duo/iphone-search-after-rotation.png)
- [Phone reopened after Back](assets/2026-10-07-iphone-duo/iphone-reopened.png)

Raw Duo captures were also visually inspected on the active display. These
captures demonstrate the specifically listed manual scenes; they are not proof
that every outstanding regression has passed.

- [Duo Closed: HTML selected search result](assets/2026-10-07-iphone-duo/duo-closed-search-result.png)
- [Duo Open: library and HTML search](assets/2026-10-07-iphone-duo/duo-open-search-result.png)
- [Duo Partially Open, rotated: selected HTML result](assets/2026-10-07-iphone-duo/duo-partial-rotated-search.png)
- [Duo Closed: Markdown selected search result](assets/2026-10-07-iphone-duo/duo-closed-markdown-search.png)
- [Duo Partially Open: Markdown search](assets/2026-10-07-iphone-duo/duo-partial-markdown-search.png)
- [Original-file share in Closed](assets/2026-10-07-iphone-duo/duo-closed-original-share-pass.png)
- [Same original-file share after Open](assets/2026-10-07-iphone-duo/duo-open-original-share-pass.png)
- [HTML PDF sharing in Open](assets/2026-10-07-iphone-duo/duo-open-pdf-share-pass.png)
- [ZIP detail page in Open](assets/2026-10-07-iphone-duo/duo-open-zip-selected-page.png)
- [Same ZIP detail page after Closed](assets/2026-10-07-iphone-duo/duo-closed-zip-selected-page.png)

Later root-verified native captures preserve original bytes and modification
times. They prove the listed scenes on the capture-time build. The final PDF
sequence explicitly uses the verified trace-free installed build; older images
are not assigned that later build identity.

- [HTML: Closed keyboard before Open](assets/2026-10-07-iphone-duo/duo-racefix-html-before-open.png)
- [HTML: Open keyboard typing without refocusing](assets/2026-10-07-iphone-duo/duo-racefix-html-open-keyboard-typing-pass.png)
- [HTML: rotated Partially Open keyboard/caret](assets/2026-10-07-iphone-duo/duo-racefix-html-partial-rotated-keyboard.png)
- [HTML: portrait second match after Next ends editing](assets/2026-10-07-iphone-duo/duo-racefix-html-next-portrait.png)
- [JSON: landscape complete result above keyboard](assets/2026-10-07-iphone-duo/duo-json-scrollfix-landscape-keyboard.png)
- [JSON: settled portrait result above keyboard](assets/2026-10-07-iphone-duo/duo-json-scrollfix-portrait-keyboard-settled.png)
- [YAML: Closed Source line above keyboard](assets/2026-10-07-iphone-duo/duo-yaml-source-closed-keyboard-final.png)
- [YAML: Open Source line after Hide Sidebar](assets/2026-10-07-iphone-duo/duo-yaml-source-open-sidebar-hidden-final.png)
- [HTML: Open second match with keyboard dismissed](assets/2026-10-07-iphone-duo/duo-final-html-next-open-dismissed.png)
- [HTML: reopened from the real library](assets/2026-10-07-iphone-duo/duo-final-html-reopen.png)
- [Markdown: Open with retained focus and selected match](assets/2026-10-07-iphone-duo/duo-final-markdown-open-typing.png)
- [Markdown: selected match and keyboard after re-closing](assets/2026-10-07-iphone-duo/duo-final-markdown-reclosed-keyboard.png)
- [System Split View: reader left, Settings right](assets/2026-10-07-iphone-duo/duo-final-system-split-left.png)
- [PDF share after native rotation to Open portrait](assets/2026-10-07-iphone-duo/duo-final-pdf-share-rotated.png)
- [PDF share retained in Closed landscape](assets/2026-10-07-iphone-duo/duo-final-pdf-share-closed.png)
- [System Split View: settled right reader, left Settings](assets/2026-10-07-iphone-duo/duo-final-system-split-right-settled.png)
- [System Split View: right reader second match](assets/2026-10-07-iphone-duo/duo-final-system-split-right-search.png)
- [System Split View: right reader Reading Tools commands](assets/2026-10-07-iphone-duo/duo-final-system-split-right-tools.png)


## Apple references

- [Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo)
- [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)
- [Tools and SDKs](https://developer.apple.com/iphone-duo/)

Unchecked items are not verified results.
