#!/usr/bin/env bash
# Verify and unpack a build archive made by pack-build.sh, then delete the
# archive to free disk space.
#
# Usage: unpack-build.sh ARCHIVE_DIR

set -euo pipefail

root_dir="${GITHUB_WORKSPACE:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)}"
archive_dir="$1"

(cd "$archive_dir" && shasum -a 256 -c build.tar.zst.sha256)
zstd -d -c "$archive_dir/build.tar.zst" | tar -C "$root_dir" -x -f -
rm -f "$archive_dir/build.tar.zst"

df -h /
