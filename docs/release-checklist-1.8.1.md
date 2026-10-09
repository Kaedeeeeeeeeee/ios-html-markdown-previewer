# HTML Previewer 1.8.1 (14) — submitted for review

Submitted on 2026-10-09 at 11:53:53 JST (02:53:53.963 UTC). Review submission
`50552e91-868e-411d-a599-dd1a7afb264b` is **WAITING_FOR_REVIEW**. It holds App
Store version 1.8.1 (`f18a4a24-79aa-4bb9-87cc-785bfc74629e`), which links VALID
build 14 (`5a0e68dc-04b2-458f-9347-5df9f48740e9`) and releases automatically
after approval (`AFTER_APPROVAL`). Independent `asc status` and `asc versions
view` reads confirmed the submission, build link, and release type. Apple
approval and public availability are still pending.

1.8.1 ships the iPhone Duo and reader polish from #25 and the UI test wait fixes
from #26. Release preparation is #27. Notes and their wording limits are in
[the 1.8.1 release-note handoff](updates/1.8.1-release-notes.md).

## Source and CI

- Main is `8aa5aca` (#27 squash). Its tree is identical to `b03b8bd`, which CI
  validated.
- [Run 37872676727](https://github.com/Kaedeeeeeeeeee/ios-html-markdown-previewer/actions/runs/37872676727)
  on `b03b8bd` passed all five jobs: 218/218 unit tests and 13/13 UI smoke tests
  (1059 s), including ZIP navigation, the first complete run of that test on
  #25's code.
- Earlier runs did not count. Run 37801600737 on main and run 37764541147 on
  #25 reached the old 25-minute UI smoke limit with no test failures; #27 raised
  the limit to 40 minutes. Run 37869715374 on `3ff65c2` failed one unit test
  (`testReadingStylePreservesAuthorCascadeAndConstructedStyleSheets` timed out
  waiting for native optical zoom on a starved runner), then passed on the next
  run without code changes.

## Distribution

- Archived locally from clean commit `3ff65c2` with Xcode 27.1 RC (27A9275) and
  SDK iphoneos27.1, using `scripts/create-signed-archive.sh` with
  `ALLOW_PROVISIONING_UPDATES=NO`. The archive's app tree
  (`09b66083257e28c503bd9e6250e1abe0ce732e37`) is identical to main; only the two
  submission-gate scripts differ.
- Bundle 1.8.1 (14), minimum iOS 17.0. Signed with Apple Distribution
  `CAB1F79C429CD517B797AE1F500927A924B1875B` and the App Store profile "HTML
  Markdown Previewer App Store" (`6878486a-441b-41d8-9967-3305bafed034`,
  expires 2027-05-17).
- Exported IPA: 5,502,915 bytes, SHA-256
  `ce0abf8f5de04c2a294a2174917076f4d6e92efceee4b83e9f195c14dcb558e9`.
  `asc builds upload` reported upload `5a0e68dc-04b2-458f-9347-5df9f48740e9`,
  which processed to VALID.
- No simulator smoke of the Release binary and no physical-device or TestFlight
  install was performed for 1.8.1.

## App Store Connect

- Version 1.8.1 was created from 1.8 metadata: description, keywords, marketing
  URL, promotional text, and support URL, for four locales. The four What's New
  texts were then written from `fastlane/metadata/*/release_notes.txt`.
- The read-only store gate passed before and immediately before submission: 1.8
  READY_FOR_SALE, four locales with 32 fields exact against the draft AppInfo
  `81672b0e-26d1-42fc-bc7f-5fd690b7042f`, and 72 ordered screenshots.
- Screenshots are the 1.8 (13) placements carried over unchanged. Their
  reference names stay `release-1.8-<hash>`, as declared in the handoff.

## Submission tooling fix

The first submission attempt created nothing. App Store Connect rejected
`POST /v1/reviewSubmissions` with 409 `ENTITY_ERROR.RELATIONSHIP.NOT_ALLOWED`
because the request included `appStoreVersionForReview`. 1.8 had used an
existing empty submission, so this create path was never exercised.
`create_review_submission` now creates the submission with only the app and
platform. The existing step then adds the version as a `reviewSubmissionItems`
entry before submitting. The encryption-flag update keeps reporting 409 because
`usesNonExemptEncryption` is already `false` on the build; that warning is
expected.

## Pending

- [ ] Record Apple approval and actual public availability when they occur.
