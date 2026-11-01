#!/bin/bash
# Tests for release-preflight.sh. Run directly: ./scripts/release-preflight.test.sh

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
preflight="$script_dir/release-preflight.sh"

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

# A throwaway repository with COMMITS commits, a version.txt, notes and an
# appcast whose newest entry is NEWEST (empty for none).
make_repo() {
  local dir="$1" commits="$2" newest="$3"
  rm -rf "$dir"
  mkdir -p "$dir/.sparkle/notes"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name test
  echo "0.1.0" >"$dir/version.txt"
  printf -- '- New:\n' >"$dir/.sparkle/notes/TEMPLATE.md"
  printf -- '- New: Something\n' >"$dir/.sparkle/notes/next.md"
  {
    echo '<?xml version="1.0" standalone="yes"?>'
    echo '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel><language>en</language>'
    if [[ -n "$newest" ]]; then
      echo "<item><sparkle:version>$newest</sparkle:version></item>"
    fi
    echo '</channel></rss>'
  } >"$dir/.sparkle/appcast.xml"
  local i
  for ((i = 1; i <= commits; i++)); do
    git -C "$dir" commit -q --allow-empty -m "commit $i"
  done
}

run() {
  local dir="$1"; shift
  (cd "$dir" && "$preflight" "$@")
}

expect_output() {
  local description="$1" dir="$2" expected="$3"; shift 3
  local output
  if output="$(run "$dir" "$@" 2>/dev/null)" && [[ "$output" == "$expected" ]]; then
    check "$description" pass
  else
    check "$description" fail
    echo "         expected: $(tr '\n' ' ' <<<"$expected")"
    echo "         got:      $(tr '\n' ' ' <<<"${output-}")"
  fi
}

expect_refusal() {
  local description="$1" dir="$2" message="$3"; shift 3
  local output
  if output="$(run "$dir" "$@" 2>&1)"; then
    check "$description" fail
  elif [[ "$output" == *"$message"* ]]; then
    check "$description" pass
  else
    check "$description" fail
    echo "         expected message containing: $message"
    echo "         got: $output"
  fi
}

repo="$workdir/repo"

# --- versions -----------------------------------------------------------------
make_repo "$repo" 5 ""
expect_output "first release uses version.txt" "$repo" $'version=0.1.0\nbuild=6\ntag=v0.1.0' --bump patch
expect_output "first release ignores a minor bump" "$repo" $'version=0.1.0\nbuild=6\ntag=v0.1.0' --bump minor

make_repo "$repo" 5 ""
git -C "$repo" tag v0.1.0
expect_output "patch bump: 0.1.0 -> 0.1.1" "$repo" $'version=0.1.1\nbuild=6\ntag=v0.1.1' --bump patch

make_repo "$repo" 5 ""
git -C "$repo" tag v0.1.3
expect_output "minor bump: 0.1.3 -> 0.2.0" "$repo" $'version=0.2.0\nbuild=6\ntag=v0.2.0' --bump minor
expect_output "major bump: 0.1.3 -> 1.0.0" "$repo" $'version=1.0.0\nbuild=6\ntag=v1.0.0' --bump major

make_repo "$repo" 5 ""
git -C "$repo" tag v0.1.9
git -C "$repo" tag v0.1.10
expect_output "uses the highest tag by version, not by name" "$repo" $'version=0.1.11\nbuild=6\ntag=v0.1.11' --bump patch

# Engine prereleases (design D10) tag commits too, often newer than the last
# release; they must never count as a version.
make_repo "$repo" 5 ""
git -C "$repo" tag v0.1.0 HEAD~2
git -C "$repo" tag chromium-engine-0123456789abcdef
git -C "$repo" tag -a chromium-engine-fedcba9876543210 -m "engine" HEAD~1
expect_output "ignores chromium-engine-* tags newer than the latest v* tag" "$repo" $'version=0.1.1\nbuild=6\ntag=v0.1.1' --bump patch

make_repo "$repo" 5 ""
git -C "$repo" tag chromium-engine-0123456789abcdef
expect_output "an engine tag alone is still a first release" "$repo" $'version=0.1.0\nbuild=6\ntag=v0.1.0' --bump patch

# --- build number -----------------------------------------------------------
make_repo "$repo" 5 "5"
expect_output "build one above the newest appcast entry is allowed" "$repo" $'version=0.1.0\nbuild=6\ntag=v0.1.0' --bump patch

make_repo "$repo" 5 "6"
expect_refusal "refuses a build equal to the newest appcast entry" "$repo" "Sparkle would never offer" --bump patch

make_repo "$repo" 5 "40"
expect_refusal "refuses a build below the newest appcast entry" "$repo" "Sparkle would never offer" --bump patch

# --- notes ------------------------------------------------------------------
make_repo "$repo" 5 ""
rm "$repo/.sparkle/notes/next.md"
expect_refusal "refuses missing release notes" "$repo" "missing" --bump patch

make_repo "$repo" 5 ""
cp "$repo/.sparkle/notes/TEMPLATE.md" "$repo/.sparkle/notes/next.md"
expect_refusal "refuses unedited template notes" "$repo" "unedited template" --bump patch

make_repo "$repo" 5 ""
git -C "$repo" tag v0.1.0
printf -- '- Old\n' >"$repo/.sparkle/notes/0.1.1.md"
expect_refusal "refuses to overwrite archived notes" "$repo" "already exists" --bump patch

# --- inputs -----------------------------------------------------------------
make_repo "$repo" 5 ""
expect_refusal "requires --bump" "$repo" "--bump is required"
expect_refusal "rejects an unknown bump" "$repo" "unknown bump" --bump huge

make_repo "$repo" 5 ""
echo "0.1" >"$repo/version.txt"
expect_refusal "rejects a malformed version.txt" "$repo" "must hold X.Y.Z" --bump patch

make_repo "$repo" 5 ""
rm "$repo/version.txt"
expect_refusal "refuses a first release without version.txt" "$repo" "no v* tag" --bump patch

echo
if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
