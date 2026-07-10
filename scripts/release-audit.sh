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
require_file "scripts/check-github-actions-execution.sh"
require_file "scripts/prepare-local-automated-test-report.sh"
require_file "scripts/check-signing-readiness.sh"
require_file "scripts/create-signed-archive.sh"
require_file "scripts/final-submission-preflight.sh"
require_file "scripts/portable-release-materials-audit.sh"
require_file "scripts/prepare-release-packet.sh"
require_file "scripts/prepare-submission-gate-status.sh"
require_file "scripts/validate-completed-release-results.sh"
require_file "scripts/prepare-submission-owner-handoff.sh"
require_file "scripts/prepare-app-store-connect-run.sh"
require_file "scripts/prepare-final-smoke-run.sh"
require_file "scripts/prepare-usability-test-packet.sh"
require_file "scripts/prepare-usability-session-run.sh"
require_file "scripts/prepare-physical-device-validation-run.sh"
require_file "scripts/prepare-validation-samples.sh"
require_file "scripts/release-device-build.sh"
require_file "scripts/run-archive-device-smoke.sh"
require_file "scripts/serve-validation-samples.sh"
require_file "scripts/verify-public-pages.sh"
require_file "fastlane/Fastfile"
require_text "project.yml" "type: bundle\\.ui-testing" "project.yml includes UI test target"
require_text "project.yml" "CURRENT_PROJECT_VERSION: 4" "project.yml build number is 4"
require_text "project.yml" "MARKETING_VERSION: 1\\.1" "project.yml marketing version is 1.1"
require_text "HTMLMarkdownPreviewer.xcodeproj/project.pbxproj" "MARKETING_VERSION = 1\\.1;" "generated Xcode project marketing version is 1.1"
require_text "HTMLMarkdownPreviewer.xcodeproj/project.pbxproj" "CURRENT_PROJECT_VERSION = 4;" "generated Xcode project build number is 4"
require_text "HTMLMarkdownPreviewer.xcodeproj/project.pbxproj" "PRODUCT_BUNDLE_IDENTIFIER = com\\.kaede\\.htmlmarkdownpreviewer;" "bundle identifier is com.kaede.htmlmarkdownpreviewer"
require_text "project.yml" "ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon" "AppIcon asset catalog is configured"
require_text ".github/workflows/app-store-upload.yml" "APP_STORE_CONNECT_BUILD_NUMBER: \"4\"" "App Store upload workflow targets build 4"
require_text ".github/workflows/app-store-upload.yml" "APP_STORE_CONNECT_VERSION_STRING: \"1\\.1\"" "App Store upload workflow targets version 1.1"
require_text ".github/workflows/app-store-upload.yml" "Sync localized metadata and screenshots" "App Store upload workflow syncs localized store assets"
require_text ".github/workflows/app-store-upload.yml" "submit_for_review:" "App Store upload workflow keeps review submission explicit"
require_text "fastlane/Fastfile" "overwrite_screenshots: true" "Fastlane replaces stale App Store screenshots"
require_text "fastlane/Fastfile" "skip_app_version_update: false" "Fastlane creates or updates the App Store version"
require_text ".github/scripts/submit-app-store-review.rb" "/v1/apps/#\\{APP_ID\\}/appStoreVersions" "App Store verification resolves versions through the app relationship"

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
echo "== Signing readiness helper =="
if DEVELOPMENT_TEAM=ABCDE12345 "$ROOT_DIR/scripts/check-signing-readiness.sh" --dry-run >/tmp/html-previewer-signing-readiness-dry-run.log; then
  ok "signing readiness helper dry-run succeeds"
else
  cat /tmp/html-previewer-signing-readiness-dry-run.log >&2 || true
  fail "signing readiness helper dry-run failed"
fi
if grep -Fq "signing-readiness-report.md" /tmp/html-previewer-signing-readiness-dry-run.log; then
  ok "signing readiness helper creates a readiness report"
else
  fail "signing readiness helper dry-run is missing the report"
fi
require_text "scripts/check-signing-readiness.sh" "Apple Distribution identity available" "signing readiness helper checks Apple Distribution identities"
require_text "scripts/check-signing-readiness.sh" "Matching App Store provisioning profile" "signing readiness helper checks matching App Store provisioning profiles"
require_text "scripts/check-signing-readiness.sh" "Requested team id does not match any installed signing identity" "signing readiness helper flags team id mismatches"
require_text "scripts/check-signing-readiness.sh" "Latest signed archive is development-signed local smoke evidence" "signing readiness helper distinguishes development archive evidence"

echo
echo "== Signed archive helper =="
if DEVELOPMENT_TEAM=ABCDE12345 "$ROOT_DIR/scripts/create-signed-archive.sh" --dry-run >/tmp/html-previewer-signed-archive-dry-run.log; then
  ok "signed archive helper dry-run succeeds"
else
  cat /tmp/html-previewer-signed-archive-dry-run.log >&2 || true
  fail "signed archive helper dry-run failed"
fi
if grep -Eq "xcodebuild[[:space:]]+archive" /tmp/html-previewer-signed-archive-dry-run.log; then
  ok "signed archive helper invokes xcodebuild archive"
else
  fail "signed archive helper dry-run is missing xcodebuild archive"
fi
if grep -Fq "DEVELOPMENT_TEAM=ABCDE12345" /tmp/html-previewer-signed-archive-dry-run.log; then
  ok "signed archive helper passes DEVELOPMENT_TEAM"
else
  fail "signed archive helper dry-run is missing DEVELOPMENT_TEAM"
fi
if grep -Fq "HTMLPreviewer.xcarchive" /tmp/html-previewer-signed-archive-dry-run.log; then
  ok "signed archive helper uses the expected archive name"
