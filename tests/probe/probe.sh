#!/bin/bash
# Starts, drives and stops the XCUITest probe (tests/probe/README.md).
#
#   probe.sh start [bundle id]   start the probe and attach it to an app
#                                (default: Arc, company.thebrowser.Browser)
#   probe.sh send <line>...      run probe commands, one per argument, and
#                                print their output
#   probe.sh status              whether it runs, and the end of its log
#   probe.sh stop
#
# Clair (dev.joshuapark.Clair) must be the test copy from launch-clair.sh:
# start refuses to attach to Clair otherwise, since XCUITest would launch
# whichever copy Launch Services prefers.

set -euo pipefail
# shellcheck source=tests/probe/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

queue="$work/queue"
log="$work/probe.log"
derived="$work/DerivedData"
project="$probe_dir/ClairProbe.xcodeproj"
# How long send waits for a batch, beyond its own sleeps.
timeout="${CLAIR_PROBE_TIMEOUT:-60}"

usage() {
  sed -n '/^#   probe.sh start/,/^#   probe.sh stop/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

running() {
  pgrep -f "ClairProbe-Runner" >/dev/null
}

# Runs one batch of lines and prints the output. Fails when a line failed or
# the probe stopped answering.
send() {
  running || die "the probe isn't running; start it with probe.sh start"
  local wait="$timeout" line seconds
  for line in "$@"; do
    if [[ "$line" == sleep\ * ]]; then
      seconds="${line#sleep }"
      wait=$((wait + ${seconds%.*} + 1))
    fi
  done
  rm -f "$queue/out"
  printf '%s\n' "$@" >"$queue/cmd.tmp"
  mv "$queue/cmd.tmp" "$queue/cmd"
  local ticks=$((wait * 5))
  while ((ticks > 0)); do
    if [[ -f "$queue/out" ]] && grep -q '^done ' "$queue/out"; then
      grep -v '^done ' "$queue/out" || true
      ! grep -q '^error: ' "$queue/out"
      return
    fi
    running || die "the probe stopped; see $log"
    sleep 0.2
    ticks=$((ticks - 1))
  done
  die "no answer in ${wait}s; see $log"
}

stop() {
  if running; then
    printf 'quit\n' >"$queue/cmd" 2>/dev/null || true
    sleep 1
  fi
  pkill -f "xcodebuild test-without-building -project $project" 2>/dev/null || true
  pkill -f "ClairProbe-Runner" 2>/dev/null || true
  rm -f "$queue/cmd" "$queue/out"
}

start() {
  local app="${1:-company.thebrowser.Browser}"
  if [[ "$app" == "$clair_id" ]]; then
    test_clair_running || die "start the test copy of Clair with launch-clair.sh first"
  fi
  unregister_other_clairs "$(test_clair)"
  stop
  mkdir -p "$queue"
  local bundle="$derived/Build/Products/Debug/ClairProbe-Runner.app"
  if [[ ! -d "$bundle" || "$probe_dir/ClairProbe/Probe.swift" -nt "$bundle" ]]; then
    echo "Building the probe…"
    xcodebuild -project "$project" -scheme ClairProbe -destination "platform=macOS,arch=arm64" \
      -derivedDataPath "$derived" -quiet build-for-testing >"$work/build.log" 2>&1 \
      || die "the build failed; see $work/build.log"
  fi
  TEST_RUNNER_PROBE_DIR="$queue" TEST_RUNNER_PROBE_HOURS="${CLAIR_PROBE_HOURS:-3}" \
    nohup xcodebuild test-without-building -project "$project" -scheme ClairProbe \
    -destination "platform=macOS,arch=arm64" -derivedDataPath "$derived" \
    -only-testing:ClairProbe/Probe/testProbe >"$log" 2>&1 &
  local ticks=300
  until [[ -f "$queue/out" ]] && grep -q '^ready' "$queue/out"; do
    if grep -q "Not authorized for performing UI testing\|automation mode" "$log" 2>/dev/null; then
      die "macOS refused UI testing; see README.md (one-time setup) and $log"
    fi
    ((ticks-- > 0)) || die "the probe didn't start in 60 s; approve any macOS prompt on screen, or see $log"
    sleep 0.2
  done
  send "app $app" "activate" "sleep 1" "frame"
}

case "${1-}" in
  start) shift; start "$@" ;;
  send) shift; (($# > 0)) || usage; send "$@" ;;
  status)
    if running; then echo "running, attached through $queue"; else echo "not running"; fi
    [[ -f "$log" ]] && tail -5 "$log"
    ;;
  stop) stop ;;
  *) usage ;;
esac
