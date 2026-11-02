# Building Clair

Clair is ungoogled-chromium plus Clair's patches, built for Apple Silicon Macs. The same `build.sh` stages run on your Mac and in GitHub Actions.

## Building in GitHub Actions (the usual way)

The build is split in two (design D9–D12 of the active OpenSpec change):

- **The engine**, the patched Chromium, is built only on the owner's Mac by `.github/workflows/engine.yml`, when the owner starts it: `gh workflow run engine.yml -f ref=<branch>`. That uses `main`'s copy of `engine.yml`; add `--ref <branch>` when the branch changes the workflow itself. It publishes the prerelease `chromium-engine-<key>`, where the key is a hash of the engine's inputs (`scripts/engine-key.sh --manifest` lists them). Read its log with `gh run view --log`.
- **The patch check**, `.github/workflows/build.yml`, runs `./build.sh fetch prepare` on a GitHub-hosted runner for each pull request. A patch that doesn't apply fails the job, and the log names the patch. The same stage compiles Clair's icon and replaces Chromium's logos (see `resources/icon/README.md`); a logo path that no longer exists in Chromium also fails the job and is named in the log. Pull requests that only touch Markdown, `docs/`, `openspec/` or `.sparkle/` skip it, and a new push to the same pull request cancels the check that's running.

To try an engine, download it with `gh release download chromium-engine-<key>`, unzip it and remove the quarantine flag first: `xattr -dr com.apple.quarantine Clair.app`.

## Building locally

### System requirements

Building and running have different requirements: Clair runs on macOS 15.6 or later, but building it needs a much newer Mac.

| | Engine (Chromium) | Native layer (`ClairUI`) |
|---|---|---|
| Mac | Apple Silicon, 32 GB of RAM or more, about 80 GB of free disk (a 40 GB workspace plus the 30 GB reserve) | Apple Silicon |
| macOS | 26.6 or later, for Xcode 27.2 | 26.6 or later, for Xcode 27.2 |
| Xcode | 27.2 or later, with its Metal toolchain (`xcodebuild -downloadComponent MetalToolchain`): ANGLE compiles its shaders with it | 27.2 or later: the project is in Xcode's JSON format (`project.xcproj`), which Xcode 26 can't open |
| macOS SDK | 26.x, 26.2 or later, passed with `-s`: Chromium 156 needs 26.2, and its linker can't read the macOS 27 SDK that Xcode 27 ships. The Command Line Tools include a 26.x SDK (`/Library/Developer/CommandLineTools/SDKs/`) | Xcode's own |
| Other tools | Python 3.13 with `pip3 install PySocks httplib2`, and `brew install go ninja coreutils esbuild typescript zstd quilt` | none |