else
  fail "signed archive helper dry-run is missing the expected archive name"
fi
require_text "scripts/create-signed-archive.sh" "ALLOW_DEVELOPMENT_SIGNING" "signed archive helper keeps development signing opt-in"
require_text "scripts/create-signed-archive.sh" "Apple Distribution" "signed archive helper validates Apple Distribution signing"
require_text "scripts/create-signed-archive.sh" "get-task-allow=false" "signed archive helper rejects debug provisioning profiles"
require_text "scripts/create-signed-archive.sh" "ProvisionedDevices" "signed archive helper rejects device-limited provisioning profiles"
require_text "scripts/create-signed-archive.sh" "Apple Development" "signed archive helper rejects Apple Development signing by default"
require_text "scripts/create-signed-archive.sh" "SignedArchiveDiagnostics" "signed archive helper writes diagnostic evidence"
require_text "scripts/create-signed-archive.sh" "signed-archive-diagnostic-report\\.md" "signed archive helper writes a Markdown diagnostic report"
require_text "scripts/run-archive-device-smoke.sh" "App Store/TestFlight submission evidence" "archive device smoke report labels submission evidence"
require_text "scripts/run-archive-device-smoke.sh" "Submission evidence note" "archive device smoke report includes submission evidence note"
require_text "scripts/prepare-final-smoke-run.sh" "Archive smoke App Store/TestFlight submission evidence" "final smoke draft carries archive smoke submission evidence"

echo
echo "== Archive device smoke helper =="
if "$ROOT_DIR/scripts/run-archive-device-smoke.sh" --device TEST-DEVICE --dry-run >/tmp/html-previewer-archive-device-smoke-dry-run.log; then
  ok "archive device smoke helper dry-run succeeds"
else
  cat /tmp/html-previewer-archive-device-smoke-dry-run.log >&2 || true
  fail "archive device smoke helper dry-run failed"
fi
if grep -Fq "devicectl device install app" /tmp/html-previewer-archive-device-smoke-dry-run.log; then
  ok "archive device smoke helper installs through devicectl"
else
  fail "archive device smoke helper dry-run is missing devicectl install"
fi
if grep -Fq "devicectl device process launch" /tmp/html-previewer-archive-device-smoke-dry-run.log; then
  ok "archive device smoke helper launches through devicectl"
else
  fail "archive device smoke helper dry-run is missing devicectl launch"
fi
if grep -Fq "devicectl device capture screenshot" /tmp/html-previewer-archive-device-smoke-dry-run.log; then
  ok "archive device smoke helper captures a launch screenshot"
else
  fail "archive device smoke helper dry-run is missing devicectl screenshot capture"
fi

echo
echo "== Final smoke run helper =="
if "$ROOT_DIR/scripts/prepare-final-smoke-run.sh" --device TEST-DEVICE --dry-run >/tmp/html-previewer-final-smoke-run-dry-run.log; then
  ok "final smoke run helper dry-run succeeds"
else
  cat /tmp/html-previewer-final-smoke-run-dry-run.log >&2 || true
  fail "final smoke run helper dry-run failed"
fi
if grep -Fq "final-archive-smoke-result.md" /tmp/html-previewer-final-smoke-run-dry-run.log; then
  ok "final smoke run helper creates a result draft"
else
  fail "final smoke run helper dry-run is missing the result draft"
fi
if grep -Fq "Archive smoke report" /tmp/html-previewer-final-smoke-run-dry-run.log; then
  ok "final smoke run helper links archive smoke evidence"
else
  fail "final smoke run helper dry-run is missing archive smoke evidence"
fi
if grep -Fq "Archive smoke commit check" /tmp/html-previewer-final-smoke-run-dry-run.log; then
  ok "final smoke run helper labels archive smoke commit freshness"
else
  fail "final smoke run helper dry-run is missing archive smoke commit freshness"
fi

echo
echo "== App Store Connect run helper =="
if "$ROOT_DIR/scripts/prepare-app-store-connect-run.sh" --dry-run >/tmp/html-previewer-app-store-connect-run-dry-run.log; then
  ok "App Store Connect run helper dry-run succeeds"
else
  cat /tmp/html-previewer-app-store-connect-run-dry-run.log >&2 || true
  fail "App Store Connect run helper dry-run failed"
fi
if grep -Fq "app-store-connect-result.md" /tmp/html-previewer-app-store-connect-run-dry-run.log; then
  ok "App Store Connect run helper creates a result draft"
else
  fail "App Store Connect run helper dry-run is missing the result draft"
fi
if grep -Fq "paid download" /tmp/html-previewer-app-store-connect-run-dry-run.log &&
  grep -Fq "Data Not Collected" /tmp/html-previewer-app-store-connect-run-dry-run.log &&
  grep -Fq "no IAP" /tmp/html-previewer-app-store-connect-run-dry-run.log; then
  ok "App Store Connect run helper covers commercial and privacy gates"
else
  fail "App Store Connect run helper dry-run is missing commercial or privacy gates"
fi

echo
echo "== Submission gate status helper =="
if "$ROOT_DIR/scripts/prepare-submission-gate-status.sh" --dry-run >/tmp/html-previewer-submission-gate-status-dry-run.log; then
  ok "submission gate status helper dry-run succeeds"
else
  cat /tmp/html-previewer-submission-gate-status-dry-run.log >&2 || true
  fail "submission gate status helper dry-run failed"
fi
if grep -Fq "submission-gate-status-report.md" /tmp/html-previewer-submission-gate-status-dry-run.log; then
  ok "submission gate status helper creates a status report"
else
  fail "submission gate status helper dry-run is missing the status report"
fi

