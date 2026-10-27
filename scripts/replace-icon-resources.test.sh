#!/bin/bash
# Tests for replace-icon-resources.sh. Run directly: ./scripts/replace-icon-resources.test.sh
#
# Requires Xcode 26 or later (actool with .icon support), like compile-icon.sh.
# Uses a stand-in Chromium tree that holds only the files the script replaces.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
replace="$script_dir/replace-icon-resources.sh"
icon_dir="$script_dir/../resources/icon"
list="$icon_dir/product-logos.txt"
mac_dir="chrome/app/theme/chromium/mac"

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

# Prints each "<source> <size> <destination>" entry in product-logos.txt.
entries() {
  grep -v '^[[:space:]]*#' "$list" | awk 'NF == 3'
}

# Makes a stand-in Chromium tree with a placeholder at every destination.
make_tree() {
  local tree="$1" source size destination
  mkdir -p "$tree/$mac_dir"
  echo placeholder >"$tree/$mac_dir/Assets.car"
  echo placeholder >"$tree/$mac_dir/app.icns"
  while read -r source size destination; do
    mkdir -p "$tree/$(dirname "$destination")"
    echo placeholder >"$tree/$destination"
  done < <(entries)
}

# Expects a failing run whose error output contains a phrase.
reject() {
  local description="$1" phrase="$2"
  shift 2
  if "$@" >/dev/null 2>"$workdir/err"; then
    check "$description" fail
  elif grep -qF -- "$phrase" "$workdir/err"; then
    check "$description" pass
  else
    check "$description (error did not name: $phrase)" fail
  fi
}

# --- the real resources -----------------------------------------------------
tree="$workdir/src"
make_tree "$tree"
if "$replace" "$tree" >"$workdir/log" 2>&1; then
  check "replaces the resources in a complete tree" pass
else
  cat "$workdir/log"
  check "replaces the resources in a complete tree" fail
fi

if [[ -f "$tree/$mac_dir/Assets.car" ]] &&
    xcrun assetutil --info "$tree/$mac_dir/Assets.car" 2>/dev/null | grep -q '"Name" : "AppIcon"'; then
  check "copies the compiled Assets.car" pass
else
  check "copies the compiled Assets.car" fail
fi
if [[ -f "$tree/$mac_dir/app.icns" ]] && iconutil -c iconset -o "$workdir/app.iconset" "$tree/$mac_dir/app.icns" 2>/dev/null; then
  check "copies the compiled app.icns" pass
else
  check "copies the compiled app.icns" fail
fi

wrong=0
count=0
while read -r source size destination; do
  count=$((count + 1))
  if [[ "$size" == "-" ]]; then
    from="$icon_dir/$source"
  else
    from="$icon_dir/logos/$destination"
  fi
  cmp -s "$from" "$tree/$destination" || {
    echo "         not replaced: $destination"
    wrong=$((wrong + 1))
  }
done < <(entries)
[[ "$count" -gt 0 && "$wrong" -eq 0 ]] && check "copies all $count product-logos.txt entries" pass ||
  check "copies all product-logos.txt entries" fail

replaced="$(grep -c '^replaced ' "$workdir/log")"
[[ "$replaced" -eq $((count + 2)) ]] && check "logs every copy" pass || check "logs every copy" fail

# --- a missing destination --------------------------------------------------
gone="components/vector_icons/chromium/product.icon"
tree="$workdir/missing"
make_tree "$tree"
rm "$tree/$gone"
reject "fails when a destination is missing, naming it" "$gone" "$replace" "$tree"
if grep -q placeholder "$tree/$mac_dir/Assets.car" && grep -q placeholder "$tree/chrome/app/theme/chromium/product_logo.svg"; then
  check "a failed run copies nothing" pass
else
  check "a failed run copies nothing" fail
fi

# --- bad input --------------------------------------------------------------
tree="$workdir/src2"
make_tree "$tree"
reject "rejects missing arguments" "usage" "$replace"
reject "rejects a missing source tree" "not found" "$replace" "$workdir/nowhere"

# Bad lists, each in a copy of the icon directory.
bad_list() {
  local name="$1" line="$2"
  cp -R "$icon_dir" "$workdir/$name"
  echo "$line" >>"$workdir/$name/product-logos.txt"
  echo "$workdir/$name"
}
reject "rejects a line with too few fields" "expected" \
  "$replace" "$tree" "$(bad_list short 'logo.svg 16x16')"
reject "rejects a malformed size" "size must be" \
  "$replace" "$tree" "$(bad_list size 'logo.svg 16 chrome/app/theme/chromium/product_logo_16.png')"
reject "rejects a destination outside the tree" "unsafe path" \
  "$replace" "$tree" "$(bad_list unsafe 'logo.svg - ../outside.svg')"
reject "rejects a rendered logo that is not in logos/" "not found" \
  "$replace" "$tree" "$(bad_list unrendered 'logo.svg 99x99 chrome/app/theme/chromium/product_logo_99.png')"

echo
if [[ "$failures" -eq 0 ]]; then
  echo "All replace-icon-resources tests passed."
else
  echo "$failures replace-icon-resources test(s) failed."
fi
exit "$failures"
