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

Runtime validation and submission evidence are recorded in the 1.3 release
record. Machine-readable build provenance and logs are under
`DerivedData/Release1.3/`.