echo
echo "== Completed release results validation helper =="
if "$ROOT_DIR/scripts/validate-completed-release-results.sh" --dry-run >/tmp/html-previewer-completed-results-validation-dry-run.log; then
  ok "completed release results validation helper dry-run succeeds"
else
  cat /tmp/html-previewer-completed-results-validation-dry-run.log >&2 || true
  fail "completed release results validation helper dry-run failed"
fi
if grep -Fq "completed-release-results-validation.md" /tmp/html-previewer-completed-results-validation-dry-run.log; then
  ok "completed release results validation helper creates a report"
else
  fail "completed release results validation helper dry-run is missing the report"
fi
if "$ROOT_DIR/scripts/validate-completed-release-results.sh" --self-test >/tmp/html-previewer-completed-results-validation-self-test.log; then
  ok "completed release results validation helper self-test succeeds"
else
  cat /tmp/html-previewer-completed-results-validation-self-test.log >&2 || true
  fail "completed release results validation helper self-test failed"
fi

echo
echo "== Submission owner handoff helper =="
if "$ROOT_DIR/scripts/prepare-submission-owner-handoff.sh" --dry-run >/tmp/html-previewer-submission-owner-handoff-dry-run.log; then
  ok "submission owner handoff helper dry-run succeeds"
else
  cat /tmp/html-previewer-submission-owner-handoff-dry-run.log >&2 || true
  fail "submission owner handoff helper dry-run failed"
fi
if grep -Fq "submission-owner-handoff.md" /tmp/html-previewer-submission-owner-handoff-dry-run.log; then
  ok "submission owner handoff helper creates a report"
else
  fail "submission owner handoff helper dry-run is missing the report"
fi

echo
echo "== Physical-device validation run helper =="
if "$ROOT_DIR/scripts/prepare-physical-device-validation-run.sh" --device TEST-DEVICE --dry-run >/tmp/html-previewer-physical-validation-run-dry-run.log; then
  ok "physical-device validation run helper dry-run succeeds"
else
  cat /tmp/html-previewer-physical-validation-run-dry-run.log >&2 || true
  fail "physical-device validation run helper dry-run failed"
fi
if grep -Fq "physical-device-validation-result.md" /tmp/html-previewer-physical-validation-run-dry-run.log; then
  ok "physical-device validation run helper creates a result draft"
else
  fail "physical-device validation run helper dry-run is missing the result draft"
fi
if grep -Fq "HTMLPreviewerValidationSamples.zip" /tmp/html-previewer-physical-validation-run-dry-run.log; then
  ok "physical-device validation run helper stages the validation sample package"
else
  fail "physical-device validation run helper dry-run is missing the validation sample package"
fi

echo
echo "== Usability session run helper =="
if "$ROOT_DIR/scripts/prepare-usability-session-run.sh" --participant-code P01 --device TEST-DEVICE --dry-run >/tmp/html-previewer-usability-session-run-dry-run.log; then
  ok "usability session run helper dry-run succeeds"
else
  cat /tmp/html-previewer-usability-session-run-dry-run.log >&2 || true
  fail "usability session run helper dry-run failed"
fi
if grep -Fq "first-round-usability-result.md" /tmp/html-previewer-usability-session-run-dry-run.log; then
  ok "usability session run helper creates a result draft"
else
  fail "usability session run helper dry-run is missing the result draft"
fi
if grep -Fq "usability-observation-notes.md" /tmp/html-previewer-usability-session-run-dry-run.log; then
  ok "usability session run helper creates an observation draft"
else
  fail "usability session run helper dry-run is missing the observation draft"
fi
if grep -Fq "Participant code: P01" /tmp/html-previewer-usability-session-run-dry-run.log; then
  ok "usability session run helper carries participant code metadata"
else
  fail "usability session run helper dry-run is missing participant code metadata"
fi

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
echo "== Localization =="
require_file "HTMLMarkdownPreviewer/Localizable.xcstrings"
if python3 - "$ROOT_DIR/HTMLMarkdownPreviewer/Localizable.xcstrings" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

required_keys = {
    "error.cannotOpenFile.title",
    "error.cannotOpenHTML.title",
    "error.unsupportedFileType",
    "error.unsupportedEntryType",
    "error.text.unsupportedEncoding",
    "error.zip.invalidArchive",
    "error.zip.unsafeOrConflictingPath",
    "error.zip.archiveTooLarge",
    "error.zip.tooManyFiles",
    "error.zip.singleFileTooLarge",
    "error.zip.expandedSizeTooLarge",
    "error.zip.missingEntryFile",
    "security.html.interactive.confirmation",
    "security.html.interactive.status",
    "security.html.safe.singleFile.message",
    "security.html.safe.zip.message",
    "security.markdown.externalLink.title",
    "security.markdown.externalLink.message",
    "security.markdown.unsupportedLink.title",
    "security.markdown.unsupportedLink.message",
    "security.preview.rawText.message",
    "settings.clearImportedFiles.confirmation",
}

strings = data.get("strings", {})
missing = sorted(required_keys - strings.keys())
empty_values = []
required_locales = {"en", "zh-Hans", "zh-Hant", "ja"}
for key in required_keys & strings.keys():
    localizations = strings[key].get("localizations", {})
    missing_locales = sorted(required_locales - localizations.keys())
    if missing_locales:
        empty_values.append(f"{key} missing locales: {', '.join(missing_locales)}")
        continue

    for locale in sorted(required_locales):
        value = (
            localizations[locale]
            .get("stringUnit", {})
            .get("value", "")
        )
        if not value.strip():
            empty_values.append(f"{key} has empty {locale} value")

