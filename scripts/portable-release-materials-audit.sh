#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT_DIR" <<'PY'
import json
import pathlib
import plistlib
import re
import struct
import sys
import zipfile

root = pathlib.Path(sys.argv[1])
failures = []


def ok(message):
    print(f"[OK] {message}")


def fail(message):
    failures.append(message)
    print(f"[FAIL] {message}", file=sys.stderr)


def rel(path):
    return pathlib.Path(path)


def require_file(path):
    candidate = root / path
    if candidate.is_file():
        ok(f"{path} exists")
        return candidate
    fail(f"{path} is missing")
    return candidate


def require_text(path, pattern, message):
    candidate = require_file(path)
    if not candidate.is_file():
        return
    text = candidate.read_text(encoding="utf-8", errors="replace")
    if re.search(pattern, text, re.MULTILINE):
        ok(message)
    else:
        fail(message)


def read_text(path):
    return (root / path).read_text(encoding="utf-8", errors="replace")


def png_dimensions(path):
    candidate = require_file(path)
    if not candidate.is_file():
        return None
    with candidate.open("rb") as handle:
        header = handle.read(24)
    signature = b"\x89PNG\r\n\x1a\n"
    if len(header) < 24 or not header.startswith(signature) or header[12:16] != b"IHDR":
        fail(f"{path} is not a valid PNG")
        return None
    width, height = struct.unpack(">II", header[16:24])
    return width, height


def require_png_dimensions(path, width, height):
    dimensions = png_dimensions(path)
    if dimensions == (width, height):
        ok(f"{path} is {width}x{height}")
    elif dimensions is not None:
        fail(f"{path} is {dimensions[0]}x{dimensions[1]}, expected {width}x{height}")


def load_plist(path):
    candidate = require_file(path)
    if not candidate.is_file():
        return {}
    with candidate.open("rb") as handle:
        return plistlib.load(handle)


def require_zip_entries(path, expected_entries, message):
    candidate = require_file(path)
    if not candidate.is_file():
        return
    with zipfile.ZipFile(candidate) as archive:
        names = set(archive.namelist())
        archive.testzip()
    missing = sorted(set(expected_entries) - names)
    if missing:
        fail(f"{message}: missing {', '.join(missing)}")
    else:
        ok(message)


print("== Portable Project Metadata ==")
for path in [
    "project.yml",
    "HTMLMarkdownPreviewer.xcodeproj/project.pbxproj",
    "HTMLMarkdownPreviewer/Info.plist",
    "HTMLMarkdownPreviewer/PrivacyInfo.xcprivacy",
    "HTMLMarkdownPreviewer/Localizable.xcstrings",
    "HTMLMarkdownPreviewerUITests/SmokeUITests.swift",
    "scripts/check-github-actions-execution.sh",
    "scripts/prepare-submission-gate-status.sh",
    "scripts/validate-completed-release-results.sh",
    "scripts/prepare-submission-owner-handoff.sh",
    "scripts/prepare-usability-session-run.sh",
]:
    require_file(path)

require_text("project.yml", r"CURRENT_PROJECT_VERSION:\s*1\b", "project.yml build number is 1")
require_text("project.yml", r"MARKETING_VERSION:\s*1\.0\b", "project.yml marketing version is 1.0")
require_text("project.yml", r"deploymentTarget:\s*\n\s+iOS:\s*\"17\.0\"", "project.yml minimum iOS is 17.0")
require_text("project.yml", r"PRODUCT_BUNDLE_IDENTIFIER:\s*com\.kaede\.htmlmarkdownpreviewer", "project.yml bundle identifier is correct")
require_text("project.yml", r"ASSETCATALOG_COMPILER_APPICON_NAME:\s*AppIcon", "project.yml configures AppIcon")
require_text("project.yml", r"ZIPFoundation:[\s\S]*from:\s*0\.9\.20", "ZIPFoundation dependency version is declared")
require_text("project.yml", r"SwiftMarkdown:[\s\S]*from:\s*0\.8\.0", "Swift Markdown dependency version is declared")

require_text("HTMLMarkdownPreviewer.xcodeproj/project.pbxproj", r"MARKETING_VERSION = 1\.0;", "generated Xcode project marketing version is 1.0")
require_text("HTMLMarkdownPreviewer.xcodeproj/project.pbxproj", r"CURRENT_PROJECT_VERSION = 1;", "generated Xcode project build number is 1")
require_text("HTMLMarkdownPreviewer.xcodeproj/project.pbxproj", r"PRODUCT_BUNDLE_IDENTIFIER = com\.kaede\.htmlmarkdownpreviewer;", "generated Xcode project bundle identifier is correct")

print("\n== Info.plist ==")
info = load_plist("HTMLMarkdownPreviewer/Info.plist")
info_errors = []
if info.get("CFBundleDisplayName") != "HTML Previewer":
    info_errors.append("CFBundleDisplayName must be HTML Previewer")
if info.get("LSApplicationCategoryType") != "public.app-category.productivity":
    info_errors.append("LSApplicationCategoryType must be productivity")
