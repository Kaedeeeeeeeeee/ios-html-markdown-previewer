# HTML Previewer 1.8 (13) — release preparation

Prepared on 2026-10-07. This update includes the current Duo/reader changes,
the pending local review-request implementation, and ASO preparation. Version
1.7 is already released according to the release operator's live ASC check.
This checklist does not change historical 1.7 evidence or first-release issues.

## Prepared locally

- Version/build: 1.8 / 13; minimum iOS 17.0 and iPhone/iPad support retained.
- CI and archive/upload workflows require Xcode 27.1 and both iOS SDKs 27.1.
  `scripts/select-release-toolchain.sh` checks reported versions, supports installed
  Xcode app names with different separators, and never changes `xcode-select`.
  An explicit invalid `DEVELOPER_DIR` fails; no older toolchain fallback occurs.
  Workflow auto-selection first clears the runner's inherited `DEVELOPER_DIR`,
  then exports the verified installation through `GITHUB_ENV`. Local explicit
  overrides retain their strict validation semantics.
- Archive validators require the new version/build and `DTSDKName=iphoneos27.1`.
  Signing settings remain unchanged. Modern AppAssetLibrary screenshot groups
  are verified as `IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE`, `IPAD_13_PROFILE`, and
  `IPHONE_DUO_PROFILE`; the legacy ScreenshotSets overwrite route is disabled.
- English, Simplified Chinese, Japanese, and Traditional Chinese notes are active in
  `fastlane/metadata/<locale>/release_notes.txt`. See
  [notes and localization boundary](updates/1.8-release-notes.md).
- Existing Duo QA and its limits remain in
  [the October 7 record](updates/2026-10-07-iphone-duo.md).
  Debug simulator acceptance does not prove Release/archive equivalence.

## Toolchain prerequisite

