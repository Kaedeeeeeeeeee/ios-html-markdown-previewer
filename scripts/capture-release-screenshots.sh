#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/HTMLMarkdownPreviewer.xcodeproj"
DERIVED_DATA="${DERIVED_DATA:-$ROOT_DIR/DerivedData/ScreenshotCapture}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/docs/app-store-screenshots}"
SOURCE_OUT_DIR="${SOURCE_OUT_DIR:-$ROOT_DIR/DerivedData/AppStoreScreenshotSources}"
PREVIEW_OUT_DIR="${PREVIEW_OUT_DIR:-$ROOT_DIR/DerivedData/AppStoreScreenshotPreviews}"
CAPTURE_LOCALES="${CAPTURE_LOCALES:-en-US zh-Hans ja}"
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
types = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devicetypes", "-j"], text=True))["devicetypes"]
preferred_type_ids = {item["identifier"] for item in types if item["name"] == preferred_name}

matches = []
for runtime, devices in devices_by_runtime.items():
    if not runtime.startswith("com.apple.CoreSimulator.SimRuntime.iOS-"):
        continue
    version = tuple(int(part) for part in runtime.rsplit("iOS-", 1)[1].split("-"))
    if version != runtime_version:
        continue
    for device in devices:
        exact_name = device["name"] == preferred_name
        same_type = device.get("deviceTypeIdentifier") in preferred_type_ids
        if (exact_name or same_type) and device.get("isAvailable", False):
            matches.append((exact_name, version, device["udid"]))

if not matches:
    raise SystemExit(f"No available simulator named {preferred_name!r} for iOS {'-'.join(map(str, runtime_version))}")

matches.sort(reverse=True)
print(matches[0][2])
PY
}

IPHONE_RUNTIME_VERSION="${IPHONE_RUNTIME_VERSION:-18-5}"
IPAD_RUNTIME_VERSION="${IPAD_RUNTIME_VERSION:-18-5}"
IPHONE_DEVICE="${IPHONE_DEVICE:-$(select_device "iPhone 16 Pro Max" "$IPHONE_RUNTIME_VERSION")}"
IPAD_DEVICE="${IPAD_DEVICE:-$(select_device "iPad Pro (12.9-inch) (6th generation)" "$IPAD_RUNTIME_VERSION")}"

CURRENT_DEVICE=""
CURRENT_WAS_BOOTED=""
CURRENT_APPEARANCE=""

restore_device() {
  if [[ -n "$CURRENT_DEVICE" ]]; then
    xcrun simctl terminate "$CURRENT_DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl status_bar "$CURRENT_DEVICE" clear >/dev/null 2>&1 || true
    if [[ "$CURRENT_APPEARANCE" == "light" || "$CURRENT_APPEARANCE" == "dark" ]]; then
      xcrun simctl ui "$CURRENT_DEVICE" appearance "$CURRENT_APPEARANCE" >/dev/null 2>&1 || true
    fi
    if [[ "$CURRENT_WAS_BOOTED" != "Booted" ]]; then
      xcrun simctl shutdown "$CURRENT_DEVICE" >/dev/null 2>&1 || true
    fi
    CURRENT_DEVICE=""
  fi
}
trap restore_device EXIT

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
  CURRENT_DEVICE="$device"
  CURRENT_WAS_BOOTED="$(xcrun simctl list devices --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["state"] for group in d["devices"].values() for x in group if x["udid"]==sys.argv[1]))' "$device")"
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
  CURRENT_APPEARANCE="$(xcrun simctl ui "$device" appearance)"
  xcrun simctl ui "$device" appearance light
  xcrun simctl status_bar "$device" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
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
  SIMCTL_CHILD_HTML_PREVIEWER_UI_TESTS=1 xcrun simctl launch --terminate-running-process "$device" "$BUNDLE_ID" \
    -AppleLanguages "($language)" \
    -AppleLocale "$apple_locale" \
    "$@" >/dev/null
  # Reapply after launch so the first frame also uses the presentation status bar.
  xcrun simctl status_bar "$device" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100

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

  xcrun simctl ui "$device" appearance light
  capture "$device" "$output_dir" "$prefix-01-html-report" "$language" "$apple_locale" --screenshot-reset-library --screenshot-sample=html
  capture "$device" "$output_dir" "$prefix-02-batch-import" "$language" "$apple_locale" --screenshot-reset-library "--batch-import-fixture=$(uuidgen)" --batch-import-scenario=showcase
  capture "$device" "$output_dir" "$prefix-03-json-preview" "$language" "$apple_locale" --screenshot-reset-library --screenshot-sample=json
  capture "$device" "$output_dir" "$prefix-04-markdown-preview" "$language" "$apple_locale" --screenshot-reset-library --screenshot-sample=markdown
  capture "$device" "$output_dir" "$prefix-05-library" "$language" "$apple_locale" --screenshot-reset-library --screenshot-library
  xcrun simctl ui "$device" appearance dark
  capture "$device" "$output_dir" "$prefix-06-yaml-preview" "$language" "$apple_locale" --screenshot-reset-library --screenshot-sample=yaml
}

for family in iphone ipad; do
  if [[ "$family" == "iphone" ]]; then device="$IPHONE_DEVICE"; else device="$IPAD_DEVICE"; fi
  boot_and_install "$device"
  for locale in $CAPTURE_LOCALES; do
    case "$locale" in
      en-US) language="en"; apple_locale="en_US" ;;
      zh-Hans) language="zh-Hans"; apple_locale="zh_CN" ;;
      ja) language="ja"; apple_locale="ja_JP" ;;
      *) echo "Unsupported screenshot locale: $locale" >&2; exit 1 ;;
    esac
    echo "Capturing $locale $family source screenshots on $device..."
    capture_set "$device" "$family" "$SOURCE_OUT_DIR/$locale" "$language" "$apple_locale"
  done
  # All fixtures live in the independent Debug test library.
  SIMCTL_CHILD_HTML_PREVIEWER_UI_TESTS=1 xcrun simctl launch --terminate-running-process "$device" "$BUNDLE_ID" --screenshot-reset-library >/dev/null
  sleep 2
  restore_device
done

echo "Composing localized App Store screenshots..."
xcrun swift "$ROOT_DIR/scripts/generate-app-store-screenshots.swift" \
  --source-dir "$SOURCE_OUT_DIR" \
  --output-dir "$OUT_DIR" \
  --copy-file "$COPY_FILE" \
  --preview-dir "$PREVIEW_OUT_DIR"

echo "Source screenshots written to $SOURCE_OUT_DIR"
echo "Localized App Store screenshots written to $OUT_DIR"
echo "Contact sheets written to $PREVIEW_OUT_DIR"
