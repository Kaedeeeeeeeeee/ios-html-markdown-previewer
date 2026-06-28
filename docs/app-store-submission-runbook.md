# App Store Submission Runbook

Issue: #10

Use this runbook after physical-device validation passes. Keep the app as a paid download for MVP; do not configure StoreKit products, subscriptions, ads, or account requirements.

## Source Materials

- Listing draft: `docs/app-store-listing.md`
- Release checklist: `docs/release-checklist.md`
- Screenshot set: `docs/app-store-screenshots/`
- Privacy manifest: `HTMLMarkdownPreviewer/PrivacyInfo.xcprivacy`
- Privacy and required reason API note: `docs/privacy-required-reasons.md`
- App icon: `HTMLMarkdownPreviewer/Assets.xcassets/AppIcon.appiconset/`
- Usability samples and review smoke-test samples: `docs/usability-testing/samples/`

## App Store Connect

1. Create or open the app record for bundle id `com.kaede.htmlmarkdownpreviewer`.
2. Configure the commercial model as paid download.
3. Confirm no in-app purchase products are configured for MVP.
4. Enter the listing name, subtitle, description, keywords, promotional text, and review notes from `docs/app-store-listing.md`.
5. Upload screenshots from `docs/app-store-screenshots/`.
6. Set privacy labels to "Data Not Collected" to match the app behavior and privacy manifest.
7. Add the uploaded build after it finishes App Store Connect processing.

Apple references:

- Create an app record: https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app
- Upload builds: https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds
- Manage app privacy: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy
- Screenshot specifications: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
- Required reason API declarations: https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api

## Archive And Smoke Test

1. Run `scripts/release-audit.sh` on the final commit.
2. Confirm the GitHub Actions iOS CI workflow is passing for the final commit.
3. Select a Generic iOS Device or physical iPhone destination in Xcode.
4. Create an archive from the Release configuration.
5. Upload the archive to App Store Connect.
6. Install the processed build through TestFlight or run the archived build on a physical device.
7. Smoke test:
   - Open the app home screen.
   - Open HTML Sample.
   - Open Markdown Sample.
   - Open ZIP Report Sample.
   - Verify Safe Preview blocks external resources by default.
   - Verify Settings states: JavaScript disabled, external resources blocked, no ads, no account.
   - Verify recent file reopen and delete.

## Close Criteria

Close #10 only after:

- App Store Connect paid-download setup is complete.
- Privacy labels are filled and match the app behavior.
- Screenshots are accepted by App Store Connect.
- Physical-device external-open validation from #1 is complete.
- Final archive or TestFlight smoke test passes.
