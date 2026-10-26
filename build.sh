#!/usr/bin/env bash
# Build Clair for Apple Silicon macOS from the pinned ungoogled-chromium release.
#
# Adapted from ungoogled-chromium-macos's build.sh (BSD-3-Clause), see CREDITS.md.
# The same stages run locally and in GitHub Actions, so CI can resume a build
# that is split across several jobs.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./build.sh [-d] [-s SDK_PATH] [-t SECONDS] [STAGE...]

Stages (run in the order given; default: all):
  fetch      Retrieve the Chromium source into build/src
  prepare    Prune binaries, apply all patches, apply domain substitution and
             unpack platform toolchains. "fetch prepare" is the patch-only mode.
  configure  Write args.gn, bootstrap GN, build bindgen and run gn gen
  compile    Run ninja for Clair. With -t, stop after SECONDS and record
             build/compile_status as "running" so a later run can resume.
  all        fetch prepare configure compile

Options:
  -d           Use the Chromium source archive instead of cloning
  -s SDK_PATH  Use this macOS SDK instead of the Xcode default
  -t SECONDS   Time limit for the compile stage
  -h           Show this help
EOF
}

_root_dir="$(cd "$(dirname "$0")" && pwd -P)"
_src_dir="$_root_dir/build/src"
_out_dir="$_src_dir/out/Default"
_main_repo="$_root_dir/ungoogled-chromium"
_status_file="$_root_dir/build/compile_status"
_prepared_stamp="$_src_dir/.clair_prepared"

_clone=true
_sdk_path=""
_time_limit=""
while getopts ':ds:t:h' option; do
  case "$option" in
    d) _clone=false ;;
    s)
      if [[ ! -d "$OPTARG" || ! -f "$OPTARG/SDKSettings.json" ]]; then
        echo "Invalid macOS SDK directory: $OPTARG" >&2
        exit 1
      fi
      _sdk_path="$(cd "$OPTARG" && pwd -P)"
      ;;
    t) _time_limit="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac
done
shift "$((OPTIND - 1))"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "Clair builds only on Apple Silicon (arm64) Macs." >&2
  exit 1
fi

if [[ -n "$_sdk_path" ]]; then
  # build_bindgen.py asks xcrun for the SDK; SDKROOT controls that selection.
  export SDKROOT="$_sdk_path"
fi

_timeout_bin="$(command -v gtimeout || command -v timeout || true)"

stage_fetch() {
  rm -f "$_status_file"
  mkdir -p "$_root_dir/build/download_cache"
  if $_clone; then
    # Reuses an existing clone only when it is unmodified, so a patched tree is
    # always replaced by clean source.
    "$_root_dir/retrieve_and_unpack_resource.py" -g arm64
  else
    # Unpacking over a patched tree would leave patch leftovers behind.
    rm -rf "$_src_dir"
    "$_root_dir/retrieve_and_unpack_resource.py" -d -g arm64
  fi
}

stage_prepare() {
  if [[ -e "$_prepared_stamp" ]]; then
    echo "build/src is already patched. Run the fetch stage again to start from clean source." >&2
    exit 1
  fi
  rm -rf "$_src_dir/out"
  mkdir -p "$_out_dir"

  python3 "$_main_repo/utils/prune_binaries.py" "$_src_dir" "$_main_repo/pruning.list"
  # Applies ungoogled-chromium's series, then Clair's patches/series. Stops at
  # the first patch that does not apply and names it.
  python3 "$_main_repo/utils/patches.py" apply "$_src_dir" "$_main_repo/patches" "$_root_dir/patches"
  python3 "$_main_repo/utils/domain_substitution.py" apply \
    -r "$_main_repo/domain_regex.list" \
    -f "$_main_repo/domain_substitution.list" \
    "$_src_dir"

  mkdir -p "$_src_dir/third_party/llvm-build/Release+Asserts"
  mkdir -p "$_src_dir/third_party/rust-toolchain/bin"
  "$_root_dir/retrieve_and_unpack_resource.py" -p arm64

  touch "$_prepared_stamp"
}

stage_configure() {
  mkdir -p "$_out_dir"
  {
    cat "$_main_repo/flags.gn" "$_root_dir/flags.macos.gn"
    echo 'target_cpu = "arm64"'
  } > "$_out_dir/args.gn"

  if [[ -n "$_sdk_path" ]]; then
    # Chromium's sdk_inputs action requires its SDK path inside root_build_dir.
    mkdir -p "$_out_dir/sdk"
    ln -sfn "$_sdk_path" "$_out_dir/sdk/selected_macos_sdk"
    echo 'mac_sdk_path = "//out/Default/sdk/selected_macos_sdk"' >> "$_out_dir/args.gn"
  fi

  cd "$_src_dir"

  # Use Homebrew's esbuild in place of the prebuilt binary removed by pruning.
  local esbuild_version esbuild_module
  esbuild_version="$(esbuild --version)"
  esbuild_module="$_root_dir/build/esbuild-node/node_modules/esbuild"
  if [[ ! -f "$esbuild_module/package.json" ]] ||
      [[ "$(node -p 'require(process.argv[1]).version' "$esbuild_module/package.json")" != "$esbuild_version" ]]; then
    npm install --prefix "$_root_dir/build/esbuild-node" --no-save --package-lock=false \
      --no-bin-links --ignore-scripts --omit=optional --no-audit --no-fund "esbuild@$esbuild_version"
  fi
  rm -rf third_party/devtools-frontend/src/node_modules/esbuild
  ln -s "$esbuild_module" third_party/devtools-frontend/src/node_modules/esbuild

  ./tools/gn/bootstrap/bootstrap.py -o out/Default/gn --skip-generate-buildfiles
  ./tools/rust/build_bindgen.py --skip-test
  ./out/Default/gn gen out/Default --fail-on-unused-args
}

stage_compile() {
  cd "$_src_dir"
  echo running > "$_status_file"

  if [[ -z "$_time_limit" ]]; then
    ninja -C out/Default chrome chromedriver
  else
    if [[ -z "$_timeout_bin" ]]; then
      echo "-t needs GNU timeout (brew install coreutils)." >&2
      exit 1
    fi
    local code=0
    "$_timeout_bin" -k 7m -s SIGTERM "${_time_limit}s" ninja -C out/Default chrome chromedriver || code=$?
    if [[ "$code" -eq 124 ]]; then
      echo "Time limit reached; the build can be resumed with the compile stage."
      return 0
    fi
    if [[ "$code" -ne 0 ]]; then
      exit "$code"
    fi
  fi

  echo finished > "$_status_file"
}

if [[ $# -eq 0 ]]; then
  set -- all
fi

for stage in "$@"; do
  case "$stage" in
    fetch) stage_fetch ;;
    prepare) stage_prepare ;;
    configure) stage_configure ;;
    compile) stage_compile ;;
    all) stage_fetch; stage_prepare; stage_configure; stage_compile ;;
    *) echo "Unknown stage: $stage" >&2; usage >&2; exit 1 ;;
  esac
done
