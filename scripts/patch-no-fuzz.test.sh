#!/bin/bash
# Tests for patch-no-fuzz.sh. Run directly: ./scripts/patch-no-fuzz.test.sh
#
# Uses a stand-in source file and stand-in patches.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
strict="$script_dir/patch-no-fuzz.sh"

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

# A hunk adding "new" after line c, with "$1", "$2" and "$3" as its context
# before the addition.
write_patch() {
  cat >"$workdir/test.patch" <<PATCH
--- a/f.txt
+++ b/f.txt
@@ -1,6 +1,7 @@
 $1
 $2
 $3
+new
 d
 e
 f
PATCH
}

# Applies the patch the way ungoogled-chromium's patches.py does.
apply() {
  rm -rf "$workdir/tree"
  mkdir "$workdir/tree"
  printf 'a\nb\nc\nd\ne\nf\n' >"$workdir/tree/f.txt"
  "$strict" -p1 --ignore-whitespace -i "$workdir/test.patch" -d "$workdir/tree" \
    --no-backup-if-mismatch --forward >/dev/null 2>&1
}

# patches.py checks that its patch tool runs before using it.
if "$strict" --version >/dev/null 2>&1; then r=pass; else r=fail; fi
check "answers --version" "$r"

write_patch a b c
if apply && grep -qx new "$workdir/tree/f.txt"; then r=pass; else r=fail; fi
check "a patch with exact context applies" "$r"

write_patch CHANGED b c
if apply; then r=fail; else r=pass; fi
check "a changed outermost context line fails" "$r"

write_patch a CHANGED c
if apply; then r=fail; else r=pass; fi
check "a changed middle context line fails" "$r"

write_patch a b CHANGED
if apply; then r=fail; else r=pass; fi
check "a changed context line next to the edit fails" "$r"

echo
if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
