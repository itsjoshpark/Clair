#!/bin/bash
# Tests for package.sh. Run directly: ./package.test.sh
#
# Packages a stand-in engine, ClairUI and Sparkle made of small real Mach-O
# files, so it needs no Chromium (needs clang from Xcode or the Command Line
# Tools). Builds real DMGs with dmgbuild, which scripts/fetch-dmgbuild.sh
# installs into build/dmgbuild, from PyPI the first time. Signs ad hoc only,
# with stand-ins for Apple's notary service; real Developer ID signing and
# notarization are checked by the release dry run.

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package="$root/package.sh"
layout="$root/resources/dmg/layout.json"

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
# Any real icon will do; the DMG's volume icon must match it byte for byte.
cp /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns "$workdir/app.icns" || exit 1

dmgbuild="$("$root/scripts/fetch-dmgbuild.sh" "$root/build/dmgbuild")" || exit 1
dmg_python="$(dirname "$dmgbuild")/python"

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
  if [[ "${3-icon}" == icon ]]; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string app" "$app/Contents/Info.plist"
    mkdir -p "$app/Contents/Resources"
    cp "$workdir/app.icns" "$app/Contents/Resources/app.icns"
  fi
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
  output="$("$package" --clairui "$clairui/ClairUI.framework" --sparkle "$sparkle" --dmgbuild "$dmgbuild" "$@" 2>&1)"
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
    && "$(plist_value "$info" SUAutomaticallyUpdate)" == true \
    && "$(plist_value "$info" SUScheduledCheckInterval)" == 86400 \
    && "$(plist_value "$info" SUPublicEDKey)" == "pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ=" ]]; then
  check "writes SUFeedURL, the automatic update keys and SUPublicEDKey" pass
else
  check "writes SUFeedURL, the automatic update keys and SUPublicEDKey" fail
fi

if [[ "$(plist_value "$info" ClairNonOfficialPackage)" == true ]]; then
  check "marks an ad hoc package as non-official" pass
else
  check "marks an ad hoc package as non-official" fail
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

if "$root/scripts/verify-app.sh" --skip-signing --version 1.2.3 "$app" >/dev/null 2>&1; then
  check "the package passes verify-app.sh" pass
else
  check "the package passes verify-app.sh" fail
  "$root/scripts/verify-app.sh" --skip-signing --version 1.2.3 "$app" 2>&1 | grep FAIL | sed 's/^/         /'
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

# --- the DMG window (style-release-dmg design D5) -----------------------------------
# What the layout should be, from layout.json, and what a mounted DMG's .DS_Store
# says it is, one fact a line: "<fact> <value>".
layout_facts() {
  "$dmg_python" -I -c '
import json, sys
layout = json.load(open(sys.argv[1]))
w = layout["window"]
print("window {{%d, %d}, {%d, %d}}" % (w["x"], w["y"], w["width"], w["height"]))
print("icon_size %s" % float(layout["icon_size"]))
for name, (x, y) in sorted(layout["icons"].items()):
    print("position %s %d %d" % (name, x, y))
print("bars off")
print("background /.background.tiff")
' "$layout"
}

dmg_facts() {
  "$dmg_python" -I -c '
import sys
from ds_store import DSStore
from mac_alias import Alias
bars = ("ShowToolbar", "ShowSidebar", "ShowStatusBar", "ShowPathbar", "ShowTabView")
with DSStore.open(sys.argv[1] + "/.DS_Store", "r") as store:
    positions = {}
    for entry in store:
        if entry.code == b"Iloc":
            positions[entry.filename] = entry.value
        elif entry.filename == "." and entry.code == b"bwsp":
            print("window %s" % entry.value["WindowBounds"])
            on = [bar for bar in bars if entry.value.get(bar, True)]
            print("bars %s" % (" ".join(on) or "off"))
        elif entry.filename == "." and entry.code == b"icvp":
            print("icon_size %s" % float(entry.value["iconSize"]))
            if entry.value.get("backgroundType") == 2:
                alias = Alias.from_bytes(entry.value["backgroundImageAlias"])
                print("background %s" % alias.target.posix_path)
            else:
                print("background none")
    for name, (x, y) in sorted(positions.items()):
        print("position %s %d %d" % (name, x, y))
' "$1"
}

tiff_sizes() {
  tiffutil -info "$1" 2>/dev/null | sed -n 's/^ *Image Width: \([0-9]*\) Image Length: \([0-9]*\)$/\1x\2/p' | tr '\n' ' '
}

