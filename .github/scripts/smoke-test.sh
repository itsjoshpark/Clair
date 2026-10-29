#!/usr/bin/env bash
# Smoke-test a finished build: launch the app headless, load a page and check
# the rendered DOM, then zip the app for download.
#
# Usage: smoke-test.sh OUTPUT_DIR

set -euo pipefail

root_dir="${GITHUB_WORKSPACE:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)}"
out_dir="$root_dir/build/src/out/Default"
output_dir="$1"

app=""
for candidate in "$out_dir/Clair.app" "$out_dir/Chromium.app"; do
  if [[ -d "$candidate" ]]; then
    app="$candidate"
    break
  fi
done
if [[ -z "$app" ]]; then
  echo "::error::No built app found in $out_dir"
  exit 1
fi

executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")"
profile_dir="$(mktemp -d)"
dom="$("$app/Contents/MacOS/$executable" --headless=new --no-first-run \
  --user-data-dir="$profile_dir" --disable-gpu \
  --dump-dom 'data:text/html,<title>smoke</title><p id="smoke">rendered</p>' 2>/dev/null)"
rm -rf "$profile_dir"

if ! grep -q '<p id="smoke">rendered</p>' <<<"$dom"; then
  echo "::error::$(basename "$app") did not render the smoke-test page"
  echo "$dom"
  exit 1
fi
echo "$(basename "$app") rendered the smoke-test page."

mkdir -p "$output_dir"
ditto -c -k --keepParent "$app" "$output_dir/$(basename "$app" .app)-unsigned.zip"
ls -lh "$output_dir"
