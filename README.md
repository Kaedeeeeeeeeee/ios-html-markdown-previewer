# HTML Previewer

Local-first iOS/iPadOS app for previewing HTML, Markdown, YAML, JSON, and zipped HTML report packages.

The product and implementation plan is in `ios-html-markdown-previewer-plan.md`.

## Current Status

MVP implementation is complete for the local core flow:

- Document type declarations for HTML, Markdown, YAML (`.yaml` / `.yml`), JSON (`.json`), and ZIP.
- Separate app file picker entries for previewable documents and ZIP report packages.
- New HTML imports open in Interactive WKWebView preview with page JavaScript and external resources enabled. Safe Preview remains available to block page scripts and external HTTP/HTTPS resources; both modes block external navigation and form navigation.
- Native Markdown reading view, including GFM tables with column alignment and horizontal scrolling. Documents with code, mathematics, or Mermaid diagrams use an offline enhanced reader.
- Syntax highlighting for 19 code languages and exact one-tap copying; inline and display LaTeX math; Mermaid diagrams. Bundled libraries and fonts require no network connection.
- Native YAML structure/source views with collapsible objects and arrays, scalar type labels, source highlighting and line numbers, field/source search, multiple-document selection, and syntax-error locations. Copy values, paths, or original source, and resume the selected document/view/position.
- Native JSON structure/source views with strict offline parsing, exact number text, typed fields, collapsible objects and arrays, field/source search, and syntax-error locations. Copy decoded scalar values, exact collection source, or field paths without rounding large numeric IDs.
- ZIP package import with local CSS/image resource loading, searchable HTML/Markdown page selection, and previous-page navigation.
- Share original files or complete ZIP packages, preserving bundled CSS and images.
- Export rendered HTML and Markdown to paginated A4 PDFs from the share menu.
- Recent files before collapsible samples, details, raw text fallback, and delete cleanup.
- Paste HTML, Markdown, YAML, or JSON text with the system Paste button, choose a format and optional name, and keep the preview in Recent files.
- Find text, jump through a heading outline, and resume the last reading position in rendered HTML and Markdown previews.
- Full-screen reading with a one-tap control restore button, HTML page zoom, and Markdown font-size and line-spacing controls.
- Local Markdown images open in a full-screen viewer with pinch, pan, double-tap, and accessible zoom controls.
- Search the document library, filter by type, pin frequent documents, and rename display titles without changing source filenames or asset paths.
- Review repeated imports before choosing to update an existing document or keep another copy.
- Select multiple files in either document or ZIP import. Review duplicates one at a time, skip an individual file, and see imported/skipped/failed totals after the selection finishes.
- App icon, privacy manifest, App Store listing draft, and screenshot assets.

PDF export uses the loaded HTML page and its print styles, or a locally rendered
Markdown document. It is available after rendered preview finishes loading;
Raw Text mode continues to offer original-file sharing. Exported PDFs are static
documents. Temporary export files are removed when the share activity finishes.

Reading tools are available from the document-and-magnifier button in rendered
previews. Search highlights matches and provides previous/next controls; the
outline lists document headings. Reading positions are stored locally per
imported document, including across app restarts. HTML reading tools inspect the
main document in an app-owned WebKit content world without enabling page scripts
in Safe Preview. ZIP packages remember the last selected page and a separate
reading position for each page.

ZIP previews include a compact package bar below the preview status. Tap the
current page to search titles and paths, or use the back arrow to return to the
previous package page. Local links between HTML and Markdown use the same reader;
CSS and images remain relative to their page. Original sharing sends the complete
ZIP, while PDF export and Raw Text use the current page. The built-in ZIP sample
contains an overview, a nested HTML report, and a Markdown appendix. See
[ZIP navigation](docs/updates/2026-09-27-zip-navigation.md) for behavior and validation.

Paste to Preview accepts up to 2 MB of text and never reads the clipboard in the
background. It can recognize HTML, Markdown, YAML, and JSON wrapped in a single code fence;
the format can also be chosen explicitly. Pasting only a URL shows an explanation
instead of fetching a webpage. Pasted content uses the same local storage,
preview defaults, sharing, and PDF export as imported files. New pasted HTML and
HTML entries inside ZIP packages open in Interactive mode; Markdown uses its
rendered reading view. Plain YAML configuration text requires choosing YAML;
an outer `yaml` or `yml` fence selects it automatically. Reopening a document
preserves its saved preview mode.

JSON files and complete pasted objects/arrays open in the same native structured
reader as YAML, using an independent strict parser. Plain numbers, quoted text,
and Markdown links are not automatically treated as JSON; choose JSON explicitly
for scalar documents. JSONC comments and trailing commas are reported as errors.
The source and original-file sharing remain available when parsing fails.
JSON uses UTF-8 (an initial BOM is accepted), with a 2 MB structure limit,
64 levels of nesting, and 12,000 tree nodes. Source previews are bounded to
200,000 characters and 20,000 lines. The original imported bytes remain unchanged.
JSON and YAML do not offer PDF export or ZIP page navigation.

The 1.7.1 candidate [store copy](docs/app-store-listing.md)
and [usage measurement proposal](docs/plans/2026-10-02-usage-measurement.md) are
local preparation. Usage analytics have not been integrated; the app still
does not upload usage events or user documents.

[App Store rating requests](docs/updates/2026-10-03-review-prompts.md) use local
reading counts: five foreground readings of at least 30 seconds across three
dates, followed by a two-second pause back in the library. The same version is
requested at most once, with at least 120 days between requests.

