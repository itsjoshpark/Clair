#!/bin/bash
# Tests for check-release-credentials.sh. Run directly:
# scripts/check-release-credentials.test.sh
#
# Stand-ins replace security, openssl and xcrun; each can be told to answer as for a
# missing identity, a given expiry date or a rejected key.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$script_dir/check-release-credentials.sh"

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

mkdir "$workdir/stubs"
cat >"$workdir/stubs/security" <<'EOF'
#!/bin/bash
case "$1" in
  find-identity) [[ -n "${NO_IDENTITY-}" ]] || echo '  1) ABC "Developer ID Application: Joshua Park (TCQ6328PP6)"' ;;
  find-certificate) echo "PEM" ;;
  *) exit 64 ;;
esac
EOF
cat >"$workdir/stubs/openssl" <<'EOF'
#!/bin/bash
cat >/dev/null
[[ -n "${UNREADABLE-}" ]] || echo "notAfter=$EXPIRY"
EOF
cat >"$workdir/stubs/xcrun" <<EOF
#!/bin/bash
echo "\$*" >>"$workdir/xcrun.log"
[[ -z "\${KEY_REJECTED-}" ]]
EOF
chmod +x "$workdir/stubs/"*

# A date N days from now, as openssl prints it.
in_days() {
  LC_ALL=C date -u -v "$1d" '+%b %e %H:%M:%S %Y GMT'
}

run() {
  output="$(PATH="$workdir/stubs:$PATH" EXPIRY="${EXPIRY-$(in_days +400)}" "$script" \
    --keychain "$workdir/k" --key "$workdir/AuthKey.p8" --key-id ABCDE12345 --issuer some-issuer 2>&1)"
}

expect() {
  local description="$1" expected="$2" message="$3" status=0
  run || status=$?
  if [[ "$expected" == pass && $status -eq 0 && "$output" == *"$message"* ]] || [[ "$expected" == fail && $status -ne 0 && "$output" == *"$message"* ]]; then
    check "$description" pass
  else
    check "$description" fail
    echo "$output" | sed 's/^/         /'
  fi
}

expect "good credentials print the identity" pass "identity=Developer ID Application: Joshua Park (TCQ6328PP6)"
if grep -qF "notarytool history --key $workdir/AuthKey.p8 --key-id ABCDE12345 --issuer some-issuer" "$workdir/xcrun.log"; then
  check "asks Apple about the API key" pass
else
  check "asks Apple about the API key" fail
fi
NO_IDENTITY=1 expect "a missing identity stops it" fail "No Developer ID Application identity"
EXPIRY="$(in_days -3)" expect "an expired certificate stops it" fail "::error::The signing certificate expired"
EXPIRY="$(in_days +20)" expect "under 30 days warns" pass "::warning::The signing certificate expires in"
EXPIRY="$(in_days +20)" expect "under 30 days still succeeds" pass "identity=Developer ID Application"
EXPIRY="$(in_days +45)" expect "over 30 days says when" pass "Certificate expires in"
EXPIRY="Feb  1 22:12:15 2027 GMT" expect "reads openssl's space-padded day" pass "identity=Developer ID Application"
UNREADABLE=1 expect "an unreadable expiry warns" pass "::warning::Could not read"
KEY_REJECTED=1 expect "a rejected API key stops it" fail "Apple rejected the App Store Connect API key"
if PATH="$workdir/stubs:$PATH" "$script" --keychain "$workdir/k" >/dev/null 2>&1; then
  check "requires its arguments" fail
else
  check "requires its arguments" pass
fi

echo
if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
