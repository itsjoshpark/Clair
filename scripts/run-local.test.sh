#!/bin/bash
# Tests for run-local.sh. Run directly: ./scripts/run-local.test.sh
# Works offline: gh and xcodebuild are stand-ins on PATH, package.sh is
# replaced through CLAIR_RUN_LOCAL_PACKAGE, and the "engine" is a Clair.app
# whose executable records how it was launched.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
run_local="$script_dir/run-local.sh"

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

# --- stand-ins ----------------------------------------------------------------------
bin="$workdir/bin"
releases="$workdir/releases"
gh_log="$workdir/gh.log"
launch_log="$workdir/launch.log"
mkdir -p "$bin" "$releases"

# gh: a release is published when $releases/<tag> exists; downloading copies
# its files.
cat >"$bin/gh" <<'EOF'
#!/bin/bash
echo "$*" >>"$GH_LOG"
[[ "$1 $2" == "release view" || "$1 $2" == "release download" ]] || exit 2
tag="$3"
[[ -d "$RELEASES/$tag" ]] || { echo "release not found" >&2; exit 1; }
if [[ "$2" == view ]]; then
  echo false
  exit 0
fi
shift 3
while (( $# > 0 )); do
  case "$1" in
    --dir) dir="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cp "$RELEASES/$tag"/* "$dir/"
EOF

# xcodebuild: leaves a framework where a Debug build would.
cat >"$bin/xcodebuild" <<'EOF'
#!/bin/bash
while (( $# > 0 )); do
  case "$1" in
    -derivedDataPath) dd="$2"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$dd/Build/Products/Debug/ClairUI.framework"
EOF

# package.sh: copies the engine app into the output directory.
cat >"$bin/package.sh" <<'EOF'
#!/bin/bash
args=()
while (( $# > 0 )); do
  case "$1" in
    --clairui) [[ -d "$2" ]] || exit 1; shift 2 ;;
    --no-dmg) shift ;;
    *) args+=("$1"); shift ;;
  esac
done
[[ ! -e "${args[1]}/Clair.app" ]] || { echo "Clair.app already exists" >&2; exit 1; }
ditto "${args[0]}" "${args[1]}/Clair.app"
EOF
chmod +x "$bin/gh" "$bin/xcodebuild" "$bin/package.sh"

# Publishes a fake engine for KEY. A third argument corrupts its checksum.
publish() {
  local key="$1" corrupt="${2-}"
  local dir="$releases/chromium-engine-$key" app="$workdir/engine-src/Clair.app"
  local zip="Clair-Chromium-Engine-$key-arm64.zip"
  rm -rf "$workdir/engine-src"
  mkdir -p "$app/Contents/MacOS" "$dir"
  cat >"$app/Contents/MacOS/Clair" <<EOF
#!/bin/bash
{
  echo "engine=$key"
  echo "dumps=\$BREAKPAD_DUMP_LOCATION"
  for arg in "\$@"; do echo "arg=\$arg"; done
} >"$launch_log"
for arg in "\$@"; do
  case "\$arg" in
    --user-data-dir=*) [[ -d "\${arg#*=}" ]] && echo "profile-existed=yes" >>"$launch_log" ;;
  esac
done
exit "\${FAKE_CLAIR_STATUS:-0}"
EOF
  chmod +x "$app/Contents/MacOS/Clair"
  ditto -c -k --keepParent "$app" "$dir/$zip"
  (cd "$dir" && shasum -a 256 "$zip" >"$zip.sha256")
  if [[ -n "$corrupt" ]]; then
    printf 'x' >>"$dir/$zip"
  fi
}

home="$workdir/home"
mkdir -p "$home/Library/Application Support/Clair"
work="$workdir/work"

output=""
status=0
# Runs run-local.sh for KEY with the remaining arguments.
run() {
  local key="$1"; shift
  : >"$gh_log"
  rm -f "$launch_log"
  status=0
  output="$(HOME="$home" PATH="$bin:$PATH" GH_LOG="$gh_log" RELEASES="$releases" \
    CLAIR_RUN_LOCAL_ENGINE_KEY="$key" CLAIR_RUN_LOCAL_PACKAGE="$bin/package.sh" \
    "$run_local" --work "$work" "$@" 2>&1)" || status=$?
}

