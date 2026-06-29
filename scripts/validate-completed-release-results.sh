#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT_DIR/DerivedData/CompletedReleaseResultsValidation}"
REPORT_PATH="$OUTPUT_ROOT/completed-release-results-validation.md"
FAIL_ON_INVALID=false
FAIL_ON_INCOMPLETE=false
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: scripts/validate-completed-release-results.sh [options]

Validates the latest manually completed release result drafts for #1, #10, and
#11. By default this writes a report and exits 0 even when results are still
missing or draft-only. Use strict flags when every manual gate is expected to be
complete.

Options:
  --fail-on-invalid     Exit 1 if a result is marked complete but still has
                        placeholders, empty required result cells, stale commit
                        evidence, or unresolved P0/P1 follow-up rows.
  --fail-on-incomplete  Exit 1 unless every tracked manual result is complete
                        and valid. Implies --fail-on-invalid.
  --dry-run             Print planned report path without writing files.
  -h, --help            Show this help.
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --fail-on-invalid)
      FAIL_ON_INVALID=true
      shift
      ;;
    --fail-on-incomplete)
      FAIL_ON_INCOMPLETE=true
      FAIL_ON_INVALID=true
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

if [[ "$DRY_RUN" == true ]]; then
  printf 'Would validate completed release results:\n'
  printf -- '- Report: %s\n' "$REPORT_PATH"
  printf -- '- Strict invalid check: %s\n' "$FAIL_ON_INVALID"
  printf -- '- Strict completeness check: %s\n' "$FAIL_ON_INCOMPLETE"
  exit 0
fi

python3 - "$ROOT_DIR" "$REPORT_PATH" "$FAIL_ON_INVALID" "$FAIL_ON_INCOMPLETE" <<'PY'
import datetime as _dt
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
report_path = pathlib.Path(sys.argv[2])
fail_on_invalid = sys.argv[3] == "true"
fail_on_incomplete = sys.argv[4] == "true"


def git_value(*args):
    try:
        return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()
    except Exception:
        return "unknown"


def latest_file(search_root, filename):
    base = root / search_root
    if not base.is_dir():
        return None
    matches = sorted(base.glob(f"**/{filename}"))
    return matches[-1] if matches else None


def md_escape(value):
    return str(value).replace("|", "\\|").replace("\n", "<br>")


def rel_path(path):
    if not path:
        return "not generated"
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def normalize(value):
    return re.sub(r"\s+", " ", value.strip().lower())


def report_field(text, label):
    prefix = f"- {label}:"
    for line in text.splitlines():
        if line.startswith(prefix):
            return line[len(prefix):].strip()
    return ""


def report_commit(text):
    full = report_field(text, "Full commit")
    if full:
        return full
    match = re.search(r"^- Commit:\s*[0-9a-fA-F]{7,}\s*\(([0-9a-fA-F]{40})\)", text, re.MULTILINE)
    if match:
        return match.group(1)
    value = report_field(text, "Commit")
    return value.split()[0] if value else ""


def commit_check(path, text, current_full, current_short):
    evidence = report_commit(text)
    if not evidence:
        return "commit not recorded", False
    if evidence in {current_full, current_short} or current_full.startswith(evidence):
        return f"matches current commit ({current_short})", True
    return f"stale: evidence commit {evidence[:7]} does not match current {current_short}", False


def table_rows_by_section(text):
    sections = {}
    current = "document"
    for line in text.splitlines():
        heading = re.match(r"^##\s+(.+?)\s*$", line)
        if heading:
            current = heading.group(1).strip()
            sections.setdefault(current, [])
            continue
        sections.setdefault(current, []).append(line)
    return sections


def parse_tables(lines):
    tables = []
    active = []
    for line in lines + [""]:
        if line.strip().startswith("|") and line.strip().endswith("|"):
            active.append(line.strip())
        else:
            if len(active) >= 2:
                tables.append(active)
            active = []
    return tables


def split_row(row):
    return [cell.strip() for cell in row.strip().strip("|").split("|")]


