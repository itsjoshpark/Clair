#!/bin/bash
# Tests for publish-release.sh. Run directly: scripts/publish-release.test.sh
#
# Publishes to a local bare repository, with real git, Changie and cmark-gfm. A
# stand-in for gh records what the remote's main held at each call, to show that the
# Release comes first and main last.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$script_dir/.."

failures=0
workdir="$(mktemp -d)"
workdir="$(cd "$workdir" && pwd -P)"
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

stubs="$workdir/stubs"
mkdir "$stubs"
cat >"$stubs/gh" <<EOF
#!/bin/bash
echo "\$*" >>"$workdir/gh.log"
echo "\$1 \$2 main=\$(git -C "$workdir/remote.git" rev-parse main) tag=\$(git -C "$workdir/remote.git" rev-parse -q --verify "refs/tags/\$3" || echo none)" >>"$workdir/gh-state.log"
if [[ "\$1 \$2" == "release create" ]]; then
  [[ -z "\${GH_CREATE_FAILS-}" ]] || exit 1
  while (( \$# > 0 )); do
    [[ "\$1" != --notes-file ]] || cp "\$2" "$workdir/body.md"
    shift
  done
elif [[ -n "\${MOVE_MAIN_ON_EDIT-}" ]]; then
  git -C "$workdir/other" commit -q --allow-empty -m "landed during the release"
  git -C "$workdir/other" push -q origin HEAD:main
fi
EOF
chmod +x "$stubs/gh"

# A remote with five commits, a clone to publish from, and a second clone.
setup() {
  rm -rf "$workdir/remote.git" "$workdir/repo" "$workdir/other" "$workdir/dist" "$workdir/gh.log" "$workdir/gh-state.log" "$workdir/body.md"
  git init -q --bare -b main "$workdir/remote.git"
  git clone -q "$workdir/remote.git" "$workdir/repo" 2>/dev/null
  local repo="$workdir/repo"
  git -C "$repo" checkout -q -b main
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name test
  mkdir -p "$repo/.changes/unreleased" "$repo/.sparkle"
  cp "$repo_root/.changie.yaml" "$repo/"
  cp "$repo_root/.changes/header.tpl.md" "$repo/.changes/"
  cp "$repo_root/.changes/unreleased/.gitkeep" "$repo/.changes/unreleased/"
  echo 0.1.0 >"$repo/version.txt"
  cat >"$repo/.sparkle/appcast.xml" <<'XML'
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>Clair</title>
    <language>en</language>

  </channel>
</rss>
XML
  printf 'kind: New\nbody: First release\ntime: 2026-01-01T00:00:00.000000000Z\n' >"$repo/.changes/unreleased/New-1.yaml"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "commit 1"
  local i
  for i in 2 3 4 5; do
    git -C "$repo" commit -q --allow-empty -m "commit $i"
  done
  git -C "$repo" push -q origin main
  git clone -q "$workdir/remote.git" "$workdir/other"
  git -C "$workdir/other" config user.email other@example.com
  git -C "$workdir/other" config user.name other
  base="$(git -C "$repo" rev-parse HEAD)"

  mkdir "$workdir/dist"
  printf 'the dmg' >"$workdir/dist/Clair-0.1.0-arm64.dmg"
  printf 'a delta' >"$workdir/dist/Clair-4-6.delta"
  {
    echo "dmg_signature=c2lnbmF0dXJl"
    echo "dmg_length=7"
    echo "delta=4,https://github.com/itsjoshpark/Clair/releases/download/v0.1.0/Clair-4-6.delta,ZGVsdGE=,7"
  } >"$workdir/dist/assets.txt"
}

run() {
  output="$(cd "$workdir/repo" && PATH="$stubs:$PATH" "$script_dir/publish-release.sh" --version 0.1.0 --build "${BUILD-6}" \
    --base "${BASE-$base}" --dist "$workdir/dist" --ungoogled 156.0.8078.73-1 --engine-key ffd2eaa67da27a29 "$@" 2>&1)"
}

remote_main() {
  git -C "$workdir/remote.git" rev-parse main
}

expect_refusal() {
  local description="$1" message="$2"
  shift 2
  if run "$@"; then
    check "$description" fail
  elif [[ "$output" == *"$message"* ]]; then
    check "$description" pass
  else
    check "$description" fail
    echo "$output" | sed 's/^/         /'
  fi
}

# --- a release -------------------------------------------------------------------
setup
if run; then
  check "publishes" pass
else
  check "publishes" fail
  echo "$output" | sed 's/^/         /'
fi
tagged="$(git -C "$workdir/remote.git" rev-parse -q --verify refs/tags/v0.1.0)"
if [[ -n "$tagged" && "$tagged" == "$(remote_main)" && "$(git -C "$workdir/remote.git" log -1 --format=%s main)" == "chore: release 0.1.0 (6) [skip ci]" ]]; then
  check "tags the release commit, which ends up on main" pass
else
  check "tags the release commit, which ends up on main" fail
fi
if [[ "$(git -C "$workdir/remote.git" rev-list --count main)" == 6 ]]; then
  check "the release commit's commit count is the build number" pass
else
  check "the release commit's commit count is the build number" fail
fi
if grep -q "^release create main=$base tag=$tagged$" "$workdir/gh-state.log" && grep -q "^release edit main=$base " "$workdir/gh-state.log"; then
  check "the tag exists before the Release, and main moves only after it" pass
else
  check "the tag exists before the Release, and main moves only after it" fail
  sed 's/^/         /' "$workdir/gh-state.log"
fi
create="$(grep '^release create' "$workdir/gh.log")"
if [[ "$create" == *"--draft"* && "$create" == *Clair-0.1.0-arm64.dmg* && "$create" == *Clair-4-6.delta* && "$create" == *Clair-0.1.0-SHA256SUMS.txt* ]] \
    && grep -q -- "--draft=false --latest" "$workdir/gh.log"; then
  check "uploads the DMG, deltas and checksums to a draft, then publishes it" pass
else
  check "uploads the DMG, deltas and checksums to a draft, then publishes it" fail
fi
if (cd "$workdir/dist" && shasum -a 256 -c Clair-0.1.0-SHA256SUMS.txt >/dev/null) \
    && [[ "$(wc -l <"$workdir/dist/Clair-0.1.0-SHA256SUMS.txt" | tr -d ' ')" == 2 ]]; then
  check "the checksums cover the DMG and each delta" pass
else
  check "the checksums cover the DMG and each delta" fail
fi
if grep -qF -- "- New: First release" "$workdir/body.md" && grep -qF 'Clair 0.1.0 (build 6), ungoogled-chromium 156.0.8078.73-1, engine key `ffd2eaa67da27a29`' "$workdir/body.md"; then
  check "the Release notes state the version, build, ungoogled-chromium and engine key" pass
else
  check "the Release notes state the version, build, ungoogled-chromium and engine key" fail
fi
changed="$(git -C "$workdir/remote.git" show --name-status --format= main | LC_ALL=C sort | tr '\t' ' ' | tr '\n' ',')"
if [[ "$changed" == "A .changes/0.1.0.md,A CHANGELOG.md,D .changes/unreleased/New-1.yaml,M .sparkle/appcast.xml,M version.txt," ]] \
    || [[ "$changed" == "A .changes/0.1.0.md,A CHANGELOG.md,D .changes/unreleased/New-1.yaml,M .sparkle/appcast.xml," ]]; then
  check "the release commit changes only the version, notes, changelog and appcast" pass
else
  check "the release commit changes only the version, notes, changelog and appcast" fail
  echo "         $changed"
fi
appcast="$(git -C "$workdir/remote.git" show main:.sparkle/appcast.xml)"
if xmllint --noout - <<<"$appcast" \
    && [[ "$appcast" == *"<sparkle:version>6</sparkle:version>"* && "$appcast" == *"<sparkle:minimumSystemVersion>15.6</sparkle:minimumSystemVersion>"* \
       && "$appcast" == *'releases/download/v0.1.0/Clair-0.1.0-arm64.dmg"'* && "$appcast" == *'sparkle:deltaFrom="4"'* && "$appcast" == *"<li>New: First release</li>"* ]]; then
  check "the appcast entry has the build, minimum macOS, DMG, delta and notes" pass
else
  check "the appcast entry has the build, minimum macOS, DMG, delta and notes" fail
fi
if [[ "$(git -C "$workdir/remote.git" show main:version.txt)" == 0.1.0 ]]; then
  check "version.txt holds the version" pass
else
  check "version.txt holds the version" fail
fi

# --- main moved -------------------------------------------------------------------
setup
git -C "$workdir/other" commit -q --allow-empty -m "landed during the build"
git -C "$workdir/other" push -q origin HEAD:main
moved="$(remote_main)"
expect_refusal "stops when main moved during the release" "main moved during the release"
if [[ ! -e "$workdir/gh.log" && "$(remote_main)" == "$moved" && -z "$(git -C "$workdir/remote.git" tag)" ]]; then
  check "creates no Release or tag and leaves main alone when it moved" pass
else
  check "creates no Release or tag and leaves main alone when it moved" fail
fi

setup
if MOVE_MAIN_ON_EDIT=1 run && [[ "$(git -C "$workdir/remote.git" log -1 --format=%s main)" == "chore: release 0.1.0 (6) [skip ci]" ]] \
    && [[ "$(git -C "$workdir/remote.git" log -2 --format=%s main | tail -1)" == "landed during the release" ]]; then
  check "after the Release is public, rebases onto a moved main and pushes" pass
else
  check "after the Release is public, rebases onto a moved main and pushes" fail
  echo "$output" | sed 's/^/         /'
fi

# --- failures --------------------------------------------------------------------
setup
GH_CREATE_FAILS=1 expect_refusal "a failed Release says how to recover" "creating the GitHub Release failed"
if [[ "$(remote_main)" == "$base" ]]; then
  check "a failed Release leaves main and its appcast unchanged" pass
else
  check "a failed Release leaves main and its appcast unchanged" fail
fi

setup
BASE=0000000000000000000000000000000000000000 expect_refusal "refuses a checkout of another commit" "isn't 0000"
BUILD=9 expect_refusal "refuses a build that isn't the commit count" "isn't the release commit's commit count"
expect_refusal "rejects a version that isn't X.Y.Z" "must be X.Y.Z" --version '0.1;x'
rm "$workdir/dist/Clair-4-6.delta"
expect_refusal "refuses a delta that isn't there" "Clair-4-6.delta, which isn't in"
rm "$workdir/dist/assets.txt"
expect_refusal "refuses a missing assets.txt" "no assets.txt"
rm "$workdir/dist/Clair-0.1.0-arm64.dmg"
expect_refusal "refuses a missing DMG" "no DMG at"

setup
printf 'the dmg, changed' >"$workdir/dist/Clair-0.1.0-arm64.dmg"
expect_refusal "refuses a DMG that isn't the one signed" "length isn't the DMG's"

setup
echo changed >"$workdir/repo/version.txt"
expect_refusal "refuses uncommitted changes" "uncommitted changes"

echo
if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
