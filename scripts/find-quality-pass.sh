#!/bin/bash
# Finds a passed quality run (quality.yml) that covers a commit, so the suite
# doesn't run again on files that have already passed (build-pipeline spec,
# "Quality checks reuse a passed run"). A run covers the commit when:
#
# - its commit has the same file tree, as after squash-merging an up-to-date
#   branch whose quality run passed; or
# - the commit changes only documentation (openspec/, docs/, .changes/ and
#   Markdown files at the repository root) and a run covers its first parent.
#
#   find-quality-pass.sh [--commit <rev>] [--limit <n>]
#
# Looks through the <n> most recent successful runs (default 30) and prints the
# URL of the newest that covers <rev> (default HEAD). Exits 0 when it finds one,
# 1 when none does, and 2 on bad input or when gh fails. Run it in a checkout
# with the history it should walk back through. Uses gh, with GH_TOKEN and
# GH_REPO from the environment.

set -euo pipefail

rev=HEAD limit=30
# How many documentation-only commits it walks back through.
max_walk=20

die() {
  echo "find-quality-pass: $1" >&2
  exit 2
}

while (( $# > 0 )); do
  case "$1" in
    --commit) rev="${2-}"; shift 2 ;;
    --limit) limit="${2-}"; shift 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done

[[ -n "$rev" && "$rev" != -* ]] || die "--commit must name a commit"
commit="$(git rev-parse --verify --quiet "$rev^{commit}")" || die "no commit '$rev' in this checkout"
[[ "$limit" =~ ^[1-9][0-9]{0,2}$ ]] || die "--limit must be a number from 1 to 999"

# Every changed path is documentation.
docs_only() {
  local path
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    case "$path" in
      openspec/* | docs/* | .changes/*) ;;
      */*) return 1 ;;
      *.md) ;;
      *) return 1 ;;
    esac
  done <<<"$1"
}

runs="$(gh run list --workflow quality.yml --status success --limit "$limit" \
  --json headSha,url --jq '.[] | "\(.headSha) \(.url)"')" || die "gh couldn't list the quality runs"

# "tree url" for each run, newest first, reading each commit's tree once.
passed="" trees=" "
while read -r sha url; do
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || continue
  if [[ "$trees" == *" $sha="* ]]; then
    tree="${trees#* "$sha"=}"
    tree="${tree%% *}"
  else
    tree="$(gh api "repos/{owner}/{repo}/git/commits/$sha" --jq .tree.sha)" ||
      die "gh couldn't read commit $sha"
    [[ "$tree" =~ ^[0-9a-f]{40}$ ]] || die "commit $sha has no tree"
    trees+="$sha=$tree "
  fi
  passed+="$tree $url"$'\n'
done <<<"$runs"

for (( step = 0; step <= max_walk; step++ )); do
  tree="$(git rev-parse "$commit^{tree}")"
  while read -r run_tree url; do
    if [[ "$run_tree" == "$tree" ]]; then
      (( step == 0 )) || echo "Covered through $step documentation-only commit(s), from ${commit:0:7}" >&2
      echo "$url"
      exit 0
    fi
  done <<<"$passed"
  parent="$(git rev-parse --verify --quiet "$commit^1")" || break
  docs_only "$(git diff --name-only "$parent" "$commit")" || break
  commit="$parent"
done

exit 1
