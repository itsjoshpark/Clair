#!/bin/bash
# Tests for release-keychain.sh. Run directly: scripts/release-keychain.test.sh
#
# A stand-in for `security` keeps the search list in a file and logs its arguments
# and its stdin apart, so the tests can tell that no password is an argument. The
# release dry run covers the real tool.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$script_dir/release-keychain.sh"

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
cat >"$workdir/stubs/security" <<EOF
#!/bin/bash
echo "\$*" >>"$workdir/args.log"
case "\$1" in
  -i)
    cat >>"$workdir/stdin.log"
    [[ -z "\${INTERACTIVE_FAILS-}" ]] || exit 1
    : >"$workdir/clair.keychain-db"
    ;;
  list-keychains)
    if [[ "\$4" == -s ]]; then
      shift 4
      : >"$workdir/list"
      for path in "\$@"; do printf '    "%s"\n' "\$path" >>"$workdir/list"; done
    else
      cat "$workdir/list"
    fi
    ;;
  set-keychain-settings) ;;
  find-identity)
    [[ -n "\${NO_IDENTITY-}" ]] || echo '  1) ABC "Developer ID Application: Joshua Park (TCQ6328PP6)"'
    ;;
  delete-keychain) rm -f "\$2" ;;
  *) exit 64 ;;
esac
EOF
chmod +x "$workdir/stubs/security"

keychain="$workdir/clair.keychain-db"
saved="$workdir/saved"
secret='p"a\ss w$rd!'
start_list() {
  rm -f "$workdir/args.log" "$workdir/stdin.log" "$saved" "$keychain"
  printf '    "/Users/me/Library/Keychains/login.keychain-db"\n    "/Users/me/My Keychains/other.keychain-db"\n' >"$workdir/list"
  cp "$workdir/list" "$workdir/list-before"
}

run() {
  output="$(PATH="$workdir/stubs:$PATH" DEVELOPER_ID_CERT_P12_BASE64="${P12-Y2VydA==}" DEVELOPER_ID_CERT_PASSWORD="${PASSWORD-$secret}" \
    "$script" "$@" 2>&1)"
}

start_list
if run create "$keychain" "$saved"; then
  check "creates the keychain" pass
else
  check "creates the keychain" fail
  echo "$output" | sed 's/^/         /'
fi
if [[ "$(sed -n 1p "$workdir/list")" == "    \"$keychain\"" && "$(sed 1d "$workdir/list")" == "$(cat "$workdir/list-before")" ]]; then
  check "adds the keychain to the search list, keeping the rest in order" pass
else
  check "adds the keychain to the search list, keeping the rest in order" fail
  sed 's/^/         /' "$workdir/list"
fi
if ! grep -qF "$secret" "$workdir/args.log" && ! grep -v '^find-identity' "$workdir/args.log" | grep -qE ' -[pkP] '; then
  check "no password is ever an argument" pass
else
  check "no password is ever an argument" fail
  sed 's/^/         /' "$workdir/args.log"
fi
if grep -qE '^import ".*/developer-id\.[^"]*" -f pkcs12 ' "$workdir/stdin.log"; then
  check "names the certificate's format, since its temporary name has no extension" pass
else
  check "names the certificate's format, since its temporary name has no extension" fail
  grep import "$workdir/stdin.log" | sed 's/^/         /'
fi
if grep -qF -- '-P "p\"a\\ss w$rd!" -T /usr/bin/codesign' "$workdir/stdin.log"; then
  check "quotes the certificate's password for security's own parser" pass
else
  check "quotes the certificate's password for security's own parser" fail
  grep import "$workdir/stdin.log" | sed 's/^/         /'
fi
if grep -q '^create-keychain ' "$workdir/stdin.log" && grep -q '^set-key-partition-list -S apple-tool:,apple:,codesign: -s ' "$workdir/stdin.log"; then
  check "lets codesign use the key without a prompt" pass
else
  check "lets codesign use the key without a prompt" fail
fi
if [[ -z "$(find "$workdir" -maxdepth 1 -name 'developer-id.*')" ]]; then
  check "leaves no copy of the certificate" pass
else
  check "leaves no copy of the certificate" fail
fi
if ! grep -qE 'default-keychain|login-keychain' "$workdir/args.log" "$workdir/stdin.log"; then
  check "leaves the default and login keychains alone" pass
else
  check "leaves the default and login keychains alone" fail
fi

if run create "$keychain" "$saved"; then
  check "refuses a keychain that already exists" fail
else
  [[ "$output" == *"already exists"* ]] && check "refuses a keychain that already exists" pass || check "refuses a keychain that already exists" fail
fi

if run delete "$keychain" "$saved" && [[ "$(cat "$workdir/list")" == "$(cat "$workdir/list-before")" && ! -e "$keychain" && ! -e "$saved" ]]; then
  check "delete restores the search list and removes the keychain" pass
else
  check "delete restores the search list and removes the keychain" fail
  echo "$output" | sed 's/^/         /'
fi
if run delete "$keychain" "$saved"; then
  check "delete is safe to run again" pass
else
  check "delete is safe to run again" fail
fi

# After a failed create, as a cancelled job leaves things.
start_list
if NO_IDENTITY=1 run create "$keychain" "$saved"; then
  check "fails when the certificate didn't import" fail
elif [[ "$output" == *"no Developer ID Application identity"* ]]; then
  check "fails when the certificate didn't import" pass
else
  check "fails when the certificate didn't import" fail
fi
run delete "$keychain" "$saved"
if [[ "$(cat "$workdir/list")" == "$(cat "$workdir/list-before")" && ! -e "$keychain" ]]; then
  check "delete cleans up after a failed create" pass
else
  check "delete cleans up after a failed create" fail
fi

start_list
if INTERACTIVE_FAILS=1 run create "$keychain" "$saved"; then
  check "fails when security can't import the certificate, saying what to check" fail
elif [[ "$output" == *"couldn't create the keychain or import the certificate"* ]]; then
  check "fails when security can't import the certificate, saying what to check" pass
else
  check "fails when security can't import the certificate, saying what to check" fail
  echo "$output" | sed 's/^/         /'
fi
run delete "$keychain" "$saved"

start_list
if P12="" run create "$keychain" "$saved" || [[ "$output" != *"DEVELOPER_ID_CERT_P12_BASE64 is not set"* ]]; then
  check "requires the certificate" fail
else
  check "requires the certificate" pass
fi
if PASSWORD="" run create "$keychain" "$saved" || [[ "$output" != *"DEVELOPER_ID_CERT_PASSWORD is not set"* ]]; then
  check "requires the certificate's password" fail
else
  check "requires the certificate's password" pass
fi
if run; then check "requires its arguments" fail; else check "requires its arguments" pass; fi

echo
if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