expected_facts="$(layout_facts)"
read -r window_width window_height < <("$dmg_python" -I -c 'import json, sys; w = json.load(open(sys.argv[1]))["window"]; print(w["width"], w["height"])' "$layout")

mount="$workdir/mount"
mkdir "$mount"
if hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount" "$out/Clair-0.1.0-arm64.dmg" 2>/dev/null; then
  if [[ -d "$mount/Clair.app" && "$(readlink "$mount/Applications")" == /Applications ]] \
      && codesign --verify --strict "$mount/Clair.app" 2>/dev/null; then
    check "the DMG holds the signed Clair.app and an /Applications link" pass
  else
    check "the DMG holds the signed Clair.app and an /Applications link" fail
  fi

  visible="$(ls "$mount" | tr '\n' ' ')"
  if [[ "$visible" == "Applications Clair.app " ]]; then
    check "Clair.app and Applications are the only visible items" pass
  else
    check "Clair.app and Applications are the only visible items" fail
    echo "         got: $visible"
  fi

  sizes="$(tiff_sizes "$mount/.background.tiff")"
  if [[ "$sizes" == "${window_width}x$window_height $((window_width * 2))x$((window_height * 2)) " ]]; then
    check "the background holds the window's 1x and 2x images" pass
  else
    check "the background holds the window's 1x and 2x images" fail
    echo "         got: ${sizes:-no .background.tiff}"
  fi

  # kHasCustomIcon is bit 10 of the Finder flags, which start at byte 8 of FinderInfo.
  finder_flags="$(xattr -px com.apple.FinderInfo "$mount" 2>/dev/null | tr -d ' \n' | cut -c17-18)"
  if cmp -s "$mount/.VolumeIcon.icns" "$out/Clair.app/Contents/Resources/app.icns" \
      && (( (0x${finder_flags:-00} & 0x04) != 0 )); then
    check "the volume icon is the app's icon, and the volume shows it" pass
  else
    check "the volume icon is the app's icon, and the volume shows it" fail
  fi

  actual_facts="$(dmg_facts "$mount" 2>&1)"
  for pair in "window=the window's position and size" "icon_size=the icon size" "position=the icons' positions" \
      "bars=no toolbar, sidebar, status bar, path bar or tab bar" "background=the background alias"; do
    fact="${pair%%=*}" description="${pair#*=}"
    expected="$(grep "^$fact " <<<"$expected_facts")"
    actual="$(grep "^$fact " <<<"$actual_facts")"
    if [[ -n "$expected" && "$actual" == "$expected" ]]; then
      check "the .DS_Store sets $description, as layout.json says" pass
    else
      check "the .DS_Store sets $description, as layout.json says" fail
      echo "         expected: $expected"
      echo "         got: ${actual:-$actual_facts}"
    fi
  done
  hdiutil detach -quiet "$mount" || true
else
  check "the DMG holds the signed Clair.app and an /Applications link" fail
  echo "         hdiutil couldn't mount it"
fi

# --- dmgbuild failures ----------------------------------------------------------------
# A stand-in dmgbuild, so a flaky one can be tried again without waiting on real
# DMGs. The DMG tests above cover the real thing.
stub_bin="$workdir/stub-bin"
mkdir "$stub_bin"
printf '#!/bin/bash\necho "$1" >>"%s"\n' "$workdir/sleeps" >"$stub_bin/sleep"
cat >"$stub_bin/dmgbuild" <<EOF
#!/bin/bash
count="\$(cat "$workdir/dmgbuild-count" 2>/dev/null || echo 0)"
echo "\$((count + 1))" >"$workdir/dmgbuild-count"
printf '%s\n' "\$@" >"$workdir/dmgbuild-args"
if ((count < DMGBUILD_FAILURES)); then
  echo "dmgbuild: Unable to create disk image: Resource busy" >&2
  exit 1
fi
: >"\${!#}"
EOF
chmod +x "$stub_bin/sleep" "$stub_bin/dmgbuild"

echo 0 >"$workdir/dmgbuild-count"
: >"$workdir/sleeps"
out="$workdir/out-retry"
if DMGBUILD_FAILURES=2 PATH="$stub_bin:$PATH" run_package --version 0.1.0 --build 7 --dmgbuild "$stub_bin/dmgbuild" "$engine/Clair.app" "$out" \
    && [[ -f "$out/Clair-0.1.0-arm64.dmg" && "$(cat "$workdir/dmgbuild-count")" == 3 ]]; then
  check "tries dmgbuild again when it fails" pass
else
  check "tries dmgbuild again when it fails" fail
  echo "$output" | tail -5 | sed 's/^/         /'
