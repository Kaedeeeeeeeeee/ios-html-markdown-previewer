# App Store Screenshots

This directory is the canonical input for the 1.8 (13) local screenshot audit,
modern App Asset Library uploader, and read-only distribution gate. The source
packet is [`../aso/2026-10-07-duo/materials/`](../aso/2026-10-07-duo/materials/README.md).
An integrated local packet does not establish an upload, Apple acceptance,
review submission, or public release; those states require separate live records.

Each of `en-US`, `zh-Hans`, `ja`, and `zh-Hant` has 18 final PNGs: six ordinary
iPhone, six iPad, and six iPhone Duo images. The four localized sets total 72.
The 18 English images are also mirrored here at the root, byte for byte, for
existing local release consumers. Root copies are compatibility files, not
another locale or 18 additional uploads.

| Order | Filename suffix | Actual scene |
| --- | --- | --- |
| 01 | `01-html-report` | Locally rendered synthetic HTML weekly report |
| 02 | `02-markdown-preview` | Localized synthetic development notes with code and formula |
| 03 | `03-json-preview` | Built-in read-only JSON structure |
| 04 | `04-yaml-preview` | Built-in read-only YAML configuration in dark appearance |
| 05 | `05-batch-import` | Isolated showcase import results, four imported files |
| 06 | `06-library` | Two local templates and five built-in format examples |

Use `iphone-`, `ipad-`, or `duo-` prefixes, for example
`zh-Hant/duo-02-markdown-preview.png`. Source filenames retain their previous
scene keys; `order.json` in the packet explicitly maps source keys to the final
order. Do not infer source identity from the final number alone.

## Canvas and source proportions

- Ordinary iPhone: 1320 × 2868, portrait marketing canvas.
- iPad: 2064 × 2752, portrait marketing canvas.
- Duo inner: 2853 × 2007, actual Open landscape captures for HTML, JSON, and library.
- Duo outer: 1398 × 2034, actual Closed portrait captures for Markdown, YAML, and import.

Duo uses one six-image group with both inner and outer examples. This does not
promise automatic posture-specific storefront switching. The backend profile
and display class are `IPHONE_DUO_PROFILE` and `IPHONE_DUO`; no legacy ScreenshotSet
enum is guessed. Apple's other supported Duo orientations are 2007 × 2853
inner portrait and 2034 × 1398 outer landscape.

All upload PNGs are opaque 8-bit RGB with no alpha. The native source RGBA
images remain unchanged in the packet; the compositor fits each complete source
proportionally below a localized headline on the blue gradient. It neither
redraws UI nor stretches it. Mixed horizontal/vertical contact sheets also
preserve each image's own aspect ratio.

[Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
and [App Store asset management](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-your-app-store-assets/)
are the official dimension and asset references.

## Reproduce and verify

Capture uses `scripts/capture-aso-sources.sh` against one explicit existing
Booted device at a time. It does not build, install, boot, create, or change
Duo pose. The operator selects the actual pose and display; screenshots are
written to a unique `/tmp` directory and copied unchanged into the packet.
All fixture launches use `HTML_PREVIEWER_UI_TESTS=1` and the isolated test library.
Normal user documents are preserved. The 9:41 status override is cleared after
capture. Device shutdown is handled by the capture owner.

See the packet README for the exact four-language matrix and commands. After
all 72 sources are captured, generate the final PNGs with
`scripts/generate-app-store-screenshots.swift`, audit with
`scripts/audit-aso-materials.py`, and visually inspect the 12 contact sheets.
Record those inspections in `visual-review-<family>.json`, then run:

```sh
python3 scripts/generate-aso-provenance.py
python3 scripts/integrate-aso-materials.py
python3 scripts/integrate-aso-materials.py --apply
python3 scripts/audit-integrated-release-materials.py
```

Integration requires the complete current 72-image validation and unchanged
source hashes, keeps the original formal inputs in a unique local backup, and
preserves the historical 10/03 packet. Every final image maps to its actual
source, locale, pixels, device/display, capture time, and installed Debug
executable/debug dylib hashes. Mixed capture binaries remain explicit; Debug
screenshots are not claimed to originate from a signed Release archive.

The workflow uses the same canonical files in a GET-only modern assets gate
before archive and again before submission. Mutations use the separately
approved App Asset Library upload plan and exact app/version/locale/group scope.
Legacy Fastlane screenshot overwrite and duplicate deletion are disabled.

JSON is standard read-only JSON; no JSONC or JSON PDF export is implied. Library
search is filename search. The showcase import fixture demonstrates the result
UI and does not substitute for an actual Files-import regression. Historical
`verification-*.md/json` records describe their own releases and remain intact.
