#!/bin/bash
# Tests for package.sh. Run directly: ./package.test.sh
#
# Packages a stand-in engine, ClairUI and Sparkle made of small real Mach-O
# files, so it works offline and needs no Chromium (needs clang from Xcode or
# the Command Line Tools). Signs ad hoc only; Developer ID signing is checked
# by the release dry run.

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package="$root/package.sh"

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
echo 'int clair_stub(void) { return 0; }' >"$workdir/lib.c"
cc -arch arm64 -o "$workdir/exe" "$workdir/main.c" || exit 1
cc -arch arm64 -arch x86_64 -o "$workdir/exe-universal" "$workdir/main.c" || exit 1
cc -arch x86_64 -o "$workdir/exe-x86_64" "$workdir/main.c" || exit 1
cc -arch arm64 -dynamiclib -o "$workdir/lib" "$workdir/lib.c" || exit 1
cc -arch arm64 -arch x86_64 -dynamiclib -o "$workdir/lib-universal" "$workdir/lib.c" || exit 1

plist() {
  local file="$1" id="$2" executable="$3"
  mkdir -p "$(dirname "$file")"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $id" \
    -c "Add :CFBundleName string $executable" \
    -c "Add :CFBundleExecutable string $executable" \
    -c "Add :CFBundlePackageType string ${4-APPL}" "$file" >/dev/null
}

# A versioned framework bundle: framework DIR NAME ID BINARY
framework() {
  local dir="$1" name="$2" id="$3" binary="$4"
  mkdir -p "$dir/Versions/A/Resources"
  cp "$workdir/$binary" "$dir/Versions/A/$name"
  plist "$dir/Versions/A/Resources/Info.plist" "$id" "$name" FMWK
  ln -s A "$dir/Versions/Current"
  ln -s "Versions/Current/$name" "$dir/$name"
  ln -s Versions/Current/Resources "$dir/Resources"
}

# helper DIR NAME ID
helper() {
  local app="$1/$2.app"
  mkdir -p "$app/Contents/MacOS"
  cp "$workdir/exe" "$app/Contents/MacOS/$2"
  plist "$app/Contents/Info.plist" "$3" "$2"
}

# The engine's layout: Clair.app with Clair Framework.framework and its helpers.
make_engine() {
  local app="$1/Clair.app" id="${2-dev.joshuapark.Clair}"
  rm -rf "$1"
  mkdir -p "$app/Contents/MacOS"
  cp "$workdir/exe" "$app/Contents/MacOS/Clair"
  plist "$app/Contents/Info.plist" "$id" Clair
  /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 156.0.8078.73" \
    -c "Add :CFBundleVersion string 8078.73" \
    -c "Add :LSMinimumSystemVersion string 15.6" "$app/Contents/Info.plist"
  local fw="$app/Contents/Frameworks/Clair Framework.framework"
  framework "$fw" "Clair Framework" dev.joshuapark.Clair.framework lib
  local helpers="$fw/Versions/A/Helpers"
  mkdir -p "$helpers" "$fw/Versions/A/Libraries"
  ln -s Versions/Current/Helpers "$fw/Helpers"
  ln -s Versions/Current/Libraries "$fw/Libraries"
  local kind
  for kind in "" "Aperitif "; do
    if [[ -z "$kind" ]]; then
      helper "$helpers" "Clair Helper" dev.joshuapark.Clair.helper
    else
      helper "$helpers" "Clair Helper (Aperitif)" dev.joshuapark.Clair.helper
    fi
    helper "$helpers" "Clair Helper (${kind}Renderer)" dev.joshuapark.Clair.helper.renderer
    helper "$helpers" "Clair Helper (${kind}GPU)" dev.joshuapark.Clair.helper
    helper "$helpers" "Clair Helper (${kind}Alerts)" dev.joshuapark.Clair.framework.AlertNotificationService
  done
  local tool
  for tool in chrome_crashpad_handler app_mode_loader web_app_shortcut_copier; do
    cp "$workdir/exe" "$helpers/$tool"
  done
  cp "$workdir/lib" "$fw/Versions/A/Libraries/libvulkan.dylib"
  codesign --sign - --force --deep "$app" 2>/dev/null
}

