#!/bin/bash
# Tests for fetch-dmgbuild.sh. Run directly: ./scripts/fetch-dmgbuild.test.sh
# Works offline: a stand-in Python makes the environment and stands in for pip.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fetch="$script_dir/fetch-dmgbuild.sh"
real_requirements="$script_dir/../resources/dmg/requirements.txt"

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

# A stand-in for python3. It reports FAKE_PYTHON_VERSION, makes a "virtual
# environment" holding a copy of itself, and, run from one as "-m pip", logs its
# arguments and provides bin/dmgbuild, or fails half way when FAKE_PIP_FAIL is set.
python="$workdir/python3"
cat >"$python" <<'EOF'
#!/bin/bash
[[ "$1" == -I ]] && shift
case "$1" in
  -c)
    if [[ "$2" == *version_info* ]]; then echo "${FAKE_PYTHON_VERSION-3.13.1}"; fi
    exit 0
    ;;
  -m)
    case "$2" in
      venv)
        [[ -z "${FAKE_VENV_FAIL-}" ]] || exit 1
        mkdir -p "$3/bin"
        cp "$0" "$3/bin/python"
        echo "home = /fake" >"$3/pyvenv.cfg"
        ;;
      pip)
        env="$(cd "$(dirname "$0")/.." && pwd)"
        echo "${*:3}" >>"$FAKE_PIP_LOG"
        echo partial >"$env/bin/partial"
        [[ -z "${FAKE_PIP_FAIL-}" ]] || exit 1
        printf '#!/bin/sh\necho dmgbuild\n' >"$env/bin/dmgbuild"
        chmod +x "$env/bin/dmgbuild"
        ;;
      *) exit 64 ;;
    esac
    ;;
  *) exit 64 ;;
esac
EOF
chmod +x "$python"
export DMGBUILD_PYTHON="$python" FAKE_PIP_LOG="$workdir/pip.log"
: >"$FAKE_PIP_LOG"

requirements="$workdir/requirements.txt"
printf 'dmgbuild==1.0 \\\n    --hash=sha256:%064d\n' 1 >"$requirements"
export DMGBUILD_REQUIREMENTS="$requirements"

output=""
run_fetch() {
  output="$("$fetch" "$@" 2>&1)"
}

pip_calls() {
  wc -l <"$FAKE_PIP_LOG" | tr -d ' '
}

# --- a fresh install --------------------------------------------------------------
dest="$workdir/out/dmgbuild"
if run_fetch "$dest" && [[ "$(tail -1 <<<"$output")" == "$dest/bin/dmgbuild" && -x "$dest/bin/dmgbuild" ]]; then
  check "a fresh install provides bin/dmgbuild and prints its path" pass
else
  check "a fresh install provides bin/dmgbuild and prints its path" fail
  echo "         got: $output"
fi

args="$(tail -1 "$FAKE_PIP_LOG")"
pinned=pass
for flag in "install " "--isolated" "--require-hashes" "--no-deps" "--only-binary :all:" "-r $requirements"; do
  [[ " $args " == *" $flag"* ]] || { pinned=fail; echo "         pip wasn't given $flag: $args"; }
done
check "installs with pip --isolated --require-hashes --no-deps --only-binary :all:" "$pinned"

if [[ "$output" == *"Python 3.13.1"* && -f "$dest/.dmgbuild-requirements" ]]; then
  check "records the requirements and the Python it installed with" pass
else
  check "records the requirements and the Python it installed with" fail
fi

# --- reuse --------------------------------------------------------------------------
echo marker >"$dest/marker"
calls="$(pip_calls)"
if run_fetch "$dest" && [[ "$output" == "$dest/bin/dmgbuild" && -f "$dest/marker" && "$(pip_calls)" == "$calls" ]]; then
  check "reuses an environment installed from the same requirements" pass
else
  check "reuses an environment installed from the same requirements" fail
  echo "         got: $output"
fi

# --- reinstalls ---------------------------------------------------------------------
printf 'dmgbuild==2.0 \\\n    --hash=sha256:%064d\n' 2 >"$requirements"
if run_fetch "$dest" && [[ ! -e "$dest/marker" && -x "$dest/bin/dmgbuild" && "$(pip_calls)" == $((calls + 1)) ]]; then
  check "reinstalls when the requirements change" pass
else
  check "reinstalls when the requirements change" fail
  echo "         got: $output"
fi

echo marker >"$dest/marker"
if FAKE_PYTHON_VERSION=3.14.0 run_fetch "$dest" && [[ ! -e "$dest/marker" && "$output" == *"Python 3.14.0"* ]]; then
  check "reinstalls when the Python changes" pass
else
  check "reinstalls when the Python changes" fail
  echo "         got: $output"
fi

echo marker >"$dest/marker"
rm "$dest/bin/python"
if run_fetch "$dest" && [[ ! -e "$dest/marker" && -x "$dest/bin/python" ]]; then
  check "reinstalls when the environment's interpreter is gone" pass
