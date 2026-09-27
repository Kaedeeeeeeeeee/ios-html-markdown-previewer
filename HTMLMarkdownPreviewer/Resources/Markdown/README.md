# Bundled Markdown runtime

All dependencies are local assets. Preserve this folder's hierarchy when adding it as an Xcode folder resource. Rebuild instructions and exact npm pins are in `scripts/vendor-markdown/README.md`. Licenses are in `THIRD-PARTY-LICENSES.txt`; generated file hashes and upstream package provenance are in `manifest.json`.

Load `katex.min.css` and `markdown-libraries.min.js` from the same local base. The stylesheet resolves its 20 local WOFF2 fonts through `fonts/`. Do not inline the stylesheet without rewriting the font URLs to that base.

The script exposes one global:

```js
MarkdownLibraries = {
  katex,                 // KaTeX 0.16.47
  hljs,                  // highlight.js core + 19 registered languages
  mermaid,               // Mermaid 11.17.2, all included diagram implementations
  katexOptions,          // frozen safe defaults
  mermaidOptions,        // frozen safe defaults; clone nested arrays/objects
  versions,
  highlightLanguages
};
```

No Markdown content is scanned or rendered automatically. Mermaid's window-load autorun is explicitly disabled when the bundle loads.

## Render contract

```js
const libs = MarkdownLibraries;

// Always use source text, not HTML derived from the Markdown document.
code.innerHTML = libs.hljs.getLanguage(language)
  ? libs.hljs.highlight(source, { language, ignoreIllegals: true }).value
  : escapeHTML(source);

libs.katex.render(source, mathElement, {
  ...libs.katexOptions,
  displayMode: true,
  macros: {} // Fresh per-document state, never shared between imported documents.
});

// Optional, once per document, e.g. when choosing a light/dark theme.
libs.mermaid.initialize({
  ...libs.mermaidOptions,
  flowchart: { ...libs.mermaidOptions.flowchart },
  secure: [...libs.mermaidOptions.secure],
  theme: 'default' // Or 'dark'; do not copy document-controlled config here.
});
const { svg } = await libs.mermaid.render(uniqueSafeDOMID, diagramSource);
diagramElement.innerHTML = svg;
```

The highlighted languages are Bash, C, C++, CSS, Diff, Go, Java, JavaScript, JSON, Kotlin, Plaintext, Python, Ruby, Rust, SQL, Swift, TypeScript, XML, and YAML, including upstream aliases such as `sh`, `js`, `ts`, `html`, `py`, and `yml`. Unknown languages should remain escaped plain text. Fenced content must never become executable HTML or scripts.

KaTeX supports its documented LaTeX math subset, not complete `.tex` documents or arbitrary packages. `trust:false` disables commands such as remote `\\includegraphics` and unsafe HTML helpers. Errors remain visible source with `throwOnError:false`. The defaults bound macro expansion to 1,000 and explicit size to 20em. The app should additionally bound total document/fence sizes.

Mermaid uses `securityLevel:'strict'`, disables automatic start and HTML labels, and protects security/configuration keys from document directives/frontmatter. It bounds individual diagrams to 50,000 source characters and 500 edges. Do not merge document-controlled settings into `initialize`, register remote icon/font loaders, or change `securityLevel`. Mermaid's packaged DOMPurify handles SVG sanitization; strict mode disables diagram click callbacks. The host page must also enforce a local-only Content Security Policy and block network/navigation in WebKit, because any local input remains untrusted. Libraries themselves are bundled with no CDN imports or chunk requests; document-requested remote resources must be blocked by the host.

Mermaid render is asynchronous. Render diagrams sequentially (or use Mermaid's serialized public API), catch failures per block, preserve escaped source on error, and only mark the page ready after every diagram has resolved and `document.fonts.ready` has resolved. Await local image decoding if images affect PDF/reading-position geometry. Native PDF export, outline/search indexing, screenshot capture, and scroll restoration should await the app's explicit ready signal; `WKWebView.didFinish` alone does not indicate all math/diagrams/fonts have finished.

Do not invoke Mermaid `run()` on the entire untrusted document. It should receive only explicitly parsed Mermaid fence content. Avoid calling returned `bindFunctions` because diagrams in this app are static previews.

Official API references:

- https://katex.org/docs/options
- https://katex.org/docs/supported
- https://highlightjs.readthedocs.io/en/latest/api.html
- https://mermaid.js.org/config/usage.html
- https://mermaid.js.org/config/schema-docs/config-properties-securitylevel.html
- https://mermaid.js.org/config/schema-docs/config-properties-secure.html
