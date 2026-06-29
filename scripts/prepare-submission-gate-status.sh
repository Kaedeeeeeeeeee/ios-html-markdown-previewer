#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT_DIR/DerivedData/SubmissionGateStatus}"
REPORT_PATH="$OUTPUT_ROOT/submission-gate-status-report.md"
CHECK_GITHUB=false
FAIL_ON_NOT_READY=false
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: scripts/prepare-submission-gate-status.sh [options]

Writes a release gate status report that separates locally completed
pre-submission checks from external/manual gates required before App Store
submission. By default this is a reporting tool and exits 0 even when gates are
pending. Use --fail-on-not-ready for a strict final go/no-go check.

Options:
  --check-github       Query GitHub Actions through gh for the latest main run.
  --fail-on-not-ready  Exit 1 unless every submission gate is passed.
  --dry-run            Print planned report path without writing files.
  -h, --help           Show this help.
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --check-github)
      CHECK_GITHUB=true
      shift
      ;;
    --fail-on-not-ready)
      FAIL_ON_NOT_READY=true
      shift
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

latest_file() {
  local search_root="$1"
  local filename="$2"
  if [[ ! -d "$search_root" ]]; then
    return 0
  fi
  find "$search_root" -name "$filename" -print 2>/dev/null | sort | tail -n 1
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

report_field() {
  local label="$1"
  local path="$2"
  if [[ -f "$path" ]]; then
    awk -v prefix="- $label: " 'index($0, prefix) == 1 { print substr($0, length(prefix) + 1); exit }' "$path"
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

commit_matches_current() {
  local path="$1"
  local evidence_commit

  evidence_commit="$(report_commit "$path")"
  [[ -n "$evidence_commit" ]] || return 1
  [[ "$evidence_commit" == "$CURRENT_FULL" || "$evidence_commit" == "$CURRENT_SHORT" || "$CURRENT_FULL" == "$evidence_commit"* ]]
}

commit_note() {
  local path="$1"
  local evidence_commit

  evidence_commit="$(report_commit "$path")"
  if [[ -z "$evidence_commit" ]]; then
    printf 'commit not recorded'
  elif commit_matches_current "$path"; then
    printf 'matches current commit (%s)' "$CURRENT_SHORT"
  else
    printf 'stale: evidence commit %.7s does not match current %s' "$evidence_commit" "$CURRENT_SHORT"
  fi
}

lower_value() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

is_passed_value() {
  local value
  value="$(lower_value "$1")"
  [[ "$value" == "passed" || "$value" == "pass" ]]
}

is_yes_value() {
  local value
  value="$(lower_value "$1")"
  [[ "$value" == "yes" ]]
}

md_escape() {
  printf '%s' "$1" | sed 's/|/\\|/g'
}

GATE_ROWS=()
BLOCKING_COUNT=0
PENDING_COUNT=0
PASSED_COUNT=0

add_gate() {
  local gate="$1"
  local issue="$2"
  local status="$3"
  local evidence="$4"
  local next_action="$5"

  GATE_ROWS+=("| $(md_escape "$gate") | $(md_escape "$issue") | \`$(md_escape "$status")\` | $(md_escape "$evidence") | $(md_escape "$next_action") |")
  case "$status" in
    passed)
      PASSED_COUNT=$((PASSED_COUNT + 1))
      ;;
    blocked|stale|missing)
      BLOCKING_COUNT=$((BLOCKING_COUNT + 1))
      ;;
    *)
      PENDING_COUNT=$((PENDING_COUNT + 1))
      ;;
  esac
}

latest_github_actions_summary() {
  if [[ "$CHECK_GITHUB" != true || ! -x "$(command -v gh 2>/dev/null || true)" ]]; then
    return 0
  fi

  gh run list --branch main --limit 1 \
    --json databaseId,headSha,status,conclusion,url,workflowName,createdAt,updatedAt \
    --jq '.[0] | [.databaseId, .headSha, .status, (.conclusion // ""), .url] | @tsv' \
    2>/dev/null || true
}

