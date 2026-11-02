#!/bin/bash
# Tests for install-native-contract.sh. Run directly:
# ./scripts/install-native-contract.test.sh

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
install="$script_dir/install-native-contract.sh"

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

repo="$workdir/repo"
tree="$workdir/src"

# A repository with a contract header and an ungoogled-chromium version, and a
# tree whose overlay has been copied.
reset() {
  rm -rf "$repo" "$tree"
  mkdir -p "$repo/native" "$repo/ungoogled-chromium" "$tree/chrome/browser/clair"
  echo "// contract" >"$repo/native/ClairHost.h"
  echo "156.0.8078.73" >"$repo/ungoogled-chromium/chromium_version.txt"
  echo "1" >"$repo/ungoogled-chromium/revision.txt"
  echo "// loader" >"$tree/chrome/browser/clair/clair_native_layer.mm"
}

output=""
run() {
  output="$("$install" "$tree" "$repo" 2>&1)"
}

expect_refusal() {
  local description="$1" message="$2"
  if run; then
    check "$description" fail
    echo "         succeeded: $output"
  elif [[ "$output" == *"$message"* ]]; then
    check "$description" pass
  else
    check "$description" fail
    echo "         expected a message containing: $message"
    echo "         got: $output"
  fi
}

# --- installing -------------------------------------------------------------------
reset
if run && cmp -s "$repo/native/ClairHost.h" "$tree/chrome/browser/clair/ClairHost.h"; then
  check "copies ClairHost.h into chrome/browser/clair" pass
else
  check "copies ClairHost.h into chrome/browser/clair" fail
  echo "         got: $output"
fi

version_header="$tree/chrome/browser/clair/ungoogled_version.h"
if grep -qx '#define CLAIR_UNGOOGLED_CHROMIUM_VERSION "156.0.8078.73-1"' "$version_header" 2>/dev/null; then
  check "writes the ungoogled-chromium version as <chromium>-<revision>" pass
else
  check "writes the ungoogled-chromium version as <chromium>-<revision>" fail
fi

if grep -q '^#ifndef CHROME_BROWSER_CLAIR_UNGOOGLED_VERSION_H_$' "$version_header" 2>/dev/null \
    && grep -q '^#endif  // CHROME_BROWSER_CLAIR_UNGOOGLED_VERSION_H_$' "$version_header"; then
  check "guards the version header the Chromium way" pass
else
  check "guards the version header the Chromium way" fail
fi

if [[ "$output" == *"156.0.8078.73-1"* ]]; then
  check "names the version it wrote" pass
else
  check "names the version it wrote" fail
fi

if [[ -f "$tree/chrome/browser/clair/clair_native_layer.mm" ]]; then
  check "leaves the overlay's files alone" pass
else
  check "leaves the overlay's files alone" fail
fi

# Run against this repository: its header and submodule must pass the checks.
# CI's script job checks out no submodules.
if [[ -f "$script_dir/../ungoogled-chromium/chromium_version.txt" ]]; then
  real_tree="$workdir/real-src"
  mkdir -p "$real_tree/chrome/browser/clair"
  if "$install" "$real_tree" "$script_dir/.." >/dev/null 2>&1 \
      && cmp -s "$script_dir/../native/ClairHost.h" "$real_tree/chrome/browser/clair/ClairHost.h"; then
    check "works with this repository's ClairHost.h and submodule" pass
  else
    check "works with this repository's ClairHost.h and submodule" fail
  fi
else
  echo "skip     works with this repository's ClairHost.h and submodule (no submodule checkout)"
fi

# --- refusals ---------------------------------------------------------------------
reset
run
expect_refusal "refuses to run twice on the same tree" "ClairHost.h already exists"

reset
echo "// stray" >"$tree/chrome/browser/clair/ungoogled_version.h"
expect_refusal "refuses an overlay that ships ungoogled_version.h" "ungoogled_version.h already exists"

reset
rm -rf "$tree/chrome/browser/clair"
expect_refusal "needs the overlay's chrome/browser/clair" "copy the overlay first"

reset
rm "$repo/native/ClairHost.h"
expect_refusal "needs native/ClairHost.h" "no ClairHost.h"

reset
echo '156.0.8078.73";system("x' >"$repo/ungoogled-chromium/chromium_version.txt"
expect_refusal "rejects a Chromium version that isn't one" "not a Chromium version"
if [[ ! -e "$tree/chrome/browser/clair/ClairHost.h" ]]; then
  check "writes nothing when an input is bad" pass
else
  check "writes nothing when an input is bad" fail
fi

reset
echo '1-beta' >"$repo/ungoogled-chromium/revision.txt"
expect_refusal "rejects a revision that isn't a number" "not a number"

reset
rm "$repo/ungoogled-chromium/revision.txt"
expect_refusal "needs revision.txt" "can't read ungoogled-chromium/revision.txt"

if ! "$install" >/dev/null 2>&1 && ! "$install" "$workdir/nowhere" "$repo" >/dev/null 2>&1; then
  check "needs an existing tree" pass
else
  check "needs an existing tree" fail
fi

echo
if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
