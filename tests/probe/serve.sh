#!/bin/bash
# Starts or stops the probe's web server (server.py) in the background.
#
#   serve.sh start [port]   default port 8765
#   serve.sh stop

set -euo pipefail
# shellcheck source=tests/probe/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

pidfile="$work/server.pid"

stop() {
  if [[ -f "$pidfile" ]]; then
    kill "$(cat "$pidfile")" 2>/dev/null || true
    rm -f "$pidfile"
  fi
}

case "${1-}" in
  start)
    port="${2:-8765}"
    [[ "$port" =~ ^[0-9]+$ ]] || die "the port must be a number"
    stop
    mkdir -p "$work"
    # -I: run isolated from the current directory and the user's site packages.
    nohup python3 -I "$probe_dir/server.py" "$port" >"$work/server.log" 2>&1 &
    echo $! >"$pidfile"
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      if curl -fs -o /dev/null "http://127.0.0.1:$port/colour.html"; then
        echo "Serving tests/probe/pages on http://localhost:$port/"
        exit 0
      fi
      sleep 0.3
    done
    die "the server didn't start; see $work/server.log"
    ;;
  stop) stop ;;
  *) sed -n '/^#   serve.sh start/,/^#   serve.sh stop/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
