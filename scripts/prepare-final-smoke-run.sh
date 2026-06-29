#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT_DIR/DerivedData/FinalSmokeRun}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/DerivedData/SignedArchive/HTMLPreviewer.xcarchive}"
APP_PATH="${APP_PATH:-$ARCHIVE_PATH/Products/Applications/HTMLMarkdownPreviewer.app}"
DEVICE="${DEVICE:-}"
BUILD_SOURCE="${BUILD_SOURCE:-}"
APP_STORE_CONNECT_BUILD="${APP_STORE_CONNECT_BUILD:-}"
INSTALL_METHOD="${INSTALL_METHOD:-}"
TESTER="${TESTER:-}"
IOS_VERSION="${IOS_VERSION:-}"
GITHUB_ACTIONS_RUN="${GITHUB_ACTIONS_RUN:-}"
ARCHIVE_SMOKE_REPORT="${ARCHIVE_SMOKE_REPORT:-}"
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: scripts/prepare-final-smoke-run.sh [options]

Creates a pre-filled final archive/TestFlight smoke result draft for issue #10.
This does not run the smoke test; it prepares the evidence folder for the final
manual pass after a distribution-signed archive or TestFlight build is ready.

Environment:
  OUTPUT_ROOT              Optional output root. Defaults to DerivedData/FinalSmokeRun.
  ARCHIVE_PATH             Optional .xcarchive path.
  APP_PATH                 Optional .app path inside the archive.
  DEVICE                   Optional device name/model.
  BUILD_SOURCE             Optional build source, e.g. signed archive or TestFlight.
  APP_STORE_CONNECT_BUILD  Optional App Store Connect build identifier.
  INSTALL_METHOD           Optional install method.
  TESTER                   Optional tester name or initials.
  IOS_VERSION              Optional iOS version.
  GITHUB_ACTIONS_RUN       Optional final GitHub Actions run URL or id.
  ARCHIVE_SMOKE_REPORT     Optional run-archive-device-smoke.sh report path.

Options:
  --device VALUE                   Device name/model.
  --build-source VALUE             signed archive, TestFlight, or local archive.
  --app-store-connect-build VALUE  App Store Connect build identifier.
  --install-method VALUE           TestFlight, Xcode Organizer, devicectl, etc.
  --tester VALUE                   Tester name or initials.
  --ios-version VALUE              iOS version.
  --github-actions-run VALUE       Final GitHub Actions run URL or id.
  --archive-smoke-report VALUE     Archive smoke report path.
  --dry-run                        Print planned output without writing files.
  -h, --help                       Show this help.
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --device)
      DEVICE="${2:-}"
      shift 2
      ;;
    --build-source)
      BUILD_SOURCE="${2:-}"
      shift 2
      ;;
    --app-store-connect-build)
      APP_STORE_CONNECT_BUILD="${2:-}"
      shift 2
      ;;
    --install-method)
      INSTALL_METHOD="${2:-}"
      shift 2
      ;;
    --tester)
      TESTER="${2:-}"
      shift 2
      ;;
    --ios-version)
      IOS_VERSION="${2:-}"
      shift 2
      ;;
    --github-actions-run)
      GITHUB_ACTIONS_RUN="${2:-}"
      shift 2
      ;;
    --archive-smoke-report)
      ARCHIVE_SMOKE_REPORT="${2:-}"
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

plist_value() {
  local key="$1"
  local plist="$2"
  /usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null || true
}

build_setting() {
  local key="$1"
  xcodebuild -project "$ROOT_DIR/HTMLMarkdownPreviewer.xcodeproj" \
    -scheme HTMLMarkdownPreviewer \
    -configuration Release \
    -showBuildSettings 2>/dev/null |
    awk -v key="$key" '$1 == key && $2 == "=" { print $3; exit }'
}