make_clairui() {
  rm -rf "$1"
  framework "$1/ClairUI.framework" ClairUI dev.joshuapark.Clair.ClairUI lib
}

# A directory as fetch-sparkle.sh leaves it, with Sparkle's universal binaries.
make_sparkle() {
  local dir="$1" autoupdate="${2-exe-universal}"
  rm -rf "$dir"
  local fw="$dir/Sparkle.framework"
  mkdir -p "$fw/Versions/B/Resources" "$fw/Versions/B/XPCServices/Installer.xpc/Contents/MacOS" "$dir/bin"
  cp "$workdir/lib-universal" "$fw/Versions/B/Sparkle"
  cp "$workdir/$autoupdate" "$fw/Versions/B/Autoupdate"
  plist "$fw/Versions/B/Resources/Info.plist" org.sparkle-project.Sparkle Sparkle FMWK
  local updater="$fw/Versions/B/Updater.app"
  mkdir -p "$updater/Contents/MacOS"
  cp "$workdir/exe-universal" "$updater/Contents/MacOS/Updater"
  plist "$updater/Contents/Info.plist" org.sparkle-project.Sparkle.Updater Updater
  cp "$workdir/exe" "$fw/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer"
  ln -s B "$fw/Versions/Current"
  ln -s Versions/Current/Sparkle "$fw/Sparkle"
  ln -s Versions/Current/Resources "$fw/Resources"
  ln -s Versions/Current/XPCServices "$fw/XPCServices"
  echo "Sparkle 2.10.0 stand-in" >"$dir/.sparkle-release"
}

engine="$workdir/engine"
clairui="$workdir/clairui"
sparkle="$workdir/sparkle"
key_file="$workdir/public-ed-key.txt"
make_engine "$engine"
make_clairui "$clairui"
make_sparkle "$sparkle"
echo "pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ=" >"$key_file"

output=""
run_package() {
  output="$("$package" --clairui "$clairui/ClairUI.framework" --sparkle "$sparkle" "$@" 2>&1)"
}

expect_refusal() {
  local description="$1" message="$2"; shift 2
  if run_package "$@"; then
    check "$description" fail
    echo "         succeeded: $output"
  elif [[ "$output" == *"$message"* ]]; then
    check "$description" pass
  else
    check "$description" fail
    echo "         expected a message containing: $message"
    echo "$output" | tail -5 | sed 's/^/         /'
  fi
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null
}

# --- a package from the engine app ------------------------------------------------
out="$workdir/out1"
if run_package --version 1.2.3 --build 42 --public-key "$key_file" --no-dmg "$engine/Clair.app" "$out"; then
  check "packages an engine app" pass
else
  check "packages an engine app" fail
  echo "$output" | tail -10 | sed 's/^/         /'
fi
app="$out/Clair.app"
info="$app/Contents/Info.plist"

if [[ "$(plist_value "$info" CFBundleShortVersionString)" == 1.2.3 && "$(plist_value "$info" CFBundleVersion)" == 42 ]]; then
  check "writes the Clair version and build number" pass
else
  check "writes the Clair version and build number" fail
fi

if [[ "$(plist_value "$info" SUFeedURL)" == "https://github.com/itsjoshpark/Clair/raw/main/.sparkle/appcast.xml" \
    && "$(plist_value "$info" SUEnableAutomaticChecks)" == true \
    && "$(plist_value "$info" SUPublicEDKey)" == "pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ=" ]]; then
  check "writes SUFeedURL, SUEnableAutomaticChecks and SUPublicEDKey" pass
