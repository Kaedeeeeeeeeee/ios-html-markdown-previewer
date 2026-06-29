#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/DerivedData/SignedArchive/HTMLPreviewer.xcarchive}"
APP_PATH="${APP_PATH:-$ARCHIVE_PATH/Products/Applications/HTMLMarkdownPreviewer.app}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT_DIR/DerivedData/PhysicalDeviceSmoke}"
DEVICE_ID="${DEVICE_ID:-}"
SKIP_LAUNCH=false
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: scripts/run-archive-device-smoke.sh --device <device-id-or-name> [options]

Installs the archived app on a physical device, attempts to launch it, captures
a launch screenshot when possible, and writes a Markdown smoke report plus
devicectl JSON/log artifacts.

Environment:
  ARCHIVE_PATH   Optional .xcarchive path. Defaults to DerivedData/SignedArchive/HTMLPreviewer.xcarchive.
  APP_PATH       Optional .app path. Defaults to Products/Applications/HTMLMarkdownPreviewer.app inside ARCHIVE_PATH.
  OUTPUT_ROOT    Optional artifact directory. Defaults to DerivedData/PhysicalDeviceSmoke.
  DEVICE_ID      Optional device id/name; overridden by --device.

Options:
  --device VALUE  Required target device identifier, UDID, device name, or DNS name.
  --skip-launch   Install only and mark launch as skipped.
  --dry-run       Print the planned install/launch commands without running them.
  -h, --help      Show this help.

Use `xcrun devicectl list devices` to find connected physical device ids.
Unlock the device before running if launch evidence is required.
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --device)
      if [[ "$#" -lt 2 || -z "$2" ]]; then
        printf 'Missing value for --device.\n' >&2
        exit 2
      fi
      DEVICE_ID="$2"
      shift 2
      ;;
    --skip-launch)
      SKIP_LAUNCH=true
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

if [[ -z "$DEVICE_ID" ]]; then
  printf 'Set --device or DEVICE_ID to a physical device id/name.\n' >&2
  printf 'Run `xcrun devicectl list devices` to find available devices.\n' >&2
  exit 2
fi

BUNDLE_ID="com.kaede.htmlmarkdownpreviewer"
APP_VERSION="unknown"
BUILD_NUMBER="unknown"

if [[ -d "$APP_PATH" ]]; then
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist" 2>/dev/null || true)"
  APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Info.plist" 2>/dev/null || printf 'unknown')"
  BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Info.plist" 2>/dev/null || printf 'unknown')"
elif [[ "$DRY_RUN" == false ]]; then
  printf 'Archived app not found: %s\n' "$APP_PATH" >&2
  printf 'Create an archive first with `DEVELOPMENT_TEAM=<Apple Team ID> scripts/create-signed-archive.sh`.\n' >&2
  exit 2
fi

if [[ -z "$BUNDLE_ID" ]]; then
  printf 'Could not read CFBundleIdentifier from %s/Info.plist\n' "$APP_PATH" >&2
  exit 2
fi

safe_device="$(printf '%s' "$DEVICE_ID" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-')"
timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
run_dir="$OUTPUT_ROOT/$timestamp-$safe_device"
install_json="$run_dir/install.json"
install_log="$run_dir/install.log"
launch_json="$run_dir/launch.json"
launch_log="$run_dir/launch.log"
screenshot_png="$run_dir/launch-screenshot.png"
screenshot_json="$run_dir/screenshot.json"
screenshot_log="$run_dir/screenshot.log"
report_path="$run_dir/archive-device-smoke-report.md"

git_value() {
  git -C "$ROOT_DIR" "$@" 2>/dev/null || printf 'unknown'
}

if [[ "$DRY_RUN" == true ]]; then
  printf 'Would install archived app:\n'
  printf '  xcrun devicectl device install app --device %q --json-output %q %q\n' "$DEVICE_ID" "$install_json" "$APP_PATH"
  if [[ "$SKIP_LAUNCH" == false ]]; then
    printf 'Would launch app:\n'
    printf '  xcrun devicectl device process launch --device %q --json-output %q --terminate-existing %q\n' "$DEVICE_ID" "$launch_json" "$BUNDLE_ID"
    printf 'Would capture launch screenshot:\n'
    printf '  xcrun devicectl device capture screenshot --device %q --destination %q --json-output %q\n' "$DEVICE_ID" "$screenshot_png" "$screenshot_json"
  fi
  printf 'Would write smoke report: %s\n' "$report_path"
  exit 0
