#!/usr/bin/env python3
"""Write the DMG window's background, background.svg (style-release-dmg design D3).

A plain light field. "To install, drag Clair to Applications" runs along the
top, and three chevrons, light to dark, point from Clair to Applications.

The window size and the icon positions come from layout.json, which settings.py
also reads, so the chevrons always sit between the icons. The text is Inter
(SIL Open Font License 1.1), downloaded from a pinned google/fonts commit into
resources/icon/.font-cache/, which git ignores, and turned into outlines so the
SVG has no <text>.

Finder draws the icon labels dark on a light background, in Dark Mode too, so
the script refuses a field where black text falls below LABEL_CONTRAST.

Needs fontTools and uharfbuzz (pip install fonttools uharfbuzz): HarfBuzz lays
out the text with Inter's kerning, and fontTools draws the outlines. Render the
result with scripts/render-dmg-background.sh.

Usage: make_background.py [--out FILE] [--font-cache DIR]
"""

import json
import os
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ICON = os.path.join(HERE, "..", "icon")
# Importing these would otherwise leave __pycache__ in resources/icon/.
sys.dont_write_bytecode = True
sys.path.insert(0, ICON)
import make_layers  # noqa: E402

from fontTools.pens.svgPathPen import SVGPathPen  # noqa: E402
from fontTools.pens.transformPen import TransformPen  # noqa: E402
from fontTools.ttLib import TTFont  # noqa: E402
from fontTools.varLib import instancer  # noqa: E402
import uharfbuzz as hb  # noqa: E402

FIELD = "#FAF8F4"
LABEL_CONTRAST = 4.5

FONT_COMMIT = "fffdadf0f0c9cc1ec8b407063424a8bfbee05611"
FONT_URL = ("https://raw.githubusercontent.com/google/fonts/%s/ofl/inter/Inter%%5Bopsz%%2Cwght%%5D.ttf"
            % FONT_COMMIT)
OPTICAL_SIZE = 20

# The instruction: runs of (text, colour, weight), centred at CAPTION_Y.
CAPTION = (("To install, drag ", "#666666", 400), ("Clair", "#000000", 600),
           (" to ", "#666666", 400), ("Applications", "#000000", 600))
CAPTION_Y = 52.5          # the capitals' vertical centre
CAPTION_CAP_HEIGHT = 12

# Three chevrons, light to dark, pointing from Clair to Applications.
CHEVRONS = ("#C6C6C6", "#7C7C7C", "#000000")
CHEVRON_DROP = 13.5       # below the icons' centres, where app icons look centred
CHEVRON_PITCH = 16.25     # from one chevron to the next
CHEVRON_WIDTH = 7.5       # from the arms' ends to the tip
CHEVRON_HEIGHT = 20.5     # from one arm's end to the other's
CHEVRON_STROKE = 3


def luminance(colour):
    """WCAG relative luminance of #RRGGBB."""
    def channel(value):
        c = value / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (int(colour[i:i + 2], 16) for i in (1, 3, 5))
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def load_layout():
    with open(os.path.join(HERE, "layout.json")) as f:
        return json.load(f)


def n(value):
    return make_layers.num(value, 2)


def font_path(cache):
    path = os.path.join(cache, "Inter-%s.ttf" % FONT_COMMIT[:12])
    if not os.path.exists(path):
        os.makedirs(cache, exist_ok=True)
        urllib.request.urlretrieve(FONT_URL, path)
    return path


def chevrons(layout):
    """The three chevrons' paths and colours, centred between the icons."""
    (x1, y1), (x2, y2) = layout["icons"]["Clair.app"], layout["icons"]["Applications"]
    span = CHEVRON_PITCH * (len(CHEVRONS) - 1) + CHEVRON_WIDTH
    if y1 != y2 or x2 - x1 < layout["icon_size"] + span:
        raise SystemExit("make_background: Applications must sit level with Clair, far enough to its right for the chevrons")
    y = y1 + CHEVRON_DROP
    left = (x1 + x2) / 2 - span / 2
    paths = []
    for i, colour in enumerate(CHEVRONS):
        x = left + i * CHEVRON_PITCH
        paths.append((colour, "M%s %s L%s %s L%s %s" % (
            n(x), n(y - CHEVRON_HEIGHT / 2), n(x + CHEVRON_WIDTH), n(y), n(x), n(y + CHEVRON_HEIGHT / 2))))
    return paths


