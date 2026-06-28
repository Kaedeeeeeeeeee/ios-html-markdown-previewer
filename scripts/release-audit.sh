#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

ok() {
  printf '[OK] %s\n' "$1"
}

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  FAILURES=$((FAILURES + 1))
}

require_file() {
  local path="$1"
  if [[ -f "$ROOT_DIR/$path" ]]; then
    ok "$path exists"
  else
    fail "$path is missing"
  fi
}

require_text() {
  local path="$1"
  local pattern="$2"
  local description="$3"
  if grep -Eq "$pattern" "$ROOT_DIR/$path"; then
    ok "$description"
  else
    fail "$description"
  fi
}

check_png_dimensions() {
  local path="$1"
  local expected_width="$2"
  local expected_height="$3"
  local full_path="$ROOT_DIR/$path"

  if [[ ! -f "$full_path" ]]; then
    fail "$path is missing"
    return
  fi

  local width
  local height
  width="$(sips -g pixelWidth "$full_path" 2>/dev/null | awk '/pixelWidth/ { print $2 }')"
  height="$(sips -g pixelHeight "$full_path" 2>/dev/null | awk '/pixelHeight/ { print $2 }')"

  if [[ "$width" == "$expected_width" && "$height" == "$expected_height" ]]; then
    ok "$path is ${expected_width}x${expected_height}"
  else
    fail "$path is ${width:-unknown}x${height:-unknown}, expected ${expected_width}x${expected_height}"
  fi
}

echo "== Project metadata =="
require_file "project.yml"
require_file "HTMLMarkdownPreviewer.xcodeproj/project.pbxproj"
require_file "HTMLMarkdownPreviewerUITests/SmokeUITests.swift"
require_file "scripts/archive-preflight.sh"
require_file "scripts/prepare-release-packet.sh"
require_file "scripts/prepare-validation-samples.sh"
require_file "scripts/release-device-build.sh"
require_file "scripts/verify-public-pages.sh"
require_text "project.yml" "type: bundle\\.ui-testing" "project.yml includes UI test target"
require_text "project.yml" "CURRENT_PROJECT_VERSION: 1" "project.yml build number is 1"
require_text "project.yml" "MARKETING_VERSION: 1\\.0" "project.yml marketing version is 1.0"
require_text "HTMLMarkdownPreviewer.xcodeproj/project.pbxproj" "MARKETING_VERSION = 1\\.0;" "generated Xcode project marketing version is 1.0"
require_text "HTMLMarkdownPreviewer.xcodeproj/project.pbxproj" "PRODUCT_BUNDLE_IDENTIFIER = com\\.kaede\\.htmlmarkdownpreviewer;" "bundle identifier is com.kaede.htmlmarkdownpreviewer"
require_text "project.yml" "ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon" "AppIcon asset catalog is configured"

echo
echo "== Package resolution =="
require_file "HTMLMarkdownPreviewer.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
if python3 - "$ROOT_DIR/HTMLMarkdownPreviewer.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

expected = {
    "zipfoundation": "0.9.20",
    "swift-markdown": "0.8.0",
    "swift-cmark": "0.8.0",
}

pins = {
    pin["identity"]: pin.get("state", {}).get("version")
    for pin in data.get("pins", [])
}

errors = []
for identity, version in expected.items():
    if pins.get(identity) != version:
        errors.append(f"{identity} must be pinned to {version}, found {pins.get(identity)!r}")

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)
PY
then
  ok "Swift package dependencies are pinned to expected versions"
else
  fail "Swift package dependency pins are invalid"
fi

echo
echo "== Info.plist =="
require_file "HTMLMarkdownPreviewer/Info.plist"
if python3 - "$ROOT_DIR/HTMLMarkdownPreviewer/Info.plist" <<'PY'
import plistlib
import sys

path = sys.argv[1]
with open(path, "rb") as handle:
    data = plistlib.load(handle)

errors = []
if data.get("CFBundleDisplayName") != "HTML Previewer":
    errors.append("CFBundleDisplayName must be HTML Previewer")
if data.get("LSApplicationCategoryType") != "public.app-category.productivity":
    errors.append("LSApplicationCategoryType must be productivity")
if data.get("ITSAppUsesNonExemptEncryption") is not False:
    errors.append("ITSAppUsesNonExemptEncryption must be false")
if data.get("LSSupportsOpeningDocumentsInPlace") is not True:
    errors.append("LSSupportsOpeningDocumentsInPlace must be true")

found_types = set()
for document_type in data.get("CFBundleDocumentTypes", []):
    found_types.update(document_type.get("LSItemContentTypes", []))

