# Building Clair

Clair is ungoogled-chromium plus Clair's patches, built for Apple Silicon Macs. The same `build.sh` stages run on your Mac and in GitHub Actions.

## Building in GitHub Actions (the usual way)

Open a pull request. `.github/workflows/build.yml` then:

1. **Fetch** fetches and patches the source with `./build.sh fetch prepare` (the patch-only mode). A patch that doesn't apply fails this job, and the log names the patch. The same stage compiles Clair's icon and replaces Chromium's logos (see `resources/icon/README.md`); a logo path that no longer exists in Chromium also fails the job and is named in the log.
2. **Phases 1–20** compile. Each phase runs `./build.sh -j 3 -t <seconds> compile` until about an hour before GitHub's 6-hour job limit, then hands the build directory to the next phase as an artifact. Phase 1 also runs `./build.sh -l configure`, which appends `flags.pr.gn`: hosted runners have 3 cores and 7 GB of memory, so pull request builds skip ThinLTO, debug symbols and dSYMs and link one binary at a time. Release builds use the full settings. Phases after the one that finishes are skipped.
3. **The finishing phase** runs a headless smoke test, checks that the work tree is clean, and uploads `clair-unsigned-app`, a zip of the unsigned app. You can download it from the run's summary page.
4. **Build result** fails the run if any phase failed, or if 20 phases weren't enough.

Pull requests that only touch Markdown, `docs/`, `openspec/` or `.sparkle/` skip the build. A new push to the same pull request cancels the build that's running.

To run an unsigned app downloaded from CI, unzip it and remove the quarantine flag first: `xattr -dr com.apple.quarantine Chromium.app`.

## Building locally

### System requirements

Building and running have different requirements: Clair runs on macOS 15.6 or later, but building it needs a much newer Mac.

| | Engine (Chromium) | Native layer (`ClairUI`) |
|---|---|---|
| Mac | Apple Silicon, 32 GB of RAM or more, about 150 GB of free disk | Apple Silicon |
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

## Engine build times

Measured on the self-hosted Mac (M1 Pro, 32 GB, internal disk) for the first engine, `chromium-engine-70bf0b64d9e3cb3c` (Chromium 156.0.8078.73), on 2026-10-31:

| Stage | Time |
|---|---|
| Fetch, prepare and configure, with `build/download_cache` already filled | 9 min |
| Compile, 50,411 of 56,713 ninja actions | 3 h 34 min |
| Full compile (extrapolated from the above) | about 4 h |
| Verify, smoke test, package and publish | about 1 min |
| A run whose engine is already published | 12 s |

A patch-fix rebuild time will be added once `build.sh` updates the workspace in place (task 10.3).
