# ZIP package navigation

ZIP reports can contain several connected documents. The reader now keeps those
pages together instead of exposing only the automatically selected entry page.

## Interface

- A compact package bar shows the current page title and relative file path.
- Tap the bar to open **Package Pages**, with title/path search, an entry-page
  label, and a checkmark on the current page. The existing four bottom controls
  remain in place.
- The package back arrow returns to the previous page. The navigation-bar back
  button still returns to the library.
- The built-in sample has three pages: **A week of reading**, **Reading in
  detail** (`chapters/details.html`), and **Notes & method** (`appendix/notes.md`).
  It demonstrates relative CSS/images and links between HTML and Markdown.

Interface and sample content include English, Japanese, Simplified Chinese, and
Traditional Chinese. Page titles come from the user's own document content.

## Behavior

The catalog includes visible `.html`, `.htm`, `.md`, and `.markdown` files beneath
the extracted package root. The entry page appears first; remaining pages are
ordered by folder and filename. Titles use an HTML title or Markdown heading,
with a filename fallback. Scanning runs off the main actor and is cancellable.

The reader owns cross-page transitions, including local `target="_blank"` links.
Markdown relative links are resolved against the current source page; heading
fragments support the reader's structural IDs and familiar Unicode Markdown
slugs. External navigation, form submissions, traversal, and symlink escapes
remain blocked. Non-page assets do not replace the active package page.

Each package remembers its selected page and per-page reading positions. History
starts fresh on reopening. Older saved ZIPs retain their entry-page reading
position. Replacing the imported ZIP clears saved page selections and positions
because its contents may have changed.

Search, outline, Raw Text, and PDF export follow the current page. PDF uses the
page title as its suggested filename; original-file sharing keeps the complete
ZIP and its resources. The HTML preview mode remains a document preference;
Markdown pages use their rendered reader unless Raw Text is selected.

## Validation

Automated catalog/store tests cover discovery, ordering, title fallback,
containment, persistence, replacement, history, and Markdown heading fragments.
WebKit integration tests cover page callbacks, local assets, same-page anchors,
new-window links, blocked targets, Safe Preview, and current-page PDF content.
The UI regression imports an isolated three-page fixture, searches and switches
pages, uses Raw Text and back history, follows HTML/Markdown links, and reopens
the last selected page after relaunch. Cleanup removes only its own fixture.

Validated on 2026-09-27:

- iPhone 18 Pro / iOS 27: 156 unit and WebKit integration cases passed after
  fixing catalog enumeration/title issues and an invalid cross-origin test probe.
  The ZIP navigation UI flow and Chinese Markdown heading regression passed.
  Two WebKit launch timeouts during concurrent simulator startup passed when
  rerun serially; all latest case results are recorded in `phone-test-summary.json`.
- iPad Pro 12.9 / iOS 18.5: all 25 selected catalog, navigation, and sample tests
  passed, together with the full ZIP UI flow. The final row styling was also
  exercised by a passing UI rerun. A larger default sheet on regular-width
  layouts was verified by a final passing UI run; its initial test-runner startup
  stall resolved after restarting this simulator without erasing it.
- Japanese iPhone pages were visually checked in light and dark appearance.
  A PDF exported through the actual detail-page UI contains its title and daily
  average, with no entry-page title. Switching back and selecting the Markdown
  appendix restored its previous formula/code scroll position.
- Localization key parity and `scripts/release-audit.sh` passed. CI now includes
  the ZIP UI regression, a corrected sample-heading assertion, and sufficient
  time for the expanded UI suite.

Local test bundles, screenshots, the exported PDF, and a per-case test summary
are under `/Users/user/html_preview/DerivedData/ZIPNavigation/`. Key screenshots:
`ja-02-page-picker.png`, `ja-03-html-detail.png`, `ja-05-math-code.png`, and
`ja-06-math-code-dark.png`.

No physical-device run, version bump, or App Store submission is part of this change.
