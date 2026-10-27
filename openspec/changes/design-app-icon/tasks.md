# Tasks

Tasks marked **(owner)** need the repository owner, because they need Icon Composer, a visual judgment, or a Mac running a specific macOS version.

Wherever a task needs a build, it means the CI build of the pull request, its logs, or the unsigned app artifact it uploads (see `ship-plain-ungoogled-build`). This change depends on that change's task 2.4, the resource-replacement step.

## 1. Artwork source

- [x] 1.1 Add `resources/icon/geometry.svg` with the reference drawing from design D1, plus `resources/icon/AppIcon.icon/Assets/ring.svg` (ring, curl, flick) and `inlay.svg` (hairline, bead), with strokes outlined to filled shapes. Verify that a 1024 px render of the two layers overlaid matches `geometry.svg`: ring outer diameter 585 to 602 px, ring center 12 to 22 px right of the canvas center and within 2 px of it vertically.
- [x] 1.2 Write `resources/icon/AppIcon.icon/icon.json` as in design D2: an automatic background, the ring group with glass and the light and dark gold gradients, and the inlay group without glass. Verify that the JSON parses and that each layer it names exists in `Assets/`.
- [ ] 1.3 **(owner)** Open `AppIcon.icon` in Icon Composer, tune the gold gradients, and check the light, dark, tinted and clear previews. Save it from Icon Composer and commit the saved file. Verify that it opens without warnings and matches the concept page's "B1 at 72%".
- [ ] 1.4 Add `resources/icon/logo.svg` (the mark alone in the D1 drawing space, baked gold gradient, transparent background). Verify by rendering it at 16, 32 and 128 px and checking that the open ring and curl read clearly at 16 px.
- [ ] 1.5 Write `resources/icon/README.md`: what each file is, how to change the drawing and regenerate the layers, how to edit the icon in Icon Composer, and how to render the logos and compile. Verify that the layer, compile and render commands run as written on a fresh clone (rendering needs Homebrew's `librsvg`).

## 2. Generated images

- [ ] 2.1 Add `scripts/render-icon-images.sh` and `scripts/render-icon-images.test.sh`. The script renders `logo.svg` to the product logos listed in `resources/icon/product-logos.txt`. It fails clearly when `rsvg-convert` is missing or a list entry is malformed. Add `librsvg` to `ci.yml`'s Homebrew step. Verify that the test checks every output's pixel size with `sips`, and that CI passes the test and `shellcheck`.
- [ ] 2.2 Write `resources/icon/product-logos.txt`, with each Chromium `product_logo_*` destination path and its pixel size, built from Helium's resource list and Chromium's tree at the pinned tag. Verify that every destination path exists in the CI fetch job's source tree.
- [ ] 2.3 Render and commit the product logos (`resources/icon/logos/`). Verify that every listed logo exists at its listed pixel size, and that the smallest one still shows the open ring and curl.

## 3. Compile and integrate

- [ ] 3.1 Add `scripts/compile-icon.sh` and `scripts/compile-icon.test.sh`. The script runs `xcrun actool` on `AppIcon.icon` (app icon `AppIcon`, platform macOS, minimum deployment target 15.6) to write `Assets.car` and `AppIcon.icns`, then renames the latter to `app.icns`. It fails clearly on a missing or malformed input, or when `actool` is unavailable. Verify that the test compiles the real source on CI's `macos-26` runner, that `assetutil --info` lists an `AppIcon` in `Assets.car`, and that `iconutil` converts `app.icns` back to an iconset that includes 16 px and 256 px images.
- [ ] 3.2 Call `scripts/compile-icon.sh` from `./build.sh prepare`, then copy `Assets.car` and `app.icns` into `chrome/app/theme/chromium/mac/` and the product logos to their listed paths, through task 2.4's resource-replacement step. Verify in the CI fetch job's log that the compile and every copy ran, and that `prepare` fails, naming the missing path, if a destination does not exist.
- [ ] 3.3 Update `ship-plain-ungoogled-build`'s design D2 and task 2.4 to describe compiling from source instead of committing `Assets.car`. Verify that `openspec validate` passes for both changes and that neither describes a committed `Assets.car`.

## 4. Checks on the built app

- [ ] 4.1 **(owner)** On macOS 26, install the CI artifact. Verify that the Dock, Finder, Get Info and the Cmd+Tab switcher show the gold ring and nowhere show Chromium's logo.
- [ ] 4.2 **(owner)** On macOS 26, switch icons through the light, dark, tinted (two different tint colors) and clear appearances. Verify each against the spec's System icon appearances scenarios, and attach screenshots to the PR.
- [ ] 4.3 Export the 1024 px image from the built app's icon and measure the ring. Verify that its outer diameter is 585 to 602 px and its center is 12 to 22 px right of center and within 2 px vertically.
- [ ] 4.4 **(owner)** Check the Dock icon against a bright wallpaper in the light appearance. Verify that the gold ring's edge stays clearly visible. If it doesn't, deepen the light gold in Icon Composer and re-run 1.3.
- [ ] 4.5 **(owner)** On macOS 15.6, install the CI artifact. Verify that the Dock and Finder show the gold mark on a light rounded-square tile, and that the open ring and curl are recognisable in Finder's list view at 16 px.
- [ ] 4.6 Open About Clair and `chrome://settings/help` in the CI artifact. Verify that the product logo is the gold ring and that Chromium's logo appears nowhere on either page.
- [ ] 4.7 Check `document.icns` in the built app. Verify whether it shows Chromium's logo, and record the result under Open Questions in `proposal.md`, either resolved or as a named follow-up change.

## Workflow follow-up

- Squash-merge the PR once CI and the Build pass, as described in `CLAUDE.md`.
- Archive the change once every task is checked, so that `app-icon` becomes a main spec.