def placeholderish(value):
    lowered = normalize(value).strip("`")
    if not lowered:
        return True
    placeholders = {
        "tbd",
        "pending / passed / failed",
        "yes / no",
        "yes/no",
        "p0/p1/p2",
        "pass/fail",
        "xcode run / local archive / testflight",
        "signed archive / testflight",
        "wi-fi / cellular / offline",
    }
    if lowered in placeholders:
        return True
    return "tbd" in lowered


def completion_status(text, expectations):
    values = {label: report_field(text, label) for label, _expected in expectations}
    normalized = {label: normalize(value) for label, value in values.items()}
    complete = all(normalized.get(label) == expected for label, expected in expectations)
    failed_values = []
    for label, value in normalized.items():
        if value in {"failed", "fail", "no"}:
            failed_values.append(label)
    if complete:
        return "complete", values
    if failed_values:
        return "failed", values
    return "draft", values


def unresolved_field_notes(text, field_labels):
    notes = []
    for label in field_labels:
        value = report_field(text, label)
        if placeholderish(value):
            notes.append(f"{label} is unresolved")
    return notes


def validate_tables(text, spec):
    notes = []
    sections = table_rows_by_section(text)
    for section, rules in spec.items():
        lines = sections.get(section, [])
        for table in parse_tables(lines):
            headers = split_row(table[0])
            body_rows = table[2:]
            if not headers or not body_rows:
                continue
            for row in body_rows:
                cells = split_row(row)
                if not any(cell.strip() for cell in cells):
                    continue
                first = normalize(cells[0]) if cells else ""
                if first == "p0/p1/p2":
                    notes.append(f"{section} still contains the P0/P1/P2 placeholder row")
                    continue
                for header_pattern, required_values in rules:
                    for index, header in enumerate(headers):
                        if re.search(header_pattern, header, re.IGNORECASE):
                            value = cells[index] if index < len(cells) else ""
                            if placeholderish(value):
                                notes.append(f"{section} row '{cells[0]}' has unresolved {header}")
                            elif required_values and normalize(value) not in required_values:
                                allowed = ", ".join(sorted(required_values))
                                notes.append(f"{section} row '{cells[0]}' has unsupported {header}: {value} (expected {allowed})")
    return notes


def p0_p1_followup_notes(text, section_names):
    notes = []
    sections = table_rows_by_section(text)
    for section in section_names:
        for table in parse_tables(sections.get(section, [])):
            headers = [normalize(cell) for cell in split_row(table[0])]
            if "priority" not in headers:
                continue
            try:
                priority_index = headers.index("priority")
            except ValueError:
                continue
            followup_index = None
            for index, header in enumerate(headers):
                if "follow-up" in header or "followup" in header:
                    followup_index = index
                    break
            for row in table[2:]:
                cells = split_row(row)
                if priority_index >= len(cells):
                    continue
                priority = normalize(cells[priority_index])
                if priority == "p0/p1/p2":
                    notes.append(f"{section} still contains the P0/P1/P2 placeholder row")
                    continue
                if priority in {"p0", "p1"}:
                    followup = cells[followup_index] if followup_index is not None and followup_index < len(cells) else ""
                    if placeholderish(followup) or normalize(followup) in {"none", "n/a", "na"}:
                        notes.append(f"{section} {priority.upper()} row is missing a follow-up issue")
    return notes


