#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAMPLES_DIR="$ROOT_DIR/docs/usability-testing/samples"
OUTPUT_ROOT="$ROOT_DIR/DerivedData/UsabilityTestPacket"
PACKET_DIR="$OUTPUT_ROOT/HTMLPreviewerUsabilityTestPacket"
ZIP_PATH="$OUTPUT_ROOT/HTMLPreviewerUsabilityTestPacket.zip"

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

copy_file() {
  local source="$1"
  local destination="$2"
  mkdir -p "$(dirname "$destination")"
  cp "$source" "$destination"
}

rm -rf "$PACKET_DIR" "$ZIP_PATH"
mkdir -p "$PACKET_DIR/Samples"

cat > "$PACKET_DIR/README.txt" <<EOF
HTML Previewer first-round usability test packet

Generated from commit: $(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || printf 'unknown')

Use this packet with at least one external participant on a physical iPhone.

Recommended flow:
1. Install the latest local archive or TestFlight build.
2. Move the files in Samples/ onto the device through Files, Mail, AirDrop,
   iCloud Drive, Safari downloads, or a messaging app.
3. Run script.md.
4. Record observations in observation-template.md.
5. Record the final session decision in first-round-result-template.md.
6. File or fix every P0/P1 finding before closing issue #11.

Do not record participant names, contact details, payment details, or private
file contents in this repository.
EOF

copy_file "$ROOT_DIR/docs/usability-testing/README.md" "$PACKET_DIR/README-usability.md"
copy_file "$ROOT_DIR/docs/usability-testing/script.md" "$PACKET_DIR/script.md"
copy_file "$ROOT_DIR/docs/usability-testing/observation-template.md" "$PACKET_DIR/observation-template.md"
copy_file "$ROOT_DIR/docs/usability-testing/first-round-result-template.md" "$PACKET_DIR/first-round-result-template.md"
copy_file "$ROOT_DIR/docs/app-store-listing.md" "$PACKET_DIR/AppStore/app-store-listing.md"
copy_file "$ROOT_DIR/docs/privacy-policy.md" "$PACKET_DIR/AppStore/privacy-policy.md"

for filename in "${sample_files[@]}"; do
  copy_file "$SAMPLES_DIR/$filename" "$PACKET_DIR/Samples/$filename"
done

(
  cd "$OUTPUT_ROOT"
  zip -qry -X "HTMLPreviewerUsabilityTestPacket.zip" "HTMLPreviewerUsabilityTestPacket"
)

printf 'Prepared usability test packet folder: %s\n' "$PACKET_DIR"
printf 'Prepared usability test packet package: %s\n' "$ZIP_PATH"