required_types = {
    "public.html",
    "public.xhtml",
    "net.daringfireball.markdown",
    "public.zip-archive",
}
missing_types = sorted(required_types - found_types)
if missing_types:
    errors.append("missing document types: " + ", ".join(missing_types))

markdown_declared = any(
    declaration.get("UTTypeIdentifier") == "net.daringfireball.markdown"
    and set(declaration.get("UTTypeTagSpecification", {}).get("public.filename-extension", [])) >= {"md", "markdown"}
    for declaration in data.get("UTImportedTypeDeclarations", [])
)
if not markdown_declared:
    errors.append("Markdown UTType declaration must include md and markdown extensions")

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)
PY
then
  ok "Info.plist document types and app metadata are valid"
else
  fail "Info.plist document types or app metadata are invalid"
fi
require_file "docs/export-compliance.md"

echo
echo "== Privacy manifest =="
require_file "HTMLMarkdownPreviewer/PrivacyInfo.xcprivacy"
if plutil -lint "$ROOT_DIR/HTMLMarkdownPreviewer/PrivacyInfo.xcprivacy" >/dev/null; then
  ok "PrivacyInfo.xcprivacy is valid plist"
else
  fail "PrivacyInfo.xcprivacy is invalid"
fi

if python3 - "$ROOT_DIR/HTMLMarkdownPreviewer/PrivacyInfo.xcprivacy" <<'PY'
import plistlib
import sys

path = sys.argv[1]
with open(path, "rb") as handle:
    data = plistlib.load(handle)

errors = []
if data.get("NSPrivacyCollectedDataTypes") != []:
    errors.append("NSPrivacyCollectedDataTypes must be empty")
if data.get("NSPrivacyTracking") is not False:
    errors.append("NSPrivacyTracking must be false")
if data.get("NSPrivacyTrackingDomains") != []:
    errors.append("NSPrivacyTrackingDomains must be empty")

accessed = data.get("NSPrivacyAccessedAPITypes", [])
file_timestamp = next(
    (
        item
        for item in accessed
        if item.get("NSPrivacyAccessedAPIType") == "NSPrivacyAccessedAPICategoryFileTimestamp"
    ),
    None,
)
if file_timestamp is None:
    errors.append("missing NSPrivacyAccessedAPICategoryFileTimestamp declaration")
else:
    reasons = set(file_timestamp.get("NSPrivacyAccessedAPITypeReasons", []))
    if not {"C617.1", "3B52.1"} <= reasons:
        errors.append("file timestamp declaration must include C617.1 and 3B52.1")

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)
PY
then
  ok "Privacy manifest matches local-only data and required reason API policy"
else
  fail "Privacy manifest is missing required release declarations"
fi
require_file "docs/privacy-required-reasons.md"

echo
echo "== App icon =="
require_file "HTMLMarkdownPreviewer/Assets.xcassets/AppIcon.appiconset/Contents.json"
require_file "HTMLMarkdownPreviewer/Assets.xcassets/AppIcon.appiconset/AppIcon-1024x1024@1x.png"
check_png_dimensions "HTMLMarkdownPreviewer/Assets.xcassets/AppIcon.appiconset/AppIcon-1024x1024@1x.png" 1024 1024

echo
echo "== App Store materials =="
for path in \
  "docs/app-store-listing.md" \
  "docs/app-store-connect-handoff.md" \
  "docs/app-store-submission-runbook.md" \
  "docs/final-archive-smoke-test-template.md" \
  "docs/release-checklist.md" \
  "docs/privacy-policy.md" \
  "docs/support.md" \
  "docs/export-compliance.md" \
  "docs/physical-device-validation.md" \
  "docs/physical-device-validation-result-template.md" \
  "docs/usability-testing/script.md" \
  "docs/usability-testing/observation-template.md"; do
  require_file "$path"
