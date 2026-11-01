#!/bin/bash
# Provides Sparkle from its pinned release tarball, checked against its sha512
# (change 1 design D4): Sparkle.framework for package.sh to embed, and the
# sign_update, BinaryDelta and generate_keys tools for releases.
#
#   fetch-sparkle.sh <dest-dir>
#
# <dest-dir> ends up holding Sparkle.framework, bin/sign_update,
# bin/BinaryDelta, bin/generate_keys and Sparkle's LICENSE, and is replaced
# only once a new tarball has been checked and unpacked. A <dest-dir> already
# holding this pinned release is reused without downloading. Prints <dest-dir>.
#
# For tests only: SPARKLE_TARBALL names a local tarball to use instead of the
# download, and SPARKLE_SHA512 replaces the pinned checksum.

set -euo pipefail

SPARKLE_VERSION="2.10.0"
PINNED_SHA512="ea01242340f178b6be155df45de90da3738110d54d7e618bd0bded60580c843bf8754731767d7009aeaeb1c4f01f79c13eb279c153b6c398fae29c46344a867f"
URL="https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
TOOLS=(sign_update BinaryDelta generate_keys)

die() {
  echo "fetch-sparkle: $1" >&2
  exit 1
}

[[ $# -eq 1 && -n "$1" ]] || die "usage: fetch-sparkle.sh <dest-dir>"
dest="${1%/}"
expected="${SPARKLE_SHA512-$PINNED_SHA512}"
[[ "$expected" =~ ^[0-9a-f]{128}$ ]] || die "the expected sha512 is not 128 hex digits"
stamp="Sparkle $SPARKLE_VERSION $expected"

if [[ -f "$dest/.sparkle-release" && "$(cat "$dest/.sparkle-release")" == "$stamp" ]]; then
  echo "$dest"
  exit 0
fi
[[ ! -e "$dest" || -d "$dest" ]] || die "not a directory: $dest"

parent="$(dirname "$dest")"
mkdir -p "$parent"
work="$(mktemp -d "$parent/.fetch-sparkle.XXXXXX")"
trap 'rm -rf "$work"' EXIT

tarball="$work/Sparkle-$SPARKLE_VERSION.tar.xz"
if [[ -n "${SPARKLE_TARBALL-}" ]]; then
  [[ -f "$SPARKLE_TARBALL" ]] || die "no tarball at $SPARKLE_TARBALL"
  cp "$SPARKLE_TARBALL" "$tarball"
else
  echo "fetch-sparkle: downloading $URL" >&2
  curl -fsSL --retry 3 -o "$tarball" "$URL" || die "could not download $URL"
fi

actual="$(shasum -a 512 "$tarball" | cut -d ' ' -f 1)"
if [[ "$actual" != "$expected" ]]; then
  die "Sparkle-$SPARKLE_VERSION.tar.xz failed its checksum: expected sha512 $expected, got $actual"
fi

unpacked="$work/unpacked"
mkdir "$unpacked"
tar -xJf "$tarball" -C "$unpacked" || die "could not unpack Sparkle-$SPARKLE_VERSION.tar.xz"

out="$work/out"
mkdir -p "$out/bin"
[[ -f "$unpacked/Sparkle.framework/Versions/B/Sparkle" ]] || die "the tarball has no Sparkle.framework/Versions/B/Sparkle"
mv "$unpacked/Sparkle.framework" "$out/"
for tool in "${TOOLS[@]}"; do
  [[ -f "$unpacked/bin/$tool" && -x "$unpacked/bin/$tool" ]] || die "the tarball has no executable bin/$tool"
  mv "$unpacked/bin/$tool" "$out/bin/"
done
[[ -f "$unpacked/LICENSE" ]] || die "the tarball has no LICENSE"
mv "$unpacked/LICENSE" "$out/"
printf '%s\n' "$stamp" >"$out/.sparkle-release"

rm -rf "$dest"
mv "$out" "$dest"
echo "$dest"