CURRENT_SHORT="$(git_value rev-parse --short HEAD)"
CURRENT_FULL="$(git_value rev-parse HEAD)"
BRANCH="$(git_value branch --show-current)"
WORKING_TREE="$(working_tree_state)"

PREFLIGHT_REPORT="$ROOT_DIR/DerivedData/FinalSubmissionPreflight/submission-readiness-report.md"
RELEASE_PACKET="$ROOT_DIR/DerivedData/ReleasePacket/HTMLPreviewerReleasePacket.zip"
APP_STORE_CONNECT_RESULT="$(latest_file "$ROOT_DIR/DerivedData/AppStoreConnectRun" "app-store-connect-result.md")"
FINAL_SMOKE_RESULT="$(latest_file "$ROOT_DIR/DerivedData/FinalSmokeRun" "final-archive-smoke-result.md")"
PHYSICAL_DEVICE_RESULT="$(latest_file "$ROOT_DIR/DerivedData/PhysicalDeviceValidationRun" "physical-device-validation-result.md")"
USABILITY_RESULT="$(latest_file "$ROOT_DIR/DerivedData/UsabilitySessionRun" "first-round-usability-result.md")"
ARCHIVE_SMOKE_REPORT="$(latest_file "$ROOT_DIR/DerivedData/PhysicalDeviceSmoke" "archive-device-smoke-report.md")"
SIGNED_ARCHIVE_DIAGNOSTIC="$(latest_file "$ROOT_DIR/DerivedData/SignedArchiveDiagnostics" "signed-archive-diagnostic-report.md")"
SIGNING_READINESS="$(latest_file "$ROOT_DIR/DerivedData/SigningReadiness" "signing-readiness-report.md")"
GITHUB_DIAGNOSTIC="$(latest_file "$ROOT_DIR/DerivedData/GitHubActionsDiagnostics" "github-actions-diagnostics.md")"
COMPLETED_RESULTS_VALIDATION_REPORT="$ROOT_DIR/DerivedData/CompletedReleaseResultsValidation/completed-release-results-validation.md"

if [[ "$DRY_RUN" == true ]]; then
  printf 'Would prepare submission gate status report:\n'
  printf -- '- Report: %s\n' "$REPORT_PATH"
  printf -- '- Current commit: %s (%s)\n' "$CURRENT_SHORT" "$CURRENT_FULL"
  exit 0
fi

if [[ -f "$PREFLIGHT_REPORT" ]]; then
  preflight_status="$(report_field Status "$PREFLIGHT_REPORT")"
  preflight_tree="$(report_field "Working tree" "$PREFLIGHT_REPORT")"
  if [[ "$preflight_status" == "passed" ]] &&
    [[ "$preflight_tree" == "clean" ]] &&
    commit_matches_current "$PREFLIGHT_REPORT"; then
    add_gate "Final local preflight" "#10" "passed" "$PREFLIGHT_REPORT; $(commit_note "$PREFLIGHT_REPORT")" "Keep this report with release evidence."
  else
    add_gate "Final local preflight" "#10" "pending" "$PREFLIGHT_REPORT; status: ${preflight_status:-unknown}; working tree: ${preflight_tree:-unknown}; $(commit_note "$PREFLIGHT_REPORT")" "Rerun scripts/final-submission-preflight.sh on a clean final commit."
  fi
else
  add_gate "Final local preflight" "#10" "missing" "$PREFLIGHT_REPORT" "Run scripts/final-submission-preflight.sh on a clean final commit."
fi

if [[ -f "$RELEASE_PACKET" ]]; then
  add_gate "Release packet" "#10" "passed" "$RELEASE_PACKET" "Keep this packet with submission evidence."
else
  add_gate "Release packet" "#10" "missing" "$RELEASE_PACKET" "Run scripts/prepare-release-packet.sh."
fi