Apple distinguishes compatibility from full Duo layout: older SDK builds run on
Duo; iOS 27 expands inner-display usage; iOS **27.1** enables edge-to-edge layout
and vertical standard bars. See [Prepare your app for iPhone Duo, 0:30–1:17](https://developer.apple.com/videos/play/tech-talks/111461/?time=30).

The two build/test CI jobs use the official standard `xcode-27` hosted label.
The [official image list](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md),
checked on 2026-10-07 (image `20260928.0222.1`), lists macOS 27 and Xcode 27.1
build `27A9269` with both SDKs 27.1. This image is a public preview. Run `37598377482` actually used Xcode 27.1
build `27A9269` and both SDKs 27.1; its Release build/archive job passed.
Final automated-test status is tracked below. `macos-27` is not a documented label. The existing `macos-26` image only lists Xcode 26.x.
[GitHub's runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
lists `xcode-27` as a standard runner, free for this public repository; no larger
runner or new self-hosted registration is used.

Distribution uses the verified local Xcode 27.1 RC build `27A9275`. The upload
workflow also targets `xcode-27`, but sets `RELEASE_XCODE_BUILD=27A9275` so the
currently listed earlier beta cannot silently produce a distribution archive.
It stops before archive until the matching build is installed. Local archive
and upload remain the usable release route; existing-build `submit_only` skips
toolchain/archive/upload. This is separate from CI's SDK-level build/test checks.

On the verified local host, select without changing the global default:

```sh
export DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer
export RELEASE_XCODE_BUILD=27A9275
bash scripts/select-release-toolchain.sh
```

The installed toolchain is Xcode 27.1 RC (27A9275). Its new Distribution archive
was accepted and processed as VALID build 1.8 (13); see the evidence below.

## Verified local build and repository route

- Read-only repository audit: `Kaedeeeeeeeeee/ios-html-markdown-previewer` is
  public, remote/local `main` both at `3f3cf0e` at the audit time. The branch API
  reports no protection and the ruleset list is empty; neither was changed.
  The only registered self-hosted runner is the existing online Linux
  `ubuntu-zhang` runner, so it cannot provide the Xcode build route.
- The new workflows retain PR #23's integrated-materials audit and previous-
  version release gate. Their script content and the new screenshot inventory
  must be integrated before final CI; changing the runner does not bypass them.
- Generic iOS **unsigned** Release build passed locally on 2026-10-07, using
  Xcode 27.1 RC and `CODE_SIGNING_ALLOWED=NO` in
  `DerivedData/Release1.8/CIEquivalent`. Bundle metadata is 1.8 (13),
  `iphoneos27.1`, `DTXcode=2710`, `DTXcodeBuild=27A9275`, minimum iOS 17.0,
  device families `[1, 2]`. Binary, `Assets.car`, and privacy manifest are present.
  Log: `/tmp/html-release-1.8-generic27.1-build-20261007.log` (exit 0).
- This build is not a signed archive, simulator test result, final-commit CI,
  hosted-runner execution result, or upload. The executable next route is local
  RC validation/signing/archive/upload plus the existing standard hosted
  `xcode-27` CI jobs after the release operator integrates and pushes the source.

## Required before submission

- [x] Synchronize the four locales (`en-US`, `zh-Hans`, `ja`, `zh-Hant`) to the
  editable 1.8 version and draft AppInfo. Exact remote readback passed for all
  32 metadata fields. Published 1.7 metadata and AppInfo were unchanged.
  Target version ID: `e9e623b5-1cad-42fd-a8fc-db5b0f2be9f5`.
- [x] Complete the latest 212 unit tests and the existing five targeted UI
  regressions on the reused ordinary iPhone simulator; the separately added
  immediate-navigation/reflow test also passed (1/1, both HTML and rich Markdown).
  See the [permanent release QA record](updates/assets/2026-10-07-iphone-duo/release-1.8-validation.json),
  extracted from xcresult and logs with source content hashes. The original
  combined run remains Failed (209 unit passes / 3 failures, all five UI passes);
  its viewport timing failures are covered by the subsequent 3/3 focused and
  212/212 full-unit passes. These are Debug results, not one 213-test suite.
  The older [Duo 12/13 aggregate](updates/assets/2026-10-07-iphone-duo/duo-validation-results.json)
  retains its automated rotation-geometry failure; ordinary iPhone results do
  not replace it.
- [x] Pass offline release-script checks: previous-version gate (12 checks),
  modern assets gate (12 tests / 95 assertions), and CLI authentication
  (6 tests / 68 assertions). Ruby/Fastfile syntax and diff whitespace checks pass.
  `ASC_USE_CLI_TOKEN=true` uses the existing authorized asc keychain profile,
  keeps JWTs in memory, and avoids exporting a private key. Default CI private-
  key authentication remains unchanged. The separate live 72-image gate below
  also passed.
- [x] Freeze the source at `fb8e0ccfb1ca89d3f795f44ff94befbce67c15fa` and push
  `codex/iphone-duo-release-1.8`. PR #23 history and all verified 1.8 code are retained.
- [ ] Verify CI on that commit with recorded Xcode/SDK versions; preserve the
  known automated rotation-geometry limitation and its native QA evidence.
  First CI run `37598377482` passed four jobs; a single optical-zoom test failed
  because 440pt / 3 rounds to a 147 CSS-pixel viewport. The same measurement
  defect reproduced on Duo (382pt / 3 rounds to 127). The test now compares CSS
  width within half a CSS pixel and retains native scale precision, animation
  completion, and two stable samples. All eight local appearance tests passed.
  See [before/after evidence](updates/assets/2026-10-07-iphone-duo/release-1.8-zoom-quantization.json).
  CI now omits verbose sysdiagnose collection after failure, preserving tests,
  xcresult and screenshots while avoiding the observed post-suite timeout.
- [x] Finish the four-locale, three-family screenshot inventory: six images per
  family per locale, 72 total, plus 18 byte-identical English compatibility copies.
  All 12 contact sheets passed independent and root visual review. Source and
  final hashes, dimensions, opaque RGB, six-slot order, and the integrated,
  portable, and macOS release-materials audits passed. See
  [material validation](aso/2026-10-07-duo/materials/integration-validation.json).
- [x] Finish all Asset Library placements and the independent live 72-image gate.
  All 72 delivered PNGs are pixel-identical to local files; 12 groups contain six
  screenshots each in exact order. Remote metadata matches all 32 local fields.
  Both upload receipts have zero unknown operations. Published 1.7 placements
  are unchanged; ordinary 48-image synchronization preserves the verified Duo24.
  See [full 72-image evidence](updates/assets/2026-10-07-iphone-duo/store-assets-1.8/full72-verification.json).
  The uploader waits within a bounded deadline when Apple reports COMPLETE before
  spec and dimensions converge; strict scope and reviewed-receipt resume remain enforced.
- [x] Review the final four-language release notes and store copy; wording and
  actual rendered sample content match the shipped feature scope.
- [x] Create and export a Distribution-signed 1.8 (13) Release archive using
  local Xcode 27.1 RC (27A9275), SDK 27.1, from clean commit `27fe3fc`.
  Bundle/version/SDK, signing, assets, privacy manifest, and IPA SHA passed.
  See [Distribution evidence](updates/assets/2026-10-07-iphone-duo/release-1.8-distribution.json).
  The first attempt failed because global manual-profile settings reached SwiftPM
  targets; using the existing App target settings fixed archive creation.
- [x] Upload and process build `775d76dc-bbc4-4dd4-a972-d24f17f32718` as VALID,
  independently verify its marketing version 1.8 / build 13 / IOS / encryption
  flag, and attach it to the exact 1.8 App Store version. Submission validation
  reports zero blockers. See [ASC readiness](updates/assets/2026-10-07-iphone-duo/release-1.8-asc-ready.json).
- [x] Record final optimized Release simulator smoke on the reused Duo: native
  sample import, HTML search/selected-match continuity across fold, Markdown
  rendering, JSON expansion/exact value, YAML second-document continuity, and
  PDF generation/share presentation passed. Six original captures and matching
  built/installed binary hashes are in the [Release smoke record](updates/assets/2026-10-07-iphone-duo/release-1.8-smoke.json).
  No external share occurred. Four task-created samples were recoverably moved
  after testing, restoring the previously empty normal library. This is not a
  physical-device/TestFlight installation of the Distribution archive; that
  evidence is not claimed for 1.8. Review prompt logic remains covered by unit
  tests and the unchanged feature code from the earlier candidate validation.
- [ ] Verify ASC 1.8 metadata, screenshot identities/order/delivery, privacy/export
  fields, build processing/attachment, and actual `AFTER_APPROVAL` configuration.
- [ ] Record review submission and later public release separately.

Signed archive, export, upload, VALID processing, build attachment, metadata and
all 72 screenshot placements are complete. The first CI run passed four jobs but
one optical-zoom test rejected WebKit's integer CSS-width rounding; the test
measurement is corrected and all eight local appearance tests passed. Full CI
must pass before review submission.
Submission and public release remain separate.
