#!/bin/bash
# Tests for report-quality.sh, with a fake gh that records its calls.

set -uo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/report-quality.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0
sha="0123456789abcdef0123456789abcdef01234567"
url="https://github.com/itsjoshpark/Clair/actions/runs/1"

mkdir "$work/bin"
cat >"$work/bin/gh" <<'FAKE'
#!/bin/bash
printf '%s\n' "$*" >>"$FAKE_GH_LOG"
if [[ "$1 $2" == "issue list" ]]; then
  printf '%s' "${FAKE_OPEN_ISSUE-}"
fi
FAKE
chmod +x "$work/bin/gh"

run() {
  : >"$work/log"
  PATH="$work/bin:$PATH" FAKE_GH_LOG="$work/log" "$script" "$@" >"$work/out" 2>&1
}

check() {
  local name="$1" pattern="$2"
  if grep -qE -- "$pattern" "$work/log"; then
    echo "ok       $name"
  else
    echo "FAIL     $name: no '$pattern' in:"
    cat "$work/log"
    failures=$((failures + 1))
  fi
}

check_not() {
  local name="$1" pattern="$2"
  if grep -qE -- "$pattern" "$work/log"; then
    echo "FAIL     $name: '$pattern' in:"
    cat "$work/log"
    failures=$((failures + 1))
  else
    echo "ok       $name"
  fi
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

printf 'AppTests/testOne()\nUpdateMenuTests/testTwo()\n' >"$work/failed"

# A failure with no open issue opens one, naming the commit, tests and run.
FAKE_OPEN_ISSUE="" run --result failure --commit "$sha" --run-url "$url" --failures "$work/failed"
check_exit "a failure exits 0" 0 $?
check "a failure creates the label" "label create quality-failure"
check "a failure opens an issue" "issue create --title Quality checks failed on main --label quality-failure"
check "the issue names the commit" "$sha"
check "the issue names the first test" 'AppTests/testOne\(\)'
check "the issue names the second test" 'UpdateMenuTests/testTwo\(\)'
check "the issue links the run" "$url"

# A failure with an open issue comments on it, and opens nothing new.
FAKE_OPEN_ISSUE=12 run --result failure --commit "$sha" --run-url "$url" --failures "$work/failed"
check "another failure comments on the open issue" "issue comment 12 --body"
check_not "another failure opens no second issue" "issue create"
check "the comment names the test" 'AppTests/testOne\(\)'

# A failure before the suite had results still says so.
FAKE_OPEN_ISSUE="" run --result failure --commit "$sha" --run-url "$url"
check "a failure without results says so" "No test results"

# A pass closes the open issue.
FAKE_OPEN_ISSUE=12 run --result success --commit "$sha" --run-url "$url"
check "a pass closes the issue" "issue close 12 --comment"
check "the closing comment links the run" "$url"

# A pass with no open issue does nothing.
FAKE_OPEN_ISSUE="" run --result success --commit "$sha" --run-url "$url"
check_not "a pass with no issue closes nothing" "issue close"
check_not "a pass with no issue opens nothing" "issue create"

# A cancelled run changes nothing.
FAKE_OPEN_ISSUE=12 run --result cancelled --commit "$sha" --run-url "$url"
check_not "a cancelled run closes nothing" "issue close"
check_not "a cancelled run comments nothing" "issue comment"

# Bad input is refused.
FAKE_OPEN_ISSUE="" run --result failure --commit 'x; rm' --run-url "$url"
check_exit "a bad commit is refused" 2 $?
FAKE_OPEN_ISSUE="" run --result failure --commit "$sha" --run-url 'not a url'
check_exit "a bad run URL is refused" 2 $?

echo
if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
