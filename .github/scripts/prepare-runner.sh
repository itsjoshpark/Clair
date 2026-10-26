#!/usr/bin/env bash
# Prepare a GitHub-hosted macOS arm64 runner for building Clair: free disk
# space, select Xcode and install the build toolchain.
#
# Based on ungoogled-chromium-macos's github_prepare_xcode.sh and
# github_setup_env_toolchain.sh (BSD-3-Clause), see CREDITS.md.

set -euo pipefail
shopt -s extglob nullglob

xcode_version="${CLAIR_XCODE_VERSION:-26.0.1}"
xcode_path="/Applications/Xcode_${xcode_version}.app"

echo "::group::Disk before cleanup"
df -h /
echo "::endgroup::"

sudo mdutil -a -i off >/dev/null || true

if [[ ! -d "$xcode_path" ]]; then
  echo "::error::Xcode $xcode_version is not installed on this runner. Installed versions:"
  ls -d /Applications/Xcode*.app
  exit 1
fi
sudo xcode-select --switch "$xcode_path"
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

xcodebuild -version
xcodebuild -downloadComponent MetalToolchain || true

brew install go ninja coreutils esbuild typescript zstd
pip3 install PySocks httplib2 --break-system-packages

echo "::group::Disk after cleanup"
df -h /
echo "::endgroup::"
