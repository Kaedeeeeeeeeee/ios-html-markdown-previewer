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

write_checksums() {
  local checksum_path="$PACKET_DIR/Evidence/checksums-sha256.txt"

  mkdir -p "$(dirname "$checksum_path")"
  (
    cd "$PACKET_DIR"
    find . -type f ! -path "./Evidence/checksums-sha256.txt" -print |
      LC_ALL=C sort |
      while IFS= read -r file; do
        shasum -a 256 "$file" | sed 's# \./#  #'
      done
  ) > "$checksum_path"
}

latest_file() {
  local search_root="$1"
  local filename="$2"
  find "$search_root" -name "$filename" -print 2>/dev/null | sort | tail -n 1
}

report_field() {
  local label="$1"
  local path="$2"
  if [[ -f "$path" ]]; then
    awk -v prefix="- $label: " 'index($0, prefix) == 1 { print substr($0, length(prefix) + 1); exit }' "$path"
  fi
}

"$ROOT_DIR/scripts/serve-validation-samples.sh" --prepare-only >/dev/null
"$ROOT_DIR/scripts/prepare-usability-test-packet.sh" >/dev/null
"$ROOT_DIR/scripts/prepare-app-store-connect-run.sh" >/dev/null
"$ROOT_DIR/scripts/prepare-final-smoke-run.sh" >/dev/null

APP_STORE_CONNECT_RESULT="$(latest_file "$ROOT_DIR/DerivedData/AppStoreConnectRun" "app-store-connect-result.md")"
FINAL_SMOKE_RESULT="$(latest_file "$ROOT_DIR/DerivedData/FinalSmokeRun" "final-archive-smoke-result.md")"
PHYSICAL_DEVICE_RESULT="$(latest_file "$ROOT_DIR/DerivedData/PhysicalDeviceValidationRun" "physical-device-validation-result.md")"
ARCHIVE_SMOKE_REPORT="$(latest_file "$ROOT_DIR/DerivedData/PhysicalDeviceSmoke" "archive-device-smoke-report.md")"
PREFLIGHT_REPORT="$ROOT_DIR/DerivedData/FinalSubmissionPreflight/submission-readiness-report.md"
ARCHIVE_SMOKE_COMMIT_CHECK="$(report_field "Archive smoke commit check" "$FINAL_SMOKE_RESULT")"
ARCHIVE_SMOKE_COMMIT_CHECK="${ARCHIVE_SMOKE_COMMIT_CHECK:-commit freshness not recorded}"

if [[ -z "$APP_STORE_CONNECT_RESULT" || ! -f "$APP_STORE_CONNECT_RESULT" ]]; then
  printf 'Missing generated App Store Connect result draft.\n' >&2
  exit 1
fi

if [[ -z "$FINAL_SMOKE_RESULT" || ! -f "$FINAL_SMOKE_RESULT" ]]; then
  printf 'Missing generated final smoke result draft.\n' >&2
  exit 1
fi

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
- AppStoreConnect/app-store-connect-result-draft.md
- FinalSmoke/final-archive-smoke-result-draft.md
- FinalSmoke/ArchiveDeviceSmoke/ (when archive smoke evidence exists)
- Evidence/README.txt
- Evidence/release-evidence-index.md
- Evidence/checksums-sha256.txt
- Evidence/submission-readiness-report.md (when final preflight already ran)
- PhysicalDevice/physical-device-validation.md
- PhysicalDevice/physical-device-validation-result-template.md
- PhysicalDevice/physical-device-validation-result-draft.md (when staged)
- PhysicalDevice/LatestValidationRun/ (when staged)
- PhysicalDevice/HTMLPreviewerValidationSamples.zip
- PhysicalDevice/validation-download-index.html
- UsabilityTesting/HTMLPreviewerUsabilityTestPacket.zip
- UsabilityTesting/first-round-result-template.md
- Screenshots/
- PublicPages/privacy-policy.md
- PublicPages/support.md
- Compliance/privacy-required-reasons.md
- Compliance/export-compliance.md
- AppMetadata/PrivacyInfo.xcprivacy
- AppMetadata/AppIcon-1024x1024@1x.png
- Scripts/create-signed-archive.sh
- Scripts/final-submission-preflight.sh
- Scripts/prepare-app-store-connect-run.sh
- Scripts/prepare-final-smoke-run.sh
- Scripts/prepare-physical-device-validation-run.sh
- Scripts/run-archive-device-smoke.sh

