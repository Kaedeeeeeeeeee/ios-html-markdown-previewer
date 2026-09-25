# HTML Previewer Support

HTML Previewer is a local HTML, Markdown, and ZIP report package viewer for iPhone and iPad.

## Support Contact

For support, bug reports, or privacy questions, use this public support page:

https://gist.github.com/Kaedeeeeeeeeee/394a005738e00a0f72bf9bd3a5abd59c

You may leave a comment on the public support gist when signed in to GitHub.

## Before Contacting Support

Include:

- App version and build number
- iPhone or iPad model
- iOS version
- File type: `.html`, `.htm`, `.md`, `.markdown`, or `.zip`
- Source app, such as Files, Mail, AirDrop, iCloud Drive, Safari downloads, or a messaging app
- Whether the file opens in Safe Preview, Interactive mode, or Raw Text

Do not attach sensitive files to public comments.

## Common Notes

- In version 1.3 and later, new HTML files open in Interactive mode, with page JavaScript and external resources enabled. This also applies to pasted HTML and HTML entries in ZIP packages. Version 1.2 and earlier use Safe Preview by default.
- Select Safe Preview to block page JavaScript and external HTTP/HTTPS resources. Both modes block external navigation and form navigation.
- Reopening a document preserves its saved preview mode; Markdown continues to use its native reading view.
- ZIP packages are the reliable way to preview HTML files that depend on local CSS or images.
- Single-file HTML and Markdown imports are best effort for relative local assets.

## Reading Tools and Preview Controls (Version 1.3 and Later)

The document controls are at the bottom right: reading tools, preview mode,
sharing, and file details. Available controls depend on the document type and
preview mode. The title has more room at the top; tap it to see the complete
filename in file details.

Open reading tools to search within rendered HTML or Markdown, move to the next
or previous match, browse the heading outline, or return to the beginning.
Documents without headings have no outline entries. HTML reading tools work on
the main document; for ZIP packages, reading position is saved for the entry page.
Switch out of Raw Text to use reading tools.

Reading positions are saved automatically and restored when you reopen a document,
including after restarting the app. During search, the search bar replaces the
bottom controls. Close search to bring the controls back.

## Paste to Preview (Version 1.3 and Later)

On Home, choose Paste to Preview and paste or enter the HTML or Markdown content
itself. The app suggests a format; you can change it and optionally enter a name
before tapping Preview. The new document is saved in Recent Files. The clipboard
is only accessed when you choose to paste; it is not read automatically.

A web address alone cannot be previewed this way. For text larger than 2 MB,
import it as a file instead. Pasted HTML uses the same preview modes as imported
HTML. Use a ZIP package when your HTML needs accompanying local styles or images.

## Sharing and PDF Export (Version 1.2 and Later)

Open the share menu in a document preview to share the original file or export a
PDF. For a ZIP report, sharing sends the complete original ZIP, including its
styles and images. PDF export becomes available when the rendered preview has
finished loading; switch out of Raw Text to export the rendered document.

HTML PDFs use the current page and its print layout. Scripts, animations, and
interactive controls become static in the PDF. Markdown PDFs include tables and
available local images; blocked remote images remain blocked.

Recent files appear above Samples. When the library contains files, tap Samples
to expand or collapse the examples. The app remembers that choice.