if missing or empty_values:
    if missing:
        print("missing localization keys: " + ", ".join(missing), file=sys.stderr)
    if empty_values:
        print("locale coverage issues: " + "; ".join(sorted(empty_values)), file=sys.stderr)
    raise SystemExit(1)
PY
then
  ok "Localizable.xcstrings is valid and critical error and safety copy has en, zh-Hans, zh-Hant, and ja values"
else
  fail "Localizable.xcstrings is invalid or critical error/safety locale coverage is incomplete"
fi

echo
echo "== App icon =="
require_file "HTMLMarkdownPreviewer/Assets.xcassets/AppIcon.appiconset/Contents.json"
require_file "HTMLMarkdownPreviewer/Assets.xcassets/AppIcon.appiconset/AppIcon-1024x1024@1x.png"
check_png_dimensions "HTMLMarkdownPreviewer/Assets.xcassets/AppIcon.appiconset/AppIcon-1024x1024@1x.png" 1024 1024

echo
echo "== Accessibility =="
require_text "HTMLMarkdownPreviewer/AppView.swift" "accessibilityLabel.*sample.title.*sample.subtitle" "built-in sample rows expose combined VoiceOver labels"
require_text "HTMLMarkdownPreviewer/AppView.swift" "accessibilityLabel.*document.displayName.*typeText.*dateText" "recent document rows expose type, size, and date VoiceOver labels"
require_text "HTMLMarkdownPreviewer/Views/DocumentPreviewView.swift" "accessibilityLabel\\(AppStrings\\.Accessibility\\.previewMode\\)" "preview mode control has a VoiceOver label"
require_text "HTMLMarkdownPreviewer/Views/DocumentPreviewView.swift" "accessibilityHint\\(AppStrings\\.Accessibility\\.previewModeHint\\)" "preview mode control has a VoiceOver hint"
require_text "HTMLMarkdownPreviewer/Views/DocumentPreviewView.swift" "accessibilityIdentifier\\(\"preview-mode-menu\"\\)" "preview mode control has a UI test identifier"
require_text "HTMLMarkdownPreviewer/Views/DocumentPreviewView.swift" "accessibilityLabel: AppStrings\\.Accessibility\\.shareFile" "share control has a VoiceOver label"
require_text "HTMLMarkdownPreviewer/Views/DocumentPreviewView.swift" "accessibilityIdentifier: \"share-file-button\"" "share control has a UI test identifier"
require_text "HTMLMarkdownPreviewer/Views/DocumentPreviewView.swift" "accessibilityLabel\\(AppStrings\\.Accessibility\\.fileDetails\\)" "details control has a VoiceOver label"
require_text "HTMLMarkdownPreviewer/Views/DocumentPreviewView.swift" "accessibilityIdentifier\\(\"file-details-button\"\\)" "details control has a UI test identifier"
require_text "HTMLMarkdownPreviewer/Views/DocumentPreviewView.swift" "accessibilityLabel.*status.title.*status.message" "preview status bar exposes a combined VoiceOver label"
require_text "HTMLMarkdownPreviewer/Views/DocumentDetailsView.swift" "accessibilityIdentifier\\(\"document-details-screen\"\\)" "document details sheet has a UI test identifier"
require_text "HTMLMarkdownPreviewer/Views/DocumentDetailsView.swift" "accessibilityIdentifier\\(\"document-details-done-button\"\\)" "document details Done button has a UI test identifier"
require_text "HTMLMarkdownPreviewer/Views/DocumentDetailsView.swift" "accessibilityLabel.*title.*value" "document details rows expose combined VoiceOver labels"
require_text "HTMLMarkdownPreviewer/Views/MarkdownPreviewView.swift" "AppStrings\\.Accessibility\\.markdownImage" "Markdown images without alt text get a fallback VoiceOver label"
require_text "HTMLMarkdownPreviewer/Views/MarkdownPreviewView.swift" "accessibilityLabel.*title.*detail" "Markdown image placeholders expose combined VoiceOver labels"

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
  "docs/github-actions-troubleshooting.md" \
  "docs/physical-device-validation.md" \
  "docs/physical-device-validation-result-template.md" \
  "docs/usability-testing/script.md" \
  "docs/usability-testing/observation-template.md" \
  "docs/usability-testing/first-round-result-template.md"; do
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
require_text "docs/app-store-connect-handoff.md" "prepare-app-store-connect-run\\.sh" "App Store Connect handoff uses the App Store Connect run helper"
require_text "docs/app-store-connect-handoff.md" "prepare-final-smoke-run\\.sh" "App Store Connect handoff uses the final smoke run helper"
require_text "docs/app-store-submission-runbook.md" "DerivedData/AppStoreConnectRun" "submission runbook points to generated App Store Connect result"
require_text "docs/app-store-submission-runbook.md" "DerivedData/FinalSmokeRun" "submission runbook points to generated final smoke result"
require_text "docs/app-store-submission-runbook.md" "physical-device validation draft staging" "submission runbook says final preflight stages physical-device validation drafts"
require_text "docs/app-store-submission-runbook.md" "check-github-actions-execution\\.sh" "submission runbook points to Actions execution diagnostics"
require_text "docs/app-store-submission-runbook.md" "attempt <attempt-number>" "submission runbook documents Actions rerun attempt diagnostics"
require_text "docs/app-store-submission-runbook.md" "prepare-local-automated-test-report\\.sh" "submission runbook points to local automated test evidence"
require_text "docs/app-store-submission-runbook.md" "check-signing-readiness\\.sh" "submission runbook points to signing readiness evidence"
require_text "docs/app-store-submission-runbook.md" "validate-completed-release-results\\.sh" "submission runbook points to completed result validation"
require_text "docs/app-store-submission-runbook.md" "prepare-submission-owner-handoff\\.sh" "submission runbook points to owner handoff"
require_text "scripts/verify-public-pages.sh" "gist\\.githubusercontent\\.com/.*/raw/privacy-policy\\.md" "public page verifier uses stable privacy raw file URL"
require_text "scripts/verify-public-pages.sh" "gist\\.githubusercontent\\.com/.*/raw/support\\.md" "public page verifier uses stable support raw file URL"
require_text "docs/github-actions-troubleshooting.md" "steps: \\[\\]" "GitHub Actions troubleshooting documents zero-step blocker"
require_text "docs/github-actions-troubleshooting.md" "Budgets and alerts" "GitHub Actions troubleshooting covers billing budget checks"
require_text "docs/github-actions-troubleshooting.md" "attempt <attempt-number>" "GitHub Actions troubleshooting documents rerun attempt diagnostics"
require_text "docs/final-archive-smoke-test-template.md" "Can submit for review" "final smoke template includes submission decision"
require_text "docs/final-archive-smoke-test-template.md" "Data Not Collected" "final smoke template covers App Store privacy label check"
require_text "docs/final-archive-smoke-test-template.md" "Build source must be a signed archive or TestFlight build" "final smoke template rejects development-signed build evidence"
require_text "docs/physical-device-validation-result-template.md" "External Open Matrix" "physical-device result template includes source matrix"
require_text "docs/physical-device-validation-result-template.md" "Can close #1" "physical-device result template includes issue close decision"
require_text "docs/physical-device-validation.md" "Files local row must be Pass" "physical-device guide documents required Files local coverage"
require_text "scripts/final-submission-preflight.sh" "Physical-device validation result draft staging" "final preflight stages current physical-device validation drafts"
require_text "docs/usability-testing/first-round-result-template.md" "Can close #11" "usability result template includes issue close decision"
require_text "docs/usability-testing/first-round-result-template.md" "Do not store the participant's real name" "usability result template avoids direct participant identifiers"
require_text "docs/privacy-policy.md" "HTML Previewer does not collect personal data" "privacy policy states no personal data collection"
require_text "docs/support.md" "https://gist\\.github\\.com/Kaedeeeeeeeeee/394a005738e00a0f72bf9bd3a5abd59c" "support page includes support contact"