if [[ -f "$COMPLETED_RESULTS_VALIDATION_REPORT" ]] && commit_matches_current "$COMPLETED_RESULTS_VALIDATION_REPORT"; then
  completed_results_status="$(report_field Status "$COMPLETED_RESULTS_VALIDATION_REPORT")"
  case "$completed_results_status" in
    complete)
      add_gate "Completed manual result validation" "#1/#10/#11" "passed" "$COMPLETED_RESULTS_VALIDATION_REPORT; $(commit_note "$COMPLETED_RESULTS_VALIDATION_REPORT")" "Keep this report with release evidence."
      ;;
    invalid)
      add_gate "Completed manual result validation" "#1/#10/#11" "blocked" "$COMPLETED_RESULTS_VALIDATION_REPORT; status: invalid; $(commit_note "$COMPLETED_RESULTS_VALIDATION_REPORT")" "Fix placeholders, stale commits, empty required result cells, or unresolved P0/P1 follow-ups in completed result drafts."
      ;;
    failed)
      add_gate "Completed manual result validation" "#1/#10/#11" "pending" "$COMPLETED_RESULTS_VALIDATION_REPORT; status: failed; $(commit_note "$COMPLETED_RESULTS_VALIDATION_REPORT")" "Resolve the failed manual validation result before submission."
      ;;
    *)
      add_gate "Completed manual result validation" "#1/#10/#11" "pending" "$COMPLETED_RESULTS_VALIDATION_REPORT; status: ${completed_results_status:-unknown}; $(commit_note "$COMPLETED_RESULTS_VALIDATION_REPORT")" "Run scripts/validate-completed-release-results.sh --fail-on-invalid after manual results are filled."
      ;;
  esac
else
  add_gate "Completed manual result validation" "#1/#10/#11" "missing" "$COMPLETED_RESULTS_VALIDATION_REPORT" "Run scripts/validate-completed-release-results.sh after staging manual result drafts."
fi

github_summary="$(latest_github_actions_summary)"
if [[ -n "$github_summary" ]]; then
  IFS=$'\t' read -r run_id run_sha run_status run_conclusion run_url <<<"$github_summary"
  if [[ "$run_sha" == "$CURRENT_FULL" && "$run_status" == "completed" && "$run_conclusion" == "success" ]]; then
    add_gate "GitHub Actions iOS CI" "#10" "passed" "Run $run_id succeeded: $run_url" "Keep the green run URL with submission evidence."
  elif [[ "$run_sha" == "$CURRENT_FULL" ]]; then
    add_gate "GitHub Actions iOS CI" "#10" "blocked" "Run $run_id is $run_status/$run_conclusion: $run_url" "Resolve hosted Actions execution and rerun CI."
  else
    add_gate "GitHub Actions iOS CI" "#10" "pending" "Latest run $run_id is for ${run_sha:0:7}" "Rerun CI for current commit $CURRENT_SHORT."
  fi
elif [[ -f "$GITHUB_DIAGNOSTIC" ]] && grep -Fq "$CURRENT_FULL" "$GITHUB_DIAGNOSTIC"; then
  add_gate "GitHub Actions iOS CI" "#10" "blocked" "$GITHUB_DIAGNOSTIC reports zero-step failure for current commit" "Account owner must resolve Actions billing/policy/execution blocker and rerun CI."
else
  add_gate "GitHub Actions iOS CI" "#10" "pending" "No green CI evidence for current commit" "Run hosted CI or rerun this script with --check-github after CI completes."
fi

