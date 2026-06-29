#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT_DIR/DerivedData/LocalAutomatedTests}"
STATUS=""
PASSED_COUNT=""
FAILED_COUNT=""
SKIPPED_COUNT=""
DURATION_MS=""
TARGET="simulator"
TOOL="XcodeBuildMCP test_sim"
BUILD_LOG=""
XCRESULT=""
COMMAND=""
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: scripts/prepare-local-automated-test-report.sh [options]

Writes a local automated simulator test evidence report and copies optional
test artifacts into DerivedData/LocalAutomatedTests. This is supplemental local
evidence and does not replace the required hosted GitHub Actions CI gate.

Options:
  --status VALUE        Required. Test status, for example SUCCEEDED or FAILED.
  --passed-count N      Required. Number of passed tests.
  --failed-count N      Required. Number of failed tests.
  --skipped-count N     Required. Number of skipped tests.
  --duration-ms N       Required. Test duration in milliseconds.
  --target VALUE        Test target/device label. Defaults to simulator.
  --tool VALUE          Test runner label. Defaults to XcodeBuildMCP test_sim.
  --build-log PATH      Optional build log artifact to copy.
  --xcresult PATH       Optional .xcresult bundle artifact to copy.
  --command VALUE       Optional command or MCP invocation summary.
  --dry-run             Print planned report path without writing files.
  -h, --help            Show this help.
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --status)
      STATUS="${2:-}"
      shift 2
      ;;
    --passed-count)
      PASSED_COUNT="${2:-}"
      shift 2
      ;;
    --failed-count)
      FAILED_COUNT="${2:-}"
      shift 2
      ;;
    --skipped-count)
      SKIPPED_COUNT="${2:-}"
      shift 2
      ;;
    --duration-ms)
      DURATION_MS="${2:-}"
      shift 2
      ;;
    --target)
      TARGET="${2:-}"
      shift 2
      ;;
    --tool)
      TOOL="${2:-}"
      shift 2
      ;;
    --build-log)
      BUILD_LOG="${2:-}"
      shift 2
      ;;
    --xcresult)
      XCRESULT="${2:-}"
      shift 2
      ;;
    --command)
      COMMAND="${2:-}"
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

require_value() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    printf 'Missing required option: %s\n\n' "$name" >&2
    usage >&2
    exit 2
  fi
}

require_integer() {
  local name="$1"
  local value="$2"
  require_value "$name" "$value"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    printf '%s must be a non-negative integer, found: %s\n' "$name" "$value" >&2
    exit 2
  fi
}

normalize_status() {
  local value
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    succeeded|success|passed|pass)
      printf 'passed'
      ;;
    failed|failure|fail)
      printf 'failed'
      ;;
    *)
      printf '%s' "$value"
      ;;
  esac
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

require_value "--status" "$STATUS"
require_integer "--passed-count" "$PASSED_COUNT"
require_integer "--failed-count" "$FAILED_COUNT"
require_integer "--skipped-count" "$SKIPPED_COUNT"
require_integer "--duration-ms" "$DURATION_MS"

normalized_status="$(normalize_status "$STATUS")"
timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
run_dir="$OUTPUT_ROOT/$timestamp-local-automated-tests"
report_path="$run_dir/local-automated-test-report.md"

if [[ "$DRY_RUN" == true ]]; then
  printf 'Would prepare local automated test report:\n'
  printf -- '- Report: %s\n' "$report_path"
  printf -- '- Status: %s\n' "$normalized_status"
  exit 0
fi

mkdir -p "$run_dir/artifacts"

build_log_copy="not provided"
if [[ -n "$BUILD_LOG" ]]; then
  if [[ ! -f "$BUILD_LOG" ]]; then
    printf 'Build log not found: %s\n' "$BUILD_LOG" >&2
    exit 1
  fi
  cp "$BUILD_LOG" "$run_dir/artifacts/build.log"
  build_log_copy="$run_dir/artifacts/build.log"
fi

xcresult_copy="not provided"
if [[ -n "$XCRESULT" ]]; then
  if [[ ! -d "$XCRESULT" ]]; then
    printf 'xcresult bundle not found: %s\n' "$XCRESULT" >&2
    exit 1
  fi
  rm -rf "$run_dir/artifacts/test.xcresult"
  cp -R "$XCRESULT" "$run_dir/artifacts/test.xcresult"
  xcresult_copy="$run_dir/artifacts/test.xcresult"
fi

{
  printf '# Local Automated Test Report\n\n'
  printf -- '- Status: %s\n' "$normalized_status"
  printf -- '- Generated: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf -- '- Branch: %s\n' "$(git_value branch --show-current)"
  printf -- '- Commit: %s\n' "$(git_value rev-parse --short HEAD)"
  printf -- '- Full commit: %s\n' "$(git_value rev-parse HEAD)"
  printf -- '- Working tree: %s\n' "$(working_tree_state)"
  printf -- '- Tool: %s\n' "$TOOL"
  printf -- '- Target: %s\n' "$TARGET"
  printf -- '- Duration ms: %s\n' "$DURATION_MS"
  printf -- '- Passed tests: %s\n' "$PASSED_COUNT"
  printf -- '- Failed tests: %s\n' "$FAILED_COUNT"
  printf -- '- Skipped tests: %s\n' "$SKIPPED_COUNT"
  printf -- '- Hosted CI substitute: no\n'
  printf -- '- Evidence note: Supplemental local simulator test evidence only; hosted GitHub Actions must still pass for submission readiness.\n'
  printf -- '- Build log: %s\n' "$build_log_copy"
  printf -- '- Result bundle: %s\n' "$xcresult_copy"
  if [[ -n "$COMMAND" ]]; then
    printf -- '- Command: %s\n' "$COMMAND"
  fi
  printf '\n## Test Summary\n\n'
  printf '| Result | Count |\n'
  printf '|---|---:|\n'
  printf '| Passed | %s |\n' "$PASSED_COUNT"
  printf '| Failed | %s |\n' "$FAILED_COUNT"
  printf '| Skipped | %s |\n' "$SKIPPED_COUNT"
  printf '\n## Required Follow-Up\n\n'
  printf -- '- Keep the hosted GitHub Actions iOS CI gate separate from this local report.\n'
  printf -- '- If this report is stale for the final commit, rerun simulator tests and regenerate it before building the final release packet.\n'
} >"$report_path"

printf 'Prepared local automated test report: %s\n' "$report_path"
