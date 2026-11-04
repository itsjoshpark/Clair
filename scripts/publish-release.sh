#!/bin/bash
# Publishes a packaged release (change 1 design D5): makes the release commit, tags
# it, creates the GitHub Release, and pushes to main last, so the appcast never
# points at a file that doesn't exist yet.
#
#   publish-release.sh --version <x.y.z> --build <n> --base <sha> --dist <dir>
#                      --ungoogled <tag> --engine-key <key> [--repo <owner/name>]
#
# Run from the root of a checkout of <sha>, with a remote named origin that can
# push to main. <dir> holds Clair-<version>-arm64.dmg, any deltas, and assets.txt,
# the output of make-deltas.sh. Needs changie, cmark-gfm and gh.
#
# If main has moved past <sha>, it stops before anything leaves the machine. Once
# the Release is public a rejected push would leave installed copies unaware of it,
# so from there it rebases and tries again.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
minimum_system_version="15.6"

die() {
  echo "publish-release: $1" >&2
  exit 1
}

version="" build="" base="" dist="" ungoogled="" engine_key="" repo="itsjoshpark/Clair"
while (( $# > 0 )); do
  case "$1" in
    --version) version="${2-}"; shift 2 ;;
    --build) build="${2-}"; shift 2 ;;
    --base) base="${2-}"; shift 2 ;;
    --dist) dist="${2-}"; shift 2 ;;
    --ungoogled) ungoogled="${2-}"; shift 2 ;;
    --engine-key) engine_key="${2-}"; shift 2 ;;
    --repo) repo="${2-}"; shift 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done
for required in version build base dist ungoogled engine_key; do
  [[ -n "${!required}" ]] || die "--${required//_/-} is required"
done
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || die "the version must be X.Y.Z: $version"
[[ "$build" =~ ^[1-9][0-9]*$ ]] || die "the build number must be a positive integer: $build"
[[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die "not a repository: $repo"

tag="v$version"
dmg_name="Clair-$version-arm64.dmg"
dmg="$dist/$dmg_name"
assets="$dist/assets.txt"
[[ -f "$dmg" ]] || die "no DMG at $dmg"
[[ -f "$assets" ]] || die "no assets.txt in $dist"

[[ "$(git rev-parse HEAD)" == "$base" ]] || die "this checkout isn't $base"
[[ -z "$(git status --porcelain)" ]] || die "this checkout has uncommitted changes"
(( $(git rev-list --count HEAD) + 1 == build )) || die "build $build isn't the release commit's commit count"

# Each line of assets.txt, as make-deltas.sh wrote it.
signature="$(sed -n 's/^dmg_signature=//p' "$assets")"
length="$(sed -n 's/^dmg_length=//p' "$assets")"
[[ -n "$signature" && -n "$length" ]] || die "assets.txt has no signature or length for the DMG"
[[ "$length" == "$(stat -f %z "$dmg")" ]] || die "assets.txt's length isn't the DMG's"
delta_args=() delta_files=()
while IFS= read -r delta; do
  delta_args+=(--delta "$delta")
  url="${delta#*,}"
  url="${url%%,*}"
  name="${url##*/}"
  [[ -f "$dist/$name" ]] || die "assets.txt names $name, which isn't in $dist"
  delta_files+=("$name")
done < <(sed -n 's/^delta=//p' "$assets")

# --- the release commit -------------------------------------------------------------
changie batch "$version"
changie merge
notes="$(mktemp)" html="$(mktemp)" body="$(mktemp)"
trap 'rm -f "$notes" "$html" "$body"' EXIT
# The version file without its "## version - date" heading and the blank line after.
tail -n +3 ".changes/$version.md" >"$notes"
[[ -s "$notes" ]] || die ".changes/$version.md has no notes"
"$script_dir/render-notes.sh" "$notes" >"$html"

"$script_dir/append-appcast-item.sh" \
  --appcast .sparkle/appcast.xml \
  --version "$version" --build "$build" \
  --url "https://github.com/$repo/releases/download/$tag/$dmg_name" \
  --signature "$signature" --length "$length" --notes "$html" \
  --pub-date "$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')" \
  --minimum-system-version "$minimum_system_version" \
  ${delta_args[@]+"${delta_args[@]}"}

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add version.txt .changes CHANGELOG.md .sparkle/appcast.xml
git commit -q -m "chore: release $version ($build) [skip ci]"
commit="$(git rev-parse HEAD)"

# --- nothing has left the machine until here ----------------------------------------
git fetch -q origin main
[[ "$(git rev-parse FETCH_HEAD)" == "$base" ]] ||
  die "main moved during the release, so nothing was published. Run the release again."

checksums="Clair-$version-SHA256SUMS.txt"
(cd "$dist" && shasum -a 256 "$dmg_name" ${delta_files[@]+"${delta_files[@]}"} >"$checksums")

{
  cat "$notes"
  printf '\n---\n\nClair %s (build %s), ungoogled-chromium %s, engine key `%s`\n' "$version" "$build" "$ungoogled" "$engine_key"
} >"$body"

git push -q origin "$commit:refs/tags/$tag"
paths=("$dmg")
for name in ${delta_files[@]+"${delta_files[@]}"}; do
  paths+=("$dist/$name")
done
paths+=("$dist/$checksums")
# A draft stays invisible until every asset is uploaded.
if ! gh release create "$tag" --repo "$repo" --draft --verify-tag --title "$tag" --notes-file "$body" "${paths[@]}"; then
  die "tag $tag is pushed, but creating the GitHub Release failed, and main is unchanged. Delete the tag and any draft (git push origin :$tag), then run the release again."
fi
gh release edit "$tag" --repo "$repo" --draft=false --latest ||
  die "the Release for $tag is still a draft, and main is unchanged. Publish it, then push the tagged commit to main: git fetch origin tag $tag && git push origin $tag:main"

# --- main last --------------------------------------------------------------------
stranded() {
  die "$1 The Release is public, but installed copies won't be offered it until the appcast is on main. Cherry-pick the tagged commit onto main: git fetch origin tag $tag && git cherry-pick $tag"
}
for attempt in 1 2 3; do
  if git push -q origin HEAD:main; then
    echo "publish-release: published $tag"
    exit 0
  fi
  (( attempt < 3 )) || break
  echo "publish-release: push rejected (attempt $attempt), rebasing onto main" >&2
  git fetch -q origin main
  if ! git rebase -q FETCH_HEAD; then
    git rebase --abort
    stranded "Rebasing the release commit onto main conflicted."
  fi
done
stranded "The release commit couldn't be pushed after 3 attempts."
