#!/bin/bash
# Turns an engine into Clair.app (change 1 design D3, D4, D5): embeds
# ClairUI.framework and Sparkle.framework, writes the Clair version, the build
# number and Sparkle's keys into Info.plist, signs every nested bundle inside
# out without --deep, and builds the DMG.
#
#   package.sh [options] <engine> <out-dir>
#
# <engine> is the engine's Clair.app, or its zip from chromium-engine-<key>.
# <out-dir> receives Clair.app and Clair-<version>-arm64.dmg; it must not hold
# a Clair.app already.
#
# Options:
#   --clairui <dir>      a built ClairUI.framework (default: build it from
#                        native/ClairUI.xcodeproj, Release)
#   --sparkle <dir>      a directory from scripts/fetch-sparkle.sh (default:
#                        fetch into build/sparkle)
#   --version <x.y.z>    the Clair version (default: version.txt)
#   --build <n>          the build number (default: git rev-list --count HEAD)
#   --public-key <file>  the file holding Sparkle's public EdDSA key (default:
#                        .sparkle/public-ed-key.txt). Without one, the package
#                        has no SUPublicEDKey and Sparkle installs no update.
#   --identity <name>    the Developer ID Application identity to sign with,
#                        from the keychain search list. Without it, the app is
#                        signed ad hoc.
#   --no-dmg             stop after signing the app
#
# Notarization and stapling come later (task 5.2).

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bundle_id="dev.joshuapark.Clair"
feed_url="https://github.com/itsjoshpark/Clair/raw/main/.sparkle/appcast.xml"
product="Clair"

die() {
  echo "package: $1" >&2
  exit 1
}

usage() {
  sed -n '/^#   package.sh/,/^# Notarization/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

clairui="" sparkle="" version="" build="" public_key_file="$root/.sparkle/public-ed-key.txt"
identity="" dmg=true
args=()
while (( $# > 0 )); do
  case "$1" in
    --clairui) clairui="${2-}"; shift 2 || usage ;;
    --sparkle) sparkle="${2-}"; shift 2 || usage ;;
    --version) version="${2-}"; shift 2 || usage ;;
    --build) build="${2-}"; shift 2 || usage ;;
    --public-key) public_key_file="${2-}"; shift 2 || usage ;;
    --identity) identity="${2-}"; shift 2 || usage ;;
    --no-dmg) dmg=false; shift ;;
    -h|--help) usage ;;
    -*) die "unknown option: $1" ;;
    *) args+=("$1"); shift ;;
  esac
