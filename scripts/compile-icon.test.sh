#!/bin/bash
# Tests for compile-icon.sh. Run directly: ./scripts/compile-icon.test.sh
#
# Requires Xcode 26 or later (actool with .icon support).

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
compile="$script_dir/compile-icon.sh"
source_icon="$script_dir/../resources/icon/AppIcon.icon"

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

reject() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    check "$description" fail
  else
    check "$description" pass
  fi
}

# --- the real source --------------------------------------------------------
out="$workdir/out"
if "$compile" "$source_icon" "$out" >/dev/null 2>&1; then
  check "compiles resources/icon/AppIcon.icon" pass
else
  check "compiles resources/icon/AppIcon.icon" fail
fi

if [[ -f "$out/Assets.car" ]] && xcrun assetutil --info "$out/Assets.car" 2>/dev/null | grep -q '"Name" : "AppIcon"'; then
  check "Assets.car holds an AppIcon" pass
else
  check "Assets.car holds an AppIcon" fail
fi

if [[ -f "$out/app.icns" ]] && iconutil -c iconset -o "$workdir/app.iconset" "$out/app.icns" 2>/dev/null; then
  check "app.icns converts back to an iconset" pass
else
  check "app.icns converts back to an iconset" fail
fi
for image in icon_16x16.png icon_128x128@2x.png; do
  if [[ -f "$workdir/app.iconset/$image" ]]; then
    check "app.icns includes $image" pass
  else
    check "app.icns includes $image" fail
  fi
done

if [[ ! -e "$out/AppIcon.icns" && ! -e "$out/partial.plist" ]]; then
  check "writes only Assets.car and app.icns" pass
else
  check "writes only Assets.car and app.icns" fail
fi

# --- bad input --------------------------------------------------------------
reject "rejects missing arguments" "$compile"
reject "rejects a missing source" "$compile" "$workdir/AppIcon.icon" "$workdir/x"

mkdir -p "$workdir/Other.icon"
cp "$source_icon/icon.json" "$workdir/Other.icon/"
reject "rejects a source not named AppIcon.icon" "$compile" "$workdir/Other.icon" "$workdir/x"

mkdir -p "$workdir/empty/AppIcon.icon"
reject "rejects a document without icon.json" "$compile" "$workdir/empty/AppIcon.icon" "$workdir/x"

mkdir -p "$workdir/broken/AppIcon.icon"
printf '{ "groups" : [ \n' >"$workdir/broken/AppIcon.icon/icon.json"
reject "rejects malformed icon.json" "$compile" "$workdir/broken/AppIcon.icon" "$workdir/x"

if DEVELOPER_DIR="$workdir/no-xcode" "$compile" "$source_icon" "$workdir/x" 2>"$workdir/err" >/dev/null; then
  check "fails without actool" fail
else
  grep -q "Install Xcode" "$workdir/err" && check "fails without actool, naming the fix" pass ||
    check "fails without actool, naming the fix" fail
fi

[[ ! -e "$workdir/x" ]] && check "failed runs write nothing" pass || check "failed runs write nothing" fail

echo
if [[ "$failures" -eq 0 ]]; then
  echo "All compile-icon tests passed."
else
  echo "$failures compile-icon test(s) failed."
fi
exit "$failures"