else
  check "writes SUFeedURL, SUEnableAutomaticChecks and SUPublicEDKey" fail
fi

if [[ -f "$app/Contents/Frameworks/ClairUI.framework/Versions/A/ClairUI" && -f "$app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle" ]]; then
  check "embeds ClairUI.framework and Sparkle.framework" pass
else
  check "embeds ClairUI.framework and Sparkle.framework" fail
fi

if [[ ! -e "$app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" && ! -L "$app/Contents/Frameworks/Sparkle.framework/XPCServices" ]]; then
  check "leaves out Sparkle's XPC services" pass
else
  check "leaves out Sparkle's XPC services" fail
fi

thin=pass
for file in Sparkle Autoupdate Updater.app/Contents/MacOS/Updater; do
  [[ "$(lipo -archs "$app/Contents/Frameworks/Sparkle.framework/Versions/B/$file")" == arm64 ]] || thin=fail
done
check "thins Sparkle's universal binaries to arm64" "$thin"

if codesign --verify --strict "$app" 2>/dev/null; then
  check "the app's signature verifies strictly" pass
else
  check "the app's signature verifies strictly" fail
fi

all_verify=pass
while IFS= read -r -d '' bundle; do
  codesign --verify --strict "$bundle" 2>/dev/null || { all_verify=fail; echo "         ${bundle#"$app/"}"; }
done < <(find "$app/Contents" \( -name '*.app' -o -name '*.framework' \) -type d -print0)
check "every nested bundle's signature verifies strictly" "$all_verify"

identifiers=pass
for pair in \
    "Contents/Frameworks/Clair Framework.framework/Helpers/Clair Helper (Renderer).app=dev.joshuapark.Clair.helper.renderer" \
    "Contents/Frameworks/Clair Framework.framework/Helpers/Clair Helper (Aperitif Alerts).app=dev.joshuapark.Clair.framework.AlertNotificationService" \
    "Contents/Frameworks/Clair Framework.framework=dev.joshuapark.Clair.framework" \
    "Contents/Frameworks/ClairUI.framework=dev.joshuapark.Clair.ClairUI" \
    ".=dev.joshuapark.Clair"; do
  path="${pair%%=*}" expected="${pair#*=}"
  signed="$(codesign -dv "$app/$path" 2>&1 | sed -n 's/^Identifier=//p')"
  [[ "$signed" == "$expected" ]] || { identifiers=fail; echo "         $path is signed as $signed"; }
done
check "signs each bundle as its own identifier" "$identifiers"

if ! codesign -dv "$app" 2>&1 | grep -q 'flags=.*runtime'; then
  check "an ad hoc package runs without the hardened runtime" pass
else
  check "an ad hoc package runs without the hardened runtime" fail
fi

if "$root/scripts/verify-app.sh" "$app" >/dev/null 2>&1; then
  check "the package passes verify-app.sh" pass
else
  check "the package passes verify-app.sh" fail
  "$root/scripts/verify-app.sh" "$app" 2>&1 | grep FAIL | sed 's/^/         /'
fi

if [[ "$(plist_value "$engine/Clair.app/Contents/Info.plist" CFBundleShortVersionString)" == 156.0.8078.73 \
    && ! -e "$engine/Clair.app/Contents/Frameworks/ClairUI.framework" ]]; then
  check "leaves the engine untouched" pass
else
  check "leaves the engine untouched" fail
fi

# --- a package from the engine zip, with the DMG ------------------------------------
(cd "$engine" && ditto -c -k --keepParent Clair.app "$workdir/engine.zip")
out="$workdir/out2"
if run_package --version 0.1.0 --build 7 --public-key "$workdir/no-key.txt" "$workdir/engine.zip" "$out" \
    && [[ -f "$out/Clair-0.1.0-arm64.dmg" ]]; then
  check "packages the engine zip and builds Clair-<version>-arm64.dmg" pass