if info.get("ITSAppUsesNonExemptEncryption") is not False:
    info_errors.append("ITSAppUsesNonExemptEncryption must be false")
if info.get("LSSupportsOpeningDocumentsInPlace") is not True:
    info_errors.append("LSSupportsOpeningDocumentsInPlace must be true")

found_types = set()
for document_type in info.get("CFBundleDocumentTypes", []):
    found_types.update(document_type.get("LSItemContentTypes", []))
missing_types = sorted({"public.html", "public.xhtml", "net.daringfireball.markdown", "public.zip-archive"} - found_types)
if missing_types:
    info_errors.append("missing document types: " + ", ".join(missing_types))

markdown_declared = any(
    declaration.get("UTTypeIdentifier") == "net.daringfireball.markdown"
    and set(declaration.get("UTTypeTagSpecification", {}).get("public.filename-extension", [])) >= {"md", "markdown"}
    for declaration in info.get("UTImportedTypeDeclarations", [])
)
if not markdown_declared:
    info_errors.append("Markdown imported type must include md and markdown")

if info_errors:
    for error in info_errors:
        fail(error)
else:
    ok("Info.plist app metadata and document types are valid")

print("\n== Privacy Manifest ==")
privacy = load_plist("HTMLMarkdownPreviewer/PrivacyInfo.xcprivacy")
privacy_errors = []
if privacy.get("NSPrivacyCollectedDataTypes") != []:
    privacy_errors.append("NSPrivacyCollectedDataTypes must be empty")
if privacy.get("NSPrivacyTracking") is not False:
    privacy_errors.append("NSPrivacyTracking must be false")
if privacy.get("NSPrivacyTrackingDomains") != []:
    privacy_errors.append("NSPrivacyTrackingDomains must be empty")
file_timestamp = next(
    (
        item
        for item in privacy.get("NSPrivacyAccessedAPITypes", [])
        if item.get("NSPrivacyAccessedAPIType") == "NSPrivacyAccessedAPICategoryFileTimestamp"
    ),
    None,
)
if file_timestamp is None:
    privacy_errors.append("missing file timestamp required-reason API declaration")
else:
    reasons = set(file_timestamp.get("NSPrivacyAccessedAPITypeReasons", []))
    if not {"C617.1", "3B52.1"} <= reasons:
        privacy_errors.append("file timestamp declaration must include C617.1 and 3B52.1")

if privacy_errors:
    for error in privacy_errors:
        fail(error)
else:
    ok("Privacy manifest matches no-data release stance and required reason APIs")

print("\n== Localization ==")
xcstrings_path = require_file("HTMLMarkdownPreviewer/Localizable.xcstrings")
if xcstrings_path.is_file():
    data = json.loads(xcstrings_path.read_text(encoding="utf-8"))
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
    locales = {"en", "zh-Hans", "zh-Hant", "ja"}
    strings = data.get("strings", {})
    missing_keys = sorted(required_keys - strings.keys())
    locale_errors = []
    for key in sorted(required_keys & strings.keys()):
        localizations = strings[key].get("localizations", {})
        missing_locales = sorted(locales - localizations.keys())
        if missing_locales:
            locale_errors.append(f"{key} missing locales: {', '.join(missing_locales)}")
            continue
        for locale in sorted(locales):
            value = localizations[locale].get("stringUnit", {}).get("value", "")
            if not value.strip():
                locale_errors.append(f"{key} has empty {locale} value")

    if missing_keys or locale_errors:
        if missing_keys:
            fail("missing localization keys: " + ", ".join(missing_keys))
        for error in locale_errors:
            fail(error)
    else:
        ok("critical error and safety strings cover en, zh-Hans, zh-Hant, and ja")

print("\n== Visual Assets ==")
require_png_dimensions("HTMLMarkdownPreviewer/Assets.xcassets/AppIcon.appiconset/AppIcon-1024x1024@1x.png", 1024, 1024)
for name in ["iphone-01-home", "iphone-02-html-safe-preview", "iphone-03-markdown-preview", "iphone-04-zip-report-preview", "iphone-05-settings"]:
    require_png_dimensions(f"docs/app-store-screenshots/{name}.png", 1320, 2868)
for name in ["ipad-01-home", "ipad-02-html-safe-preview", "ipad-03-markdown-preview", "ipad-04-zip-report-preview", "ipad-05-settings"]:
    require_png_dimensions(f"docs/app-store-screenshots/{name}.png", 2064, 2752)

print("\n== App Store Materials ==")
for path in [
    "docs/app-store-listing.md",
    "docs/app-store-connect-handoff.md",
    "docs/app-store-submission-runbook.md",
    "docs/final-archive-smoke-test-template.md",
    "docs/release-checklist.md",
    "docs/privacy-policy.md",
    "docs/support.md",
    "docs/export-compliance.md",
    "docs/github-actions-troubleshooting.md",
    "docs/privacy-required-reasons.md",
    "docs/physical-device-validation.md",
    "docs/physical-device-validation-result-template.md",
    "docs/usability-testing/README.md",
    "docs/usability-testing/script.md",
    "docs/usability-testing/observation-template.md",
    "docs/usability-testing/first-round-result-template.md",
]:
    require_file(path)

