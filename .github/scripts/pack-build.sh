#!/usr/bin/env bash
# Pack the build directory into a zstd archive for upload as a workflow
# artifact, so the next job in the chain can resume from it.
#
# Usage: pack-build.sh OUTPUT_DIR
#
# Based on ungoogled-chromium-macos's github_prepare_artifacts.sh
# (BSD-3-Clause), see CREDITS.md.

set -euo pipefail

root_dir="${GITHUB_WORKSPACE:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)}"
output_dir="$1"

mkdir -p "$output_dir"
# Flush the file system so tar never reads half-written ninja state.
sync
tar -C "$root_dir" -c -f - build | zstd -11 -T0 -o "$output_dir/build.tar.zst"
(cd "$output_dir" && shasum -a 256 build.tar.zst > build.tar.zst.sha256)

ls -lh "$output_dir"
df -h /
