#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT_DIR/DerivedData/PhysicalDeviceValidationRun}"
DEVICE="${DEVICE:-}"
BUILD_SOURCE="${BUILD_SOURCE:-}"
IOS_VERSION="${IOS_VERSION:-}"
TESTER="${TESTER:-}"
REGION_LANGUAGE="${REGION_LANGUAGE:-}"
NETWORK_STATE="${NETWORK_STATE:-}"
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: scripts/prepare-physical-device-validation-run.sh [options]

Stages the physical-device external-open validation samples and creates a
pre-filled result draft for issue #1. This does not run the validation; it
prepares the evidence folder for a tester to complete on a physical iPhone.

Environment:
  OUTPUT_ROOT       Optional output root. Defaults to DerivedData/PhysicalDeviceValidationRun.
  DEVICE            Optional physical iPhone name/model.
  BUILD_SOURCE      Optional build source, e.g. Xcode run, local archive, or TestFlight.
  IOS_VERSION       Optional iOS version.
  TESTER            Optional tester name or initials.
  REGION_LANGUAGE   Optional region/language note.
  NETWORK_STATE     Optional network state.

Options:
  --device VALUE           Physical iPhone name/model.
  --build-source VALUE     Xcode run, local archive, or TestFlight.
  --ios-version VALUE      iOS version.
  --tester VALUE           Tester name or initials.
  --region-language VALUE  Region/language note.
  --network-state VALUE    Wi-Fi, cellular, or offline.
  --dry-run                Print planned output without writing files.
  -h, --help               Show this help.
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --device)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        printf 'Missing value for --device.\n' >&2
        exit 2
      fi
      DEVICE="$2"
      shift 2
      ;;
    --build-source)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        printf 'Missing value for --build-source.\n' >&2
        exit 2
      fi
      BUILD_SOURCE="$2"
      shift 2
      ;;
    --ios-version)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        printf 'Missing value for --ios-version.\n' >&2
        exit 2
      fi
      IOS_VERSION="$2"
      shift 2
      ;;
    --tester)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        printf 'Missing value for --tester.\n' >&2
        exit 2
      fi
      TESTER="$2"
      shift 2
      ;;
    --region-language)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        printf 'Missing value for --region-language.\n' >&2
        exit 2
      fi
      REGION_LANGUAGE="$2"
      shift 2
      ;;
    --network-state)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        printf 'Missing value for --network-state.\n' >&2
        exit 2
      fi
      NETWORK_STATE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_value_or_placeholder() {
  local value="$1"
  local placeholder="$2"
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
  else
    printf '%s' "$placeholder"
  fi
}

safe_slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-'
}

git_value() {
  git -C "$ROOT_DIR" "$@" 2>/dev/null || printf 'unknown'
}

build_setting() {
  local key="$1"
  xcodebuild -project "$ROOT_DIR/HTMLMarkdownPreviewer.xcodeproj" \
    -scheme HTMLMarkdownPreviewer \
    -configuration Release \
    -showBuildSettings 2>/dev/null |
    awk -v key="$key" '$1 == key && $2 == "=" { print $3; exit }'
}

commit_short="$(git_value rev-parse --short HEAD)"
commit_full="$(git_value rev-parse HEAD)"
branch="$(git_value branch --show-current)"
app_version="$(build_setting MARKETING_VERSION)"
build_number="$(build_setting CURRENT_PROJECT_VERSION)"
app_version="${app_version:-unknown}"
build_number="${build_number:-unknown}"

date_stamp="$(date -u '+%Y-%m-%d')"
timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
device_label="$(require_value_or_placeholder "$DEVICE" "device")"
device_slug="$(safe_slug "$device_label")"
run_dir="$OUTPUT_ROOT/$timestamp-$device_slug"
result_path="$run_dir/physical-device-validation-result.md"
samples_zip="$run_dir/HTMLPreviewerValidationSamples.zip"
samples_dir="$run_dir/HTMLPreviewerValidationSamples"
device_list_path="$run_dir/devicectl-devices.txt"
README_PATH="$run_dir/README.txt"

if [[ "$DRY_RUN" == true ]]; then
  printf 'Would prepare physical-device validation run:\n'
  printf -- '- Result draft: %s\n' "$result_path"
  printf -- '- Samples zip: %s\n' "$samples_zip"
  printf -- '- Samples folder: %s\n' "$samples_dir"
  printf -- '- Device list: %s\n' "$device_list_path"
  exit 0
fi

"$ROOT_DIR/scripts/prepare-validation-samples.sh" >/dev/null

rm -rf "$run_dir"
mkdir -p "$run_dir"
cp "$ROOT_DIR/DerivedData/ValidationSamples/HTMLPreviewerValidationSamples.zip" "$samples_zip"
cp -R "$ROOT_DIR/DerivedData/ValidationSamples/HTMLPreviewerValidationSamples" "$samples_dir"

if xcrun devicectl list devices >"$device_list_path" 2>&1; then
  :
else
  printf 'devicectl device listing failed; continue manually.\n' >"$device_list_path"
fi

