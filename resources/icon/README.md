# Clair icon and logos

Everything here is drawn from one geometry: the gilded ring, a thick open gold ring with an inner hairline and bead, a curl at its lower end and a short flick at its upper end. The decisions behind it are in `openspec/changes/design-app-icon/` (or its archived copy).

## Files

| File | What it is | Made by |
|---|---|---|
| `geometry.svg` | Reference drawing of the mark as strokes, on Icon Composer's 1024 px canvas | hand |
| `make_layers.py` | Outlines the geometry into every vector form below | hand |
| `AppIcon.icon/` | Icon Composer document: `icon.json` plus the `ring.svg` and `inlay.svg` layers | `icon.json` by hand (saved from Icon Composer), layers by `make_layers.py` |
| `logo.svg`, `logo-mono.svg` | In-app logo: the gold mark, and a one-colour silhouette | `make_layers.py` |
| `vector_icons/` | Chromium `.icon` vector icons, at the same paths as Chromium's | `make_layers.py` |
| `make_wordmark.py` | Writes the wordmark: the mark plus "Clair" in Albert Sans, as outlines | hand |
| `wordmark.svg`, `wordmark-white.svg` | Wordmark with dark text, and with white text | `make_wordmark.py` |
| `product-logos.txt` | Every Chromium file Clair replaces, and its source and size | hand |
| `logos/` | Rendered PNGs, at the same paths as Chromium's | `scripts/render-icon-images.sh` |

The app icon itself (`Assets.car` and `app.icns`) is not committed. `./build.sh prepare` compiles it from `AppIcon.icon` with `scripts/compile-icon.sh`.

## Changing the mark

The geometry lives in two places that must agree: the strokes in `geometry.svg` and the constants at the top of `make_layers.py`. Change both, then regenerate everything, from the repository root:

```sh
python3 resources/icon/make_layers.py
python3 -m venv /tmp/clair-fonttools && /tmp/clair-fonttools/bin/pip install fonttools
/tmp/clair-fonttools/bin/python resources/icon/make_wordmark.py
scripts/render-icon-images.sh resources/icon/product-logos.txt resources/icon resources/icon/logos
```

- **Previews:** `make_layers.py --preview <dir>` also writes each `.icon` file back out as an SVG you can open.
- **Font:** `make_wordmark.py` downloads Albert Sans (SIL Open Font License 1.1) from a pinned `google/fonts` commit into `resources/icon/.font-cache/`, which git ignores.
- **Tools:** the render script needs `rsvg-convert` (`brew install librsvg`).

Commit the regenerated files together with the geometry change.

## Editing the icon's look

Open `AppIcon.icon` in Icon Composer (Xcode 26 or later) to tune the gold gradients, glass, shadow and the light, dark, tinted and clear appearances. Save it from Icon Composer and commit `icon.json`. Icon Composer's 1024 px canvas is the icon tile itself, and the layers fill it at scale 1, so don't move or rescale them there. Size and position belong to the geometry.

## Checking the compiled icon

```sh
scripts/compile-icon.sh resources/icon/AppIcon.icon /tmp/clair-icon
iconutil -c iconset -o /tmp/clair-icon/app.iconset /tmp/clair-icon/app.icns
open /tmp/clair-icon/app.iconset/icon_128x128@2x.png
```

The ring should be 71% to 73% of the tile's width and sit about 2% right of center.
