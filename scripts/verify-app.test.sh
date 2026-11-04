#!/bin/bash
# Tests for verify-app.sh. Run directly: ./scripts/verify-app.test.sh
#
# Builds small fake app bundles with real Mach-O executables (needs clang from
# Xcode or the Command Line Tools).

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
verify="$script_dir/verify-app.sh"

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

echo 'int main(void) { return 0; }' >"$workdir/main.c"
cc -arch arm64 -o "$workdir/arm64.bin" "$workdir/main.c" || exit 1
cc -arch arm64 -arch x86_64 -o "$workdir/universal.bin" "$workdir/main.c" || exit 1

write_plist() {
  local plist="$1" id="$2" name="$3" min="$4"
  mkdir -p "$(dirname "$plist")"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $id" \
    -c "Add :CFBundleName string $name" \
    -c "Add :CFBundleExecutable string $name" "$plist" >/dev/null
  if [[ -n "$min" ]]; then
    /usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string $min" "$plist" >/dev/null
  fi
}

# make_app DIR NAME ID NAME_KEY MIN HELPER_ID BINARY
make_app() {
  local dir="$1" name="$2" id="$3" bundle_name="$4" min="$5" helper_id="$6" binary="$7"
  local app="$dir/$name.app"
  rm -rf "$dir"
  mkdir -p "$app/Contents/MacOS"
  write_plist "$app/Contents/Info.plist" "$id" "$bundle_name" "$min"
  cp "$workdir/arm64.bin" "$app/Contents/MacOS/$bundle_name"
  local framework="$app/Contents/Frameworks/$bundle_name Framework.framework/Versions/A"
  mkdir -p "$framework/Helpers"
  cp "$workdir/$binary" "$framework/$bundle_name Framework"
  local helper="$framework/Helpers/$bundle_name Helper.app"
  write_plist "$helper/Contents/Info.plist" "$helper_id" "$bundle_name Helper" ""
  mkdir -p "$helper/Contents/MacOS"
  cp "$workdir/arm64.bin" "$helper/Contents/MacOS/$bundle_name Helper"
  echo "not a binary" >"$app/Contents/README.txt"
  echo "$app"
}

expect() {
  local description="$1" expected="$2" app="$3" message="${4-}"
  local output status
  output="$("$verify" --engine "$app" 2>&1)"
  status=$?
  if [[ "$expected" == "pass" && $status -eq 0 ]]; then
    check "$description" pass
  elif [[ "$expected" == "fail" && $status -ne 0 && "$output" == *"$message"* ]]; then
    check "$description" pass
  else
    check "$description" fail
    echo "$output" | sed 's/^/         /'
  fi
}

good="$(make_app "$workdir/good" Clair dev.joshuapark.Clair Clair 15.6 dev.joshuapark.Clair.helper arm64.bin)"
expect "a correct engine passes with --engine" pass "$good"

app="$(make_app "$workdir/chromium" Chromium org.chromium.Chromium Chromium 13.0 org.chromium.Chromium.helper arm64.bin)"
expect "an unbranded Chromium.app fails on its name" fail "$app" "expected Clair.app"
expect "an unbranded Chromium.app fails on its identifier" fail "$app" "expected dev.joshuapark.Clair"
expect "an unbranded Chromium.app fails on CFBundleName" fail "$app" "which names Chromium"
expect "an unbranded Chromium.app fails on helper identifiers" fail "$app" "helper"

app="$(make_app "$workdir/minos" Clair dev.joshuapark.Clair Clair 13.0 dev.joshuapark.Clair.helper arm64.bin)"
expect "a wrong minimum macOS version fails" fail "$app" "LSMinimumSystemVersion is '13.0'"

app="$(make_app "$workdir/nomin" Clair dev.joshuapark.Clair Clair "" dev.joshuapark.Clair.helper arm64.bin)"
expect "a missing minimum macOS version fails" fail "$app" "LSMinimumSystemVersion is ''"

app="$(make_app "$workdir/helper" Clair dev.joshuapark.Clair Clair 15.6 org.chromium.Chromium.helper arm64.bin)"
expect "a helper with a foreign identifier fails" fail "$app" "Clair Helper.app has identifier 'org.chromium.Chromium.helper'"

app="$(make_app "$workdir/universal" Clair dev.joshuapark.Clair Clair 15.6 dev.joshuapark.Clair.helper universal.bin)"
expect "a universal (x86_64 + arm64) binary fails" fail "$app" "expected only arm64"

