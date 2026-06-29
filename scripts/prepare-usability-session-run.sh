#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT_DIR/DerivedData/UsabilitySessionRun}"
PARTICIPANT_CODE="${PARTICIPANT_CODE:-}"
MODERATOR="${MODERATOR:-}"
DEVICE="${DEVICE:-}"
BUILD_SOURCE="${BUILD_SOURCE:-}"
IOS_VERSION="${IOS_VERSION:-}"
REGION_LANGUAGE="${REGION_LANGUAGE:-}"
SOURCE_APPS="${SOURCE_APPS:-}"
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: scripts/prepare-usability-session-run.sh [options]

Stages a first-round usability session folder and creates pre-filled result and
observation drafts for issue #11. This does not run the session; it prepares
the evidence folder for an external participant test on a physical iPhone.

Environment:
  OUTPUT_ROOT        Optional output root. Defaults to DerivedData/UsabilitySessionRun.
  PARTICIPANT_CODE  Optional anonymized participant code, e.g. P01.
  MODERATOR         Optional moderator initials.
  DEVICE            Optional physical iPhone name/model.
  BUILD_SOURCE      Optional build source, e.g. local archive or TestFlight.
  IOS_VERSION       Optional iOS version.
  REGION_LANGUAGE   Optional region/language note.
  SOURCE_APPS       Optional source app list.

Options:
  --participant-code VALUE  Anonymized participant code, e.g. P01.
  --moderator VALUE         Moderator initials.
  --device VALUE            Physical iPhone name/model.
  --build-source VALUE      Xcode run, local archive, or TestFlight.
  --ios-version VALUE       iOS version.
  --region-language VALUE   Region/language note.
  --source-apps VALUE       Source apps available/tested.
  --dry-run                 Print planned output without writing files.
  -h, --help                Show this help.
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --participant-code)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        printf 'Missing value for --participant-code.\n' >&2
        exit 2
      fi
      PARTICIPANT_CODE="$2"
      shift 2
      ;;
    --moderator)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        printf 'Missing value for --moderator.\n' >&2
        exit 2
      fi
      MODERATOR="$2"
      shift 2
      ;;
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
    --region-language)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        printf 'Missing value for --region-language.\n' >&2
        exit 2
      fi
      REGION_LANGUAGE="$2"
      shift 2
      ;;
    --source-apps)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        printf 'Missing value for --source-apps.\n' >&2
        exit 2
      fi
      SOURCE_APPS="$2"
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
participant_value="$(require_value_or_placeholder "$PARTICIPANT_CODE" "P01")"
participant_slug="$(safe_slug "$participant_value")"
run_dir="$OUTPUT_ROOT/$timestamp-$participant_slug"
result_path="$run_dir/first-round-usability-result.md"
observation_path="$run_dir/usability-observation-notes.md"
packet_zip="$run_dir/HTMLPreviewerUsabilityTestPacket.zip"
packet_dir="$run_dir/HTMLPreviewerUsabilityTestPacket"
device_list_path="$run_dir/devicectl-devices.txt"
README_PATH="$run_dir/README.txt"

if [[ "$DRY_RUN" == true ]]; then
  printf 'Would prepare first-round usability session run:\n'
  printf -- '- Result draft: %s\n' "$result_path"
  printf -- '- Observation draft: %s\n' "$observation_path"
  printf -- '- Usability packet zip: %s\n' "$packet_zip"
  printf -- '- Usability packet folder: %s\n' "$packet_dir"
  printf -- '- Device list: %s\n' "$device_list_path"
  printf -- '- Participant code: %s\n' "$participant_value"
  exit 0
fi

"$ROOT_DIR/scripts/prepare-usability-test-packet.sh" >/dev/null

rm -rf "$run_dir"
mkdir -p "$run_dir"
cp "$ROOT_DIR/DerivedData/UsabilityTestPacket/HTMLPreviewerUsabilityTestPacket.zip" "$packet_zip"
cp -R "$ROOT_DIR/DerivedData/UsabilityTestPacket/HTMLPreviewerUsabilityTestPacket" "$packet_dir"

if xcrun devicectl list devices >"$device_list_path" 2>&1; then
  :
else
  printf 'devicectl device listing failed; continue manually.\n' >"$device_list_path"
fi

moderator_value="$(require_value_or_placeholder "$MODERATOR" "TBD")"
build_source_value="$(require_value_or_placeholder "$BUILD_SOURCE" "Xcode run / local archive / TestFlight")"
device_value="$(require_value_or_placeholder "$DEVICE" "TBD physical iPhone")"
ios_version_value="$(require_value_or_placeholder "$IOS_VERSION" "TBD")"
region_language_value="$(require_value_or_placeholder "$REGION_LANGUAGE" "TBD")"
source_apps_value="$(require_value_or_placeholder "$SOURCE_APPS" "Files, Mail, AirDrop, iCloud Drive, messaging app, Safari downloads as available")"

cat > "$result_path" <<EOF
# First-Round Usability Result

Issue: #11

## Session Metadata

