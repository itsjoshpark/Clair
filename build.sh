#!/usr/bin/env bash
# Build Clair for Apple Silicon macOS from the pinned ungoogled-chromium release.
#
# Adapted from ungoogled-chromium-macos's build.sh (BSD-3-Clause), see CREDITS.md.
# The same stages run locally and in GitHub Actions, so CI can resume a build
# that is split across several jobs.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./build.sh [-d] [-k] [-j JOBS] [-s SDK_PATH] [-t SECONDS] [STAGE...]

Stages (run in the order given; default: all):
  fetch      Retrieve the Chromium source into build/src
  prepare    Prune binaries, apply all patches, rebrand UI strings, replace
             the icon and logos, apply domain substitution and unpack platform
             toolchains. "fetch prepare" is the patch-only mode.
  update     Bring a tree prepared with -k up to date with Clair's patches
             in place, so ninja rebuilds only what changed. Falls back to
             "fetch prepare" when the tree can't be updated in place.
  configure  Write args.gn, bootstrap GN, build bindgen and run gn gen
  compile    Run ninja for Clair. With -t, stop after SECONDS and record
             build/compile_status as "running" so a later run can resume.
  all        fetch prepare configure compile

Options:
  -d           Use the Chromium source archive instead of cloning
  -k           Keep a clone of the tree from before Clair's patches in
               build/base, so a later "update" can work in place (APFS only)
  -j JOBS      Run at most JOBS ninja jobs in parallel during compile
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
# In-place updates (D11): build/base is an APFS clone of build/src from before
# Clair's patches, base_key names the inputs it was made from, and layer_files
# lists the files Clair's patches and substitutions touched in build/src.
_base_dir="$_root_dir/build/base"
_next_dir="$_root_dir/build/next"
_base_key_file="$_root_dir/build/base_key"
_layer_file="$_root_dir/build/layer_files"
_layer_stamp="$_root_dir/build/layer_stamp"
_updating_file="$_root_dir/build/updating"
_sync_tree="$_root_dir/utils/sync_tree.py"
# Bump when the steps that make the base change (pruning, ungoogled-chromium's
# patches, the toolchains), so existing bases are replaced.
_base_format=1

_clone=true
_keep_base=false
_sdk_path=""
_time_limit=""
_ninja_jobs=()
while getopts ':dkj:s:t:h' option; do
  case "$option" in
    d) _clone=false ;;
    k) _keep_base=true ;;
    j)
      if [[ ! "$OPTARG" =~ ^[1-9][0-9]*$ ]]; then
        echo "Invalid job count: $OPTARG" >&2
        exit 1
      fi
      _ninja_jobs=(-j "$OPTARG")
      ;;
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

# The key of the inputs that make the base: everything before Clair's patches.
base_key() {
  {
    echo "format $_base_format"
    echo "clone $_clone"
    echo "ungoogled-chromium $(git -C "$_main_repo" rev-parse HEAD)"
    cd "$_root_dir" && shasum -a 256 downloads*.ini retrieve_and_unpack_resource.py
  } | shasum -a 256 | cut -c 1-16
}

clear_base() {
  rm -rf "$_base_dir" "$_next_dir"
  rm -f "$_base_key_file" "$_layer_file" "$_layer_stamp" "$_updating_file"
}

# Clair's layer: its patch series, UI string rebranding, the icon and logos,
# and domain substitution, applied to the tree in $1.
apply_layer() {
  local tree="$1"
  python3 "$_main_repo/utils/patches.py" apply "$tree" "$_root_dir/patches"
  # Rebrand Chrome/Chromium as Clair in UI strings and their translations.
  python3 "$_root_dir/utils/name_substitution.py" --sub -t "$tree"
  # Replace Chromium's app icon and product logos with Clair's. Fails and names
  # the path if a destination no longer exists in this Chromium version.
  "$_root_dir/scripts/replace-icon-resources.sh" "$tree"
  python3 "$_main_repo/utils/domain_substitution.py" apply \
    -r "$_main_repo/domain_regex.list" \
    -f "$_main_repo/domain_substitution.list" \
    "$tree"
}

# Marks the time before a layer is applied, so record_layer can find the files
# it touched.
stamp_layer() {
  touch "$_layer_stamp"
  sleep 1
}

record_layer() {
  python3 "$_sync_tree" record --stamp "$_layer_stamp" --patches "$_root_dir/patches" "$1"
}

stage_fetch() {
  rm -f "$_status_file"
  clear_base
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

  clear_base

  python3 "$_main_repo/utils/prune_binaries.py" "$_src_dir" "$_main_repo/pruning.list"
  # Applies ungoogled-chromium's series, then (in apply_layer) Clair's
  # patches/series. Each stops at the first patch that does not apply and
  # names it.
  python3 "$_main_repo/utils/patches.py" apply "$_src_dir" "$_main_repo/patches"
  mkdir -p "$_src_dir/third_party/llvm-build/Release+Asserts"
  mkdir -p "$_src_dir/third_party/rust-toolchain/bin"
  "$_root_dir/retrieve_and_unpack_resource.py" -p arm64

  if $_keep_base; then
    if python3 "$_sync_tree" clone "$_src_dir" "$_base_dir"; then
      base_key > "$_base_key_file"
    else
      echo "Can't clone build/src on this volume; later updates will start from fresh source." >&2
      _keep_base=false
    fi
  fi
  stamp_layer
  apply_layer "$_src_dir"
  if $_keep_base; then
    record_layer "$_src_dir" > "$_layer_file"
  fi

  touch "$_prepared_stamp"
}

