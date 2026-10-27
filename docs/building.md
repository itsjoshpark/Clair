# Building Clair

Clair is ungoogled-chromium plus Clair's patches, built for Apple Silicon Macs. The same `build.sh` stages run on your Mac and in GitHub Actions.

## Building in GitHub Actions (the usual way)

Open a pull request. `.github/workflows/build.yml` then:

1. **Fetch** fetches and patches the source with `./build.sh fetch prepare` (the patch-only mode). A patch that doesn't apply fails this job, and the log names the patch.
2. **Phases 1–20** compile. Each phase runs `./build.sh -j 3 -t <seconds> compile` until about an hour before GitHub's 6-hour job limit, then hands the build directory to the next phase as an artifact. Phase 1 also runs `./build.sh -l configure`, which appends `flags.pr.gn`: hosted runners have 3 cores and 7 GB of memory, so pull request builds skip ThinLTO, debug symbols and dSYMs and link one binary at a time. Release builds use the full settings. Phases after the one that finishes are skipped.
3. **The finishing phase** runs a headless smoke test, checks that the work tree is clean, and uploads `clair-unsigned-app`, a zip of the unsigned app. You can download it from the run's summary page.
4. **Build result** fails the run if any phase failed, or if 20 phases weren't enough.

Pull requests that only touch Markdown, `docs/`, `openspec/` or `.sparkle/` skip the build. A new push to the same pull request cancels the build that's running.

To run an unsigned app downloaded from CI, unzip it and remove the quarantine flag first: `xattr -dr com.apple.quarantine Chromium.app`.

## Building locally

You need:

- an Apple Silicon Mac with macOS 15.6 or later, about 150 GB of free disk, and 32 GB or more of RAM. A clean build takes several hours.
- Xcode 26 (CI uses 26.0.1), plus its Metal toolchain: `xcodebuild -downloadComponent MetalToolchain`
- Homebrew packages: `brew install go ninja coreutils esbuild typescript zstd quilt`
- Python 3.13, with `pip3 install PySocks httplib2`

Then:

```sh
git clone --recurse-submodules https://github.com/itsjoshpark/Clair.git
cd Clair
./build.sh            # fetch, prepare, configure and compile
```

The stages can also be run one at a time: `./build.sh fetch prepare`, then `./build.sh configure`, then `./build.sh compile`. Run `./build.sh -h` for the options. The app is built at `build/src/out/Default/`.

`prepare` refuses to run twice on the same source. Run `fetch` again to start from clean source. It re-clones only when the existing source has been modified.

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

## Updating the engine

Change the pinned ungoogled-chromium tag:

```sh
git -C ungoogled-chromium fetch --tags
git -C ungoogled-chromium checkout <new tag>
git add ungoogled-chromium
```

Then open a pull request. If a macOS or Clair patch no longer applies, the fetch job names it. Fix that patch, using ungoogled-chromium-macos's and Helium's updates as references.
