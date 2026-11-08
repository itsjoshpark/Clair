#!/bin/bash
# Tests for find-quality-pass.sh, with a fake gh that serves runs and commits.

set -uo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/find-quality-pass.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

commit_a="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
commit_b="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
tree_1="1111111111111111111111111111111111111111"
tree_2="2222222222222222222222222222222222222222"
tree_3="3333333333333333333333333333333333333333"
url_a="https://github.com/itsjoshpark/Clair/actions/runs/10"
url_b="https://github.com/itsjoshpark/Clair/actions/runs/20"

# FAKE_RUNS: what `gh run list` prints. FAKE_TREES: "commit tree" lines for
# `gh api`. FAKE_FAIL: a subcommand that fails.
mkdir "$work/bin"
cat >"$work/bin/gh" <<'FAKE'
#!/bin/bash
printf '%s\n' "$*" >>"$FAKE_GH_LOG"
[[ "$1" != "${FAKE_FAIL-}" ]] || exit 1
case "$1" in
  run) printf '%s' "${FAKE_RUNS-}" ;;
  api)
    sha="${2##*/}"
    while read -r commit tree; do
      if [[ "$commit" == "$sha" ]]; then echo "$tree"; fi
    done <<<"${FAKE_TREES-}"
    ;;
esac
FAKE
chmod +x "$work/bin/gh"

run() {
  : >"$work/log"
  PATH="$work/bin:$PATH" FAKE_GH_LOG="$work/log" "$script" "$@" >"$work/out" 2>&1
}

check_exit() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "ok       $name"
  else
    echo "FAIL     $name: exit $actual, expected $expected"
    cat "$work/out"
    failures=$((failures + 1))
  fi
}

check_out() {
  local name="$1" expected="$2"
  if [[ "$(cat "$work/out")" == "$expected" ]]; then
    echo "ok       $name"
  else
    echo "FAIL     $name: printed '$(cat "$work/out")', expected '$expected'"
    failures=$((failures + 1))
  fi
}

check_calls() {
  local name="$1" pattern="$2" expected="$3" count
  count="$(grep -cE -- "$pattern" "$work/log")"
  if [[ "$count" == "$expected" ]]; then
    echo "ok       $name"
  else
    echo "FAIL     $name: $count calls matching '$pattern', expected $expected"
    cat "$work/log"
    failures=$((failures + 1))
  fi
}

export FAKE_RUNS="$commit_a $url_a
$commit_b $url_b
$commit_a https://github.com/itsjoshpark/Clair/actions/runs/5
"
export FAKE_TREES="$commit_a $tree_1
$commit_b $tree_2"

# A run on a commit with the same tree is found.
run --tree "$tree_2"
check_exit "a matching tree is found" 0 $?
check_out "it prints the matching run's URL" "$url_b"
check_calls "it asks for passed quality runs" "run list --workflow quality.yml --status success --limit 30" 1

# The newest matching run wins, and a commit is looked up once.
run --tree "$tree_3"
check_exit "no matching tree exits 1" 1 $?
check_out "no match prints nothing" ""
check_calls "each commit is looked up once" "^api " 2
run --tree "$tree_1"
check_out "the newest matching run wins" "$url_a"

# The limit is passed on.
run --tree "$tree_1" --limit 5
check_calls "the limit is passed on" "--limit 5" 1

# No passed runs at all.
FAKE_RUNS="" run --tree "$tree_1"
check_exit "no runs exits 1" 1 $?

# gh failures aren't mistaken for "no match".
FAKE_FAIL=run run --tree "$tree_1"
check_exit "a failed run list exits 2" 2 $?
FAKE_FAIL=api run --tree "$tree_1"
check_exit "a failed commit lookup exits 2" 2 $?

# Bad input is refused.
run --tree "abc"
check_exit "a short tree is refused" 2 $?
run --tree "$tree_1; rm"
check_exit "a tree with shell in it is refused" 2 $?
run --tree "$tree_1" --limit 0
check_exit "a zero limit is refused" 2 $?
run --tree "$tree_1" --limit "5 --repo x"
check_exit "a limit with options in it is refused" 2 $?

echo
if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
