#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_PATH="$ROOT_DIR/DerivedData/ArchivePreflight/HTMLPreviewer.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/HTMLMarkdownPreviewer.app"

rm -rf "$ARCHIVE_PATH"

xcodebuild -quiet archive \
  -project "$ROOT_DIR/HTMLMarkdownPreviewer.xcodeproj" \
  -scheme HTMLMarkdownPreviewer \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$ROOT_DIR/DerivedData" \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO

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

errors = []

for path, description in [
    (archive_info_path, "archive Info.plist"),
    (app_info_path, "app Info.plist"),
    (privacy_path, "PrivacyInfo.xcprivacy"),
    (binary_path, "app executable"),
    (assets_path, "Assets.car"),
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
        "CFBundleVersion": "2",
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
        "CFBundleVersion": "2",
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

printf 'Archive preflight passed: %s\n' "$ARCHIVE_PATH"
