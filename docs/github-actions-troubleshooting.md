# GitHub Actions Troubleshooting

Use this note when the final commit needs a green hosted CI run but GitHub
Actions fails before any workflow step starts.

## Current Blocker Signature

The blocker seen during release prep has this shape:

- The workflow run completes in about five seconds.
- Every job fails, including the Ubuntu `Portable Release Materials` job.
- GitHub's run/job API shows each job with `steps: []`.
- `gh run view <run-id> --log-failed` returns no job log.
- Repository Actions permissions are enabled and `allowed_actions` is `all`.

That signature is different from a failing build, test, script, or workflow
command. Treat it as an Actions execution-layer blocker until GitHub returns
step-level logs.

## Generate A Diagnostic Report

Run this from the repository root:

```sh
scripts/check-github-actions-execution.sh
```

To inspect a specific run:

```sh
scripts/check-github-actions-execution.sh --run-id <run-id>
```

To preserve evidence for a specific debug rerun attempt:

```sh
scripts/check-github-actions-execution.sh --run-id <run-id> --attempt <attempt-number>
```

The script writes a report under:

```text
DerivedData/GitHubActionsDiagnostics/<timestamp>-run-<run-id>/github-actions-diagnostics.md
```

Attach or summarize that report in issue #10 before retrying the final App
Store submission gate.

## Account Owner Checks

1. Open repository Settings -> Actions -> General and confirm Actions are
   enabled for the repository.
2. Confirm repository or organization policies allow the actions used in
   `.github/workflows/ios-ci.yml`.
3. Open account or organization Billing -> Budgets and alerts. Confirm GitHub
   Actions usage is not blocked by an exhausted budget or a stop-usage budget.
4. If the diagnostic script cannot read billing through `gh`, either check the
   GitHub web UI or refresh the local token with:
   ```sh
   gh auth refresh -h github.com -s user
   ```
5. After changing billing or policy settings, rerun the failed workflow:
   ```sh
   gh run rerun <run-id> --debug
   ```
6. Rerun the diagnostic script. The blocker is cleared only when jobs show
   normal step entries and the workflow can reach checkout or later steps.

## References

- GitHub Actions workflow run logs:
  https://docs.github.com/actions/monitoring-and-troubleshooting-workflows/using-workflow-run-logs
- GitHub Actions repository permissions:
  https://docs.github.com/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/disabling-or-limiting-github-actions-for-a-repository
- GitHub budgets and usage:
  https://docs.github.com/billing/managing-your-billing/managing-your-budget
