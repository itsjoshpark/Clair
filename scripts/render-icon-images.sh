#!/bin/bash
# Renders Clair's product logo PNGs from their SVG sources, following a list
# such as resources/icon/product-logos.txt.
#
#   render-icon-images.sh resources/icon/product-logos.txt resources/icon resources/icon/logos
#
# Each list line is "<source> <size> <destination>". Lines whose size is WxH are
# rendered to <out-dir>/<destination>; lines whose size is "-" are copied as
# they are by the build and skipped here. Blank lines and # comments are ignored.

set -euo pipefail

list="${1-}"
icon_dir="${2-}"
out_dir="${3-}"

die() {
  echo "render-icon-images: $1" >&2
  exit 1
}

[[ -n "$list" && -n "$icon_dir" && -n "$out_dir" ]] ||
  die "usage: render-icon-images.sh <list> <icon-dir> <out-dir>"
[[ -f "$list" ]] || die "list not found: $list"
[[ -d "$icon_dir" ]] || die "icon directory not found: $icon_dir"

command -v rsvg-convert >/dev/null ||
  die "rsvg-convert is not installed. Run: brew install librsvg"

# Validate every line before rendering anything, so a bad list changes nothing.
entries=()
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
  [[ -f "$icon_dir/$source" ]] || die "$list:$line_number: source not found: $icon_dir/$source"

  if [[ "$size" == "-" ]]; then
    continue
  fi
  [[ "$size" =~ ^[1-9][0-9]{0,3}x[1-9][0-9]{0,3}$ ]] ||
    die "$list:$line_number: size must be WxH or -: $size"
  [[ "$source" == *.svg && "$destination" == *.png ]] ||
    die "$list:$line_number: rendered entries go from .svg to .png"
  entries+=("$source $size $destination")
done <"$list"

[[ ${#entries[@]} -gt 0 ]] || die "$list has nothing to render"

for entry in "${entries[@]}"; do
  read -r source size destination <<<"$entry"
  mkdir -p "$out_dir/$(dirname "$destination")"
  rsvg-convert --width "${size%x*}" --height "${size#*x}" \
    --output "$out_dir/$destination" "$icon_dir/$source" ||
    die "rsvg-convert could not render $source at $size"
  echo "rendered $destination ($size)"
done
