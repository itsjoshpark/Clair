#!/bin/bash
# Tests for release-preflight.sh. Run directly: ./scripts/release-preflight.test.sh

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
preflight="$script_dir/release-preflight.sh"
repo_root="$script_dir/.."
fragments=0

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

# A throwaway repository with COMMITS commits, Clair's Changie configuration, an
# appcast whose newest entry is NEWEST (empty for none), and the releases named
# after that, as .changes/<version>.md files.
make_repo() {
  local dir="$1" commits="$2" newest="$3"
  shift 3
  rm -rf "$dir"
  mkdir -p "$dir/.sparkle" "$dir/.changes/unreleased"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name test
  cp "$repo_root/.changie.yaml" "$dir/"
  cp "$repo_root/.changes/header.tpl.md" "$dir/.changes/"
  echo "0.1.0" >"$dir/version.txt"
  local release
  for release in "$@"; do
    printf '## %s - 2026-01-01\n\n- Fixed: Something\n' "$release" >"$dir/.changes/$release.md"
  done
  {
    echo '<?xml version="1.0" standalone="yes"?>'
    echo '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel><language>en</language>'
    if [[ -n "$newest" ]]; then
      echo "<item><sparkle:version>$newest</sparkle:version></item>"
    fi
    echo '</channel></rss>'
  } >"$dir/.sparkle/appcast.xml"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "commit 1"
  local i
  for ((i = 2; i <= commits; i++)); do
    git -C "$dir" commit -q --allow-empty -m "commit $i"
  done
}

