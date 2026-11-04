#!/bin/bash
# Works out the next release's version and build number, and refuses to
# continue when Sparkle would never offer the release or its notes are missing
# or malformed. Changes nothing.
#
#   release-preflight.sh --release-type auto   ->  version=0.1.1
#                                                  build=42
#                                                  tag=v0.1.1
#
# Run from the repository root before anything is built. Output is key=value
# lines, suitable for appending to $GITHUB_OUTPUT. Needs changie and cmark-gfm.
#
# - Version: `changie next` for --release-type (auto, patch, minor or major).
#   With auto, a New fragment bumps the minor version and the others the patch.
# - Build number: the commit count of the release commit, which is made on top
#   of HEAD after the build, so HEAD's count plus one.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

release_type="" appcast=".sparkle/appcast.xml" changes=".changes"

die() {
  echo "release-preflight: $1" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release-type) release_type="${2-}"; shift 2 ;;
    --appcast) appcast="${2-}"; shift 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done

case "$release_type" in
  auto | major | minor | patch) ;;
  "") die "--release-type is required (auto, major, minor, or patch)" ;;
  *) die "unknown release type '$release_type' (expected auto, major, minor, or patch)" ;;
esac

[[ -f "$appcast" ]] || die "appcast not found: $appcast"
command -v changie >/dev/null || die "changie is not installed"

# `changie next patch` happily names a version with nothing in it.
compgen -G "$changes/unreleased/*.yaml" >/dev/null ||
  die "no fragments in $changes/unreleased. Add the release notes with \`changie new\`."

next="$(changie next "$release_type")" || die "changie couldn't work out the next version"
# Changie puts a v on the version it derives from no releases at all.
version="${next#v}"
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] ||
  die "changie's next version isn't X.Y.Z: '$next'"
tag="v$version"

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  die "tag $tag already exists"
fi
if [[ -e "$changes/$version.md" ]]; then
  die "$changes/$version.md already exists, so the archived notes for $version would be overwritten."
fi

build=$(( $(git rev-list --count HEAD) + 1 ))

# Sparkle picks updates by CFBundleVersion. A build number that does not exceed
# the newest entry is never offered.
newest="$({ grep -o '<sparkle:version>[0-9]*</sparkle:version>' "$appcast" || true; } |
  { grep -o '[0-9]*' || true; } | sort -n | tail -1)"
if [[ -n "$newest" ]] && (( build <= newest )); then
  die "build $build does not exceed the newest appcast entry ($newest). Sparkle would never offer this release."
fi

# Malformed notes fail here rather than after the build. The batch's first two
# lines are its "## version - date" heading and a blank line.
notes="$(mktemp)"
trap 'rm -f "$notes"' EXIT
batch="$(changie batch "$version" --dry-run)" || die "changie couldn't batch the fragments"
tail -n +3 <<<"$batch" >"$notes"
[[ -s "$notes" ]] || die "the fragments give no release notes"
"$script_dir/render-notes.sh" "$notes" >/dev/null || die "the release notes don't render"

echo "version=$version"
echo "build=$build"
echo "tag=$tag"
