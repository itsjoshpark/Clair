#!/bin/bash
# Writes ungoogled-chromium's domain substitution list without the files Clair
# leaves out (arc-extension-experience design D1).
#
#   filter-domain-substitution.sh <substitution-list> <exclude-list> <output>
#
# The exclude list has one path per line; blank lines and lines starting with
# "#" are ignored. A listed path that isn't in the substitution list stops the
# run with an error naming it, so a renamed file can't silently drop out. Every
# path is checked before the output is written.

set -euo pipefail

die() {
  echo "filter-domain-substitution: $1" >&2
  exit 1
}

[[ $# -eq 3 ]] || die "usage: filter-domain-substitution.sh <substitution-list> <exclude-list> <output>"
list="$1"
exclude="$2"
output="$3"
[[ -f "$list" ]] || die "substitution list not found: $list"
[[ -f "$exclude" ]] || die "exclude list not found: $exclude"

paths="$(mktemp)"
trap 'rm -f "$paths"' EXIT
{ grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$exclude" || true; } >"$paths"

missing=false
while IFS= read -r path; do
  if ! grep -qxF -- "$path" "$list"; then
    echo "filter-domain-substitution: not in the substitution list: $path" >&2
    missing=true
  fi
done <"$paths"
$missing && die "update $exclude to match $list"

if [[ -s "$paths" ]]; then
  { grep -vxF -f "$paths" -- "$list" || true; } >"$output"
else
  cp "$list" "$output"
fi