RESULTS = [
    {
        "name": "Physical-device external-open result",
        "issue": "#1",
        "root": "DerivedData/PhysicalDeviceValidationRun",
        "filename": "physical-device-validation-result.md",
        "expectations": [
            ("Overall status", "passed"),
            ("Can close #1", "yes"),
            ("Can continue App Store submission", "yes"),
        ],
        "required_fields": [
            "Date",
            "Tester",
            "Commit",
            "Build source",
            "App version",
            "Device",
            "iOS version",
            "Overall status",
            "Can close #1",
            "Can continue App Store submission",
        ],
        "table_spec": {
            "External Open Matrix": [(r"^\.(html|htm|md|markdown|zip)$", None)],
            "Import And Preview Checks": [(r"Pass/Fail", None)],
            "Safety And Error Path Checks": [(r"Pass/Fail", None)],
        },
        "p0_sections": ["Blocking Failures"],
    },
    {
        "name": "App Store Connect setup result",
        "issue": "#10",
        "root": "DerivedData/AppStoreConnectRun",
        "filename": "app-store-connect-result.md",
        "expectations": [
            ("Overall status", "passed"),
            ("Can continue final archive/TestFlight smoke", "yes"),
        ],
        "required_fields": [
            "Date",
            "Commit",
            "GitHub Actions run",
            "App Store Connect app id",
            "App Store Connect selected build",
            "Overall status",
            "Can continue final archive/TestFlight smoke",
            "Can submit for review",
        ],
        "table_spec": {
            "App Record": [(r"Entered value", None), (r"Pass/Fail", None)],
            "Pricing And Availability": [(r"Entered value", None), (r"Pass/Fail", None)],
            "Metadata And Review Notes": [(r"Pass/Fail", None)],
            "Screenshots": [(r"Accepted in App Store Connect", None)],
            "Privacy": [(r"Pass/Fail", None)],
            "Age Rating": [(r"Entered answer", None), (r"Pass/Fail", None)],
            "Export Compliance": [(r"Pass/Fail", None)],
            "Build Selection": [(r"Pass/Fail", None)],
        },
        "p0_sections": ["Blocking Submission Issues"],
    },
    {
        "name": "Final archive/TestFlight smoke result",
        "issue": "#10",
        "root": "DerivedData/FinalSmokeRun",
        "filename": "final-archive-smoke-result.md",
        "expectations": [
            ("Overall status", "passed"),
            ("Can submit for review", "yes"),
        ],
        "required_fields": [
            "Date",
            "Tester",
            "Commit",
            "GitHub Actions run",
            "Build source",
            "App Store Connect build",
            "Device",
            "iOS version",
            "Install method",
            "Overall status",
            "Can submit for review",
        ],
        "table_spec": {
            "Pre-Smoke Gates": [(r"Pass/Fail", None)],
            "App Launch And Built-In Samples": [(r"Pass/Fail", None)],
            "Settings And Release Claims": [(r"Pass/Fail", None)],
            "App Store Connect Checks": [(r"Pass/Fail", None)],
        },
        "p0_sections": ["Blocking Failures"],
    },
    {
        "name": "First external usability result",
        "issue": "#11",
        "root": "DerivedData/UsabilitySessionRun",
        "filename": "first-round-usability-result.md",
        "expectations": [
            ("All P0 findings filed or fixed", "yes"),
            ("All P1 findings filed or fixed", "yes"),
            ("Can close #11", "yes"),
            ("Can continue App Store submission", "yes"),
        ],
        "required_fields": [
            "Date",
            "Moderator",
            "Participant code",
            "Build source",
            "Commit",
            "Device",
            "iOS version",
            "All P0 findings filed or fixed",
            "All P1 findings filed or fixed",
            "Can close #11",
            "Can continue App Store submission",
        ],
        "table_spec": {
            "Setup Evidence": [(r"Pass/Fail", None)],
            "Task Results": [(r"Result", None)],
            "Source-App Notes": [(r"Result", None)],
        },
        "p0_sections": ["Findings"],
    },
]

current_short = git_value("rev-parse", "--short", "HEAD")
current_full = git_value("rev-parse", "HEAD")
branch = git_value("branch", "--show-current")
working_tree = "dirty" if git_value("status", "--porcelain") else "clean"

rows = []
complete_count = 0
invalid_count = 0
failed_count = 0
incomplete_count = 0

