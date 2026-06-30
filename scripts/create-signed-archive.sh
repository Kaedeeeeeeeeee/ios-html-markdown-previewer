#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/DerivedData/SignedArchive/HTMLPreviewer.xcarchive}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT_DIR/DerivedData/SignedArchiveDiagnostics}"
CODE_SIGN_STYLE="${CODE_SIGN_STYLE:-}"
ALLOW_PROVISIONING_UPDATES="${ALLOW_PROVISIONING_UPDATES:-YES}"
ALLOW_DEVELOPMENT_SIGNING="${ALLOW_DEVELOPMENT_SIGNING:-NO}"
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: DEVELOPMENT_TEAM=<Apple Team ID> scripts/create-signed-archive.sh [--dry-run]

Creates a signed Release archive for App Store Connect/TestFlight handoff.

Environment:
  DEVELOPMENT_TEAM                 Required Apple Developer Team ID.
  ARCHIVE_PATH                     Optional .xcarchive output path.
  OUTPUT_ROOT                      Optional diagnostic output root.
  CODE_SIGN_STYLE                  Optional signing style override. Defaults to
                                   the project target settings.
  CODE_SIGN_IDENTITY               Optional signing identity override.
  PROVISIONING_PROFILE_SPECIFIER   Optional profile name for manual signing.
  ALLOW_PROVISIONING_UPDATES       YES or NO, defaults to YES.
  ALLOW_DEVELOPMENT_SIGNING        YES or NO, defaults to NO. Set YES only for
                                   local device smoke archives that are not
                                   App Store/TestFlight submission evidence.

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

case "$ALLOW_DEVELOPMENT_SIGNING" in
  YES|NO)
    ;;
  *)
    printf 'ALLOW_DEVELOPMENT_SIGNING must be YES or NO, found %s\n' "$ALLOW_DEVELOPMENT_SIGNING" >&2
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
  CODE_SIGNING_ALLOWED=YES
)

if [[ -n "${CODE_SIGN_STYLE:-}" ]]; then
  cmd+=("CODE_SIGN_STYLE=$CODE_SIGN_STYLE")
fi

if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
  cmd+=("CODE_SIGN_IDENTITY=$CODE_SIGN_IDENTITY")
fi

if [[ -n "${PROVISIONING_PROFILE_SPECIFIER:-}" ]]; then
  cmd+=("PROVISIONING_PROFILE_SPECIFIER=$PROVISIONING_PROFILE_SPECIFIER")
fi

if [[ "$ALLOW_PROVISIONING_UPDATES" == "YES" ]]; then
  cmd+=(-allowProvisioningUpdates)
fi

git_value() {
  git -C "$ROOT_DIR" "$@" 2>/dev/null || printf 'unknown'
}

working_tree_state() {
  if [[ -n "$(git -C "$ROOT_DIR" status --porcelain 2>/dev/null || true)" ]]; then
    printf 'dirty'
  else
    printf 'clean'
  fi
}

write_archive_diagnostic() {
  local status="$1"
  local exit_code="$2"
  local summary="$3"
  local error_summary=""
  local submission_evidence="no"
  local evidence_note="This diagnostic records signing/archive readiness only; a successful Apple Distribution archive or processed TestFlight build is still required for submission evidence."

  if [[ -f "$build_log" ]]; then
    error_summary="$(grep -E "error:|No Accounts|No profiles|Provisioning profile|Signing|CodeSign" "$build_log" | tail -n 30 || true)"
  fi
  if [[ "$status" == "passed" && "$ALLOW_DEVELOPMENT_SIGNING" == "NO" ]]; then
    submission_evidence="yes"
    evidence_note="Archive passed Apple Distribution signing validation; upload/select the processed build and run final smoke before submission."
  elif [[ "$status" == "passed" ]]; then
    evidence_note="Archive passed development-signing validation for local device smoke only; it is not App Store/TestFlight upload evidence."
  fi

  {
    printf '# Signed Archive Diagnostic Report\n\n'
    printf -- '- Status: %s\n' "$status"
    printf -- '- Generated: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf -- '- Branch: %s\n' "$(git_value branch --show-current)"
    printf -- '- Commit: %s\n' "$(git_value rev-parse --short HEAD)"
    printf -- '- Full commit: %s\n' "$(git_value rev-parse HEAD)"
    printf -- '- Working tree: %s\n' "$(working_tree_state)"
    printf -- '- Summary: %s\n' "$summary"
    printf -- '- Exit code: %s\n' "$exit_code"
    printf -- '- Archive path: %s\n' "$ARCHIVE_PATH"
    printf -- '- Development team: %s\n' "$DEVELOPMENT_TEAM"
    printf -- '- Code sign style: %s\n' "${CODE_SIGN_STYLE:-project settings}"
    printf -- '- Allow provisioning updates: %s\n' "$ALLOW_PROVISIONING_UPDATES"
    printf -- '- Allow development signing: %s\n' "$ALLOW_DEVELOPMENT_SIGNING"
    printf -- '- App Store/TestFlight submission evidence: %s\n' "$submission_evidence"
    printf -- '- Evidence note: %s\n' "$evidence_note"
    printf -- '- Build log: %s\n' "$build_log"
    printf '\n## Command\n\n```sh\n'
    printf '%q ' "${cmd[@]}"
    printf '\n```\n'
    printf '\n## Error Summary\n\n'
    if [[ -n "$error_summary" ]]; then
      printf '```text\n%s\n```\n' "$error_summary"
    else
      printf -- '- No matching signing/archive error lines were captured.\n'
    fi
  } >"$report_path"
}