launched_arg() {
  grep -qxF "arg=$1" "$launch_log" 2>/dev/null
}

profile_arg() {
  sed -n 's/^arg=--user-data-dir=//p' "$launch_log" 2>/dev/null
}

key_a=aaaaaaaaaaaaaaaa
key_b=bbbbbbbbbbbbbbbb

# --- no published engine ------------------------------------------------------------
run "$key_a"
if (( status != 0 )) && [[ "$output" == *"gh workflow run engine.yml -f ref="* && ! -e "$launch_log" ]]; then
  check "a key with no published engine fails and prints the engine.yml command" pass
else
  check "a key with no published engine fails and prints the engine.yml command" fail
  echo "         got ($status): $output"
fi
if [[ ! -e "$work/engines/$key_a" ]] && ! grep -q "release download" "$gh_log"; then
  check "and downloads nothing" pass
else
  check "and downloads nothing" fail
fi

# --- first run ------------------------------------------------------------------------
publish "$key_a"
run "$key_a" -- --enable-logging=stderr https://example.com/
if (( status == 0 )) && grep -q "release download chromium-engine-$key_a" "$gh_log" &&
    grep -qx "engine=$key_a" "$launch_log" 2>/dev/null; then
  check "downloads the engine for the key, packages it and launches it" pass
else
  check "downloads the engine for the key, packages it and launches it" fail
  echo "         got ($status): $output"
fi

if launched_arg --use-mock-keychain && launched_arg --enable-logging=stderr && launched_arg https://example.com/; then
  check "launches with the mock keychain and passes extra arguments through" pass
else
  check "launches with the mock keychain and passes extra arguments through" fail
fi

profile="$(profile_arg)"
if [[ "$profile" == "$work/profiles/"* ]] && grep -qx "profile-existed=yes" "$launch_log"; then
  check "launches with a throwaway profile under the work directory" pass
else
  check "launches with a throwaway profile under the work directory" fail
  echo "         profile: $profile"
fi
case "$profile/" in
  "$home/Library/Application Support/Clair/"*) check "the throwaway profile is outside ~/Library/Application Support/Clair" fail ;;
  *) check "the throwaway profile is outside ~/Library/Application Support/Clair" pass ;;
esac
if [[ -n "$profile" && ! -e "$profile" ]]; then
  check "deletes the throwaway profile when Clair quits" pass
else
  check "deletes the throwaway profile when Clair quits" fail
fi
if grep -qxF "dumps=$profile/Crashpad" "$launch_log"; then
  check "keeps Crashpad's dumps in the profile" pass
else
  check "keeps Crashpad's dumps in the profile" fail
fi
if [[ -z "$(ls -A "$home/Library/Application Support/Clair")" ]]; then
  check "leaves ~/Library/Application Support/Clair alone" pass
else
  check "leaves ~/Library/Application Support/Clair alone" fail
fi

# --- cache hit ------------------------------------------------------------------------
run "$key_a"
if (( status == 0 )) && [[ ! -s "$gh_log" ]] && grep -qx "engine=$key_a" "$launch_log" 2>/dev/null; then
  check "a cached engine is reused without calling gh" pass
else
  check "a cached engine is reused without calling gh" fail
  echo "         gh calls: $(cat "$gh_log")"
fi

# --- changed key ------------------------------------------------------------------------
publish "$key_b"
run "$key_b"
if (( status == 0 )) && grep -q "release download chromium-engine-$key_b" "$gh_log" &&
    grep -qx "engine=$key_b" "$launch_log" 2>/dev/null; then
  check "a changed key downloads and launches that key's engine" pass
else
  check "a changed key downloads and launches that key's engine" fail
  echo "         got ($status): $output"
fi
if [[ -d "$work/engines/$key_a/Clair.app" ]]; then
  check "keeps the previous key's engine cached" pass
else
  check "keeps the previous key's engine cached" fail
fi

# --- checksum ---------------------------------------------------------------------------
key_c=cccccccccccccccc
publish "$key_c" corrupt
run "$key_c"
if (( status != 0 )) && [[ "$output" == *"SHA-256"* && ! -e "$work/engines/$key_c" && ! -e "$launch_log" ]]; then
  check "refuses an engine that fails its SHA-256 check, and caches nothing" pass
