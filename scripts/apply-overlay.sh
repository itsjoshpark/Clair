#!/bin/bash
# Copies Clair's overlay, new Chromium source files kept at their paths in the
# Chromium tree, into a patched Chromium source tree (change 1 design D1).
#
#   apply-overlay.sh build/src [overlay-dir]
#
# The overlay only adds files. A file whose path already exists in the tree
# would shadow Chromium's (or a patch's) version, so it fails the run and is
# named; edits to existing files belong in patches/. Every file is checked
# before any is copied. Copies get a new modification time, so build.sh's
# in-place update records them as part of Clair's layer. A missing overlay
# directory means there is nothing to copy.

set -euo pipefail

src_dir="${1-}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
overlay_dir="${2-$script_dir/../overlay}"

die() {
  echo "apply-overlay: $1" >&2
  exit 1
}

[[ -n "$src_dir" ]] || die "usage: apply-overlay.sh <chromium-src> [overlay-dir]"
[[ -d "$src_dir" ]] || die "Chromium source not found: $src_dir"
if [[ ! -e "$overlay_dir" ]]; then
  echo "apply-overlay: no overlay directory; nothing to copy"
  exit 0
fi
[[ -d "$overlay_dir" && ! -L "$overlay_dir" ]] || die "overlay is not a directory: $overlay_dir"

files=()
while IFS= read -r -d '' entry; do
  path="${entry#./}"
  [[ "$path" == *$'\n'* ]] && die "file name contains a newline: $path"
  [[ "$(basename "$path")" == ".DS_Store" ]] && continue
  if [[ -L "$overlay_dir/$path" ]]; then
    die "symlinks aren't allowed in the overlay: $path"
  fi
  if [[ -d "$overlay_dir/$path" ]]; then
    continue
  fi
  [[ -f "$overlay_dir/$path" ]] || die "not a regular file: $path"

  # The file and each of its parent directories, as they would be in the tree.
  # A parent may already exist, but only as a real directory: a file there
  # can't hold the new file, and a symlink could lead outside the tree.
  [[ -e "$src_dir/$path" || -L "$src_dir/$path" ]] &&
    die "overlay file shadows an existing Chromium file: $path"
  parent="$(dirname "$path")"
  while [[ "$parent" != "." ]]; do
    if [[ -L "$src_dir/$parent" ]]; then
      die "overlay path goes through a symlink in the Chromium tree: $parent (for $path)"
    fi
    if [[ -e "$src_dir/$parent" && ! -d "$src_dir/$parent" ]]; then
      die "overlay path goes through a file in the Chromium tree: $parent (for $path)"
    fi
    parent="$(dirname "$parent")"
  done
  files+=("$path")
done < <(cd "$overlay_dir" && find . -mindepth 1 -print0)

for path in ${files[@]+"${files[@]}"}; do
  mkdir -p "$src_dir/$(dirname "$path")"
  # A plain copy, not -p: the new modification time marks it as Clair's layer.
  cp "$overlay_dir/$path" "$src_dir/$path"
  echo "added $path"
done
echo "apply-overlay: copied ${#files[@]} files"
