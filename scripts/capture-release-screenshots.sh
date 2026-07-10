#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/HTMLMarkdownPreviewer.xcodeproj"
DERIVED_DATA="$ROOT_DIR/DerivedData"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/docs/app-store-screenshots}"
SOURCE_OUT_DIR="${SOURCE_OUT_DIR:-$DERIVED_DATA/AppStoreScreenshotSources/en-US}"
PREVIEW_OUT_DIR="${PREVIEW_OUT_DIR:-$DERIVED_DATA/AppStoreScreenshotPreviews}"
CAPTURE_LANGUAGE="${CAPTURE_LANGUAGE:-en}"
CAPTURE_APPLE_LOCALE="${CAPTURE_APPLE_LOCALE:-en_US}"
COPY_FILE="${COPY_FILE:-$ROOT_DIR/docs/app-store-screenshots/copy.json}"
BUNDLE_ID="com.kaede.htmlmarkdownpreviewer"
SCHEME="HTMLMarkdownPreviewer"

mkdir -p "$OUT_DIR" "$SOURCE_OUT_DIR" "$PREVIEW_OUT_DIR"

select_device() {
  local preferred_name="$1"
  local runtime_version="$2"
  python3 - "$preferred_name" "$runtime_version" <<'PY'
import json
import subprocess
import sys

preferred_name = sys.argv[1]
runtime_version = tuple(int(part) for part in sys.argv[2].split("-"))
raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"], text=True)
devices_by_runtime = json.loads(raw)["devices"]

matches = []
for runtime, devices in devices_by_runtime.items():
    if not runtime.startswith("com.apple.CoreSimulator.SimRuntime.iOS-"):
        continue
    version = tuple(int(part) for part in runtime.rsplit("iOS-", 1)[1].split("-"))
    if version != runtime_version:
        continue
    for device in devices:
        if device["name"] == preferred_name and device.get("isAvailable", False):
            matches.append((version, device["udid"]))

if not matches:
    raise SystemExit(f"No available simulator named {preferred_name!r} for iOS {'-'.join(map(str, runtime_version))}")

matches.sort(reverse=True)
print(matches[0][1])
PY
}

IPHONE_RUNTIME_VERSION="${IPHONE_RUNTIME_VERSION:-26-5}"
IPAD_RUNTIME_VERSION="${IPAD_RUNTIME_VERSION:-26-5}"
IPHONE_DEVICE="${IPHONE_DEVICE:-$(select_device "iPhone 17 Pro Max" "$IPHONE_RUNTIME_VERSION")}"
IPAD_DEVICE="${IPAD_DEVICE:-$(select_device "iPad Pro 13-inch (M5)" "$IPAD_RUNTIME_VERSION")}"

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/HTMLMarkdownPreviewer.app"

echo "Building $SCHEME for simulator screenshots..."
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$IPHONE_DEVICE" \
  -derivedDataPath "$DERIVED_DATA" \
  >/tmp/html-previewer-screenshot-build.log

boot_and_install() {
  local device="$1"
  xcrun simctl boot "$device" >/dev/null 2>&1 || true
  python3 - "$device" "${BOOTSTATUS_TIMEOUT_SECONDS:-45}" <<'PY'
import subprocess
import sys

device = sys.argv[1]
timeout = int(sys.argv[2])
try:
    subprocess.run(["xcrun", "simctl", "bootstatus", device, "-b"], check=False, timeout=timeout)
except subprocess.TimeoutExpired:
    print(f"warning: bootstatus timed out for {device}; continuing", file=sys.stderr)
PY
  xcrun simctl install "$device" "$APP_PATH"
}

capture() {
  local device="$1"
  local output_dir="$2"
  local output_name="$3"
  local language="$4"
  local apple_locale="$5"
  shift 5

  mkdir -p "$output_dir"
  xcrun simctl terminate "$device" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch --terminate-running-process "$device" "$BUNDLE_ID" \
    -AppleLanguages "($language)" \
    -AppleLocale "$apple_locale" \
    "$@" >/dev/null

  wait_seconds="${SCREENSHOT_WAIT_SECONDS:-8}"
  for argument in "$@"; do
    if [[ "$argument" == --screenshot-sample=* ]]; then
      wait_seconds="${SCREENSHOT_SAMPLE_WAIT_SECONDS:-20}"
      break
    fi
  done
  sleep "$wait_seconds"

  xcrun simctl io "$device" screenshot "$output_dir/$output_name.png" >/dev/null
  sips -g pixelWidth -g pixelHeight "$output_dir/$output_name.png" | sed "s#^#$output_name: #"
}

capture_set() {
  local device="$1"
  local prefix="$2"
  local output_dir="$3"
  local language="$4"
  local apple_locale="$5"

  boot_and_install "$device"
  capture "$device" "$output_dir" "$prefix-01-home" "$language" "$apple_locale" --screenshot-reset-library
  capture "$device" "$output_dir" "$prefix-02-html-safe-preview" "$language" "$apple_locale" --screenshot-reset-library --screenshot-sample=html
  capture "$device" "$output_dir" "$prefix-03-markdown-preview" "$language" "$apple_locale" --screenshot-reset-library --screenshot-sample=markdown
  capture "$device" "$output_dir" "$prefix-04-zip-report-preview" "$language" "$apple_locale" --screenshot-reset-library --screenshot-sample=zipPackage
  capture "$device" "$output_dir" "$prefix-05-settings" "$language" "$apple_locale" --screenshot-reset-library --screenshot-settings
}

echo "Capturing English iPhone source screenshots on $IPHONE_DEVICE..."
capture_set "$IPHONE_DEVICE" "iphone" "$SOURCE_OUT_DIR" "$CAPTURE_LANGUAGE" "$CAPTURE_APPLE_LOCALE"

echo "Capturing English iPad source screenshots on $IPAD_DEVICE..."
capture_set "$IPAD_DEVICE" "ipad" "$SOURCE_OUT_DIR" "$CAPTURE_LANGUAGE" "$CAPTURE_APPLE_LOCALE"

echo "Composing localized App Store screenshots..."
xcrun swift "$ROOT_DIR/scripts/generate-app-store-screenshots.swift" \
  --source-dir "$SOURCE_OUT_DIR" \
  --output-dir "$OUT_DIR" \
  --copy-file "$COPY_FILE" \
  --preview-dir "$PREVIEW_OUT_DIR"

echo "Source screenshots written to $SOURCE_OUT_DIR"
echo "Localized App Store screenshots written to $OUT_DIR"
echo "Contact sheets written to $PREVIEW_OUT_DIR"