def shape(font_file, text, weight):
    """HarfBuzz's layout of TEXT at WEIGHT: (glyph name, x offset, advance) in font units, kerning included."""
    with open(font_file, "rb") as f:
        face = hb.Face(f.read())
    font = hb.Font(face)
    font.set_variations({"wght": weight, "opsz": OPTICAL_SIZE})
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(font, buf, {"kern": True, "liga": True})
    order = TTFont(font_file).getGlyphOrder()
    return [(order[info.codepoint], pos.x_offset, pos.x_advance)
            for info, pos in zip(buf.glyph_infos, buf.glyph_positions)]


def caption(font_file, width):
    """The instruction's runs as (colour, path data), centred across the window."""
    fonts = {weight: instancer.instantiateVariableFont(TTFont(font_file), {"wght": weight, "opsz": OPTICAL_SIZE})
             for weight in sorted({run[2] for run in CAPTION})}
    scale = CAPTION_CAP_HEIGHT / fonts[400]["OS/2"].sCapHeight
    shaped = [(colour, weight, shape(font_file, text, weight)) for text, colour, weight in CAPTION]
    advance = sum(a for _, _, glyphs in shaped for _, _, a in glyphs) * scale
    x = (width - advance) / 2
    baseline = CAPTION_Y + CAPTION_CAP_HEIGHT / 2
    runs = []
    for colour, weight, glyphs in shaped:
        glyph_set = fonts[weight].getGlyphSet()
        pen = SVGPathPen(glyph_set, lambda v: make_layers.num(v, 2))
        for name, offset, adv in glyphs:
            # Font units are y-up; the canvas is y-down.
            glyph_set[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x + offset * scale, baseline)))
            x += adv * scale
        runs.append((colour, pen.getCommands()))
    return runs


def background(layout, font_file):
    width, height = layout["window"]["width"], layout["window"]["height"]
    labels = contrast(FIELD, "#000000")
    if labels < LABEL_CONTRAST:
        raise SystemExit("make_background: labels would have %.2f:1 contrast on %s; need %.1f:1"
                         % (labels, FIELD, LABEL_CONTRAST))
    for text, colour, _ in CAPTION:
        if contrast(FIELD, colour) < LABEL_CONTRAST:
            raise SystemExit("make_background: %r in %s has too little contrast on %s" % (text, colour, FIELD))
    marks = chevrons(layout)
    runs = caption(font_file, width)
    return "\n".join([
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d">' % (width, height, width, height),
        "  <!-- Generated by resources/dmg/make_background.py; do not edit. -->",
        '  <rect width="%d" height="%d" fill="%s"/>' % (width, height, FIELD),
        "\n".join('  <path fill="%s" d="%s"/>' % run for run in runs),
        '  <g fill="none" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round">' % n(CHEVRON_STROKE),
        "\n".join('    <path stroke="%s" d="%s"/>' % mark for mark in marks),
        "  </g>",
        "</svg>",
        "",
    ]), labels


def main(argv):
    out = argv[argv.index("--out") + 1] if "--out" in argv else os.path.join(HERE, "background.svg")
    cache = argv[argv.index("--font-cache") + 1] if "--font-cache" in argv else os.path.join(ICON, ".font-cache")
    text, labels = background(load_layout(), font_path(cache))
    with open(out, "w") as f:
        f.write(text)
    print("wrote", out)
    print("label contrast: %.2f:1" % labels)


if __name__ == "__main__":
    main(sys.argv[1:])