done
require_text "docs/app-store-listing.md" "No in-app purchases" "listing states no in-app purchases"
require_text "docs/app-store-listing.md" "No ads" "listing states no ads"
require_text "docs/app-store-listing.md" "No account" "listing states no account"
require_text "docs/app-store-listing.md" "Paid download" "listing states paid download"
require_text "docs/app-store-listing.md" "Data collected: None" "listing privacy draft states no data collected"
require_text "docs/app-store-listing.md" "Privacy Policy URL: https://gist\\.github\\.com/Kaedeeeeeeeeee/b3baa9048f37467e51bd9b3513787c42" "listing includes privacy policy URL"
require_text "docs/app-store-listing.md" "Support URL: https://gist\\.github\\.com/Kaedeeeeeeeeee/394a005738e00a0f72bf9bd3a5abd59c" "listing includes support URL"
require_text "docs/app-store-connect-handoff.md" "Commercial model: paid download" "App Store Connect handoff states paid download"
require_text "docs/app-store-connect-handoff.md" "Data collected: none" "App Store Connect handoff states no data collected"
require_text "docs/app-store-connect-handoff.md" "Unrestricted web access.*No" "App Store Connect handoff covers unrestricted web access"
require_text "docs/app-store-connect-handoff.md" "ITSAppUsesNonExemptEncryption=false" "App Store Connect handoff covers export compliance"
require_text "docs/final-archive-smoke-test-template.md" "Can submit for review" "final smoke template includes submission decision"
require_text "docs/final-archive-smoke-test-template.md" "Data Not Collected" "final smoke template covers App Store privacy label check"
require_text "docs/physical-device-validation-result-template.md" "External Open Matrix" "physical-device result template includes source matrix"
require_text "docs/physical-device-validation-result-template.md" "Can close #1" "physical-device result template includes issue close decision"
require_text "docs/privacy-policy.md" "HTML Previewer does not collect personal data" "privacy policy states no personal data collection"
require_text "docs/support.md" "https://gist\\.github\\.com/Kaedeeeeeeeeee/394a005738e00a0f72bf9bd3a5abd59c" "support page includes support contact"

echo
echo "== Screenshots =="
for name in \
  iphone-01-home \
  iphone-02-html-safe-preview \
  iphone-03-markdown-preview \
  iphone-04-zip-report-preview \
  iphone-05-settings; do
  check_png_dimensions "docs/app-store-screenshots/$name.png" 1320 2868
done
for name in \
  ipad-01-home \
  ipad-02-html-safe-preview \
  ipad-03-markdown-preview \
  ipad-04-zip-report-preview \
  ipad-05-settings; do
  check_png_dimensions "docs/app-store-screenshots/$name.png" 2064 2752
done

echo
echo "== Usability samples =="
for path in \
  "docs/usability-testing/samples/basic-report.html" \
  "docs/usability-testing/samples/legacy-report.htm" \
  "docs/usability-testing/samples/markdown-notes.md" \
  "docs/usability-testing/samples/markdown-reference.markdown" \
  "docs/usability-testing/samples/external-resource.html" \
  "docs/usability-testing/samples/interactive-trusted.html" \
  "docs/usability-testing/samples/zip-report.zip" \
  "docs/usability-testing/samples/broken.zip"; do
  require_file "$path"
done
if python3 - "$ROOT_DIR/docs/usability-testing/samples" <<'PY'
import pathlib
import sys

sample_dir = pathlib.Path(sys.argv[1])
required_extensions = {".html", ".htm", ".md", ".markdown", ".zip"}
found_extensions = {
    path.suffix.lower()
    for path in sample_dir.iterdir()
    if path.is_file()
}
missing_extensions = sorted(required_extensions - found_extensions)
if missing_extensions:
    print("missing sample extensions: " + ", ".join(missing_extensions), file=sys.stderr)
    raise SystemExit(1)
PY
then
  ok "external-open sample files cover html, htm, md, markdown, and zip extensions"
else
  fail "external-open sample files are missing supported extension coverage"
fi
if unzip -t "$ROOT_DIR/docs/usability-testing/samples/zip-report.zip" >/dev/null; then
  ok "zip-report.zip is valid"
else
  fail "zip-report.zip is invalid"
fi
if unzip -t "$ROOT_DIR/docs/usability-testing/samples/broken.zip" >/dev/null 2>&1; then
  fail "broken.zip should remain intentionally invalid"
else
  ok "broken.zip remains intentionally invalid"
fi
if "$ROOT_DIR/scripts/prepare-validation-samples.sh" >/tmp/html-previewer-validation-samples.log; then
  ok "validation sample staging package can be generated"
else
  cat /tmp/html-previewer-validation-samples.log >&2 || true
  fail "validation sample staging package generation failed"
fi
if python3 - "$ROOT_DIR/DerivedData/ValidationSamples/HTMLPreviewerValidationSamples.zip" <<'PY'
import subprocess
import sys

