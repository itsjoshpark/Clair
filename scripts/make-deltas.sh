#!/bin/bash
# Makes a release's Sparkle deltas from up to three previous releases, and signs
# the DMG and every delta (change 1 design D5, D6). Each delta is applied before
# it's kept, and the result must pass codesign.
#
#   make-deltas.sh --app <Clair.app> --dmg <file> --version <x.y.z> --build <n>
#                  --out <dir> [--sparkle <dir>] [--repo <owner/name>]
#
# <Clair.app> and <file> are the new release's stapled app and DMG. <dir>
# receives Clair-<from-build>-<build>.delta files. --sparkle is a directory from
# fetch-sparkle.sh (default: fetch into build/sparkle).
#
# The private key is read from the SPARKLE_ED_PRIVATE_KEY environment variable and
# reaches sign_update only through stdin. Stdout holds the results as lines for
# the appcast entry, with progress on stderr:
#
#   dmg_signature=<base64>
#   dmg_length=<bytes>
#   delta=<from-build>,<url>,<base64>,<bytes>    (one for each delta)

set -euo pipefail
set +x

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
max_deltas=3

die() {
  echo "make-deltas: $1" >&2
  exit 1
}

app="" dmg="" version="" build="" out="" sparkle="" repo="itsjoshpark/Clair"
while (( $# > 0 )); do
  case "$1" in
    --app) app="${2-}"; shift 2 ;;
    --dmg) dmg="${2-}"; shift 2 ;;
    --version) version="${2-}"; shift 2 ;;
    --build) build="${2-}"; shift 2 ;;
    --out) out="${2-}"; shift 2 ;;
    --sparkle) sparkle="${2-}"; shift 2 ;;
    --repo) repo="${2-}"; shift 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done

for required in app dmg version build out; do
  [[ -n "${!required}" ]] || die "--$required is required"
done
[[ -n "${SPARKLE_ED_PRIVATE_KEY-}" ]] || die "SPARKLE_ED_PRIVATE_KEY is not set"
[[ -d "$app" ]] || die "no app at $app"
[[ -f "$dmg" ]] || die "no DMG at $dmg"
# These end up in URLs, file names and the appcast.
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || die "the version must be X.Y.Z: $version"
[[ "$build" =~ ^[1-9][0-9]*$ ]] || die "the build number must be a positive integer: $build"
[[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die "not a repository: $repo"

if [[ -z "$sparkle" ]]; then
  sparkle="$("$root/scripts/fetch-sparkle.sh" "$root/build/sparkle")"
fi
sign_update="${sparkle%/}/bin/sign_update"
binary_delta="${sparkle%/}/bin/BinaryDelta"
[[ -x "$sign_update" && -x "$binary_delta" ]] || die "no sign_update and BinaryDelta in $sparkle"

mkdir -p "$out"
work="$(mktemp -d "${TMPDIR:-/tmp}/clair-deltas.XXXXXX")"
mounted=""
cleanup() {
  if [[ -n "$mounted" ]]; then
    hdiutil detach -quiet -force "$mounted" || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

# Prints FILE's EdDSA signature. The key travels only through the pipe.
sign() {
  printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$sign_update" --ed-key-file - -p "$1"
}

signature="$(sign "$dmg")" || die "couldn't sign $(basename "$dmg")"
echo "dmg_signature=$signature"
echo "dmg_length=$(stat -f %z "$dmg")"

# The newest published releases before this one, newest first. Engine releases are
# prereleases with their own tags, so neither the flag nor the pattern lets them in.
tags="$(gh release list --repo "$repo" --exclude-drafts --exclude-pre-releases --limit 100 --json tagName --jq '.[].tagName')" ||
  die "couldn't list the releases of $repo"
previous="$(grep -E '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' <<<"$tags" |
  { grep -vxF "v$version" || true; } | sed 's/^v//' |
  sort -t . -k 1,1nr -k 2,2nr -k 3,3nr | head -n "$max_deltas")" || previous=""

if [[ -z "$previous" ]]; then
  echo "make-deltas: no previous releases, so no deltas" >&2
  exit 0
fi

while IFS= read -r old_version; do
  old_name="Clair-$old_version-arm64.dmg"
  old_dir="$work/$old_version"
  mkdir "$old_dir"
  echo "make-deltas: downloading $old_name" >&2
  gh release download "v$old_version" --repo "$repo" --pattern "$old_name" --dir "$old_dir" >&2 ||
    die "couldn't download $old_name from v$old_version"
  [[ -f "$old_dir/$old_name" ]] || die "v$old_version has no $old_name"

  mount="$old_dir/mount"
  mkdir "$mount"
  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount" "$old_dir/$old_name" >&2 ||
    die "couldn't mount $old_name"
  mounted="$mount"
  old_app="$mount/Clair.app"
  [[ -d "$old_app" ]] || die "$old_name holds no Clair.app"

  from="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$old_app/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$from" =~ ^[1-9][0-9]*$ ]] || die "$old_name's build number isn't an integer: $from"
  (( from < build )) || die "$old_name's build $from isn't lower than the new build $build"
  codesign --verify --deep --strict "$old_app" >&2 || die "the app in $old_name doesn't pass codesign"

  delta_name="Clair-$from-$build.delta"
  delta="$work/$delta_name"
  echo "make-deltas: making $delta_name" >&2
  "$binary_delta" create "$old_app" "$app" "$delta" >&2 || die "BinaryDelta couldn't make $delta_name"

  # A delta that can't reproduce the app only costs users a full download, but it
  # means this release's packaging went wrong, so stop here.
  patched="$old_dir/patched.app"
  "$binary_delta" apply "$old_app" "$patched" "$delta" >&2 || die "$delta_name doesn't apply to build $from"
  codesign --verify --deep --strict "$patched" >&2 || die "the app $delta_name makes doesn't pass codesign"

  hdiutil detach -quiet "$mount" >&2 || die "couldn't detach $old_name"
  mounted=""

  signature="$(sign "$delta")" || die "couldn't sign $delta_name"
  length="$(stat -f %z "$delta")"
  mv "$delta" "$out/$delta_name"
  echo "delta=$from,https://github.com/$repo/releases/download/v$version/$delta_name,$signature,$length"
  rm -rf "$old_dir"
done <<<"$previous"
