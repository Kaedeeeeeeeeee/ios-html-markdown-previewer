#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT_DIR/DerivedData/GitHubActionsDiagnostics}"
REPO="${REPO:-}"
BRANCH="${BRANCH:-}"
RUN_ID="${RUN_ID:-}"
FAIL_ON_BLOCKED=false

usage() {
  cat <<'EOF'
Usage: scripts/check-github-actions-execution.sh [options]

Generates a GitHub Actions execution diagnostic report for the latest workflow
run on the current branch, or for a specific run id. This script is intended
for account/repository execution-layer blockers where jobs fail before any
workflow steps run.

Environment:
  REPO         Optional GitHub repository in owner/name form.
  BRANCH       Optional branch. Defaults to current git branch.
  RUN_ID       Optional workflow run id.
  OUTPUT_ROOT  Optional output root. Defaults to DerivedData/GitHubActionsDiagnostics.

Options:
  --repo OWNER/NAME     GitHub repository.
  --branch NAME         Branch to inspect when --run-id is not provided.
  --run-id ID           Workflow run id to inspect.
  --fail-on-blocked     Exit non-zero when every job has zero recorded steps.
  -h, --help            Show this help.
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --branch)
      BRANCH="${2:-}"
      shift 2
      ;;
    --run-id)
      RUN_ID="${2:-}"
      shift 2
      ;;
    --fail-on-blocked)
      FAIL_ON_BLOCKED=true
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

if ! command -v gh >/dev/null 2>&1; then
  printf 'GitHub CLI `gh` is required.\n' >&2
  exit 2
fi

if [[ -z "$REPO" ]]; then
  REPO="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || true)"
fi

if [[ -z "$REPO" ]]; then
  printf 'Unable to infer GitHub repository. Pass --repo OWNER/NAME.\n' >&2
  exit 2
fi

