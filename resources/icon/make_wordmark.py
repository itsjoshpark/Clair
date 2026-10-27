#!/usr/bin/env python3
"""Write the Clair wordmark: the gold mark followed by "Clair" in Albert Sans.

Writes wordmark.svg (dark text) and wordmark-white.svg (white text) on the
171 x 32 canvas of Chromium's wordmark (design D7). The text is converted to
outlines, so the SVGs contain no <text> and render the same everywhere.

Needs fontTools (pip install fonttools). The Albert Sans font (SIL Open Font
License 1.1) is downloaded from a pinned google/fonts commit into a cache
directory and is not committed.

Usage: make_wordmark.py [--font-cache DIR]
"""

import os
import sys
import urllib.request

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

import make_layers

HERE = os.path.dirname(os.path.abspath(__file__))

FONT_COMMIT = "fffdadf0f0c9cc1ec8b407063424a8bfbee05611"
FONT_URL = ("https://raw.githubusercontent.com/google/fonts/%s/ofl/albertsans/AlbertSans%%5Bwght%%5D.ttf"
            % FONT_COMMIT)
WEIGHT = 500

WIDTH, HEIGHT = 171, 32
RING_HEIGHT = 28        # the ring's outer diameter, in canvas pixels
RING_LEFT = 2           # the ring's left edge
TEXT_LEFT = 38          # where "Clair" starts
CAP_HEIGHT = 17         # height of the capital C, in canvas pixels
TEXT = "Clair"
TEXT_COLOURS = {"wordmark.svg": "#4A4741", "wordmark-white.svg": "#FFFFFF"}


def font_path(cache):
    path = os.path.join(cache, "AlbertSans-%s.ttf" % FONT_COMMIT[:12])
    if not os.path.exists(path):
        os.makedirs(cache, exist_ok=True)
        urllib.request.urlretrieve(FONT_URL, path)
    return path


def text_outline(path):
    """SVG path data for TEXT, with the baseline placed so the capitals are centred vertically."""
    font = instancer.instantiateVariableFont(TTFont(path), {"wght": WEIGHT})
    scale = CAP_HEIGHT / font["OS/2"].sCapHeight
    baseline = HEIGHT / 2 + CAP_HEIGHT / 2
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    pen = SVGPathPen(glyphs, lambda v: make_layers.num(v, 2))
    x = TEXT_LEFT
    for char in TEXT:
        name = cmap[ord(char)]
        # Font units are y-up; the canvas is y-down.
        glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x, baseline)))
        x += glyphs[name].width * scale
    return pen.getCommands(), x


def main(argv):
    cache = argv[argv.index("--font-cache") + 1] if "--font-cache" in argv else os.path.join(HERE, ".font-cache")
    text_d, text_right = text_outline(font_path(cache))
    if text_right > WIDTH:
        sys.exit("make_wordmark: the text runs past the %d px canvas" % WIDTH)

    scale = RING_HEIGHT / (2 * make_layers.RING_OUTER)
    mapping = (scale, RING_LEFT + RING_HEIGHT / 2 - 50 * scale, HEIGHT / 2 - 50 * scale)
    marks = "\n".join('  <path fill="url(#gold)" d="%s"/>' % make_layers.svg_d(s)
                      for s in make_layers.mark(mapping, samples=24))
    for name, colour in TEXT_COLOURS.items():
        svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d">\n%s%s\n'
               '  <path fill="%s" d="%s"/>\n</svg>\n'
               % (WIDTH, HEIGHT, WIDTH, HEIGHT, make_layers.gold_defs(mapping), marks, colour, text_d))
        make_layers.write(os.path.join(HERE, name), svg)


if __name__ == "__main__":
    main(sys.argv[1:])
