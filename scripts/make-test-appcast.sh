#!/bin/bash
# Adds a release to a local test appcast, signed with the test-only key in
# tests/runtime/update-key (docs/updates.md, design D6). Only packages made
# with that key as --public-key accept it; shipped builds don't.
#
#   make-test-appcast.sh --appcast <file> --dmg <file> --version <x.y.z>
#                        --build <n> --base-url <url> [options]
#
# The appcast is created if it's missing, and is refused if it's the real one.
# Assets are expected at <base-url>/<file name>.
#
# Options:
#   --minimum-system-version <v>  default: 15.6
#   --delta <from-build>,<file>   a delta from an earlier build (up to three)
#   --sparkle <dir>               a directory from fetch-sparkle.sh (default:
#                                 fetch into build/sparkle)
#   --key <file>                  the private key (default: the test-only key)

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
key="$root/tests/runtime/update-key/private-ed-key.txt"
appcast="" dmg="" version="" build="" base_url="" sparkle="" minimum_system_version="15.6"
deltas=()
# append-appcast-item.sh takes https URLs only, as the real feed must; a local
# server speaks http, so the placeholder is rewritten afterwards.
placeholder="https://clair-test.invalid"

die() {
  echo "make-test-appcast: $1" >&2
  exit 1
}

while (( $# > 0 )); do
  case "$1" in
    --appcast) appcast="${2-}"; shift 2 ;;
    --dmg) dmg="${2-}"; shift 2 ;;
    --version) version="${2-}"; shift 2 ;;
    --build) build="${2-}"; shift 2 ;;
    --base-url) base_url="${2-}"; shift 2 ;;
    --minimum-system-version) minimum_system_version="${2-}"; shift 2 ;;
    --delta) deltas+=("${2-}"); shift 2 ;;
    --sparkle) sparkle="${2-}"; shift 2 ;;
    --key) key="${2-}"; shift 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done

for required in appcast dmg version build base_url; do
  [[ -n "${!required}" ]] || die "--${required//_/-} is required"
done
[[ -f "$dmg" ]] || die "no file at $dmg"
[[ -f "$key" ]] || die "no key at $key"
# Everything here ends up in XML, and in a sed replacement below.
[[ "$base_url" =~ ^https?://[A-Za-z0-9.:-]+(/[A-Za-z0-9._-]+)*$ ]] || die "not a plain URL: $base_url"

appcast_dir="$(mkdir -p "$(dirname "$appcast")" && cd "$(dirname "$appcast")" && pwd -P)"
[[ "$appcast_dir/$(basename "$appcast")" != "$root/.sparkle/appcast.xml" ]] || die "refusing to write to the real appcast"
appcast="$appcast_dir/$(basename "$appcast")"

if [[ -z "$sparkle" ]]; then
  sparkle="$("$root/scripts/fetch-sparkle.sh" "$root/build/sparkle")"
fi
sign_update="${sparkle%/}/bin/sign_update"
[[ -x "$sign_update" ]] || die "no sign_update in $sparkle"

# Prints FILE's URL under the placeholder, its signature and its length.
asset() {
  local file="$1" name
  name="$(basename "$file")"
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die "the file name can't be part of a plain URL: $name"
  printf '%s %s %s\n' "$placeholder/$name" \
    "$("$sign_update" --ed-key-file "$key" -p "$file")" \
    "$(stat -f %z "$file")"
}

[[ -f "$appcast" ]] || cat >"$appcast" <<'XML'
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>Clair test feed</title>
    <language>en</language>

  </channel>
</rss>
XML

notes="$(mktemp)"
trap 'rm -f "$notes"' EXIT
echo "<p>Test release $version.</p>" >"$notes"

read -r url signature length < <(asset "$dmg")
delta_args=()
for delta in ${deltas[@]+"${deltas[@]}"}; do
  from="${delta%%,*}"
  file="${delta#*,}"
  [[ -f "$file" ]] || die "no delta file at $file"
  read -r d_url d_signature d_length < <(asset "$file")
  delta_args+=(--delta "$from,$d_url,$d_signature,$d_length")
done

"$root/scripts/append-appcast-item.sh" \
  --appcast "$appcast" --version "$version" --build "$build" \
  --url "$url" --signature "$signature" --length "$length" --notes "$notes" \
  --pub-date "$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')" \
  --minimum-system-version "$minimum_system_version" \
  ${delta_args[@]+"${delta_args[@]}"}

sed -i '' "s|$placeholder|${base_url%/}|g" "$appcast"
xmllint --noout "$appcast"