echo
echo "== Screenshots =="
require_file "docs/app-store-screenshots/copy.json"
require_file "scripts/generate-app-store-screenshots.swift"
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
for locale in en-US zh-Hans ja; do
  for name in \
    iphone-01-home \
    iphone-02-html-safe-preview \
    iphone-03-markdown-preview \
    iphone-04-zip-report-preview \
    iphone-05-settings; do
    check_png_dimensions "docs/app-store-screenshots/$locale/$name.png" 1320 2868
  done
  for name in \
    ipad-01-home \
    ipad-02-html-safe-preview \
    ipad-03-markdown-preview \
    ipad-04-zip-report-preview \
    ipad-05-settings; do
    check_png_dimensions "docs/app-store-screenshots/$locale/$name.png" 2064 2752
  done
done
if python3 - "$ROOT_DIR/docs/app-store-screenshots/copy.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    copy = json.load(handle)

required_locales = {"en-US", "zh-Hans", "ja"}
required_screenshots = {
    "01-home",
    "02-html-safe-preview",
    "03-markdown-preview",
    "04-zip-report-preview",
    "05-settings",
}
if set(copy) != required_locales:
    raise SystemExit(f"unexpected screenshot locales: {sorted(copy)}")

for locale in sorted(required_locales):
    entries = copy[locale].get("screenshots", {})
    if set(entries) != required_screenshots:
        raise SystemExit(f"unexpected screenshot copy keys for {locale}: {sorted(entries)}")
    for key, value in entries.items():
        for field in ("eyebrow", "title", "subtitle"):
            if not str(value.get(field, "")).strip():
                raise SystemExit(f"empty {locale}/{key}/{field}")
PY
then
  ok "App Store screenshot copy covers en-US, zh-Hans, and ja"
else
  fail "App Store screenshot copy is incomplete or invalid"
fi

for locale in en-US zh-Hans ja; do
  for field in name subtitle promotional_text description keywords release_notes support_url privacy_url; do
    require_file "fastlane/metadata/$locale/$field.txt"
  done
done
if python3 - "$ROOT_DIR/fastlane/metadata" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
limits = {
    "name.txt": 30,
    "subtitle.txt": 30,
    "promotional_text.txt": 170,
    "description.txt": 4000,
    "keywords.txt": 100,
    "release_notes.txt": 4000,
}
for locale in ("en-US", "zh-Hans", "ja"):
    for filename, limit in limits.items():
        value = (root / locale / filename).read_text(encoding="utf-8").strip()
        if not value:
            raise SystemExit(f"empty metadata: {locale}/{filename}")
        if len(value) > limit:
            raise SystemExit(f"metadata too long: {locale}/{filename} is {len(value)}, limit {limit}")
PY
then
  ok "Fastlane metadata is complete and within App Store length limits"
else
  fail "Fastlane metadata is incomplete or exceeds App Store limits"
fi

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
if "$ROOT_DIR/scripts/serve-validation-samples.sh" --prepare-only >/tmp/html-previewer-validation-samples-server.log; then
  ok "validation sample browser delivery page can be prepared"
else
  cat /tmp/html-previewer-validation-samples-server.log >&2 || true
  fail "validation sample browser delivery page generation failed"
fi
if python3 - "$ROOT_DIR/DerivedData/ValidationSamples/index.html" <<'PY'
import pathlib
import sys

index_path = pathlib.Path(sys.argv[1])
if not index_path.exists():
    print(f"missing validation download index: {index_path}", file=sys.stderr)
    raise SystemExit(1)

