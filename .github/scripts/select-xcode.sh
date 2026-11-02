#!/usr/bin/env bash
# Selects Xcode on a GitHub-hosted xcode-27 runner and prints its path:
# /Applications/Xcode_$CLAIR_XCODE_VERSION.app when that is set, otherwise the
# newest Xcode 27 on the image. Clair's native layer needs Xcode 27.2 or later
# (its project is in Xcode's JSON format).

set -euo pipefail
shopt -s nullglob

xcode_path=""
if [[ -n "${CLAIR_XCODE_VERSION:-}" ]]; then
  xcode_path="/Applications/Xcode_${CLAIR_XCODE_VERSION}.app"
else
  candidates=()
  for candidate in /Applications/Xcode_27*.app; do
    # Images add symlinks such as Xcode_27.app next to the real bundles.
    [[ -L "$candidate" ]] || candidates+=("$candidate")
  done
  if [[ ${#candidates[@]} -gt 0 ]]; then
    xcode_path="$(printf '%s\n' "${candidates[@]}" | sort -V | tail -n 1)"
  elif [[ "$(defaults read /Applications/Xcode.app/Contents/Info CFBundleShortVersionString 2>/dev/null)" == 27.* ]]; then
    xcode_path="/Applications/Xcode.app"
  fi
fi

if [[ -z "$xcode_path" || ! -d "$xcode_path" ]]; then
  echo "::error::No Xcode ${CLAIR_XCODE_VERSION:-27} on this runner. Installed versions:" >&2
  ls -d /Applications/Xcode*.app >&2 || true
  exit 1
fi
# Xcode.app is often a symlink to one of the versioned bundles; print the real
# bundle, so callers that delete the other versions keep this one.
xcode_path="$(cd "$xcode_path" && pwd -P)"
sudo xcode-select --switch "$xcode_path"
xcodebuild -version >&2
echo "$xcode_path"
