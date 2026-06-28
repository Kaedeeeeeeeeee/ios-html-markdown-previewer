#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_ROOT="$ROOT_DIR/DerivedData/ReleasePacket"
PACKET_DIR="$OUTPUT_ROOT/HTMLPreviewerReleasePacket"
ZIP_PATH="$OUTPUT_ROOT/HTMLPreviewerReleasePacket.zip"

copy_file() {
  local source="$1"
  local destination="$2"
  mkdir -p "$(dirname "$destination")"
  cp "$source" "$destination"
}

copy_dir() {
  local source="$1"
  local destination="$2"
  rm -rf "$destination"
  mkdir -p "$(dirname "$destination")"
  cp -R "$source" "$destination"
}

"$ROOT_DIR/scripts/prepare-validation-samples.sh" >/dev/null

rm -rf "$PACKET_DIR" "$ZIP_PATH"
mkdir -p "$PACKET_DIR"

cat > "$PACKET_DIR/README.txt" <<EOF
HTML Previewer release packet

Generated from commit: $(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || printf 'unknown')

Use this packet for App Store Connect entry, physical-device validation,
final archive/TestFlight smoke testing, and App Review handoff.

Key files:
- AppStore/app-store-listing.md
- AppStore/app-store-connect-handoff.md
- AppStore/app-store-submission-runbook.md
- AppStore/release-checklist.md
- AppStore/final-archive-smoke-test-template.md
- PhysicalDevice/physical-device-validation.md
- PhysicalDevice/physical-device-validation-result-template.md
- PhysicalDevice/HTMLPreviewerValidationSamples.zip
- Screenshots/
- PublicPages/privacy-policy.md
- PublicPages/support.md
- Compliance/privacy-required-reasons.md
- Compliance/export-compliance.md
- AppMetadata/PrivacyInfo.xcprivacy
- AppMetadata/AppIcon-1024x1024@1x.png
- Scripts/create-signed-archive.sh

Before submission, complete the physical-device and final archive/TestFlight
result templates and summarize them in the linked GitHub issues.
EOF

copy_file "$ROOT_DIR/docs/app-store-listing.md" "$PACKET_DIR/AppStore/app-store-listing.md"
copy_file "$ROOT_DIR/docs/app-store-connect-handoff.md" "$PACKET_DIR/AppStore/app-store-connect-handoff.md"
copy_file "$ROOT_DIR/docs/app-store-submission-runbook.md" "$PACKET_DIR/AppStore/app-store-submission-runbook.md"
copy_file "$ROOT_DIR/docs/release-checklist.md" "$PACKET_DIR/AppStore/release-checklist.md"
copy_file "$ROOT_DIR/docs/final-archive-smoke-test-template.md" "$PACKET_DIR/AppStore/final-archive-smoke-test-template.md"

copy_file "$ROOT_DIR/docs/physical-device-validation.md" "$PACKET_DIR/PhysicalDevice/physical-device-validation.md"
copy_file "$ROOT_DIR/docs/physical-device-validation-result-template.md" "$PACKET_DIR/PhysicalDevice/physical-device-validation-result-template.md"
copy_file "$ROOT_DIR/DerivedData/ValidationSamples/HTMLPreviewerValidationSamples.zip" "$PACKET_DIR/PhysicalDevice/HTMLPreviewerValidationSamples.zip"

copy_file "$ROOT_DIR/docs/usability-testing/README.md" "$PACKET_DIR/UsabilityTesting/README.md"
copy_file "$ROOT_DIR/docs/usability-testing/script.md" "$PACKET_DIR/UsabilityTesting/script.md"
copy_file "$ROOT_DIR/docs/usability-testing/observation-template.md" "$PACKET_DIR/UsabilityTesting/observation-template.md"

copy_file "$ROOT_DIR/docs/privacy-policy.md" "$PACKET_DIR/PublicPages/privacy-policy.md"
copy_file "$ROOT_DIR/docs/support.md" "$PACKET_DIR/PublicPages/support.md"

copy_file "$ROOT_DIR/docs/privacy-required-reasons.md" "$PACKET_DIR/Compliance/privacy-required-reasons.md"
copy_file "$ROOT_DIR/docs/export-compliance.md" "$PACKET_DIR/Compliance/export-compliance.md"

copy_file "$ROOT_DIR/HTMLMarkdownPreviewer/PrivacyInfo.xcprivacy" "$PACKET_DIR/AppMetadata/PrivacyInfo.xcprivacy"
copy_file "$ROOT_DIR/HTMLMarkdownPreviewer/Assets.xcassets/AppIcon.appiconset/AppIcon-1024x1024@1x.png" "$PACKET_DIR/AppMetadata/AppIcon-1024x1024@1x.png"

copy_dir "$ROOT_DIR/docs/app-store-screenshots" "$PACKET_DIR/Screenshots"

copy_file "$ROOT_DIR/scripts/create-signed-archive.sh" "$PACKET_DIR/Scripts/create-signed-archive.sh"
copy_file "$ROOT_DIR/scripts/archive-preflight.sh" "$PACKET_DIR/Scripts/archive-preflight.sh"
copy_file "$ROOT_DIR/scripts/release-audit.sh" "$PACKET_DIR/Scripts/release-audit.sh"
copy_file "$ROOT_DIR/scripts/release-device-build.sh" "$PACKET_DIR/Scripts/release-device-build.sh"
copy_file "$ROOT_DIR/scripts/verify-public-pages.sh" "$PACKET_DIR/Scripts/verify-public-pages.sh"
copy_file "$ROOT_DIR/scripts/prepare-validation-samples.sh" "$PACKET_DIR/Scripts/prepare-validation-samples.sh"

(
  cd "$OUTPUT_ROOT"
  zip -qry -X "HTMLPreviewerReleasePacket.zip" "HTMLPreviewerReleasePacket"
)

printf 'Prepared release packet folder: %s\n' "$PACKET_DIR"
printf 'Prepared release packet package: %s\n' "$ZIP_PATH"
