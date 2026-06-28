# App Store Screenshots

These screenshots were generated with:

```sh
scripts/capture-release-screenshots.sh
```

Current set:

- `iphone-01-home.png`
- `iphone-02-html-safe-preview.png`
- `iphone-03-markdown-preview.png`
- `iphone-04-zip-report-preview.png`
- `iphone-05-settings.png`
- `ipad-01-home.png`
- `ipad-02-html-safe-preview.png`
- `ipad-03-markdown-preview.png`
- `ipad-04-zip-report-preview.png`
- `ipad-05-settings.png`

Captured dimensions:

- iPhone: 1206 x 2622
- iPad: 2064 x 2752

The script uses simulator launch arguments to reset the local library, open built-in samples, and show Settings. Override `OUT_DIR`, `IPHONE_DEVICE`, `IPAD_DEVICE`, `IPHONE_RUNTIME_VERSION`, or `IPAD_RUNTIME_VERSION` when capturing on a different simulator setup.
