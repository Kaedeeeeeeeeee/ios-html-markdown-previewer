# Release Checklist

## Required Before App Store Submission

- Verify document type open/share flow on a physical iPhone.
- Verify Files, Mail, AirDrop, iCloud Drive, and at least one messaging app source.
- Prepare final app icon.
- Capture App Store screenshots for iPhone and iPad.
- Create App Store Connect record as paid download.
- Confirm no IAP products are configured for MVP.
- Fill privacy labels as "Data Not Collected".
- Add review notes from `docs/app-store-listing.md`.
- Run full simulator test suite.
- Run a smoke test using built-in samples.

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
