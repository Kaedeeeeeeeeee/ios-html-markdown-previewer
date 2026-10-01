# Bundled YAML parser and highlighter

`yaml-runtime.min.js` exposes `YAMLRuntime.parse(source)` in JavaScriptCore and
returns a JSON string containing separate YAML documents, flat preorder rows,
source locations, diagnostics, and escaped highlighted source. Imported text is
passed as a function argument, never evaluated as JavaScript. Swift decodes
highlight spans into native text; there is no WebView or HTML execution.

The parser uses YAML 1.2 with strict syntax and unique mapping keys. Mapping and
sequence rows retain their hierarchy, scalar types, source positions, anchors,
and explicit tags. Numeric source is preserved to avoid JavaScript rounding.
Aliases are displayed as references; they are never expanded, including recursive
aliases. Source mode keeps comments and document separators. Original-file sharing
uses the unchanged imported file.

Limits: 2,000,000 UTF-8 bytes for structural parsing, 12,000 displayed nodes,
64 collection levels, 100 documents, and 120,000 CST tokens. CST checks precede
recursive composition. Syntax and complexity failures keep readable source.
Source highlighting/preview is bounded to 200,000 characters and 20,000 lines;
larger source remains in the original file. Files larger than 2 MB are read as an
excerpt and cannot use Copy Source, so a partial excerpt cannot be mistaken for
the full file.

Rebuild and audit instructions are in
[`scripts/vendor-yaml/README.md`](../../../scripts/vendor-yaml/README.md).
Dependency provenance and hashes are in `manifest.json`; distribution notices
are in `THIRD-PARTY-LICENSES.txt`.
