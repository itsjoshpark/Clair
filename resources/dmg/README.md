# Clair's DMG window

What the release DMG looks like when it's opened in Finder: its window, the background with the arrow from Clair to Applications, and the volume icon. The decisions behind it are in `openspec/changes/style-release-dmg/` (or its archived copy).

`package.sh` builds the DMG with [`dmgbuild`](https://github.com/dmgbuild/dmgbuild), which writes the window's `.DS_Store` itself, so packaging needs no Finder scripting and runs headless.

## Files

| File | What it is | Made by |
|---|---|---|
| `layout.json` | The window's position and size, the icon and label sizes, and where Clair and Applications sit | hand |
| `settings.py` | `dmgbuild`'s settings: the layout from `layout.json`, the volume icon, the background, ULFO on HFS+, and no toolbar, sidebar, status bar or path bar | hand |
| `make_background.py` | Writes the background from `layout.json` and the mark's geometry and gold in `resources/icon/make_layers.py` | hand |
| `background.svg` | The background, 660 × 400 points | `make_background.py` |
| `background.tiff` | The background rendered at 1x and 2x in one file, which `package.sh` puts on the volume as `.background.tiff` | `scripts/render-dmg-background.sh` |
| `requirements.txt` | `dmgbuild`, `ds_store` and `mac_alias`, pinned to wheels and their sha256 | hand |

The volume icon isn't here: `package.sh` uses the packaged app's own `Contents/Resources/app.icns`, so it always matches the app icon.

`scripts/fetch-dmgbuild.sh` installs `requirements.txt` into a virtual environment in `build/dmgbuild/`, with a Python of 3.10 or later, and `package.sh` runs it unless it's given `--dmgbuild <path>`. To upgrade `dmgbuild`, change all three pins together, with each wheel's sha256 from PyPI, and check `dmgbuild`'s and `ds_store`'s dependencies haven't grown: pip installs only what's listed.

## Changing the layout or the background

Edit `layout.json` for positions and sizes, and the constants at the top of `make_background.py` for the tone, the arrow and the mark. Then regenerate both renders, from the repository root:

```sh
python3 resources/dmg/make_background.py
scripts/render-dmg-background.sh resources/dmg/background.svg resources/dmg/background.tiff
```

- **Tone:** Finder draws the labels black in Light Mode and white in Dark Mode, and never changes a DMG's background with the appearance. `make_background.py` refuses a label tone where either has less than 4.5:1 contrast, and prints both.
- **Tools:** the render script needs `rsvg-convert` (`brew install librsvg`). `tiffutil` comes with macOS.
- **Checks:** `scripts/render-dmg-background.test.sh` fails if `background.svg` isn't what `make_background.py` writes or `background.tiff` isn't at the window's size. `./package.test.sh` checks a built DMG against `layout.json`.

Commit `layout.json`, `background.svg` and `background.tiff` together. Before a release that changes them, open the dry-run DMG in Light and Dark Mode, as `docs/releasing.md`'s checklist says.
