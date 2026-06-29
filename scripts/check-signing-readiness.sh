#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT_DIR/DerivedData/SigningReadiness}"
DRY_RUN=false
FAIL_ON_NOT_READY=false

usage() {
  cat <<'EOF'
Usage: [DEVELOPMENT_TEAM=<Apple Team ID>] scripts/check-signing-readiness.sh [options]

Writes a signing readiness report that separates local development-signing
evidence from App Store/TestFlight distribution readiness.

Environment:
  DEVELOPMENT_TEAM  Optional Apple Developer Team ID to validate.
  BUNDLE_ID         Optional bundle id override; defaults to Info.plist.
  OUTPUT_ROOT       Optional report root; defaults to DerivedData/SigningReadiness.

Options:
  --fail-on-not-ready  Exit 1 unless App Store/TestFlight signing readiness is ready.
  --dry-run            Print planned report path without writing files.
  -h, --help           Show this help.
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --fail-on-not-ready)
      FAIL_ON_NOT_READY=true
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

timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
RUN_DIR="$OUTPUT_ROOT/$timestamp-signing-readiness"
REPORT_PATH="$RUN_DIR/signing-readiness-report.md"

if [[ "$DRY_RUN" == true ]]; then
  printf 'Would prepare signing readiness report:\n'
  printf -- '- Report: %s\n' "$REPORT_PATH"
  printf -- '- Bundle id: %s\n' "${BUNDLE_ID:-from HTMLMarkdownPreviewer/Info.plist}"
  printf -- '- Development team: %s\n' "${DEVELOPMENT_TEAM:-infer from Apple Distribution identity if unique}"
  exit 0
fi

mkdir -p "$RUN_DIR"

python3 - "$ROOT_DIR" "$REPORT_PATH" <<'PY'
import datetime as dt
import os
import pathlib
import plistlib
import re
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
report_path = pathlib.Path(sys.argv[2])
requested_team = os.environ.get("DEVELOPMENT_TEAM", "").strip()
bundle_override = os.environ.get("BUNDLE_ID", "").strip()
profile_root = pathlib.Path.home() / "Library" / "MobileDevice" / "Provisioning Profiles"


def run(command):
    return subprocess.run(
        command,
        cwd=root,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=False,
    )


def run_text(command):
    result = run(command)
    output = result.stdout + result.stderr
    return result.returncode, output.decode("utf-8", errors="replace")


def git_value(*args):
    code, output = run_text(["git", *args])
    if code == 0:
        value = output.strip()
        return value if value else "unknown"
    return "unknown"


def working_tree_state():
    code, output = run_text(["git", "status", "--porcelain"])
    if code != 0:
        return "unknown"
    return "dirty" if output.strip() else "clean"


def plist(path):
    with path.open("rb") as handle:
        return plistlib.load(handle)


def field_value(path, label):
    if not path or not path.exists():
        return ""
    prefix = f"- {label}: "
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith(prefix):
            return line[len(prefix) :].strip()
    return ""


def project_bundle_id():
    for path in [root / "project.yml", root / "HTMLMarkdownPreviewer.xcodeproj" / "project.pbxproj"]:
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        match = re.search(r"PRODUCT_BUNDLE_IDENTIFIER[: =]+([A-Za-z0-9_.-]+)", text)
        if match:
            return match.group(1).rstrip(";")
    return ""


def md_escape(value):
    return str(value).replace("|", "\\|").replace("\n", " ")


def bool_text(value):
    return "yes" if value else "no"


def parse_identity_output(text):
    identities = []
    pattern = re.compile(r'^\s*\d+\)\s+([0-9A-F]+)\s+"([^"]+)"')
    team_pattern = re.compile(r"\(([A-Z0-9]+)\)$")
    for line in text.splitlines():
        match = pattern.match(line)
        if not match:
            continue
        fingerprint, name = match.groups()
        team_match = team_pattern.search(name)
        team_id = team_match.group(1) if team_match else ""
        if name.startswith("Apple Distribution:"):
            kind = "Apple Distribution"
        elif name.startswith("Apple Development:"):
            kind = "Apple Development"
        elif name.startswith("Developer ID Application:"):
            kind = "Developer ID Application"
        else:
            kind = "Other"
        identities.append(
            {
                "fingerprint": fingerprint,
                "name": name,
                "team_id": team_id,
                "kind": kind,
            }
        )
    return identities


