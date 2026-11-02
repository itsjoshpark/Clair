#!/bin/bash
# Tests for apply-overlay.sh. Run directly: ./scripts/apply-overlay.test.sh
#
# Uses a stand-in Chromium tree and stand-in overlays.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
apply="$script_dir/apply-overlay.sh"

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

# Expects a failing run whose error output contains a phrase.
reject() {
  local description="$1" phrase="$2"
  shift 2
  if "$@" >/dev/null 2>"$workdir/err"; then
    check "$description" fail
  elif grep -qF -- "$phrase" "$workdir/err"; then
    check "$description" pass
  else
    check "$description (error did not name: $phrase)" fail
  fi
}

# Makes a stand-in Chromium tree with a few existing files.
make_tree() {
  local tree="$1"
  mkdir -p "$tree/chrome/browser/ui" "$tree/base"
  echo chromium >"$tree/chrome/browser/ui/browser.cc"
  echo chromium >"$tree/base/logging.h"
  echo chromium >"$tree/chrome/BUILD.gn"
  touch -t 202001010000 "$tree/chrome/browser/ui/browser.cc" "$tree/base/logging.h" "$tree/chrome/BUILD.gn"
}

# Lists every file in a tree with its contents' hash, to show nothing changed.
snapshot() {
  (cd "$1" && find . -type f -print0 | sort -z | xargs -0 shasum -a 256)
}

old_time=202001010000

# --- copying ----------------------------------------------------------------
tree="$workdir/src"
overlay="$workdir/overlay"
make_tree "$tree"
mkdir -p "$overlay/chrome/browser/clair" "$overlay/chrome/browser/ui/clair" "$overlay/third_party/clair dir"
echo "host" >"$overlay/chrome/browser/clair/clair_host.mm"
echo "gn" >"$overlay/chrome/browser/clair/BUILD.gn"
echo "ui" >"$overlay/chrome/browser/ui/clair/clair_window.h"
echo "space" >"$overlay/third_party/clair dir/file name.h"
echo "finder" >"$overlay/chrome/browser/clair/.DS_Store"
chmod 755 "$overlay/chrome/browser/clair/BUILD.gn"
touch -t "$old_time" "$overlay/chrome/browser/clair/clair_host.mm"
touch "$workdir/stamp"
sleep 1

if "$apply" "$tree" "$overlay" >"$workdir/log" 2>&1; then
  check "copies an overlay into a tree" pass
else
  cat "$workdir/log"
  check "copies an overlay into a tree" fail
fi

wrong=0
for path in chrome/browser/clair/clair_host.mm chrome/browser/clair/BUILD.gn \
    chrome/browser/ui/clair/clair_window.h "third_party/clair dir/file name.h"; do
  cmp -s "$overlay/$path" "$tree/$path" || {
    echo "         not copied: $path"
    wrong=$((wrong + 1))
  }
done
[[ "$wrong" -eq 0 ]] && check "copies every file to its path, including names with spaces" pass ||
  check "copies every file to its path, including names with spaces" fail

[[ "$tree/chrome/browser/clair/clair_host.mm" -nt "$workdir/stamp" ]] &&
  check "gives copies a new modification time, so the layer records them" pass ||
  check "gives copies a new modification time, so the layer records them" fail

[[ -x "$tree/chrome/browser/clair/BUILD.gn" ]] && check "keeps the executable bit" pass ||
  check "keeps the executable bit" fail

[[ ! -e "$tree/chrome/browser/clair/.DS_Store" ]] && check "skips .DS_Store" pass ||
  check "skips .DS_Store" fail

[[ "$(cat "$tree/chrome/browser/ui/browser.cc")" == chromium ]] &&
  check "leaves Chromium's files alone" pass || check "leaves Chromium's files alone" fail

grep -qF "added chrome/browser/clair/clair_host.mm" "$workdir/log" &&
  grep -qF "copied 4 files" "$workdir/log" &&
  check "logs every copy and the count" pass || check "logs every copy and the count" fail

# --- no overlay -------------------------------------------------------------
tree="$workdir/src-empty"
make_tree "$tree"
before="$(snapshot "$tree")"
if "$apply" "$tree" "$workdir/missing-overlay" >"$workdir/log" 2>&1 &&
    [[ "$(snapshot "$tree")" == "$before" ]]; then
  check "a missing overlay directory copies nothing and succeeds" pass
else
  cat "$workdir/log"
  check "a missing overlay directory copies nothing and succeeds" fail
fi

mkdir -p "$workdir/empty-overlay/only/dirs"
if "$apply" "$tree" "$workdir/empty-overlay" >/dev/null 2>&1 &&
    [[ "$(snapshot "$tree")" == "$before" ]]; then
  check "an overlay with only directories copies nothing and succeeds" pass
else
  check "an overlay with only directories copies nothing and succeeds" fail
fi

# --- refusals ---------------------------------------------------------------
# Each case adds one bad entry to a valid overlay; nothing may be copied.
refuse_case() {
  local description="$1" phrase="$2" name="$3"
  local tree="$workdir/src-$name" overlay="$workdir/overlay-$name"
  make_tree "$tree"
  mkdir -p "$overlay/chrome/browser/clair"
  echo "host" >"$overlay/chrome/browser/clair/clair_host.mm"
  "setup_$name" "$tree" "$overlay"
  local before
  before="$(snapshot "$tree")"
  reject "$description" "$phrase" "$apply" "$tree" "$overlay"
  [[ "$(snapshot "$tree")" == "$before" ]] && check "  and copies nothing" pass ||
    check "  and copies nothing" fail
}

setup_shadow() {
  mkdir -p "$2/chrome/browser/ui"
  echo "mine" >"$2/chrome/browser/ui/browser.cc"
}
refuse_case "refuses a file that shadows a Chromium file, and names it" \
  "shadows an existing Chromium file: chrome/browser/ui/browser.cc" shadow

setup_shadow_link() {
  ln -s ../base/logging.h "$1/chrome/link.h"
  echo "mine" >"$2/chrome/link.h"
}
refuse_case "refuses a file that shadows a symlink in the tree" \
  "shadows an existing Chromium file: chrome/link.h" shadow_link

setup_through_file() {
  mkdir -p "$2/chrome/BUILD.gn"
  echo "mine" >"$2/chrome/BUILD.gn/inner.h"
}
refuse_case "refuses a path that goes through a file in the tree" \
  "goes through a file in the Chromium tree: chrome/BUILD.gn" through_file

setup_through_link() {
  ln -s /tmp "$1/chrome/outside"
  mkdir -p "$2/chrome/outside"
  echo "mine" >"$2/chrome/outside/escape.h"
}
refuse_case "refuses a path that goes through a symlinked directory" \
  "goes through a symlink in the Chromium tree: chrome/outside" through_link

setup_symlink() {
  ln -s clair_host.mm "$2/chrome/browser/clair/alias.mm"
}
refuse_case "refuses a symlink in the overlay" \
  "symlinks aren't allowed in the overlay: chrome/browser/clair/alias.mm" symlink

reject "refuses a missing Chromium tree" "Chromium source not found" \
  "$apply" "$workdir/no-such-tree" "$workdir/overlay"
reject "refuses a missing argument" "usage" "$apply"

echo
if [[ "$failures" -eq 0 ]]; then
  echo "All tests passed"
else
  echo "$failures test(s) failed"
fi
exit "$failures"
