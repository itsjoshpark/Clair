#!/bin/bash
# Renders the DMG window's background from its SVG into one TIFF holding the 1x
# and 2x images, which Finder picks between for the display (style-release-dmg
# design D3).
#
#   render-dmg-background.sh resources/dmg/background.svg resources/dmg/background.tiff
#
# The 1x image is the SVG's own size in points, and the 2x image twice that.
# The output is replaced only once both have rendered and joined.

set -euo pipefail

svg="${1-}"
out="${2-}"

die() {
  echo "render-dmg-background: $1" >&2
  exit 1
}

[[ $# -eq 2 && -n "$svg" && -n "$out" ]] ||
  die "usage: render-dmg-background.sh <background.svg> <background.tiff>"
[[ -f "$svg" ]] || die "no SVG at $svg"
[[ "$out" == *.tiff ]] || die "the output must be a .tiff: $out"
command -v rsvg-convert >/dev/null ||
  die "rsvg-convert is not installed. Run: brew install librsvg"
command -v tiffutil >/dev/null || die "no tiffutil; it comes with macOS"

work="$(mktemp -d "${TMPDIR:-/tmp}/render-dmg-background.XXXXXX")"
trap 'rm -rf "$work"' EXIT

pixel_size() {
  local width height
  width="$(sips -g pixelWidth "$1" 2>/dev/null | awk '/pixelWidth/ { print $2 }')"
  height="$(sips -g pixelHeight "$1" 2>/dev/null | awk '/pixelHeight/ { print $2 }')"
  echo "${width}x${height}"
}

rsvg-convert --zoom 1 --output "$work/background.png" "$svg" || die "rsvg-convert couldn't render $svg"
rsvg-convert --zoom 2 --output "$work/background@2x.png" "$svg" || die "rsvg-convert couldn't render $svg at 2x"
one="$(pixel_size "$work/background.png")"
two="$(pixel_size "$work/background@2x.png")"
[[ "$one" =~ ^([1-9][0-9]*)x([1-9][0-9]*)$ ]] || die "couldn't read the size of the 1x render"
[[ "$two" == "$((BASH_REMATCH[1] * 2))x$((BASH_REMATCH[2] * 2))" ]] ||
  die "the 2x render is $two, not twice the 1x render's $one"

# -cathidpicheck marks the second image as the first's 2x version.
tiffutil -cathidpicheck "$work/background.png" "$work/background@2x.png" -out "$work/background.tiff" >/dev/null 2>&1 ||
  die "tiffutil couldn't join the renders"
mkdir -p "$(dirname "$out")"
mv "$work/background.tiff" "$out"
echo "rendered $out ($one and $two)"
