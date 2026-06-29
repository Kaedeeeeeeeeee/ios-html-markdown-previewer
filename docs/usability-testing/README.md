# Usability Testing

This folder contains the first-round usability test materials for HTML Previewer.

Use `script.md` to run the session, `observation-template.md` to capture findings, `first-round-result-template.md` to record the close decision, and `samples/` as the file set shared to the test device through Files, Mail, AirDrop, iCloud Drive, Safari downloads, or a messaging app.

To stage a self-contained first-round test packet, run:

```sh
scripts/prepare-usability-test-packet.sh
```

This creates:

- `DerivedData/UsabilityTestPacket/HTMLPreviewerUsabilityTestPacket/`
- `DerivedData/UsabilityTestPacket/HTMLPreviewerUsabilityTestPacket.zip`

To prepare an actual session evidence folder with the current commit, app
version, device snapshot, result draft, and observation draft, run:

```sh
scripts/prepare-usability-session-run.sh --participant-code P01 --device <physical-iPhone>
```

This creates:

- `DerivedData/UsabilitySessionRun/.../first-round-usability-result.md`
- `DerivedData/UsabilitySessionRun/.../usability-observation-notes.md`
- `DerivedData/UsabilitySessionRun/.../HTMLPreviewerUsabilityTestPacket.zip`
- `DerivedData/UsabilitySessionRun/.../devicectl-devices.txt`

The first test round should verify that a user can:

- Open HTML, Markdown, and ZIP files from another app.
- Understand that Safe Preview blocks scripts and external network resources.
- Switch to Interactive mode only for trusted files.
- Recognize when missing assets should be delivered as a ZIP package.
- Explain the app's paid download, no ads, no account, no subscription positioning.

Do not close the usability issue until at least one external participant has run through the script and all discovered P0/P1 issues are filed or fixed.