html = index_path.read_text(encoding="utf-8")
expected_links = [
    "HTMLPreviewerValidationSamples/basic-report.html",
    "HTMLPreviewerValidationSamples/legacy-report.htm",
    "HTMLPreviewerValidationSamples/markdown-notes.md",
    "HTMLPreviewerValidationSamples/markdown-reference.markdown",
    "HTMLPreviewerValidationSamples/zip-report.zip",
    "HTMLPreviewerValidationSamples/external-resource.html",
    "HTMLPreviewerValidationSamples/interactive-trusted.html",
    "HTMLPreviewerValidationSamples/broken.zip",
    "HTMLPreviewerValidationSamples.zip",
]
missing = [link for link in expected_links if link not in html]
if missing:
    print("missing links in validation download index: " + ", ".join(missing), file=sys.stderr)
    raise SystemExit(1)
PY
then
  ok "validation sample browser delivery page links expected files"
else
  fail "validation sample browser delivery page is missing expected links"
fi
if "$ROOT_DIR/scripts/prepare-usability-test-packet.sh" >/tmp/html-previewer-usability-packet.log; then
  ok "usability test packet can be generated"
else
  cat /tmp/html-previewer-usability-packet.log >&2 || true
  fail "usability test packet generation failed"
fi
if python3 - "$ROOT_DIR/DerivedData/UsabilityTestPacket/HTMLPreviewerUsabilityTestPacket.zip" <<'PY'
import subprocess
import sys

zip_path = sys.argv[1]
expected = {
    "HTMLPreviewerUsabilityTestPacket/README.txt",
    "HTMLPreviewerUsabilityTestPacket/README-usability.md",
    "HTMLPreviewerUsabilityTestPacket/script.md",
    "HTMLPreviewerUsabilityTestPacket/observation-template.md",
    "HTMLPreviewerUsabilityTestPacket/first-round-result-template.md",
    "HTMLPreviewerUsabilityTestPacket/AppStore/app-store-listing.md",
    "HTMLPreviewerUsabilityTestPacket/AppStore/privacy-policy.md",
    "HTMLPreviewerUsabilityTestPacket/Samples/basic-report.html",
    "HTMLPreviewerUsabilityTestPacket/Samples/legacy-report.htm",
    "HTMLPreviewerUsabilityTestPacket/Samples/markdown-notes.md",
    "HTMLPreviewerUsabilityTestPacket/Samples/markdown-reference.markdown",
    "HTMLPreviewerUsabilityTestPacket/Samples/zip-report.zip",
    "HTMLPreviewerUsabilityTestPacket/Samples/external-resource.html",
    "HTMLPreviewerUsabilityTestPacket/Samples/interactive-trusted.html",
    "HTMLPreviewerUsabilityTestPacket/Samples/broken.zip",
}
raw = subprocess.check_output(["unzip", "-Z1", zip_path], text=True)
found = set(raw.splitlines())
missing = sorted(expected - found)
if missing:
    print("missing files in usability test packet: " + ", ".join(missing), file=sys.stderr)
    raise SystemExit(1)
PY
then
  ok "usability test packet contains expected files"
else
  fail "usability test packet is missing expected files"
fi
if "$ROOT_DIR/scripts/prepare-usability-session-run.sh" --participant-code P01 --device TEST-DEVICE >/tmp/html-previewer-usability-session.log; then
  ok "usability session run can be generated"
else
  cat /tmp/html-previewer-usability-session.log >&2 || true
  fail "usability session run generation failed"
fi
if python3 - "$ROOT_DIR/DerivedData/UsabilitySessionRun" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
results = sorted(root.glob("**/first-round-usability-result.md"))
if not results:
    print("missing first-round usability result draft", file=sys.stderr)
    raise SystemExit(1)

latest = results[-1]
run_dir = latest.parent
expected = [
    run_dir / "usability-observation-notes.md",
    run_dir / "HTMLPreviewerUsabilityTestPacket.zip",
    run_dir / "HTMLPreviewerUsabilityTestPacket" / "script.md",
    run_dir / "devicectl-devices.txt",
]
missing = [str(path) for path in expected if not path.exists()]
text = latest.read_text(encoding="utf-8")
for marker in ["Issue: #11", "Participant code: P01", "Do not store the participant's real name", "Can close #11"]:
    if marker not in text:
        missing.append(f"result marker: {marker}")
if missing:
    print("missing usability session artifacts: " + ", ".join(missing), file=sys.stderr)
    raise SystemExit(1)
PY
then
  ok "usability session run contains expected drafts and packet artifacts"
else
  fail "usability session run is missing expected artifacts"
fi
if "$ROOT_DIR/scripts/prepare-submission-gate-status.sh" >/tmp/html-previewer-submission-gate-status.log; then
  ok "submission gate status report can be generated"
else
  cat /tmp/html-previewer-submission-gate-status.log >&2 || true
  fail "submission gate status report generation failed"
fi
if python3 - "$ROOT_DIR/DerivedData/SubmissionGateStatus/submission-gate-status-report.md" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
required = [
    "# Submission Gate Status Report",
    "Final local preflight",
    "Completed manual result validation",
    "GitHub Actions iOS CI",
    "Physical-device external-open matrix",
    "App Store Connect paid-download setup",
    "Distribution archive or TestFlight upload evidence",
    "Final archive/TestFlight smoke",
    "First external usability round",
]
missing = [marker for marker in required if marker not in text]
if missing:
    print("missing submission gate markers: " + ", ".join(missing), file=sys.stderr)
    raise SystemExit(1)
PY
then
  ok "submission gate status report covers required App Store gates"