Open a YAML file through Open File, Paste to Preview, or the built-in YAML sample.
Use Structure to browse typed fields and Source to read comments and original
formatting. Long-press a field to copy its value/path or jump to its source line.
The parser and highlighter are bundled offline. YAML sharing sends the original
file; PDF export and ZIP page navigation remain available for HTML/Markdown.
See [YAML preview changes and simulator screenshots](docs/updates/2026-10-01-yaml-preview.md)
for usage, validation, and bounded preview limits.

Markdown supports `$...$` and `\(...\)` for inline mathematics, `$$...$$`,
`\[...\]`, or a `math` fenced block for display equations, and `mermaid`
fenced blocks for diagrams. This is the KaTeX subset of LaTeX math, not a `.tex`
document compiler. Code and escaped dollar signs remain literal. Unknown code
languages and invalid equations or diagrams keep readable source. Formula and
diagram source is searchable, and PDF export waits for the local renderer and
fonts before printing. See [Markdown enhancements](docs/updates/2026-09-27-markdown-enhancements.md)
for examples and offline dependency details.

Remaining release gates are external to simulator-only local development:

- Physical-device open/share validation from Files, Mail, AirDrop, iCloud Drive, Safari downloads, and one messaging app. See `docs/physical-device-validation.md`.
- App Store Connect paid-download setup, privacy labels, upload, and final archive/TestFlight smoke test. See `docs/app-store-submission-runbook.md`.
- First usability test round with an external participant. See `docs/usability-testing/`.

## Build

```sh
xcodegen generate
xcodebuild test \
  -project HTMLMarkdownPreviewer.xcodeproj \
  -scheme HTMLMarkdownPreviewer \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath DerivedData
```

Release device build preflight:

```sh
scripts/release-device-build.sh
```

Archive preflight:

```sh
scripts/archive-preflight.sh
```

Signed archive creation:

```sh
DEVELOPMENT_TEAM=<Apple Team ID> scripts/create-signed-archive.sh
```

The signed archive helper validates App Store/TestFlight distribution signing by default. Use
`ALLOW_DEVELOPMENT_SIGNING=YES` only for local physical-device smoke builds.

Archive physical-device smoke helper:

```sh
scripts/run-archive-device-smoke.sh --device <device-id-or-name>
```

The helper records install, launch, and launch-screenshot artifacts under
`DerivedData/PhysicalDeviceSmoke/`.

Public App Store page verification:

```sh
scripts/verify-public-pages.sh
```

GitHub Actions execution diagnostic:

```sh
scripts/check-github-actions-execution.sh
```

Portable release materials audit:

```sh
scripts/portable-release-materials-audit.sh
```

Release packet staging:

```sh
scripts/prepare-release-packet.sh
```

The release packet includes generated App Store Connect and final smoke result
drafts under `AppStoreConnect/` and `FinalSmoke/`. After
`scripts/final-submission-preflight.sh` runs, the packet also includes the
current preflight report under `Evidence/`, including the working-tree state
and latest evidence commit checks. When local physical-device validation or
archive-smoke evidence has been staged, the packet also copies those evidence
files under `PhysicalDevice/LatestValidationRun/` and
`FinalSmoke/ArchiveDeviceSmoke/`, with a packet-relative index at
`Evidence/release-evidence-index.md` and SHA-256 checksums at
`Evidence/checksums-sha256.txt`.

App Store Connect setup run draft:

```sh
scripts/prepare-app-store-connect-run.sh
```

Physical-device validation sample staging:

```sh
scripts/prepare-validation-samples.sh
```

Physical-device validation run draft:

```sh
scripts/prepare-physical-device-validation-run.sh --device <physical-iPhone>
```

Physical-device validation sample browser delivery:

```sh
scripts/serve-validation-samples.sh
```

First-round usability test packet:

```sh
scripts/prepare-usability-test-packet.sh
```

Final archive/TestFlight smoke run draft:

```sh
scripts/prepare-final-smoke-run.sh --device <physical-iPhone>
```

Final submission preflight:

```sh
scripts/final-submission-preflight.sh
```

## Release Materials

- JSON and batch import development notes and real UI evidence: `docs/updates/2026-10-02-json-batch.md`
- App Store listing draft: `docs/app-store-listing.md`
- App Store Connect handoff: `docs/app-store-connect-handoff.md`
- Release checklist: `docs/release-checklist.md`
- Final archive/TestFlight smoke template: `docs/final-archive-smoke-test-template.md`
- Release packet staging: `scripts/prepare-release-packet.sh`
- GitHub Actions execution diagnostic: `scripts/check-github-actions-execution.sh`
- Portable release materials audit: `scripts/portable-release-materials-audit.sh`
- Local release audit: `scripts/release-audit.sh`
- Public App Store page verification: `scripts/verify-public-pages.sh`
- Generic iOS Release build preflight: `scripts/release-device-build.sh`
- Generic iOS archive preflight: `scripts/archive-preflight.sh`
- Distribution-signed Release archive helper: `scripts/create-signed-archive.sh`
- App Store Connect setup run draft: `scripts/prepare-app-store-connect-run.sh`
- Archive physical-device smoke helper: `scripts/run-archive-device-smoke.sh`
- Final archive/TestFlight smoke run draft: `scripts/prepare-final-smoke-run.sh`
- Physical-device validation sample staging: `scripts/prepare-validation-samples.sh`
- Physical-device validation run draft: `scripts/prepare-physical-device-validation-run.sh`
- Physical-device validation browser delivery: `scripts/serve-validation-samples.sh`
- First-round usability test packet: `scripts/prepare-usability-test-packet.sh`
- Final submission preflight: `scripts/final-submission-preflight.sh`
- Screenshot set: `docs/app-store-screenshots/`
- Privacy manifest: `HTMLMarkdownPreviewer/PrivacyInfo.xcprivacy`
- App icon: `HTMLMarkdownPreviewer/Assets.xcassets/AppIcon.appiconset/`
