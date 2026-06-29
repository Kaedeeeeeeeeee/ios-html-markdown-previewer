# Release Checklist

## Completed Locally

- Final app icon is included in `Assets.xcassets`.
- Privacy manifest is included in the app target.
- Critical error and safety copy is present in `Localizable.xcstrings` for English, Simplified Chinese, Traditional Chinese, and Japanese.
- Required reason API usage is documented in `docs/privacy-required-reasons.md`.
- Export compliance metadata is documented in `docs/export-compliance.md`.
- App Store listing draft and review notes are in `docs/app-store-listing.md`.
- App Store Connect field handoff is in `docs/app-store-connect-handoff.md`.
- Privacy policy and support page drafts are in `docs/privacy-policy.md` and `docs/support.md`.
- iPhone and iPad screenshot sets are captured in `docs/app-store-screenshots/`.
- Screenshot capture can be regenerated with `scripts/capture-release-screenshots.sh`.
- Local release materials can be audited with `scripts/release-audit.sh`.
- Public App Store privacy/support URLs can be verified with `scripts/verify-public-pages.sh`.
- App Store handoff materials, including generated App Store Connect and final smoke result drafts, final preflight evidence with commit checks, locally staged physical-device/archive-smoke evidence, and a packet-relative evidence index when available, can be staged with `scripts/prepare-release-packet.sh`.
- App Store Connect setup result drafts can be generated with `scripts/prepare-app-store-connect-run.sh`.
- Generic iOS Release device build can be verified without signing with `scripts/release-device-build.sh`.
- Generic iOS archive creation and metadata can be preflighted without signing with `scripts/archive-preflight.sh`.
- Distribution-signed Release archive creation is scripted with `scripts/create-signed-archive.sh` and dry-run audited without Apple credentials. Development signing is opt-in only for local device smoke and is not App Store/TestFlight submission evidence.
- Archived app physical-device install, launch, and launch-screenshot smoke evidence can be captured with `scripts/run-archive-device-smoke.sh`.
- Final archive/TestFlight smoke result drafts can be generated with `scripts/prepare-final-smoke-run.sh`.
- Physical-device validation samples can be delivered to Safari with `scripts/serve-validation-samples.sh`.
- Physical-device validation run drafts can be generated with `scripts/prepare-physical-device-validation-run.sh`.
- First-round usability materials can be staged with `scripts/prepare-usability-test-packet.sh`.
- Final local submission gates can be run with `scripts/final-submission-preflight.sh`.
- GitHub Actions runs release audit and simulator tests on push and pull request.
- GitHub Actions verifies the public privacy/support URLs on push and pull request.
- GitHub Actions runs a generic iOS Release device build and archive preflight on push and pull request.
- Built-in HTML, Markdown, and ZIP samples are available for first launch and App Review.
- App marketing version is set to `1.0` and build number is `1`.
- Release simulator build verifies `CFBundleShortVersionString=1.0`, `CFBundleVersion=1`, app icon assets, and privacy manifest in the app bundle.

## Required Before App Store Submission

- Verify document type open/share flow on a physical iPhone.
- Verify Files, Mail, AirDrop, iCloud Drive, and at least one messaging app source.
- Run `scripts/prepare-physical-device-validation-run.sh --device <physical-iPhone>` before the physical-device source matrix to prefill the result draft and sample packet.
- Record the run with `docs/physical-device-validation-result-template.md` and attach or summarize it in issue #1.
- Create App Store Connect record as paid download.
- Use `docs/app-store-connect-handoff.md` to fill and confirm app record, pricing, privacy, age rating, export compliance, screenshots, and review notes.
- Run `scripts/prepare-app-store-connect-run.sh` while entering App Store Connect fields and keep the generated `DerivedData/AppStoreConnectRun/.../app-store-connect-result.md` result draft.
- Confirm privacy policy URL and support URL are publicly reachable HTTPS pages.
- Confirm no IAP products are configured for MVP.
- Fill privacy labels as "Data Not Collected".
- Confirm export compliance in App Store Connect matches `ITSAppUsesNonExemptEncryption=false`.
- Add review notes from `docs/app-store-listing.md`.
- Run full simulator test suite on the final commit.
- Run `scripts/release-audit.sh` on the final commit.
- Run `scripts/verify-public-pages.sh` on the final commit.
- Run `scripts/final-submission-preflight.sh` on the final commit and keep `DerivedData/FinalSubmissionPreflight/submission-readiness-report.md` with submission evidence.
- Run `scripts/prepare-release-packet.sh` on the final commit and keep the generated packet with submission evidence.
- Run `scripts/prepare-usability-test-packet.sh` and use it for the first external usability round.
- Run `scripts/serve-validation-samples.sh` when staging sample files for Safari download and device-side sharing.
- Run `scripts/release-device-build.sh` on the final commit to verify the iPhoneOS Release build path before creating a signed archive.
- Run `scripts/archive-preflight.sh` on the final commit to verify the archive action and archive metadata before creating a signed archive.
- Run `DEVELOPMENT_TEAM=<Apple Team ID> scripts/create-signed-archive.sh` on the final commit with the account owner's Apple Distribution signing setup. Do not count `ALLOW_DEVELOPMENT_SIGNING=YES` archives as App Store/TestFlight evidence.
- Run `scripts/run-archive-device-smoke.sh --device <device-id-or-name>` on the final archive when using an archived build for physical-device smoke evidence.
- Run `scripts/prepare-final-smoke-run.sh --device <physical-iPhone>` to prefill the final archive/TestFlight smoke result draft with commit, version, and archive smoke evidence paths.
- Confirm the GitHub Actions iOS CI workflow is passing on the final commit.
- Run a smoke test using built-in samples on the final archive or TestFlight build.
- Record final archive/TestFlight smoke with the generated `DerivedData/FinalSmokeRun/.../final-archive-smoke-result.md` draft and attach or summarize it in issue #10.
- Run the first usability round, record it with `docs/usability-testing/first-round-result-template.md`, and file or fix every P0/P1 finding before closing #11.

Use `docs/physical-device-validation.md` for the external-open matrix and `docs/app-store-submission-runbook.md` for the App Store Connect handoff.

## Current Automated Validation

- File type detection
- External URL detection for file details
- UTF-8/UTF-16 text decoding for Markdown, Raw Text, and external URL detection
- Critical error and safety localization coverage for English, Simplified Chinese, Traditional Chinese, and Japanese
- VoiceOver labels for recent rows, sample rows, preview controls, status banners, details rows, and Markdown image placeholders
- ZIP path traversal rejection
- ZIP duplicate/case-conflict rejection
- ZIP archive, file count, single-file, and expanded-size limits
- ZIP failed-import cleanup
- Metadata persistence
- Preferred preview mode persistence
- Delete cleanup
- Settings clear-imported-files cleanup
- Safe HTML external resource blocking
- Safe vs interactive JavaScript behavior
- Markdown rendering
- Markdown local image root containment and remote image blocking
- Markdown link taps stay in-app and expose copy-only recovery
- Raw text mode for HTML and Markdown
- Built-in sample generation and import
- Separate home-screen import entries for HTML/Markdown files and ZIP packages
- Simulator UI smoke for Settings and built-in HTML, Markdown, and ZIP samples
