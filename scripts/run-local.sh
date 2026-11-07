#!/bin/bash
# The local edit-to-run loop (replace-browser-window design D15): packages the
# checkout's ClairUI against the published engine for its key, signed ad hoc,
# and launches it with a throwaway profile and the mock keychain, so the
# owner's own Clair data and "Clair Safe Storage" keychain item stay untouched.
# It never fetches or builds Chromium.
#
#   run-local.sh [options] [-- <Chromium arguments>...]
#
# Options:
#   --work <dir>     where the engine cache, ClairUI's build, the packaged app
#                    and throwaway profiles live (default: build/run-local)
#   --profile <dir>  use this profile directory and keep it, instead of a
#                    throwaway one deleted when Clair quits. It can't be in
#                    ~/Library/Application Support/Clair.
#   --no-launch      package only, and print the app's path
#
# The engine is chromium-engine-<key> for the checkout's engine key, downloaded
# with gh once, checked against its SHA-256 and cached by key (the three most
# recently used keys are kept). A key with no published engine stops the
# script with the engine.yml command that builds it. Arguments after -- go to
# Clair, after --user-data-dir and --use-mock-keychain.
#
# For tests only: CLAIR_RUN_LOCAL_ENGINE_KEY replaces the computed engine key,
# and CLAIR_RUN_LOCAL_PACKAGE replaces package.sh.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
product="Clair"
keep_engines=3

die() {
  echo "run-local: $1" >&2
  exit 1
}

usage() {
  sed -n '/^#   run-local.sh/,/^# The engine/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//' >&2
  exit 2
}

work="$root/build/run-local" profile="" launch=true
while (( $# > 0 )); do
  case "$1" in
    --work) work="${2-}"; shift 2 || usage ;;
    --profile) profile="${2-}"; shift 2 || usage ;;
    --no-launch) launch=false; shift ;;
    --) shift; break ;;
    -h|--help) usage ;;
    *) die "unknown argument: $1 (Chromium arguments go after --)" ;;
  esac
done
[[ -n "$work" ]] || die "--work needs a directory"
mkdir -p "$work"
work="$(cd "$work" && pwd -P)"

# --- the profile -------------------------------------------------------------------
# Resolves PATH as far as it exists, so a profile given through a symlink or
# with .. still can't land in Clair's own data folder.
real_path() {
  local path="$1" tail=""
  while [[ ! -d "$path" ]]; do
    tail="/$(basename "$path")$tail"
    path="$(dirname "$path")"
  done
  printf '%s%s\n' "$(cd "$path" && pwd -P)" "$tail"
}

clair_data="$(real_path "$HOME/Library/Application Support/$product")"
throwaway=false
if [[ -n "$profile" ]]; then
  profile="$(real_path "$profile")"
  case "$profile/" in
    "$clair_data/"*) die "the profile can't be in $clair_data, which holds your own Clair data" ;;
  esac
fi

# --- the engine -------------------------------------------------------------------
key="${CLAIR_RUN_LOCAL_ENGINE_KEY-}"
if [[ -z "$key" ]]; then
  key="$("$root/scripts/engine-key.sh" "$root")" || die "couldn't compute the engine key"
fi
[[ "$key" =~ ^[0-9a-f]{16}$ ]] || die "the engine key is not 16 hex digits: $key"
tag="chromium-engine-$key"
zip="Clair-Chromium-Engine-$key-arm64.zip"
engines="$work/engines"
cached="$engines/$key"

if [[ -f "$cached/.complete" && -d "$cached/$product.app" ]]; then
  echo "run-local: using the cached engine $key" >&2
else
  draft="$(gh release view "$tag" --json isDraft --jq .isDraft 2>/dev/null || true)"
  if [[ "$draft" != false ]]; then
    branch="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "<branch>")"
    die "no published engine for $key. Push the branch and build it with: gh workflow run engine.yml -f ref=$branch"
  fi
  mkdir -p "$engines"
  download="$(mktemp -d "$engines/.download.XXXXXX")"
  trap 'rm -rf "$download"' EXIT
  echo "run-local: downloading $tag" >&2
  gh release download "$tag" --dir "$download" --pattern "$zip" --pattern "$zip.sha256" ||
    die "couldn't download $tag"
  [[ -f "$download/$zip" && -f "$download/$zip.sha256" ]] || die "$tag has no $zip and $zip.sha256"
  (cd "$download" && shasum -a 256 -c "$zip.sha256" >/dev/null 2>&1) ||
    die "$zip failed its SHA-256 check"
  mkdir "$download/unpacked"
  ditto -x -k "$download/$zip" "$download/unpacked" || die "couldn't unpack $zip"
  [[ -d "$download/unpacked/$product.app" ]] || die "$zip holds no $product.app at its top level"
  cut -d ' ' -f 1 "$download/$zip.sha256" >"$download/unpacked/.complete"
  rm -rf "$cached"
  mv "$download/unpacked" "$cached"
  rm -rf "$download"
  trap - EXIT
fi
touch "$cached"
# Keep the most recently used engines only; each is several hundred MB.
kept=0
while IFS= read -r old; do
  [[ "$old" =~ ^[0-9a-f]{16}$ ]] || continue
  kept=$((kept + 1))
  if (( kept > keep_engines )); then
    rm -rf "${engines:?}/$old"
  fi
done < <(cd "$engines" && ls -1t)

# --- ClairUI and the package --------------------------------------------------------
# Debug, in a kept derived-data folder, so a one-line change rebuilds in seconds.
echo "run-local: building ClairUI" >&2
xcodebuild -project "$root/native/ClairUI.xcodeproj" -scheme ClairUI \
  -configuration Debug -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$work/DerivedData" CODE_SIGNING_ALLOWED=NO -quiet build >&2 ||
  die "ClairUI didn't build"
clairui="$work/DerivedData/Build/Products/Debug/ClairUI.framework"
[[ -d "$clairui" ]] || die "xcodebuild left no ClairUI.framework at $clairui"

package="${CLAIR_RUN_LOCAL_PACKAGE:-$root/package.sh}"
rm -rf "$work/app"
mkdir -p "$work/app"
"$package" --no-dmg --clairui "$clairui" "$cached/$product.app" "$work/app" >&2 || die "packaging failed"
app="$work/app/$product.app"
[[ -x "$app/Contents/MacOS/$product" ]] || die "packaging left no $app"

if ! $launch; then
  echo "$app"
  exit 0
fi

# --- launch -----------------------------------------------------------------------
if [[ -z "$profile" ]]; then
  mkdir -p "$work/profiles"
  profile="$(mktemp -d "$work/profiles/profile.XXXXXX")"
  throwaway=true
fi
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
cleanup() {
  # The app and its notification helper register themselves with Launch
  # Services; don't leave a second dev.joshuapark.Clair for "open" to pick.
  local bundle
  while IFS= read -r -d '' bundle; do
    "$lsregister" -u "$bundle" >/dev/null 2>&1 || true
  done < <(find "$app" -name '*.app' -type d -print0 2>/dev/null)
  if $throwaway; then
    rm -rf "$profile"
  fi
}
trap cleanup EXIT
echo "run-local: launching with the profile $profile" >&2
status=0
# Crashpad writes to the default data folder even with --user-data-dir
# (chrome_paths.cc, DIR_CRASH_DUMPS); this keeps it in the profile.
BREAKPAD_DUMP_LOCATION="$profile/Crashpad" "$app/Contents/MacOS/$product" \
  --user-data-dir="$profile" --use-mock-keychain --no-first-run --no-default-browser-check \
  "$@" || status=$?
exit "$status"
