#!/bin/bash
# Checks the static properties a shipped Clair.app must have, and prints every
# failure before exiting non-zero.
#
#   verify-app.sh [options] path/to/Clair.app
#
# By default it runs every check, as a shipped package must pass them:
#
# - Identity (app-identity spec): the bundle name and identifier, helper
#   identifiers, no Chromium product name in the bundle names, the minimum macOS
#   version, and arm64-only Mach-O files.
# - Version and updates: the short version, an integer build number, the feed URL
#   and a public EdDSA key.
# - Signing: strict signatures, Clair's team, the hardened runtime, Gatekeeper's
#   notarized verdict, a stapled ticket, Clair's own EdDSA key, and no non-official
#   mark.
#
# Options:
#   --version <x.y.z>  the version to expect (default: version.txt). A release
#                      package passes this, since it's built before the release
#                      commit updates version.txt.
#   --dmg <file>       also check the DMG's signature, Gatekeeper's verdict and
#                      its stapled ticket
#   --skip-signing     for a package signed ad hoc: skip the signing checks
#   --engine           for a bare engine: identity checks only

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
bundle_id="dev.joshuapark.Clair"
min_system_version="15.6"
feed_url="https://github.com/itsjoshpark/Clair/raw/main/.sparkle/appcast.xml"
team_id="TCQ6328PP6"

usage() {
  sed -n '/^#   verify-app.sh/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

app="" version="" dmg="" signing=true packaged=true
while (( $# > 0 )); do
  case "$1" in
    --version) version="${2-}"; shift 2 || usage ;;
    --dmg) dmg="${2-}"; shift 2 || usage ;;
    --skip-signing) signing=false; shift ;;
    --engine) signing=false; packaged=false; shift ;;
    -h|--help) usage ;;
    -*) echo "verify-app: unknown option: $1" >&2; exit 2 ;;
    *) [[ -z "$app" ]] || usage; app="$1"; shift ;;
  esac
done
failures=0

fail() {
  echo "FAIL     $1"
  failures=$((failures + 1))
}

pass() {
  echo "ok       $1"
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null
}

[[ -n "$app" ]] || usage
if [[ -n "$dmg" ]] && ! $signing; then
  echo "verify-app: --dmg checks signing, so it can't go with --skip-signing or --engine" >&2
  exit 2
fi
[[ -z "$dmg" || -f "$dmg" ]] || { echo "verify-app: not a file: $dmg" >&2; exit 2; }
[[ -d "$app" ]] || { echo "verify-app: not a directory: $app" >&2; exit 2; }
app="${app%/}"
info="$app/Contents/Info.plist"
[[ -f "$info" ]] || { echo "verify-app: missing $info" >&2; exit 2; }

if [[ "$(basename "$app")" == "Clair.app" ]]; then
  pass "bundle is named Clair.app"
else
  fail "bundle is named $(basename "$app"), expected Clair.app"
fi

actual_id="$(plist_value "$info" CFBundleIdentifier)"
if [[ "$actual_id" == "$bundle_id" ]]; then
  pass "CFBundleIdentifier is $bundle_id"
else
  fail "CFBundleIdentifier is '$actual_id', expected $bundle_id"
fi

for key in CFBundleName CFBundleDisplayName; do
  value="$(plist_value "$info" "$key")"
  if [[ "$value" == *Chromium* || "$value" == *Chrome* ]]; then
    fail "$key is '$value', which names Chromium"
  else
    pass "$key ('${value}') does not name Chromium"
  fi
done

actual_min="$(plist_value "$info" LSMinimumSystemVersion)"
if [[ "$actual_min" == "$min_system_version" ]]; then
  pass "LSMinimumSystemVersion is $min_system_version"
else
  fail "LSMinimumSystemVersion is '$actual_min', expected $min_system_version"
fi

helpers=0
bad_helpers=0
while IFS= read -r -d '' helper; do
  helpers=$((helpers + 1))
  helper_id="$(plist_value "$helper/Contents/Info.plist" CFBundleIdentifier)"
  if [[ "$helper_id" != "$bundle_id."* ]]; then
    fail "helper $(basename "$helper") has identifier '$helper_id', expected a $bundle_id. prefix"
    bad_helpers=$((bad_helpers + 1))
  fi
done < <(find "$app/Contents" -path "$app/Contents/Frameworks/Sparkle.framework" -prune \
           -o -name '*.app' -type d -print0)
# Sparkle's Updater.app keeps Sparkle's own identifier: it is Sparkle's code,
# embedded unchanged and signed as itself.
if (( bad_helpers == 0 )); then
  pass "all $helpers helper apps use the $bundle_id. prefix"
fi