fi

# Long enough to outlast simdiskimaged's unmount retries on hosted runners.
if [[ "$(tr '\n' ' ' <"$workdir/sleeps")" == "30 30 " ]]; then
  check "waits 30 seconds before each new attempt" pass
else
  check "waits 30 seconds before each new attempt" fail
  echo "         slept: $(tr '\n' ' ' <"$workdir/sleeps")"
fi

passed="$(tr '\n' ' ' <"$workdir/dmgbuild-args")"
out="$(cd "$out" && pwd -P)"
if [[ "$passed" == *"-s $root/resources/dmg/settings.py "* \
    && "$passed" == *"-D app=$out/Clair.app "* \
    && "$passed" == *"-D icon=$out/Clair.app/Contents/Resources/app.icns "* \
    && "$passed" == *"-D background=$root/resources/dmg/background.tiff "* \
    && "$passed" == *"-D layout=$layout "* \
    && "$passed" == *" Clair $out/Clair-0.1.0-arm64.dmg " ]]; then
  check "passes dmgbuild the settings, the app, its icon, the background and the layout" pass
else
  check "passes dmgbuild the settings, the app, its icon, the background and the layout" fail
  echo "         $passed"
fi

echo 0 >"$workdir/dmgbuild-count"
out="$workdir/out-busy"
if DMGBUILD_FAILURES=99 PATH="$stub_bin:$PATH" run_package --version 0.1.0 --build 7 --dmgbuild "$stub_bin/dmgbuild" "$engine/Clair.app" "$out"; then
  check "stops after three dmgbuild failures, showing its error" fail
elif [[ "$output" == *"Resource busy"* && "$output" == *"couldn't create the DMG"* \
    && "$(cat "$workdir/dmgbuild-count")" == 3 && ! -e "$out/Clair-0.1.0-arm64.dmg" ]]; then
  check "stops after three dmgbuild failures, showing its error" pass
else
  check "stops after three dmgbuild failures, showing its error" fail
  echo "$output" | tail -5 | sed 's/^/         /'
fi

expect_refusal "refuses a missing dmgbuild" "no dmgbuild at" \
  --version 0.1.0 --build 7 --dmgbuild "$workdir/no-dmgbuild" "$engine/Clair.app" "$workdir/out3"

# --- signing with an identity -----------------------------------------------------
# No Developer ID here: stand-ins accept the identity and sign ad hoc instead.
identity_bin="$workdir/identity-bin"
mkdir "$identity_bin"
cat >"$identity_bin/security" <<'EOF'
#!/bin/bash
echo '  1) 0000000000000000000000000000000000000000 "Test Identity"'
EOF
cat >"$identity_bin/codesign" <<'EOF'
#!/bin/bash
args=()
while (( $# > 0 )); do
  case "$1" in
    --sign) args+=(--sign -); shift 2 ;;
    --keychain) [[ -z "${KEYCHAIN_LOG-}" ]] || echo "$2" >>"$KEYCHAIN_LOG"; shift 2 ;;
    --timestamp) shift ;;
    --requirements|--options) shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
exec /usr/bin/codesign "${args[@]}"
EOF
chmod +x "$identity_bin/security" "$identity_bin/codesign"
out="$workdir/out-identity"
if PATH="$identity_bin:$PATH" run_package --version 0.1.0 --build 7 --no-dmg --identity "Test Identity" "$engine/Clair.app" "$out" \
    && [[ -f "$out/Clair.app/Contents/Info.plist" && -z "$(plist_value "$out/Clair.app/Contents/Info.plist" ClairNonOfficialPackage)" ]]; then
  check "leaves the non-official mark off a package signed with an identity" pass
else
  check "leaves the non-official mark off a package signed with an identity" fail
  echo "$output" | tail -5 | sed 's/^/         /'
fi

# A keychain limits both the identity check and every signature to it.
signing_keychain="$workdir/signing.keychain-db"
: >"$signing_keychain"
export KEYCHAIN_LOG="$workdir/keychain.log"
out="$workdir/out-keychain"
if PATH="$identity_bin:$PATH" run_package --version 0.1.0 --build 7 --identity "Test Identity" --keychain "$signing_keychain" "$engine/Clair.app" "$out" \
    && [[ -s "$KEYCHAIN_LOG" && -z "$(grep -vxF "$signing_keychain" "$KEYCHAIN_LOG")" ]] \
    && [[ "$(wc -l <"$KEYCHAIN_LOG" | tr -d ' ')" -gt 10 ]]; then
  check "signs everything from the given keychain, the DMG too" pass