fi

mkdir -p "$run_dir"

install_status="failed"
launch_status="skipped"
screenshot_status="skipped"
overall_status="failed"

set +e
xcrun devicectl device install app \
  --device "$DEVICE_ID" \
  --json-output "$install_json" \
  "$APP_PATH" >"$install_log" 2>&1
install_exit=$?
set -e

if [[ "$install_exit" -eq 0 ]]; then
  install_status="passed"
fi

if [[ "$install_status" == "passed" && "$SKIP_LAUNCH" == false ]]; then
  set +e
  xcrun devicectl device process launch \
    --device "$DEVICE_ID" \
    --json-output "$launch_json" \
    --terminate-existing \
    "$BUNDLE_ID" >"$launch_log" 2>&1
  launch_exit=$?
  set -e

  if [[ "$launch_exit" -eq 0 ]]; then
    launch_status="passed"
    overall_status="passed"
  else
    launch_status="failed"
  fi
elif [[ "$install_status" == "passed" && "$SKIP_LAUNCH" == true ]]; then
  overall_status="partial"
fi

if [[ "$launch_status" == "passed" ]]; then
  set +e
  xcrun devicectl device capture screenshot \
    --device "$DEVICE_ID" \
    --destination "$screenshot_png" \
    --json-output "$screenshot_json" >"$screenshot_log" 2>&1
  screenshot_exit=$?
  set -e

  if [[ "$screenshot_exit" -eq 0 && -s "$screenshot_png" ]]; then
    screenshot_status="passed"
  else
    screenshot_status="failed"
  fi
fi

locked_note=""
if [[ -f "$launch_log" ]] && grep -Fq "Locked" "$launch_log"; then
  locked_note="Launch failed because the device was locked. Unlock the device and rerun this script."
fi

generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
{
  printf '# Archive Device Smoke Report\n\n'
  printf -- '- Status: %s\n' "$overall_status"
  printf -- '- Generated: %s\n' "$generated_at"
  printf -- '- Branch: %s\n' "$(git_value branch --show-current)"
  printf -- '- Commit: %s\n' "$(git_value rev-parse --short HEAD)"
  printf -- '- Full commit: %s\n' "$(git_value rev-parse HEAD)"
  printf -- '- Device: %s\n' "$DEVICE_ID"
  printf -- '- App path: `%s`\n' "$APP_PATH"
  printf -- '- Bundle ID: `%s`\n' "$BUNDLE_ID"
  printf -- '- App version: %s\n' "$APP_VERSION"
  printf -- '- Build number: %s\n' "$BUILD_NUMBER"
  printf -- '- Install: %s\n' "$install_status"
  printf -- '- Launch: %s\n' "$launch_status"
  printf -- '- Screenshot: %s\n' "$screenshot_status"
  if [[ -n "$locked_note" ]]; then
    printf -- '- Note: %s\n' "$locked_note"
  fi
  printf '\n## Artifacts\n\n'
  printf -- '- Install JSON: `%s`\n' "$install_json"
  printf -- '- Install log: `%s`\n' "$install_log"
  printf -- '- Launch JSON: `%s`\n' "$launch_json"
  printf -- '- Launch log: `%s`\n' "$launch_log"
  printf -- '- Launch screenshot: `%s`\n' "$screenshot_png"
  printf -- '- Screenshot JSON: `%s`\n' "$screenshot_json"
  printf -- '- Screenshot log: `%s`\n' "$screenshot_log"
  printf '\n## Manual Smoke Still Required\n\n'
  printf -- '- Open HTML Sample.\n'
  printf -- '- Open Markdown Sample.\n'
  printf -- '- Open ZIP Report Sample.\n'
  printf -- '- Verify Safe Preview messaging and Settings release claims.\n'
  printf -- '- Record the full result in `docs/final-archive-smoke-test-template.md`.\n'
} >"$report_path"

printf 'Archive device smoke status: %s\n' "$overall_status"
printf 'Wrote smoke report: %s\n' "$report_path"

if [[ "$overall_status" == "passed" || "$overall_status" == "partial" ]]; then
  exit 0
fi

if [[ -n "$locked_note" ]]; then
  printf '%s\n' "$locked_note" >&2
fi
exit 1
