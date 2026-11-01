#!/bin/bash
# Tests for engine-key.sh. Run directly: ./scripts/engine-key.test.sh
#
# Builds a stand-in repository with one file for each kind of engine input and
# each kind of file that must not affect the key, then changes them one by one.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

failures=0
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
repo="$workdir/repo"

check() {
  local description="$1" condition="$2"
  if [[ "$condition" == "pass" ]]; then
    echo "ok       $description"
  else
    echo "FAIL     $description"
    failures=$((failures + 1))
  fi
}

key() {
  "$repo/scripts/engine-key.sh" "$repo"
}

# Engine inputs: each one must change the key.
covered=(
  build.sh
  retrieve_and_unpack_resource.py
  downloads-arm64.ini
  flags.macos.gn
  flags.clair.gn
  patches/series
  patches/clair/branding.patch
  overlay/chrome/browser/clair/clair_host.mm
  utils/name_substitution.py
  native/ClairHost.h
  scripts/apply-overlay.sh
  scripts/compile-icon.sh
  scripts/replace-icon-resources.sh
  resources/icon/AppIcon.icon/icon.json
  resources/icon/logos/chrome/app/theme/chromium/product_logo_16.png
  resources/icon/vector_icons/chrome/app/vector_icons/product.icon
  resources/icon/logo.svg
)
# Not engine inputs: none of these may change the key.
ignored=(
  native/ClairUI/UpdateMenu.swift
  version.txt
  .sparkle/notes/next.md
  .github/workflows/ci.yml
  package.sh
  resources/icon/README.md
  resources/icon/geometry.svg
  scripts/render-notes.sh
)

mkdir -p "$repo/scripts"
git -C "$repo" init -q
for path in "${covered[@]}" "${ignored[@]}"; do
  mkdir -p "$repo/$(dirname "$path")"
  echo "original $path" >"$repo/$path"
done
cat >"$repo/resources/icon/product-logos.txt" <<'EOF'
# source size destination
logo.svg - chrome/app/theme/chromium/product_logo.svg
- 16x16 chrome/app/theme/chromium/product_logo_16.png
EOF
covered+=(resources/icon/product-logos.txt)
cp "$script_dir/engine-key.sh" "$repo/scripts/engine-key.sh"
git -C "$repo" add -A
git -C "$repo" update-index --add --cacheinfo \
  "160000,1111111111111111111111111111111111111111,ungoogled-chromium"

base="$(key)"
if [[ "$base" =~ ^[0-9a-f]{16}$ ]]; then
  check "key is 16 hex characters" pass
else
  check "key is 16 hex characters (got: $base)" fail
fi
[[ "$(key)" == "$base" ]] && check "key is stable" pass || check "key is stable" fail

# --- covered inputs ---------------------------------------------------------
for path in "${covered[@]}"; do
  cp "$repo/$path" "$workdir/saved"
  echo "changed" >>"$repo/$path"
  [[ "$(key)" != "$base" ]] && check "changing $path changes the key" pass ||
    check "changing $path changes the key" fail
  cp "$workdir/saved" "$repo/$path"
done
[[ "$(key)" == "$base" ]] && check "restoring the inputs restores the key" pass ||
  check "restoring the inputs restores the key" fail

git -C "$repo" update-index --cacheinfo \
  "160000,2222222222222222222222222222222222222222,ungoogled-chromium"
[[ "$(key)" != "$base" ]] && check "a new ungoogled-chromium commit changes the key" pass ||
  check "a new ungoogled-chromium commit changes the key" fail
git -C "$repo" update-index --cacheinfo \
  "160000,1111111111111111111111111111111111111111,ungoogled-chromium"

echo "# changed" >>"$repo/scripts/engine-key.sh"
[[ "$(key)" != "$base" ]] && check "changing engine-key.sh itself changes the key" pass ||
  check "changing engine-key.sh itself changes the key" fail
cp "$script_dir/engine-key.sh" "$repo/scripts/engine-key.sh"

echo "new" >"$repo/patches/clair/new.patch"
git -C "$repo" add patches/clair/new.patch
[[ "$(key)" != "$base" ]] && check "adding a patch changes the key" pass ||
  check "adding a patch changes the key" fail
git -C "$repo" rm -q --cached patches/clair/new.patch
rm "$repo/patches/clair/new.patch"

# --- ignored files ----------------------------------------------------------
for path in "${ignored[@]}"; do
  echo "changed" >>"$repo/$path"
  [[ "$(key)" == "$base" ]] && check "changing $path keeps the key" pass ||
    check "changing $path keeps the key" fail
done

echo "untracked" >"$repo/patches/untracked.patch"
[[ "$(key)" == "$base" ]] && check "an untracked file keeps the key" pass ||
  check "an untracked file keeps the key" fail
rm "$repo/patches/untracked.patch"

# --- manifest ---------------------------------------------------------------
manifest="$("$repo/scripts/engine-key.sh" --manifest "$repo")"
for path in "${covered[@]}" scripts/engine-key.sh; do
  grep -q "^$path [0-9a-f]\{64\}$" <<<"$manifest" &&
    check "manifest lists $path" pass || check "manifest lists $path" fail
done
grep -q "^ungoogled-chromium 1111111111111111111111111111111111111111$" <<<"$manifest" &&
  check "manifest lists the ungoogled-chromium commit" pass ||
  check "manifest lists the ungoogled-chromium commit" fail
for path in "${ignored[@]}"; do
  grep -q "^$path " <<<"$manifest" &&
    check "manifest leaves out $path" fail || check "manifest leaves out $path" pass
done
[[ "$(printf '%s\n' "$manifest" | shasum -a 256 | cut -c 1-16)" == "$(key)" ]] &&
  check "key is the hash of the manifest" pass || check "key is the hash of the manifest" fail

# --- errors -----------------------------------------------------------------
git -C "$repo" rm -q --cached ungoogled-chromium
if key >/dev/null 2>"$workdir/err"; then
  check "fails without the submodule" fail
elif grep -q "not a submodule" "$workdir/err"; then
  check "fails without the submodule" pass
else
  check "fails without the submodule (unexpected error)" fail
fi

echo
if [[ "$failures" -eq 0 ]]; then
  echo "All engine-key tests passed."
else
  echo "$failures engine-key test(s) failed."
fi
exit "$failures"