latest_archive_smoke_report() {
  if [[ -d "$ROOT_DIR/DerivedData/PhysicalDeviceSmoke" ]]; then
    find "$ROOT_DIR/DerivedData/PhysicalDeviceSmoke" \
      -name archive-device-smoke-report.md \
      -print 2>/dev/null | sort | tail -n 1
  fi
}

report_field() {
  local label="$1"
  local path="$2"
  if [[ -f "$path" ]]; then
    awk -F': ' -v label="$label" '$0 ~ "^- " label ":" { print $2; exit }' "$path"
  fi
}

report_commit() {
  local path="$1"
  local full_commit
  local parenthesized_commit
  local short_commit

  full_commit="$(report_field "Full commit" "$path")"
  if [[ -n "$full_commit" ]]; then
    printf '%s' "$full_commit"
    return 0
  fi

  parenthesized_commit="$(awk -F'[()]' '/^- Commit: / { print $2; exit }' "$path" 2>/dev/null || true)"
  if [[ -n "$parenthesized_commit" ]]; then
    printf '%s' "$parenthesized_commit"
    return 0
  fi

  short_commit="$(report_field "Commit" "$path")"
  printf '%s' "$short_commit"
}

short_commit_value() {
  local value="$1"
  printf '%.7s' "$value"
}

archive_smoke_commit_status() {
  local evidence_commit

  if [[ -z "$ARCHIVE_SMOKE_REPORT" || ! -f "$ARCHIVE_SMOKE_REPORT" ]]; then
    printf 'TBD'
    return 0
  fi

  evidence_commit="$(report_commit "$ARCHIVE_SMOKE_REPORT")"
  if [[ -z "$evidence_commit" ]]; then
    printf 'unknown'
    return 0
  fi

  if [[ "$evidence_commit" == "$commit_full" || "$evidence_commit" == "$commit_short" || "$commit_full" == "$evidence_commit"* ]]; then
    printf 'matches current commit (%s)' "$commit_short"
  else
    printf 'stale: archive smoke commit %s does not match current %s' "$(short_commit_value "$evidence_commit")" "$commit_short"
  fi
}

report_artifact_path() {
  local label="$1"
  local path="$2"
  if [[ -f "$path" ]]; then
    awk -F'`' -v label="$label" '$0 ~ "^- " label ":" { print $2; exit }' "$path"
  fi
}

if [[ -z "$ARCHIVE_SMOKE_REPORT" ]]; then
  ARCHIVE_SMOKE_REPORT="$(latest_archive_smoke_report || true)"
fi

commit_short="$(git_value rev-parse --short HEAD)"
commit_full="$(git_value rev-parse HEAD)"
branch="$(git_value branch --show-current)"
date_stamp="$(date -u '+%Y-%m-%d')"
timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"

app_version=""
build_number=""
if [[ -d "$APP_PATH" ]]; then
  app_version="$(plist_value CFBundleShortVersionString "$APP_PATH/Info.plist")"
  build_number="$(plist_value CFBundleVersion "$APP_PATH/Info.plist")"
fi
app_version="${app_version:-$(build_setting MARKETING_VERSION)}"
build_number="${build_number:-$(build_setting CURRENT_PROJECT_VERSION)}"
app_version="${app_version:-unknown}"
build_number="${build_number:-unknown}"