Before submission, complete the physical-device and final archive/TestFlight
result templates and summarize them in the linked GitHub issues.
Only a distribution-signed archive produced without ALLOW_DEVELOPMENT_SIGNING=YES
counts as App Store/TestFlight upload evidence.
EOF

copy_file "$ROOT_DIR/docs/app-store-listing.md" "$PACKET_DIR/AppStore/app-store-listing.md"
copy_file "$ROOT_DIR/docs/app-store-connect-handoff.md" "$PACKET_DIR/AppStore/app-store-connect-handoff.md"
copy_file "$ROOT_DIR/docs/app-store-submission-runbook.md" "$PACKET_DIR/AppStore/app-store-submission-runbook.md"
copy_file "$ROOT_DIR/docs/release-checklist.md" "$PACKET_DIR/AppStore/release-checklist.md"
copy_file "$ROOT_DIR/docs/final-archive-smoke-test-template.md" "$PACKET_DIR/AppStore/final-archive-smoke-test-template.md"

copy_file "$APP_STORE_CONNECT_RESULT" "$PACKET_DIR/AppStoreConnect/app-store-connect-result-draft.md"
copy_file "$FINAL_SMOKE_RESULT" "$PACKET_DIR/FinalSmoke/final-archive-smoke-result-draft.md"
if [[ -n "$ARCHIVE_SMOKE_REPORT" && -f "$ARCHIVE_SMOKE_REPORT" ]]; then
  copy_dir "$(dirname "$ARCHIVE_SMOKE_REPORT")" "$PACKET_DIR/FinalSmoke/ArchiveDeviceSmoke"
fi

mkdir -p "$PACKET_DIR/Evidence"
cat > "$PACKET_DIR/Evidence/README.txt" <<EOF
Submission evidence

Run scripts/final-submission-preflight.sh on the final commit before upload.
When a preflight report already exists, this packet includes it as:

- Evidence/submission-readiness-report.md

Use Evidence/release-evidence-index.md as the portable entry point for copied
evidence paths inside the packet.

The final-submission-preflight script also refreshes this release packet with
the current report after all local gates finish.
EOF

if [[ -f "$PREFLIGHT_REPORT" ]]; then
  copy_file "$PREFLIGHT_REPORT" "$PACKET_DIR/Evidence/submission-readiness-report.md"
fi

