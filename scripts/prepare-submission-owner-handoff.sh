#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT_DIR/DerivedData/SubmissionOwnerHandoff}"
REPORT_PATH="$OUTPUT_ROOT/submission-owner-handoff.md"
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: scripts/prepare-submission-owner-handoff.sh [options]

Writes a handoff report for the external/manual owners who must complete the
remaining App Store submission gates. This script does not modify GitHub,
App Store Connect, devices, or result drafts; it only summarizes the current
evidence paths and exact completion criteria.

Options:
  --dry-run   Print planned report path without writing files.
  -h, --help  Show this help.
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
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

md_escape() {
  printf '%s' "$1" | sed 's/|/\\|/g'
}

path_or_missing() {
  local path="$1"
  if [[ -n "$path" && -e "$path" ]]; then
    printf '%s' "$path"
  else
    printf 'not generated'
  fi
}

latest_actions_run() {
  if command -v gh >/dev/null 2>&1; then
    gh run list --branch main --limit 1 \
      --json databaseId,headSha,status,conclusion,url \
      --jq '.[0] | [.databaseId, .headSha, .status, (.conclusion // ""), .url] | @tsv' \
      2>/dev/null || true
  fi
}

CURRENT_SHORT="$(git_value rev-parse --short HEAD)"
CURRENT_FULL="$(git_value rev-parse HEAD)"
BRANCH="$(git_value branch --show-current)"
WORKING_TREE="$(working_tree_state)"

PREFLIGHT_REPORT="$ROOT_DIR/DerivedData/FinalSubmissionPreflight/submission-readiness-report.md"
RELEASE_PACKET="$ROOT_DIR/DerivedData/ReleasePacket/HTMLPreviewerReleasePacket.zip"
SUBMISSION_GATE_STATUS_REPORT="$ROOT_DIR/DerivedData/SubmissionGateStatus/submission-gate-status-report.md"
COMPLETED_RESULTS_VALIDATION_REPORT="$ROOT_DIR/DerivedData/CompletedReleaseResultsValidation/completed-release-results-validation.md"
APP_STORE_CONNECT_RESULT="$(latest_file "$ROOT_DIR/DerivedData/AppStoreConnectRun" "app-store-connect-result.md")"
FINAL_SMOKE_RESULT="$(latest_file "$ROOT_DIR/DerivedData/FinalSmokeRun" "final-archive-smoke-result.md")"
PHYSICAL_DEVICE_RESULT="$(latest_file "$ROOT_DIR/DerivedData/PhysicalDeviceValidationRun" "physical-device-validation-result.md")"
USABILITY_RESULT="$(latest_file "$ROOT_DIR/DerivedData/UsabilitySessionRun" "first-round-usability-result.md")"
ARCHIVE_SMOKE_REPORT="$(latest_file "$ROOT_DIR/DerivedData/PhysicalDeviceSmoke" "archive-device-smoke-report.md")"
SIGNED_ARCHIVE_DIAGNOSTIC="$(latest_file "$ROOT_DIR/DerivedData/SignedArchiveDiagnostics" "signed-archive-diagnostic-report.md")"
GITHUB_DIAGNOSTIC="$(latest_file "$ROOT_DIR/DerivedData/GitHubActionsDiagnostics" "github-actions-diagnostics.md")"

GATE_STATUS="$(report_field Status "$SUBMISSION_GATE_STATUS_REPORT")"
PREFLIGHT_STATUS="$(report_field Status "$PREFLIGHT_REPORT")"
COMPLETED_RESULTS_STATUS="$(report_field Status "$COMPLETED_RESULTS_VALIDATION_REPORT")"
ARCHIVE_SUBMISSION_EVIDENCE="$(report_field "App Store/TestFlight submission evidence" "$ARCHIVE_SMOKE_REPORT")"
ARCHIVE_SUBMISSION_NOTE="$(report_field "Submission evidence note" "$ARCHIVE_SMOKE_REPORT")"
SIGNED_ARCHIVE_STATUS="$(report_field Status "$SIGNED_ARCHIVE_DIAGNOSTIC")"
latest_actions_summary="$(latest_actions_run)"

if [[ "$DRY_RUN" == true ]]; then
  printf 'Would prepare submission owner handoff report:\n'
  printf -- '- Report: %s\n' "$REPORT_PATH"
  printf -- '- Commit: %s (%s)\n' "$CURRENT_SHORT" "$CURRENT_FULL"
  exit 0
fi

mkdir -p "$OUTPUT_ROOT"

