#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

xcodebuild -quiet build \
  -project "$ROOT_DIR/HTMLMarkdownPreviewer.xcodeproj" \
  -scheme HTMLMarkdownPreviewer \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$ROOT_DIR/DerivedData" \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO
