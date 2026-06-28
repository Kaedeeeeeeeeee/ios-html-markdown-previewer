# Privacy And Required Reason APIs

The app does not collect user data, does not track users, does not use ads, and does not require an account.

`HTMLMarkdownPreviewer/PrivacyInfo.xcprivacy` declares:

- `NSPrivacyCollectedDataTypes`: empty
- `NSPrivacyTracking`: false
- `NSPrivacyTrackingDomains`: empty
- `NSPrivacyAccessedAPICategoryFileTimestamp` with reasons `C617.1` and `3B52.1`

The file metadata declaration is needed because the app reads file metadata such as file size and directory status while importing user-selected documents and managing files copied into the app sandbox.

This metadata is used only to:

- enforce ZIP archive and extracted-size limits
- show local file size in the UI
- identify valid local document records inside the app container

The metadata is not transmitted off device and is not used for tracking.

Apple reference:

- Describing use of required reason API: https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
