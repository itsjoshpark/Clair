#!/bin/bash
# Tests for filter-domain-substitution.sh. Run directly:
# ./scripts/filter-domain-substitution.test.sh

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
filter="$script_dir/filter-domain-substitution.sh"

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

printf '%s\n' a/one.cc a/one.cc.bak b/two.json c/three.h >"$workdir/list"

# Filtering: only exact paths go, and comments and blank lines are ignored.
printf '%s\n' '# A comment' '' b/two.json a/one.cc >"$workdir/exclude"
if "$filter" "$workdir/list" "$workdir/exclude" "$workdir/out" 2>"$workdir/err"; then
  printf '%s\n' a/one.cc.bak c/three.h >"$workdir/expected"
  if cmp -s "$workdir/out" "$workdir/expected"; then
    check "leaves out exactly the listed paths" pass
  else
    check "leaves out exactly the listed paths" fail
  fi
else
  check "leaves out exactly the listed paths (run failed: $(cat "$workdir/err"))" fail
fi

# An exclude list with nothing in it copies the list.
printf '%s\n' '# Nothing yet' >"$workdir/empty"
"$filter" "$workdir/list" "$workdir/empty" "$workdir/out-empty" 2>/dev/null
if cmp -s "$workdir/out-empty" "$workdir/list"; then
  check "an empty exclude list changes nothing" pass
else
  check "an empty exclude list changes nothing" fail
fi

# A listed file that isn't in the substitution list stops the run and is named,
# and no output is written.
printf '%s\n' b/two.json gone/renamed.cc >"$workdir/stale"
if "$filter" "$workdir/list" "$workdir/stale" "$workdir/out-stale" 2>"$workdir/err"; then
  check "a stale entry stops the run" fail
elif grep -qF "gone/renamed.cc" "$workdir/err" && [[ ! -e "$workdir/out-stale" ]]; then
  check "a stale entry stops the run, is named and writes nothing" pass
else
  check "a stale entry stops the run, is named and writes nothing" fail
fi

# A substitution list that is missing is an error.
if "$filter" "$workdir/nope" "$workdir/exclude" "$workdir/out-none" 2>/dev/null; then
  check "a missing substitution list fails" fail
else
  check "a missing substitution list fails" pass
fi

if [[ "$failures" -gt 0 ]]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "All tests passed"
