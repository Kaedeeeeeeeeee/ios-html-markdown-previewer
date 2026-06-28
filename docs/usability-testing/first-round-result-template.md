# First-Round Usability Result Template

Copy this template for each completed first-round usability session. Suggested path:
`docs/usability-testing/results/YYYY-MM-DD-participant-code-build.md`.

Issue: #11

## Session Metadata

- Date:
- Moderator:
- Participant code:
- Build source: Xcode run / local archive / TestFlight
- Commit:
- App version:
- Device:
- iOS version:
- Region/language:
- Source apps available:

Do not store the participant's real name, contact details, payment details, or private file contents in this repository.

## Setup Evidence

| Item | Pass/Fail | Notes |
|---|---|---|
| Latest usability packet used |  |  |
| Physical iPhone used |  |  |
| Sample files available in Files |  |  |
| At least one external source app tested |  |  |
| App Store listing draft reviewed |  |  |

## Task Results

Use Pass, Fail, Assisted, Not available, or Not tested.

| Task | Result | Evidence/notes |
|---|---|---|
| Open `basic-report.html` from Files |  |  |
| Open `legacy-report.htm` from Files |  |  |
| Open `markdown-notes.md` from Files |  |  |
| Open `markdown-reference.markdown` from Files |  |  |
| Open `zip-report.zip` and confirm CSS/image assets |  |  |
| Explain Safe Preview for `external-resource.html` |  |  |
| Decide whether to use Interactive mode for `interactive-trusted.html` |  |  |
| Recover from `broken.zip` error |  |  |
| Reopen a recent file |  |  |
| Delete a recent file |  |  |
| Explain paid download / no ads / no account / no subscription |  |  |

## Source-App Notes

| Source app | File types tried | Result | Caveats |
|---|---|---|---|
| Files |  |  |  |
| iCloud Drive |  |  |  |
| Mail |  |  |  |
| AirDrop |  |  |  |
| Messaging app |  |  |  |
| Safari downloads |  |  |  |

## Findings

| Priority | Area | Finding | Evidence | Follow-up issue |
|---|---|---|---|---|
| P0/P1/P2 |  |  |  |  |

Priority guide:

- P0: Blocks opening, previewing, deleting, or recovering from core file errors.
- P1: Causes serious confusion around source app entry points, Safe Preview, ZIP assets, or pricing/privacy claims.
- P2: Polish, copy, layout, or convenience improvements that do not block the core workflow.

## Close Criteria

- All P0 findings filed or fixed:
- All P1 findings filed or fixed:
- Can close #11: yes / no
- Can continue App Store submission: yes / no
- Follow-up issues:

## Issue Comment Draft

```text
First-round usability result:

- Commit:
- Build source:
- Participant code:
- Device/iOS:
- Sources tested:
- Overall status:

Passed:
-

Caveats:
-

P0/P1 findings:
-

Follow-ups:
-

Can close #11: yes/no
```
