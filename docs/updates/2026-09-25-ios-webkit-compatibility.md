# WebKit compatibility for older iOS versions — 2026-09-25

Release 1.3 uses named JavaScript arguments and an isolated content world for
search, the heading outline, reading position, and temporary PDF highlight
suspension. With the current Xcode SDK, the ordinary Swift `callAsyncJavaScript`
overlay introduced a strong dependency on `libswiftWebKit.dylib`. The library is
absent from iOS 18.5, causing launch to fail before application code executes.
The previous 1.2 archive did not have this dependency.

`WKWebView+DocumentJavaScript.swift` calls WebKit's public refined Objective-C
entry point directly. It preserves promise completion, named arguments, errors,
optional results, and the isolated content world. The async wrapper keeps WebKit
values on the main actor. The deployment target remains iOS 17.

The fix was committed as `0301506`. The new unit regression covers fulfilled and
rejected promises, arguments, undefined results, and page-world isolation. The
existing reading and PDF tests exercise the production call sites.

Static inspection of the rebuilt Debug application, test bundles, and signed
Release archive found no `libswiftWebKit` load command or undefined Swift WebKit
overlay symbol. The fixed archive passes strict code-signature verification.
Only the fixed archive and IPA are eligible for release. The pre-fix build was
never uploaded to App Store Connect.

Runtime validation passed all 76 unit/integration tests on both iPhone SE
(3rd generation), iOS 18.5, and iPhone 18 Pro, iOS 27. These include the new bridge
regression, existing reading isolation/position tests, and PDF exports. The
built-in sample/settings UI smoke also passed on iOS 18.5.

The SE initially had an independent simulator launch-service stall. A scoped
restart of only its `runningboardd` restored app/test launch. No simulator data
was erased and no other simulator was reset. Earlier UI paste failures were
separately traced to the iOS 18 Form accessibility frame covering the whole row,
while the native Paste control is left-aligned. The UI fixture now taps inside
the observed control and prepares clipboard data in the foreground.

Final UI validation and submission evidence are recorded in the 1.3 release
record. Machine-readable build provenance and logs are under
`DerivedData/Release1.3/`.
