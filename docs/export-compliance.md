# Export Compliance

`HTMLMarkdownPreviewer/Info.plist` sets:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

The app does not implement custom cryptography, proprietary encryption, account authentication, secure messaging, VPN, DRM, password management, or secure storage features.

The app's core behavior is local document import and preview. Any encrypted transport that may occur through system frameworks, such as WebKit loading a trusted interactive page over HTTPS, is provided by Apple operating system frameworks rather than app-provided encryption.

Use this document when answering App Store Connect export compliance prompts. If future versions add custom networking, authentication, sync, cloud storage, or cryptographic features, re-evaluate this key before submission.

Apple reference:

- Overview of export compliance: https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance
