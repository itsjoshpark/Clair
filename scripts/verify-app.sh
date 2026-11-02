#!/bin/bash
# Checks the static properties a shipped Clair.app must have, and prints every
# failure before exiting non-zero.
#
#   verify-app.sh path/to/Clair.app
#
# Identity checks (app-identity spec): the bundle name and identifier, helper
# identifiers, no Chromium product name in the bundle names, the minimum macOS
# version, and arm64-only Mach-O files.

set -uo pipefail

bundle_id="dev.joshuapark.Clair"
min_system_version="15.6"

app="${1-}"
failures=0

fail() {
  echo "FAIL     $1"
  failures=$((failures + 1))
}

pass() {
  echo "ok       $1"
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null
}

[[ -n "$app" ]] || { echo "usage: verify-app.sh path/to/Clair.app" >&2; exit 2; }
[[ -d "$app" ]] || { echo "verify-app: not a directory: $app" >&2; exit 2; }
app="${app%/}"
info="$app/Contents/Info.plist"
[[ -f "$info" ]] || { echo "verify-app: missing $info" >&2; exit 2; }

if [[ "$(basename "$app")" == "Clair.app" ]]; then
  pass "bundle is named Clair.app"
else
  fail "bundle is named $(basename "$app"), expected Clair.app"
fi

actual_id="$(plist_value "$info" CFBundleIdentifier)"
if [[ "$actual_id" == "$bundle_id" ]]; then
  pass "CFBundleIdentifier is $bundle_id"
else
  fail "CFBundleIdentifier is '$actual_id', expected $bundle_id"
fi

for key in CFBundleName CFBundleDisplayName; do
  value="$(plist_value "$info" "$key")"
  if [[ "$value" == *Chromium* || "$value" == *Chrome* ]]; then
    fail "$key is '$value', which names Chromium"
  else
    pass "$key ('${value}') does not name Chromium"
  fi
done

actual_min="$(plist_value "$info" LSMinimumSystemVersion)"
if [[ "$actual_min" == "$min_system_version" ]]; then
  pass "LSMinimumSystemVersion is $min_system_version"
else
  fail "LSMinimumSystemVersion is '$actual_min', expected $min_system_version"
fi

helpers=0
bad_helpers=0
while IFS= read -r -d '' helper; do
  helpers=$((helpers + 1))
  helper_id="$(plist_value "$helper/Contents/Info.plist" CFBundleIdentifier)"
  if [[ "$helper_id" != "$bundle_id."* ]]; then
    fail "helper $(basename "$helper") has identifier '$helper_id', expected a $bundle_id. prefix"
    bad_helpers=$((bad_helpers + 1))
  fi
done < <(find "$app/Contents" -path "$app/Contents/Frameworks/Sparkle.framework" -prune \
           -o -name '*.app' -type d -print0)
# Sparkle's Updater.app keeps Sparkle's own identifier: it is Sparkle's code,
# embedded unchanged and signed as itself.
if (( bad_helpers == 0 )); then
  pass "all $helpers helper apps use the $bundle_id. prefix"
fi

machos=0
bad_machos=0
while IFS= read -r -d '' file; do
  [[ -L "$file" ]] && continue
  file -b "$file" | grep -q 'Mach-O' || continue
  machos=$((machos + 1))
  archs="$(lipo -archs "$file" 2>/dev/null)"
  if [[ "$archs" != "arm64" ]]; then
    fail "${file#"$app"/} has architectures '$archs', expected only arm64"
    bad_machos=$((bad_machos + 1))
  fi
done < <(find "$app" -type f -print0)
if (( machos == 0 )); then
  fail "no Mach-O files found"
elif (( bad_machos == 0 )); then
  pass "all $machos Mach-O files are arm64 only"
fi

echo
if (( failures > 0 )); then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
