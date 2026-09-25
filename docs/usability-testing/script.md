# First-Round Usability Script

## Setup

- Device: physical iPhone on iOS 17 or newer.
- App build: latest local archive or TestFlight build.
- Sample files: `docs/usability-testing/samples/`.
- Sources to test: Files, Mail, AirDrop, iCloud Drive, and one messaging app where available.

## Tasks

1. Open `basic-report.html` from Files.
2. Open `legacy-report.htm` from Files.
3. Open `markdown-notes.md` from Files.
4. Open `markdown-reference.markdown` from Files.
5. Open `zip-report.zip` from Files and confirm the local CSS and image appear.
6. Open `external-resource.html`, switch to Safe Preview, and describe the difference.
7. Open `interactive-trusted.html`, try its interaction in the default Interactive mode, then switch to Safe Preview.
8. Try opening `broken.zip` and explain the error message.
9. Return to the app home screen and reopen a recent file.
10. Delete a recent file.
11. Review the app listing text and say whether the pricing and privacy model are clear.

## Moderator Prompts

- What did you expect to happen when you tapped the file?
- Was it clear which app option to choose?
- Did the app explain enough when something did not load?
- Did Safe Preview feel useful, confusing, or unnecessary?
- Would you know when to use ZIP instead of a single HTML file?

## Pass Criteria

- User can complete core open and preview tasks without moderator instruction.
- User understands that new HTML opens in Interactive mode with scripts and external resources enabled, and can select Safe Preview to block them.
- User understands that ZIP is the reliable path for local CSS and image assets.
- User can recover from an invalid ZIP error.
- User understands paid download, no ads, no account, and no subscription.
