#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_ROOT="$ROOT_DIR/DerivedData/ValidationSamples"
INDEX_PATH="$OUTPUT_ROOT/index.html"
README_PATH="$OUTPUT_ROOT/README-browser-delivery.txt"
PORT="${PORT:-8787}"
BIND_HOST="${BIND_HOST:-0.0.0.0}"
PREPARE_ONLY=false

usage() {
  cat <<'EOF'
Usage: scripts/serve-validation-samples.sh [--prepare-only]

Stages the physical-device validation samples and serves a local download page
for testing Safari downloads and moving sample files onto a physical iPhone.

Environment:
  PORT          Optional HTTP port, defaults to 8787.
  BIND_HOST     Optional bind host, defaults to 0.0.0.0.
  HOST_ADDRESS  Optional address printed for the iPhone URL.

Options:
  --prepare-only  Generate the download page without starting the server.
  -h, --help      Show this help.
EOF
}

detect_host_address() {
  if [[ -n "${HOST_ADDRESS:-}" ]]; then
    printf '%s\n' "$HOST_ADDRESS"
    return
  fi

  for interface in en0 en1; do
    if address="$(ipconfig getifaddr "$interface" 2>/dev/null)" && [[ -n "$address" ]]; then
      printf '%s\n' "$address"
      return
    fi
  done

  printf 'localhost\n'
}

for arg in "$@"; do
  case "$arg" in
    --prepare-only)
      PREPARE_ONLY=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n\n' "$arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

"$ROOT_DIR/scripts/prepare-validation-samples.sh" >/dev/null

cat > "$INDEX_PATH" <<'EOF'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>HTML Previewer Validation Samples</title>
  <style>
    body {
      max-width: 760px;
      margin: 32px auto;
      padding: 0 20px;
      font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: #1d1d1f;
      background: #fff;
    }
    h1 {
      font-size: 28px;
      line-height: 1.2;
    }
    h2 {
      margin-top: 28px;
      font-size: 19px;
    }
    a {
      color: #0645ad;
    }
    li {
      margin: 8px 0;
    }
    code {
      padding: 2px 5px;
      border-radius: 4px;
      background: #f2f2f7;
    }
    .note {
      padding: 12px 14px;
      border-left: 4px solid #6e6e73;
      background: #f5f5f7;
    }
  </style>
</head>
<body>
  <h1>HTML Previewer Validation Samples</h1>
  <p class="note">Use these links on a physical iPhone. Download or share the individual files, then verify HTML Previewer appears in the source app's open/share menu.</p>

  <h2>Primary Extension Matrix</h2>
  <ul>
    <li><a href="HTMLPreviewerValidationSamples/basic-report.html">basic-report.html</a> for <code>.html</code></li>
    <li><a href="HTMLPreviewerValidationSamples/legacy-report.htm">legacy-report.htm</a> for <code>.htm</code></li>
    <li><a href="HTMLPreviewerValidationSamples/markdown-notes.md">markdown-notes.md</a> for <code>.md</code></li>
    <li><a href="HTMLPreviewerValidationSamples/markdown-reference.markdown">markdown-reference.markdown</a> for <code>.markdown</code></li>
    <li><a href="HTMLPreviewerValidationSamples/zip-report.zip">zip-report.zip</a> for <code>.zip</code></li>
  </ul>

  <h2>Safety And Error Paths</h2>
  <ul>
    <li><a href="HTMLPreviewerValidationSamples/external-resource.html">external-resource.html</a></li>
    <li><a href="HTMLPreviewerValidationSamples/interactive-trusted.html">interactive-trusted.html</a></li>
    <li><a href="HTMLPreviewerValidationSamples/broken.zip">broken.zip</a></li>
  </ul>

  <h2>Full Package</h2>
  <ul>
    <li><a href="HTMLPreviewerValidationSamples.zip">HTMLPreviewerValidationSamples.zip</a></li>
  </ul>
  <p>Expand the full package in Files before testing. Do not use the outer distribution ZIP as the app's ZIP-import sample; use <code>zip-report.zip</code>.</p>
</body>
</html>
EOF

host_address="$(detect_host_address)"

cat > "$README_PATH" <<EOF
HTML Previewer browser delivery helper

Generated files:
- $INDEX_PATH
- $OUTPUT_ROOT/HTMLPreviewerValidationSamples.zip
- $OUTPUT_ROOT/HTMLPreviewerValidationSamples/

To serve the files:
1. Keep this Mac and the iPhone on the same network.
2. Run: scripts/serve-validation-samples.sh
3. Open: http://$host_address:$PORT/
4. Download or share the individual sample files on the iPhone.
5. Record results in physical-device-validation-result-template.md.

The Safari download row in the validation matrix should use the individual
downloaded files, not this README and not the outer distribution ZIP.
EOF

printf 'Prepared validation download page: %s\n' "$INDEX_PATH"
printf 'Prepared browser delivery notes: %s\n' "$README_PATH"
printf 'Local URL: http://localhost:%s/\n' "$PORT"
printf 'Device URL: http://%s:%s/\n' "$host_address" "$PORT"

if [[ "$PREPARE_ONLY" == true ]]; then
  exit 0
fi

printf 'Serving validation samples from %s\n' "$OUTPUT_ROOT"
printf 'Press Ctrl+C to stop the server.\n'
cd "$OUTPUT_ROOT"
python3 -m http.server "$PORT" --bind "$BIND_HOST"