if [[ -f "$PHYSICAL_DEVICE_RESULT" ]] && commit_matches_current "$PHYSICAL_DEVICE_RESULT"; then
  physical_overall="$(report_field "Overall status" "$PHYSICAL_DEVICE_RESULT")"
  physical_close="$(report_field "Can close #1" "$PHYSICAL_DEVICE_RESULT")"
  physical_continue="$(report_field "Can continue App Store submission" "$PHYSICAL_DEVICE_RESULT")"
  if is_passed_value "$physical_overall" && is_yes_value "$physical_close" && is_yes_value "$physical_continue"; then
    add_gate "Physical-device external-open matrix" "#1" "passed" "$PHYSICAL_DEVICE_RESULT; $(commit_note "$PHYSICAL_DEVICE_RESULT")" "Attach/summarize result in #1."
  else
    add_gate "Physical-device external-open matrix" "#1" "pending" "$PHYSICAL_DEVICE_RESULT; $(commit_note "$PHYSICAL_DEVICE_RESULT")" "Complete Files/iCloud/Mail/AirDrop/messaging/Safari matrix and close criteria."
  fi
else
  add_gate "Physical-device external-open matrix" "#1" "missing" "${PHYSICAL_DEVICE_RESULT:-not generated}" "Run scripts/prepare-physical-device-validation-run.sh and complete the matrix on a physical iPhone."
fi

if [[ -f "$APP_STORE_CONNECT_RESULT" ]] && commit_matches_current "$APP_STORE_CONNECT_RESULT"; then
  asc_overall="$(report_field "Overall status" "$APP_STORE_CONNECT_RESULT")"
  asc_continue="$(report_field "Can continue final archive/TestFlight smoke" "$APP_STORE_CONNECT_RESULT")"
  if is_passed_value "$asc_overall" && is_yes_value "$asc_continue"; then
    add_gate "App Store Connect paid-download setup" "#10" "passed" "$APP_STORE_CONNECT_RESULT; $(commit_note "$APP_STORE_CONNECT_RESULT")" "Keep the completed App Store Connect setup result with release evidence."
  else
    add_gate "App Store Connect paid-download setup" "#10" "pending" "$APP_STORE_CONNECT_RESULT; $(commit_note "$APP_STORE_CONNECT_RESULT")" "Complete app record, pricing, privacy labels, screenshots, age rating, export compliance, and build selection."
  fi
else
  add_gate "App Store Connect paid-download setup" "#10" "missing" "${APP_STORE_CONNECT_RESULT:-not generated}" "Run scripts/prepare-app-store-connect-run.sh while the account owner enters App Store Connect fields."
fi

if [[ -f "$ARCHIVE_SMOKE_REPORT" ]] && commit_matches_current "$ARCHIVE_SMOKE_REPORT"; then
  archive_status="$(report_field Status "$ARCHIVE_SMOKE_REPORT")"
  archive_submission="$(report_field "App Store/TestFlight submission evidence" "$ARCHIVE_SMOKE_REPORT")"
  if is_passed_value "$archive_status" && [[ "$(lower_value "$archive_submission")" == "yes" ]]; then
    add_gate "Distribution archive or TestFlight upload evidence" "#10" "passed" "$ARCHIVE_SMOKE_REPORT; $(commit_note "$ARCHIVE_SMOKE_REPORT")" "Use this as App Store/TestFlight evidence."
  elif is_passed_value "$archive_status"; then
    add_gate "Distribution archive or TestFlight upload evidence" "#10" "pending" "$ARCHIVE_SMOKE_REPORT; App Store/TestFlight evidence: ${archive_submission:-unknown}" "Create an Apple Distribution archive or processed TestFlight build; development-signed smoke is local-only."
  else
    add_gate "Distribution archive or TestFlight upload evidence" "#10" "pending" "$ARCHIVE_SMOKE_REPORT; status: ${archive_status:-unknown}" "Create and smoke-test the final uploadable build."
  fi