`engine.yml` picks the newest installed 26.x SDK itself. On the owner's Mac, `.github/workflows/runner-check.yml` checks the Xcode version, the Metal toolchain, the SDK, Python and the Homebrew tools, and warns when free disk is low. Software Update can replace the Command Line Tools' SDKs; when the SDK changes, the engine build deletes `out/Default` and compiles from scratch. A clean engine build takes about 4 hours on an M1 Pro (see [Engine build times](#engine-build-times)).

GitHub's `macos-26` runner image has Xcode 26.6 at most, so CI jobs that build `ClairUI` use the `xcode-27` image (a public preview).

Then:

```sh
git clone --recurse-submodules https://github.com/itsjoshpark/Clair.git
cd Clair
./build.sh -s /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk   # fetch, prepare, configure and compile
```

The stages can also be run one at a time: `./build.sh fetch prepare`, then `./build.sh configure`, then `./build.sh compile`. Run `./build.sh -h` for the options. The app is built at `build/src/out/Default/`.

`prepare` refuses to run twice on the same source. Run `fetch` again to start from clean source. It re-clones only when the existing source has been modified.

### Updating a prepared tree in place

`engine.yml` builds in a workspace it keeps between runs, and passes `-k` so `prepare` keeps `build/base`: an APFS clone of the source as it is after ungoogled-chromium's patches and before Clair's. Cloning takes no extra disk space until files change. `./build.sh -k update` then brings a prepared tree up to date when only Clair's patches changed:

1. It clones `build/base` to `build/next` and applies Clair's layer there: `patches/series`, the overlay, the UI string rebranding, the icon and logos, and domain substitution. A patch that doesn't apply stops the update before `build/src` changes.
2. It copies into `build/src` only the files whose contents differ, using the list of files the previous layer touched (`build/layer_files`) and the files the new one touched. Files that come out the same keep their modification times, so ninja rebuilds only the targets the change affects.

`update` starts from fresh source (`fetch prepare`) instead when the tree has no base, when the ungoogled-chromium pin, `downloads*.ini` or `retrieve_and_unpack_resource.py` changed, when an earlier update stopped partway, or when `build/base_key` is unreadable. The log names the reason, with the recorded and current base keys when they differ. `configure` deletes `out/Default` when the macOS SDK changes, so no objects compiled with the old SDK are linked into the new engine.

## Building the native layer

`ClairUI.framework`, Clair's Swift layer, builds with Xcode 27.2 or later and needs no Chromium checkout or engine:

```sh
xcodebuild -project native/ClairUI.xcodeproj -scheme ClairUI \
  -destination "platform=macOS,arch=arm64" build test
```

Or open `native/ClairUI.xcodeproj` in Xcode. The project is in Xcode's JSON format (`project.xcproj`); don't add a `project.pbxproj`. Sources in `native/ClairUI/` and tests in `native/ClairUITests/` join their targets by being in those folders.

`native/ClairHost.h` is the whole contract with Chromium. Swift imports it as the `ClairHost` module (`native/module.modulemap`). Chromium loads the framework, takes its principal class (`ClairUIMain`) and calls `+startWithHost:` with its host. The header is an engine input, so changing it needs a new engine; Swift sources aren't.

On the Chromium side, `patches/clair/native-layer-hook.patch` calls `clair::StartNativeLayer()` once the main menu is built. The loader and Chromium's host live in `overlay/chrome/browser/clair/`, and `prepare` copies `ClairHost.h` beside them (`scripts/install-native-contract.sh`). The engine looks for `Contents/Frameworks/ClairUI.framework`; a bare engine has none, logs `ClairUI: no framework at …` and runs without it.

## Packaging Clair.app

`package.sh` turns an engine into `Clair.app` and its DMG in about a minute, with no Chromium checkout:

```sh
gh release download chromium-engine-<key> -p '*.zip'
./package.sh Clair-Chromium-Engine-<key>-arm64.zip build/package
```

It builds `ClairUI` (or takes `--clairui <framework>`), fetches Sparkle with `scripts/fetch-sparkle.sh`, writes the version from `version.txt`, the build number from `git rev-list --count HEAD` and Sparkle's keys into `Info.plist`, signs every nested bundle inside out, and writes `Clair-<version>-arm64.dmg`. Without `--identity`, it signs ad hoc and without the hardened runtime: an ad hoc signature has no Team ID, so library validation would refuse every framework. Ad hoc packages are for testing on your own Mac. Remove the quarantine flag before opening one you downloaded. `./package.test.sh` checks it against a stand-in engine.

## Editing patches

Clair's patch series is `patches/series`. Paths in it are relative to `patches/`, and it is applied after ungoogled-chromium's own series. To edit or add a patch, use quilt on a fetched, unpatched source tree:

```sh
./build.sh fetch
cd build/src
export QUILT_PATCHES="$PWD/../../patches" QUILT_SERIES=series
export QUILT_REFRESH_ARGS="-p ab --no-timestamps --no-index"
quilt push -a       # apply Clair's patches one by one
quilt new clair/my-change.patch
quilt add path/to/file.cc
# edit the file...
quilt refresh
```

Clair's series assumes ungoogled-chromium's patches are already applied. Apply those first with `python3 ../../ungoogled-chromium/utils/patches.py apply . ../../ungoogled-chromium/patches`, then use quilt for Clair's.

## Adding new source files: the overlay

New Chromium source files go in `overlay/`, at their paths in the Chromium tree, for example `overlay/chrome/browser/clair/clair_host.mm`. `prepare` copies them in right after `patches/series` (`scripts/apply-overlay.sh`). The overlay only adds files: one whose path already exists in Chromium, or that a patch creates, fails `prepare` and is named in the log. Changes to Chromium's existing files are patches. Wiring a new file into the build (a `BUILD.gn` dependency, a call site) is a patch too, so keep that patch to the hook and put the logic in the overlay.

## Updating the engine

Change the pinned ungoogled-chromium tag:

```sh
git -C ungoogled-chromium fetch --tags
git -C ungoogled-chromium checkout <new tag>
git add ungoogled-chromium
```

Then open a pull request. If a macOS or Clair patch no longer applies, the fetch job names it. Fix that patch, using ungoogled-chromium-macos's and Helium's updates as references.

## Engine build times

Measured on the self-hosted Mac (M1 Pro, 32 GB, internal disk) for the first engine, `chromium-engine-70bf0b64d9e3cb3c` (Chromium 156.0.8078.73), on 2026-10-31:

| Stage | Time |
|---|---|
| Fetch, prepare and configure, with `build/download_cache` already filled | 9 min |
| Full compile from scratch, 57,495 ninja actions (rebuild of the same engine, 2026-10-31) | 3 h 58 min |
| Verify, smoke test, package and publish | about 1 min |
| A run whose engine is already published | 12 s |
| Fresh tree that also creates `build/base` (`fetch prepare configure compile` with `-k`, PR #17) | 3 h 48 min for the Build step, 3 h 50 min for the run |
| Patch fix in place (`update configure compile`: a one-line change to one `.cc` file, 2026-11-01) | 5 min 30 s for the Build step, 6 min 30 s from start to published |

In the patch-fix run, the update took about 1.5 minutes (`sync_tree: 6 copied, 0 removed, 1459 unchanged`). After its first action, ninja's restat cut the work to 14 steps: the changed object, the framework relink and the library checks. Besides the patched file, the sync copies `chrome/app/theme/chromium/mac/Assets.car`, which `actool` doesn't build byte for byte the same, and a few grit `__pycache__` files. Neither costs a noticeable rebuild.

## Engine workspace size

Measured with `du` in the same workspace after the full compile:

| Part | Size |
|---|---|
| `build/src` without `out/` (the prepared source, including 4.6 GB of LLVM, 1.8 GB of Rust toolchain and 1.4 GB of `.git`) | 18.8 GB |
| `build/src/out/Default` (7.4 GB of objects, 2.8 GB of dSYMs, the 0.37 GB `Clair.app`) | 18.2–19.3 GB |
| `build/download_cache` | 0.9 GB |
| Whole workspace | about 38 GB |
| Published engine zip | 164 MB |

`build/base`, the pristine clone kept by `build.sh -k`, shares its blocks with `build/src` through APFS and adds only the files Clair's layer changes, but `du` counts it in full. `engine.yml` sizes the workspace without it and allows 50 GB for a fresh tree, plus the 30 GB reserve.