app="$(make_app "$workdir/sparkle" Clair dev.joshuapark.Clair Clair 15.6 dev.joshuapark.Clair.helper arm64.bin)"
updater="$app/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
write_plist "$updater/Contents/Info.plist" org.sparkle-project.Sparkle.Updater Updater ""
expect "Sparkle's Updater.app keeps Sparkle's identifier" pass "$app" "helper apps use"

app="$(make_app "$workdir/stray" Clair dev.joshuapark.Clair Clair 15.6 dev.joshuapark.Clair.helper arm64.bin)"
stray="$app/Contents/Frameworks/Other.framework/Updater.app"
write_plist "$stray/Contents/Info.plist" org.sparkle-project.Sparkle.Updater Updater ""
expect "an app outside Sparkle.framework still needs Clair's prefix" fail "$app" "Updater.app has identifier"

if "$verify" "$workdir/missing.app" >/dev/null 2>&1; then
  check "rejects a missing app" fail
else
  check "rejects a missing app" pass
fi

# --- version and updates ------------------------------------------------------------
feed="https://github.com/itsjoshpark/Clair/raw/main/.sparkle/appcast.xml"
real_key="$(tr -d '[:space:]' <"$script_dir/../.sparkle/public-ed-key.txt")"
current_version="$(cat "$script_dir/../version.txt")"

# make_package DIR [VERSION]: a good package's Info.plist, on a correct engine.
make_package() {
  local app
  app="$(make_app "$1" Clair dev.joshuapark.Clair Clair 15.6 dev.joshuapark.Clair.helper arm64.bin)"
  /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${2-$current_version}" \
    -c "Add :CFBundleVersion string 42" \
    -c "Add :SUFeedURL string $feed" \
    -c "Add :SUPublicEDKey string $real_key" "$app/Contents/Info.plist" >/dev/null
  echo "$app"
}

set_key() {
  /usr/libexec/PlistBuddy -c "Set :$2 $3" "$1/Contents/Info.plist"
}

delete_key() {
  /usr/libexec/PlistBuddy -c "Delete :$1" "$2/Contents/Info.plist"
}

# expect_flags DESCRIPTION pass|fail MESSAGE ARGS...: runs verify-app with ARGS.
expect_flags() {
  local description="$1" expected="$2" message="$3" output status
  shift 3
  output="$("$verify" "$@" 2>&1)"
  status=$?
  if [[ "$expected" == pass && $status -eq 0 && "$output" == *"$message"* ]]; then
    check "$description" pass
  elif [[ "$expected" == fail && $status -ne 0 && "$output" == *"$message"* ]]; then
    check "$description" pass
  else
    check "$description" fail
    echo "$output" | sed 's/^/         /'
  fi
}

app="$(make_package "$workdir/package")"
expect_flags "an ad hoc package passes with --skip-signing" pass "SUPublicEDKey is present" --skip-signing "$app"
expect_flags "--engine skips the version and update checks" pass "all checks passed" --engine "$good"
expect_flags "a bare engine fails --skip-signing on its version" fail "CFBundleShortVersionString is ''" --skip-signing "$good"
expect_flags "a version other than the one asked for fails" fail "expected '99.0.0'" --version 99.0.0 --skip-signing "$app"
app="$(make_package "$workdir/package" 9.9.9)"
expect_flags "--version replaces version.txt" pass "CFBundleShortVersionString is 9.9.9" --version 9.9.9 --skip-signing "$app"
expect_flags "a package that isn't version.txt's version fails by default" fail "CFBundleShortVersionString is '9.9.9'" --skip-signing "$app"

app="$(make_package "$workdir/package")"
set_key "$app" CFBundleVersion 1.2
expect_flags "a build number that isn't an integer fails" fail "CFBundleVersion is '1.2'" --skip-signing "$app"

app="$(make_package "$workdir/package")"
set_key "$app" SUFeedURL https://example.com/appcast.xml
expect_flags "another feed fails" fail "SUFeedURL is 'https://example.com/appcast.xml'" --skip-signing "$app"

app="$(make_package "$workdir/package")"
delete_key SUFeedURL "$app"
expect_flags "a missing feed fails" fail "SUFeedURL is ''" --skip-signing "$app"

app="$(make_package "$workdir/package")"
delete_key SUPublicEDKey "$app"
expect_flags "a missing public key fails" fail "SUPublicEDKey is ''" --skip-signing "$app"

app="$(make_package "$workdir/package")"
set_key "$app" SUPublicEDKey short
expect_flags "a malformed public key fails" fail "SUPublicEDKey is 'short'" --skip-signing "$app"

