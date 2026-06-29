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
    printf -- '- Preflight logs: `DerivedData/FinalSubmissionPreflight/logs/`\n'

    printf '\n## Manual Gates Still Required\n\n'
    printf -- '- #1: Run the physical-device external-open matrix on a real iPhone and record `docs/physical-device-validation-result-template.md`.\n'
    printf -- '- #11: Run the first usability round with at least one external participant and record `docs/usability-testing/first-round-result-template.md`.\n'
    printf -- '- #10: Run `DEVELOPMENT_TEAM=<Apple Team ID> scripts/create-signed-archive.sh` with the account owner Apple Distribution signing setup. Do not count `ALLOW_DEVELOPMENT_SIGNING=YES` archives as upload evidence.\n'
    printf -- '- #10: If using an archived build for smoke, run `scripts/run-archive-device-smoke.sh --device <device-id-or-name>` on an unlocked physical device and keep the generated report.\n'
    printf -- '- #10: Upload/select the processed App Store Connect build, then complete final archive/TestFlight smoke using `docs/final-archive-smoke-test-template.md`.\n'
  } >"$REPORT_PATH"
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
    printf 'Wrote preflight report: %s\n' "$REPORT_PATH" >&2
    exit 1
  fi
}

rm -rf "$OUTPUT_ROOT"
mkdir -p "$LOG_DIR"

run_step "Release audit" "$ROOT_DIR/scripts/release-audit.sh"
run_step "Public App Store pages" "$ROOT_DIR/scripts/verify-public-pages.sh"
run_step "Release packet staging" "$ROOT_DIR/scripts/prepare-release-packet.sh"
run_step "Usability test packet staging" "$ROOT_DIR/scripts/prepare-usability-test-packet.sh"
run_step "Validation sample browser delivery staging" "$ROOT_DIR/scripts/serve-validation-samples.sh" --prepare-only
run_step "Signed archive dry-run" env DEVELOPMENT_TEAM=ABCDE12345 "$ROOT_DIR/scripts/create-signed-archive.sh" --dry-run

if [[ "$RUN_BUILDS" == true ]]; then
  run_step "Generic iOS Release build" "$ROOT_DIR/scripts/release-device-build.sh"
  run_step "Generic iOS archive preflight" "$ROOT_DIR/scripts/archive-preflight.sh"
else
  SKIPPED_STEPS+=("Generic iOS Release build")
  SKIPPED_STEPS+=("Generic iOS archive preflight")
fi

write_report "passed"
printf 'Final submission preflight passed.\n'
printf 'Wrote preflight report: %s\n' "$REPORT_PATH"