tester_value="$(require_value_or_placeholder "$TESTER" "TBD")"
build_source_value="$(require_value_or_placeholder "$BUILD_SOURCE" "signed archive / TestFlight")"
app_store_connect_build_value="$(require_value_or_placeholder "$APP_STORE_CONNECT_BUILD" "TBD")"
device_value="$(require_value_or_placeholder "$DEVICE" "TBD physical iPhone")"
ios_version_value="$(require_value_or_placeholder "$IOS_VERSION" "TBD")"
install_method_value="$(require_value_or_placeholder "$INSTALL_METHOD" "TBD")"
github_actions_run_value="$(require_value_or_placeholder "$GITHUB_ACTIONS_RUN" "TBD")"
archive_smoke_report_value="$(require_value_or_placeholder "$ARCHIVE_SMOKE_REPORT" "TBD")"
archive_smoke_status="$(report_field Status "$ARCHIVE_SMOKE_REPORT")"
archive_smoke_install="$(report_field Install "$ARCHIVE_SMOKE_REPORT")"
archive_smoke_launch="$(report_field Launch "$ARCHIVE_SMOKE_REPORT")"
archive_smoke_screenshot="$(report_field Screenshot "$ARCHIVE_SMOKE_REPORT")"
archive_smoke_commit_check="$(archive_smoke_commit_status)"
launch_screenshot_value="$(report_artifact_path "Launch screenshot" "$ARCHIVE_SMOKE_REPORT")"
archive_smoke_status="${archive_smoke_status:-TBD}"
archive_smoke_install="${archive_smoke_install:-TBD}"
archive_smoke_launch="${archive_smoke_launch:-TBD}"
archive_smoke_screenshot="${archive_smoke_screenshot:-TBD}"
archive_smoke_commit_check="${archive_smoke_commit_check:-TBD}"
if [[ -z "$launch_screenshot_value" || ! -f "$launch_screenshot_value" ]]; then
  launch_screenshot_value="TBD"
fi

run_slug="$(safe_slug "$build_source_value-$device_value")"
run_dir="$OUTPUT_ROOT/$timestamp-$run_slug"
result_path="$run_dir/final-archive-smoke-result.md"
readme_path="$run_dir/README.txt"

if [[ "$DRY_RUN" == true ]]; then
  printf 'Would prepare final archive/TestFlight smoke run:\n'
  printf -- '- Result draft: %s\n' "$result_path"
  printf -- '- README: %s\n' "$readme_path"
  printf -- '- Archive smoke report: %s\n' "$archive_smoke_report_value"
  printf -- '- Archive smoke commit check: %s\n' "$archive_smoke_commit_check"
  exit 0
fi

rm -rf "$run_dir"
mkdir -p "$run_dir"

cat > "$result_path" <<EOF
# Final Archive Or TestFlight Smoke Result

Issue: #10

## Run Metadata

