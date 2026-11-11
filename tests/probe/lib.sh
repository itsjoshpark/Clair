#!/bin/bash
# Shared by the probe scripts (tests/probe/README.md). Sourced, not run.

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
probe_dir="$root/tests/probe"
# Everything the scripts make goes here; build/ is ignored by git.
work="${CLAIR_PROBE_WORK:-$root/build/probe}"
bin="$work/bin"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
clair_id=dev.joshuapark.Clair

die() {
  echo "$(basename "$0"): $1" >&2
  exit 1
}

# The packaged test copy of Clair, once launch-clair.sh has made it.
test_clair() {
  cat "$work/clair-app" 2>/dev/null
}

test_clair_running() {
  local app
  app="$(test_clair)"
  [[ -n "$app" ]] && pgrep -f "^$app/Contents/MacOS/Clair( |$)" >/dev/null
}

# Every copy of Clair Launch Services knows, one path per line.
registered_clairs() {
  "$lsregister" -dump | awk -v id="$clair_id" '
    /^path:/ { sub(/^path: +/, ""); sub(/ \(0x[0-9a-f]+\)$/, ""); path = $0 }
    $1 == "identifier:" && $2 == id { print path }' | sort -u
}

# Unregisters every copy of Clair but `$1` and installed ones in
# /Applications, so XCUITest attaches to the test copy and never launches
# another, such as the runner's build, with the owner's real profile.
unregister_other_clairs() {
  local keep="$1" app
  while IFS= read -r app; do
    [[ "$app" == "$keep" || "$app" == /Applications/* ]] && continue
    "$lsregister" -u "$app" 2>/dev/null || true
  done < <(registered_clairs)
}

# Compiles the Swift tools into $bin when they're missing or older than their
# sources.
build_tools() {
  local source name
  mkdir -p "$bin"
  for source in "$probe_dir"/tools/*.swift; do
    name="$(basename "$source" .swift)"
    if [[ ! -x "$bin/$name" || "$source" -nt "$bin/$name" ]]; then
      xcrun swiftc -O -o "$bin/$name" "$source" || die "couldn't compile tools/$name.swift"
    fi
  done
}
