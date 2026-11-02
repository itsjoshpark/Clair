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
support="$HOME/Library/Application Support"

# The runner is a fresh machine, so the branded app's data directory must not
# exist yet. Check before the first launch: every launch, also the headless one
# with --user-data-dir, creates Crashpad/ in the default data directory
# (chrome_paths.cc, DIR_CRASH_DUMPS).
if [[ "$(basename "$app")" == "Clair.app" && -e "$support/Clair" ]]; then
  echo "::error::$support/Clair already exists before the first launch"
  exit 1
fi

profile_dir="$(mktemp -d)"
dom="$("$app/Contents/MacOS/$executable" --headless=new --no-first-run \
  --user-data-dir="$profile_dir" --disable-gpu --use-mock-keychain \
  --dump-dom 'data:text/html,<title>smoke</title><p id="smoke">rendered</p>' 2>/dev/null)"
rm -rf "$profile_dir"

if ! grep -q '<p id="smoke">rendered</p>' <<<"$dom"; then
  echo "::error::$(basename "$app") did not render the smoke-test page"
  echo "$dom"
  exit 1
fi
echo "$(basename "$app") rendered the smoke-test page."

# With the default profile location, Clair must use its own data directory.
# Only meaningful for the branded app.
if [[ "$(basename "$app")" == "Clair.app" ]]; then
  # Headless mode would use a temporary profile, so launch the app normally
  # (the runner has a GUI session) until the default profile appears.
  # Its log shows whether the native-layer hook ran (task 9.2).
  browser_log="$(mktemp)"
  "$app/Contents/MacOS/$executable" --no-first-run --use-mock-keychain \
    --no-default-browser-check --enable-logging=stderr about:blank \
    >"$browser_log" 2>&1 &
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

  # A bare engine has no ClairUI.framework: the hook must log that and carry on.
  if ! grep -q "ClairUI: no framework at .*/Contents/Frameworks/ClairUI.framework; running without the native layer" "$browser_log"; then
    echo "::error::The engine did not log the missing ClairUI.framework"
    grep -i clairui "$browser_log" || tail -20 "$browser_log"
    rm -f "$browser_log"
    exit 1
  fi
  echo "The engine logged the missing ClairUI.framework and carried on."
  rm -f "$browser_log"
fi

mkdir -p "$output_dir"
ditto -c -k --keepParent "$app" "$output_dir/$(basename "$app" .app)-unsigned.zip"
ls -lh "$output_dir"