elif [[ -f "$SIGNED_ARCHIVE_DIAGNOSTIC" ]] && commit_matches_current "$SIGNED_ARCHIVE_DIAGNOSTIC"; then
  signed_archive_status="$(report_field Status "$SIGNED_ARCHIVE_DIAGNOSTIC")"
  signed_archive_summary="$(report_field Summary "$SIGNED_ARCHIVE_DIAGNOSTIC")"
  signed_archive_submission="$(report_field "App Store/TestFlight submission evidence" "$SIGNED_ARCHIVE_DIAGNOSTIC")"
  signing_readiness_status=""
  signing_readiness_archive=""
  if [[ -f "$SIGNING_READINESS" ]] && commit_matches_current "$SIGNING_READINESS"; then
    signing_readiness_status="$(report_field Status "$SIGNING_READINESS")"
    signing_readiness_archive="$(report_field "App Store/TestFlight archive readiness" "$SIGNING_READINESS")"
  fi
  if is_passed_value "$signed_archive_status" && [[ "$(lower_value "$signed_archive_submission")" == "yes" ]]; then
    add_gate "Distribution archive or TestFlight upload evidence" "#10" "pending" "$SIGNED_ARCHIVE_DIAGNOSTIC; $(commit_note "$SIGNED_ARCHIVE_DIAGNOSTIC")" "Upload/select the processed build, then capture final archive/TestFlight smoke evidence."
  elif is_passed_value "$signed_archive_status" && [[ "$(lower_value "$signing_readiness_archive")" == "blocked" ]]; then
    add_gate "Distribution archive or TestFlight upload evidence" "#10" "blocked" "$SIGNED_ARCHIVE_DIAGNOSTIC; $SIGNING_READINESS; archive is development/local-only; signing readiness: ${signing_readiness_status:-unknown}" "Install/create the matching Apple Distribution signing assets, rerun scripts/check-signing-readiness.sh, then create upload evidence."
  elif [[ "$(lower_value "$signed_archive_status")" == "failed" ]]; then
    add_gate "Distribution archive or TestFlight upload evidence" "#10" "blocked" "$SIGNED_ARCHIVE_DIAGNOSTIC; summary: ${signed_archive_summary:-unknown}; $(commit_note "$SIGNED_ARCHIVE_DIAGNOSTIC")" "Configure Xcode Apple account/provisioning profile or App Store Distribution signing, then rerun scripts/create-signed-archive.sh."
  else
    add_gate "Distribution archive or TestFlight upload evidence" "#10" "pending" "$SIGNED_ARCHIVE_DIAGNOSTIC; status: ${signed_archive_status:-unknown}; $(commit_note "$SIGNED_ARCHIVE_DIAGNOSTIC")" "Create an Apple Distribution archive or processed TestFlight build, then capture smoke evidence."
  fi
elif [[ -f "$SIGNING_READINESS" ]] && commit_matches_current "$SIGNING_READINESS"; then
  signing_readiness_status="$(report_field Status "$SIGNING_READINESS")"
  signing_readiness_archive="$(report_field "App Store/TestFlight archive readiness" "$SIGNING_READINESS")"
  if [[ "$(lower_value "$signing_readiness_archive")" == "blocked" ]]; then
    add_gate "Distribution archive or TestFlight upload evidence" "#10" "blocked" "$SIGNING_READINESS; status: ${signing_readiness_status:-unknown}; $(commit_note "$SIGNING_READINESS")" "Install/create Apple Distribution signing assets, rerun scripts/check-signing-readiness.sh, then create upload evidence."
  else
    add_gate "Distribution archive or TestFlight upload evidence" "#10" "pending" "$SIGNING_READINESS; status: ${signing_readiness_status:-unknown}; $(commit_note "$SIGNING_READINESS")" "Create an Apple Distribution archive or processed TestFlight build, then capture smoke evidence."
  fi
else
  add_gate "Distribution archive or TestFlight upload evidence" "#10" "missing" "${ARCHIVE_SMOKE_REPORT:-not generated}" "Run scripts/create-signed-archive.sh with Apple Distribution signing, upload/select build, then capture smoke evidence."
fi

