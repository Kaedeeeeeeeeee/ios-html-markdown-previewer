# First-Round Usability Script

## Setup

- Device: physical iPhone on iOS 17 or newer.
- App build: latest local archive or TestFlight build.
- Sample files: `docs/usability-testing/samples/`.
- Sources to test: Files, Mail, AirDrop, iCloud Drive, and one messaging app where available.

## Tasks

1. Open `basic-report.html` from Files.
2. Open `markdown-notes.md` from Files.
3. Open `zip-report.zip` from Files and confirm the local CSS and image appear.
4. Open `external-resource.html` and describe what Safe Preview is doing.
5. Open `interactive-trusted.html`, then decide whether to use Interactive mode.
6. Try opening `broken.zip` and explain the error message.
7. Return to the app home screen and reopen a recent file.
8. Delete a recent file.
9. Review the app listing text and say whether the pricing and privacy model are clear.

## Moderator Prompts

- What did you expect to happen when you tapped the file?
- Was it clear which app option to choose?
- Did the app explain enough when something did not load?
- Did Safe Preview feel useful, confusing, or unnecessary?
- Would you know when to use ZIP instead of a single HTML file?

## Pass Criteria

- User can complete core open and preview tasks without moderator instruction.
- User understands that default Safe Preview blocks JavaScript and external network resources.
- User understands that ZIP is the reliable path for local CSS and image assets.
- User can recover from an invalid ZIP error.
- User understands paid download, no ads, no account, and no subscription.
