# App Store screenshots for 1.7.1

The current upload set contains four languages (`en-US`, `zh-Hans`, `ja`, `zh-Hant`), with six iPhone and six iPad PNGs per language: 48 localized images. Root-level PNGs are byte-identical English compatibility copies and are excluded from upload staging.

The six slots are:

1. `01-html-report`: a synthetic weekly report shown in the actual app.
2. `02-markdown-preview`: code and mathematics in the actual Markdown reader.
3. `03-json-preview`: read-only JSON structure.
4. `04-yaml-preview`: YAML configuration structure.
5. `05-batch-import`: import outcomes and failure reasons.
6. `06-library`: pinned files and filename search.

Images are opaque RGB PNGs at 1320 × 2868 for iPhone and 2064 × 2752 for iPad. The compositor preserves the source UI proportions.

The original source captures, fixtures, contact sheets, and capture provenance are preserved in [the ASO package](../aso/2026-10-03/materials/README.md). Source filenames deliberately keep their previous keys; final image names encode the new upload order. The screenshots use Debug UI-test fixtures and do not prove final Release archive equivalence or an actual Files import.

The 1.7.1 integration audit checks exact inventory, dimensions, opacity, source-package hashes, copy, and upload order. Version 1.7 verification files remain historical evidence. Capture is unnecessary for unchanged surfaces, but a UI change requires new captures before submission.

The default capture helper uses built-in samples. Regenerating these specific marketing scenes requires the ASO report and Markdown fixtures; follow its package instructions. Do not replace them with built-in examples while retaining these captions.

No App Store Connect assets have been changed by this preparation.
