#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LISTING_PATH="$ROOT_DIR/docs/app-store-listing.md"
PRIVACY_PATH="$ROOT_DIR/docs/privacy-policy.md"
SUPPORT_PATH="$ROOT_DIR/docs/support.md"

PRIVACY_URL="https://gist.github.com/Kaedeeeeeeeeee/b3baa9048f37467e51bd9b3513787c42"
SUPPORT_URL="https://gist.github.com/Kaedeeeeeeeeee/394a005738e00a0f72bf9bd3a5abd59c"
PRIVACY_RAW_URL="https://gist.githubusercontent.com/Kaedeeeeeeeeee/b3baa9048f37467e51bd9b3513787c42/raw/privacy-policy.md"
SUPPORT_RAW_URL="https://gist.githubusercontent.com/Kaedeeeeeeeeee/394a005738e00a0f72bf9bd3a5abd59c/raw/support.md"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

curl_common=(
  --location
  --fail
  --silent
  --show-error
  --retry 3
  --retry-delay 2
  --connect-timeout 10
  --max-time 30
)

require_listing_url() {
  local label="$1"
  local url="$2"

  if grep -Fq "$label: $url" "$LISTING_PATH"; then
    printf '[OK] listing contains %s\n' "$label"
  else
    printf '[FAIL] listing missing %s: %s\n' "$label" "$url" >&2
    return 1
  fi
}

verify_public_url() {
  local label="$1"
  local url="$2"

  curl "${curl_common[@]}" --head "$url" >/dev/null
  printf '[OK] %s public page is reachable\n' "$label"
}

verify_raw_matches_local() {
  local label="$1"
  local url="$2"
  local local_path="$3"
  local raw_path="$TMP_DIR/$label.md"

  curl "${curl_common[@]}" "$url" > "$raw_path"

  python3 - "$local_path" "$raw_path" "$label" <<'PY'
import pathlib
import sys

local_path = pathlib.Path(sys.argv[1])
raw_path = pathlib.Path(sys.argv[2])
label = sys.argv[3]

local_text = local_path.read_text(encoding="utf-8").strip()
raw_text = raw_path.read_text(encoding="utf-8").strip()

if local_text != raw_text:
    print(f"{label} public raw page does not match {local_path}", file=sys.stderr)
    raise SystemExit(1)
PY

  printf '[OK] %s public raw page matches local source\n' "$label"
}

require_listing_url "Privacy Policy URL" "$PRIVACY_URL"
require_listing_url "Support URL" "$SUPPORT_URL"

verify_public_url "privacy policy" "$PRIVACY_URL"
verify_public_url "support" "$SUPPORT_URL"

verify_raw_matches_local "privacy-policy" "$PRIVACY_RAW_URL" "$PRIVACY_PATH"
verify_raw_matches_local "support" "$SUPPORT_RAW_URL" "$SUPPORT_PATH"

printf 'Public App Store pages verification passed.\n'
