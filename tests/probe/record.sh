#!/bin/bash
# Records part of the screen while the probe runs some lines, then saves the
# recording's frames (tests/probe/README.md).
#
#   record.sh <name> <x,y,w,h> <seconds> [-- <probe line>...]
#
# The rectangle is in screen points, top-left origin, as tools/windows prints
# a window's frame. The movie and frames go to build/probe/rec/<name>/: the
# frames as frames/f<ms>.png, every 1/60 s. The lines start 0.8 s in.

set -euo pipefail
# shellcheck source=tests/probe/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

(($# >= 3)) || { sed -n '/^#   record.sh/p' "${BASH_SOURCE[0]}" | sed 's/^# *//' >&2; exit 2; }
name="$1" rect="$2" seconds="$3"
shift 3
[[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die "the name may use letters, digits, '.', '_' and '-'"
[[ "$rect" =~ ^[0-9]+,[0-9]+,[0-9]+,[0-9]+$ ]] || die "the rectangle is x,y,w,h in points"
[[ "$seconds" =~ ^[0-9]+$ ]] || die "the length is whole seconds"
if (($# > 0)); then
  [[ "$1" == "--" ]] || die "probe lines go after --"
  shift
fi

build_tools
out="$work/rec/$name"
rm -rf "$out"
mkdir -p "$out"
screencapture -x -v -V "$seconds" -R "$rect" "$out/movie.mov" &
capture=$!
sleep 0.8
if (($# > 0)); then
  "$probe_dir/probe.sh" send "$@" >/dev/null || echo "record.sh: a probe line failed" >&2
fi
wait "$capture"
"$bin/frames" "$out/movie.mov" "$out/frames"
echo "$out/frames: $(find "$out/frames" -name 'f*.png' | wc -l | tr -d ' ') frames"
