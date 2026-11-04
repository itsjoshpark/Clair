#!/bin/bash
# Keeps the quality-failure issue up to date with the result of a quality run on
# main (change 1 design D12). A failure opens the issue, or comments on the open
# one; a pass closes it.
#
#   report-quality.sh --result <success|failure> --commit <sha> --run-url <url>
#                     [--failures <file>]
#
# <file> names one failing test per line. Without any, the run failed before
# the runtime suite had results. Other results, such as a cancelled run, change
# nothing. Uses gh, with GH_TOKEN and GH_REPO from the environment.

set -euo pipefail

label="quality-failure"
result="" commit="" run_url="" failures_file=""

die() {
  echo "report-quality: $1" >&2
  exit 2
}

while (( $# > 0 )); do
  case "$1" in
    --result) result="${2-}"; shift 2 ;;
    --commit) commit="${2-}"; shift 2 ;;
    --run-url) run_url="${2-}"; shift 2 ;;
    --failures) failures_file="${2-}"; shift 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done

[[ "$commit" =~ ^[0-9a-f]{7,40}$ ]] || die "--commit must be a commit hash"
[[ "$run_url" =~ ^https://[^[:space:]]+$ ]] || die "--run-url must be an https URL"

open_issue() {
  gh issue list --state open --label "$label" --limit 1 --json number --jq '.[0].number // empty'
}

case "$result" in
  success)
    issue="$(open_issue)"
    if [[ -n "$issue" ]]; then
      gh issue close "$issue" --comment "Quality checks passed on $commit: $run_url"
      echo "Closed #$issue"
    else
      echo "No open $label issue to close"
    fi
    ;;
  failure)
    tests=""
    if [[ -n "$failures_file" && -s "$failures_file" ]]; then
      while IFS= read -r test; do
        [[ -n "$test" ]] && tests+="- \`$test\`"$'\n'
      done <"$failures_file"
    fi
    [[ -n "$tests" ]] || tests="No test results: the run failed before the runtime suite finished. See the run's log."$'\n'
    body="Quality checks failed on $commit.

Failing tests:

$tests
Run: $run_url"
    issue="$(open_issue)"
    if [[ -n "$issue" ]]; then
      gh issue comment "$issue" --body "$body"
      echo "Updated #$issue"
    else
      gh label create "$label" --color D93F0B \
        --description "A quality run on main failed" --force >/dev/null
      gh issue create --title "Quality checks failed on main" --label "$label" --body "$body"
    fi
    ;;
  *)
    echo "Nothing to report for result '$result'"
    ;;
esac
