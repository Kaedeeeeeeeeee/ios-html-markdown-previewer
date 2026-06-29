# Final Archive Or TestFlight Smoke Test Template

Copy this template for the final signed archive or TestFlight build smoke test. Suggested path:
`docs/final-smoke-results/YYYY-MM-DD-build-version.md`.

Issue: #10

## Run Metadata

- Date:
- Tester:
- Commit:
- GitHub Actions run:
- Build source: signed archive / TestFlight
- App Store Connect build:
- App version:
- Build number:
- Device:
- iOS version:
- Install method:

## Pre-Smoke Gates

| Gate | Expected evidence | Pass/Fail | Notes |
|---|---|---|---|
| Final GitHub Actions run is green | Release Audit, Public App Store Pages, Release Device Build And Archive, Automated Tests |  |  |
| Local release audit passed | `scripts/release-audit.sh` output |  |  |
| Public pages verification passed | `scripts/verify-public-pages.sh` output |  |  |
| Release device build preflight passed | `scripts/release-device-build.sh` output |  |  |
| Archive preflight passed | `scripts/archive-preflight.sh` output |  |  |
| Archived app install/launch evidence captured | `scripts/run-archive-device-smoke.sh --device <device-id-or-name>` report and launch screenshot, when using an archived build |  |  |
| Physical-device external-open validation completed | Linked #1 result |  |  |
| App Store Connect record configured | Paid download, no IAP, privacy labels, age rating, export compliance |  |  |

## App Launch And Built-In Samples

| Check | Pass/Fail | Evidence/notes |
|---|---|---|
| App launches to home screen |  |  |
| Home screen shows Samples section |  |  |
| HTML Sample opens |  |  |
| HTML Sample shows Safe Preview |  |  |
| HTML Safe Preview blocks external resources by default |  |  |
| Markdown Sample opens and renders formatted content |  |  |
| ZIP Report Sample opens |  |  |
| ZIP Report Sample renders local CSS/images |  |  |
| ZIP sample appears in Recent |  |  |
| Recent item reopens successfully |  |  |
| Recent item can be deleted |  |  |

## Settings And Release Claims

| Claim | Expected state | Pass/Fail | Notes |
|---|---|---|---|
| JavaScript | Disabled in Safe Preview |  |  |
| External resources | Blocked in Safe Preview |  |  |
| Processing | On device |  |  |
| Account | None |  |  |
| Ads | None |  |  |
| Purchase flow | None in app; paid download only |  |  |

## App Store Connect Checks

| Area | Expected state | Pass/Fail | Notes |
|---|---|---|---|
| Commercial model | Paid download |  |  |
| In-app purchases | None configured for MVP |  |  |
| Subscriptions | None |  |  |
| Privacy labels | Data Not Collected |  |  |
| Privacy policy URL | Public HTTPS URL accepted |  |  |
| Support URL | Public HTTPS URL accepted |  |  |
| Export compliance | Matches `ITSAppUsesNonExemptEncryption=false` |  |  |
| Screenshots | Accepted for iPhone and iPad slots |  |  |
| Review notes | Built-in sample flow included |  |  |

## Blocking Failures

| Priority | Failure | Reproduction steps | Follow-up issue |
|---|---|---|---|
| P0/P1/P2 |  |  |  |

Priority guide:

- P0: Blocks launch, preview, import, deletion, or App Store submission.
- P1: Conflicts with App Store listing, privacy, paid-download positioning, or review notes.
- P2: Polish or documentation issue that does not block submission.

## Result

- Overall status: pending / passed / failed
- Can submit for review: yes / no
- Follow-up issues:

## Issue Comment Draft

```text
Final archive/TestFlight smoke result:

- Commit:
- GitHub Actions run:
- Build source:
- App Store Connect build:
- Device/iOS:
- Overall status:

Passed:
- 

Caveats:
- 

Blocking failures:
- 

Follow-ups:
- 
```
