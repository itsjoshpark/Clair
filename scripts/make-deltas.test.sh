#!/bin/bash
# Tests for make-deltas.sh. Run directly: scripts/make-deltas.test.sh
#
# Runs Sparkle's real BinaryDelta and sign_update on small ad hoc signed apps,
# with the test-only key, so it needs the pinned Sparkle tarball (downloaded once
# into build/sparkle) and clang. Stand-ins replace gh, and hdiutil, whose "DMG" here
# is a tar file: real hdiutil is covered by the release dry run.

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
script="$root/scripts/make-deltas.sh"

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

sparkle="$("$root/scripts/fetch-sparkle.sh" "$root/build/sparkle")" || exit 1
key_file="$root/tests/runtime/update-key/private-ed-key.txt"
private_key="$(cat "$key_file")"

echo 'int main(void) { return 0; }' >"$workdir/main.c"
cc -arch arm64 -o "$workdir/exe" "$workdir/main.c" || exit 1

# make_app DIR BUILD: an ad hoc signed Clair.app whose contents differ per build.
make_app() {
  local app="$1/Clair.app" build="$2"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cp "$workdir/exe" "$app/Contents/MacOS/Clair"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string dev.joshuapark.Clair" \
    -c "Add :CFBundleExecutable string Clair" \
    -c "Add :CFBundlePackageType string APPL" \
    -c "Add :CFBundleVersion string $build" "$app/Contents/Info.plist" >/dev/null
  echo "resources of build $build" >"$app/Contents/Resources/data.txt"
  codesign --sign - --force "$app" 2>/dev/null
}

# publish VERSION BUILD: a release asset in the stand-in gh's store.
store="$workdir/store"
publish() {
  local version="$1" build="$2" dir="$workdir/published/$1"
  rm -rf "$dir"
  mkdir -p "$dir" "$store/v$version"
  make_app "$dir" "$build"
  tar -cf "$store/v$version/Clair-$version-arm64.dmg" -C "$dir" Clair.app
}

stubs="$workdir/stubs"
mkdir "$stubs"
cat >"$stubs/gh" <<EOF
#!/bin/bash
echo "\$*" >>"$workdir/gh.log"
[[ -z "\${GH_FAILS-}" ]] || { echo "gh: network down" >&2; exit 1; }
case "\$1 \$2" in
  "release list") cat "$workdir/tags" ;;
  "release download")
    tag="\$3"
    shift 3
    while ((\$# > 0)); do
      case "\$1" in
        --pattern) pattern="\$2"; shift 2 ;;
        --dir) dir="\$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    [[ -f "$store/\$tag/\$pattern" ]] || { echo "no assets match" >&2; exit 1; }
    cp "$store/\$tag/\$pattern" "\$dir/"
    ;;
  *) exit 64 ;;
esac
EOF
cat >"$stubs/hdiutil" <<EOF
#!/bin/bash
echo "\$*" >>"$workdir/hdiutil.log"
case "\$1" in
  attach)
    while ((\$# > 1)); do
      [[ "\$1" == -mountpoint ]] && mount="\$2"
      shift
    done
    tar -xf "\$1" -C "\$mount"
    ;;
  detach) ;;
  *) exit 64 ;;
esac
EOF
chmod +x "$stubs/gh" "$stubs/hdiutil"

new="$workdir/new"
mkdir "$new"
make_app "$new" 14
echo "new dmg" >"$workdir/new.dmg"

run() {
  : >"$workdir/gh.log"
  : >"$workdir/hdiutil.log"
  rm -rf "$workdir/out"
  output="$(SPARKLE_ED_PRIVATE_KEY="${KEY-$private_key}" PATH="$stubs:$PATH" "$script" --sparkle "$sparkle" \
    --app "$new/Clair.app" --dmg "$workdir/new.dmg" --version 0.2.0 --build 14 --out "$workdir/out" "$@" 2>"$workdir/stderr")"
}

verifies() {
  "$sparkle/bin/sign_update" --verify --ed-key-file "$key_file" "$1" "$2" >/dev/null 2>&1
}

expect_failure() {
  local description="$1" message="$2"
  shift 2
  if run "$@"; then
    check "$description" fail
    echo "         succeeded: $output"
  elif grep -qF "$message" "$workdir/stderr"; then
    check "$description" pass
  else
    check "$description" fail
    sed 's/^/         /' "$workdir/stderr"
  fi
}

# --- three deltas, from the newest three of four releases ---------------------------
publish 0.1.0 10
publish 0.1.1 11
publish 0.1.9 12
publish 0.1.10 13
# Unsorted, with an engine tag and a pre-release version, and this release's own tag
# from a re-run: none of those may count as previous releases.
printf '%s\n' v0.1.1 chromium-engine-0123456789abcdef v0.1.10 v0.1.0 v0.2.0 v0.1.9 v0.3.0-beta >"$workdir/tags"

if run; then
  check "makes deltas" pass
else
  check "makes deltas" fail
  sed 's/^/         /' "$workdir/stderr"
fi
if grep -q -- "--exclude-drafts --exclude-pre-releases" "$workdir/gh.log"; then
  check "lists only published, final releases" pass
else
  check "lists only published, final releases" fail
fi
dmg_signature="$(sed -n 's/^dmg_signature=//p' <<<"$output")"
if verifies "$workdir/new.dmg" "$dmg_signature" && [[ "$(sed -n 's/^dmg_length=//p' <<<"$output")" == "$(stat -f %z "$workdir/new.dmg")" ]]; then
  check "signs the DMG and gives its length" pass
else
  check "signs the DMG and gives its length" fail