else
  check "refuses an engine that fails its SHA-256 check, and caches nothing" fail
  echo "         got ($status): $output"
fi
if [[ -z "$(find "$work/engines" -name '.download.*')" ]]; then
  check "cleans up a failed download" pass
else
  check "cleans up a failed download" fail
fi

# --- pruning ----------------------------------------------------------------------------
publish "$key_c"
key_d=dddddddddddddddd
publish "$key_d"
run "$key_c"
sleep 1
run "$key_d"
if [[ ! -e "$work/engines/$key_a" && -d "$work/engines/$key_b" && -d "$work/engines/$key_c" && -d "$work/engines/$key_d" ]]; then
  check "keeps only the three most recently used engines" pass
else
  check "keeps only the three most recently used engines" fail
  ls "$work/engines"
fi

# --- profiles -----------------------------------------------------------------------------
run "$key_d" --profile "$home/Library/Application Support/Clair"
if (( status != 0 )) && [[ "$output" == *"your own Clair data"* && ! -e "$launch_log" ]]; then
  check "refuses Clair's own data folder as the profile" pass
else
  check "refuses Clair's own data folder as the profile" fail
  echo "         got ($status): $output"
fi

run "$key_d" --profile "$home/Library/Application Support/Clair/Default"
if (( status != 0 )) && [[ ! -e "$launch_log" ]]; then
  check "refuses a profile inside Clair's own data folder" pass
else
  check "refuses a profile inside Clair's own data folder" fail
fi

ln -s "$home/Library/Application Support" "$workdir/support-link"
run "$key_d" --profile "$workdir/support-link/Clair/../Clair/Profile 1"
if (( status != 0 )) && [[ ! -e "$launch_log" ]]; then
  check "refuses a profile that reaches Clair's data folder through a symlink or .." pass
else
  check "refuses a profile that reaches Clair's data folder through a symlink or .." fail
fi

kept="$workdir/kept-profile"
mkdir -p "$kept"
echo data >"$kept/marker"
run "$key_d" --profile "$kept"
if (( status == 0 )) && [[ "$(profile_arg)" == "$kept" && -f "$kept/marker" ]]; then
  check "uses and keeps a profile given with --profile" pass
else
  check "uses and keeps a profile given with --profile" fail
  echo "         got ($status): $output"
fi

run "$key_d" --profile "$workdir/ClairCopy"
if (( status == 0 )) && [[ "$(profile_arg)" == "$workdir/ClairCopy" ]]; then
  check "accepts a profile whose name only starts like Clair's data folder" pass
else
  check "accepts a profile whose name only starts like Clair's data folder" fail
fi

# --- the rest -------------------------------------------------------------------------------
run "$key_d" --no-launch
if (( status == 0 )) && [[ "$output" == *"$work/app/Clair.app" && ! -e "$launch_log" ]] &&
    [[ -z "$(ls -A "$work/profiles")" ]]; then
  check "--no-launch packages and prints the app without launching or making a profile" pass
else
  check "--no-launch packages and prints the app without launching or making a profile" fail
  echo "         profiles left: $(ls -A "$work/profiles" | tr '\n' ' ')"
  echo "         got ($status): $output"
fi

status=0
HOME="$home" PATH="$bin:$PATH" GH_LOG="$gh_log" RELEASES="$releases" FAKE_CLAIR_STATUS=3 \
  CLAIR_RUN_LOCAL_ENGINE_KEY="$key_d" CLAIR_RUN_LOCAL_PACKAGE="$bin/package.sh" \
  "$run_local" --work "$work" >/dev/null 2>&1 || status=$?
if (( status == 3 )); then
  check "exits with Clair's exit status" pass
else
  check "exits with Clair's exit status" fail
  echo "         got: $status"
fi

run "$key_d" https://example.com/
if (( status != 0 )) && [[ "$output" == *"after --"* ]]; then
  check "rejects Chromium arguments given before --" pass
else
  check "rejects Chromium arguments given before --" fail
fi

run "not-a-key"
if (( status != 0 )) && [[ "$output" == *"16 hex digits"* ]]; then
  check "rejects a malformed engine key" pass
else
  check "rejects a malformed engine key" fail
fi

echo
if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