require_text("docs/app-store-listing.md", r"Paid download", "listing states paid download")
require_text("docs/app-store-listing.md", r"No ads", "listing states no ads")
require_text("docs/app-store-listing.md", r"No account", "listing states no account")
require_text("docs/app-store-listing.md", r"No in-app purchases", "listing states no IAP")
require_text("docs/app-store-listing.md", r"Data collected: None", "listing states no collected data")
require_text("docs/app-store-connect-handoff.md", r"Commercial model: paid download", "handoff states paid download model")
require_text("docs/app-store-connect-handoff.md", r"Data collected: none", "handoff states no collected data")
require_text("docs/app-store-connect-handoff.md", r"ITSAppUsesNonExemptEncryption=false", "handoff covers export compliance")
require_text("docs/app-store-submission-runbook.md", r"check-github-actions-execution\.sh", "submission runbook points to Actions diagnostics")
require_text("docs/app-store-submission-runbook.md", r"prepare-submission-gate-status\.sh", "submission runbook points to submission gate status report")
require_text("docs/app-store-submission-runbook.md", r"validate-completed-release-results\.sh", "submission runbook points to completed result validation")
require_text("docs/app-store-submission-runbook.md", r"prepare-submission-owner-handoff\.sh", "submission runbook points to owner handoff")
require_text("scripts/verify-public-pages.sh", r"gist\.githubusercontent\.com/.*/raw/privacy-policy\.md", "public page verifier uses stable privacy raw file URL")
require_text("scripts/verify-public-pages.sh", r"gist\.githubusercontent\.com/.*/raw/support\.md", "public page verifier uses stable support raw file URL")
require_text("docs/github-actions-troubleshooting.md", r"steps: \[\]", "Actions troubleshooting documents zero-step blocker")
require_text("docs/github-actions-troubleshooting.md", r"Budgets and alerts", "Actions troubleshooting covers budget checks")
require_text("docs/privacy-policy.md", r"HTML Previewer does not collect personal data", "privacy policy states no personal data collection")
require_text("docs/support.md", r"HTML Previewer Support", "support page is present")
require_text("docs/usability-testing/README.md", r"prepare-usability-session-run\.sh", "usability README points to the session run helper")
require_text("docs/usability-testing/first-round-result-template.md", r"Do not store the participant's real name", "usability template avoids direct participant identifiers")

print("\n== Sample Packages ==")
for path in [
    "docs/usability-testing/samples/basic-report.html",
    "docs/usability-testing/samples/legacy-report.htm",
    "docs/usability-testing/samples/markdown-notes.md",
    "docs/usability-testing/samples/markdown-reference.markdown",
    "docs/usability-testing/samples/external-resource.html",
    "docs/usability-testing/samples/interactive-trusted.html",
    "docs/usability-testing/samples/zip-report.zip",
    "docs/usability-testing/samples/broken.zip",
]:
    require_file(path)

sample_dir = root / "docs/usability-testing/samples"
found_extensions = {path.suffix.lower() for path in sample_dir.iterdir() if path.is_file()}
missing_extensions = sorted({".html", ".htm", ".md", ".markdown", ".zip"} - found_extensions)
if missing_extensions:
    fail("external-open samples missing extensions: " + ", ".join(missing_extensions))
else:
    ok("external-open sample files cover html, htm, md, markdown, and zip")

require_zip_entries(
    "docs/usability-testing/samples/zip-report.zip",
    {
        "index.html",
        "assets/report.css",
        "assets/local-chart.svg",
    },
    "zip-report.zip contains expected report assets",
)

broken_zip = root / "docs/usability-testing/samples/broken.zip"
if broken_zip.is_file():
    try:
        with zipfile.ZipFile(broken_zip) as archive:
            archive.testzip()
        fail("broken.zip should remain intentionally invalid")
    except zipfile.BadZipFile:
        ok("broken.zip remains intentionally invalid")

print("\n== Source Absence Checks ==")
source_text = ""
for path in list((root / "HTMLMarkdownPreviewer").rglob("*")) + [root / "project.yml"]:
    if path.is_file():
        try:
            source_text += path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            pass
for pattern in ["StoreKit", "SKPayment", "InAppPurchase", "AdMob", "FirebaseAnalytics", "Sign in with Apple", "ASAuthorization"]:
    if pattern in source_text:
        fail(f"release build should not contain {pattern} references")
if not any(pattern in source_text for pattern in ["StoreKit", "SKPayment", "InAppPurchase", "AdMob", "FirebaseAnalytics", "Sign in with Apple", "ASAuthorization"]):
    ok("no StoreKit, account, analytics, or ad SDK references found")

if failures:
    print(f"\nPortable release materials audit failed with {len(failures)} issue(s).", file=sys.stderr)
    raise SystemExit(1)

print("\nPortable release materials audit passed.")
PY