if [[ -f "$FINAL_SMOKE_RESULT" ]] && commit_matches_current "$FINAL_SMOKE_RESULT"; then
  final_overall="$(report_field "Overall status" "$FINAL_SMOKE_RESULT")"
  final_submit="$(report_field "Can submit for review" "$FINAL_SMOKE_RESULT")"
  if is_passed_value "$final_overall" && is_yes_value "$final_submit"; then
    add_gate "Final archive/TestFlight smoke" "#10" "passed" "$FINAL_SMOKE_RESULT; $(commit_note "$FINAL_SMOKE_RESULT")" "Attach/summarize result in #10."
  else
    add_gate "Final archive/TestFlight smoke" "#10" "pending" "$FINAL_SMOKE_RESULT; $(commit_note "$FINAL_SMOKE_RESULT")" "Run final smoke on the distribution archive or TestFlight build and fill close criteria."
  fi
else
  add_gate "Final archive/TestFlight smoke" "#10" "missing" "${FINAL_SMOKE_RESULT:-not generated}" "Run scripts/prepare-final-smoke-run.sh and complete the final smoke pass."
fi

if [[ -f "$USABILITY_RESULT" ]] && commit_matches_current "$USABILITY_RESULT"; then
  usability_close="$(report_field "Can close #11" "$USABILITY_RESULT")"
  usability_continue="$(report_field "Can continue App Store submission" "$USABILITY_RESULT")"
  if is_yes_value "$usability_close" && is_yes_value "$usability_continue"; then
    add_gate "First external usability round" "#11" "passed" "$USABILITY_RESULT; $(commit_note "$USABILITY_RESULT")" "Attach/summarize result in #11."
  else
    add_gate "First external usability round" "#11" "pending" "$USABILITY_RESULT; $(commit_note "$USABILITY_RESULT")" "Run the session with an external participant and file/fix every P0/P1 finding."
  fi
else
  add_gate "First external usability round" "#11" "missing" "${USABILITY_RESULT:-not generated}" "Run scripts/prepare-usability-session-run.sh and complete the external session."
fi

if [[ "$BLOCKING_COUNT" -gt 0 ]]; then
  OVERALL_STATUS="blocked"
elif [[ "$PENDING_COUNT" -gt 0 ]]; then
  OVERALL_STATUS="pending"
else
  OVERALL_STATUS="ready"
fi

mkdir -p "$OUTPUT_ROOT"
{
  printf '# Submission Gate Status Report\n\n'
  printf -- '- Status: %s\n' "$OVERALL_STATUS"
  printf -- '- Generated: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf -- '- Branch: %s\n' "$BRANCH"
  printf -- '- Commit: %s\n' "$CURRENT_SHORT"
  printf -- '- Full commit: %s\n' "$CURRENT_FULL"
  printf -- '- Working tree: %s\n' "$WORKING_TREE"
  printf -- '- Passed gates: %s\n' "$PASSED_COUNT"
  printf -- '- Pending gates: %s\n' "$PENDING_COUNT"
  printf -- '- Blocking gates: %s\n' "$BLOCKING_COUNT"
  printf '\n## Gate Matrix\n\n'
  printf '| Gate | Issue | Status | Evidence | Next action |\n'
  printf '|---|---:|---|---|---|\n'
  printf '%s\n' "${GATE_ROWS[@]}"
  printf '\n## Status Semantics\n\n'
  printf -- '- `passed`: evidence proves the gate is complete for the current commit.\n'
  printf -- '- `pending`: evidence exists or can be produced, but a required manual/external step is not complete.\n'
  printf -- '- `blocked`: an external system state currently prevents completion.\n'
  printf -- '- `missing`: required evidence was not found for the current commit.\n'
  printf '\n## Strict Check\n\n'
  printf 'Run `scripts/prepare-submission-gate-status.sh --check-github --fail-on-not-ready` only after App Store Connect, TestFlight/archive smoke, physical-device validation, usability testing, and hosted CI are expected to be complete.\n'
} > "$REPORT_PATH"

printf 'Prepared submission gate status report: %s\n' "$REPORT_PATH"
printf 'Submission gate status: %s\n' "$OVERALL_STATUS"

if [[ "$FAIL_ON_NOT_READY" == true && "$OVERALL_STATUS" != "ready" ]]; then
  exit 1
fi
