# Offline YAML runtime

From the repository root, using Node 22.12 or newer:

```sh
npm ci --ignore-scripts --no-fund --prefix scripts/vendor-yaml
npm test --prefix scripts/vendor-yaml
npm run build --prefix scripts/vendor-yaml
python3 scripts/audit-yaml-assets.py
```

Runtime dependencies are pinned to `yaml` 2.9.1 (ISC) and `highlight.js` 11.12.0
(BSD-3-Clause). The build tool is `esbuild` 0.28.2. npm verifies the locked tarball
integrities; dependency install scripts are disabled. The generated Safari 17
compatible IIFE runs in JavaScriptCore. Xcode and the installed app need no npm
installation or network connection.

Commit the source, lockfile, generated runtime, manifest, and complete third-party
notices together. The manifest records source/lock SHA-256, shipped asset size and
SHA-256, dependency versions, registry URLs, integrity values, and licenses.
`scripts/audit-yaml-assets.py` checks these relationships in the portable CI job.

The Node tests exercise YAML 1.2 scalar types, Unicode, quoted keys, multiline
values, precise numeric source, multiple documents, aliases without expansion,
invalid input, and complexity limits. XCTest also exercises the exact shipped
bundle in JavaScriptCore, and simulator UI tests cover the native reader.

See [the resource API](../../HTMLMarkdownPreviewer/Resources/YAML/README.md)
and [the feature report](../../docs/updates/2026-10-01-yaml-preview.md).
