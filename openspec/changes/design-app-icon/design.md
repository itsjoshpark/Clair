# Design

## Context

The motivation is in `proposal.md` and the required behaviour is in `specs/app-icon/spec.md`.

- **Where Chromium's icon lives.** On macOS, Chromium's bundle icon comes from two files in `chrome/app/theme/chromium/mac/`:
  - `Assets.car`, the compiled asset catalog that macOS 26 uses for its icon appearances
  - `app.icns`, the classic icon file
- **How Helium replaces them.** Helium keeps an Icon Composer source (`AppIcon.icon`: `icon.json` plus an SVG) and commits a precompiled `Assets.car` and `app.icns`. A resource list (`platform_resources.txt`) copies both over Chromium's files at prepare time.
- **Change 1's plan.** `ship-plain-ungoogled-build` design D2 and task 2.4 plan the same approach with a placeholder icon.
- **Tooling.** Compiling a `.icon` document needs `actool` from Xcode 26. The hosted macOS runners and the release runner both have Xcode 26.6. The development machine never runs `prepare`.
- **Design record.** The concepts, sizes and variants explored on 2026-10-27 are on the owner's private concept page, <https://claude.ai/artifact/3BJdVBWhpfHk7As4UauYFR>. The chosen variant is "B1 at 72%".

## Goals / Non-Goals

**Goals:**
- One committed vector source for the mark. Every icon file and logo image is generated from it, and the generated files can be regenerated without design work.
- The icon looks right in every macOS 26 appearance without a custom background.

**Non-Goals:**
- Per-size artwork on macOS 26. Icon Composer documents don't support it, and the system scales the vector layers itself.
- Animated or seasonal icon variants.

## Decisions

### D1. Canonical geometry

The mark is drawn in a 100 × 100 drawing space centered on (50, 50) and mapped onto Icon Composer's 1024 px canvas, whose tile is 824 px wide at an offset of 100 px. The mapping `translate(107.5 90.65) scale(8.4271)` produces these values:
- **Size:** the ring's outer edge (radius 35.2 drawing units) is 593 px across, 72% of the tile.
- **Offset:** the ring's center lands at (528.9, 512), so the mark sits 16.9 px (about 2% of the tile) right of center.

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <g transform="translate(107.5 90.65) scale(8.4271)" fill="none" stroke="#000" stroke-linecap="round">
    <!-- ring layer -->
    <path stroke-width="6.4" d="M74.51 29.43 A32 32 0 1 0 74.51 70.57"/>                       <!-- ring, gap +-40 deg -->
    <path stroke-width="3.6" d="M74.51 70.57 C80.43 66.02 81.08 58.22 75.88 55.62 C71.97 53.67 68.07 56.92 70.02 60.43"/> <!-- curl -->
    <path stroke-width="3.6" d="M74.51 29.43 C77.31 27.87 79.13 25.92 79.39 23.71"/>          <!-- flick -->
    <!-- inlay layer -->
    <path stroke-width="2" d="M68 34.89 A23.5 23.5 0 1 0 68 65.11"/>                           <!-- hairline -->
    <circle cx="26.5" cy="50" r="2.6" fill="#000" stroke="none"/>                               <!-- bead -->
  </g>
</svg>
```

The committed layer SVGs convert strokes to filled outlines, because Icon Composer's glass effects and system tinting expect filled shapes. The geometry above stays the reference for any redraw.

**Alternative considered:** a solid, filled mark like Dia's or Safari's. Rejected: the open ring with fine inner detail is the chosen look, and the 72% size gives the line work enough presence in the Dock.

### D2. Icon Composer document

`resources/icon/AppIcon.icon/`:
- **`icon.json` background:** the background fill is `automatic` in every appearance, which gives the system's default light and dark backgrounds the owner asked for.
- **Group 1, the ring layer** (ring, curl and flick): glass on, specular on, neutral shadow. Its fill is a vertical gold gradient specialized by appearance. The starting values below come from the concept page and are tuned by eye in Icon Composer:
  - light: `#EBCB7A` to `#9A6A1C`, deeper so it holds contrast on the light background
  - dark: `#FBE6A6` to `#B5852F`
  - tinted and clear: no fill specialization, so the system recolors the mark
