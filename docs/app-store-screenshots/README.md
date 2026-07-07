# App Store Screenshots

These screenshots were generated with:

```sh
scripts/capture-release-screenshots.sh
```

Current set:

- `en-US/iphone-01-home.png`
- `en-US/iphone-02-html-safe-preview.png`
- `en-US/iphone-03-markdown-preview.png`
- `en-US/iphone-04-zip-report-preview.png`
- `en-US/iphone-05-settings.png`
- `en-US/ipad-01-home.png`
- `en-US/ipad-02-html-safe-preview.png`
- `en-US/ipad-03-markdown-preview.png`
- `en-US/ipad-04-zip-report-preview.png`
- `en-US/ipad-05-settings.png`
- `zh-Hans/...`
- `ja/...`

The script also mirrors the `en-US` screenshots into the root screenshot directory
as `iphone-01-home.png`, `ipad-01-home.png`, and the other legacy filenames used
by release audits.

Captured dimensions:

- iPhone: 1320 x 2868
- iPad: 2064 x 2752

These dimensions match Apple's App Store Connect screenshot specifications for 6.9-inch iPhone portrait screenshots and 13-inch iPad portrait screenshots:
https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications

The script uses simulator launch arguments to reset the local library, set app
language and locale, open built-in samples, and show Settings.

Default App Store screenshot locales:

- `en-US`
- `zh-Hans`
- `ja`

Override `OUT_DIR`, `SCREENSHOT_LOCALES`, `ROOT_SCREENSHOT_LOCALE`,
`IPHONE_DEVICE`, `IPAD_DEVICE`, `IPHONE_RUNTIME_VERSION`, or
`IPAD_RUNTIME_VERSION` when capturing on a different simulator setup.

`SCREENSHOT_LOCALES` entries use `store-locale|AppleLanguages|AppleLocale`, for
example:

```sh
SCREENSHOT_LOCALES='en-US|en|en_US zh-Hans|zh-Hans|zh_Hans_CN ja|ja|ja_JP' \
  scripts/capture-release-screenshots.sh
```