if [[ "$DRY_RUN" == true ]]; then
  printf 'Dry run signed archive command:\n'
  printf '%q ' "${cmd[@]}"
  printf '\n'
  exit 0
fi

timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
run_dir="$OUTPUT_ROOT/$timestamp-signed-archive"
build_log="$run_dir/xcodebuild-archive.log"
report_path="$run_dir/signed-archive-diagnostic-report.md"
mkdir -p "$run_dir"

rm -rf "$ARCHIVE_PATH"
set +e
"${cmd[@]}" 2>&1 | tee "$build_log"
archive_exit="${PIPESTATUS[0]}"
set -e

if [[ "$archive_exit" -ne 0 ]]; then
  write_archive_diagnostic "failed" "$archive_exit" "xcodebuild archive failed"
  printf 'Signed archive diagnostic report: %s\n' "$report_path" >&2
  exit "$archive_exit"
fi

APP_PATH="$ARCHIVE_PATH/Products/Applications/HTMLMarkdownPreviewer.app"

set +e
codesign --verify --strict "$APP_PATH"
codesign_exit="$?"
set -e

if [[ "$codesign_exit" -ne 0 ]]; then
  write_archive_diagnostic "failed" "$codesign_exit" "codesign verification failed"
  printf 'Signed archive diagnostic report: %s\n' "$report_path" >&2
  exit "$codesign_exit"
fi

set +e
python3 - "$ARCHIVE_PATH" "$APP_PATH" <<'PY'
import os
import plistlib
import subprocess
import sys

archive_path = sys.argv[1]
app_path = sys.argv[2]
allow_development_signing = os.environ.get("ALLOW_DEVELOPMENT_SIGNING") == "YES"
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
    profile_result = subprocess.run(
        ["security", "cms", "-D", "-i", profile_path],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if profile_result.returncode != 0:
        errors.append("embedded provisioning profile could not be decoded")
        profile = {}
    else:
        profile = plistlib.loads(profile_result.stdout)
    codesign_result = subprocess.run(
        ["codesign", "-dvvv", app_path],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    codesign_details = codesign_result.stdout + codesign_result.stderr

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

    if not allow_development_signing:
        entitlements = profile.get("Entitlements", {})
        profile_name = profile.get("Name", "")
        app_identifier = entitlements.get("application-identifier", "")

        if "Authority=Apple Development" in codesign_details:
            errors.append("App Store/TestFlight archive must not be signed with Apple Development")
        if "Authority=Apple Distribution" not in codesign_details:
            errors.append("App Store/TestFlight archive must be signed with Apple Distribution")
        if entitlements.get("get-task-allow") is not False:
            errors.append("App Store/TestFlight provisioning profile must set get-task-allow=false")
        if profile.get("ProvisionedDevices"):
            errors.append("App Store/TestFlight provisioning profile must not be device-limited")
        if profile.get("ProvisionsAllDevices") is True:
            errors.append("App Store/TestFlight archive must not use an enterprise provisioning profile")
        if app_identifier.endswith(".*"):
            errors.append("App Store/TestFlight provisioning profile must use an explicit app identifier")
        if profile_name.startswith("iOS Team Provisioning Profile"):
            errors.append("App Store/TestFlight archive must not use an iOS Team Provisioning Profile")

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)
PY
validation_exit="$?"
set -e

if [[ "$validation_exit" -ne 0 ]]; then
  write_archive_diagnostic "failed" "$validation_exit" "archive signing validation failed"
  printf 'Signed archive diagnostic report: %s\n' "$report_path" >&2
  exit "$validation_exit"
fi

write_archive_diagnostic "passed" 0 "Archive created and signing validation passed"

if [[ "$ALLOW_DEVELOPMENT_SIGNING" == "YES" ]]; then
  printf 'Development-signed archive created and validated for local device smoke only: %s\n' "$ARCHIVE_PATH"
  printf 'This archive is not App Store/TestFlight submission evidence. Re-run without ALLOW_DEVELOPMENT_SIGNING=YES for upload readiness.\n'
else
  printf 'Distribution-signed archive created and validated: %s\n' "$ARCHIVE_PATH"
  printf 'Next: upload it through Xcode Organizer or App Store Connect tooling, then run the final archive/TestFlight smoke test.\n'
fi
printf 'Signed archive diagnostic report: %s\n' "$report_path"