def profile_type(profile):
    entitlements = profile.get("Entitlements", {})
    if entitlements.get("get-task-allow") is True:
        return "Development"
    if profile.get("ProvisionsAllDevices") is True:
        return "Enterprise"
    if profile.get("ProvisionedDevices"):
        return "Ad Hoc"
    if entitlements.get("get-task-allow") is False:
        return "App Store"
    return "Unknown"


def app_id_suffix(profile):
    app_identifier = profile.get("Entitlements", {}).get("application-identifier", "")
    if "." not in app_identifier:
        return app_identifier
    return app_identifier.split(".", 1)[1]


def matches_bundle(suffix, bundle_id):
    if suffix == bundle_id:
        return "explicit"
    if suffix.endswith(".*") and bundle_id.startswith(suffix[:-1]):
        return "wildcard"
    return "no"


def decode_profiles(bundle_id, selected_team):
    profiles = []
    if not profile_root.is_dir():
        return profiles
    for path in sorted(profile_root.glob("*.mobileprovision")):
        result = run(["security", "cms", "-D", "-i", str(path)])
        record = {
            "path": path,
            "decode_error": "",
            "name": path.name,
            "uuid": "",
            "team_ids": [],
            "app_id": "",
            "match": "no",
            "type": "Unknown",
            "expired": True,
            "expires": "",
            "team_match": False,
        }
        if result.returncode != 0:
            record["decode_error"] = (result.stderr or result.stdout).decode("utf-8", errors="replace").strip()
            profiles.append(record)
            continue
        try:
            profile = plistlib.loads(result.stdout)
        except Exception as exc:  # pragma: no cover - defensive for malformed local profiles
            record["decode_error"] = str(exc)
            profiles.append(record)
            continue
        expires = profile.get("ExpirationDate")
        if isinstance(expires, dt.datetime):
            now = dt.datetime.now(dt.UTC).replace(tzinfo=None)
            record["expired"] = expires.replace(tzinfo=None) <= now
            record["expires"] = expires.replace(tzinfo=None).isoformat(timespec="seconds") + "Z"
        else:
            record["expired"] = True
            record["expires"] = "unknown"
        team_ids = [str(value) for value in profile.get("TeamIdentifier", [])]
        suffix = app_id_suffix(profile)
        record.update(
            {
                "name": str(profile.get("Name") or path.name),
                "uuid": str(profile.get("UUID") or ""),
                "team_ids": team_ids,
                "app_id": suffix,
                "match": matches_bundle(suffix, bundle_id),
                "type": profile_type(profile),
                "team_match": bool(selected_team and selected_team in team_ids),
            }
        )
        profiles.append(record)
    return profiles


info_path = root / "HTMLMarkdownPreviewer" / "Info.plist"
try:
    bundle_id = bundle_override or plist(info_path).get("CFBundleIdentifier", "")
except Exception:
    bundle_id = bundle_override or "unknown"
if not bundle_override and (not bundle_id or "$(" in bundle_id):
    bundle_id = project_bundle_id() or bundle_id or "unknown"

_, xcode_version = run_text(["xcodebuild", "-version"])
identity_exit, identity_output = run_text(["security", "find-identity", "-p", "codesigning", "-v"])
identities = parse_identity_output(identity_output if identity_exit == 0 else "")
identity_team_ids = sorted({item["team_id"] for item in identities if item["team_id"]})
distribution_team_ids = sorted({item["team_id"] for item in identities if item["kind"] == "Apple Distribution" and item["team_id"]})

if requested_team:
    selected_team = requested_team
    selected_team_source = "DEVELOPMENT_TEAM"
elif len(distribution_team_ids) == 1:
    selected_team = distribution_team_ids[0]
    selected_team_source = "inferred from unique Apple Distribution identity"
else:
    selected_team = ""
    selected_team_source = "not available"

profiles = decode_profiles(bundle_id, selected_team)
distribution_identity_ready = bool(
    selected_team and any(item["kind"] == "Apple Distribution" and item["team_id"] == selected_team for item in identities)
)
development_identity_available = any(item["kind"] == "Apple Development" for item in identities)
selected_development_identity_ready = bool(
    selected_team and any(item["kind"] == "Apple Development" and item["team_id"] == selected_team for item in identities)
)
team_matches_identity = bool(selected_team and selected_team in identity_team_ids)
matching_app_store_profiles = [
    item
    for item in profiles
    if item["team_match"]
    and item["match"] == "explicit"
    and item["type"] == "App Store"
    and not item["expired"]
    and not item["decode_error"]
]
matching_development_profiles = [
    item
    for item in profiles
    if item["team_match"]
    and item["match"] in {"explicit", "wildcard"}
    and item["type"] == "Development"
    and not item["expired"]
    and not item["decode_error"]
]