stage_update() {
  local reason=""
  if [[ ! -e "$_prepared_stamp" ]]; then
    reason="build/src is not a prepared tree"
  elif [[ ! -d "$_base_dir" || ! -f "$_layer_file" || ! -f "$_base_key_file" ]]; then
    reason="the workspace has no base tree"
  elif [[ -e "$_updating_file" ]]; then
    reason="an earlier update did not finish"
  elif [[ "$(cat "$_base_key_file")" != "$(base_key)" ]]; then
    reason="the ungoogled-chromium pin or the downloads changed"
  fi
  if [[ -n "$reason" ]]; then
    echo "Can't update build/src in place: $reason. Starting from fresh source."
    _keep_base=true
    stage_fetch
    stage_prepare
    return
  fi

  echo "Updating build/src in place"
  rm -rf "$_next_dir"
  python3 "$_sync_tree" clone "$_base_dir" "$_next_dir"
  stamp_layer
  # A patch that doesn't apply stops here, before build/src changes.
  apply_layer "$_next_dir"
  record_layer "$_next_dir" > "$_layer_file.new"
  rm -f "$_status_file"
  # Until the sync finishes, build/src is in an unknown state, and the next
  # update starts from fresh source.
  touch "$_updating_file"
  python3 "$_sync_tree" sync "$_next_dir" "$_src_dir" "$_layer_file" "$_layer_file.new"
  mv "$_layer_file.new" "$_layer_file"
  rm -f "$_updating_file"
  rm -rf "$_next_dir"
}

stage_configure() {
  # mac_sdk_path is a symlink with a fixed name, so ninja doesn't see an SDK
  # change. Objects compiled with another SDK are deleted instead of mixed in.
  local sdk_link="$_out_dir/sdk/selected_macos_sdk"
  if [[ -f "$_out_dir/args.gn" && "$(readlink "$sdk_link" 2>/dev/null || true)" != "$_sdk_path" ]]; then
    echo "The macOS SDK changed; deleting out/Default to compile everything again."
    rm -rf "$_out_dir"
  fi
  local fresh_out=false
  if [[ ! -f "$_out_dir/args.gn" ]]; then
    fresh_out=true
  fi

  mkdir -p "$_out_dir"
  {
    cat "$_main_repo/flags.gn" "$_root_dir/flags.macos.gn" "$_root_dir/flags.clair.gn"
    echo 'target_cpu = "arm64"'
    if [[ -n "$_sdk_path" ]]; then
      echo 'mac_sdk_path = "//out/Default/sdk/selected_macos_sdk"'
    fi
  } > "$_out_dir/args.gn.new"
  # Rewritten only when it changes, so an unchanged configuration doesn't
  # make ninja regenerate the build files.
  if cmp -s "$_out_dir/args.gn.new" "$_out_dir/args.gn"; then
    rm "$_out_dir/args.gn.new"
  else
    mv "$_out_dir/args.gn.new" "$_out_dir/args.gn"
  fi

  if [[ -n "$_sdk_path" ]]; then
    # Chromium's sdk_inputs action requires its SDK path inside root_build_dir.
    mkdir -p "$_out_dir/sdk"
    ln -sfn "$_sdk_path" "$sdk_link"
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

  # GN and bindgen are built for a new out/Default only: bindgen is an input
  # of the bindgen actions, so a new copy would rerun them all.
  if $fresh_out || [[ ! -x out/Default/gn ]]; then
    ./tools/gn/bootstrap/bootstrap.py -o out/Default/gn --skip-generate-buildfiles
  fi
  if $fresh_out || [[ ! -x third_party/rust-toolchain/bin/bindgen ]]; then
    ./tools/rust/build_bindgen.py --skip-test
  fi
  ./out/Default/gn gen out/Default --fail-on-unused-args
}

stage_compile() {
  cd "$_src_dir"
  echo running > "$_status_file"

  if [[ -z "$_time_limit" ]]; then
    ninja ${_ninja_jobs[@]+"${_ninja_jobs[@]}"} -C out/Default chrome chromedriver
  else
    if [[ -z "$_timeout_bin" ]]; then
      echo "-t needs GNU timeout (brew install coreutils)." >&2
      exit 1
    fi
    local code=0
    "$_timeout_bin" -k 7m -s SIGTERM "${_time_limit}s" ninja ${_ninja_jobs[@]+"${_ninja_jobs[@]}"} -C out/Default chrome chromedriver || code=$?
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
    update) stage_update ;;
    configure) stage_configure ;;
    compile) stage_compile ;;
    all) stage_fetch; stage_prepare; stage_configure; stage_compile ;;
    *) echo "Unknown stage: $stage" >&2; usage >&2; exit 1 ;;
  esac
done