for spec in RESULTS:
    path = latest_file(spec["root"], spec["filename"])
    if not path or not path.is_file():
        rows.append({
            "name": spec["name"],
            "issue": spec["issue"],
            "status": "missing",
            "path": "not generated",
            "commit": "not available",
            "fields": "result file not found",
            "notes": "Generate the corresponding result draft before the manual run.",
        })
        incomplete_count += 1
        continue

    text = path.read_text(encoding="utf-8", errors="replace")
    status, field_values = completion_status(text, spec["expectations"])
    commit_note, commit_ok = commit_check(path, text, current_full, current_short)
    notes = []

    if status == "complete":
        notes.extend(unresolved_field_notes(text, spec["required_fields"]))
        notes.extend(validate_tables(text, spec["table_spec"]))
        notes.extend(p0_p1_followup_notes(text, spec["p0_sections"]))
        if not commit_ok:
            notes.append(commit_note)
        if notes:
            status = "invalid"
            invalid_count += 1
        else:
            complete_count += 1
    elif status == "failed":
        failed_count += 1
        notes.append("Result records a failing or negative close/continue field.")
    else:
        incomplete_count += 1
        placeholders = [label for label, value in field_values.items() if placeholderish(value)]
        if placeholders:
            notes.append("Still draft-only: " + ", ".join(placeholders))
        else:
            notes.append("Completion fields are not all passed/yes yet.")

    field_summary = "; ".join(f"{label}: {value or 'empty'}" for label, value in field_values.items())
    rows.append({
        "name": spec["name"],
        "issue": spec["issue"],
        "status": status,
        "path": rel_path(path),
        "commit": commit_note,
        "fields": field_summary,
        "notes": "; ".join(dict.fromkeys(notes)) if notes else "complete and internally consistent",
    })

if invalid_count:
    overall = "invalid"
elif complete_count == len(RESULTS):
    overall = "complete"
elif failed_count:
    overall = "failed"
else:
    overall = "incomplete"

report_path.parent.mkdir(parents=True, exist_ok=True)
generated = _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
with report_path.open("w", encoding="utf-8") as handle:
    handle.write("# Completed Release Results Validation\n\n")
    handle.write(f"- Status: {overall}\n")
    handle.write(f"- Generated: {generated}\n")
    handle.write(f"- Branch: {branch}\n")
    handle.write(f"- Commit: {current_short}\n")
    handle.write(f"- Full commit: {current_full}\n")
    handle.write(f"- Working tree: {working_tree}\n")
    handle.write(f"- Complete results: {complete_count}\n")
    handle.write(f"- Incomplete results: {incomplete_count}\n")
    handle.write(f"- Failed results: {failed_count}\n")
    handle.write(f"- Invalid completed results: {invalid_count}\n")
    handle.write("\n## Result Matrix\n\n")
    handle.write("| Result | Issue | Status | Path | Commit check | Completion fields | Validation notes |\n")
    handle.write("|---|---:|---|---|---|---|---|\n")
    for row in rows:
        handle.write(
            f"| {md_escape(row['name'])} | {md_escape(row['issue'])} | `{md_escape(row['status'])}` | "
            f"`{md_escape(row['path'])}` | {md_escape(row['commit'])} | {md_escape(row['fields'])} | "
            f"{md_escape(row['notes'])} |\n"
        )
    handle.write("\n## Status Semantics\n\n")
    handle.write("- `complete`: all close/continue fields are affirmative, required result cells are filled, P0/P1 rows have follow-up issues, and commit evidence matches the current commit.\n")
    handle.write("- `draft`: a generated template exists, but close/continue fields still need manual completion.\n")
    handle.write("- `failed`: the result explicitly records a failed or negative release decision.\n")
    handle.write("- `invalid`: a result is marked complete but still contains placeholders, stale commit evidence, empty required result cells, or unresolved P0/P1 follow-up rows.\n")
    handle.write("- `missing`: no generated result draft was found for that gate.\n")
    handle.write("\n## Strict Checks\n\n")
    handle.write("Run `scripts/validate-completed-release-results.sh --fail-on-invalid` after manually filling result drafts to catch false-positive completion.\n")
    handle.write("Run `scripts/validate-completed-release-results.sh --fail-on-incomplete` only when #1, #10, and #11 are all expected to be ready for submission.\n")

print(f"Prepared completed release results validation report: {report_path}")
print(f"Completed release results validation: {overall}")

if fail_on_invalid and invalid_count:
    raise SystemExit(1)
if fail_on_incomplete and overall != "complete":
    raise SystemExit(1)
PY
