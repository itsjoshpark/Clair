# Clair's DMG window

What the release DMG looks like when it's opened in Finder: a plain light window with "To install, drag **Clair** to **Applications**" along the top, Clair and Applications side by side, three chevrons between them, and Clair's icon on the mounted volume. The decisions behind it are in `openspec/changes/style-release-dmg/` (or its archived copy).

`package.sh` builds the DMG with [`dmgbuild`](https://github.com/dmgbuild/dmgbuild), which writes the window's `.DS_Store` itself, so packaging needs no Finder scripting and runs headless.

## Files

| File | What it is | Made by |
|---|---|---|
| `layout.json` | The window's position, its size without the title bar, the title bar's height, the icon and label sizes, and where Clair and Applications sit | hand |
| `settings.py` | `dmgbuild`'s settings: the layout from `layout.json`, the volume icon, the background, ULFO on HFS+, and no toolbar, sidebar, status bar or path bar | hand |
| `make_background.py` | Writes the background from `layout.json`: the field, the instruction and the chevrons | hand |
| `artwork-requirements.txt` | What `make_background.py` needs: fontTools and uharfbuzz | hand |
| `background.svg` | The background, 800 × 400 points, with the text as outlines | `make_background.py` |
| `background.tiff` | The background rendered at 1x and 2x in one file, which `package.sh` puts on the volume as `.background.tiff` | `scripts/render-dmg-background.sh` |
| `requirements.txt` | `dmgbuild`, `ds_store` and `mac_alias`, pinned to wheels and their sha256 | hand |

The volume icon isn't here: `package.sh` uses the packaged app's own `Contents/Resources/app.icns`, so it always matches the app icon.

`scripts/fetch-dmgbuild.sh` installs `requirements.txt` into a virtual environment in `build/dmgbuild/`, with a Python of 3.10 or later, and `package.sh` runs it unless it's given `--dmgbuild <path>`. To upgrade `dmgbuild`, change all three pins together, with each wheel's sha256 from PyPI, and check `dmgbuild`'s and `ds_store`'s dependencies haven't grown: pip installs only what's listed.

## Changing the layout or the background

Edit `layout.json` for positions and sizes, and the constants at the top of `make_background.py` for the colours, the text and the chevrons. Then regenerate both renders, from the repository root:

```sh
python3 -m venv /tmp/clair-dmg-artwork && /tmp/clair-dmg-artwork/bin/pip install -r resources/dmg/artwork-requirements.txt
/tmp/clair-dmg-artwork/bin/python resources/dmg/make_background.py
scripts/render-dmg-background.sh resources/dmg/background.svg resources/dmg/background.tiff
```

- **Text:** the instruction is set in [Inter](https://github.com/google/fonts/tree/main/ofl/inter) (SIL Open Font License 1.1) at optical size 20. HarfBuzz lays it out with Inter's kerning, and fontTools turns it into outlines, so the SVG has no `<text>`. The font is downloaded from a pinned `google/fonts` commit into `resources/icon/.font-cache/`, which git ignores.
- **Title bar:** Finder's window bounds include the title bar, so `settings.py` adds `title_bar` to the window's height. Without it, Finder cuts that much off the bottom of the background.
- **Labels:** Finder draws the icon labels dark on a light background, in Dark Mode too. `make_background.py` refuses a field where black text, or any run of the instruction, has less than 4.5:1 contrast.
- **Your own Finder settings:** if "Show Path Bar", "Show Status Bar" or "Show all filename extensions" is on, Finder shows those bars at the bottom of every DMG window, and the label "Clair.app". That's Finder, not the DMG; nothing important sits at the bottom of the window.
- **Tools:** the render script needs `rsvg-convert` (`brew install librsvg`). `tiffutil` comes with macOS.
- **Checks:** `scripts/render-dmg-background.test.sh` fails if `background.svg` isn't what `make_background.py` writes (when the artwork tools are installed; CI installs them) or `background.tiff` isn't at the window's size. `./package.test.sh` checks a built DMG against `layout.json`.

Commit `layout.json`, `background.svg` and `background.tiff` together. Before a release that changes them, open the dry-run DMG in Light and Dark Mode, as `docs/releasing.md`'s checklist says.
