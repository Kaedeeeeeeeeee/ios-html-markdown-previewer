#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT_DIR/DerivedData/AppStoreConnectRun}"
APP_NAME="${APP_NAME:-HTML Previewer}"
BUNDLE_ID="${BUNDLE_ID:-com.kaede.htmlmarkdownpreviewer}"
SKU="${SKU:-com.kaede.htmlmarkdownpreviewer.ios}"
PRIMARY_LANGUAGE="${PRIMARY_LANGUAGE:-English (U.S.)}"
PRIMARY_CATEGORY="${PRIMARY_CATEGORY:-Productivity}"
SECONDARY_CATEGORY="${SECONDARY_CATEGORY:-Utilities / empty}"
PRICE="${PRICE:-}"
AVAILABILITY="${AVAILABILITY:-}"
RELEASE_TIMING="${RELEASE_TIMING:-}"
COPYRIGHT_OWNER="${COPYRIGHT_OWNER:-}"
GITHUB_ACTIONS_RUN="${GITHUB_ACTIONS_RUN:-}"
APP_STORE_CONNECT_APP_ID="${APP_STORE_CONNECT_APP_ID:-}"
APP_STORE_CONNECT_BUILD="${APP_STORE_CONNECT_BUILD:-}"
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: scripts/prepare-app-store-connect-run.sh [options]

Creates a pre-filled App Store Connect setup result draft for issue #10. This
does not configure App Store Connect; it prepares the evidence file the account
owner fills while creating the paid-download app record and first submission.

Environment:
  OUTPUT_ROOT                 Optional output root. Defaults to DerivedData/AppStoreConnectRun.
  APP_NAME                    Optional App Store app name.
  BUNDLE_ID                   Optional bundle id.
  SKU                         Optional SKU.
  PRIMARY_LANGUAGE            Optional primary language.
  PRIMARY_CATEGORY            Optional primary category.
  SECONDARY_CATEGORY          Optional secondary category.
  PRICE                       Optional selected price.
  AVAILABILITY                Optional selected countries/regions.
  RELEASE_TIMING              Optional release timing choice.
  COPYRIGHT_OWNER             Optional copyright owner.
  GITHUB_ACTIONS_RUN          Optional final GitHub Actions run URL or id.
  APP_STORE_CONNECT_APP_ID    Optional App Store Connect app id.
  APP_STORE_CONNECT_BUILD     Optional selected build identifier.

Options:
  --price VALUE                     Selected paid-download price.
  --availability VALUE              Selected countries/regions.
  --release-timing VALUE            Manual, automatic, or scheduled release.
  --copyright-owner VALUE           Copyright owner.
  --github-actions-run VALUE        Final GitHub Actions run URL or id.
  --app-store-connect-app-id VALUE  App Store Connect app id.
  --app-store-connect-build VALUE   Selected build identifier.
  --dry-run                         Print planned output without writing files.
  -h, --help                        Show this help.
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --price)
      PRICE="${2:-}"
      shift 2
      ;;
    --availability)
      AVAILABILITY="${2:-}"
      shift 2
      ;;
    --release-timing)
      RELEASE_TIMING="${2:-}"
      shift 2
      ;;
    --copyright-owner)
      COPYRIGHT_OWNER="${2:-}"
      shift 2
      ;;
    --github-actions-run)
      GITHUB_ACTIONS_RUN="${2:-}"
      shift 2
      ;;
    --app-store-connect-app-id)
      APP_STORE_CONNECT_APP_ID="${2:-}"
      shift 2
      ;;
    --app-store-connect-build)
      APP_STORE_CONNECT_BUILD="${2:-}"
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

listing_value() {
  local label="$1"
  awk -F': ' -v label="$label" '$0 ~ "^- " label ":" || $0 ~ "^" label ":" { print $2; exit }' "$ROOT_DIR/docs/app-store-listing.md" 2>/dev/null || true
}

screenshot_line() {
  local pattern="$1"
  find "$ROOT_DIR/docs/app-store-screenshots" -maxdepth 1 -name "$pattern" -print 2>/dev/null |
    sed "s#^$ROOT_DIR/##" |
    sort |
    paste -sd ',' - |
    sed 's/,/, /g'
}

