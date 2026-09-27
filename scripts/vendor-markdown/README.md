# Offline Markdown libraries

Rebuild the checked-in resources from the repository root:

```sh
npm ci --ignore-scripts --no-fund --prefix scripts/vendor-markdown
npm run build --prefix scripts/vendor-markdown
```

Use Node 22.12 or newer. npm verifies the tarball integrity recorded in the lockfile. Dependency install scripts are disabled; esbuild uses its locked, optional platform binary package. No bundler or npm dependency is needed by Xcode or by app users. Commit `package.json`, `package-lock.json`, `browser-entry.mjs`, `build.mjs`, and all generated resources together.

The build creates one Safari 17 compatible IIFE (including Mermaid's normally lazy diagram modules), validates there are no unresolved imports or dynamic import expressions, copies the unmodified KaTeX WOFF2 font files, and keeps the original relative CSS font paths. It omits WOFF/TTF fallbacks because the minimum supported WebKit supports WOFF2. It records every shipped asset's SHA-256 and the npm registry URL/integrity for each package contributing bundled source. `THIRD-PARTY-LICENSES.txt` contains the packages' complete notices, including fastdom's README license section. All source packages use permissive licenses, with DOMPurify offered under Apache-2.0 or MPL-2.0 (choose Apache-2.0 for distribution).

Pinned runtime versions were verified against official npm metadata on 2026-09-27:

| Library | Pin | Upstream |
| --- | --- | --- |
| KaTeX | 0.16.47 | https://github.com/KaTeX/KaTeX |
| highlight.js | 11.12.0 | https://github.com/highlightjs/highlight.js |
| Mermaid | 11.17.2 | https://github.com/mermaid-js/mermaid |

KaTeX 0.16.47 is the maintained 0.16 patch line used by Mermaid 11.17.2, so they share one math renderer in the bundle. Mermaid 11.17.2 is the maintained 11.x patch line; this change does not adopt the new 12.0 major. The build tool esbuild is pinned at 0.28.2. `npm audit --omit=dev` reported zero advisories for this lockfile on that date; rerun when updating dependencies. An audit result is not a guarantee of future vulnerability status.

The generated `HTMLMarkdownPreviewer/Resources/Markdown/README.md` documents the app-facing API and security/readiness contract. Highlight styling and the Markdown reader's DOM controller belong to the app renderer, not this third-party bundle.
