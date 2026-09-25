# Interactive default — 2026-09-25

Newly imported HTML opens in Interactive mode, including pasted HTML, bundled
HTML samples, and HTML entries inside ZIP packages. The initial mode is resolved
from the entry document type. Markdown continues to use rendered preview.

Existing document metadata keeps its saved mode. Switching to Safe Preview still
blocks page scripts and external HTTP/HTTPS resources. Navigation restrictions
and the existing manual-switch confirmation are unchanged.

Settings uses the shared HTML default and its existing localized mode name.
Current documentation, next-release store copy, and future validation templates
have been updated. Published store metadata and public policy pages have not
been changed.

## Validation

- Simulator build passed on iPhone 18 Pro / iOS 27.0.
- 29 unit/integration tests passed across model persistence, file/ZIP/paste
  imports, built-in samples, reading persistence, and WebKit security behavior.
- The pasted-HTML UI test passed: Interactive runs the fixture script; switching
  to Safe Preview blocks it; search, outline, reading position, and the selected
  Safe mode survive reopening after app relaunch.
- The samples/settings UI test passed on the dedicated `HTML Previewer QA
  iPhone 18 Pro` simulator: settings reports Interactive, HTML and ZIP samples
  start Interactive, Safe remains selectable, and Markdown renders normally.
- 31 distinct tests passed in total. The first samples/settings attempt was
  interrupted by another app activating on the shared simulator; it passed on
  the dedicated simulator without a product or test-helper change.
- `git diff --check` and `bash -n` for the three edited checklist generators passed.

Result bundles:

- `~/Library/Developer/XcodeBuildMCP/workspaces/html_preview-0a68f0590b32/result-bundles/test_sim_2026-09-25T04-55-57-059Z_pid64081_e1dd6cde.xcresult`
- `~/Library/Developer/XcodeBuildMCP/workspaces/html_preview-0a68f0590b32/result-bundles/test_sim_2026-09-25T05-02-30-016Z_pid64081_e461b72f.xcresult`

No physical-device installation, push, or release was performed for this change.