else
  fail "submission gate status report is missing required gates"
fi

if "$ROOT_DIR/scripts/validate-completed-release-results.sh" >/tmp/html-previewer-completed-results-validation.log; then
  ok "completed release results validation report can be generated"
else
  cat /tmp/html-previewer-completed-results-validation.log >&2 || true
  fail "completed release results validation report generation failed"
fi
if "$ROOT_DIR/scripts/check-signing-readiness.sh" >/tmp/html-previewer-signing-readiness.log; then
  ok "signing readiness report can be generated"
else
  cat /tmp/html-previewer-signing-readiness.log >&2 || true
  fail "signing readiness report generation failed"
fi
if python3 - "$ROOT_DIR/DerivedData/SigningReadiness" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
reports = sorted(root.glob("**/signing-readiness-report.md"))
if not reports:
    print("missing signing readiness report", file=sys.stderr)
    raise SystemExit(1)
text = reports[-1].read_text(encoding="utf-8")
required = [
    "# Signing Readiness Report",
    "App Store/TestFlight archive readiness",
    "Local device smoke readiness",
    "Apple Distribution identity available",
    "Matching App Store provisioning profile",
]
missing = [marker for marker in required if marker not in text]
if missing:
    print("missing signing readiness markers: " + ", ".join(missing), file=sys.stderr)
    raise SystemExit(1)
PY
then
  ok "signing readiness report covers signing and provisioning gates"
else
  fail "signing readiness report is missing required markers"
fi
if "$ROOT_DIR/scripts/validate-completed-release-results.sh" --self-test >/tmp/html-previewer-completed-results-validation-self-test.log; then
  ok "completed release results validation self-test passes"
else
  cat /tmp/html-previewer-completed-results-validation-self-test.log >&2 || true
  fail "completed release results validation self-test failed"
fi
if python3 - "$ROOT_DIR/DerivedData/CompletedReleaseResultsValidation/completed-release-results-validation.md" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
required = [
    "# Completed Release Results Validation",
    "Physical-device external-open result",
    "App Store Connect setup result",
    "Final archive/TestFlight smoke result",
    "First external usability result",
]
missing = [marker for marker in required if marker not in text]
if missing:
    print("missing completed result validation markers: " + ", ".join(missing), file=sys.stderr)
    raise SystemExit(1)
PY
then
  ok "completed release results validation report covers required manual result drafts"
else
  fail "completed release results validation report is missing required result drafts"
fi
if "$ROOT_DIR/scripts/prepare-submission-owner-handoff.sh" >/tmp/html-previewer-submission-owner-handoff.log; then
  ok "submission owner handoff report can be generated"
else
  cat /tmp/html-previewer-submission-owner-handoff.log >&2 || true
  fail "submission owner handoff report generation failed"
fi
if python3 - "$ROOT_DIR/DerivedData/SubmissionOwnerHandoff/submission-owner-handoff.md" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
required = [
    "# Submission Owner Handoff",
    "GitHub account owner",
    "App Store Connect account owner",
    "Signing/upload owner",
    "Physical-device tester",
    "Final smoke tester",
    "Usability moderator",
    "Release operator",
    "Do not treat a development-signed archive as App Store/TestFlight upload evidence.",
]
missing = [marker for marker in required if marker not in text]
if missing:
    print("missing owner handoff markers: " + ", ".join(missing), file=sys.stderr)
    raise SystemExit(1)
PY
then
  ok "submission owner handoff report covers required external owners"