- Date: $date_stamp
- Moderator: $moderator_value
- Participant code: $participant_value
- Build source: $build_source_value
- Commit: $commit_short ($commit_full)
- Branch: $branch
- App version: $app_version
- Build number: $build_number
- Device: $device_value
- iOS version: $ios_version_value
- Region/language: $region_language_value
- Source apps available: $source_apps_value
- Usability packet: \`$packet_zip\`
- Observation notes: \`$observation_path\`
- Device list snapshot: \`$device_list_path\`

Do not store the participant's real name, contact details, payment details, or private file contents in this repository.

## Setup Evidence

| Item | Pass/Fail | Notes |
|---|---|---|
| Latest usability packet used |  |  |
| Physical iPhone used |  |  |
| Sample files available in Files |  |  |
| At least one external source app tested |  |  |
| App Store listing draft reviewed |  |  |

## Task Results

Use Pass, Fail, Assisted, Not available, or Not tested.

| Task | Result | Evidence/notes |
|---|---|---|
| Open \`basic-report.html\` from Files |  |  |
| Open \`legacy-report.htm\` from Files |  |  |
| Open \`markdown-notes.md\` from Files |  |  |
| Open \`markdown-reference.markdown\` from Files |  |  |
| Open \`zip-report.zip\` and confirm CSS/image assets |  |  |
| Explain Safe Preview for \`external-resource.html\` |  |  |
| Decide whether to use Interactive mode for \`interactive-trusted.html\` |  |  |
| Recover from \`broken.zip\` error |  |  |
| Reopen a recent file |  |  |
| Delete a recent file |  |  |
| Explain paid download / no ads / no account / no subscription |  |  |

## Source-App Notes

| Source app | File types tried | Result | Caveats |
|---|---|---|---|
| Files |  |  |  |
| iCloud Drive |  |  |  |
| Mail |  |  |  |
| AirDrop |  |  |  |
| Messaging app |  |  |  |
| Safari downloads |  |  |  |

## Findings

| Priority | Area | Finding | Evidence | Follow-up issue |
|---|---|---|---|---|
| P0/P1/P2 |  |  |  |  |

Priority guide:

- P0: Blocks opening, previewing, deleting, or recovering from core file errors.
- P1: Causes serious confusion around source app entry points, Safe Preview, ZIP assets, or pricing/privacy claims.
- P2: Polish, copy, layout, or convenience improvements that do not block the core workflow.

## Close Criteria

- All P0 findings filed or fixed:
- All P1 findings filed or fixed:
- Can close #11: yes / no
- Can continue App Store submission: yes / no
- Follow-up issues:

## Issue Comment Draft

\`\`\`text
First-round usability result:

- Commit: $commit_short
- Build source: $build_source_value
- Participant code: $participant_value
- Device/iOS: $device_value / $ios_version_value
- Sources tested:
- Overall status:

Passed:
-

Caveats:
-

P0/P1 findings:
-

Follow-ups:
-

Can close #11: yes/no
\`\`\`
EOF

cat > "$observation_path" <<EOF
# Usability Observation Notes

## Session

- Date: $date_stamp
- Build: $build_source_value, version $app_version ($build_number), commit $commit_short
- Device: $device_value
- iOS version: $ios_version_value
- Participant code: $participant_value
- Source apps tested: $source_apps_value

Do not store the participant's real name, contact details, payment details, or private file contents in this repository.

## Task Results

| Task | Pass/Fail | Notes |
|---|---|---|
| Open .html from Files |  |  |
| Open .htm from Files |  |  |
| Open .md from Files |  |  |
| Open .markdown from Files |  |  |
| Open ZIP package |  |  |
| Understand Safe Preview |  |  |
| Decide on Interactive mode |  |  |
| Understand invalid ZIP error |  |  |
| Reopen recent file |  |  |
| Delete recent file |  |  |
| Understand listing/pricing/privacy |  |  |

## Findings

| Priority | Area | Finding | Evidence | Follow-up |
|---|---|---|---|---|
| P0/P1/P2 |  |  |  |  |

## Priority Guide

- P0: Blocks opening, previewing, deleting, or recovering from core file errors.
- P1: Causes serious confusion around source app entry points, Safe Preview, ZIP assets, or pricing/privacy claims.
- P2: Polish, copy, layout, or convenience improvements that do not block the core workflow.
EOF

cat > "$README_PATH" <<EOF
HTML Previewer first-round usability session run

Generated: $timestamp
Commit: $commit_short
Participant code: $participant_value

Files:
- first-round-usability-result.md
- usability-observation-notes.md
- HTMLPreviewerUsabilityTestPacket.zip
- HTMLPreviewerUsabilityTestPacket/
- devicectl-devices.txt

Next:
1. Install the latest local archive or TestFlight build on a physical iPhone.
2. Move sample files from HTMLPreviewerUsabilityTestPacket/Samples/ onto the
   device through Files, Mail, AirDrop, iCloud Drive, Safari downloads, or a
   messaging app.
3. Run HTMLPreviewerUsabilityTestPacket/script.md with an external participant.
4. Fill usability-observation-notes.md during the session.
5. Fill first-round-usability-result.md with the final close decision.
6. File or fix every P0/P1 finding, then summarize the result in issue #11.

Do not record participant names, contact details, payment details, or private
file contents in this repository.
EOF

printf 'Prepared usability session run folder: %s\n' "$run_dir"
printf 'Prepared result draft: %s\n' "$result_path"
printf 'Prepared observation draft: %s\n' "$observation_path"
printf 'Prepared usability packet: %s\n' "$packet_zip"
