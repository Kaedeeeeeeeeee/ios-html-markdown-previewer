# App Store Connect Handoff

Issue: #10

Use this handoff when creating the App Store Connect record and preparing the first `1.0` submission. It consolidates the fields that otherwise live across the listing draft, privacy notes, export compliance note, screenshots, and release checklist.

## Preconditions

- Physical-device external-open validation from #1 has passed or all blocking failures are fixed.
- The final commit passes GitHub Actions jobs: Release Audit, Public App Store Pages, Release Device Build And Archive, and Automated Tests.
- `scripts/release-audit.sh` passes locally.
- `scripts/verify-public-pages.sh` passes locally.
- `scripts/prepare-release-packet.sh` has generated `DerivedData/ReleasePacket/HTMLPreviewerReleasePacket.zip`.
- `scripts/serve-validation-samples.sh --prepare-only` passes locally.
- `scripts/release-device-build.sh` passes locally.
- `scripts/archive-preflight.sh` passes locally.
- `DEVELOPMENT_TEAM=<Apple Team ID> scripts/create-signed-archive.sh` has produced the signed Release archive for upload.
- A signed Release archive or TestFlight build is available for smoke testing.
- Final archive/TestFlight smoke is recorded with `docs/final-archive-smoke-test-template.md` before submission.

## App Record

| Field | Value |
|---|---|
| Platform | iOS |
| Bundle ID | `com.kaede.htmlmarkdownpreviewer` |
| App name | `HTML Previewer` |
| Primary language | English (U.S.) |
| SKU | Account-owner choice; suggested stable value: `com.kaede.htmlmarkdownpreviewer.ios` |
| Primary category | Productivity |
| Secondary category | Utilities, or leave empty |
| Content rights | App-bundled samples are original. Confirm the account-owner answer in App Store Connect before submission. |

## Pricing And Availability

- Commercial model: paid download.
- In-app purchases: none.
- Subscriptions: none.
- Ads: none.
- Account requirement: none.
- Price: account-owner decision.
- Availability: account-owner decision. If there is no region-specific legal constraint, use all App Store countries and regions.
- Do not configure StoreKit products for MVP.

## Version 1.0 Metadata

Copy from `docs/app-store-listing.md`:

- Name
- Subtitle
- Promotional text
- Description
- Keywords
- Support URL
- Privacy Policy URL
- Review notes

Current public URLs:

- Privacy Policy URL: https://gist.github.com/Kaedeeeeeeeeee/b3baa9048f37467e51bd9b3513787c42
- Support URL: https://gist.github.com/Kaedeeeeeeeeee/394a005738e00a0f72bf9bd3a5abd59c

Fields that require account-owner input:

- Copyright owner
- Price
- Availability countries or regions
- Release timing: manual release, automatic release after approval, or scheduled release

## Screenshots

Upload screenshots from `docs/app-store-screenshots/`.

| App Store Connect slot | Files |
|---|---|
| iPhone 6.9-inch display | `iphone-01-home.png`, `iphone-02-html-safe-preview.png`, `iphone-03-markdown-preview.png`, `iphone-04-zip-report-preview.png`, `iphone-05-settings.png` |
| iPad Pro 13-inch display | `ipad-01-home.png`, `ipad-02-html-safe-preview.png`, `ipad-03-markdown-preview.png`, `ipad-04-zip-report-preview.png`, `ipad-05-settings.png` |

`scripts/release-audit.sh` verifies the current screenshot dimensions.

## App Privacy

Use `docs/privacy-policy.md`, `docs/privacy-required-reasons.md`, and `HTMLMarkdownPreviewer/PrivacyInfo.xcprivacy`.

Recommended App Store Connect privacy response:

- Data collected: none.
- Tracking: no.
- Data linked to user: none.
- Data used for tracking: none.
- Privacy Policy URL: use the public gist URL above.
- User Privacy Choices URL: leave empty unless the account owner wants a separate page.

Rationale:

- The app does not collect personal data.
- The app has no analytics, ads, accounts, subscriptions, or in-app purchases.
- User-selected files are copied into the app sandbox for local preview only.
- Files and local metadata are not uploaded by the app.

## Age Rating Worksheet

Use App Store Connect's current age rating questionnaire and confirm each answer before submission.

Recommended answers for the MVP app-bundled experience:

| Area | Recommended answer | Rationale |
|---|---|---|
| Profanity, horror, alcohol, medical, sexual, violence, gambling, contests, loot boxes | None / No | The app bundles only neutral HTML, Markdown, and ZIP samples. |
| Messaging and chat | No | The app has no user-to-user communication. |
| Advertising | No | The app includes no ads or ad SDKs. |
| User-generated content | No | The app does not broadly distribute user-created content or host a social content feed. |
| Unrestricted web access | No | The app is not a browser and has no URL entry or free web navigation. Safe Preview blocks external resources by default. |
| Made for Kids | No / Not Applicable | The app is a general productivity utility, not a Kids category app. |
| Override to higher age rating | Not Applicable | Use only if the account owner chooses a higher rating for policy or market reasons. |

If App Store Connect or App Review interprets user-selected local HTML files differently, answer conservatively and record the final rating decision in #10.

## Export Compliance

Use `docs/export-compliance.md`.

- `HTMLMarkdownPreviewer/Info.plist` sets `ITSAppUsesNonExemptEncryption=false`.
- The app does not implement custom cryptography, authentication, VPN, secure messaging, DRM, password management, or secure storage.
- If App Store Connect asks about encryption, answer consistently with the Info.plist and export compliance note.

## Build Selection And Review Notes

Before selecting the build:

1. Confirm final GitHub Actions run is green.
2. Run `scripts/release-audit.sh`.
3. Run `scripts/verify-public-pages.sh`.
4. Run `scripts/prepare-release-packet.sh`.
5. Run `scripts/release-device-build.sh`.
6. Run `scripts/archive-preflight.sh`.
7. Run `DEVELOPMENT_TEAM=<Apple Team ID> scripts/create-signed-archive.sh`.
8. Upload the signed archive from Xcode Organizer and select the processed build in App Store Connect.
9. Install the processed build through TestFlight or run the archived build on a physical device.
10. Smoke test the built-in HTML, Markdown, and ZIP samples and record the result with `docs/final-archive-smoke-test-template.md`.

Review note summary:

- No login is required.
- No purchase flow is present because the MVP is a paid download.
- Use the built-in Samples section to test HTML, Markdown, and ZIP preview without external files.
- External opening is supported through document type registration; exact menu placement depends on iOS and the source app.

## Apple References

- App privacy: https://developer.apple.com/help/app-store-connect/reference/app-information/app-privacy/
- Manage app privacy: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/
- Set an app age rating: https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/
- Age rating values and definitions: https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/
- Manage availability: https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store/
- Export compliance overview: https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/
