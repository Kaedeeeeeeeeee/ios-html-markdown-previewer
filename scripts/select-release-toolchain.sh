#!/usr/bin/env bash
# Source this before a release build, or run with --github-env in GitHub Actions.
# Select by reported versions, not the app filename. Never change xcode-select.
set -euo pipefail

select_release_toolchain() {
  local candidate xcode_info xcode_version xcode_build sdk sdk_version sdk_report valid
  local candidates=()
  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    candidates=("$DEVELOPER_DIR")
  else
    candidates=(/Applications/Xcode*.app/Contents/Developer)
  fi

  for candidate in "${candidates[@]}"; do
    [[ -d "$candidate" ]] || continue
    xcode_info="$(DEVELOPER_DIR="$candidate" xcodebuild -version 2>/dev/null)" || continue
    xcode_version="$(printf '%s\n' "$xcode_info" | awk 'NR == 1 { print $2 }')"
    [[ "$xcode_version" =~ ^27\.1(\.[0-9]+)?$ ]] || continue
    xcode_build="$(printf '%s\n' "$xcode_info" | awk 'NR == 2 { print $3 }')"
    if [[ -n "${RELEASE_XCODE_BUILD:-}" && "$xcode_build" != "$RELEASE_XCODE_BUILD" ]]; then
      printf '%s has Xcode build %s; this operation requires %s.\n' "$candidate" "$xcode_build" "$RELEASE_XCODE_BUILD" >&2
      continue
    fi
    valid=true
    sdk_report=""
    for sdk in iphoneos iphonesimulator; do
      sdk_version="$(DEVELOPER_DIR="$candidate" xcrun --sdk "$sdk" --show-sdk-version 2>/dev/null)" || sdk_version="unavailable"
      if [[ ! "$sdk_version" =~ ^27\.1(\.[0-9]+)?$ ]]; then
        printf '%s has unsupported %s SDK %s; release 1.8.1 requires 27.1.\n' "$candidate" "$sdk" "$sdk_version" >&2
        valid=false
        break
      fi
      sdk_report="$sdk_report$sdk SDK $sdk_version"$'\n'
    done
    if [[ "$valid" == true ]]; then
      export DEVELOPER_DIR="$candidate"
      printf 'Release toolchain: %s\n%s\n%s' "$DEVELOPER_DIR" "$xcode_info" "$sdk_report"
      return 0
    fi
  done

  printf 'Xcode 27.1 with iPhoneOS and iPhoneSimulator SDK 27.1 is required. Install it on this runner or set DEVELOPER_DIR to a matching installation; no older SDK fallback is allowed.\n' >&2
  if [[ -n "${RELEASE_XCODE_BUILD:-}" ]]; then
    printf 'Required Xcode build: %s.\n' "$RELEASE_XCODE_BUILD" >&2
  fi
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-}" in
    "") ;;
    --github-env)
      [[ -n "${GITHUB_ENV:-}" ]] || { printf 'GITHUB_ENV is required.\n' >&2; exit 2; }
      ;;
    *) printf 'Usage: %s [--github-env]\n' "$0" >&2; exit 2 ;;
  esac
  select_release_toolchain
  if [[ "${1:-}" == --github-env ]]; then
    printf 'DEVELOPER_DIR=%s\n' "$DEVELOPER_DIR" >> "$GITHUB_ENV"
  fi
else
  select_release_toolchain
fi