else
  fail "submission owner handoff report is missing required owner markers"
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
    "HTMLPreviewerReleasePacket/AppStoreConnect/app-store-connect-result-draft.md",
    "HTMLPreviewerReleasePacket/FinalSmoke/final-archive-smoke-result-draft.md",
    "HTMLPreviewerReleasePacket/Evidence/README.txt",
    "HTMLPreviewerReleasePacket/Evidence/release-evidence-index.md",
    "HTMLPreviewerReleasePacket/Evidence/checksums-sha256.txt",
    "HTMLPreviewerReleasePacket/Evidence/completed-release-results-validation.md",
    "HTMLPreviewerReleasePacket/Evidence/submission-gate-status-report.md",
    "HTMLPreviewerReleasePacket/Evidence/submission-owner-handoff.md",
    "HTMLPreviewerReleasePacket/Evidence/SigningReadiness/signing-readiness-report.md",
    "HTMLPreviewerReleasePacket/PhysicalDevice/physical-device-validation.md",
    "HTMLPreviewerReleasePacket/PhysicalDevice/physical-device-validation-result-template.md",
    "HTMLPreviewerReleasePacket/PhysicalDevice/HTMLPreviewerValidationSamples.zip",
    "HTMLPreviewerReleasePacket/PhysicalDevice/validation-download-index.html",
    "HTMLPreviewerReleasePacket/PhysicalDevice/README-browser-delivery.txt",
    "HTMLPreviewerReleasePacket/UsabilityTesting/script.md",
    "HTMLPreviewerReleasePacket/UsabilityTesting/observation-template.md",
    "HTMLPreviewerReleasePacket/UsabilityTesting/first-round-result-template.md",
    "HTMLPreviewerReleasePacket/UsabilityTesting/HTMLPreviewerUsabilityTestPacket.zip",
    "HTMLPreviewerReleasePacket/UsabilityTesting/first-round-usability-result-draft.md",
    "HTMLPreviewerReleasePacket/UsabilityTesting/LatestSessionRun/usability-observation-notes.md",
    "HTMLPreviewerReleasePacket/PublicPages/privacy-policy.md",
    "HTMLPreviewerReleasePacket/PublicPages/support.md",
    "HTMLPreviewerReleasePacket/Compliance/privacy-required-reasons.md",
    "HTMLPreviewerReleasePacket/Compliance/export-compliance.md",
    "HTMLPreviewerReleasePacket/Operations/github-actions-troubleshooting.md",
    "HTMLPreviewerReleasePacket/AppMetadata/PrivacyInfo.xcprivacy",
    "HTMLPreviewerReleasePacket/AppMetadata/AppIcon-1024x1024@1x.png",
    "HTMLPreviewerReleasePacket/Scripts/check-github-actions-execution.sh",
    "HTMLPreviewerReleasePacket/Scripts/prepare-local-automated-test-report.sh",
    "HTMLPreviewerReleasePacket/Scripts/check-signing-readiness.sh",
    "HTMLPreviewerReleasePacket/Scripts/create-signed-archive.sh",
    "HTMLPreviewerReleasePacket/Scripts/final-submission-preflight.sh",
    "HTMLPreviewerReleasePacket/Scripts/prepare-submission-gate-status.sh",
    "HTMLPreviewerReleasePacket/Scripts/validate-completed-release-results.sh",
    "HTMLPreviewerReleasePacket/Scripts/prepare-submission-owner-handoff.sh",
    "HTMLPreviewerReleasePacket/Scripts/archive-preflight.sh",
    "HTMLPreviewerReleasePacket/Scripts/portable-release-materials-audit.sh",
    "HTMLPreviewerReleasePacket/Scripts/release-audit.sh",
    "HTMLPreviewerReleasePacket/Scripts/prepare-app-store-connect-run.sh",
    "HTMLPreviewerReleasePacket/Scripts/prepare-final-smoke-run.sh",
    "HTMLPreviewerReleasePacket/Scripts/prepare-physical-device-validation-run.sh",
    "HTMLPreviewerReleasePacket/Scripts/prepare-usability-session-run.sh",
    "HTMLPreviewerReleasePacket/Scripts/run-archive-device-smoke.sh",
    "HTMLPreviewerReleasePacket/Scripts/serve-validation-samples.sh",
    "HTMLPreviewerReleasePacket/Scripts/prepare-usability-test-packet.sh",
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
if python3 - \
  "$ROOT_DIR/DerivedData/ReleasePacket/HTMLPreviewerReleasePacket.zip" \
  "$ROOT_DIR/DerivedData/PhysicalDeviceValidationRun" \
  "$ROOT_DIR/DerivedData/PhysicalDeviceSmoke" \
  "$ROOT_DIR/DerivedData/GitHubActionsDiagnostics" \
  "$ROOT_DIR/DerivedData/SigningReadiness" \
  "$ROOT_DIR/DerivedData/SignedArchiveDiagnostics" <<'PY'
import pathlib
import subprocess
import sys

zip_path, physical_root, smoke_root, actions_root, signing_root, signed_archive_root = sys.argv[1:]
raw = subprocess.check_output(["unzip", "-Z1", zip_path], text=True)
found = set(raw.splitlines())

checks = []
physical_files = sorted(pathlib.Path(physical_root).glob("**/physical-device-validation-result.md"))
if physical_files:
    checks.append("HTMLPreviewerReleasePacket/PhysicalDevice/physical-device-validation-result-draft.md")
    checks.append("HTMLPreviewerReleasePacket/PhysicalDevice/LatestValidationRun/devicectl-devices.txt")

smoke_files = sorted(pathlib.Path(smoke_root).glob("**/archive-device-smoke-report.md"))
if smoke_files:
    checks.append("HTMLPreviewerReleasePacket/FinalSmoke/ArchiveDeviceSmoke/archive-device-smoke-report.md")

actions_files = sorted(pathlib.Path(actions_root).glob("**/github-actions-diagnostics.md"))
if actions_files:
    checks.append("HTMLPreviewerReleasePacket/Operations/GitHubActionsDiagnostics/github-actions-diagnostics.md")

signing_files = sorted(pathlib.Path(signing_root).glob("**/signing-readiness-report.md"))
if signing_files:
    checks.append("HTMLPreviewerReleasePacket/Evidence/SigningReadiness/signing-readiness-report.md")

local_test_files = sorted(pathlib.Path(zip_path).parents[1].glob("LocalAutomatedTests/**/local-automated-test-report.md"))
if local_test_files:
    checks.append("HTMLPreviewerReleasePacket/Evidence/LocalAutomatedTests/local-automated-test-report.md")

signed_archive_files = sorted(pathlib.Path(signed_archive_root).glob("**/signed-archive-diagnostic-report.md"))
if signed_archive_files:
    checks.append("HTMLPreviewerReleasePacket/Evidence/SignedArchiveDiagnostics/signed-archive-diagnostic-report.md")

missing = [path for path in checks if path not in found]
if missing:
    print("missing optional release evidence copies: " + ", ".join(missing), file=sys.stderr)
    raise SystemExit(1)
PY
then
  ok "release packet copies available local evidence drafts"
else
  fail "release packet is missing available local evidence drafts"
fi
if unzip -p "$ROOT_DIR/DerivedData/ReleasePacket/HTMLPreviewerReleasePacket.zip" \
  HTMLPreviewerReleasePacket/Evidence/checksums-sha256.txt |
  grep -Fq "Evidence/release-evidence-index.md" &&
  unzip -p "$ROOT_DIR/DerivedData/ReleasePacket/HTMLPreviewerReleasePacket.zip" \
    HTMLPreviewerReleasePacket/Evidence/checksums-sha256.txt |
    grep -Fq "AppStoreConnect/app-store-connect-result-draft.md"; then
  ok "release packet checksum manifest covers key evidence files"
else
  fail "release packet checksum manifest is missing key evidence files"
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
