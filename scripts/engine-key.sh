#!/bin/bash
# Prints Clair's engine key: the first 16 hex characters of a SHA-256 over a
# sorted manifest of "<path> <sha256>" lines, one per engine input (change 1
# design D10). Files that don't reach the Chromium build don't change the key.
#
#   engine-key.sh [--manifest] [repo-dir]
#
# --manifest prints the manifest instead of the key, so a key change can be
# explained. The ungoogled-chromium submodule is listed by the commit the
# index records. Only files tracked by git count, with their working-tree
# contents.

set -euo pipefail

die() {
  echo "engine-key: $1" >&2
  exit 1
}

manifest_only=false
if [[ "${1-}" == "--manifest" ]]; then
  manifest_only=true
  shift
fi
repo="${1-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
cd "$repo" || die "repository not found: $repo"
icon_dir="resources/icon"
logo_list="$icon_dir/product-logos.txt"

# Tracked files at or under these paths are engine inputs.
inputs=(
  build.sh retrieve_and_unpack_resource.py 'downloads*.ini' 'flags*.gn'
  patches overlay utils native/ClairHost.h
  scripts/engine-key.sh scripts/compile-icon.sh scripts/replace-icon-resources.sh
  "$icon_dir/AppIcon.icon" "$icon_dir/logos" "$icon_dir/vector_icons" "$logo_list"
)
# "-" entries in product-logos.txt copy a file from resources/icon itself.
if [[ -f "$logo_list" ]]; then
  while read -r source size _; do
    if [[ "$size" == "-" ]]; then
      inputs+=("$icon_dir/$source")
    fi
  done < <(grep -v '^[[:space:]]*#' "$logo_list" | awk 'NF == 3')
fi

submodule="$(git ls-files -s ungoogled-chromium | awk '$1 == "160000" { print $2 }')"
[[ -n "$submodule" ]] || die "ungoogled-chromium is not a submodule in $repo"

lines="$(mktemp)"
trap 'rm -f "$lines"' EXIT
echo "ungoogled-chromium $submodule" >"$lines"
while IFS= read -r -d '' path; do
  [[ -f "$path" ]] || die "tracked input is missing from the work tree: $path"
  printf '%s %s\n' "$path" "$(shasum -a 256 <"$path" | cut -d ' ' -f 1)" >>"$lines"
done < <(git ls-files -z -- "${inputs[@]}")

manifest="$(LC_ALL=C sort "$lines")"
if $manifest_only; then
  printf '%s\n' "$manifest"
else
  printf '%s\n' "$manifest" | shasum -a 256 | cut -c 1-16
fi
