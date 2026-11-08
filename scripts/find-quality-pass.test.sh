#!/bin/bash
# Tests for find-quality-pass.sh, in a scratch repository with a fake gh that
# serves quality runs and reads commits' trees from that repository.

set -uo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/find-quality-pass.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

repo="$work/repo"
git init -q "$repo"
git -C "$repo" config user.name test
git -C "$repo" config user.email test@example.com
git -C "$repo" config commit.gpgsign false

# commit <message> <path>...: writes each path and commits, printing the hash.
commit() {
  local message="$1" path
  shift
  for path in "$@"; do
    mkdir -p "$repo/$(dirname "$path")"
    echo "$message" >>"$repo/$path"
  done
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "$message"
  git -C "$repo" rev-parse HEAD
}

code_1="$(commit "code 1" native/app.swift)"
docs_1="$(commit "docs 1" docs/guide.md)"
code_2="$(commit "code 2" native/app.swift)"
docs_2="$(commit "docs 2" openspec/specs/a/spec.md .changes/unreleased/x.yaml CHANGELOG.md)"
code_md="$(commit "code md" native/README.md)"
# A branch commit with code_1's tree, as a squash merge has its branch's tree.
branch_1="$(git -C "$repo" commit-tree "$(git -C "$repo" rev-parse "$code_1^{tree}")" -m branch)"

url() { echo "https://github.com/itsjoshpark/Clair/actions/runs/$1"; }

mkdir "$work/bin"
cat >"$work/bin/gh" <<'FAKE'
#!/bin/bash
printf '%s\n' "$*" >>"$FAKE_GH_LOG"
[[ "$1" != "${FAKE_FAIL-}" ]] || exit 1
case "$1" in
  run) printf '%s' "${FAKE_RUNS-}" ;;
  api) git -C "$FAKE_REPO" rev-parse "${2##*/}^{tree}" ;;
esac
FAKE
chmod +x "$work/bin/gh"

run() {
  : >"$work/log"
  (cd "$repo" && PATH="$work/bin:$PATH" FAKE_GH_LOG="$work/log" FAKE_REPO="$repo" \
    "$script" "$@" >"$work/out" 2>"$work/err")
}

check_exit() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "ok       $name"
  else
    echo "FAIL     $name: exit $actual, expected $expected"
    cat "$work/out" "$work/err"
    failures=$((failures + 1))
  fi
}

check_out() {
  local name="$1" expected="$2"
  if [[ "$(cat "$work/out")" == "$expected" ]]; then
    echo "ok       $name"
  else
    echo "FAIL     $name: printed '$(cat "$work/out")', expected '$expected'"
    cat "$work/err"
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

# Same tree: a squash merge of a branch that passed.
FAKE_RUNS="$branch_1 $(url 1)
"
export FAKE_RUNS
run --commit "$code_1"
check_exit "a run on the same tree is found" 0 $?
check_out "it prints that run's URL" "$(url 1)"
check_calls "it asks for passed quality runs" "run list --workflow quality.yml --status success --limit 30" 1

# HEAD by default.
run
check_exit "no match for HEAD exits 1" 1 $?

# A docs-only commit is covered by its parent's run.
run --commit "$docs_1"
check_exit "a docs-only commit is covered by its parent's run" 0 $?
check_out "it prints the parent's run" "$(url 1)"

# A code change isn't covered by an older run.
run --commit "$code_2"
check_exit "a code change isn't covered by an older run" 1 $?
check_out "no match prints nothing" ""

# openspec/, .changes/ and root Markdown count as documentation.
FAKE_RUNS="$code_2 $(url 2)
" run --commit "$docs_2"
check_exit "openspec, .changes and root Markdown are documentation" 0 $?
check_out "it prints the code commit's run" "$(url 2)"

# Markdown outside the root and the documentation folders is not.
FAKE_RUNS="$docs_2 $(url 3)
" run --commit "$code_md"
check_exit "Markdown in a code folder isn't documentation" 1 $?

# The newest covering run wins, and each run's commit is read once.
FAKE_RUNS="$code_1 $(url 5)
$branch_1 $(url 4)
$code_1 $(url 3)
" run --commit "$docs_1"
check_out "the newest covering run wins" "$(url 5)"
check_calls "each commit is read once" "^api " 2

# The walk stops at the first commit.
FAKE_RUNS="" run --commit "$docs_1"
check_exit "no runs exits 1" 1 $?

# The limit is passed on.
run --commit "$code_1" --limit 5
check_calls "the limit is passed on" "--limit 5" 1

# gh failures aren't mistaken for "no run".
FAKE_FAIL=run run --commit "$code_1"
check_exit "a failed run list exits 2" 2 $?
FAKE_RUNS="$code_1 $(url 1)
" FAKE_FAIL=api run --commit "$code_1"
check_exit "a failed commit lookup exits 2" 2 $?

# Bad input is refused.
run --commit "nosuchcommit"
check_exit "an unknown commit is refused" 2 $?
run --commit "--output=x"
check_exit "an option as the commit is refused" 2 $?
run --commit "$code_1" --limit 0
check_exit "a zero limit is refused" 2 $?
run --commit "$code_1" --limit "5 --repo x"
check_exit "a limit with options in it is refused" 2 $?

echo
if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
