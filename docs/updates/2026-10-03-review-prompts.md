# App Store rating requests

The app requests an App Store rating after five completed readings across at
least three local calendar dates. Each reading requires 30 seconds of active
foreground viewing after the content is ready. Loading, background time,
reader sheets, sharing, and PDF export do not count. Built-in samples are
excluded, and a document counts at most once per local date.

The request happens only after returning to the file list and remaining there
for two seconds. Import preparation, queued imports, file pickers, settings,
paste/rename/duplicate sheets, errors, and active library search defer the
request. Leaving the list or backgrounding the app cancels the delay without
consuming the opportunity. Cold launch alone never triggers a request.

The app attempts a request at most once per marketing version, at least 120 days
after the previous attempt, and only after another five readings across three
dates. Engagement and request history are kept in local UserDefaults under
`reviews.engagement.v1`; no document contents or usage events are uploaded.
Automatic UI tests disable these requests to keep the reading tests deterministic.

The SwiftUI StoreKit `requestReview` action presents Apple's standard prompt.
StoreKit decides whether the prompt actually appears, and doesn't report whether
the user rated, dismissed, or disabled requests. The app records an attempt,
including when StoreKit elects not to display anything, to avoid repeated calls.
TestFlight doesn't display review requests.

## Local validation on October 3, 2026

- Final `ReviewPromptTests`: 10 passed, including counts/dates, local midnight,
  short/sample exclusion, daily deduplication, persistence, version/cooldown,
  disabled test launches, and active-time accumulation.
- Existing UI regression checks passed: original sharing and pasted Markdown
  search, outline, and reading-position restoration after relaunch.
- Portable release materials audit, full release audit, and simulator build passed.
- A seeded simulator run verified the fifth reading progressing to a persisted
  request-attempt record after returning to the library. The system dialog was
  not visually observed. The final rerun encountered simulator startup instability,
  so visible presentation remains unverified.
- Reused the existing iPhone 16 / iOS 18.5 simulator named
  `HTML Previewer 1.6 Geometry iOS18.5`, UDID
  `D17454A3-3351-48DD-A61F-395E5E7EE3FF`. No device was created or deleted.
  The temporary QA document was removed, the original rating preference restored,
  and the simulator shut down afterward.

Evidence is in `DerivedData/ReviewPromptQA/`. Changes are local; there has been
no App Store upload, submission, or release for this feature.

References:

- [Apple: Requesting App Store reviews](https://developer.apple.com/documentation/storekit/requesting-app-store-reviews)
- [Apple: RequestReviewAction](https://developer.apple.com/documentation/storekit/requestreviewaction)
- [Apple: Ratings and reviews](https://developer.apple.com/design/human-interface-guidelines/ratings-and-reviews)

## Physical-device validation on October 3, 2026

- Tested the user's connected physical iPhone 17, iOS 27.0, UDID
  `00008150-001179E81EF8401C`. No simulator was created, deleted, or used
  for this run.
- Signed Debug build, installation, and launch succeeded for the separate
  `com.kaede.htmlmarkdownpreviewer.reviewqa` app. The existing production
  app and its document container were preserved.
- A source copy under `DerivedData/ReviewPromptDeviceQA/source/` contains
  temporary QA bootstrap and diagnostic output. It seeds four readings on
  October 1 and 2 plus a disposable Markdown document. The shipping
  eligibility rules and the 30-second threshold were unchanged.
- A short reading (11.78 seconds) left the count at four and produced no
  prompt. An eligible reading (43.87 active seconds) advanced the count to
  five over three local dates. After returning to the library, Apple's
  native five-star rating prompt was visually observed and captured.
- Selected **Not Now**. No star was selected and no rating was submitted.
- Another reading (51.57 seconds) produced no repeat prompt. The observed
  session logged exactly one StoreKit request. The request history was
  identical after another reading and cold relaunch, and the library
  remained visible without another prompt.
- A dedicated background check returned Home, waited at least 35 seconds,
  and resumed the reader through App Switcher. Its recorded active reading
  time was only 11.56 seconds, confirming that background time was excluded.
- The isolated QA app remains installed for inspection. The console session
  ended; the app was relaunched without QA environment variables. Temporary
  seeding and diagnostics are absent from the shipping source.

Evidence is in `DerivedData/ReviewPromptDeviceQA/`, especially
`system-review-prompt.png`, `device-console.log`, the preference snapshots,
and `status.json`. This validates development-device presentation; Apple
still controls whether production requests show a dialog. These local
changes have not been uploaded, submitted, or released to the App Store.
