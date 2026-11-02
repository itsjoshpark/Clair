#!/bin/bash
# Tests for verify-app.sh. Run directly: ./scripts/verify-app.test.sh
#
# Builds small fake app bundles with real Mach-O executables (needs clang from
# Xcode or the Command Line Tools).

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
verify="$script_dir/verify-app.sh"

failures=0
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

check() {
  local description="$1" condition="$2"
  if [[ "$condition" == "pass" ]]; then
    echo "ok       $description"
  else
    echo "FAIL     $description"
    failures=$((failures + 1))
  fi
}

echo 'int main(void) { return 0; }' >"$workdir/main.c"
cc -arch arm64 -o "$workdir/arm64.bin" "$workdir/main.c" || exit 1
cc -arch arm64 -arch x86_64 -o "$workdir/universal.bin" "$workdir/main.c" || exit 1

write_plist() {
  local plist="$1" id="$2" name="$3" min="$4"
  mkdir -p "$(dirname "$plist")"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $id" \
    -c "Add :CFBundleName string $name" \
    -c "Add :CFBundleExecutable string $name" "$plist" >/dev/null
  if [[ -n "$min" ]]; then
    /usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string $min" "$plist" >/dev/null
  fi
}

# make_app DIR NAME ID NAME_KEY MIN HELPER_ID BINARY
make_app() {
  local dir="$1" name="$2" id="$3" bundle_name="$4" min="$5" helper_id="$6" binary="$7"
  local app="$dir/$name.app"
  rm -rf "$dir"
  mkdir -p "$app/Contents/MacOS"
  write_plist "$app/Contents/Info.plist" "$id" "$bundle_name" "$min"
  cp "$workdir/arm64.bin" "$app/Contents/MacOS/$bundle_name"
  local framework="$app/Contents/Frameworks/$bundle_name Framework.framework/Versions/A"
  mkdir -p "$framework/Helpers"
  cp "$workdir/$binary" "$framework/$bundle_name Framework"
  local helper="$framework/Helpers/$bundle_name Helper.app"
  write_plist "$helper/Contents/Info.plist" "$helper_id" "$bundle_name Helper" ""
  mkdir -p "$helper/Contents/MacOS"
  cp "$workdir/arm64.bin" "$helper/Contents/MacOS/$bundle_name Helper"
  echo "not a binary" >"$app/Contents/README.txt"
  echo "$app"
}

expect() {
  local description="$1" expected="$2" app="$3" message="${4-}"
  local output status
  output="$("$verify" "$app" 2>&1)"
  status=$?
  if [[ "$expected" == "pass" && $status -eq 0 ]]; then
    check "$description" pass
  elif [[ "$expected" == "fail" && $status -ne 0 && "$output" == *"$message"* ]]; then
    check "$description" pass
  else
    check "$description" fail
    echo "$output" | sed 's/^/         /'
  fi
}

good="$(make_app "$workdir/good" Clair dev.joshuapark.Clair Clair 15.6 dev.joshuapark.Clair.helper arm64.bin)"
expect "a correct Clair.app passes" pass "$good"

app="$(make_app "$workdir/chromium" Chromium org.chromium.Chromium Chromium 13.0 org.chromium.Chromium.helper arm64.bin)"
expect "an unbranded Chromium.app fails on its name" fail "$app" "expected Clair.app"
expect "an unbranded Chromium.app fails on its identifier" fail "$app" "expected dev.joshuapark.Clair"
expect "an unbranded Chromium.app fails on CFBundleName" fail "$app" "which names Chromium"
expect "an unbranded Chromium.app fails on helper identifiers" fail "$app" "helper"

app="$(make_app "$workdir/minos" Clair dev.joshuapark.Clair Clair 13.0 dev.joshuapark.Clair.helper arm64.bin)"
expect "a wrong minimum macOS version fails" fail "$app" "LSMinimumSystemVersion is '13.0'"

app="$(make_app "$workdir/nomin" Clair dev.joshuapark.Clair Clair "" dev.joshuapark.Clair.helper arm64.bin)"
expect "a missing minimum macOS version fails" fail "$app" "LSMinimumSystemVersion is ''"

app="$(make_app "$workdir/helper" Clair dev.joshuapark.Clair Clair 15.6 org.chromium.Chromium.helper arm64.bin)"
expect "a helper with a foreign identifier fails" fail "$app" "Clair Helper.app has identifier 'org.chromium.Chromium.helper'"

app="$(make_app "$workdir/universal" Clair dev.joshuapark.Clair Clair 15.6 dev.joshuapark.Clair.helper universal.bin)"
expect "a universal (x86_64 + arm64) binary fails" fail "$app" "expected only arm64"

app="$(make_app "$workdir/sparkle" Clair dev.joshuapark.Clair Clair 15.6 dev.joshuapark.Clair.helper arm64.bin)"
updater="$app/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
write_plist "$updater/Contents/Info.plist" org.sparkle-project.Sparkle.Updater Updater ""
expect "Sparkle's Updater.app keeps Sparkle's identifier" pass "$app" "helper apps use"

app="$(make_app "$workdir/stray" Clair dev.joshuapark.Clair Clair 15.6 dev.joshuapark.Clair.helper arm64.bin)"
stray="$app/Contents/Frameworks/Other.framework/Updater.app"
write_plist "$stray/Contents/Info.plist" org.sparkle-project.Sparkle.Updater Updater ""
expect "an app outside Sparkle.framework still needs Clair's prefix" fail "$app" "Updater.app has identifier"

if "$verify" "$workdir/missing.app" >/dev/null 2>&1; then
  check "rejects a missing app" fail
else
  check "rejects a missing app" pass
fi

echo
if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