{
  printf '# Release Evidence Index\n\n'
  printf -- '- Generated from commit: %s\n' "$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
  printf -- '- Release packet: `HTMLPreviewerReleasePacket.zip`\n'
  printf -- '- Source reports may contain local absolute paths from the machine that generated them. Use the packet-relative paths below when reviewing this packet outside the source checkout.\n'
  printf '\n## Packet Evidence\n\n'
  printf '| Evidence | Packet-relative path | Status |\n'
  printf '|---|---|---|\n'
  printf '| Final preflight report | `Evidence/submission-readiness-report.md` | %s |\n' "$(if [[ -f "$PREFLIGHT_REPORT" ]]; then printf 'Included'; else printf 'Not generated before packet staging'; fi)"
  printf '| Packet checksums | `Evidence/checksums-sha256.txt` | Generated during packet staging |\n'
  printf '| App Store Connect setup draft | `AppStoreConnect/app-store-connect-result-draft.md` | Included |\n'
  printf '| Final archive/TestFlight smoke draft | `FinalSmoke/final-archive-smoke-result-draft.md` | Included |\n'
  if [[ -n "$PHYSICAL_DEVICE_RESULT" && -f "$PHYSICAL_DEVICE_RESULT" ]]; then
    printf '| Physical-device validation draft | `PhysicalDevice/physical-device-validation-result-draft.md` | Included, still requires manual matrix completion |\n'
    printf '| Physical-device validation run folder | `PhysicalDevice/LatestValidationRun/` | Included with device list snapshot and staged samples |\n'
  else
    printf '| Physical-device validation draft | `PhysicalDevice/physical-device-validation-result-draft.md` | Not staged locally |\n'
    printf '| Physical-device validation run folder | `PhysicalDevice/LatestValidationRun/` | Not staged locally |\n'
  fi
  printf '| Physical-device validation samples | `PhysicalDevice/HTMLPreviewerValidationSamples.zip` | Included |\n'
  printf '| Browser delivery page | `PhysicalDevice/validation-download-index.html` | Included |\n'
  if [[ -n "$ARCHIVE_SMOKE_REPORT" && -f "$ARCHIVE_SMOKE_REPORT" ]]; then
    printf '| Archive device smoke report | `FinalSmoke/ArchiveDeviceSmoke/archive-device-smoke-report.md` | Included; %s |\n' "$ARCHIVE_SMOKE_COMMIT_CHECK"
    printf '| Archive device smoke logs | `FinalSmoke/ArchiveDeviceSmoke/` | Included when produced by `scripts/run-archive-device-smoke.sh` |\n'
  else
    printf '| Archive device smoke report | `FinalSmoke/ArchiveDeviceSmoke/archive-device-smoke-report.md` | Not staged locally |\n'
  fi
  printf '| Usability test packet | `UsabilityTesting/HTMLPreviewerUsabilityTestPacket.zip` | Included, still requires external participant run |\n'
  printf '\n## External Gates Still Required\n\n'
  printf -- '- Complete physical-device external-open validation on an unlocked real iPhone and fill `PhysicalDevice/physical-device-validation-result-draft.md`.\n'
  printf -- '- Complete App Store Connect paid-download setup and fill `AppStoreConnect/app-store-connect-result-draft.md`.\n'
  printf -- '- Upload/select the processed App Store Connect build, then complete final archive/TestFlight smoke using `FinalSmoke/final-archive-smoke-result-draft.md`.\n'
  printf -- '- Run the first external usability round and record the result under the issue #11 materials.\n'
} > "$PACKET_DIR/Evidence/release-evidence-index.md"

copy_file "$ROOT_DIR/docs/physical-device-validation.md" "$PACKET_DIR/PhysicalDevice/physical-device-validation.md"
copy_file "$ROOT_DIR/docs/physical-device-validation-result-template.md" "$PACKET_DIR/PhysicalDevice/physical-device-validation-result-template.md"
if [[ -n "$PHYSICAL_DEVICE_RESULT" && -f "$PHYSICAL_DEVICE_RESULT" ]]; then
  copy_file "$PHYSICAL_DEVICE_RESULT" "$PACKET_DIR/PhysicalDevice/physical-device-validation-result-draft.md"
  copy_dir "$(dirname "$PHYSICAL_DEVICE_RESULT")" "$PACKET_DIR/PhysicalDevice/LatestValidationRun"
fi
copy_file "$ROOT_DIR/DerivedData/ValidationSamples/HTMLPreviewerValidationSamples.zip" "$PACKET_DIR/PhysicalDevice/HTMLPreviewerValidationSamples.zip"
copy_file "$ROOT_DIR/DerivedData/ValidationSamples/index.html" "$PACKET_DIR/PhysicalDevice/validation-download-index.html"
copy_file "$ROOT_DIR/DerivedData/ValidationSamples/README-browser-delivery.txt" "$PACKET_DIR/PhysicalDevice/README-browser-delivery.txt"