else
  check "reinstalls when the environment's interpreter is gone" fail
  echo "         got: $output"
fi

# --- Python versions ----------------------------------------------------------------
for version in 3.9.6 2.7.18; do
  dest="$workdir/old-$version/dmgbuild"
  if ! FAKE_PYTHON_VERSION="$version" run_fetch "$dest" && [[ "$output" == *"needs 3.10 or later"* && ! -e "$dest" ]]; then
    check "refuses Python $version, installing nothing" pass
  else
    check "refuses Python $version, installing nothing" fail
    echo "         got: $output"
  fi
done

dest="$workdir/new/dmgbuild"
if FAKE_PYTHON_VERSION=3.10.0 run_fetch "$dest"; then
  check "accepts Python 3.10" pass
else
  check "accepts Python 3.10" fail
  echo "         got: $output"
fi

if ! FAKE_PYTHON_VERSION=banana run_fetch "$workdir/odd/dmgbuild" && [[ "$output" == *"unexpected version"* ]]; then
  check "refuses a Python that reports an odd version" pass
else
  check "refuses a Python that reports an odd version" fail
fi

if ! DMGBUILD_PYTHON="$workdir/no-python" run_fetch "$workdir/none/dmgbuild" && [[ "$output" == *"needs Python 3.10"* ]]; then
  check "refuses to run without a Python" pass
else
  check "refuses to run without a Python" fail
  echo "         got: $output"
fi

# --- failures -----------------------------------------------------------------------
dest="$workdir/failed/dmgbuild"
if ! FAKE_PIP_FAIL=1 run_fetch "$dest" && [[ "$output" == *"couldn't install"* && ! -e "$dest" ]]; then
  check "a failed install leaves no environment behind" pass
else
  check "a failed install leaves no environment behind" fail
  echo "         got: $output"
fi

dest="$workdir/replaced/dmgbuild"
run_fetch "$dest"
printf 'dmgbuild==3.0 \\\n    --hash=sha256:%064d\n' 3 >"$requirements"
if ! FAKE_PIP_FAIL=1 run_fetch "$dest" && [[ ! -e "$dest" ]]; then
  check "a failed reinstall leaves no environment behind" pass
else
  check "a failed reinstall leaves no environment behind" fail
  echo "         got: $output"
fi

dest="$workdir/no-venv/dmgbuild"
if ! FAKE_VENV_FAIL=1 run_fetch "$dest" && [[ "$output" == *"virtual environment"* && ! -e "$dest" ]]; then
  check "a failure to make the environment leaves nothing behind" pass
else
  check "a failure to make the environment leaves nothing behind" fail
  echo "         got: $output"
fi

# --- inputs -------------------------------------------------------------------------
if ! "$fetch" >/dev/null 2>&1 && ! "$fetch" a b >/dev/null 2>&1; then
  check "requires exactly one destination" pass
else
  check "requires exactly one destination" fail
fi

touch "$workdir/a-file"
if ! run_fetch "$workdir/a-file" && [[ "$output" == *"not a directory"* && -f "$workdir/a-file" ]]; then
  check "refuses a destination that is a file" pass
else
  check "refuses a destination that is a file" fail
fi

mkdir "$workdir/precious"
echo keep >"$workdir/precious/notes.txt"
if ! run_fetch "$workdir/precious" && [[ "$output" == *"other than a virtual environment"* && -f "$workdir/precious/notes.txt" ]]; then
  check "refuses to replace a directory that isn't an environment" pass
else
  check "refuses to replace a directory that isn't an environment" fail
  echo "         got: $output"
fi

if ! DMGBUILD_REQUIREMENTS="$workdir/none.txt" run_fetch "$workdir/no-req/dmgbuild" && [[ "$output" == *"no requirements file"* ]]; then
  check "refuses a missing requirements file" pass
else
  check "refuses a missing requirements file" fail
fi

# --- the real requirements ------------------------------------------------------------
# Every requirement is pinned to one version and a wheel's sha256, and the list
# holds dmgbuild's dependencies too, since pip resolves none.
pins="$(sed -n 's/^\([A-Za-z0-9_.-]*\)==\([0-9][0-9.]*\) *\\$/\1/p' "$real_requirements" | sort | tr '\n' ' ')"
hashes="$(grep -cE '^ +--hash=sha256:[0-9a-f]{64}$' "$real_requirements")"
requirements_lines="$(grep -cvE '^(#|$| +--hash=)' "$real_requirements")"
if [[ "$pins" == "dmgbuild ds_store mac_alias " && "$hashes" == 3 && "$requirements_lines" == 3 ]]; then
  check "requirements.txt pins dmgbuild, ds_store and mac_alias, each with a sha256" pass
else
  check "requirements.txt pins dmgbuild, ds_store and mac_alias, each with a sha256" fail
  echo "         pins: $pins; hashes: $hashes; requirement lines: $requirements_lines"
fi

echo
if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
