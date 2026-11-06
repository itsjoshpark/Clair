# Tasks

Wherever a verification below needs a packaged or signed DMG, it means one built by CI or by a `release.yml` dry run, as in `ship-plain-ungoogled-build`.

## 1. dmgbuild

- [ ] 1.1 Add `resources/dmg/requirements.txt`, pinning `dmgbuild`, `ds_store` and `mac_alias` to wheels with their hashes: `dmgbuild` 1.6.7, or the newest release at least two weeks old at implementation time. Add `scripts/fetch-dmgbuild.sh` (D2) and its test. Verify that the test covers a fresh install, reuse when the requirements match, a reinstall when they change, refusing a Python older than 3.10, and a failed install leaving no environment behind. Verify that `shellcheck -S warning` passes.

## 2. Artwork

- [ ] 2.1 Add `resources/dmg/make_background.py` and the `background.svg` it writes (D3), with the window size and icon positions in one place that `settings.py` also reads. Add `scripts/render-dmg-background.sh` and its test, and commit `background.tiff`. Verify that `tiffutil -info` lists two images, 660 × 400 and 1320 × 800, and that the test fails when the SVG is missing or `rsvg-convert` isn't installed.
- [ ] 2.2 Add `resources/dmg/README.md`: what each file is, what made it, and how to regenerate the background, as `resources/icon/README.md` does. Verify that following it from a clean checkout reproduces the committed `background.tiff`.

## 3. Packaging

- [ ] 3.1 Add `resources/dmg/settings.py` (D3) and make `package.sh` build the DMG with `dmgbuild`, with `--dmgbuild <path>` and `fetch-dmgbuild.sh` as the default, keeping the three attempts and everything after the DMG is created (D4). Extend `package.test.sh` with D5's layout checks. Verify that `package.test.sh` passes, and that each layout check fails when its setting in `settings.py` is changed on purpose.
- [ ] 3.2 Make `dmgbuild` available wherever `package.sh` builds a DMG: `ci.yml`'s script tests, `quality.yml` and `release.yml`'s `package` job, using a Python of 3.10 or later in each. Verify that the merge gate passes, and that a `quality.yml` run dispatched on the branch passes.
- [ ] 3.3 Extend the runtime suite's update test to check that an update from the new DMG replaces only `Clair.app` and leaves nothing else beside it. Verify that `quality.yml` passes on the branch, and that the check fails when a layout file is copied next to the app on purpose.

## 4. Release

- [ ] 4.1 Update `docs/building.md`'s packaging section for `dmgbuild`, add an item to `docs/releasing.md`'s checklist for the DMG window (Light and Dark Mode, and Retina and standard displays when both are at hand), and add a Changie fragment. Verify that the pull request includes all three.
- [ ] 4.2 Run a `release.yml` dry run, then choose the background tone by opening its DMG in Light and Dark Mode. Verify every `release-distribution` scenario from this change on that DMG, including that `verify-app.sh --dmg` passes and that dragging Clair to Applications installs an app that opens after only the standard prompt.

## Workflow follow-up

- Archive this change after the release that first ships the new window.
