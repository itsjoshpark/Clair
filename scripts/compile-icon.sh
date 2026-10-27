#!/bin/bash
# Compiles Clair's Icon Composer document into the two files Chromium's macOS
# bundle takes its icon from (design D3 and D4 of the design-app-icon change).
#
#   compile-icon.sh resources/icon/AppIcon.icon out/
#     ->  out/Assets.car   asset catalog: macOS 26 appearances plus pre-Tahoe images
#         out/app.icns     classic icon file, named as Chromium's Info.plist expects
#
# Needs Xcode 26 or later, whose actool reads .icon documents.

set -euo pipefail

source_icon="${1-}"
out_dir="${2-}"

die() {
  echo "compile-icon: $1" >&2
  exit 1
}

[[ -n "$source_icon" && -n "$out_dir" ]] || die "usage: compile-icon.sh <AppIcon.icon> <out-dir>"
[[ "$(basename "$source_icon")" == "AppIcon.icon" ]] ||
  die "the source must be named AppIcon.icon, the icon name Chromium's Info.plist uses: $source_icon"
[[ -d "$source_icon" ]] || die "Icon Composer document not found: $source_icon"
[[ -f "$source_icon/icon.json" ]] || die "$source_icon has no icon.json"
plutil -convert xml1 -o /dev/null "$source_icon/icon.json" 2>/dev/null ||
  die "$source_icon/icon.json is not valid JSON"

actool="$(xcrun --find actool 2>/dev/null)" ||
  die "actool was not found. Install Xcode 26 or later and select it with xcode-select."

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if ! "$actool" "$source_icon" \
  --compile "$work" \
  --platform macosx \
  --minimum-deployment-target 15.6 \
  --app-icon AppIcon \
  --output-partial-info-plist "$work/partial.plist" \
  --errors --warnings --output-format human-readable-text >"$work/actool.log" 2>&1; then
  cat "$work/actool.log" >&2
  die "actool could not compile $source_icon"
fi

[[ -f "$work/Assets.car" && -f "$work/AppIcon.icns" ]] || {
  cat "$work/actool.log" >&2
  die "actool did not write Assets.car and AppIcon.icns"
}

mkdir -p "$out_dir"
mv "$work/Assets.car" "$out_dir/Assets.car"
mv "$work/AppIcon.icns" "$out_dir/app.icns"
echo "compiled $out_dir/Assets.car and $out_dir/app.icns"