else
  check "packages the engine zip and builds Clair-<version>-arm64.dmg" fail
  echo "$output" | tail -10 | sed 's/^/         /'
fi

if [[ "$output" == *"no Sparkle public key"* && -z "$(plist_value "$out/Clair.app/Contents/Info.plist" SUPublicEDKey)" ]]; then
  check "without a public key, warns and writes no SUPublicEDKey" pass
else
  check "without a public key, warns and writes no SUPublicEDKey" fail
fi

mount="$workdir/mount"
mkdir "$mount"
if hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount" "$out/Clair-0.1.0-arm64.dmg" 2>/dev/null; then
  if [[ -d "$mount/Clair.app" && "$(readlink "$mount/Applications")" == /Applications ]] \
      && codesign --verify --strict "$mount/Clair.app" 2>/dev/null; then
    check "the DMG holds the signed Clair.app and an /Applications link" pass
  else
    check "the DMG holds the signed Clair.app and an /Applications link" fail
  fi
  hdiutil detach -quiet "$mount" || true
else
  check "the DMG holds the signed Clair.app and an /Applications link" fail
  echo "         hdiutil couldn't mount it"
fi

# --- refusals ---------------------------------------------------------------------
expect_refusal "refuses an output directory that already has Clair.app" "already exists" \
  --version 0.1.0 --build 7 --no-dmg "$engine/Clair.app" "$workdir/out1"
expect_refusal "rejects a version that isn't X.Y.Z" "must be X.Y.Z" \
  --version 0.1 --build 7 "$engine/Clair.app" "$workdir/out3"
expect_refusal "rejects a version with a leading zero" "must be X.Y.Z" \
  --version 0.01.0 --build 7 "$engine/Clair.app" "$workdir/out3"
expect_refusal "rejects a build number that isn't a positive integer" "positive integer" \
  --version 0.1.0 --build 0 "$engine/Clair.app" "$workdir/out3"
echo "not a key" >"$workdir/bad-key.txt"
expect_refusal "rejects a public key that isn't one" "base64 Ed25519" \
  --version 0.1.0 --build 7 --public-key "$workdir/bad-key.txt" "$engine/Clair.app" "$workdir/out3"
expect_refusal "refuses an identity that isn't in the keychain" "no valid signing identity" \
  --version 0.1.0 --build 7 --identity "Developer ID Application: Nobody (0000000000)" "$engine/Clair.app" "$workdir/out3"

make_engine "$workdir/foreign" org.chromium.Chromium
expect_refusal "refuses an engine with another bundle identifier" "not dev.joshuapark.Clair" \
  --version 0.1.0 --build 7 --no-dmg "$workdir/foreign/Clair.app" "$workdir/out3"

make_engine "$workdir/twice"
framework "$workdir/twice/Clair.app/Contents/Frameworks/ClairUI.framework" ClairUI dev.joshuapark.Clair.ClairUI lib
expect_refusal "refuses an engine that already contains ClairUI.framework" "already contains ClairUI.framework" \
  --version 0.1.0 --build 7 --no-dmg "$workdir/twice/Clair.app" "$workdir/out3"

make_sparkle "$sparkle" exe-x86_64
expect_refusal "refuses a Sparkle binary without arm64 code" "has no arm64 code" \
  --version 0.1.0 --build 7 --no-dmg "$engine/Clair.app" "$workdir/out3"
make_sparkle "$sparkle"

rm "$sparkle/.sparkle-release"
expect_refusal "refuses a Sparkle directory not made by fetch-sparkle.sh" "not a directory from fetch-sparkle.sh" \
  --version 0.1.0 --build 7 --no-dmg "$engine/Clair.app" "$workdir/out3"

if [[ ! -e "$workdir/out3/Clair.app" ]]; then
  check "a refused package leaves nothing behind" pass
else
  check "a refused package leaves nothing behind" fail
fi

echo
if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