# fragment DIR KIND [BODY]
fragment() {
  fragments=$((fragments + 1))
  printf 'kind: %s\nbody: %s\ntime: 2026-01-01T00:00:%02d.000000000Z\n' "$2" "${3-Something}" "$fragments" \
    >"$1/.changes/unreleased/$2-$fragments.yaml"
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
fragment "$repo" New
expect_output "first release: a New fragment gives 0.1.0, with no leading v" "$repo" $'version=0.1.0\nbuild=6\ntag=v0.1.0' --release-type auto

make_repo "$repo" 5 "" 0.1.3
fragment "$repo" New
fragment "$repo" Fixed
expect_output "auto with a New fragment: 0.1.3 -> 0.2.0" "$repo" $'version=0.2.0\nbuild=6\ntag=v0.2.0' --release-type auto

make_repo "$repo" 5 "" 0.1.3
fragment "$repo" Fixed
fragment "$repo" Updated
expect_output "auto with only other kinds: 0.1.3 -> 0.1.4" "$repo" $'version=0.1.4\nbuild=6\ntag=v0.1.4' --release-type auto
expect_output "patch: 0.1.3 -> 0.1.4" "$repo" $'version=0.1.4\nbuild=6\ntag=v0.1.4' --release-type patch
expect_output "minor: 0.1.3 -> 0.2.0" "$repo" $'version=0.2.0\nbuild=6\ntag=v0.2.0' --release-type minor
expect_output "major: 0.1.3 -> 1.0.0" "$repo" $'version=1.0.0\nbuild=6\ntag=v1.0.0' --release-type major

make_repo "$repo" 5 "" 0.1.9 0.1.10
fragment "$repo" Fixed
expect_output "uses the highest release by version, not by name" "$repo" $'version=0.1.11\nbuild=6\ntag=v0.1.11' --release-type auto

before="$(git -C "$repo" status --porcelain; ls -a "$repo/.changes" "$repo/.changes/unreleased")"
run "$repo" --release-type auto >/dev/null 2>&1
if [[ "$before" == "$(git -C "$repo" status --porcelain; ls -a "$repo/.changes" "$repo/.changes/unreleased")" && "$(cat "$repo/version.txt")" == 0.1.0 ]]; then
  check "changes nothing" pass
else
  check "changes nothing" fail
fi

# --- build number -----------------------------------------------------------
make_repo "$repo" 5 "5"
fragment "$repo" New
expect_output "build one above the newest appcast entry is allowed" "$repo" $'version=0.1.0\nbuild=6\ntag=v0.1.0' --release-type auto

make_repo "$repo" 5 "6"
fragment "$repo" New
expect_refusal "refuses a build equal to the newest appcast entry" "$repo" "Sparkle would never offer" --release-type auto

make_repo "$repo" 5 "40"
fragment "$repo" New
expect_refusal "refuses a build below the newest appcast entry" "$repo" "Sparkle would never offer" --release-type auto

# --- notes ------------------------------------------------------------------
make_repo "$repo" 5 "" 0.1.0
expect_refusal "refuses no fragments with auto" "$repo" "no fragments" --release-type auto
expect_refusal "refuses no fragments with an explicit bump" "$repo" "no fragments" --release-type patch

echo "**Note**: Only a header" >"$repo/.changes/unreleased/header.md"
expect_refusal "a header alone isn't a fragment" "$repo" "no fragments" --release-type patch
fragment "$repo" Fixed "Something <b>bold</b>"
expect_refusal "refuses notes that won't render" "$repo" "don't render" --release-type auto

make_repo "$repo" 5 "" 0.1.0
fragment "$repo" Fixed
git -C "$repo" tag v0.1.1
expect_refusal "refuses a tag that already exists" "$repo" "tag v0.1.1 already exists" --release-type auto

# Changie always names a version above its newest notes, so only a stand-in can
# reach this guard.
make_repo "$repo" 5 "" 0.1.1
fragment "$repo" Fixed
stubs="$workdir/stubs"
mkdir "$stubs"
printf '#!/bin/bash\necho 0.1.1\n' >"$stubs/changie"
chmod +x "$stubs/changie"
PATH="$stubs:$PATH" expect_refusal "refuses to overwrite archived notes" "$repo" "already exists" --release-type auto
printf '#!/bin/bash\necho "0.1;x"\n' >"$stubs/changie"
PATH="$stubs:$PATH" expect_refusal "refuses a next version that isn't X.Y.Z" "$repo" "isn't X.Y.Z" --release-type auto

# --- Clair's Changie configuration --------------------------------------------
# What the release commit runs (design D5).
make_repo "$repo" 5 ""
fragment "$repo" New "First release"
if (cd "$repo" && changie batch 0.1.0 >/dev/null && changie merge >/dev/null); then
  check "batches and merges a release" pass
else
  check "batches and merges a release" fail
fi
if [[ "$(od -c "$repo/version.txt")" == "$(printf '0.1.0\n' | od -c)" ]]; then
  check "merge leaves exactly the version in version.txt" pass
else
  check "merge leaves exactly the version in version.txt" fail
  od -c "$repo/version.txt" | sed 's/^/         /'
fi
fragment "$repo" Fixed "A fix"
(cd "$repo" && changie batch 0.1.1 >/dev/null && changie merge >/dev/null)
if [[ "$(cat "$repo/version.txt")" == 0.1.1 && "$(wc -l <"$repo/version.txt" | tr -d ' ')" == 1 ]]; then
  check "the next release stamps its version over the last" pass
else
  check "the next release stamps its version over the last" fail
fi
if grep -qxF -- "- New: First release" "$repo/.changes/0.1.0.md" && grep -qxF -- "- Fixed: A fix" "$repo/CHANGELOG.md" \
    && [[ -z "$(ls "$repo/.changes/unreleased")" ]]; then
  check "writes the notes and the changelog, and consumes the fragments" pass
else
  check "writes the notes and the changelog, and consumes the fragments" fail
fi

# --- inputs -----------------------------------------------------------------
make_repo "$repo" 5 ""
fragment "$repo" New
expect_refusal "requires --release-type" "$repo" "--release-type is required"
expect_refusal "rejects an unknown release type" "$repo" "unknown release type" --release-type huge
rm "$repo/.sparkle/appcast.xml"
expect_refusal "refuses a missing appcast" "$repo" "appcast not found" --release-type auto

echo
if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
