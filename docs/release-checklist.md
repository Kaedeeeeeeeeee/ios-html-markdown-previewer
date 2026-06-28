# Release Checklist

## Completed Locally

- Final app icon is included in `Assets.xcassets`.
- Privacy manifest is included in the app target.
- Required reason API usage is documented in `docs/privacy-required-reasons.md`.
- Export compliance metadata is documented in `docs/export-compliance.md`.
- App Store listing draft and review notes are in `docs/app-store-listing.md`.
- App Store Connect field handoff is in `docs/app-store-connect-handoff.md`.
- Privacy policy and support page drafts are in `docs/privacy-policy.md` and `docs/support.md`.
- iPhone and iPad screenshot sets are captured in `docs/app-store-screenshots/`.
- Screenshot capture can be regenerated with `scripts/capture-release-screenshots.sh`.
- Local release materials can be audited with `scripts/release-audit.sh`.
- Public App Store privacy/support URLs can be verified with `scripts/verify-public-pages.sh`.
- App Store handoff materials can be staged with `scripts/prepare-release-packet.sh`.
- Generic iOS Release device build can be verified without signing with `scripts/release-device-build.sh`.
- Generic iOS archive creation and metadata can be preflighted without signing with `scripts/archive-preflight.sh`.
- GitHub Actions runs release audit and simulator tests on push and pull request.
- GitHub Actions verifies the public privacy/support URLs on push and pull request.
- GitHub Actions runs a generic iOS Release device build and archive preflight on push and pull request.
- Built-in HTML, Markdown, and ZIP samples are available for first launch and App Review.
- App marketing version is set to `1.0` and build number is `1`.
- Release simulator build verifies `CFBundleShortVersionString=1.0`, `CFBundleVersion=1`, app icon assets, and privacy manifest in the app bundle.

## Required Before App Store Submission

- Verify document type open/share flow on a physical iPhone.
- Verify Files, Mail, AirDrop, iCloud Drive, and at least one messaging app source.
- Record the run with `docs/physical-device-validation-result-template.md` and attach or summarize it in issue #1.
- Create App Store Connect record as paid download.
- Use `docs/app-store-connect-handoff.md` to fill and confirm app record, pricing, privacy, age rating, export compliance, screenshots, and review notes.
- Confirm privacy policy URL and support URL are publicly reachable HTTPS pages.
- Confirm no IAP products are configured for MVP.
- Fill privacy labels as "Data Not Collected".
- Confirm export compliance in App Store Connect matches `ITSAppUsesNonExemptEncryption=false`.
- Add review notes from `docs/app-store-listing.md`.
- Run full simulator test suite on the final commit.
- Run `scripts/release-audit.sh` on the final commit.
- Run `scripts/verify-public-pages.sh` on the final commit.
- Run `scripts/prepare-release-packet.sh` on the final commit and keep the generated packet with submission evidence.
- Run `scripts/release-device-build.sh` on the final commit to verify the iPhoneOS Release build path before creating a signed archive.
- Run `scripts/archive-preflight.sh` on the final commit to verify the archive action and archive metadata before creating a signed archive.
- Confirm the GitHub Actions iOS CI workflow is passing on the final commit.
- Run a smoke test using built-in samples on the final archive or TestFlight build.
- Record final archive/TestFlight smoke with `docs/final-archive-smoke-test-template.md` and attach or summarize it in issue #10.

Use `docs/physical-device-validation.md` for the external-open matrix and `docs/app-store-submission-runbook.md` for the App Store Connect handoff.

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
- Simulator UI smoke for Settings and built-in HTML, Markdown, and ZIP samples
