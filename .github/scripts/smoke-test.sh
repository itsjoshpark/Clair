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

# With the default profile location, Clair must use its own data directory.
# Only meaningful for the branded app; the runner is a fresh machine.
if [[ "$(basename "$app")" == "Clair.app" ]]; then
  support="$HOME/Library/Application Support"
  if [[ -e "$support/Clair" ]]; then
    echo "::error::$support/Clair already exists before the first launch"
    exit 1
  fi
  # Headless mode would use a temporary profile, so launch the app normally
  # (the runner has a GUI session) until the default profile appears.
  "$app/Contents/MacOS/$executable" --no-first-run --use-mock-keychain \
    --no-default-browser-check about:blank >/dev/null 2>&1 &
  browser_pid=$!
  for _ in $(seq 1 60); do
    [[ -d "$support/Clair/Default" ]] && break
    sleep 1
  done
  kill "$browser_pid" 2>/dev/null || true
  wait "$browser_pid" 2>/dev/null || true
  if [[ ! -d "$support/Clair/Default" ]]; then
    echo "::error::The default profile was not created in $support/Clair"
    ls -la "$support"
    exit 1
  fi
  if [[ -e "$support/Chromium" ]]; then
    echo "::error::Clair created a Chromium data directory at $support/Chromium"
    exit 1
  fi
  echo "The default profile was created in $support/Clair."
fi

mkdir -p "$output_dir"
ditto -c -k --keepParent "$app" "$output_dir/$(basename "$app" .app)-unsigned.zip"
ls -lh "$output_dir"