# --- signing ------------------------------------------------------------------------
# No Developer ID here: stand-ins answer as Apple's tools do for a notarized
# package, and each can be told to answer otherwise.
stubs="$workdir/stubs"
mkdir "$stubs"
cat >"$stubs/codesign" <<'EOF'
#!/bin/bash
case "$1" in
  --verify)
    if [[ -n "${CODESIGN_INVALID-}" ]]; then
      echo "a sealed resource is missing or invalid" >&2
      exit 1
    fi
    ;;
  -dv)
    {
      echo "Executable=/fake"
      echo "CodeDirectory v=20500 size=1 flags=${CODESIGN_FLAGS-0x10000(runtime)} hashes=1+1 location=embedded"
      echo "TeamIdentifier=${CODESIGN_TEAM-TCQ6328PP6}"
    } >&2
    ;;
  *) exit 64 ;;
esac
EOF
cat >"$stubs/spctl" <<'EOF'
#!/bin/bash
echo "$*" >>"${SPCTL_LOG:?}"
if [[ -n "${SPCTL_REJECTED-}" ]]; then
  echo "rejected" >&2
  exit 3
fi
echo "${!#}: accepted" >&2
echo "source=${SPCTL_SOURCE-Notarized Developer ID}" >&2
echo "origin=Developer ID Application: Joshua Park (${SPCTL_TEAM-TCQ6328PP6})" >&2
EOF
cat >"$stubs/xcrun" <<'EOF'
#!/bin/bash
[[ "$1 $2" == "stapler validate" ]] || exit 64
if [[ "$3" == *"${STAPLER_UNSTAPLED-none}"* ]]; then
  exit 65
fi
EOF
chmod +x "$stubs/codesign" "$stubs/spctl" "$stubs/xcrun"
export SPCTL_LOG="$workdir/spctl.log"
dmg_file="$workdir/Clair-1.dmg"
echo "fake" >"$dmg_file"

signed() {
  PATH="$stubs:$PATH" expect_flags "$@"
}

app="$(make_package "$workdir/package")"
signed "a notarized package passes every check" pass "all checks passed" "$app"
: >"$SPCTL_LOG"
signed "a notarized package and DMG pass every check" pass "Clair-1.dmg has a valid stapled ticket" --dmg "$dmg_file" "$app"
if grep -q -- "--type execute .*Clair.app" "$SPCTL_LOG" && grep -q -- "--type open --context context:primary-signature .*Clair-1.dmg" "$SPCTL_LOG"; then
  check "assesses the app for execution and the DMG for opening" pass
else
  check "assesses the app for execution and the DMG for opening" fail
fi

CODESIGN_INVALID=1 signed "a broken signature fails" fail "sealed resource" "$app"
CODESIGN_TEAM=0000000000 signed "another team's signature fails" fail "not signed by team TCQ6328PP6" "$app"
CODESIGN_FLAGS="0x0(none)" signed "no hardened runtime fails" fail "not signed with the hardened runtime" "$app"
SPCTL_REJECTED=1 signed "a Gatekeeper rejection fails" fail "Gatekeeper's verdict on Clair.app: rejected" "$app"
SPCTL_SOURCE="Developer ID" signed "a signed but not notarized app fails" fail "Gatekeeper's verdict on Clair.app" "$app"
SPCTL_TEAM=0000000000 signed "Gatekeeper naming another team fails" fail "Gatekeeper's verdict on Clair.app" "$app"
STAPLER_UNSTAPLED=Clair.app signed "an unstapled app fails" fail "Clair.app has no valid stapled ticket" "$app"
STAPLER_UNSTAPLED=Clair-1.dmg signed "an unstapled DMG fails" fail "Clair-1.dmg has no valid stapled ticket" --dmg "$dmg_file" "$app"
CODESIGN_INVALID=1 signed "a broken DMG signature fails" fail "codesign --verify --strict" --dmg "$dmg_file" "$app"

set_key "$app" SUPublicEDKey "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
signed "a package with the test key fails" fail "isn't the key in .sparkle/public-ed-key.txt" "$app"
expect_flags "the test key is fine with --skip-signing" pass "all checks passed" --skip-signing "$app"

app="$(make_package "$workdir/package")"
/usr/libexec/PlistBuddy -c "Add :ClairNonOfficialPackage bool true" "$app/Contents/Info.plist"
signed "a package marked non-official fails" fail "marked ClairNonOfficialPackage" "$app"

expect_flags "an unsigned app fails by default" fail "not signed by team TCQ6328PP6" "$(make_package "$workdir/package")"
expect_flags "--dmg with --skip-signing is refused" fail "can't go with" --dmg "$dmg_file" --skip-signing "$app"
expect_flags "a missing DMG is refused" fail "not a file" --dmg "$workdir/none.dmg" "$app"

echo
if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