zip_path = sys.argv[1]
expected = {
    "HTMLPreviewerValidationSamples/basic-report.html",
    "HTMLPreviewerValidationSamples/legacy-report.htm",
    "HTMLPreviewerValidationSamples/markdown-notes.md",
    "HTMLPreviewerValidationSamples/markdown-reference.markdown",
    "HTMLPreviewerValidationSamples/zip-report.zip",
    "HTMLPreviewerValidationSamples/external-resource.html",
    "HTMLPreviewerValidationSamples/interactive-trusted.html",
    "HTMLPreviewerValidationSamples/broken.zip",
    "HTMLPreviewerValidationSamples/README.txt",
    "HTMLPreviewerValidationSamples/physical-device-validation-result-template.md",
}
raw = subprocess.check_output(["unzip", "-Z1", zip_path], text=True)
found = set(raw.splitlines())
missing = sorted(expected - found)
if missing:
    print("missing files in validation sample package: " + ", ".join(missing), file=sys.stderr)
    raise SystemExit(1)
PY
then
  ok "validation sample package contains expected files"
else
  fail "validation sample package is missing expected files"
fi

echo
echo "== Release packet =="
if "$ROOT_DIR/scripts/prepare-release-packet.sh" >/tmp/html-previewer-release-packet.log; then
  ok "release packet can be generated"
else
  cat /tmp/html-previewer-release-packet.log >&2 || true
  fail "release packet generation failed"
fi
if python3 - "$ROOT_DIR/DerivedData/ReleasePacket/HTMLPreviewerReleasePacket.zip" <<'PY'
import subprocess
import sys

zip_path = sys.argv[1]
expected = {
    "HTMLPreviewerReleasePacket/README.txt",
    "HTMLPreviewerReleasePacket/AppStore/app-store-listing.md",
    "HTMLPreviewerReleasePacket/AppStore/app-store-connect-handoff.md",
    "HTMLPreviewerReleasePacket/AppStore/app-store-submission-runbook.md",
    "HTMLPreviewerReleasePacket/AppStore/release-checklist.md",
    "HTMLPreviewerReleasePacket/AppStore/final-archive-smoke-test-template.md",
    "HTMLPreviewerReleasePacket/PhysicalDevice/physical-device-validation.md",
    "HTMLPreviewerReleasePacket/PhysicalDevice/physical-device-validation-result-template.md",
    "HTMLPreviewerReleasePacket/PhysicalDevice/HTMLPreviewerValidationSamples.zip",
    "HTMLPreviewerReleasePacket/UsabilityTesting/script.md",
    "HTMLPreviewerReleasePacket/UsabilityTesting/observation-template.md",
    "HTMLPreviewerReleasePacket/PublicPages/privacy-policy.md",
    "HTMLPreviewerReleasePacket/PublicPages/support.md",
    "HTMLPreviewerReleasePacket/Compliance/privacy-required-reasons.md",
    "HTMLPreviewerReleasePacket/Compliance/export-compliance.md",
    "HTMLPreviewerReleasePacket/AppMetadata/PrivacyInfo.xcprivacy",
    "HTMLPreviewerReleasePacket/AppMetadata/AppIcon-1024x1024@1x.png",
    "HTMLPreviewerReleasePacket/Screenshots/iphone-01-home.png",
    "HTMLPreviewerReleasePacket/Screenshots/ipad-01-home.png",
}
raw = subprocess.check_output(["unzip", "-Z1", zip_path], text=True)
found = set(raw.splitlines())
missing = sorted(expected - found)
if missing:
    print("missing files in release packet: " + ", ".join(missing), file=sys.stderr)
    raise SystemExit(1)
PY
then
  ok "release packet contains expected handoff files"
else
  fail "release packet is missing expected handoff files"
fi

echo
echo "== StoreKit, accounts, and ads absence =="
if command -v rg >/dev/null 2>&1; then
  rg -n "StoreKit|SKPayment|InAppPurchase|AdMob|GAD[A-Z]|AppLovin|FirebaseAnalytics|Sign in with Apple|ASAuthorization" \
    "$ROOT_DIR/HTMLMarkdownPreviewer" \
    "$ROOT_DIR/project.yml" \
    >/tmp/html-previewer-release-audit-search.log 2>/dev/null
  search_status=$?
else
  grep -R -n -E "StoreKit|SKPayment|InAppPurchase|AdMob|GAD[A-Z]|AppLovin|FirebaseAnalytics|Sign in with Apple|ASAuthorization" \
    "$ROOT_DIR/HTMLMarkdownPreviewer" \
    "$ROOT_DIR/project.yml" \
    >/tmp/html-previewer-release-audit-search.log 2>/dev/null
  search_status=$?
fi

if [[ "$search_status" -eq 0 ]]; then
  cat /tmp/html-previewer-release-audit-search.log >&2
  fail "release build should not contain StoreKit, account, analytics, or ad SDK references"
else
  ok "no StoreKit, account, analytics, or ad SDK references found"
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "Release audit passed."
else
  echo "Release audit failed with $FAILURES issue(s)." >&2
  exit 1
fi
