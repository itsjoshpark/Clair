#!/bin/bash
# Finds a passed quality run (quality.yml) on a commit with the given file tree,
# so a commit whose exact files have already passed doesn't run the suite again:
# a squash merge of an up-to-date branch that passed has the branch's tree.
#
#   find-quality-pass.sh --tree <sha> [--limit <n>]
#
# Looks through the <n> most recent successful runs (default 30), newest first,
# and prints the URL of the first whose commit has this tree. Exits 0 when it
# finds one, 1 when none matches, and 2 on bad input or when gh fails. Uses gh,
# with GH_TOKEN and GH_REPO from the environment.

set -euo pipefail

tree="" limit=30

die() {
  echo "find-quality-pass: $1" >&2
  exit 2
}

while (( $# > 0 )); do
  case "$1" in
    --tree) tree="${2-}"; shift 2 ;;
    --limit) limit="${2-}"; shift 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done

[[ "$tree" =~ ^[0-9a-f]{40}$ ]] || die "--tree must be a full tree hash"
[[ "$limit" =~ ^[1-9][0-9]{0,2}$ ]] || die "--limit must be a number from 1 to 999"

runs="$(gh run list --workflow quality.yml --status success --limit "$limit" \
  --json headSha,url --jq '.[] | "\(.headSha) \(.url)"')" || die "gh couldn't list the quality runs"

seen=" "
while read -r sha url; do
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || continue
  [[ "$seen" != *" $sha "* ]] || continue
  seen+="$sha "
  commit_tree="$(gh api "repos/{owner}/{repo}/git/commits/$sha" --jq .tree.sha)" ||
    die "gh couldn't read commit $sha"
  if [[ "$commit_tree" == "$tree" ]]; then
    echo "$url"
    exit 0
  fi
done <<<"$runs"

exit 1
