#!/bin/bash
# Replaces Chromium's app icon and product logos with Clair's, in a patched
# Chromium source tree (change 1 design D2, design-app-icon design D3 to D6).
#
#   replace-icon-resources.sh build/src [resources/icon]
#
# Compiles <icon-dir>/AppIcon.icon with compile-icon.sh and copies Assets.car
# and app.icns into chrome/app/theme/chromium/mac/. Then copies every entry in
# <icon-dir>/product-logos.txt over its Chromium file: WxH entries from
# <icon-dir>/logos/<destination>, "-" entries from <icon-dir>/<source>.
# Every destination must already exist, so a Chromium update that moves a logo
# fails here and names the path. Nothing is copied unless every check passes.

set -euo pipefail

src_dir="${1-}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
icon_dir="${2-$script_dir/../resources/icon}"
list="$icon_dir/product-logos.txt"
mac_dir="chrome/app/theme/chromium/mac"

die() {
  echo "replace-icon-resources: $1" >&2
  exit 1
}

[[ -n "$src_dir" ]] || die "usage: replace-icon-resources.sh <chromium-src> [icon-dir]"
[[ -d "$src_dir" ]] || die "Chromium source not found: $src_dir"
[[ -d "$icon_dir" ]] || die "icon directory not found: $icon_dir"
[[ -f "$list" ]] || die "list not found: $list"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The compiled files come first; they are written by the compile step, which
# runs only after every destination has been checked.
sources=("$work/compiled/Assets.car" "$work/compiled/app.icns")
destinations=("$mac_dir/Assets.car" "$mac_dir/app.icns")
line_number=0
while IFS= read -r line || [[ -n "$line" ]]; do
  line_number=$((line_number + 1))
  [[ -z "${line//[[:space:]]/}" || "$line" =~ ^[[:space:]]*# ]] && continue

  read -r source size destination extra <<<"$line"
  [[ -n "${destination-}" && -z "${extra-}" ]] ||
    die "$list:$line_number: expected '<source> <size> <destination>'"
  for path in "$source" "$destination"; do
    [[ "$path" =~ ^[A-Za-z0-9_][A-Za-z0-9_./-]*$ && "/$path/" != */../* ]] ||
      die "$list:$line_number: unsafe path: $path"
  done

  if [[ "$size" == "-" ]]; then
    from="$icon_dir/$source"
  elif [[ "$size" =~ ^[1-9][0-9]{0,3}x[1-9][0-9]{0,3}$ ]]; then
    from="$icon_dir/logos/$destination"
  else
    die "$list:$line_number: size must be WxH or -: $size"
  fi
  [[ -f "$from" ]] || die "$list:$line_number: file to copy not found: $from"
  sources+=("$from")
  destinations+=("$destination")
done <"$list"

[[ ${#sources[@]} -gt 2 ]] || die "$list has no entries"

missing=0
for destination in "${destinations[@]}"; do
  if [[ ! -f "$src_dir/$destination" ]]; then
    echo "replace-icon-resources: not in the Chromium source: $destination" >&2
    missing=$((missing + 1))
  fi
done
[[ "$missing" -eq 0 ]] ||
  die "$missing destination(s) missing; update $list for this Chromium version"

"$script_dir/compile-icon.sh" "$icon_dir/AppIcon.icon" "$work/compiled"

i=0
while [[ "$i" -lt ${#sources[@]} ]]; do
  cp "${sources[$i]}" "$src_dir/${destinations[$i]}"
  echo "replaced ${destinations[$i]}"
  i=$((i + 1))
done