copy_file "$ROOT_DIR/docs/usability-testing/README.md" "$PACKET_DIR/UsabilityTesting/README.md"
copy_file "$ROOT_DIR/docs/usability-testing/script.md" "$PACKET_DIR/UsabilityTesting/script.md"
copy_file "$ROOT_DIR/docs/usability-testing/observation-template.md" "$PACKET_DIR/UsabilityTesting/observation-template.md"
copy_file "$ROOT_DIR/docs/usability-testing/first-round-result-template.md" "$PACKET_DIR/UsabilityTesting/first-round-result-template.md"
copy_file "$ROOT_DIR/DerivedData/UsabilityTestPacket/HTMLPreviewerUsabilityTestPacket.zip" "$PACKET_DIR/UsabilityTesting/HTMLPreviewerUsabilityTestPacket.zip"

copy_file "$ROOT_DIR/docs/privacy-policy.md" "$PACKET_DIR/PublicPages/privacy-policy.md"
copy_file "$ROOT_DIR/docs/support.md" "$PACKET_DIR/PublicPages/support.md"

copy_file "$ROOT_DIR/docs/privacy-required-reasons.md" "$PACKET_DIR/Compliance/privacy-required-reasons.md"
copy_file "$ROOT_DIR/docs/export-compliance.md" "$PACKET_DIR/Compliance/export-compliance.md"

copy_file "$ROOT_DIR/HTMLMarkdownPreviewer/PrivacyInfo.xcprivacy" "$PACKET_DIR/AppMetadata/PrivacyInfo.xcprivacy"
copy_file "$ROOT_DIR/HTMLMarkdownPreviewer/Assets.xcassets/AppIcon.appiconset/AppIcon-1024x1024@1x.png" "$PACKET_DIR/AppMetadata/AppIcon-1024x1024@1x.png"

copy_dir "$ROOT_DIR/docs/app-store-screenshots" "$PACKET_DIR/Screenshots"

copy_file "$ROOT_DIR/scripts/create-signed-archive.sh" "$PACKET_DIR/Scripts/create-signed-archive.sh"
copy_file "$ROOT_DIR/scripts/final-submission-preflight.sh" "$PACKET_DIR/Scripts/final-submission-preflight.sh"
copy_file "$ROOT_DIR/scripts/archive-preflight.sh" "$PACKET_DIR/Scripts/archive-preflight.sh"
copy_file "$ROOT_DIR/scripts/release-audit.sh" "$PACKET_DIR/Scripts/release-audit.sh"
copy_file "$ROOT_DIR/scripts/release-device-build.sh" "$PACKET_DIR/Scripts/release-device-build.sh"
copy_file "$ROOT_DIR/scripts/prepare-app-store-connect-run.sh" "$PACKET_DIR/Scripts/prepare-app-store-connect-run.sh"
copy_file "$ROOT_DIR/scripts/prepare-final-smoke-run.sh" "$PACKET_DIR/Scripts/prepare-final-smoke-run.sh"
copy_file "$ROOT_DIR/scripts/prepare-physical-device-validation-run.sh" "$PACKET_DIR/Scripts/prepare-physical-device-validation-run.sh"
copy_file "$ROOT_DIR/scripts/run-archive-device-smoke.sh" "$PACKET_DIR/Scripts/run-archive-device-smoke.sh"
copy_file "$ROOT_DIR/scripts/verify-public-pages.sh" "$PACKET_DIR/Scripts/verify-public-pages.sh"
copy_file "$ROOT_DIR/scripts/prepare-usability-test-packet.sh" "$PACKET_DIR/Scripts/prepare-usability-test-packet.sh"
copy_file "$ROOT_DIR/scripts/prepare-validation-samples.sh" "$PACKET_DIR/Scripts/prepare-validation-samples.sh"
copy_file "$ROOT_DIR/scripts/serve-validation-samples.sh" "$PACKET_DIR/Scripts/serve-validation-samples.sh"

write_checksums

(
  cd "$OUTPUT_ROOT"
  zip -qry -X "HTMLPreviewerReleasePacket.zip" "HTMLPreviewerReleasePacket"
)

printf 'Prepared release packet folder: %s\n' "$PACKET_DIR"
printf 'Prepared release packet package: %s\n' "$ZIP_PATH"