commit_short="$(git_value rev-parse --short HEAD)"
commit_full="$(git_value rev-parse HEAD)"
branch="$(git_value branch --show-current)"
date_stamp="$(date -u '+%Y-%m-%d')"
timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
app_version="$(build_setting MARKETING_VERSION)"
build_number="$(build_setting CURRENT_PROJECT_VERSION)"
app_version="${app_version:-unknown}"
build_number="${build_number:-unknown}"

price_value="$(require_value_or_placeholder "$PRICE" "TBD paid-download price")"
availability_value="$(require_value_or_placeholder "$AVAILABILITY" "TBD countries/regions")"
release_timing_value="$(require_value_or_placeholder "$RELEASE_TIMING" "TBD release timing")"
copyright_owner_value="$(require_value_or_placeholder "$COPYRIGHT_OWNER" "TBD")"
github_actions_run_value="$(require_value_or_placeholder "$GITHUB_ACTIONS_RUN" "TBD")"
app_store_connect_app_id_value="$(require_value_or_placeholder "$APP_STORE_CONNECT_APP_ID" "TBD")"
app_store_connect_build_value="$(require_value_or_placeholder "$APP_STORE_CONNECT_BUILD" "TBD")"
privacy_url="$(listing_value "Privacy Policy URL")"
support_url="$(listing_value "Support URL")"
privacy_url="${privacy_url:-TBD}"
support_url="${support_url:-TBD}"
iphone_screenshots="$(screenshot_line 'iphone-*.png')"
ipad_screenshots="$(screenshot_line 'ipad-*.png')"
iphone_screenshots="${iphone_screenshots:-TBD}"
ipad_screenshots="${ipad_screenshots:-TBD}"

run_slug="$(safe_slug "$APP_NAME-$app_version-$build_number")"
run_dir="$OUTPUT_ROOT/$timestamp-$run_slug"
result_path="$run_dir/app-store-connect-result.md"
readme_path="$run_dir/README.txt"

if [[ "$DRY_RUN" == true ]]; then
  printf 'Would prepare App Store Connect setup run:\n'
  printf -- '- Result draft: %s\n' "$result_path"
  printf -- '- README: %s\n' "$readme_path"
  printf -- '- App Store Connect setup: paid download, Data Not Collected, no IAP, no ads, no account\n'
  exit 0
fi

rm -rf "$run_dir"
mkdir -p "$run_dir"

cat > "$result_path" <<EOF
# App Store Connect Setup Result

Issue: #10

## Run Metadata

