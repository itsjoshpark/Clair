#!/usr/bin/env bash
# Prepare a GitHub-hosted xcode-27 runner for the patch check: free disk space,
# select Xcode and install the tools that fetching and patching need. Never run
# it on the self-hosted Mac: it deletes Xcode versions and simulators.
#
# Based on ungoogled-chromium-macos's github_prepare_xcode.sh and
# github_setup_env_toolchain.sh (BSD-3-Clause), see CREDITS.md.

set -euo pipefail
shopt -s extglob nullglob

echo "::group::Disk before cleanup"
df -h /
echo "::endgroup::"

sudo mdutil -a -i off >/dev/null || true

# The patch check compiles no Chromium, but prepare compiles the app icon with
# actool, which needs Xcode 26 or later. Hosted jobs use the xcode-27 image.
xcode_path="$("$(dirname "$0")/select-xcode.sh")"
# Remove every other Xcode and all simulators; they take tens of GB.
for other in /Applications/Xcode_*.app; do
  if [[ "$other" != "$xcode_path" && ! -L "$other" ]]; then
    sudo rm -rf "$other"
  fi
done
xcrun simctl delete all || true
sudo rm -rf ~/Library/Developer/CoreSimulator /Library/Developer/CoreSimulator/Profiles/Runtimes || true
if [[ -n "${ANDROID_HOME:-}" ]]; then
  sudo rm -rf "$ANDROID_HOME"
fi
sudo rm -rf ~/.dotnet /usr/local/share/dotnet ~/.ghcup /Users/runner/hostedtoolcache/CodeQL || true

brew install go ninja coreutils esbuild typescript zstd
pip3 install PySocks httplib2 --break-system-packages

echo "::group::Disk after cleanup"
df -h /
echo "::endgroup::"
