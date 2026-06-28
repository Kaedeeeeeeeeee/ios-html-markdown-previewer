# Release Checklist

## Completed Locally

- Final app icon is included in `Assets.xcassets`.
- Privacy manifest is included in the app target.
- App Store listing draft and review notes are in `docs/app-store-listing.md`.
- iPhone and iPad screenshot sets are captured in `docs/app-store-screenshots/`.
- Screenshot capture can be regenerated with `scripts/capture-release-screenshots.sh`.
- Built-in HTML, Markdown, and ZIP samples are available for first launch and App Review.

## Required Before App Store Submission

- Verify document type open/share flow on a physical iPhone.
- Verify Files, Mail, AirDrop, iCloud Drive, and at least one messaging app source.
- Create App Store Connect record as paid download.
- Confirm no IAP products are configured for MVP.
- Fill privacy labels as "Data Not Collected".
- Add review notes from `docs/app-store-listing.md`.
- Run full simulator test suite on the final commit.
- Run a smoke test using built-in samples on the final archive or TestFlight build.

## Current Automated Validation

- File type detection
- ZIP path traversal rejection
- ZIP duplicate/case-conflict rejection
- ZIP archive, file count, single-file, and expanded-size limits
- ZIP failed-import cleanup
- Metadata persistence
- Delete cleanup
- Safe HTML external resource blocking
- Safe vs interactive JavaScript behavior
- Markdown rendering
- Built-in sample generation and import