- Date: $date_stamp
- Commit: $commit_short ($commit_full)
- Branch: $branch
- GitHub Actions run: $github_actions_run_value
- App Store Connect app id: $app_store_connect_app_id_value
- App Store Connect selected build: $app_store_connect_build_value
- App version: $app_version
- Build number: $build_number
- Final preflight report: \`$ROOT_DIR/DerivedData/FinalSubmissionPreflight/submission-readiness-report.md\`
- Release packet: \`$ROOT_DIR/DerivedData/ReleasePacket/HTMLPreviewerReleasePacket.zip\`

## App Record

| Field | Expected value | Entered value | Pass/Fail | Notes |
|---|---|---|---|---|
| Platform | iOS |  |  |  |
| App name | $APP_NAME |  |  |  |
| Bundle ID | \`$BUNDLE_ID\` |  |  |  |
| SKU | \`$SKU\` |  |  |  |
| Primary language | $PRIMARY_LANGUAGE |  |  |  |
| Primary category | $PRIMARY_CATEGORY |  |  |  |
| Secondary category | $SECONDARY_CATEGORY |  |  |  |
| Copyright owner | $copyright_owner_value |  |  | Account-owner confirmation required |

## Pricing And Availability

| Field | Expected value | Entered value | Pass/Fail | Notes |
|---|---|---|---|---|
| Commercial model | Paid download |  |  | MVP has no IAP or purchase screen |
| Price | $price_value |  |  | Account-owner decision |
| Availability | $availability_value |  |  | Account-owner decision |
| Release timing | $release_timing_value |  |  | Manual / automatic / scheduled |
| In-app purchases | None configured |  |  | Confirm no products exist for v1.0 |
| Subscriptions | None configured |  |  |  |
| Ads | None |  |  |  |
| Account requirement | None |  |  |  |

## Metadata And Review Notes

Use \`docs/app-store-listing.md\` and \`docs/app-store-connect-handoff.md\`.

| Area | Expected source | Pass/Fail | Notes |
|---|---|---|---|
| Name, subtitle, promotional text, description, keywords | \`docs/app-store-listing.md\` |  |  |
| Support URL | $support_url |  |  |
| Privacy Policy URL | $privacy_url |  |  |
| Review notes | Built-in HTML, Markdown, and ZIP samples described |  |  |
| Content rights | App-bundled samples are original |  |  |

## Screenshots

| Slot | Expected files | Accepted in App Store Connect | Notes |
|---|---|---|---|
| iPhone 6.9-inch display | $iphone_screenshots |  |  |
| iPad Pro 13-inch display | $ipad_screenshots |  |  |

## Privacy

| Area | Expected answer | Pass/Fail | Notes |
|---|---|---|---|
| Data collected | Data Not Collected |  |  |
| Tracking | No |  |  |
| Data linked to user | None |  |  |
| Data used for tracking | None |  |  |
| Privacy policy URL | $privacy_url |  |  |
| User Privacy Choices URL | Empty unless account owner adds a separate page |  |  |

## Age Rating

Use the current App Store Connect questionnaire and record the final account-owner answers.

| Area | Recommended answer | Entered answer | Pass/Fail | Notes |
|---|---|---|---|---|
| Profanity, horror, alcohol, medical, sexual, violence, gambling, contests, loot boxes | None / No |  |  |  |
| Messaging and chat | No |  |  | App has no user-to-user communication |
| Advertising | No |  |  | No ad SDKs |
| User-generated content | No |  |  | App locally previews user-selected files |
| Unrestricted web access | No |  |  | Safe Preview blocks external resources; app is not a browser |
| Made for Kids | No / Not Applicable |  |  |  |
| Final age rating | Account-owner/App Store Connect result |  |  |  |

## Export Compliance

| Area | Expected answer | Pass/Fail | Notes |
|---|---|---|---|
| Uses encryption | Answer consistently with \`ITSAppUsesNonExemptEncryption=false\` |  |  |
| Custom cryptography | No |  |  |
| Export compliance documentation | \`docs/export-compliance.md\` |  |  |

## Build Selection

| Area | Expected state | Pass/Fail | Notes |
|---|---|---|---|
| Distribution archive uploaded | Apple Distribution signed archive |  |  |
| Processed build selected | $app_store_connect_build_value |  |  |
| TestFlight or archive smoke ready | Final smoke run draft exists |  |  |

## Blocking Submission Issues

| Priority | Issue | App Store Connect area | Follow-up issue |
|---|---|---|---|
| P0/P1/P2 |  |  |  |

Priority guide:

- P0: Blocks App Store submission or contradicts the paid-download/no-data/no-account release stance.
- P1: Requires copy, screenshot, privacy, age-rating, or review-note changes before submission.
- P2: Non-blocking cleanup after the first submission.

## Result

- Overall status: pending / passed / failed
- Can continue final archive/TestFlight smoke: yes / no
- Can submit for review: yes / no
- Follow-up issues:

## Issue Comment Draft

\`\`\`text
App Store Connect setup result:

- Commit: $commit_short
- GitHub Actions run: $github_actions_run_value
- App Store Connect app id: $app_store_connect_app_id_value
- Selected build: $app_store_connect_build_value
- Paid download configured:
- Privacy labels Data Not Collected:
- No IAP/subscriptions/ads/accounts:
- Screenshots accepted:
- Export compliance complete:
- Overall status:

Blocking failures:
- 

Follow-ups:
- 
\`\`\`
EOF

cat > "$readme_path" <<EOF
HTML Previewer App Store Connect setup run

Generated: $timestamp
Commit: $commit_short

Files:
- app-store-connect-result.md

Next:
1. Create or update the App Store Connect app record using docs/app-store-connect-handoff.md.
2. Fill app-store-connect-result.md while entering pricing, privacy, screenshots, age rating, export compliance, and build selection.
3. Summarize the completed result in GitHub issue #10.
EOF

printf 'Prepared App Store Connect run folder: %s\n' "$run_dir"
printf 'Prepared App Store Connect result draft: %s\n' "$result_path"
