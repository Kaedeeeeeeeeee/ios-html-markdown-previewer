#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_ROOT="$ROOT_DIR/DerivedData/FinalSubmissionPreflight"
LOG_DIR="$OUTPUT_ROOT/logs"
REPORT_PATH="$OUTPUT_ROOT/submission-readiness-report.md"
RUN_BUILDS=true
PASSED_STEPS=()
FAILED_STEP=""
SKIPPED_STEPS=()

usage() {
  cat <<'EOF'
Usage: scripts/final-submission-preflight.sh [--skip-builds]

Runs the local pre-submission gates that do not require Apple account access
or a physical iPhone, then writes a readiness report under DerivedData.

Options:
  --skip-builds  Skip generic iOS Release build and archive preflight.
  -h, --help     Show this help.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --skip-builds)
      RUN_BUILDS=false
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n\n' "$arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

safe_slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-'
}

git_value() {
  git -C "$ROOT_DIR" "$@" 2>/dev/null || printf 'unknown'
}

working_tree_state() {
  if [[ -n "$(git -C "$ROOT_DIR" status --porcelain 2>/dev/null || true)" ]]; then
    printf 'dirty'
  else
    printf 'clean'
  fi
}

latest_file() {
  local search_root="$1"
  local filename="$2"
  if [[ ! -d "$search_root" ]]; then
    return 0
  fi

  find "$search_root" -name "$filename" -print 2>/dev/null | sort | tail -n 1
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

short_commit() {
  local value="$1"
  printf '%.7s' "$value"
}

commit_status() {
  local path="$1"
  local current_full="$2"
  local current_short="$3"
  local evidence_commit

  evidence_commit="$(report_commit "$path")"
  if [[ -z "$evidence_commit" ]]; then
    printf 'unknown'
    return 0
  fi

  if [[ "$evidence_commit" == "$current_full" || "$evidence_commit" == "$current_short" || "$current_full" == "$evidence_commit"* ]]; then
    printf 'matches current commit (%s)' "$current_short"
  else
    printf 'stale: evidence commit %s does not match current %s' "$(short_commit "$evidence_commit")" "$current_short"
  fi
}

write_latest_evidence() {
  local app_store_connect_result
  local final_smoke_result
  local physical_device_result
  local archive_smoke_report
  local current_full
  local current_short

  app_store_connect_result="$(latest_file "$ROOT_DIR/DerivedData/AppStoreConnectRun" "app-store-connect-result.md")"
  final_smoke_result="$(latest_file "$ROOT_DIR/DerivedData/FinalSmokeRun" "final-archive-smoke-result.md")"
  physical_device_result="$(latest_file "$ROOT_DIR/DerivedData/PhysicalDeviceValidationRun" "physical-device-validation-result.md")"
  archive_smoke_report="$(latest_file "$ROOT_DIR/DerivedData/PhysicalDeviceSmoke" "archive-device-smoke-report.md")"
  current_full="$(git_value rev-parse HEAD)"
  current_short="$(git_value rev-parse --short HEAD)"

  printf '\n## Latest Local Evidence\n\n'
  if [[ -n "$app_store_connect_result" ]]; then
    printf -- '- App Store Connect result draft: `%s`\n' "$app_store_connect_result"
    printf -- '  - Commit check: %s\n' "$(commit_status "$app_store_connect_result" "$current_full" "$current_short")"
  else
    printf -- '- App Store Connect result draft: not generated yet\n'
  fi

  if [[ -n "$final_smoke_result" ]]; then
    printf -- '- Final smoke result draft: `%s`\n' "$final_smoke_result"
    printf -- '  - Commit check: %s\n' "$(commit_status "$final_smoke_result" "$current_full" "$current_short")"
  else
    printf -- '- Final smoke result draft: not generated yet\n'
  fi

  if [[ -n "$physical_device_result" ]]; then
    printf -- '- Physical-device validation draft: `%s`\n' "$physical_device_result"
    printf -- '  - Commit check: %s\n' "$(commit_status "$physical_device_result" "$current_full" "$current_short")"
  else
    printf -- '- Physical-device validation draft: not generated yet\n'
  fi

  if [[ -n "$archive_smoke_report" ]]; then
    printf -- '- Archive device smoke report: `%s`\n' "$archive_smoke_report"
    printf -- '  - Commit check: %s\n' "$(commit_status "$archive_smoke_report" "$current_full" "$current_short")"
    printf -- '  - Status: %s\n' "$(report_field Status "$archive_smoke_report")"
    printf -- '  - App Store/TestFlight submission evidence: %s\n' "$(report_field "App Store/TestFlight submission evidence" "$archive_smoke_report")"
    printf -- '  - Submission evidence note: %s\n' "$(report_field "Submission evidence note" "$archive_smoke_report")"
    printf -- '  - Install: %s\n' "$(report_field Install "$archive_smoke_report")"
    printf -- '  - Launch: %s\n' "$(report_field Launch "$archive_smoke_report")"
    printf -- '  - Screenshot: %s\n' "$(report_field Screenshot "$archive_smoke_report")"
  else
    printf -- '- Archive device smoke report: not generated yet\n'
  fi
}

write_report() {
  local status="$1"
  local generated_at
  generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  mkdir -p "$OUTPUT_ROOT"
  {
    printf '# Final Submission Preflight Report\n\n'
    printf -- '- Status: %s\n' "$status"
    printf -- '- Generated: %s\n' "$generated_at"
    printf -- '- Branch: %s\n' "$(git_value branch --show-current)"
    printf -- '- Commit: %s\n' "$(git_value rev-parse --short HEAD)"
    printf -- '- Full commit: %s\n' "$(git_value rev-parse HEAD)"
    printf -- '- Working tree: %s\n' "$(working_tree_state)"
    printf '\n## Passed Local Gates\n\n'
    if [[ "${#PASSED_STEPS[@]}" -eq 0 ]]; then
      printf -- '- None yet\n'
    else
      local step
      for step in "${PASSED_STEPS[@]}"; do
        printf -- '- %s\n' "$step"
      done
    fi

    if [[ "${#SKIPPED_STEPS[@]}" -gt 0 ]]; then
      printf '\n## Skipped Gates\n\n'
      local skipped
      for skipped in "${SKIPPED_STEPS[@]}"; do
        printf -- '- %s\n' "$skipped"
      done
    fi

    if [[ -n "$FAILED_STEP" ]]; then
      printf '\n## Failed Gate\n\n'
      printf -- '- %s\n' "$FAILED_STEP"
    fi

    printf '\n## Generated Artifacts\n\n'
    printf -- '- Release packet: `DerivedData/ReleasePacket/HTMLPreviewerReleasePacket.zip`\n'
    printf -- '- Usability test packet: `DerivedData/UsabilityTestPacket/HTMLPreviewerUsabilityTestPacket.zip`\n'
    printf -- '- Validation samples: `DerivedData/ValidationSamples/HTMLPreviewerValidationSamples.zip`\n'
    printf -- '- Browser delivery page: `DerivedData/ValidationSamples/index.html`\n'
    printf -- '- App Store Connect draft: `DerivedData/AppStoreConnectRun/`\n'
    printf -- '- Final smoke draft: `DerivedData/FinalSmokeRun/`\n'
    printf -- '- Preflight logs: `DerivedData/FinalSubmissionPreflight/logs/`\n'

    write_latest_evidence

    printf '\n## Manual Gates Still Required\n\n'
    printf -- '- #1: Run `scripts/prepare-physical-device-validation-run.sh --device <physical-iPhone>`, complete the physical-device external-open matrix on a real iPhone, and keep the generated result draft with release evidence.\n'
    printf -- '- #11: Run the first usability round with at least one external participant and record `docs/usability-testing/first-round-result-template.md`.\n'
    printf -- '- #10: If GitHub Actions fails before workflow steps start, run `scripts/check-github-actions-execution.sh` and keep the generated diagnostic report with release evidence.\n'
    printf -- '- #10: Run `scripts/prepare-app-store-connect-run.sh`, then complete the App Store Connect paid-download setup and record the generated result draft.\n'
    printf -- '- #10: Run `DEVELOPMENT_TEAM=<Apple Team ID> scripts/create-signed-archive.sh` with the account owner Apple Distribution signing setup. Do not count `ALLOW_DEVELOPMENT_SIGNING=YES` archives as upload evidence.\n'
    printf -- '- #10: If using an archived build for smoke, run `scripts/run-archive-device-smoke.sh --device <device-id-or-name>` on an unlocked physical device and keep the generated report.\n'
    printf -- '- #10: Run `scripts/prepare-final-smoke-run.sh`, upload/select the processed App Store Connect build, then complete final archive/TestFlight smoke using the generated result draft.\n'
  } >"$REPORT_PATH"
}

refresh_release_packet_report() {
  local packet_root="$ROOT_DIR/DerivedData/ReleasePacket"
  local packet_dir="$packet_root/HTMLPreviewerReleasePacket"
  local zip_path="$packet_root/HTMLPreviewerReleasePacket.zip"
  local index_path="$packet_dir/Evidence/release-evidence-index.md"
  local tmp_index_path="$packet_dir/Evidence/release-evidence-index.md.tmp"
  local checksum_path="$packet_dir/Evidence/checksums-sha256.txt"

  if [[ ! -d "$packet_dir" || ! -f "$REPORT_PATH" ]]; then
    return 0
  fi

  mkdir -p "$packet_dir/Evidence"
  cp "$REPORT_PATH" "$packet_dir/Evidence/submission-readiness-report.md"
  if [[ -f "$index_path" ]]; then
    awk '
      /^\| Final preflight report \|/ {
        print "| Final preflight report | `Evidence/submission-readiness-report.md` | Included |"
        next
      }
      { print }
    ' "$index_path" >"$tmp_index_path"
    mv "$tmp_index_path" "$index_path"
  fi
  (
    cd "$packet_dir"
    find . -type f ! -path "./Evidence/checksums-sha256.txt" -print |
      LC_ALL=C sort |
      while IFS= read -r file; do
        shasum -a 256 "$file" | sed 's# \./#  #'
      done
  ) > "$checksum_path"
  (
    cd "$packet_root"
    zip -qry -X "HTMLPreviewerReleasePacket.zip" "HTMLPreviewerReleasePacket"
  )
  printf 'Refreshed release packet evidence: %s\n' "$zip_path"
}

run_step() {
  local name="$1"
  shift
  local slug
  local log_path
  slug="$(safe_slug "$name")"
  log_path="$LOG_DIR/${slug}.log"

  printf '==> %s\n' "$name"
  if "$@" >"$log_path" 2>&1; then
    PASSED_STEPS+=("$name")
    printf '    passed: %s\n' "$log_path"
  else
    FAILED_STEP="$name"
    printf '    failed: %s\n' "$log_path" >&2
    tail -n 80 "$log_path" >&2 || true
    write_report "failed"
    refresh_release_packet_report
    printf 'Wrote preflight report: %s\n' "$REPORT_PATH" >&2
    exit 1
  fi
}

rm -rf "$OUTPUT_ROOT"
mkdir -p "$LOG_DIR"

run_step "Portable release materials audit" "$ROOT_DIR/scripts/portable-release-materials-audit.sh"
run_step "Release audit" "$ROOT_DIR/scripts/release-audit.sh"
run_step "Public App Store pages" "$ROOT_DIR/scripts/verify-public-pages.sh"
run_step "Usability test packet staging" "$ROOT_DIR/scripts/prepare-usability-test-packet.sh"
run_step "Validation sample browser delivery staging" "$ROOT_DIR/scripts/serve-validation-samples.sh" --prepare-only
run_step "App Store Connect result draft staging" "$ROOT_DIR/scripts/prepare-app-store-connect-run.sh"
run_step "Final smoke result draft staging" "$ROOT_DIR/scripts/prepare-final-smoke-run.sh"
run_step "Release packet staging" "$ROOT_DIR/scripts/prepare-release-packet.sh"
run_step "Signed archive dry-run" env DEVELOPMENT_TEAM=ABCDE12345 "$ROOT_DIR/scripts/create-signed-archive.sh" --dry-run

if [[ "$RUN_BUILDS" == true ]]; then
  run_step "Generic iOS Release build" "$ROOT_DIR/scripts/release-device-build.sh"
  run_step "Generic iOS archive preflight" "$ROOT_DIR/scripts/archive-preflight.sh"
else
  SKIPPED_STEPS+=("Generic iOS Release build")
  SKIPPED_STEPS+=("Generic iOS archive preflight")
fi

write_report "passed"
refresh_release_packet_report
printf 'Final submission preflight passed.\n'
printf 'Wrote preflight report: %s\n' "$REPORT_PATH"