- **Group 2, the inlay layer** (hairline and bead): the same fills, glass off, so it reads as fine engraving under the glass ring.

**Alternative considered:** baking the gold gradient into the SVG. Rejected, because fills set in `icon.json` can be specialized per appearance and are replaced cleanly in the tinted and clear appearances.

### D3. Build-time compile instead of committed binaries

`./build.sh prepare` runs `scripts/compile-icon.sh <AppIcon.icon> <out-dir>`. It calls `xcrun actool` with `AppIcon` as the app icon, a minimum deployment target of 15.6 and the macOS platform, and writes `Assets.car`. It builds `app.icns` from the committed fallback iconset (D4) with `iconutil`. The resource-replacement step from change 1 task 2.4 then copies both files into `chrome/app/theme/chromium/mac/`.

**Why compile at build time:** Helium commits `Assets.car` because compiling it "requires a very specific environment". Clair's CI runners already are that environment (Xcode 26.6). Compiling there keeps the source the single truth and avoids a binary that can drift from it.

**Alternative considered:** Helium's way, committing `Assets.car` compiled on the owner's Mac. It is kept as the fallback if `actool` fails on the hosted runners (see Risks). Change 1's D2 and task 2.4 describe committed binaries today, so this change updates them to the compile step.

### D4. macOS 15 fallback and small sizes

`resources/icon/fallback/` holds a classic iconset of PNGs: the light-appearance tile with the gold mark, at 16 through 512 px at 1x and 2x.
- **16 and 32 px images:** these come from `fallback-small.svg`, which leaves out the hairline and bead and thickens the ring (stroke 9 instead of 6.4) and the curl and flick (stroke 5 instead of 3.6).
- **Larger images:** these come from the full drawing.

The PNGs are rendered by `scripts/render-icon-images.sh`, which needs `rsvg-convert` from Homebrew, and are committed, because they change only when the artwork does.

On macOS 26 the system draws the `.icon` vector at every size, so the hairline and bead stay but thin out at small sizes (see Non-Goals). The spec's small-size requirement is therefore tested on the macOS 15 fallback and only checked visually on macOS 26.

### D5. Product logos

Chromium's in-app product logo images (`product_logo_*` PNGs under `chrome/app/theme/chromium/` and the `default_100_percent` and `default_200_percent` theme folders) are replaced with renderings of `resources/icon/logo.svg`. That file is the mark alone, in a baked gold gradient on a transparent background. The exact file and size list is taken from Helium's resource list at implementation time. The same render script produces the PNGs, and they are committed and copied by the same resource-replacement step.

### D6. Originality

The mark's geometry is original. The gold palette and the light-against-shadow idea are inspired by *Clair Obscur: Expedition 33*, and no art, emblem or wordmark from the game is used or traced. The sunburst "crown" explored as variant B3 was modelled loosely on stepped-ray Art Deco metalwork. If it is ever used as a secondary brand element (for example a DMG background), it needs its own original drawing.

## Risks / Trade-offs

- **[`actool` cannot compile `.icon` on the hosted runner image]** → Fall back to D3's alternative: compile on the owner's Mac and commit `Assets.car`, with the same copy step.
- **[macOS 15 uses the asset catalog's generated rendition instead of `app.icns`]** If Chromium's `Info.plist` names `CFBundleIconName`, macOS 15 may prefer the catalog, and the simplified 16 and 32 px images in D4 would not show. → Check on macOS 15.6. If that happens, add the fallback PNGs to the catalog as an `AppIcon.appiconset` next to the `.icon` source.
- **[Gold has low contrast on the light background]** → Use the deeper light-appearance gold and the neutral shadow. Check it in the Dock against a bright wallpaper before marking the work done.
- **[Hand-written `icon.json` drifts from Icon Composer's format]** → The owner opens the document in Icon Composer and saves it once. The saved file is what gets committed.
- **[The optical offset is a judgment call]** → The spec allows a 12 to 22 px range on the 1024 px canvas, so a later nudge doesn't need a spec change.

## Migration Plan

Nothing has shipped, so there is no migration. If the new icon breaks a build, revert to change 1's placeholder by pointing the resource-replacement step back at it.