tester_value="$(require_value_or_placeholder "$TESTER" "TBD")"
build_source_value="$(require_value_or_placeholder "$BUILD_SOURCE" "Xcode run / local archive / TestFlight")"
device_value="$(require_value_or_placeholder "$DEVICE" "TBD physical iPhone")"
ios_version_value="$(require_value_or_placeholder "$IOS_VERSION" "TBD")"
region_language_value="$(require_value_or_placeholder "$REGION_LANGUAGE" "TBD")"
network_state_value="$(require_value_or_placeholder "$NETWORK_STATE" "Wi-Fi / cellular / offline")"

cat > "$result_path" <<EOF
# Physical Device Validation Result

Issue: #1

## Run Metadata

- Date: $date_stamp
- Tester: $tester_value
- Commit: $commit_short ($commit_full)
- Branch: $branch
- Build source: $build_source_value
- App version: $app_version
- Build number: $build_number
- Device: $device_value
- iOS version: $ios_version_value
- Region/language: $region_language_value
- Network state: $network_state_value
- Validation samples: \`$samples_zip\`
- Device list snapshot: \`$device_list_path\`

## Source Apps Tested

| Source | App/version | Account state | Notes |
|---|---|---|---|
| Files local |  |  |  |
| iCloud Drive |  |  |  |
| Mail attachment |  |  |  |
| AirDrop |  |  |  |
| Messaging app |  |  |  |
| Safari download |  |  |  |

## External Open Matrix

Use:

- \`basic-report.html\` for \`.html\`
- \`legacy-report.htm\` for \`.htm\`
- \`markdown-notes.md\` for \`.md\`
- \`markdown-reference.markdown\` for \`.markdown\`
- \`zip-report.zip\` for \`.zip\`

Mark each cell as Pass, Fail, Not available, or Not tested. Include exact source-app wording if HTML Previewer appears under a different menu label.

| Source | .html | .htm | .md | .markdown | .zip | Notes |
|---|---|---|---|---|---|---|
| Files local |  |  |  |  |  |  |
| iCloud Drive |  |  |  |  |  |  |
| Mail attachment |  |  |  |  |  |  |
| AirDrop |  |  |  |  |  |  |
| Messaging app |  |  |  |  |  |  |
| Safari download |  |  |  |  |  |  |

## Import And Preview Checks

Run these checks for at least one successful import per document type.

| Check | Pass/Fail | Evidence/notes |
|---|---|---|
| App appears as an open/share target |  |  |
| File imports into app sandbox |  |  |
| App navigates to preview after import |  |  |
| HTML Safe Preview renders local content |  |  |
| Markdown renders formatted content |  |  |
| ZIP opens the selected entry HTML |  |  |
| ZIP loads same-package CSS/images |  |  |
| Recent list shows imported file |  |  |
| Recent item reopens successfully |  |  |
| Delete removes recent item and imported data |  |  |

## Safety And Error Path Checks

| Sample | Expected result | Pass/Fail | Notes |
|---|---|---|---|
| \`external-resource.html\` | Safe Preview blocks remote http/https resources by default |  |  |
| \`interactive-trusted.html\` | Safe Preview disables JavaScript; Interactive mode works only after user switches |  |  |
| \`broken.zip\` | App shows a clear invalid ZIP error and leaves no broken recent item |  |  |

## Source-Specific Caveats

Record any source-specific behavior that should be documented in App Review notes, support docs, or follow-up issues.

| Source | Caveat | User impact | Follow-up |
|---|---|---|---|
|  |  |  |  |

## Blocking Failures

| Priority | Failure | Source/file | Reproduction steps | Follow-up issue |
|---|---|---|---|---|
| P0/P1/P2 |  |  |  |  |

Priority guide:

- P0: Blocks opening or previewing supported files from common source apps.
- P1: Supported flow works only through confusing or fragile steps that need product/docs changes.
- P2: Source-specific polish or documentation gap that does not block submission.

## Result

- Overall status: pending / passed / failed
- Can close #1: yes / no
- Can continue App Store submission: yes / no
- Follow-up issues:

## Issue Comment Draft

\`\`\`text
Physical-device validation result:

- Commit: $commit_short
- Build source: $build_source_value
- Device/iOS: $device_value / $ios_version_value
- Sources tested:
- Overall status:

Passed:
- 

Caveats:
- 

Blocking failures:
- 

Follow-ups:
- 
\`\`\`
EOF

cat > "$README_PATH" <<EOF
HTML Previewer physical-device validation run

Generated: $timestamp
Commit: $commit_short

Files:
- physical-device-validation-result.md
- HTMLPreviewerValidationSamples.zip
- HTMLPreviewerValidationSamples/
- devicectl-devices.txt

Next:
1. Move the individual sample files onto a physical iPhone through Files,
   iCloud Drive, Mail, AirDrop, a messaging app, and Safari downloads.
2. Fill physical-device-validation-result.md while testing the source matrix.
3. Copy the completed result into docs/physical-device-validation-results/ or
   keep this DerivedData folder with release evidence.
4. Summarize the result in GitHub issue #1.
EOF

printf 'Prepared physical-device validation run folder: %s\n' "$run_dir"
printf 'Prepared result draft: %s\n' "$result_path"
printf 'Prepared validation samples: %s\n' "$samples_zip"