latest_signed_diagnostic = None
signed_reports_root = root / "DerivedData" / "SignedArchiveDiagnostics"
if signed_reports_root.is_dir():
    signed_reports = sorted(signed_reports_root.glob("**/signed-archive-diagnostic-report.md"))
    if signed_reports:
        latest_signed_diagnostic = signed_reports[-1]

latest_signed_status = field_value(latest_signed_diagnostic, "Status")
latest_signed_team = field_value(latest_signed_diagnostic, "Development team")
latest_signed_dev_allowed = field_value(latest_signed_diagnostic, "Allow development signing")
latest_signed_submission = field_value(latest_signed_diagnostic, "App Store/TestFlight submission evidence")
latest_signed_summary = field_value(latest_signed_diagnostic, "Summary")

local_smoke_ready = "blocked"
if latest_signed_status == "passed" and latest_signed_dev_allowed == "YES" and latest_signed_submission == "no":
    local_smoke_ready = "ready"
elif development_identity_available or matching_development_profiles:
    local_smoke_ready = "conditional"

findings = []
if not selected_team:
    findings.append("No requested or inferable Apple Distribution team id. Set DEVELOPMENT_TEAM explicitly.")
elif requested_team and not team_matches_identity:
    findings.append(
        "Requested team id does not match any installed signing identity. "
        + (
            f"Available identity team ids: {', '.join(identity_team_ids)}."
            if identity_team_ids
            else "No signing identity team ids were found."
        )
    )
if selected_team and not distribution_identity_ready:
    findings.append(f"No Apple Distribution identity is installed for team {selected_team}.")
if not profiles:
    findings.append("No provisioning profiles are installed under ~/Library/MobileDevice/Provisioning Profiles.")
elif selected_team and not matching_app_store_profiles:
    findings.append(
        f"No non-expired explicit App Store provisioning profile matches bundle id {bundle_id} for team {selected_team}."
    )
if latest_signed_status == "passed" and latest_signed_submission == "no":
    findings.append("Latest signed archive is development-signed local smoke evidence, not App Store/TestFlight upload evidence.")

distribution_ready = bool(selected_team and distribution_identity_ready and matching_app_store_profiles)
status = "ready" if distribution_ready else "blocked"
summary = (
    f"App Store/TestFlight signing is ready for team {selected_team}."
    if distribution_ready
    else "App Store/TestFlight signing is not ready; see blocking findings."
)

