# Proposal

## Why

`ship-plain-ungoogled-build` only needs a placeholder icon (task 2.4), but the icon is the first thing users see in the Dock and Finder, and it should be settled before the first public release. The design was chosen during exploration on 2026-10-27, so this change turns it into production artwork and replaces every Chromium logo that a user can see.

## What Changes

- Adopt the chosen mark, the **gilded ring**:
  - a thick open gold ring, opening to the right
  - a thin inner hairline with a small bead on its left side
  - a curl at the ring's lower end and a short flick at its upper end
  - gold is the only color, on Icon Composer's default system background, so macOS chooses the light, dark, tinted or clear look
  - the ring's outer diameter is 72% of the icon tile's width, and the mark sits about 2% of the tile width right of center so it looks optically centered
  - the inspiration is the gilded Belle Époque look of *Clair Obscur: Expedition 33*, where the name comes from. Nothing is copied from the game's emblem, wordmark or art.
- Add the icon source as an Icon Composer document, `resources/icon/AppIcon.icon`, with separate layers for the ring and for the hairline and bead.
- Add a fallback icon set for macOS 15.6, whose 16 px and 32 px images use a simplified drawing that drops the hairline and bead and thickens the ring. On macOS 26 the system scales the vector source itself, and Icon Composer has no per-size artwork.
- Compile the source into `Assets.car` with `actool`, and the fallback set into `app.icns` with `iconutil`, during `./build.sh prepare`. These are the files that `ship-plain-ungoogled-build` task 2.4 copies into Chromium's tree, so this change supplies the artwork for that step and no compiled binaries are committed.
- Replace Chromium's product logo images (the `product_logo_*` PNGs used by the About page and other WebUI) with flat renderings of the mark.

**Out of scope for this change:**
- the DMG background and window layout (release distribution)
- the sunburst "crown" explored as a variant. It is recorded in `design.md` as a possible secondary brand element for large surfaces only.
- document icons for file types Clair opens (see Open Questions)

## Capabilities

### New Capabilities
- `app-icon`: how Clair's icon and product logo appear across macOS surfaces. Covers the mark shown in the Dock, Finder and app switcher, its light, dark, tinted and clear appearances on macOS 26, the fallback on macOS 15.6, legibility at small sizes, and the product logo shown inside the app.

### Modified Capabilities
- None. `app-identity` is still in flight in `ship-plain-ungoogled-build` and covers names and identifiers, not artwork.

## Impact

- **Repository:**
  - `resources/icon/`: the `AppIcon.icon` source, the small-size and flat logo SVGs, and a short README on editing the icon
  - a compile script with its `*.test.sh`, called from `build.sh prepare`
  - the product logo PNGs that replace Chromium's
- **Depends on:** `ship-plain-ungoogled-build` task 2.4 (the resource-replacement step). That change's design (D2) describes a committed placeholder `Assets.car` the way Helium does it. This change compiles from source instead, so D2 and task 2.4 need updating to match.
- **Tooling:** Xcode 26 (`actool` with `.icon` support), which the hosted macOS runners already have (Xcode 26.6). Icon Composer on the owner's Mac for visual review.
- **Builds:** adds a few seconds to the CI fetch job. No effect on the compile phases.

## Open Questions

- **Document icon.** Chromium ships a `document.icns` for HTML and other files it opens. Check what it looks like in the first CI build. If it carries Chromium's logo, add a Clair document icon here or in a follow-up change.
- **macOS 15.6 fallback.** Confirm that `actool` writes a usable pre-Tahoe rendition from the `.icon` source. If it doesn't, ship a rendered `app.icns` as the 15.6 fallback (see `design.md`).
