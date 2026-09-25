# Reading tools and Paste to Preview verification

Date: 2026-09-23. Development branch: `codex/reading-paste-preview`.

## Implemented behavior

- Rendered HTML and Markdown provide text search, previous/next match, a heading outline, and Back to Beginning from the reading toolbar menu.
- Reading position is stored with each imported document and restored when it is reopened, including after app relaunch. Existing 1.2 metadata still loads.
- HTML reading tools run in an app-owned WebKit content world. Safe Preview continues to block page scripts and external network resources. Tools index the main document; ZIP packages persist the entry page's position.
- Home offers Paste to Preview. The user explicitly pastes text, can choose HTML or Markdown and a filename, then opens a locally stored preview in Recent files. The clipboard is never read automatically.
- Pasting a whole HTML/Markdown code fence unwraps it. Empty text, URL-only input, and content exceeding 2 MB are handled with localized validation.
- English, Simplified Chinese, Traditional Chinese, and Japanese strings are included.
- PDF export excludes search highlights and restores the reading decorations afterward.

## Simulator checks

The September 23 validation in this section used simulator-only XCTest and XCUITest. Physical-device follow-up is recorded separately below.

Device: iPhone 18 Pro, iOS 27.0 simulator (`F56A2968-F35C-4455-8A34-43DCC6CDC319`).

- All 14 UI tests passed: six new reading/paste cases and eight existing smoke cases.
- All 75 unit/integration tests passed, followed by another successful complete HTML paste/search/outline/relaunch UI flow (76/76 in that targeted run).
- The initial full run had 88/89 passing tests. Further iPad checks isolated asynchronous WebKit scroll commits and a visual viewport offset that duplicated the page scroll offset. The final controller waits for two stable render frames, bounds visual viewport offsets to the layout viewport, and rejects older position snapshots. Scroll extents use `scrollingElement.clientHeight/clientWidth`. The test host now uses an active window scene; the original assertion precision remains unchanged.
- Actual screenshots confirm that search reveals the end of a long paragraph and the last column of a horizontally scrolling Markdown table. Localized controls were exercised in Simplified Chinese, Traditional Chinese, and Japanese; the core flows used English.

iPhone result bundles:

- Full UI regression: `~/Library/Developer/XcodeBuildMCP/workspaces/html_preview-0a68f0590b32/result-bundles/test_sim_2026-09-23T06-54-56-632Z_pid13628_05031eb0.xcresult`
- First corrected unit/integration + HTML UI: `~/Library/Developer/XcodeBuildMCP/workspaces/html_preview-0a68f0590b32/result-bundles/test_sim_2026-09-23T07-03-29-682Z_pid13628_f31553b7.xcresult`

Local screenshot evidence: [Paste form in Chinese](../DerivedData/ReadingPasteQA/paste-preview-zh.png), [wide-table search](../DerivedData/ReadingPasteQA/markdown-table-search.png). The complete attachment manifest is `DerivedData/ReadingPasteQA/iphone-full/manifest.json`.

iPad device: iPad Pro 13-inch (M5), iPadOS 27.0 simulator (`39391DBC-9801-4025-B05C-C40DCA861B07`). All three UI flows passed: pasted HTML, pasted Markdown, and long-paragraph/wide-table search. The screenshots also cover Dark Mode. Screenshot manifest: `DerivedData/ReadingPasteQA/ipad/manifest.json`.

The previously failing reading-position case passed three consecutive iterations after the final fixes, with unchanged assertions: `~/Library/Developer/XcodeBuildMCP/workspaces/html_preview-0a68f0590b32/result-bundles/test_sim_2026-09-23T07-29-59-774Z_pid13628_d86497cc.xcresult`.

Final iPad validation passed **76/76**: the complete 75-test unit/integration suite plus the HTML paste/search/outline/relaunch UI flow. Result: `~/Library/Developer/XcodeBuildMCP/workspaces/html_preview-0a68f0590b32/result-bundles/test_sim_2026-09-23T07-31-31-640Z_pid13628_23ecd31f.xcresult`.

Final iPhone validation of the affected HTML behavior passed **8/8**: all seven HTML reading integration tests and the complete HTML paste/search/outline/relaunch UI flow. Result: `~/Library/Developer/XcodeBuildMCP/workspaces/html_preview-0a68f0590b32/result-bundles/test_sim_2026-09-23T07-34-15-851Z_pid13628_e3b30af0.xcresult`.

Final status: all 75 unique unit/integration tests and all 14 unique UI regression tests have passing results, with the affected HTML tests rerun on both simulator form factors after the last implementation changes. No tests are skipped and no known failing checks remain. Source whitespace checks and all 28 new localization keys (four localizations each) also pass.

## Regression coverage

- Legacy metadata, merged mode/recency/position updates, and wrapped match navigation.
- Markdown repeated headings, nested blocks, Unicode matching, long-paragraph glyph positioning, and horizontally scrolling table/code content.
- HTML search across inline nodes and line breaks, rapid query changes, nested scrolling, entry/subpage isolation, and search during PDF export.
- Clipboard import format detection, fences, filenames, size limits, cleanup, and safe defaults.
- Existing sample previews, Markdown tables, ZIP sharing, HTML/Markdown/ZIP PDF export, and settings smoke tests.

The GitHub Actions UI smoke job now includes the two paste → search → outline → relaunch flows. CI has not been run remotely for this branch.

## Physical-device follow-up

On September 25, the feature branch was fast-forward merged into local `main` at `1cfd7c3`. A fresh Debug build was installed on the user's iPhone 17 (iOS 27.0), and all 14 UI regression tests passed with no skips. See [the physical-device report](physical-device-validation-results/2026-09-25-reading-paste-iphone-17.md) for results, test-harness adjustments, and local screenshot evidence.

The implementation and test evidence are local. This work does not change the App Store version or publish a build.