if [[ "$REPO" != */* ]]; then
  printf 'Repository must be in owner/name form, found: %s\n' "$REPO" >&2
  exit 2
fi

if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git -C "$ROOT_DIR" branch --show-current 2>/dev/null || true)"
fi

if [[ -z "$RUN_ID" ]]; then
  if [[ -z "$BRANCH" ]]; then
    printf 'Unable to infer branch. Pass --branch NAME or --run-id ID.\n' >&2
    exit 2
  fi
  RUN_ID="$(
    gh run list \
      --repo "$REPO" \
      --branch "$BRANCH" \
      --limit 1 \
      --json databaseId \
      --jq '.[0].databaseId' 2>/dev/null || true
  )"
fi

if [[ -z "$RUN_ID" || "$RUN_ID" == "null" ]]; then
  printf 'No GitHub Actions run found for %s on branch %s.\n' "$REPO" "${BRANCH:-unknown}" >&2
  exit 1
fi

OWNER="${REPO%%/*}"
timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
run_dir="$OUTPUT_ROOT/$timestamp-run-$RUN_ID"
mkdir -p "$run_dir"

run_json="$run_dir/run.json"
permissions_json="$run_dir/repository-actions-permissions.json"
workflow_permissions_json="$run_dir/workflow-permissions.json"
billing_json="$run_dir/actions-billing.json"
billing_error="$run_dir/actions-billing-error.txt"
failed_log_output="$run_dir/failed-log-output.txt"
report_path="$run_dir/github-actions-diagnostics.md"
blocker_state="$run_dir/blocker-state.txt"

gh run view "$RUN_ID" \
  --repo "$REPO" \
  --json status,conclusion,event,createdAt,startedAt,updatedAt,headSha,headBranch,jobs,url \
  >"$run_json"

gh api "repos/$REPO/actions/permissions" >"$permissions_json" 2>"$run_dir/repository-actions-permissions-error.txt" || true
gh api "repos/$REPO/actions/permissions/workflow" >"$workflow_permissions_json" 2>"$run_dir/workflow-permissions-error.txt" || true

if gh api "users/$OWNER/settings/billing/actions" >"$billing_json" 2>"$billing_error"; then
  billing_status="available"
elif gh api "orgs/$OWNER/settings/billing/actions" >"$billing_json" 2>>"$billing_error"; then
  billing_status="available"
else
  billing_status="unavailable"
fi

if gh run view "$RUN_ID" --repo "$REPO" --log-failed >"$failed_log_output" 2>&1; then
  failed_log_status="available"
else
  failed_log_status="unavailable"
fi

python3 - \
  "$run_json" \
  "$permissions_json" \
  "$workflow_permissions_json" \
  "$billing_json" \
  "$billing_error" \
  "$failed_log_output" \
  "$report_path" \
  "$blocker_state" \
  "$REPO" \
  "$BRANCH" \
  "$RUN_ID" \
  "$billing_status" \
  "$failed_log_status" <<'PY'
import json
import pathlib
import sys
from datetime import datetime, timezone

(
    run_json_path,
    permissions_json_path,
    workflow_permissions_json_path,
    billing_json_path,
    billing_error_path,
    failed_log_output_path,
    report_path,
    blocker_state_path,
    repo,
    branch,
    run_id,
    billing_status,
    failed_log_status,
) = sys.argv[1:]


def load_json(path):
    try:
        text = pathlib.Path(path).read_text(encoding="utf-8")
        if not text.strip():
            return None
        return json.loads(text)
    except (OSError, json.JSONDecodeError):
        return None


def read_text(path):
    try:
        return pathlib.Path(path).read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return ""


run = load_json(run_json_path) or {}
permissions = load_json(permissions_json_path)
workflow_permissions = load_json(workflow_permissions_json_path)
billing = load_json(billing_json_path)
billing_error = read_text(billing_error_path)
failed_log_output = read_text(failed_log_output_path)
jobs = run.get("jobs") or []

jobs_with_empty_steps = [job for job in jobs if not (job.get("steps") or [])]
all_jobs_empty = bool(jobs) and len(jobs_with_empty_steps) == len(jobs)
any_failed = any(job.get("conclusion") == "failure" for job in jobs)
pre_step_blocker = all_jobs_empty and any_failed

pathlib.Path(blocker_state_path).write_text(
    "pre-step-blocker\n" if pre_step_blocker else "not-pre-step-blocker\n",
    encoding="utf-8",
)

generated = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

lines = [
    "# GitHub Actions Execution Diagnostics",
    "",
    f"- Generated: {generated}",
    f"- Repository: `{repo}`",
    f"- Branch: `{branch or run.get('headBranch') or 'unknown'}`",
    f"- Run id: `{run_id}`",
    f"- Run URL: {run.get('url', 'unknown')}",
    f"- Event: {run.get('event', 'unknown')}",
    f"- Head SHA: `{run.get('headSha', 'unknown')}`",
    f"- Status: `{run.get('status', 'unknown')}`",
    f"- Conclusion: `{run.get('conclusion', 'unknown')}`",
    f"- Created: `{run.get('createdAt', 'unknown')}`",
    f"- Started: `{run.get('startedAt', 'unknown')}`",
    f"- Updated: `{run.get('updatedAt', 'unknown')}`",
    "",
    "## Job Summary",
    "",
    "| Job | Status | Conclusion | Step count | URL |",
    "|---|---|---|---:|---|",
]

for job in jobs:
    step_count = len(job.get("steps") or [])
    lines.append(
        f"| {job.get('name', 'unknown')} | `{job.get('status', 'unknown')}` | "
        f"`{job.get('conclusion', 'unknown')}` | {step_count} | {job.get('url', '')} |"
    )

if not jobs:
    lines.append("| No jobs returned by GitHub API |  |  | 0 |  |")

lines.extend(["", "## Diagnosis", ""])
if pre_step_blocker:
    lines.extend(
        [
            "- Every job in this run has zero recorded steps and failed before step logs were available.",
            "- `gh run view --log-failed` did not return normal job logs." if failed_log_status != "available" else "- Failed logs were available; inspect them before treating this as an execution-layer blocker.",
            "- This points at a GitHub Actions account, billing, repository policy, or platform execution-layer issue rather than a failing workflow command.",
        ]
    )
else:
    lines.append("- This run does not match the all-jobs-zero-steps blocker signature. Inspect failed job logs normally.")

lines.extend(["", "## Repository Actions Permissions", ""])
if permissions is None:
    lines.append("- Repository Actions permissions were unavailable from the API.")
else:
    lines.append(f"- Actions enabled: `{permissions.get('enabled')}`")
    lines.append(f"- Allowed actions: `{permissions.get('allowed_actions')}`")
    lines.append(f"- SHA pinning required: `{permissions.get('sha_pinning_required')}`")

if workflow_permissions is None:
    lines.append("- Workflow token permissions were unavailable from the API.")
else:
    lines.append(f"- Default workflow permissions: `{workflow_permissions.get('default_workflow_permissions')}`")
    lines.append(f"- Can approve pull request reviews: `{workflow_permissions.get('can_approve_pull_request_reviews')}`")

lines.extend(["", "## Billing API Check", ""])
if billing_status == "available" and billing is not None:
    for key in sorted(billing):
        lines.append(f"- {key}: `{billing[key]}`")
else:
    lines.append("- Billing details were not available through the current `gh` token.")
    if billing_error:
        redacted = billing_error.replace("\n", " ")
        lines.append(f"- API response: `{redacted}`")
    lines.append("- If needed, run `gh auth refresh -h github.com -s user` and rerun this script, or check billing in the GitHub web UI.")

lines.extend(["", "## Failed Log Command Output", ""])
if failed_log_output:
    lines.append("```text")
    lines.append(failed_log_output[:4000])
    lines.append("```")
else:
    lines.append("- No failed log command output was captured.")

lines.extend(
    [
        "",
        "## Next Checks For Account Owner",
        "",
        "1. Open repository Settings -> Actions -> General and confirm Actions are enabled and allowed for this repository.",
        "2. Open account or organization Billing -> Budgets and alerts. Confirm GitHub Actions metered usage is not blocked by an exhausted or stop-usage budget.",
        "3. If the repository belongs to an organization or enterprise, confirm parent Actions policies allow this repository and public reusable actions.",
        f"4. After changing billing or policy settings, rerun: `gh run rerun {run_id} --debug`.",
        f"5. Rerun this diagnostic script and attach the generated report to issue #10.",
    ]
)

pathlib.Path(report_path).write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

printf 'GitHub Actions diagnostic report: %s\n' "$report_path"

if [[ "$FAIL_ON_BLOCKED" == true ]] && grep -Fxq "pre-step-blocker" "$blocker_state"; then
  exit 1
fi