machos=0
bad_machos=0
while IFS= read -r -d '' file; do
  [[ -L "$file" ]] && continue
  file -b "$file" | grep -q 'Mach-O' || continue
  machos=$((machos + 1))
  archs="$(lipo -archs "$file" 2>/dev/null)"
  if [[ "$archs" != "arm64" ]]; then
    fail "${file#"$app"/} has architectures '$archs', expected only arm64"
    bad_machos=$((bad_machos + 1))
  fi
done < <(find "$app" -type f -print0)
if (( machos == 0 )); then
  fail "no Mach-O files found"
elif (( bad_machos == 0 )); then
  pass "all $machos Mach-O files are arm64 only"
fi

# --- version and updates --------------------------------------------------------
if $packaged; then
  if [[ -z "$version" ]]; then
    version="$(cat "$root/version.txt" 2>/dev/null)"
  fi
  actual_version="$(plist_value "$info" CFBundleShortVersionString)"
  if [[ -n "$version" && "$actual_version" == "$version" ]]; then
    pass "CFBundleShortVersionString is $version"
  else
    fail "CFBundleShortVersionString is '$actual_version', expected '$version'"
  fi

  actual_build="$(plist_value "$info" CFBundleVersion)"
  if [[ "$actual_build" =~ ^[1-9][0-9]*$ ]]; then
    pass "CFBundleVersion ($actual_build) is an integer"
  else
    fail "CFBundleVersion is '$actual_build', expected an integer"
  fi

  actual_feed="$(plist_value "$info" SUFeedURL)"
  if [[ "$actual_feed" == "$feed_url" ]]; then
    pass "SUFeedURL is Clair's feed"
  else
    fail "SUFeedURL is '$actual_feed', expected $feed_url"
  fi

  actual_key="$(plist_value "$info" SUPublicEDKey)"
  if [[ "$actual_key" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
    pass "SUPublicEDKey is present"
  else
    fail "SUPublicEDKey is '$actual_key', expected a base64 Ed25519 public key"
  fi
fi

# --- signing ------------------------------------------------------------------------
# Passes when Gatekeeper's verdict on $1, assessed with the remaining arguments,
# says Apple notarized it for Clair's team.
check_gatekeeper() {
  local target="$1" name assessment
  shift
  name="$(basename "$target")"
  if assessment="$(spctl --assess -vv "$@" "$target" 2>&1)" \
      && [[ "$assessment" == *"source=Notarized Developer ID"* && "$assessment" == *"($team_id)"* ]]; then
    pass "Gatekeeper accepts $name as notarized for team $team_id"
  else
    fail "Gatekeeper's verdict on $name: $assessment"
  fi
}

check_stapled() {
  local name
  name="$(basename "$1")"
  if xcrun stapler validate "$1" >/dev/null 2>&1; then
    pass "$name has a valid stapled ticket"
  else
    fail "$name has no valid stapled ticket"
  fi
}

if $signing; then
  if verification="$(codesign --verify --deep --strict "$app" 2>&1)"; then
    pass "the app and every nested bundle pass codesign --verify --strict"
  else
    fail "codesign --verify --strict: $verification"
  fi

  signature="$(codesign -dv "$app" 2>&1)"
  if [[ "$signature" == *"TeamIdentifier=$team_id"* ]]; then
    pass "signed by team $team_id"
  else
    fail "not signed by team $team_id"
  fi
  if grep -Eq '^CodeDirectory .*flags=[^ ]*\(.*runtime.*\)' <<<"$signature"; then
    pass "signed with the hardened runtime"
  else
    fail "not signed with the hardened runtime"
  fi

  check_gatekeeper "$app" --type execute
  check_stapled "$app"

  # The test-only key must never reach a shipped package (design D6).
  committed_key="$(tr -d '[:space:]' <"$root/.sparkle/public-ed-key.txt" 2>/dev/null)"
  if [[ -n "$committed_key" && "$actual_key" == "$committed_key" ]]; then
    pass "SUPublicEDKey is Clair's own key"
  else
    fail "SUPublicEDKey isn't the key in .sparkle/public-ed-key.txt"
  fi
  if [[ -z "$(plist_value "$info" ClairNonOfficialPackage)" ]]; then
    pass "not marked as a non-official package"
  else
    fail "marked ClairNonOfficialPackage, which turns on ClairUI's test overrides"
  fi

  if [[ -n "$dmg" ]]; then
    if verification="$(codesign --verify --strict "$dmg" 2>&1)"; then
      pass "$(basename "$dmg") passes codesign --verify --strict"
    else
      fail "codesign --verify --strict: $verification"
    fi
    check_gatekeeper "$dmg" --type open --context context:primary-signature
    check_stapled "$dmg"
  fi
fi

echo
if (( failures > 0 )); then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