- Date: $date_stamp
- Tester: $tester_value
- Commit: $commit_short ($commit_full)
- Branch: $branch
- GitHub Actions run: $github_actions_run_value
- Build source: $build_source_value
- App Store Connect build: $app_store_connect_build_value
- App version: $app_version
- Build number: $build_number
- Device: $device_value
- iOS version: $ios_version_value
- Install method: $install_method_value
- Archive smoke report: \`$archive_smoke_report_value\`
- Archive smoke status: $archive_smoke_status
- Archive smoke commit check: $archive_smoke_commit_check
- Archive smoke install: $archive_smoke_install
- Archive smoke launch: $archive_smoke_launch
- Archive smoke screenshot: $archive_smoke_screenshot
- Archive launch screenshot: \`$launch_screenshot_value\`
- Final preflight report: \`$ROOT_DIR/DerivedData/FinalSubmissionPreflight/submission-readiness-report.md\`

## Pre-Smoke Gates

| Gate | Expected evidence | Pass/Fail | Notes |
|---|---|---|---|
| Final GitHub Actions run is green | Release Audit, Public App Store Pages, Release Device Build And Archive, Automated Tests |  | $github_actions_run_value |
| Local release audit passed | \`scripts/release-audit.sh\` output |  | Check \`DerivedData/FinalSubmissionPreflight/logs/release-audit.log\` |
| Public pages verification passed | \`scripts/verify-public-pages.sh\` output |  | Check \`DerivedData/FinalSubmissionPreflight/logs/public-app-store-pages.log\` |
| Release device build preflight passed | \`scripts/release-device-build.sh\` output |  | Check \`DerivedData/FinalSubmissionPreflight/logs/generic-ios-release-build.log\` |
| Archive preflight passed | \`scripts/archive-preflight.sh\` output |  | Check \`DerivedData/FinalSubmissionPreflight/logs/generic-ios-archive-preflight.log\` |
| Archived app install/launch evidence captured | \`scripts/run-archive-device-smoke.sh --device <device-id-or-name>\` report and launch screenshot, when using an archived build |  | Report: \`$archive_smoke_report_value\`; screenshot: \`$launch_screenshot_value\` |
| Physical-device external-open validation completed | Linked #1 result |  |  |
| App Store Connect record configured | Paid download, no IAP, privacy labels, age rating, export compliance |  |  |

## App Launch And Built-In Samples

| Check | Pass/Fail | Evidence/notes |
|---|---|---|
| App launches to home screen |  |  |
| Home screen shows Samples section |  |  |
| HTML Sample opens |  |  |
| HTML Sample shows Safe Preview |  |  |
| HTML Safe Preview blocks external resources by default |  |  |
| Markdown Sample opens and renders formatted content |  |  |
| ZIP Report Sample opens |  |  |
| ZIP Report Sample renders local CSS/images |  |  |
| ZIP sample appears in Recent |  |  |
| Recent item reopens successfully |  |  |
| Recent item can be deleted |  |  |

## Settings And Release Claims

| Claim | Expected state | Pass/Fail | Notes |
|---|---|---|---|
| JavaScript | Disabled in Safe Preview |  |  |
| External resources | Blocked in Safe Preview |  |  |
| Processing | On device |  |  |
| Account | None |  |  |
| Ads | None |  |  |
| Purchase flow | None in app; paid download only |  |  |

## App Store Connect Checks

| Area | Expected state | Pass/Fail | Notes |
|---|---|---|---|
| Commercial model | Paid download |  |  |
| In-app purchases | None configured for MVP |  |  |
| Subscriptions | None |  |  |
| Privacy labels | Data Not Collected |  |  |
| Privacy policy URL | Public HTTPS URL accepted |  |  |
| Support URL | Public HTTPS URL accepted |  |  |
| Export compliance | Matches \`ITSAppUsesNonExemptEncryption=false\` |  |  |
| Screenshots | Accepted for iPhone and iPad slots |  |  |
| Review notes | Built-in sample flow included |  |  |

## Blocking Failures

| Priority | Failure | Reproduction steps | Follow-up issue |
|---|---|---|---|
| P0/P1/P2 |  |  |  |

Priority guide:

- P0: Blocks launch, preview, import, deletion, or App Store submission.
- P1: Conflicts with App Store listing, privacy, paid-download positioning, or review notes.
- P2: Polish or documentation issue that does not block submission.

## Result

- Overall status: pending / passed / failed
- Can submit for review: yes / no
- Follow-up issues:

## Issue Comment Draft

\`\`\`text
Final archive/TestFlight smoke result:

- Commit: $commit_short
- GitHub Actions run: $github_actions_run_value
- Build source: $build_source_value
- App Store Connect build: $app_store_connect_build_value
- Device/iOS: $device_value / $ios_version_value
- Archive smoke report: $archive_smoke_report_value
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

cat > "$readme_path" <<EOF
HTML Previewer final archive/TestFlight smoke run

Generated: $timestamp
Commit: $commit_short

Files:
- final-archive-smoke-result.md

Next:
1. Complete App Store Connect, signing, and build selection details.
2. Install the distribution-signed archive or TestFlight build on a physical iPhone.
3. If using an archived build, run scripts/run-archive-device-smoke.sh and keep its report plus launch screenshot.
4. Fill final-archive-smoke-result.md during the manual smoke pass.
5. Summarize the completed result in GitHub issue #10.
EOF

printf 'Prepared final smoke run folder: %s\n' "$run_dir"
printf 'Prepared final smoke result draft: %s\n' "$result_path"
