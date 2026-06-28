#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAMPLES_DIR="$ROOT_DIR/docs/usability-testing/samples"
OUTPUT_ROOT="$ROOT_DIR/DerivedData/ValidationSamples"
STAGING_DIR="$OUTPUT_ROOT/HTMLPreviewerValidationSamples"
ZIP_PATH="$OUTPUT_ROOT/HTMLPreviewerValidationSamples.zip"

sample_files=(
  "basic-report.html"
  "legacy-report.htm"
  "markdown-notes.md"
  "markdown-reference.markdown"
  "zip-report.zip"
  "external-resource.html"
  "interactive-trusted.html"
  "broken.zip"
)

rm -rf "$STAGING_DIR" "$ZIP_PATH"
mkdir -p "$STAGING_DIR"

for filename in "${sample_files[@]}"; do
  cp "$SAMPLES_DIR/$filename" "$STAGING_DIR/$filename"
done

cat > "$STAGING_DIR/README.txt" <<'EOF'
HTML Previewer validation samples

Use these files for physical-device external-open and first-round usability testing.

Primary extension matrix:
- .html: basic-report.html
- .htm: legacy-report.htm
- .md: markdown-notes.md
- .markdown: markdown-reference.markdown
- .zip: zip-report.zip

Additional safety and error-path samples:
- external-resource.html verifies Safe Preview external resource blocking.
- interactive-trusted.html verifies Safe Preview vs Interactive mode behavior.
- broken.zip verifies the invalid ZIP error path.

If this folder is distributed as HTMLPreviewerValidationSamples.zip, first expand it in Files.
Do not use the outer distribution ZIP as the app's ZIP-import test file; use zip-report.zip.
EOF

(
  cd "$OUTPUT_ROOT"
  zip -qry -X "HTMLPreviewerValidationSamples.zip" "HTMLPreviewerValidationSamples"
)

printf 'Prepared validation sample folder: %s\n' "$STAGING_DIR"
printf 'Prepared validation sample package: %s\n' "$ZIP_PATH"
