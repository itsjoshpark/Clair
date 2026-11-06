#!/bin/bash
# Provides dmgbuild, for package.sh's DMG, in a virtual environment installed
# from resources/dmg/requirements.txt (style-release-dmg design D2): hash-pinned
# wheels only, with no dependency resolution.
#
#   fetch-dmgbuild.sh <dest-dir>
#
# <dest-dir> ends up holding the environment, and its bin/python can import
# dmgbuild, ds_store and mac_alias. An environment installed from the same
# requirements and Python is reused. Any other is replaced, and a failed install
# leaves none. Prints the path to <dest-dir>/bin/dmgbuild.
#
# The environment is made with python3 from PATH, or DMGBUILD_PYTHON when it is
# set, which must be Python 3.10 or later.
#
# For tests only: DMGBUILD_REQUIREMENTS names another requirements file.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

die() {
  echo "fetch-dmgbuild: $1" >&2
  exit 1
}

[[ $# -eq 1 && -n "$1" ]] || die "usage: fetch-dmgbuild.sh <dest-dir>"
dest="${1%/}"
requirements="${DMGBUILD_REQUIREMENTS-$root/resources/dmg/requirements.txt}"
python="${DMGBUILD_PYTHON-python3}"

[[ -f "$requirements" ]] || die "no requirements file at $requirements"
command -v "$python" >/dev/null || die "no $python; dmgbuild needs Python 3.10 or later"
python_version="$("$python" -I -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null)" ||
  die "$python doesn't run"
[[ "$python_version" =~ ^([0-9]+)\.([0-9]+)\.[0-9]+$ ]] || die "$python reports an unexpected version: $python_version"
major="${BASH_REMATCH[1]}" minor="${BASH_REMATCH[2]}"
if (( major < 3 || (major == 3 && minor < 10) )); then
  die "$python is Python $python_version; dmgbuild needs 3.10 or later (set DMGBUILD_PYTHON)"
fi

stamp_file="$dest/.dmgbuild-requirements"
stamp="$(printf 'Python %s\n' "$python_version"; cat "$requirements")"

# Reuse only an environment whose interpreter still runs: a Homebrew upgrade
# removes the Python it was made from.
if [[ -f "$stamp_file" && "$(cat "$stamp_file")" == "$stamp" && -x "$dest/bin/dmgbuild" ]] &&
    "$dest/bin/python" -I -c '' 2>/dev/null; then
  echo "$dest/bin/dmgbuild"
  exit 0
fi
[[ ! -e "$dest" || -d "$dest" ]] || die "not a directory: $dest"
# It replaces only an environment, never a directory that happens to be named.
if [[ -d "$dest" && ! -f "$dest/pyvenv.cfg" && -n "$(ls -A "$dest")" ]]; then
  die "$dest holds something other than a virtual environment"
fi

# A virtual environment can't be moved once made, so it's made in place, and
# removed again if anything fails before it's stamped.
rm -rf "$dest"
mkdir -p "$(dirname "$dest")"
trap 'rm -rf "$dest"' EXIT

echo "fetch-dmgbuild: installing dmgbuild into $dest with Python $python_version" >&2
"$python" -I -m venv "$dest" >&2 || die "couldn't make a virtual environment in $dest"
# --isolated ignores pip's configuration and environment variables, so nothing
# on the machine can change the index or loosen the checks.
"$dest/bin/python" -I -m pip install --isolated --disable-pip-version-check --no-input \
  --require-hashes --no-deps --only-binary :all: -r "$requirements" >&2 ||
  die "couldn't install the wheels in $requirements"
[[ -x "$dest/bin/dmgbuild" ]] || die "the install provided no bin/dmgbuild"

printf '%s\n' "$stamp" >"$stamp_file"
trap - EXIT
echo "$dest/bin/dmgbuild"
