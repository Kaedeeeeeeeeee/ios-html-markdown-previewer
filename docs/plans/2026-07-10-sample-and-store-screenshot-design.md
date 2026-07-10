# Rich Samples and Localized App Store Screenshots

## Decision

Use real simulator captures as the product proof, then place them in a deterministic marketing canvas. The first release keeps five screenshots: home, HTML, Markdown, ZIP, and privacy/settings. Each screenshot is exported for iPhone and iPad in `en-US`, `zh-Hans`, and `ja`.

Three approaches were considered:

1. **Deterministic composition from real screenshots (selected).** Product UI remains exact, localized copy is reliable, and every asset can be regenerated after an app change.
2. Generative redesign of the screenshots. This can create expressive backgrounds, but it risks changing the UI, corrupting text, and showing features that do not exist.
3. Raw simulator screenshots only. This is accurate and simple, but it does not explain the product or create a coherent App Store story.

The selected visual direction follows the app icon: saturated blue, deep indigo, clean white typography, soft luminous geometry, and a large device crop. Text remains short. The screenshot inside the device is English for every storefront; only the marketing headline and supporting line change by storefront.

## Sample architecture

The single-file HTML sample becomes a self-contained responsive analytics scene built from inline CSS and SVG. It demonstrates gradients, grid layout, glass-like cards, inline vector graphics, responsive behavior, and CSS-only motion. It must not load network resources or require JavaScript. A `prefers-reduced-motion` rule removes animation when the system requests it.

The ZIP sample becomes a polished report package. `index.html` references a local stylesheet and a local SVG chart inside the ZIP, proving that relative assets survive extraction and render together. Existing ZIP safety and size constraints are unchanged.

Automated tests continue to import every sample. Additional assertions verify that the HTML sample contains inline SVG and CSS animation, that it contains no remote URL, and that the ZIP package still has exactly three safe local entries.

## Screenshot pipeline

The capture script records one English source set from iPhone and iPad simulators. A Swift/AppKit compositor then produces the final App Store PNGs at Apple's existing dimensions:

- iPhone: 1320 x 2868
- iPad: 2064 x 2752

The compositor owns all marketing copy in a small locale manifest and creates three output directories plus the root English compatibility copies used by release audits. It validates source dimensions, output dimensions, locale coverage, and filenames. The final five-message sequence is:

1. Open HTML, Markdown, and ZIP files.
2. Render rich HTML layouts, graphics, and CSS motion.
3. Read Markdown with clean native typography.
4. Preserve local CSS and images in ZIP reports.
5. Keep processing on-device with no account or ads.

## Verification

Run the sample-provider tests, the complete iOS test suite, the screenshot generator against freshly captured simulator sources, PNG dimension checks, and the release audits. Visually inspect contact sheets for all three storefronts and both device families before treating the assets as upload-ready.
