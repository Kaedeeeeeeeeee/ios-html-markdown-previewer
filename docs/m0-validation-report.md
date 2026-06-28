# M0 Validation Report

Date: 2026-06-28

## Environment

- Xcode: 26.6
- Swift: 6.3.3
- Deployment target: iOS 17.0
- Simulator used for automated validation: iPhone 17, iOS 26.5, UDID `FAF8BD3A-BB0C-4DCB-870C-FF029E3E3220`
- ZIP dependency: ZIPFoundation `0.9.20`

## Results

### A. Document Types / UTType Entry

Status: partially validated.

The app declares viewer support for:

- `public.html`
- `public.xhtml`
- `net.daringfireball.markdown`
- `public.zip-archive`

The app launches successfully on simulator and the built Info.plist contains the expected `CFBundleDocumentTypes` and Markdown `UTImportedTypeDeclarations`.

Important finding: the initial Swift `UTType(importedAs:)` construction for system types caused runtime type declaration warnings for `public.xhtml` and `public.zip-archive`. This was fixed by using `UTType(filenameExtension:)` for XHTML and `UTType.zip` for ZIP.

Remaining work: Files, WeChat, Mail, AirDrop, iCloud Drive, and one messaging app "Open In" behavior must be verified on a physical device because those source-app entry points are not reliably testable in the simulator. Use `docs/physical-device-validation.md` for the validation matrix.

### B. WKWebView Safe Mode External Resource Blocking

Status: passed automated simulator test.

`HTMLSecurityTests.testSafePreviewBlocksExternalHTTPResources` creates a local HTTP probe server, loads a local HTML file with external HTTP CSS and image references, and verifies the server receives zero requests in safe preview mode.

Safe preview currently combines:

- `WKContentRuleList` blocking `^https?://.*`
- `WKWebpagePreferences.allowsContentJavaScript = false`
- `.nonPersistent()` `WKWebsiteDataStore`
- `WebNavigationPolicy` for navigation/form/external scheme defense

### C. ZIP Entry HTML + Extracted Root Resource Loading

Status: passed automated simulator test.

`HTMLSecurityTests.testZIPExtractedHTMLLoadsLocalCSSAndImages` creates a ZIP package containing `index.html`, `assets/style.css`, and `images/pixel.svg`, imports it through `ZipImportService`, loads the entry HTML with `allowingReadAccessTo` set to the extracted root, and verifies both CSS and image rendering through WebKit.

ZIP safety tests also pass for:

- path traversal rejection
- duplicate/unsafe normalized path rejection
- case-conflicting path rejection
- `__MACOSX` and `.DS_Store` filtering
- failed import cleanup
- root `index.html` entry selection

## Verification Commands

```sh
xcodegen generate
xcodebuild test \
  -project HTMLMarkdownPreviewer.xcodeproj \
  -scheme HTMLMarkdownPreviewer \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=FAF8BD3A-BB0C-4DCB-870C-FF029E3E3220' \
  -derivedDataPath DerivedData
```

Latest XcodeBuildMCP `test_sim` result on 2026-06-28: 24 tests passed, 0 failed.

## Tooling Note

XcodeBuildMCP `build_sim` succeeds for compile-only validation. During this M0 run, XcodeBuildMCP `test_sim` and `build_run_sim` intermittently timed out in the simulator launch/test-runner wrapper. Direct `xcodebuild test` and direct `simctl launch` succeeded on the same simulator and build artifacts.
