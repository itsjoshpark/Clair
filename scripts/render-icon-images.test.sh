#!/bin/bash
# Tests for render-icon-images.sh. Run directly: ./scripts/render-icon-images.test.sh
#
# Requires rsvg-convert: brew install librsvg

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
render="$script_dir/render-icon-images.sh"
icons="$script_dir/../resources/icon"

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

pixel_size() {
  local width height
  width="$(sips -g pixelWidth "$1" 2>/dev/null | awk '/pixelWidth/ { print $2 }')"
  height="$(sips -g pixelHeight "$1" 2>/dev/null | awk '/pixelHeight/ { print $2 }')"
  echo "${width}x${height}"
}

reject() {
  local description="$1" contents="$2"
  printf '%s\n' "$contents" >"$workdir/bad.txt"
  if "$render" "$workdir/bad.txt" "$icons" "$workdir/bad-out" >/dev/null 2>&1; then
    check "$description" fail
  else
    check "$description" pass
  fi
  [[ ! -e "$workdir/bad-out" ]] || { check "$description: wrote nothing" fail; rm -rf "$workdir/bad-out"; }
}

# --- the real list ----------------------------------------------------------
out="$workdir/logos"
if "$render" "$icons/product-logos.txt" "$icons" "$out" >/dev/null 2>&1; then
  check "renders the real product-logos.txt" pass
else
  check "renders the real product-logos.txt" fail
fi

rendered=0
while read -r source size destination; do
  [[ -z "${source-}" || "$source" == \#* || "$size" == "-" ]] && continue
  rendered=$((rendered + 1))
  actual="$(pixel_size "$out/$destination")"
  if [[ "$actual" == "$size" ]]; then
    check "$destination is $size" pass
  else
    check "$destination is $size (got ${actual:-nothing})" fail
  fi
done <"$icons/product-logos.txt"
if [[ "$rendered" -gt 0 ]]; then
  check "the list has PNG entries" pass
else
  check "the list has PNG entries" fail
fi

if [[ -z "$(find "$out" -name '*.icon' -o -name '*.svg')" ]]; then
  check "copy-only entries are not rendered" pass
else
  check "copy-only entries are not rendered" fail
fi

# --- every listed PNG is committed at its size ------------------------------
# Byte-for-byte equality with a fresh render would depend on the librsvg version.
missing=0
while read -r source size destination; do
  [[ -z "${source-}" || "$source" == \#* || "$size" == "-" ]] && continue
  [[ "$(pixel_size "$icons/logos/$destination")" == "$size" ]] || missing=$((missing + 1))
done <"$icons/product-logos.txt"
if [[ "$missing" -eq 0 ]]; then
  check "every listed PNG is committed in resources/icon/logos at its size" pass
else
  check "every listed PNG is committed in resources/icon/logos at its size ($missing missing or wrong)" fail
fi

# --- bad input --------------------------------------------------------------
reject "rejects a missing source" "nope.svg 16x16 a/b.png"
reject "rejects a malformed size" "logo.svg 16 a/b.png"
reject "rejects a zero size" "logo.svg 0x16 a/b.png"
reject "rejects a missing field" "logo.svg 16x16"
reject "rejects an extra field" "logo.svg 16x16 a/b.png extra"
reject "rejects a parent-directory destination" "logo.svg 16x16 ../b.png"
reject "rejects an absolute destination" "logo.svg 16x16 /tmp/b.png"
reject "rejects shell characters" 'logo.svg 16x16 a/$(id).png'
reject "rejects rendering to a non-PNG" "logo.svg 16x16 a/b.svg"
reject "rejects a list with nothing to render" "logo.svg - a/b.svg"
reject "rejects a bad line after a good one" "logo.svg 16x16 a/b.png
logo.svg 16x16 ../c.png"

if "$render" "$workdir/missing.txt" "$icons" "$workdir/x" >/dev/null 2>&1; then
  check "rejects a missing list" fail
else
  check "rejects a missing list" pass
fi

if PATH="/usr/bin:/bin" "$render" "$icons/product-logos.txt" "$icons" "$workdir/x" 2>"$workdir/err" >/dev/null; then
  check "fails without rsvg-convert" fail
else
  grep -q "brew install librsvg" "$workdir/err" && check "fails without rsvg-convert, naming the fix" pass ||
    check "fails without rsvg-convert, naming the fix" fail
fi

echo
if [[ "$failures" -eq 0 ]]; then
  echo "All render-icon-images tests passed."
else
  echo "$failures render-icon-images test(s) failed."
fi
exit "$failures"
