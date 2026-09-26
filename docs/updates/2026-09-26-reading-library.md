# Reading and library improvements

Development version: 1.4 (8). This change does not submit a new App Store build.

## Reading

- The existing reading-tools menu includes Appearance and Full Screen Reading.
- Full screen hides navigation, the mode description, and the action dock. A small bottom-right control restores them without intercepting page interactions.
- HTML page zoom ranges from 100% to 300%. Native optical zoom enlarges text, images, and controls together without reloading scripts or changing source styles, including documents that fix their own text scaling.
- Markdown font size ranges from 80% to 180%, and added line spacing from 0 to 12 points. Both combine with system Dynamic Type and persist for the document type.
- Display settings change reading layout. PDF export keeps the document's print layout and restores the reading scale and position after printing.
- Local Markdown images support full-screen pinch zoom, pan, double-tap, and accessible zoom/reset buttons.

## Library

- Search display names and original filenames; filter HTML, Markdown, and ZIP packages.
- Pin frequently used files and change their display names without changing file or asset paths.
- Repeated imports identify identical contents or an existing filename and offer Update Existing, Keep Both, or Cancel.
- Updates preserve identity, display name, pin, and preview mode. Changed contents reset the saved reading position; byte-identical contents preserve it.
- Files are staged outside the library until a decision. Replacement commits metadata only after preparing a complete new payload, so failed writes leave the old document intact.
- New text is available in English, Simplified Chinese, Traditional Chinese, and Japanese.

## Validation

The dedicated `ReadingLibraryUITests` suite runs in the app's existing DEBUG test isolation. `HTML_PREVIEWER_UI_TESTS=1` selects a separate `UITestLibrary` directory and the `<bundle identifier>.UITests` preferences suite, on both simulators and physical devices. Normal launches continue to use the user's original library and preferences.

Each test creates documents under a unique UUID filename prefix. Its DEBUG fixture helper accepts only valid UUIDs and cleanup removes only that run's matching documents inside `UITestLibrary`. Before a test, the helper captures the isolated suite's existing HTML zoom, Markdown font scale, and line spacing, then applies predictable defaults. Cleanup restores those exact test-suite values, including whether a key was originally absent. The helper never reads or writes the user's normal `UserDefaults.standard` reading preferences. Relaunches within a test reuse the same isolated store and preferences to verify persistence.

Verified so far:

- iPhone SE (3rd generation), iOS 18.5: all 102 unit/integration tests passed in `ReadingLibrarySmallQA/unit-final-complete.xcresult`, including 14 library-management tests, 5 reading/image geometry tests, and 7 loaded-WebKit appearance tests.
- iPhone 18 Pro, iOS 27: duplicate Update/Keep Both/Cancel, pin/rename/search/type filtering/persistence, Markdown typography/persistence and image buttons/pinch/reset/close passed. The long-paragraph/wide-table search regression also passed.
- Final iOS 27 HTML verification used native simulator interaction after the XCTest runner stalled before starting its test. Confirmed visible 100% to 150% enlargement, full-screen entry/exit, retained 150% after terminating/relaunching and rebuilding the app, and reset to the original visible 100% size. Screenshots: `visual/iphone-html-100.png`, `iphone-html-150.png`, `iphone-html-fullscreen-150.png`, and `iphone-html-reset-100.png` under `ReadingLibraryQA/`.
- iPad Pro 12.9, iOS 18.5: both library-management and Markdown/image UI cases passed. Japanese and Simplified Chinese reading settings were inspected in light and dark appearances. The final library-filter contrast adjustment was also inspected in both appearances.
- Physical iPhone 17, iOS 27: duplicate imports and pin/rename/search/type filtering/persistence passed. Markdown typography and settings persistence also passed before the image run was interrupted when the device switched to Gmail. The earlier HTML implementation passed enlargement/full-screen/persistence; the final optical-zoom implementation and image viewer still require a quiet-device rerun. The currently installed build predates the final HTML fix.

Runtime QA found and fixed a search/filter interaction problem: active system search hides navigation toolbar items. File type selection now lives in the library list and remains reachable while searching or showing zero results.

Final iOS 27 visual inspection also caught Menu's automatic label style hiding the filter title and an oversized `ViewThatFits` row. The filter now explicitly shows its title/icon and uses its natural vertical size. The rebuilt app was inspected in light and dark appearances (`visual/iphone-library-final-light.png` and `iphone-library-final-dark.png`).

Further HTML validation exposed a WebKit text-size reset issue after reopening at a saved page zoom, and CSS zoom did not consistently enlarge text in documents with fixed text scaling. The implementation now uses native optical zoom. Verified cases cover actual glyph enlargement and reset with automatic and fixed text scaling, saved zoom, natural fit without a viewport declaration, unchanged author styles and strict content policy, live JavaScript state, zoomed search visibility, 92% reading-position restoration, and local-page navigation/back. PDF checks compare pagination and text selection bounds, then confirm that the original reading scale and scroll offset return after export.

The final development build for a physical iPhone succeeded (`ReadingLibraryDeviceQA/build-final-1_4.log`). Installation and the two remaining physical UI cases are waiting for the user's readiness confirmation; no further device interaction is scheduled while the phone is in use.

Evidence is stored under `DerivedData/ReadingLibraryQA/`, `DerivedData/ReadingLibrarySmallQA/`, and `DerivedData/ReadingLibraryDeviceQA/` in the main checkout. Localized visual captures are in `DerivedData/ReadingLibraryQA/visual/`.

Environment notes: the iOS 18.5 unit run initially stalled in XcodeBuildMCP's packaged test launch; a normal `xcodebuild test` run passed. The existing iPadOS 26.5 simulator stalled in FrontBoard before starting the app, so iPad validation used the existing 18.5 simulator. The final iOS 27 XCTest startup stalled before any test began; that run was cancelled and does not count as a passing automated test. Native simulator interaction verified the final HTML flow instead. No simulator was created or erased.