done
(( ${#args[@]} == 2 )) || usage
engine="${args[0]%/}"
out="${args[1]%/}"

# --- inputs ---------------------------------------------------------------------
if [[ -z "$version" ]]; then
  [[ -f "$root/version.txt" ]] || die "no --version and no version.txt"
  version="$(cat "$root/version.txt")"
fi
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || die "the version must be X.Y.Z: $version"
if [[ -z "$build" ]]; then
  build="$(git -C "$root" rev-list --count HEAD)" || die "can't count commits for the build number; pass --build"
fi
[[ "$build" =~ ^[1-9][0-9]*$ ]] || die "the build number must be a positive integer: $build"

public_key=""
if [[ -f "$public_key_file" ]]; then
  public_key="$(tr -d '[:space:]' <"$public_key_file")"
  # An Ed25519 public key: 32 bytes, base64.
  [[ "$public_key" =~ ^[A-Za-z0-9+/]{43}=$ ]] || die "$public_key_file doesn't hold a base64 Ed25519 public key"
else
  echo "package: warning: no Sparkle public key at $public_key_file; this package can't install updates" >&2
fi

if [[ -n "$identity" ]]; then
  security find-identity -v -p codesigning | grep -qF "\"$identity\"" ||
    die "no valid signing identity named \"$identity\" in the keychain search list"
fi

[[ -e "$engine" ]] || die "no engine at $engine"
[[ ! -e "$out/$product.app" ]] || die "$out/$product.app already exists"
mkdir -p "$out"
out="$(cd "$out" && pwd -P)"

work="$(mktemp -d "${TMPDIR:-/tmp}/clair-package.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# --- the engine -------------------------------------------------------------------
app="$work/$product.app"
if [[ -d "$engine" ]]; then
  [[ "$(basename "$engine")" == "$product.app" ]] || die "the engine app must be named $product.app: $engine"
  ditto "$engine" "$app"
else
  ditto -x -k "$engine" "$work/engine" || die "can't unpack $engine"
  [[ -d "$work/engine/$product.app" ]] || die "$engine holds no $product.app at its top level"
  mv "$work/engine/$product.app" "$app"
fi
info="$app/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info" 2>/dev/null)" == "$bundle_id" ]] ||
  die "the engine's bundle identifier is not $bundle_id"
frameworks="$app/Contents/Frameworks"
chromium_framework="$frameworks/$product Framework.framework"
[[ -d "$chromium_framework" ]] || die "the engine has no $product Framework.framework"
for embedded in ClairUI.framework Sparkle.framework; do
  [[ ! -e "$frameworks/$embedded" ]] || die "the engine already contains $embedded"
done
# Extended attributes, such as quarantine, would break the signatures.
xattr -cr "$app"

# --- ClairUI ------------------------------------------------------------------------
if [[ -z "$clairui" ]]; then
  echo "package: building ClairUI" >&2
  xcodebuild -project "$root/native/ClairUI.xcodeproj" -scheme ClairUI \
    -configuration Release -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$work/DerivedData" CODE_SIGNING_ALLOWED=NO -quiet build >&2 ||
    die "ClairUI didn't build"
  clairui="$work/DerivedData/Build/Products/Release/ClairUI.framework"
fi
clairui="${clairui%/}"
[[ -f "$clairui/Resources/Info.plist" && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$clairui/Resources/Info.plist" 2>/dev/null)" == "$bundle_id.ClairUI" ]] ||
  die "not a ClairUI.framework: $clairui"
ditto "$clairui" "$frameworks/ClairUI.framework"

# --- Sparkle ------------------------------------------------------------------------
if [[ -z "$sparkle" ]]; then
  sparkle="$("$root/scripts/fetch-sparkle.sh" "$root/build/sparkle")"
fi
sparkle="${sparkle%/}"
[[ -f "$sparkle/.sparkle-release" && -d "$sparkle/Sparkle.framework" ]] ||
  die "not a directory from fetch-sparkle.sh: $sparkle"
ditto "$sparkle/Sparkle.framework" "$frameworks/Sparkle.framework"
# Clair isn't sandboxed, so Sparkle needs no XPC services (Sparkle's
# documentation); leaving them out leaves less to sign.
rm -rf "$frameworks/Sparkle.framework/Versions/B/XPCServices" "$frameworks/Sparkle.framework/XPCServices"
# Sparkle ships universal binaries; Clair is arm64 only.
while IFS= read -r -d '' file; do
  archs="$(lipo -archs "$file" 2>/dev/null)" || continue
  if [[ "$archs" != arm64 ]]; then
    [[ " $archs " == *" arm64 "* ]] || die "${file#"$work/"} has no arm64 code"
    lipo -thin arm64 -output "$file.arm64" "$file"
    mv "$file.arm64" "$file"
  fi
done < <(find "$frameworks/Sparkle.framework/Versions/B" -type f -print0)

# --- Info.plist ---------------------------------------------------------------------
plist_set() {
  local key="$1" type="$2" value="$3"
  /usr/libexec/PlistBuddy -c "Delete :$key" "$info" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :$key $type $value" "$info"
}
plist_set CFBundleShortVersionString string "$version"
plist_set CFBundleVersion string "$build"
plist_set SUFeedURL string "$feed_url"
plist_set SUEnableAutomaticChecks bool true
if [[ -n "$public_key" ]]; then
  plist_set SUPublicEDKey string "$public_key"
fi

# --- signing ------------------------------------------------------------------------
# Inside out, each bundle with its own identifier (see ungoogled-chromium-macos
# issue 361), never with --deep. Ported from ungoogled-chromium-macos's
# sign_and_package_app.sh (BSD-3-Clause, see CREDITS.md).
sign() {
  if [[ -n "$identity" ]]; then
    codesign --sign "$identity" --force --timestamp "$@"
    return
  fi
  # An ad hoc signature has no Team ID, so the library validation that the
  # hardened runtime turns on would refuse every framework, Chromium's own
  # included. Ad hoc packages, which only tests use, run without it.
  local args=()
  while (( $# > 0 )); do
    if [[ "$1" == --options ]]; then
      shift 2
      continue
    fi
    args+=("$1")
    shift
  done
  codesign --sign - --force "${args[@]}"
}

entitlements="$root/entitlements"
helpers="$chromium_framework/Helpers"
libraries="$chromium_framework/Libraries"
hardened=(--options "restrict,library,runtime,kill")

sign --identifier chrome_crashpad_handler "${hardened[@]}" "$helpers/chrome_crashpad_handler"
# The Aperitif helpers come in the same four kinds, when the engine has them.
sign_helpers() {
  local main="$1" kind="$2"
  local base="$helpers/$product Helper"
  sign --identifier "$bundle_id.helper" "${hardened[@]}" "$main"
  sign --identifier "$bundle_id.helper.renderer" --options restrict,kill,runtime \
    --entitlements "$entitlements/helper-renderer-entitlements.plist" "$base (${kind}Renderer).app"
  sign --identifier "$bundle_id.helper" --options restrict,kill,runtime \
    --entitlements "$entitlements/helper-gpu-entitlements.plist" "$base (${kind}GPU).app"
  sign --identifier "$bundle_id.framework.AlertNotificationService" "${hardened[@]}" "$base (${kind}Alerts).app"
}
sign_helpers "$helpers/$product Helper.app" ""
if [[ -d "$helpers/$product Helper (Aperitif).app" ]]; then
  sign_helpers "$helpers/$product Helper (Aperitif).app" "Aperitif "
fi
sign --identifier app_mode_loader "${hardened[@]}" "$helpers/app_mode_loader"
sign --identifier web_app_shortcut_copier "${hardened[@]}" "$helpers/web_app_shortcut_copier"
for dylib in "$libraries"/*.dylib; do
  [[ -e "$dylib" ]] || continue
  sign --identifier "$(basename "$dylib" .dylib)" "$dylib"
done
sign --identifier "$bundle_id.framework" "$chromium_framework"

sparkle_framework="$frameworks/Sparkle.framework"
sign --options runtime "$sparkle_framework/Versions/B/Autoupdate"
sign --options runtime "$sparkle_framework/Versions/B/Updater.app"
sign --options runtime "$sparkle_framework"

sign --options runtime "$frameworks/ClairUI.framework"

if [[ -n "$identity" ]]; then
  sign --identifier "$bundle_id" "${hardened[@]}" --entitlements "$entitlements/app-entitlements.plist" \
    --requirements "=designated => identifier \"$bundle_id\" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */" \
    "$app"
else
  sign --identifier "$bundle_id" "${hardened[@]}" --entitlements "$entitlements/app-entitlements.plist" "$app"
fi

# --- verification -----------------------------------------------------------------
nested=(
  "$frameworks/ClairUI.framework"
  "$sparkle_framework/Versions/B/Autoupdate"
  "$sparkle_framework/Versions/B/Updater.app"
  "$sparkle_framework"
  "$chromium_framework"
  "$helpers"/*.app
  "$app"
)
for code in "${nested[@]}"; do
  codesign --verify --strict "$code" || die "the signature of ${code#"$work/"} doesn't verify"
done
# Every bundle is signed as its own bundle identifier.
for bundle in "$app" "$helpers"/*.app "$frameworks/ClairUI.framework" "$chromium_framework"; do
  plist="$bundle/Contents/Info.plist"
  [[ -f "$plist" ]] || plist="$bundle/Resources/Info.plist"
  expected="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
  signed="$(codesign -dv "$bundle" 2>&1 | sed -n 's/^Identifier=//p')"
  [[ "$signed" == "$expected" ]] || die "${bundle#"$work/"} is signed as $signed, not $expected"
done

mv "$app" "$out/$product.app"
echo "package: $out/$product.app ($version, build $build, $([[ -n "$identity" ]] && echo "signed by $identity" || echo "signed ad hoc"))"

# --- DMG --------------------------------------------------------------------------
if $dmg; then
  dmg_path="$out/$product-$version-arm64.dmg"
  rm -f "$dmg_path"
  staging="$work/dmg"
  mkdir "$staging"
  ditto "$out/$product.app" "$staging/$product.app"
  ln -s /Applications "$staging/Applications"
  hdiutil create -quiet -volname "$product" -srcfolder "$staging" -fs HFS+ -format ULFO "$dmg_path" ||
    die "hdiutil couldn't create the DMG"
  if [[ -n "$identity" ]]; then
    codesign --sign "$identity" --timestamp "$dmg_path"
  fi
  echo "package: $dmg_path"
fi
