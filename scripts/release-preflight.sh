#!/bin/bash
# Works out the next release's version and build number, and refuses to
# continue when Sparkle would never offer the release or its notes are missing.
#
#   release-preflight.sh --bump patch   ->  version=0.1.1
#                                           build=42
#                                           tag=v0.1.1
#
# Run from the repository root before anything is built. Output is key=value
# lines, suitable for appending to $GITHUB_OUTPUT.
#
# - Version: the latest v* tag bumped by --bump. The very first release has no
#   tag and uses version.txt as-is, whatever the bump.
# - Build number: the commit count of the release commit, which is made on top
#   of HEAD after the build, so HEAD's count plus one.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bump="" appcast=".sparkle/appcast.xml" notes_dir=".sparkle/notes" version_file="version.txt"

die() {
  echo "release-preflight: $1" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bump) bump="${2-}"; shift 2 ;;
    --appcast) appcast="${2-}"; shift 2 ;;
    --notes-dir) notes_dir="${2-}"; shift 2 ;;
    --version-file) version_file="${2-}"; shift 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done

case "$bump" in
  major | minor | patch) ;;
  "") die "--bump is required (major, minor, or patch)" ;;
  *) die "unknown bump '$bump' (expected major, minor, or patch)" ;;
esac

[[ -f "$appcast" ]] || die "appcast not found: $appcast"

latest_tag="$(git tag --list 'v[0-9]*' --sort=-v:refname | head -1)"
if [[ -z "$latest_tag" ]]; then
  [[ -f "$version_file" ]] || die "no v* tag and no $version_file to take the first version from"
  version="$(tr -d '[:space:]' <"$version_file")"
  [[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] ||
    die "$version_file must hold X.Y.Z, got '$version'"
else
  version="$("$script_dir/bump-version.sh" "$latest_tag" "$bump")"
fi
tag="v$version"

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  die "tag $tag already exists"
fi

build=$(( $(git rev-list --count HEAD) + 1 ))

# Sparkle picks updates by CFBundleVersion. A build number that does not exceed
# the newest entry is never offered.
newest="$(grep -o '<sparkle:version>[0-9]*</sparkle:version>' "$appcast" |
  grep -o '[0-9]*' | sort -n | tail -1 || true)"
if [[ -n "$newest" ]] && (( build <= newest )); then
  die "build $build does not exceed the newest appcast entry ($newest). Sparkle would never offer this release."
fi

next="$notes_dir/next.md"
template="$notes_dir/TEMPLATE.md"
[[ -f "$next" ]] || die "missing $next. Copy $template to it and write the release notes."
if [[ -f "$template" ]] && cmp -s "$next" "$template"; then
  die "$next is still the unedited template. Write the release notes."
fi
if [[ -e "$notes_dir/$version.md" ]]; then
  die "$notes_dir/$version.md already exists, so the archived notes for $version would be overwritten."
fi

echo "version=$version"
echo "build=$build"
echo "tag=$tag"
