#!/bin/bash
# Packages the checkout's ClairUI and launches a test copy of Clair for the
# probe (tests/probe/README.md), with a fresh throwaway profile and the mock
# keychain, so the owner's Clair data and keychain item stay untouched.
#
#   launch-clair.sh [--port <n>] [url]
#
# --port opens the DevTools protocol on that port. Launching again quits the
# previous test copy first; the probe stops with it, so start it again.
#
# Like scripts/run-local.sh, it needs the published engine for the
# checkout's engine key.

set -euo pipefail
# shellcheck source=tests/probe/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

port="" url=""
while (($# > 0)); do
  case "$1" in
    --port) port="${2-}"; shift 2 || die "--port needs a number" ;;
    -h | --help) sed -n '/^#   launch-clair.sh/p' "${BASH_SOURCE[0]}" | sed 's/^# *//' >&2; exit 2 ;;
    *) url="$1"; shift ;;
  esac
done
[[ -z "$port" || "$port" =~ ^[0-9]+$ ]] || die "--port needs a number"

mkdir -p "$work"
build_tools
echo "Packaging ClairUI…"
"$root/scripts/run-local.sh" --no-launch --work "$work/clair" >"$work/package.log" 2>&1 \
  || { tail -5 "$work/package.log" >&2; die "packaging failed; see $work/package.log"; }
app="$(tail -1 "$work/package.log")"
[[ -d "$app" ]] || die "packaging printed no app; see $work/package.log"

# Quit the previous test copy, and only it.
if test_clair_running; then
  pkill -f "^$(test_clair)/Contents/MacOS/Clair( |$)" || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do test_clair_running || break; sleep 0.5; done
fi
echo "$app" >"$work/clair-app"
"$lsregister" -f "$app"
unregister_other_clairs "$app"

profile="$work/profile"
rm -rf "$profile"
args=(--user-data-dir="$profile" --use-mock-keychain --no-first-run --no-default-browser-check)
[[ -n "$port" ]] && args+=(--remote-debugging-port="$port")
[[ -n "$url" ]] && args+=("$url")
open -n "$app" --args "${args[@]}"

for _ in $(seq 1 40); do
  if "$bin/windows" Clair | grep -q "on screen"; then
    "$bin/windows" Clair
    exit 0
  fi
  sleep 0.5
done
die "Clair showed no window in 20 s"
