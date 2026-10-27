# Tasks

Tasks marked **(owner)** need the repository owner, because they need Icon Composer, a visual judgment, or a Mac running a specific macOS version.

Wherever a task needs a build, it means the CI build of the pull request, its logs, or the unsigned app artifact it uploads (see `ship-plain-ungoogled-build`). This change depends on that change's task 2.4, the resource-replacement step. Chromium files are only ever read one at a time through the GitHub API; nothing here checks out Chromium on the development machine.

## 1. Artwork source

- [x] 1.1 Add `resources/icon/geometry.svg` with the reference drawing from design D1, plus `resources/icon/AppIcon.icon/Assets/ring.svg` (ring, curl, flick) and `inlay.svg` (hairline, bead), with strokes outlined to filled shapes. Verify that a render of the two layers overlaid covers `geometry.svg`'s strokes, and that in `actool`'s compiled icon the ring is 71% to 73% of the tile's width, its center is 1.5% to 2.7% of the tile's width right of the tile's center, and it is within 0.25% of the center vertically. On the spec's 824 px exported tile, those ranges are 585 to 602 px, 12 to 22 px and 2 px.
- [x] 1.2 Write `resources/icon/AppIcon.icon/icon.json` as in design D2: an automatic background, the ring group with glass and the light and dark gold gradients, and the inlay group without glass. Verify that the JSON parses and that each layer it names exists in `Assets/`.
- [ ] 1.3 **(owner)** Open `AppIcon.icon` in Icon Composer, tune the gold gradients, and check the light, dark, tinted and clear previews. Save it from Icon Composer and commit the saved file. Verify that it opens without warnings and matches the concept page's "B1 at 72%".
- [x] 1.4 Generate `resources/icon/logo.svg` (the full mark in a baked gold gradient on a transparent square canvas) and `logo-mono.svg` (the ring layer only, in `#222222`) from `make_layers.py`, as in design D5. Verify by rendering both at 16, 22, 32 and 128 px and checking that the open ring and curl read clearly at the smallest size.
- [ ] 1.5 Add `resources/icon/make_wordmark.py`, which writes `wordmark.svg` and `wordmark-white.svg` as in design D7, and credit Albert Sans in `CREDITS.md`. Verify that both files contain no `<text>` element, and that renders at 171×32 and 342×64 show the gold mark followed by "Clair", with the text clear of the mark and inside the canvas.
- [ ] 1.6 Write `resources/icon/README.md`: what each file is, how to change the drawing and regenerate the layers, logos, vector icons and wordmark, how to edit the icon in Icon Composer, and how to render and compile. Verify that every command in it runs as written on a fresh clone of the branch.

## 2. Generated images and vector icons

- [ ] 2.1 Add `scripts/render-icon-images.sh` and `scripts/render-icon-images.test.sh`. The script renders each source SVG to its PNGs as listed in `resources/icon/product-logos.txt`. It fails clearly when `rsvg-convert` is missing or a list entry is malformed. Add `librsvg` to `ci.yml`'s Homebrew step. Verify that the test checks every output's pixel size with `sips` and the failure cases, and that CI passes the test and `shellcheck`.
- [ ] 2.2 Write `resources/icon/product-logos.txt` with every PNG, SVG and `.icon` entry from design D5 (source, size, Chromium destination). Verify, one file at a time through the GitHub API, that every destination exists in Chromium at the pinned tag and that each PNG's listed size matches Chromium's file.
- [ ] 2.3 Render and commit the PNGs to `resources/icon/logos/`. Verify that every listed PNG exists at its listed pixel size, and that the 16 px and 22 px logos still show the open ring and curl.
- [x] 2.4 Extend `make_layers.py` to write the nine `.icon` files from design D6 to `resources/icon/vector_icons/`, keeping each file's Chromium canvas sizes. Verify that each file uses only `CANVAS_DIMENSIONS`, `PATH_COLOR_ARGB`, `NEW_PATH`, `FILL_RULE_NONZERO`, `MOVE_TO`, `LINE_TO`, `ARC_TO`, `CIRCLE` and `CLOSE`, that its canvas sizes match Chromium's file, and that a render of each, converted back to SVG by the script's preview mode, shows the mark.

## 3. Compile and integrate

- [ ] 3.1 Add `scripts/compile-icon.sh` and `scripts/compile-icon.test.sh`. The script runs `xcrun actool` on `AppIcon.icon` (app icon `AppIcon`, platform macOS, minimum deployment target 15.6) to write `Assets.car` and `AppIcon.icns`, then renames the latter to `app.icns`. It fails clearly on a missing or malformed input, or when `actool` is unavailable. Verify that the test compiles the real source on CI's `macos-26` runner, that `assetutil --info` lists an `AppIcon` in `Assets.car`, and that `iconutil` converts `app.icns` back to an iconset that includes 16 px and 256 px images.
- [ ] 3.2 Call `scripts/compile-icon.sh` from `./build.sh prepare`, then copy `Assets.car` and `app.icns` into `chrome/app/theme/chromium/mac/` and every entry in `product-logos.txt` to its destination, through task 2.4's resource-replacement step. Verify in the CI fetch job's log that the compile and every copy ran, that `prepare` fails, naming the missing path, if a destination does not exist, and that the build compiles the replaced `.icon` files.
- [ ] 3.3 Update `ship-plain-ungoogled-build`'s design D2 and task 2.4 to describe compiling from source instead of committing `Assets.car`. Verify that `openspec validate` passes for both changes and that neither describes a committed `Assets.car`.

## 4. Checks on the built app

- [ ] 4.1 **(owner)** On macOS 26, install the CI artifact. Verify that the Dock, Finder, Get Info and the Cmd+Tab switcher show the gold ring and nowhere show Chromium's logo.
- [ ] 4.2 **(owner)** On macOS 26, switch icons through the light, dark, tinted (two different tint colors) and clear appearances. Verify each against the spec's System icon appearances scenarios, and attach screenshots to the PR.
- [ ] 4.3 Export the 1024 px image from the built app's icon and measure the ring. Verify that its outer diameter is 585 to 602 px and its center is 12 to 22 px right of center and within 2 px vertically.
- [ ] 4.4 **(owner)** Check the Dock icon against a bright wallpaper in the light appearance. Verify that the gold ring's edge stays clearly visible. If it doesn't, deepen the light gold in Icon Composer and re-run 1.3.
- [ ] 4.5 **(owner)** On macOS 15.6, install the CI artifact. Verify that the Dock and Finder show the gold mark on a light rounded-square tile, and that the open ring and curl are recognisable in Finder's list view at 16 px.
- [ ] 4.6 Open About Clair, `chrome://settings/help` and `chrome://version` in the CI artifact. Verify that the first two show the gold ring, that `chrome://version` shows the Clair wordmark, and that Chromium's logo or wordmark appears on none of them.
- [ ] 4.7 Open a `chrome://` page in the CI artifact. Verify that the address bar's product icon is the one-color ring silhouette.
- [ ] 4.8 Check `document.icns` in the built app. Verify whether it shows Chromium's logo, and record the result under Open Questions in `proposal.md`, either resolved or as a named follow-up change.

## Workflow follow-up

- Squash-merge the PR once CI and the Build pass, as described in `CLAUDE.md`.
- Archive the change once every task is checked, so that `app-icon` becomes a main spec.
