#!/bin/bash
# Tests for fetch-sparkle.sh. Run directly: ./scripts/fetch-sparkle.test.sh
# Works offline: it builds stand-in tarballs and passes them in SPARKLE_TARBALL.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fetch="$script_dir/fetch-sparkle.sh"

failures=0
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

check() {
  local description="$1" condition="$2"
  if [[ "$condition" == "pass" ]]; then
    echo "ok       $description"
  else
    echo "FAIL     $description"
    failures=$((failures + 1))
  fi
}

# A stand-in for Sparkle's tarball, laid out like the real one. Leaving out a
# path given as an argument makes a broken one.
make_tarball() {
  local tarball="$1"; shift
  local root="$workdir/tarball-root"
  rm -rf "$root"
  mkdir -p "$root/Sparkle.framework/Versions/B" "$root/bin"
  echo "framework" >"$root/Sparkle.framework/Versions/B/Sparkle"
  ln -s Versions/B/Sparkle "$root/Sparkle.framework/Sparkle"
  ln -s B "$root/Sparkle.framework/Versions/Current"
  local tool
  for tool in sign_update BinaryDelta generate_keys generate_appcast; do
    printf '#!/bin/sh\necho %s\n' "$tool" >"$root/bin/$tool"
    chmod +x "$root/bin/$tool"
  done
  echo "license" >"$root/LICENSE"
  echo "changes" >"$root/CHANGELOG"
  local missing
  for missing in "$@"; do
    rm -rf "${root:?}/$missing"
  done
  (cd "$root" && tar -cJf "$tarball" .)
}

sha512() {
  shasum -a 512 "$1" | cut -d ' ' -f 1
}

# Runs fetch-sparkle.sh with TARBALL and the checksum SHA (empty: the pinned
# one), keeping its output in $output.
output=""
run_fetch() {
  local tarball="$1" sha="$2" dest="$3"
  if [[ -n "$sha" ]]; then
    output="$(SPARKLE_TARBALL="$tarball" SPARKLE_SHA512="$sha" "$fetch" "$dest" 2>&1)"
  else
    output="$(SPARKLE_TARBALL="$tarball" "$fetch" "$dest" 2>&1)"
  fi
}

good="$workdir/good.tar.xz"
make_tarball "$good"
good_sha="$(sha512 "$good")"

# --- a good tarball -----------------------------------------------------------
dest="$workdir/out/sparkle"
if run_fetch "$good" "$good_sha" "$dest" && [[ "$output" == "$dest" ]]; then
  check "a tarball matching its checksum is unpacked and the directory printed" pass
else
  check "a tarball matching its checksum is unpacked and the directory printed" fail
  echo "         got: $output"
fi

all_there=pass
for path in Sparkle.framework/Versions/B/Sparkle bin/sign_update bin/BinaryDelta bin/generate_keys LICENSE; do
  [[ -f "$dest/$path" ]] || { all_there=fail; echo "         missing: $path"; }
done
check "provides Sparkle.framework, sign_update, BinaryDelta, generate_keys and LICENSE" "$all_there"

if [[ -L "$dest/Sparkle.framework/Versions/Current" && -L "$dest/Sparkle.framework/Sparkle" ]]; then
  check "keeps the framework's symlinks" pass
else
  check "keeps the framework's symlinks" fail
fi

if [[ -x "$dest/bin/sign_update" && "$("$dest/bin/sign_update")" == sign_update ]]; then
  check "the tools stay executable" pass
else
  check "the tools stay executable" fail
fi

if [[ ! -e "$dest/bin/generate_appcast" && ! -e "$dest/CHANGELOG" ]]; then
  check "leaves out what Clair doesn't use" pass
else
  check "leaves out what Clair doesn't use" fail
fi

if [[ -z "$(find "$workdir/out" -name '.fetch-sparkle.*')" ]]; then
  check "cleans up its working directory" pass
else
  check "cleans up its working directory" fail
fi

# --- reuse ----------------------------------------------------------------------
echo "marker" >"$dest/marker"
if run_fetch "$workdir/does-not-exist.tar.xz" "$good_sha" "$dest" && [[ -f "$dest/marker" ]]; then
  check "reuses a directory that already holds the pinned release" pass
else
  check "reuses a directory that already holds the pinned release" fail
  echo "         got: $output"
fi

other="$workdir/other.tar.xz"
make_tarball "$other"
echo "extra" >"$workdir/tarball-root/extra" && (cd "$workdir/tarball-root" && tar -cJf "$other" .)
if run_fetch "$other" "$(sha512 "$other")" "$dest" && [[ ! -e "$dest/marker" && -f "$dest/bin/sign_update" ]]; then
  check "replaces a directory holding another release" pass
else
  check "replaces a directory holding another release" fail
  echo "         got: $output"
fi

# --- the checksum ---------------------------------------------------------------
tampered="$workdir/tampered.tar.xz"
cp "$good" "$tampered"
printf 'x' >>"$tampered"
dest="$workdir/tampered/sparkle"
if ! run_fetch "$tampered" "" "$dest" && [[ "$output" == *"failed its checksum"* && ! -e "$dest" ]]; then
  check "refuses a tarball that doesn't match the pinned sha512, and provides nothing" pass
else
  check "refuses a tarball that doesn't match the pinned sha512, and provides nothing" fail
  echo "         got: $output"
fi

dest="$workdir/kept/sparkle"
run_fetch "$good" "$good_sha" "$dest"
zeros="$(printf '0%.0s' {1..128})"
if ! run_fetch "$tampered" "$zeros" "$dest" && [[ "$output" == *"failed its checksum"* && -f "$dest/bin/sign_update" ]]; then
  check "a failed checksum leaves an earlier copy in place" pass
else
  check "a failed checksum leaves an earlier copy in place" fail
  echo "         got: $output"
fi

if ! run_fetch "$good" "not-a-hash" "$workdir/bad-sha/sparkle" && [[ "$output" == *"128 hex digits"* ]]; then
  check "rejects a malformed checksum" pass
else
  check "rejects a malformed checksum" fail
fi

# --- broken tarballs --------------------------------------------------------------
for missing in bin/BinaryDelta bin/sign_update bin/generate_keys Sparkle.framework LICENSE; do
  broken="$workdir/broken.tar.xz"
  make_tarball "$broken" "$missing"
  dest="$workdir/broken/sparkle"
  if ! run_fetch "$broken" "$(sha512 "$broken")" "$dest" && [[ "$output" == *"no "* && ! -e "$dest" ]]; then
    check "refuses a tarball without $missing" pass
  else
    check "refuses a tarball without $missing" fail
    echo "         got: $output"
  fi
done

# --- inputs -----------------------------------------------------------------------
if ! "$fetch" >/dev/null 2>&1 && ! "$fetch" a b >/dev/null 2>&1; then
  check "requires exactly one destination" pass
else
  check "requires exactly one destination" fail
fi

touch "$workdir/a-file"
if ! run_fetch "$good" "$good_sha" "$workdir/a-file" && [[ "$output" == *"not a directory"* && -f "$workdir/a-file" ]]; then
  check "refuses a destination that is a file" pass
else
  check "refuses a destination that is a file" fail
fi

echo
if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
