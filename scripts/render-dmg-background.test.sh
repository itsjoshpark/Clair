#!/bin/bash
# Tests for render-dmg-background.sh. Run directly: ./scripts/render-dmg-background.test.sh
#
# Requires rsvg-convert (brew install librsvg) and python3.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
render="$script_dir/render-dmg-background.sh"
dmg="$script_dir/../resources/dmg"

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

# The images in a TIFF, as "WxH" lines.
tiff_sizes() {
  tiffutil -info "$1" 2>/dev/null | sed -n 's/^ *Image Width: \([0-9]*\) Image Length: \([0-9]*\)$/\1x\2/p'
}

window="$(python3 -I -c 'import json, sys; w = json.load(open(sys.argv[1]))["window"]; print(w["width"], w["height"])' "$dmg/layout.json")"
read -r width height <<<"$window"
expected="$(printf '%sx%s\n%sx%s' "$width" "$height" "$((width * 2))" "$((height * 2))")"

# --- the committed files ------------------------------------------------------------
if [[ "$(tiff_sizes "$dmg/background.tiff")" == "$expected" ]]; then
  check "the committed background.tiff holds ${width}x$height and $((width * 2))x$((height * 2)) images" pass
else
  check "the committed background.tiff holds ${width}x$height and $((width * 2))x$((height * 2)) images" fail
  tiff_sizes "$dmg/background.tiff" | sed 's/^/         got: /'
fi

if python3 -I "$dmg/make_background.py" --out "$workdir/background.svg" >/dev/null \
    && cmp -s "$workdir/background.svg" "$dmg/background.svg"; then
  check "the committed background.svg is what make_background.py writes" pass
else
  check "the committed background.svg is what make_background.py writes" fail
fi

# --- rendering ----------------------------------------------------------------------
out="$workdir/out/background.tiff"
if "$render" "$dmg/background.svg" "$out" >/dev/null 2>&1 && [[ "$(tiff_sizes "$out")" == "$expected" ]]; then
  check "renders the SVG at 1x and 2x into one TIFF" pass
else
  check "renders the SVG at 1x and 2x into one TIFF" fail
fi

resolutions="$(tiffutil -info "$out" 2>/dev/null | sed -n 's/^ *Resolution: \([0-9]*\), [0-9]*$/\1/p' | tr '\n' ' ')"
if [[ "$resolutions" == "72 144 " ]]; then
  check "marks the second image as the 2x one" pass
else
  check "marks the second image as the 2x one (resolutions: $resolutions)" fail
fi

# Byte-for-byte equality with the committed render would depend on the librsvg
# version, so only the sizes are compared, above.

# --- failures -------------------------------------------------------------------------
if "$render" "$workdir/missing.svg" "$workdir/missing/background.tiff" 2>"$workdir/err" >/dev/null; then
  check "fails when the SVG is missing" fail
elif grep -q "no SVG at" "$workdir/err" && [[ ! -e "$workdir/missing" ]]; then
  check "fails when the SVG is missing, writing nothing" pass
else
  check "fails when the SVG is missing, writing nothing" fail
fi

if PATH="/usr/bin:/bin" "$render" "$dmg/background.svg" "$workdir/no-rsvg/background.tiff" 2>"$workdir/err" >/dev/null; then
  check "fails without rsvg-convert" fail
elif grep -q "brew install librsvg" "$workdir/err" && [[ ! -e "$workdir/no-rsvg" ]]; then
  check "fails without rsvg-convert, naming the fix and writing nothing" pass
else
  check "fails without rsvg-convert, naming the fix and writing nothing" fail
fi

echo '<svg xmlns="http://www.w3.org/2000/svg"' >"$workdir/broken.svg"
cp "$out" "$workdir/kept.tiff"
if ! "$render" "$workdir/broken.svg" "$workdir/kept.tiff" >/dev/null 2>&1 && cmp -s "$out" "$workdir/kept.tiff"; then
  check "a failed render leaves the earlier TIFF in place" pass
else
  check "a failed render leaves the earlier TIFF in place" fail
fi

if ! "$render" "$dmg/background.svg" "$workdir/background.png" >/dev/null 2>&1; then
  check "refuses an output that isn't a .tiff" pass
else
  check "refuses an output that isn't a .tiff" fail
fi

if ! "$render" >/dev/null 2>&1 && ! "$render" "$dmg/background.svg" >/dev/null 2>&1; then
  check "requires an SVG and an output" pass
else
  check "requires an SVG and an output" fail
fi

echo
if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