else
  check "signs everything from the given keychain, the DMG too" fail
  echo "$output" | tail -5 | sed 's/^/         /'
fi
unset KEYCHAIN_LOG
expect_refusal "refuses a keychain without an identity" "needs --identity" \
  --version 0.1.0 --build 7 --keychain "$signing_keychain" "$engine/Clair.app" "$workdir/out3"
PATH="$identity_bin:$PATH" expect_refusal "refuses a missing keychain" "no keychain at" \
  --version 0.1.0 --build 7 --identity "Test Identity" --keychain "$workdir/none" "$engine/Clair.app" "$workdir/out3"

# --- notarization -----------------------------------------------------------------
# No Apple here: stand-ins log each call, and staple the app by leaving a mark in
# it, as the real ticket goes into the bundle.
notary_bin="$workdir/notary-bin"
mkdir "$notary_bin"
cp "$identity_bin/security" "$identity_bin/codesign" "$notary_bin/"
cat >"$notary_bin/xcrun" <<EOF
#!/bin/bash
echo "\$*" >>"$workdir/notary.log"
case "\$1 \$2" in
  "notarytool submit")
    echo "\$*" >>"$workdir/submitted.log"
    if [[ "\$(basename "\$3")" == *"\${NOTARY_REJECT-none}"* ]]; then
      echo '{"id":"rejected-id","status":"Invalid","message":"Processing complete"}'
    else
      if [[ "\$3" == *.zip ]]; then ditto -x -k "\$3" "$workdir/submitted-app"; fi
      echo '{"id":"accepted-id","status":"Accepted","message":"Processing complete"}'
    fi
    ;;
  "notarytool log") echo "Apple's log for \$3: the signature is invalid" ;;
  "stapler staple")
    if [[ -d "\$3" ]]; then echo stapled >"\$3/Contents/CodeResources"; else echo "\$3" >>"$workdir/stapled-files.log"; fi
    ;;
  "stapler validate") [[ -z "\${STAPLE_INVALID-}" ]] ;;
  *) exit 64 ;;
esac
EOF
chmod +x "$notary_bin/xcrun"
notary_key="$workdir/AuthKey_ABCDE12345.p8"
echo "not a real key" >"$notary_key"
notary_issuer=01234567-89ab-cdef-0123-456789abcdef
notary_args=(--identity "Test Identity" --notary-key "$notary_key" --notary-key-id ABCDE12345 --notary-issuer "$notary_issuer")

: >"$workdir/notary.log"
out="$workdir/out-notary"
if PATH="$notary_bin:$PATH" run_package --version 0.1.0 --build 7 "${notary_args[@]}" "$engine/Clair.app" "$out"; then
  check "notarizes with an API key" pass
else
  check "notarizes with an API key" fail
  echo "$output" | tail -5 | sed 's/^/         /'
fi
order="$(awk '{ print $1, $2 }' "$workdir/notary.log" | tr '\n' ',')"
expected="notarytool submit,stapler staple,stapler validate,notarytool submit,stapler staple,stapler validate,"
if [[ "$order" == "$expected" ]]; then
  check "submits, staples and validates the app, then the DMG" pass
else
  check "submits, staples and validates the app, then the DMG" fail
  echo "         $order"
fi
if [[ "$(sed -n 1p "$workdir/submitted.log")" == *"/Clair.zip --key $notary_key --key-id ABCDE12345 --issuer $notary_issuer --wait"* \
    && "$(sed -n 2p "$workdir/submitted.log")" == *"/Clair-0.1.0-arm64.dmg --key $notary_key --key-id ABCDE12345 --issuer $notary_issuer --wait"* ]]; then
  check "passes the key as a file and IDs, with no keychain profile" pass
else
  check "passes the key as a file and IDs, with no keychain profile" fail
  sed 's/^/         /' "$workdir/submitted.log"
fi
if [[ -f "$workdir/submitted-app/Clair.app/Contents/Info.plist" ]]; then
  check "submits an archive holding Clair.app" pass
else
  check "submits an archive holding Clair.app" fail
fi
if ! grep -q keychain-profile "$workdir/notary.log"; then
  check "never uses a keychain profile" pass
else
  check "never uses a keychain profile" fail
fi
mount="$workdir/mount-notary"
mkdir "$mount"
if [[ "$(cat "$out/Clair.app/Contents/CodeResources" 2>/dev/null)" == stapled \
    && "$(cat "$workdir/stapled-files.log" 2>/dev/null)" == */Clair-0.1.0-arm64.dmg ]]; then
  check "staples the app and the DMG" pass