with report_path.open("w", encoding="utf-8") as handle:
    handle.write("# Signing Readiness Report\n\n")
    handle.write(f"- Status: {status}\n")
    handle.write(f"- Generated: {dt.datetime.now(dt.UTC).replace(tzinfo=None, microsecond=0).isoformat()}Z\n")
    handle.write(f"- Branch: {git_value('branch', '--show-current')}\n")
    handle.write(f"- Commit: {git_value('rev-parse', '--short', 'HEAD')}\n")
    handle.write(f"- Full commit: {git_value('rev-parse', 'HEAD')}\n")
    handle.write(f"- Working tree: {working_tree_state()}\n")
    handle.write(f"- Summary: {summary}\n")
    handle.write(f"- Bundle id: {bundle_id}\n")
    handle.write(f"- Requested development team: {requested_team or 'not set'}\n")
    handle.write(f"- Effective development team: {selected_team or 'not available'}\n")
    handle.write(f"- Effective team source: {selected_team_source}\n")
    handle.write(f"- Installed signing identity count: {len(identities)}\n")
    handle.write(f"- Installed provisioning profile count: {len(profiles)}\n")
    handle.write(f"- Apple Distribution identity available: {bool_text(distribution_identity_ready)}\n")
    handle.write(f"- Apple Development identity available: {bool_text(development_identity_available)}\n")
    handle.write(f"- Matching App Store provisioning profile: {bool_text(bool(matching_app_store_profiles))}\n")
    handle.write(f"- Matching development provisioning profile: {bool_text(bool(matching_development_profiles))}\n")
    handle.write(f"- Local device smoke readiness: {local_smoke_ready}\n")
    handle.write(f"- App Store/TestFlight archive readiness: {'ready' if distribution_ready else 'blocked'}\n")
    handle.write(f"- Latest signed archive diagnostic: {latest_signed_diagnostic or 'not generated'}\n")
    handle.write(f"- Latest signed archive status: {latest_signed_status or 'not generated'}\n")
    handle.write(f"- Latest signed archive App Store/TestFlight submission evidence: {latest_signed_submission or 'not recorded'}\n")

    handle.write("\n## Blocking Findings\n\n")
    if findings:
        for finding in findings:
            handle.write(f"- {finding}\n")
    else:
        handle.write("- None\n")

    handle.write("\n## Signing Identities\n\n")
    if identities:
        handle.write("| Type | Team ID | Name |\n")
        handle.write("|---|---|---|\n")
        for identity in identities:
            handle.write(
                f"| {md_escape(identity['kind'])} | {md_escape(identity['team_id'] or 'unknown')} | {md_escape(identity['name'])} |\n"
            )
    else:
        handle.write("- No valid code signing identities were reported by `security find-identity -p codesigning -v`.\n")

    handle.write("\n## Provisioning Profiles\n\n")
    if profiles:
        handle.write("| Name | Team IDs | App ID | Type | Match | Expires | Ready Note |\n")
        handle.write("|---|---|---|---|---|---|---|\n")
        for profile in profiles:
            if profile["decode_error"]:
                note = "decode failed"
            elif profile["expired"]:
                note = "expired"
            elif profile["team_match"] and profile["match"] == "explicit" and profile["type"] == "App Store":
                note = "distribution-ready"
            elif profile["team_match"] and profile["match"] in {"explicit", "wildcard"}:
                note = "matches bundle but not App Store distribution"
            else:
                note = "not a matching distribution profile"
            handle.write(
                "| "
                + " | ".join(
                    [
                        md_escape(profile["name"]),
                        md_escape(", ".join(profile["team_ids"]) or "unknown"),
                        md_escape(profile["app_id"] or "unknown"),
                        md_escape(profile["type"]),
                        md_escape(profile["match"]),
                        md_escape(profile["expires"]),
                        md_escape(note),
                    ]
                )
                + " |\n"
            )
    else:
        handle.write(f"- No `.mobileprovision` files found in `{profile_root}`.\n")

    handle.write("\n## Latest Signed Archive Diagnostic\n\n")
    if latest_signed_diagnostic:
        handle.write(f"- Report: `{latest_signed_diagnostic}`\n")
        handle.write(f"- Status: {latest_signed_status or 'unknown'}\n")
        handle.write(f"- Development team: {latest_signed_team or 'unknown'}\n")
        handle.write(f"- Allow development signing: {latest_signed_dev_allowed or 'unknown'}\n")
        handle.write(f"- App Store/TestFlight submission evidence: {latest_signed_submission or 'unknown'}\n")
        handle.write(f"- Summary: {latest_signed_summary or 'unknown'}\n")
    else:
        handle.write("- No signed archive diagnostic has been generated yet.\n")

    handle.write("\n## Xcode\n\n")
    handle.write("```text\n")
    handle.write(xcode_version.strip() or "unknown")
    handle.write("\n```\n")

    handle.write("\n## Next Actions\n\n")
    if distribution_ready:
        handle.write(
            f"- Run `DEVELOPMENT_TEAM={selected_team} scripts/create-signed-archive.sh` without `ALLOW_DEVELOPMENT_SIGNING=YES`, then upload or select the processed build.\n"
        )
    else:
        if selected_team:
            handle.write(
                f"- In Xcode Accounts/App Store Connect, install or create an explicit App Store provisioning profile for `{bundle_id}` under team `{selected_team}`.\n"
            )
            handle.write(
                f"- Re-run `DEVELOPMENT_TEAM={selected_team} scripts/check-signing-readiness.sh --fail-on-not-ready` before creating upload evidence.\n"
            )
        else:
            handle.write("- Set `DEVELOPMENT_TEAM=<Apple Team ID>` and rerun this script.\n")
        handle.write("- Use `ALLOW_DEVELOPMENT_SIGNING=YES` only for local physical-device smoke evidence.\n")

print(f"Prepared signing readiness report: {report_path}")
print(f"Signing readiness status: {status}")
PY

status="$(awk -F': ' '/^- Status: / { print $2; exit }' "$REPORT_PATH")"
if [[ "$FAIL_ON_NOT_READY" == true && "$status" != "ready" ]]; then
  exit 1
fi
