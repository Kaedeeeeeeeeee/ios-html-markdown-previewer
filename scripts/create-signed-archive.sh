#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/DerivedData/SignedArchive/HTMLPreviewer.xcarchive}"
CODE_SIGN_STYLE="${CODE_SIGN_STYLE:-Automatic}"
ALLOW_PROVISIONING_UPDATES="${ALLOW_PROVISIONING_UPDATES:-YES}"
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: DEVELOPMENT_TEAM=<Apple Team ID> scripts/create-signed-archive.sh [--dry-run]

Creates a signed Release archive for App Store Connect/TestFlight handoff.

Environment:
  DEVELOPMENT_TEAM                 Required Apple Developer Team ID.
  ARCHIVE_PATH                     Optional .xcarchive output path.
  CODE_SIGN_STYLE                  Optional signing style, defaults to Automatic.
  PROVISIONING_PROFILE_SPECIFIER   Optional profile name for manual signing.
  ALLOW_PROVISIONING_UPDATES       YES or NO, defaults to YES.

Options:
  --dry-run                        Print the xcodebuild command without running it.
  -h, --help                       Show this help.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
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

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  printf 'Set DEVELOPMENT_TEAM to your Apple Developer Team ID.\n' >&2
  exit 2
fi

case "$ALLOW_PROVISIONING_UPDATES" in
  YES|NO)
    ;;
  *)
    printf 'ALLOW_PROVISIONING_UPDATES must be YES or NO, found %s\n' "$ALLOW_PROVISIONING_UPDATES" >&2
    exit 2
    ;;
esac

cmd=(
  xcodebuild archive
  -project "$ROOT_DIR/HTMLMarkdownPreviewer.xcodeproj"
  -scheme HTMLMarkdownPreviewer
  -configuration Release
  -destination "generic/platform=iOS"
  -archivePath "$ARCHIVE_PATH"
  -derivedDataPath "$ROOT_DIR/DerivedData"
  -skipPackagePluginValidation
  "DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM"
  "CODE_SIGN_STYLE=$CODE_SIGN_STYLE"
  CODE_SIGNING_ALLOWED=YES
)

if [[ -n "${PROVISIONING_PROFILE_SPECIFIER:-}" ]]; then
  cmd+=("PROVISIONING_PROFILE_SPECIFIER=$PROVISIONING_PROFILE_SPECIFIER")
fi

if [[ "$ALLOW_PROVISIONING_UPDATES" == "YES" ]]; then
  cmd+=(-allowProvisioningUpdates)
fi

if [[ "$DRY_RUN" == true ]]; then
  printf 'Dry run signed archive command:\n'
  printf '%q ' "${cmd[@]}"
  printf '\n'
  exit 0
fi

rm -rf "$ARCHIVE_PATH"
"${cmd[@]}"

APP_PATH="$ARCHIVE_PATH/Products/Applications/HTMLMarkdownPreviewer.app"

codesign --verify --strict "$APP_PATH"

python3 - "$ARCHIVE_PATH" "$APP_PATH" <<'PY'
import os
import plistlib
import sys

archive_path = sys.argv[1]
app_path = sys.argv[2]
archive_info_path = os.path.join(archive_path, "Info.plist")
app_info_path = os.path.join(app_path, "Info.plist")
privacy_path = os.path.join(app_path, "PrivacyInfo.xcprivacy")
binary_path = os.path.join(app_path, "HTMLMarkdownPreviewer")
assets_path = os.path.join(app_path, "Assets.car")
signature_path = os.path.join(app_path, "_CodeSignature", "CodeResources")
profile_path = os.path.join(app_path, "embedded.mobileprovision")

errors = []

for path, description in [
    (archive_info_path, "archive Info.plist"),
    (app_info_path, "app Info.plist"),
    (privacy_path, "PrivacyInfo.xcprivacy"),
    (binary_path, "app executable"),
    (assets_path, "Assets.car"),
    (signature_path, "code signature"),
    (profile_path, "embedded provisioning profile"),
]:
    if not os.path.exists(path):
        errors.append(f"missing {description}: {path}")

if not errors:
    with open(archive_info_path, "rb") as handle:
        archive_info = plistlib.load(handle)
    with open(app_info_path, "rb") as handle:
        app_info = plistlib.load(handle)

    properties = archive_info.get("ApplicationProperties", {})
    expected_archive = {
        "ApplicationPath": "Applications/HTMLMarkdownPreviewer.app",
        "CFBundleIdentifier": "com.kaede.htmlmarkdownpreviewer",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
    }
    for key, expected in expected_archive.items():
        if properties.get(key) != expected:
            errors.append(f"archive {key} must be {expected!r}, found {properties.get(key)!r}")

    architectures = set(properties.get("Architectures", []))
    if "arm64" not in architectures:
        errors.append(f"archive Architectures must include arm64, found {sorted(architectures)!r}")

    expected_app = {
        "CFBundleDisplayName": "HTML Previewer",
        "CFBundleIdentifier": "com.kaede.htmlmarkdownpreviewer",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
        "MinimumOSVersion": "17.0",
        "ITSAppUsesNonExemptEncryption": False,
        "LSApplicationCategoryType": "public.app-category.productivity",
    }
    for key, expected in expected_app.items():
        if app_info.get(key) != expected:
            errors.append(f"app {key} must be {expected!r}, found {app_info.get(key)!r}")

    device_family = set(app_info.get("UIDeviceFamily", []))
    if not {1, 2} <= device_family:
        errors.append(f"UIDeviceFamily must include iPhone and iPad, found {sorted(device_family)!r}")

    document_types = set()
    for document_type in app_info.get("CFBundleDocumentTypes", []):
        document_types.update(document_type.get("LSItemContentTypes", []))
    required_document_types = {
        "public.html",
        "public.xhtml",
        "net.daringfireball.markdown",
        "public.zip-archive",
    }
    missing_document_types = sorted(required_document_types - document_types)
    if missing_document_types:
        errors.append("missing document types: " + ", ".join(missing_document_types))

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)
PY

printf 'Signed archive created and validated: %s\n' "$ARCHIVE_PATH"
printf 'Next: upload it through Xcode Organizer or App Store Connect tooling, then run the final archive/TestFlight smoke test.\n'
