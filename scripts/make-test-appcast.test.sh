#!/bin/bash
# Tests for make-test-appcast.sh. Run directly: scripts/make-test-appcast.test.sh
#
# Uses a stand-in sign_update, so it works offline.

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
script="$root/scripts/make-test-appcast.sh"

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

mkdir -p "$workdir/sparkle/bin"
cat >"$workdir/sparkle/bin/sign_update" <<'STUB'
#!/bin/bash
echo "$*" >>"${SIGN_LOG:?}"
echo "c2lnbmF0dXJl"
STUB
chmod +x "$workdir/sparkle/bin/sign_update"
export SIGN_LOG="$workdir/sign.log"

printf 'twelve bytes' >"$workdir/Clair-0.1.1-arm64.dmg"
printf 'delta' >"$workdir/100-101.delta"
appcast="$workdir/feed/appcast.xml"

run() {
  "$script" --sparkle "$workdir/sparkle" "$@"
}

if run --appcast "$appcast" --dmg "$workdir/Clair-0.1.1-arm64.dmg" --version 0.1.1 --build 101 \
    --base-url http://localhost:8123 --delta "100,$workdir/100-101.delta" 2>&1; then
  check "creates a feed and adds a release" pass
else
  check "creates a feed and adds a release" fail
fi

if xmllint --noout "$appcast" 2>/dev/null; then
  check "the feed is well-formed" pass
else
  check "the feed is well-formed" fail
fi

if grep -q 'url="http://localhost:8123/Clair-0.1.1-arm64.dmg"' "$appcast" \
    && grep -q 'length="12"' "$appcast" \
    && grep -q 'sparkle:edSignature="c2lnbmF0dXJl"' "$appcast" \
    && grep -q '<sparkle:version>101</sparkle:version>' "$appcast" \
    && grep -q '<sparkle:minimumSystemVersion>15.6</sparkle:minimumSystemVersion>' "$appcast"; then
  check "the release has its local URL, signature, length, build and minimum macOS" pass
else
  check "the release has its local URL, signature, length, build and minimum macOS" fail
fi

if grep -q 'url="http://localhost:8123/100-101.delta"' "$appcast" \
    && grep -q 'sparkle:deltaFrom="100"' "$appcast"; then
  check "the delta has its local URL and its build" pass
else
  check "the delta has its local URL and its build" fail
fi

if ! grep -q 'clair-test.invalid' "$appcast"; then
  check "no placeholder URL is left" pass
else
  check "no placeholder URL is left" fail
fi

if grep -qF -- "--ed-key-file $root/tests/runtime/update-key/private-ed-key.txt" "$SIGN_LOG"; then
  check "signs with the test-only key by default" pass
else
  check "signs with the test-only key by default" fail
fi

if run --appcast "$appcast" --dmg "$workdir/Clair-0.1.1-arm64.dmg" --version 0.1.2 --build 102 \
    --base-url http://localhost:8123 --minimum-system-version 99.0 2>&1 \
    && grep -q '<sparkle:minimumSystemVersion>99.0</sparkle:minimumSystemVersion>' "$appcast" \
    && [[ "$(grep -c '<item>' "$appcast")" == 2 ]]; then
  check "adds a second release with its own minimum macOS" pass
else
  check "adds a second release with its own minimum macOS" fail
fi

expect_refusal() {
  local description="$1" expected="$2" output status
  shift 2
  output="$(run "$@" 2>&1)"
  status=$?
  if [[ "$status" -ne 0 && "$output" == *"$expected"* ]]; then
    check "$description" pass
  else
    check "$description" fail
    echo "         $output"
  fi
}

dmg="$workdir/Clair-0.1.1-arm64.dmg"
before="$(cat "$root/.sparkle/appcast.xml")"
expect_refusal "refuses the real appcast" "refusing to write to the real appcast" \
  --appcast "$root/.sparkle/appcast.xml" --dmg "$dmg" --version 0.1.3 --build 103 --base-url http://localhost:8123
if [[ "$(cat "$root/.sparkle/appcast.xml")" == "$before" ]]; then
  check "leaves the real appcast alone" pass
else
  check "leaves the real appcast alone" fail
fi
expect_refusal "refuses a base URL that isn't plain" "not a plain URL" \
  --appcast "$appcast" --dmg "$dmg" --version 0.1.3 --build 103 --base-url 'http://localhost/"|x'
expect_refusal "refuses a missing DMG" "no file at" \
  --appcast "$appcast" --dmg "$workdir/none.dmg" --version 0.1.3 --build 103 --base-url http://localhost:8123
expect_refusal "refuses a build that isn't newer" "does not exceed" \
  --appcast "$appcast" --dmg "$dmg" --version 0.1.3 --build 102 --base-url http://localhost:8123

if ((failures > 0)); then
  echo
  echo "$failures test(s) failed"
  exit 1
fi
echo
echo "all tests passed"
