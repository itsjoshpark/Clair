#!/bin/bash
# Tests for utils/sync_tree.py, the in-place tree update helper used by
# build.sh. Run directly: ./scripts/sync-tree.test.sh
#
# Needs an APFS volume for the clone tests (any Mac's internal disk).

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sync_tree="$script_dir/../utils/sync_tree.py"

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

reject() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    check "$description" fail
  else
    check "$description" pass
  fi
}

mtime() {
  stat -f '%m' "$1"
}

old_time=202001010000

# --- clone ------------------------------------------------------------------
base="$workdir/base"
mkdir -p "$base/dir" "$base/out/Default"
echo one >"$base/dir/a.cc"
ln -s dir/a.cc "$base/link"
touch -t "$old_time" "$base/dir/a.cc"
python3 "$sync_tree" clone "$base" "$workdir/clone"
if cmp -s "$base/dir/a.cc" "$workdir/clone/dir/a.cc" &&
    [[ "$(readlink "$workdir/clone/link")" == dir/a.cc ]] &&
    [[ "$(mtime "$workdir/clone/dir/a.cc")" == "$(mtime "$base/dir/a.cc")" ]]; then
  check "clone copies contents, symlinks and modification times" pass
else
  check "clone copies contents, symlinks and modification times" fail
fi
reject "clone refuses an existing destination" python3 "$sync_tree" clone "$base" "$workdir/clone"

# --- record -----------------------------------------------------------------
tree="$workdir/tree"
mkdir -p "$tree/dir" "$tree/out/Default" "$tree/patches/clair"
for name in kept changed; do
  echo "$name" >"$tree/dir/$name.cc"
  touch -t "$old_time" "$tree/dir/$name.cc"
done
touch -t "$old_time" "$tree/out/Default/old.o"
cat >"$tree/patches/series" <<'EOF'
# Comment
clair/one.patch
EOF
cat >"$tree/patches/clair/one.patch" <<'EOF'
Header text
--- a/dir/deleted.cc
+++ /dev/null
@@ -1 +0,0 @@
-gone
--- a/dir/patched.cc	2020-01-01 00:00:00
+++ b/dir/patched.cc	2020-01-01 00:00:00
@@ -1 +1 @@
-old
+new
EOF
stamp="$workdir/stamp"
touch -t 202101010000 "$stamp"
echo new >"$tree/dir/changed.cc"
echo new >"$tree/dir/added.cc"
echo new >"$tree/out/Default/new.o"
recorded="$(python3 "$sync_tree" record --stamp "$stamp" --patches "$tree/patches" "$tree" | grep -v '^patches/')"
expected="$(printf '%s\n' dir/added.cc dir/changed.cc dir/deleted.cc dir/patched.cc)"
if [[ "$recorded" == "$expected" ]]; then
  check "record lists newer files and patched paths, not out/" pass
else
  check "record lists newer files and patched paths, not out/ (got: $(echo "$recorded" | tr '\n' ' '))" fail
fi

# --- sync -------------------------------------------------------------------
next="$workdir/next"
dest="$workdir/dest"
mkdir -p "$next/dir" "$dest/dir"
for name in same changed removed unlisted; do
  echo "$name" >"$dest/dir/$name.cc"
  touch -t "$old_time" "$dest/dir/$name.cc"
done
echo same >"$next/dir/same.cc"
echo changed-now >"$next/dir/changed.cc"
echo created >"$next/dir/created.cc"
echo unlisted-now >"$next/dir/unlisted.cc"
ln -s same.cc "$next/dir/link"
list="$workdir/list"
printf '%s\n' dir/same.cc dir/changed.cc dir/removed.cc dir/created.cc dir/link dir/absent.cc >"$list"
summary="$(python3 "$sync_tree" sync "$next" "$dest" "$list")"
old_epoch="$(mtime "$tree/dir/kept.cc")"

if [[ "$(mtime "$dest/dir/same.cc")" == "$old_epoch" ]]; then
  check "sync leaves an identical file's modification time alone" pass
else
  check "sync leaves an identical file's modification time alone" fail
fi
if [[ "$(cat "$dest/dir/changed.cc")" == changed-now && "$(mtime "$dest/dir/changed.cc")" != "$old_epoch" ]]; then
  check "sync copies a changed file with a new modification time" pass
else
  check "sync copies a changed file with a new modification time" fail
fi
if [[ ! -e "$dest/dir/removed.cc" && "$(cat "$dest/dir/created.cc" 2>/dev/null)" == created ]]; then
  check "sync removes and creates files" pass
else
  check "sync removes and creates files" fail
fi
if [[ "$(readlink "$dest/dir/link")" == same.cc ]]; then
  check "sync creates symlinks" pass
else
  check "sync creates symlinks" fail
fi
if [[ "$(cat "$dest/dir/unlisted.cc")" == unlisted ]]; then
  check "sync leaves unlisted files alone" pass
else
  check "sync leaves unlisted files alone" fail
fi
if [[ "$summary" == "sync_tree: 3 copied, 1 removed, 1 unchanged" ]]; then
  check "sync reports what it did" pass
else
  check "sync reports what it did (got: $summary)" fail
fi

printf '%s\n' ../escape >"$workdir/bad-list"
reject "sync rejects a path outside the tree" python3 "$sync_tree" sync "$next" "$dest" "$workdir/bad-list"
mkdir -p "$workdir/outside"
ln -s "$workdir/outside" "$dest/escape"
mkdir -p "$next/escape"
echo x >"$next/escape/file"
printf '%s\n' escape/file >"$workdir/bad-list"
reject "sync refuses to write through a symlink that leaves the tree" python3 "$sync_tree" sync "$next" "$dest" "$workdir/bad-list"
if [[ ! -e "$workdir/outside/file" ]]; then
  check "nothing is written outside the tree" pass
else
  check "nothing is written outside the tree" fail
fi
printf '%s\n' /etc/hosts >"$workdir/bad-list"
reject "sync rejects an absolute path" python3 "$sync_tree" sync "$next" "$dest" "$workdir/bad-list"

echo
if [[ "$failures" -eq 0 ]]; then
  echo "All sync-tree tests passed."
else
  echo "$failures sync-tree test(s) failed."
fi
exit "$failures"
