# Proposal

## Why

Opening Clair's DMG shows a plain Finder window with `Clair.app` and an `Applications` link, wherever Finder happens to put them, with no hint that you should drag one onto the other. Task 5.3 of `ship-plain-ungoogled-build` left the background for later. The DMG is the first thing a new user sees, so it should look like Clair and say what to do.

## What Changes

- The DMG window gets a fixed layout: its size, Clair on the left and Applications on the right at fixed positions, a large icon size, and no toolbar, sidebar or status bar.
- A designed background, drawn from the same artwork as the app icon (`resources/icon/`), with an arrow from Clair to Applications. It is generated from SVG at 1x and 2x and committed, like the product logos.
- The mounted volume uses Clair's app icon instead of the generic disk icon.
- `package.sh` builds the DMG with `dmgbuild`, pinned, instead of `hdiutil create`. `dmgbuild` writes the window's `.DS_Store` directly, so it runs headless on the owner's Mac and on hosted runners, with no Finder scripting. Signing, notarization and stapling don't change.
- `package.test.sh` checks the mounted layout: the background, icon positions and volume icon.

Out of scope:
- a background that changes with dark mode, which Finder can't do for DMG windows
- a license agreement or other installer screens
- changes to the DMG's name, format (ULFO) or contents beyond the layout files

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `release-distribution`: adds a requirement for the DMG window's layout, background and volume icon. `release-distribution` is still in flight in `ship-plain-ungoogled-build`, so this is a new requirement next to "Signed and notarized disk image" rather than a modification of it.

## Impact

- **Code:** `package.sh`'s DMG section and `package.test.sh`. New `resources/dmg/`: the `dmgbuild` settings, the background source and its renders, and the script that renders them.
- **Dependencies:** `dmgbuild` (MIT; it depends on `ds_store` and `mac_alias`), pinned in a requirements file and installed into a virtual environment by `package.sh`'s callers. `rsvg-convert` (already used for the logos) and macOS's `tiffutil` render the background.
- **Workflows:** `release.yml`'s `package` job on the owner's Mac, and `quality.yml`, whose runtime suite builds a DMG for its update test, both need `dmgbuild` installed. `ci.yml`'s script tests need it for `package.test.sh`.
- **Engine:** none. `package.sh` and `resources/dmg/` aren't engine inputs, so the engine key doesn't change.
- **Updates:** Sparkle copies only `Clair.app` out of the DMG, so the extra layout files don't affect updates. The runtime suite's update test covers this.
- **Release notes:** a Changie fragment, since users see the new window.
