# iPhone Duo UX polish — 2026-10-08

This follows the Duo review against Apple's "Designing for iPhone Duo" guidance.
The changes keep the existing reader identity, reading positions, and test
identifiers. Work is on the `duo-ux-polish` branch and has not been released.

## Reader height on the outer display

- The preview status (Interactive, Safe Preview, Raw Text) is one line by
  default: symbol, mode, and a truncated explanation. Tapping it, or the
  VoiceOver action, shows the complete explanation. Its accessibility label is
  unchanged.
- Reader search keeps the result count and previous/next/close controls on the
  field's row whenever the width leaves at least 200 points for the query.
  Before, a single row was used only in compact heights, so the inner display
  and the outer display in portrait used two rows.
- Find is a direct system toolbar action on iOS 27.1, beside Reading Tools.
  Reading Tools still contains Find for existing habits and tests.

## Library

- Open File, Open ZIP Package, and Paste to Preview share one row of tiles,
  leaving most of a short display or the sidebar for recent files.
- Settings and Edit are titled symbols. A text-only Edit button could not move
  to the vertical toolbar on the outer display; it now does.
- The sidebar uses a large title, so "HTML Previewer" (and its translations) is
  no longer truncated between toolbar buttons on the inner display.

## JSON and YAML

- When the reader is at least 480 points wide, each field shows key, value, and
  type on one line, with an adaptive key column.
- Regular-width readers place the document picker, root summary, and
  Structure/Source picker on one row, and the search field and result
  navigation on another.
- On iOS 27.1 the expand/collapse/copy-source menu is a system toolbar item with
  its own symbol. The ellipsis remains reserved for the system overflow menu.

## Outline

A regular-width reader that is at least 640 points wide shows the table of
contents as a 280-point column beside the document. Choosing a heading keeps it
open; Done or the Reading Tools command closes it. Narrower readers keep the
existing sheet.

SwiftUI's `.inspector` was tried first and removed. Its hidden content still
joined the reader's hierarchy and navigation bar on compact iPhones, added a
stray Done button, and disturbed the reader lifecycle: an enhanced Markdown
sample stayed on its spinner and native Markdown search did not reveal the
second result.

## Partially open

- Book pose: the library column ends at the fold, so the reader occupies one
  side instead of straddling it.
- Tabletop pose: HTML, rich Markdown, native Markdown, JSON, and YAML place a
  selected search result above the fold when it fits, otherwise below it. A
  fold that appears under a visible selected result moves that result aside; a
  result the reader has scrolled away from stays where it is.

The fold comes from `GeometryProxy.reservedRegions(kind: .division)` on iOS
27.1 and is stored as fractions of the reader viewport.

## Tried and reverted

- Previous/next/close in the vertical toolbar while searching. With the
  software keyboard visible, the outer display's side bar fit only Back and one
  control; the rest moved into the system overflow menu.
- Removing the custom document title to recover outer-display height. The
  system kept the same top bar with a leading title, so no height was gained.

## Screenshots

Outer display (Closed), before and after:

- [Library, before](assets/2026-10-08-duo-ux-polish/before-closed-library.png) /
  [after](assets/2026-10-08-duo-ux-polish/after-closed-library.png)
- [HTML reader, before](assets/2026-10-08-duo-ux-polish/before-closed-html.png) /
  [after](assets/2026-10-08-duo-ux-polish/after-closed-html.png)
- [ZIP reader](assets/2026-10-08-duo-ux-polish/after-closed-zip.png),
  [JSON reader](assets/2026-10-08-duo-ux-polish/after-closed-json.png)

Inner display:

- [Open launch, baseline left and new right](assets/2026-10-08-duo-ux-polish/cmp-open-sample.png)
- [JSON beside the library](assets/2026-10-08-duo-ux-polish/after-open-json.png)
- [Outline column](assets/2026-10-08-duo-ux-polish/after-outline-column.png)
- [Book pose, before left and after right](assets/2026-10-08-duo-ux-polish/compare-partial-book.png)
- [Tabletop pose with the keyboard](assets/2026-10-08-duo-ux-polish/after-partial-tabletop.png)

Captures use a dedicated "HTML Previewer Duo QA" iOS 27.1 simulator. Two
DEBUG-only launch arguments, available with `HTML_PREVIEWER_UI_TESTS=1`, open
reader tools for captures on any display: `--screenshot-reader-query=<text>`
(optionally with `--screenshot-reader-submit`) and `--screenshot-reader-outline`.

## Validation

Built with Xcode 27.1 RC and the iOS 27.1 SDK. The host was heavily loaded
throughout (load averages of roughly 400–980 from other simulator sessions),
so timing-sensitive tests were rerun individually and compared with the
unchanged `2c08a0f` build where results differed.

Ordinary iPhone, iOS 18.5 (the CI configuration):

- Unit tests: 218 run, 216 passed in one full run. The two failures were
  10-second waits (`testMarkdownSearchSpansInlineFormulaBoundariesWithoutInventingWhitespace`,
  `testVisibleSelectedSearchResultRemainsVisibleAfterViewportShrinks`); both
  passed twice when rerun, as they did on the baseline build.
- New tests: four `ReaderFoldBand` placement cases and
  `testSelectedMatchMovesClearOfAPartiallyOpenFold`, which checks in WebKit that
  a result on the fold stays put without a fold, moves aside when a fold
  appears, and that later navigation avoids the fold.
- CI UI test set plus the long-title and search-closing tests: 15 of 15 passed
  in one run.
- `SmokeUITests.scrollUntilHittable` now requires an element to sit above the
  bottom 44 points. With the shorter library, the ZIP sample row was clipped by
  the bottom edge; XCTest reported it hittable and tapped the home-indicator
  area, where the system ignored the tap.

iPhone Duo, iOS 27.1, dedicated simulator, Closed:

- Passed: JSON search/source/reopen (toolbar options), pasted Markdown
  search/outline/resume, search with no results then closing search, and
  toolbar Find (focus, typing, result controls) once the host was quiet.
- The long-title and smoke tests stop waiting for their requested landscape
  window to settle. The unchanged `2c08a0f` build fails both in the same way on
  the same simulator, so this predates these changes.

The iOS 27.1 simulator runtime installed here supports only iPhone Duo, so the
iOS 27.1 system toolbar paths (Find, JSON/YAML options, single-row search) have
been exercised only on Duo. Other iPhones use the existing controls until they
run iOS 27.1.

Supplementary runs on a quiet host, iOS 27.0 (the current release for other
devices):

- iPhone 17: the CI UI test set plus the long-title and search-closing tests
  passed 15 of 15.
- iPad Pro 11-inch (M5): `testIPadWideLibrarySelectionAndReaderSearchSurviveRotation`
  passed; the library, JSON beside the library, and the outline column were
  inspected visually.

The first PR CI run failed in `testSystemPasteDetectsJSONAndCopiesExactNumberAndCollection`
(no back button after reopening a document from Recent). On an iOS 27.0 iPhone
the new build passed and the unchanged build failed with the same message, so it
is an existing flake. Two reruns ended before any test ran: the test runner hung
or exited while bootstrapping.

Visually inspected on the Duo simulator: Closed library, HTML, ZIP, and JSON;
Open HTML, JSON, YAML, and the outline column; Partially Open book and tabletop
poses; the outline moving from a column to a sheet when the device closes.
Also inspected: [iPhone, iOS 27.0](assets/2026-10-08-duo-ux-polish/iphone-27.0-library-reader-search.png)
and [iPad, iOS 27.0](assets/2026-10-08-duo-ux-polish/ipad-27.0-library-json-outline.png).