{
  printf '# Submission Owner Handoff\n\n'
  printf -- '- Generated: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf -- '- Branch: %s\n' "$BRANCH"
  printf -- '- Commit: %s\n' "$CURRENT_SHORT"
  printf -- '- Full commit: %s\n' "$CURRENT_FULL"
  printf -- '- Working tree: %s\n' "$WORKING_TREE"
  printf -- '- Submission gate status: %s\n' "${GATE_STATUS:-not generated}"
  printf -- '- Final preflight status: %s\n' "${PREFLIGHT_STATUS:-not generated}"
  printf -- '- Completed manual result validation status: %s\n' "${COMPLETED_RESULTS_STATUS:-not generated}"
  printf '\n## Purpose\n\n'
  printf 'Use this report as the single owner-facing checklist after local release preflight passes. It separates local evidence from external actions that require a GitHub account owner, App Store Connect account owner, physical device tester, or usability moderator.\n'

  printf '\n## Owner Action Table\n\n'
  printf '| Owner | Issue | Required action | Starting evidence | Done when | Follow-up command |\n'
  printf '|---|---:|---|---|---|---|\n'
  printf '| GitHub account owner | #10 | Resolve the hosted Actions execution-layer failure where jobs finish with zero recorded steps. Check repository Actions policy, account/org billing budgets, and parent org/enterprise policies. | `%s` | Latest `main` run for `%s` is `completed/success` and has normal step logs. | `scripts/check-github-actions-execution.sh --run-id <run-id>` then `scripts/prepare-submission-gate-status.sh --check-github` |\n' "$(md_escape "$(path_or_missing "$GITHUB_DIAGNOSTIC")")" "$CURRENT_SHORT"
  printf '| App Store Connect account owner | #10 | Complete app record, paid-download pricing, availability, privacy labels, age rating, export compliance, screenshots, review notes, and processed build selection. | `%s` | Result draft records `Overall status: passed` and `Can continue final archive/TestFlight smoke: yes`; no completed-result validator findings. | `scripts/validate-completed-release-results.sh --fail-on-invalid` |\n' "$(md_escape "$(path_or_missing "$APP_STORE_CONNECT_RESULT")")"
  printf '| Signing/upload owner | #10 | Create an Apple Distribution archive or processed TestFlight build. Development-signed local smoke cannot count as upload evidence. If signing diagnostics show No Accounts or no matching profiles, configure Xcode Accounts and provisioning first. | `%s`; diagnostic: `%s` | Archive/TestFlight evidence records App Store/TestFlight submission evidence as `yes`. | `DEVELOPMENT_TEAM=<Apple Team ID> scripts/create-signed-archive.sh` then upload/select build |\n' "$(md_escape "$(path_or_missing "$ARCHIVE_SMOKE_REPORT")")" "$(md_escape "$(path_or_missing "$SIGNED_ARCHIVE_DIAGNOSTIC")")"
  printf '| Physical-device tester | #1 | Complete Files, iCloud Drive, Mail, AirDrop, messaging app, and Safari source matrix on a real iPhone. | `%s` | Result draft records `Overall status: passed`, `Can close #1: yes`, and `Can continue App Store submission: yes`; all P0/P1 findings filed or fixed. | `scripts/validate-completed-release-results.sh --fail-on-invalid` |\n' "$(md_escape "$(path_or_missing "$PHYSICAL_DEVICE_RESULT")")"
  printf '| Final smoke tester | #10 | Run built-in HTML, Markdown, ZIP, Safe Preview, Settings, recent reopen, and delete smoke on the final archive/TestFlight build. | `%s` | Final smoke result records `Overall status: passed` and `Can submit for review: yes`. | `scripts/validate-completed-release-results.sh --fail-on-invalid` |\n' "$(md_escape "$(path_or_missing "$FINAL_SMOKE_RESULT")")"
  printf '| Usability moderator | #11 | Run at least one external participant session using anonymous participant code; avoid personal identifiers in notes. | `%s` | Result draft records all P0/P1 findings filed or fixed, `Can close #11: yes`, and `Can continue App Store submission: yes`. | `scripts/validate-completed-release-results.sh --fail-on-invalid` |\n' "$(md_escape "$(path_or_missing "$USABILITY_RESULT")")"
  printf '| Release operator | #1/#10/#11 | After all owner actions are complete, run strict local gates and attach summaries to GitHub issues. | `%s` | `scripts/prepare-submission-gate-status.sh --check-github --fail-on-not-ready` exits 0 and reports `Status: ready`. | `scripts/final-submission-preflight.sh` then `scripts/prepare-submission-gate-status.sh --check-github --fail-on-not-ready` |\n' "$(md_escape "$(path_or_missing "$COMPLETED_RESULTS_VALIDATION_REPORT")")"

  printf '\n## Current Evidence Paths\n\n'
  printf '| Evidence | Path | Status |\n'
  printf '|---|---|---|\n'
  printf '| Final local preflight | `%s` | %s |\n' "$(md_escape "$(path_or_missing "$PREFLIGHT_REPORT")")" "${PREFLIGHT_STATUS:-not generated}"
  printf '| Release packet | `%s` | %s |\n' "$(md_escape "$(path_or_missing "$RELEASE_PACKET")")" "$(if [[ -f "$RELEASE_PACKET" ]]; then printf 'generated'; else printf 'not generated'; fi)"
  printf '| Submission gate status | `%s` | %s |\n' "$(md_escape "$(path_or_missing "$SUBMISSION_GATE_STATUS_REPORT")")" "${GATE_STATUS:-not generated}"
  printf '| Completed manual result validation | `%s` | %s |\n' "$(md_escape "$(path_or_missing "$COMPLETED_RESULTS_VALIDATION_REPORT")")" "${COMPLETED_RESULTS_STATUS:-not generated}"
  printf '| GitHub Actions diagnostic | `%s` | %s |\n' "$(md_escape "$(path_or_missing "$GITHUB_DIAGNOSTIC")")" "$(if [[ -f "$GITHUB_DIAGNOSTIC" ]]; then printf 'available'; else printf 'not generated'; fi)"
  printf '| Physical-device validation draft | `%s` | %s |\n' "$(md_escape "$(path_or_missing "$PHYSICAL_DEVICE_RESULT")")" "$(if [[ -f "$PHYSICAL_DEVICE_RESULT" ]]; then printf 'draft'; else printf 'not generated'; fi)"
  printf '| App Store Connect result draft | `%s` | %s |\n' "$(md_escape "$(path_or_missing "$APP_STORE_CONNECT_RESULT")")" "$(if [[ -f "$APP_STORE_CONNECT_RESULT" ]]; then printf 'draft'; else printf 'not generated'; fi)"
  printf '| Archive device smoke report | `%s` | App Store/TestFlight evidence: %s |\n' "$(md_escape "$(path_or_missing "$ARCHIVE_SMOKE_REPORT")")" "${ARCHIVE_SUBMISSION_EVIDENCE:-not recorded}"
  printf '| Signed archive diagnostic | `%s` | %s |\n' "$(md_escape "$(path_or_missing "$SIGNED_ARCHIVE_DIAGNOSTIC")")" "${SIGNED_ARCHIVE_STATUS:-not generated}"
  printf '| Final archive/TestFlight smoke draft | `%s` | %s |\n' "$(md_escape "$(path_or_missing "$FINAL_SMOKE_RESULT")")" "$(if [[ -f "$FINAL_SMOKE_RESULT" ]]; then printf 'draft'; else printf 'not generated'; fi)"
  printf '| First-round usability result draft | `%s` | %s |\n' "$(md_escape "$(path_or_missing "$USABILITY_RESULT")")" "$(if [[ -f "$USABILITY_RESULT" ]]; then printf 'draft'; else printf 'not generated'; fi)"

  printf '\n## Latest Hosted CI\n\n'
  if [[ -n "$latest_actions_summary" ]]; then
    IFS=$'\t' read -r run_id run_sha run_status run_conclusion run_url <<<"$latest_actions_summary"
    printf -- '- Run id: %s\n' "$run_id"
    printf -- '- Run SHA: %s\n' "$run_sha"
    printf -- '- Status/conclusion: %s/%s\n' "$run_status" "${run_conclusion:-none}"
    printf -- '- URL: %s\n' "$run_url"
  else
    printf -- '- Latest hosted CI run could not be read through gh in this environment.\n'
  fi

  printf '\n## Evidence Rules\n\n'
  printf -- '- Do not treat a development-signed archive as App Store/TestFlight upload evidence.\n'
  printf -- '- Current archive evidence note: %s\n' "${ARCHIVE_SUBMISSION_NOTE:-not recorded}"
  printf -- '- Do not close #1, #10, or #11 until `scripts/validate-completed-release-results.sh --fail-on-invalid` passes after the manual drafts are filled.\n'
  printf -- '- Do not treat the release as submission-ready until `scripts/prepare-submission-gate-status.sh --check-github --fail-on-not-ready` passes.\n'
  printf -- '- Result drafts marked complete but containing placeholders, failed/not-tested required cells, stale commit evidence, or unresolved P0/P1 rows must be fixed first.\n'

  printf '\n## Suggested Order\n\n'
  printf '1. GitHub account owner resolves the zero-step Actions blocker and reruns CI.\n'
  printf '2. Physical-device tester completes #1 external-open validation.\n'
  printf '3. App Store Connect account owner completes paid-download setup and selects the processed build.\n'
  printf '4. Signing/upload owner provides Apple Distribution or TestFlight evidence.\n'
  printf '5. Final smoke tester completes final archive/TestFlight smoke.\n'
  printf '6. Usability moderator completes the first external participant session.\n'
  printf '7. Release operator runs completed-result validation and strict submission gate status, then summarizes results in #1, #10, and #11.\n'
} > "$REPORT_PATH"

printf 'Prepared submission owner handoff report: %s\n' "$REPORT_PATH"
printf 'Submission owner handoff status: %s\n' "${GATE_STATUS:-not generated}"