else
  check "staples the app and the DMG" fail
fi
if hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount" "$out/Clair-0.1.0-arm64.dmg" 2>/dev/null; then
  if [[ "$(cat "$mount/Clair.app/Contents/CodeResources" 2>/dev/null)" == stapled ]]; then
    check "builds the DMG from the stapled app" pass
  else
    check "builds the DMG from the stapled app" fail
  fi
  hdiutil detach -quiet "$mount" || true
else
  check "builds the DMG from the stapled app" fail
  echo "         hdiutil couldn't mount it"
fi

out="$workdir/out-notary-no-dmg"
: >"$workdir/notary.log"
if PATH="$notary_bin:$PATH" run_package --version 0.1.0 --build 7 --no-dmg "${notary_args[@]}" "$engine/Clair.app" "$out" \
    && [[ "$(grep -c 'notarytool submit' "$workdir/notary.log")" == 1 && ! -e "$out/Clair-0.1.0-arm64.dmg" ]]; then
  check "--no-dmg notarizes only the app" pass
else
  check "--no-dmg notarizes only the app" fail
  echo "$output" | tail -5 | sed 's/^/         /'
fi

expect_notary_failure() {
  local description="$1" message="$2" dir="$3"
  if PATH="$notary_bin:$PATH" run_package --version 0.1.0 --build 7 "${notary_args[@]}" "$engine/Clair.app" "$dir"; then
    check "$description" fail
    echo "         succeeded: $output"
  elif [[ "$output" == *"$message"* ]]; then
    check "$description" pass
  else
    check "$description" fail
    echo "$output" | tail -5 | sed 's/^/         /'
  fi
}
NOTARY_REJECT=Clair.zip expect_notary_failure "stops when Apple rejects the app, naming the status" "didn't accept Clair.zip (status: Invalid)" "$workdir/out-rejected-app"
NOTARY_REJECT=Clair.zip expect_notary_failure "shows Apple's log for a rejection" "Apple's log for rejected-id" "$workdir/out-rejected-log"
if [[ ! -e "$workdir/out-rejected-app/Clair-0.1.0-arm64.dmg" ]]; then
  check "builds no DMG when the app is rejected" pass
else
  check "builds no DMG when the app is rejected" fail
fi
NOTARY_REJECT=.dmg expect_notary_failure "stops when Apple rejects the DMG" "didn't accept Clair-0.1.0-arm64.dmg (status: Invalid)" "$workdir/out-rejected-dmg"
STAPLE_INVALID=1 expect_notary_failure "stops when the stapled ticket doesn't validate" "doesn't validate" "$workdir/out-staple"

PATH="$notary_bin:$PATH" expect_refusal "refuses notarization without the key ID and issuer" "together" \
  --version 0.1.0 --build 7 --identity "Test Identity" --notary-key "$notary_key" "$engine/Clair.app" "$workdir/out3"
expect_refusal "refuses to notarize an ad hoc package" "needs --identity" \
  --version 0.1.0 --build 7 --notary-key "$notary_key" --notary-key-id ABCDE12345 --notary-issuer "$notary_issuer" "$engine/Clair.app" "$workdir/out3"
PATH="$notary_bin:$PATH" expect_refusal "refuses a missing API key file" "no App Store Connect API key" \
  --version 0.1.0 --build 7 --identity "Test Identity" --notary-key "$workdir/none.p8" --notary-key-id ABCDE12345 --notary-issuer "$notary_issuer" "$engine/Clair.app" "$workdir/out3"
PATH="$notary_bin:$PATH" expect_refusal "refuses a malformed key ID" "10 letters and digits" \
  --version 0.1.0 --build 7 --identity "Test Identity" --notary-key "$notary_key" --notary-key-id 'x;y' --notary-issuer "$notary_issuer" "$engine/Clair.app" "$workdir/out3"
PATH="$notary_bin:$PATH" expect_refusal "refuses a malformed issuer" "must be a UUID" \
  --version 0.1.0 --build 7 --identity "Test Identity" --notary-key "$notary_key" --notary-key-id ABCDE12345 --notary-issuer nope "$engine/Clair.app" "$workdir/out3"

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

make_engine "$workdir/no-icon" dev.joshuapark.Clair no-icon
expect_refusal "refuses an engine without its icon, which the volume uses" "no CFBundleIconFile" \
  --version 0.1.0 --build 7 --no-dmg "$workdir/no-icon/Clair.app" "$workdir/out3"

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
