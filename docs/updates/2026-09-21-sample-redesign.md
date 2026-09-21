# Built-in sample redesign — 2026-09-21

Implemented locally and installed as development build 1.1 (4) on the connected iPhone 17. No App Store release was submitted.

## Changes

- HTML: **Weekend plan** (`weekend-plan.html`) presents a three-stop Saturday itinerary, a note, and a short footer.
- Markdown: **Reading notes** (`reading-notes.md`) demonstrates headings, a quote, lists, a three-column reading table, and a small code block.
- ZIP: **Reading week** (`reading-week.zip`) includes an HTML report, an external stylesheet, and a local SVG chart. Seven daily values sum to the displayed 247 minutes.
- The examples use system typography, blue accents, neutral grouped surfaces, more breathing room, and automatic light/dark appearance to match the app. HTML/ZIP include a light print palette.
- The native Markdown renderer has a centered reading width, clearer heading spacing, and more generous quote/code-block spacing. Wide tables still scroll horizontally.
- All 59 new content strings have English, Japanese, Simplified Chinese, and Traditional Chinese translations. Sample filenames are descriptive and distinct from previously imported examples.
- Newly opening a sample from the home screen creates the redesigned document. Existing imported copies remain unchanged.

## Verification

- iPhone 18 Pro simulator, iOS 27: 55/55 tests passed (48 unit/integration and 7 UI tests), covering samples, home ordering, Markdown rendering, ZIP assets/sharing, and all three PDF export paths.
- PDF visual review found a print-only height cap that narrowed the ZIP SVG relative to its weekday labels. Removed that cap and reran the ZIP PDF export UI test successfully (1/1). Screen rendering is unaffected by this print-only correction.
- Final PDF review passed for all three samples: each contains one complete A4 page, uses a readable light background, and has no old gradient artifacts. All seven ZIP chart labels align with their bars after the correction.
- Chinese HTML/ZIP documents passed 12 browser layout configurations: two pages at 320, 402, and 768 px, each in light and dark mode. No horizontal overflow, clipped leaf text, or structural overlap; local CSS and SVG loaded successfully.
- Inspected native dark-mode HTML/ZIP simulator screenshots, a light-mode HTML simulator screenshot, and the Markdown screen on the physical iPhone 17.
- The final signed build was installed on the phone and launched normally. UI testing used a separate debug library; all 51 original library files remained byte-for-byte unchanged after the final install and launch, as recorded in `phone-library-comparison.json`.
- Localization completeness and `git diff --check` passed.

## Evidence

Ignored local artifacts are under `DerivedData/SampleDesignQA/`:

- `preview.png`: side-by-side layout of actual app screenshots (HTML/ZIP from the simulator, Markdown from the physical phone).
- `html-dark.png`, `html-light.png`, `markdown-dark.png`, `zip-dark.png`: individual native screenshots.
- `browser-qa.json` / `browser-qa.md`: responsive layout evidence and browser screenshot limitations. Browser screenshot APIs timed out; the visual gallery uses the native screenshots instead.
- `pdf/`: actual exported PDFs, every page rendered as PNG, and the final PDF review in `pdf-validation.json` / `pdf-validation.md`.
- `phone-install-final.json` and `phone-library-comparison.json`: final installation and original-library verification.

Result bundles:

- Full suite: `/Users/user/Library/Developer/XcodeBuildMCP/workspaces/html_preview-0a68f0590b32/result-bundles/test_sim_2026-09-21T12-47-16-968Z_pid61137_69a48a36.xcresult`
- Final ZIP PDF rerun: `/Users/user/Library/Developer/XcodeBuildMCP/workspaces/html_preview-0a68f0590b32/result-bundles/test_sim_2026-09-21T12-55-33-977Z_pid61137_72c01ab1.xcresult`