fi
froms="$(sed -n 's/^delta=\([0-9]*\),.*/\1/p' <<<"$output" | tr '\n' ' ')"
if [[ "$froms" == "13 12 11 " ]]; then
  check "uses the newest three previous releases, sorted by version" pass
else
  check "uses the newest three previous releases, sorted by version" fail
  echo "         froms: $froms"
fi
for from in 13 12 11; do
  line="$(sed -n "s/^delta=$from,//p" <<<"$output")"
  IFS=, read -r url signature length <<<"$line"
  file="$workdir/out/Clair-$from-14.delta"
  if [[ "$url" == "https://github.com/itsjoshpark/Clair/releases/download/v0.2.0/Clair-$from-14.delta" ]]; then
    check "delta from $from has its release URL" pass
  else
    check "delta from $from has its release URL" fail
    echo "         url: $url"
  fi
  if [[ -f "$file" && "$length" == "$(stat -f %z "$file")" ]] && verifies "$file" "$signature"; then
    check "delta from $from has a good signature and length" pass
  else
    check "delta from $from has a good signature and length" fail
  fi
done

# The deltas themselves: applying one to its old build gives the new build.
patched="$workdir/patched.app"
case_dir="$workdir/published/0.1.10"
if "$sparkle/bin/BinaryDelta" apply "$case_dir/Clair.app" "$patched" "$workdir/out/Clair-13-14.delta" >/dev/null 2>&1 \
    && codesign --verify --deep --strict "$patched" 2>/dev/null \
    && diff -r "$patched" "$new/Clair.app" >/dev/null; then
  check "a delta applies, and its result passes codesign and matches the new app" pass
else
  check "a delta applies, and its result passes codesign and matches the new app" fail
fi

attaches="$(grep -c '^attach' "$workdir/hdiutil.log")"
detaches="$(grep -c '^detach' "$workdir/hdiutil.log")"
if [[ "$attaches" == 3 && "$detaches" == 3 ]]; then
  check "detaches every DMG it mounts" pass
else
  check "detaches every DMG it mounts" fail
fi
if ! grep -qF "$private_key" <<<"$output$(cat "$workdir/stderr" "$workdir/gh.log" "$workdir/hdiutil.log")"; then
  check "the private key appears in no output" pass
else
  check "the private key appears in no output" fail
fi

# --- no previous release, or fewer than three ----------------------------------------
printf '%s\n' chromium-engine-0123456789abcdef >"$workdir/tags"
if run && [[ "$(grep -c '^delta=' <<<"$output")" == 0 && "$output" == *dmg_signature=* && ! -e "$workdir/out/Clair-13-14.delta" ]]; then
  check "the first release signs its DMG and makes no deltas" pass
else
  check "the first release signs its DMG and makes no deltas" fail
fi
: >"$workdir/tags"
if run && [[ "$(grep -c '^delta=' <<<"$output")" == 0 ]]; then
  check "a repository with no releases at all makes no deltas" pass
else
  check "a repository with no releases at all makes no deltas" fail
  sed 's/^/         /' "$workdir/stderr"
fi
printf '%s\n' v0.1.9 >"$workdir/tags"
if run && [[ "$(grep -c '^delta=' <<<"$output")" == 1 ]]; then
  check "a single previous release makes one delta" pass
else
  check "a single previous release makes one delta" fail
fi

# --- refusals ---------------------------------------------------------------------
GH_FAILS=1 expect_failure "stops when it can't list releases" "couldn't list the releases"
printf '%s\n' v0.0.1 >"$workdir/tags"
expect_failure "stops when a release has no DMG" "couldn't download Clair-0.0.1-arm64.dmg"
detaches="$(grep -c '^detach' "$workdir/hdiutil.log")"
if [[ "$detaches" == 0 ]]; then
  check "mounts nothing when the download fails" pass
else
  check "mounts nothing when the download fails" fail
fi

publish 0.1.5 14
printf '%s\n' v0.1.5 >"$workdir/tags"
expect_failure "refuses an old build that isn't lower than the new one" "isn't lower than the new build"
if grep -q '^detach' "$workdir/hdiutil.log"; then
  check "detaches when it stops mid-way" pass
else
  check "detaches when it stops mid-way" fail
fi

publish 0.1.6 12
tampered="$workdir/published/0.1.6"
echo tampered >>"$tampered/Clair.app/Contents/Resources/data.txt"
tar -cf "$store/v0.1.6/Clair-0.1.6-arm64.dmg" -C "$tampered" Clair.app
printf '%s\n' v0.1.6 >"$workdir/tags"
expect_failure "refuses an old app that doesn't pass codesign" "doesn't pass codesign"

no_key_output="$(env -u SPARKLE_ED_PRIVATE_KEY PATH="$stubs:$PATH" "$script" --sparkle "$sparkle" --app "$new/Clair.app" \
  --dmg "$workdir/new.dmg" --version 0.2.0 --build 14 --out "$workdir/out" 2>&1)"
if [[ $? -ne 0 && "$no_key_output" == *"SPARKLE_ED_PRIVATE_KEY is not set"* ]]; then
  check "refuses to run without the private key" pass
else
  check "refuses to run without the private key" fail
fi
KEY=not-a-key expect_failure "stops when the key can't sign" "couldn't sign"
expect_failure "rejects a version that isn't X.Y.Z" "must be X.Y.Z" --version '0.2;x'
expect_failure "rejects a build that isn't a positive integer" "positive integer" --build 0
expect_failure "rejects a repository name that isn't one" "not a repository" --repo 'a b/c'
expect_failure "rejects a missing app" "no app at" --app "$workdir/none.app"
expect_failure "rejects a missing DMG" "no DMG at" --dmg "$workdir/none.dmg"

echo
if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
