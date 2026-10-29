#!/usr/bin/env python3
"""Generate every vector form of the Clair mark from one geometry.

Writes, relative to resources/icon/:
  AppIcon.icon/Assets/ring.svg, inlay.svg   Icon Composer layers (design D1)
  logo.svg, logo-mono.svg                   in-app product logos (design D5)
  vector_icons/<chromium path>.icon         Chromium vector icons (design D6)

Strokes are outlined to filled shapes: the ring and hairline as exact arcs with
round caps, the curl and flick as sampled curves. Standard library only.

Usage: make_layers.py [--preview OUT_DIR]
  --preview also writes each .icon back out as an SVG, for checking by eye.
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# Geometry in the 100 x 100 drawing space; keep in step with geometry.svg.
RING = dict(cx=50, cy=50, r=32, width=6.4, gap=40)
HAIRLINE = dict(cx=50, cy=50, r=23.5, width=2, gap=40)
CURL = ((74.51, 70.57), (80.43, 66.02), (81.08, 58.22), (75.88, 55.62),
        (71.97, 53.67), (68.07, 56.92), (70.02, 60.43))
FLICK = ((74.51, 29.43), (77.31, 27.87), (79.13, 25.92), (79.39, 23.71))
TERMINAL_WIDTH = 3.6
BEAD = dict(cx=26.5, cy=50, r=2.6)
RING_OUTER = RING["r"] + RING["width"] / 2

GOLD_TOP, GOLD_BOTTOM = "#EBCB7A", "#9A6A1C"
MONO = "#222222"
GOLD_ARGB = (0xFF, 0xC9, 0x95, 0x36)

# Icon Composer's 1024 px canvas is the tile: ring 72% of it, 2% right of centre.
ICON_MAPPING = (10.4727, 9.36, -11.64)

# Chromium vector icons (Chromium 156.0.8078.47): path -> (canvas sizes, coloured)
VECTOR_ICONS = {
    "chrome/app/vector_icons/browser_logo_old.icon": ((16,), False),
    "chrome/app/vector_icons/chrome_product.icon": ((16,), False),
    "components/omnibox/browser/vector_icons/chrome_product.icon": ((24,), False),
    "components/omnibox/browser/vector_icons/product_chrome_refresh_old.icon": ((15,), False),
    "components/omnibox/browser/vector_icons/product_old.icon": ((32, 16), False),
    "components/vector_icons/chromium/product.icon": ((24,), False),
    "components/vector_icons/chromium/product_refresh.icon": ((24,), True),
    "ui/message_center/vector_icons/chrome_product.icon": ((24,), False),
    "ui/message_center/vector_icons/product_old.icon": ((96,), False),
}


def fitted(canvas, fill=1.0):
    """Mapping that centres the ring on a square canvas, ring diameter = fill * canvas."""
    scale = canvas * fill / (2 * RING_OUTER)
    return scale, canvas / 2 - 50 * scale, canvas / 2 - 50 * scale


# A path is a list of commands: ("M", x, y), ("L", x, y),
# ("A", r, large, sweep, x, y) for circular arcs, and ("Z",).

def unit(dx, dy):
    length = math.hypot(dx, dy)
    return dx / length, dy / length


def cap_sweep(start, centre, direction):
    """Sweep flag for the semicircle from start around centre that bulges along direction."""
    # In y-down space a sweep of 1 turns clockwise; that semicircle passes centre + (-v.y, v.x).
    vx, vy = start[0] - centre[0], start[1] - centre[1]
    return 1 if (-vy * direction[0] + vx * direction[1]) > 0 else 0


def ring_path(m, cx, cy, r, width, gap):
    """Open ring from -gap to +gap degrees through the left, with round caps."""
    scale, tx, ty = m
    centre = (tx + scale * cx, ty + scale * cy)
    outer, inner, half = (r + width / 2) * scale, (r - width / 2) * scale, width / 2 * scale
    top, bottom = math.radians(-gap), math.radians(gap)

    def at(radius, angle):
        return centre[0] + radius * math.cos(angle), centre[1] + radius * math.sin(angle)

    # Travel runs from the top end anticlockwise (decreasing angle) to the bottom end.
    end_dir = (math.sin(bottom), -math.cos(bottom))
    start_dir = (-math.sin(top), math.cos(top))
    ob, ib, it, ot = at(outer, bottom), at(inner, bottom), at(inner, top), at(outer, top)
    return [
        ("M",) + ot,
        ("A", outer, 1, 0) + ob,
        ("A", half, 0, cap_sweep(ob, at(r * scale, bottom), end_dir)) + ib,
        ("A", inner, 1, 1) + it,
        ("A", half, 0, cap_sweep(it, at(r * scale, top), start_dir)) + ot,
        ("Z",),
    ]


def bezier_points(controls, samples):
    """Sample a chain of cubic segments given as p0 c1 c2 p1 c1 c2 p2 ..."""
    points = []
    for i in range(0, len(controls) - 1, 3):
        p0, p1, p2, p3 = controls[i:i + 4]
        for step in range(0 if not points else 1, samples + 1):
            t = step / samples
            u = 1 - t
            points.append(tuple(
                u * u * u * p0[k] + 3 * u * u * t * p1[k] + 3 * u * t * t * p2[k] + t * t * t * p3[k]
                for k in (0, 1)))
    return points


def stroke_path(m, controls, width, samples):
    """Outline a sampled curve with round caps at both ends."""
    scale, tx, ty = m
    pts = [(tx + scale * x, ty + scale * y) for x, y in bezier_points(controls, samples)]
    half = width / 2 * scale
    left, right = [], []
    for i, p in enumerate(pts):
        a, b = pts[max(i - 1, 0)], pts[min(i + 1, len(pts) - 1)]
        dx, dy = unit(b[0] - a[0], b[1] - a[1])
        left.append((p[0] - dy * half, p[1] + dx * half))
        right.append((p[0] + dy * half, p[1] - dx * half))
    end_dir = unit(pts[-1][0] - pts[-2][0], pts[-1][1] - pts[-2][1])
    start_dir = unit(pts[0][0] - pts[1][0], pts[0][1] - pts[1][1])
    return ([("M",) + left[0]] + [("L",) + p for p in left[1:]]
            + [("A", half, 0, cap_sweep(left[-1], pts[-1], end_dir)) + right[-1]]
            + [("L",) + p for p in reversed(right[:-1])]
            + [("A", half, 0, cap_sweep(right[0], pts[0], start_dir)) + left[0], ("Z",)])


def circle_path(m, cx, cy, r):
    scale, tx, ty = m
    x, y, radius = tx + scale * cx, ty + scale * cy, r * scale
    return [("M", x - radius, y), ("A", radius, 0, 0, x + radius, y),
            ("A", radius, 0, 0, x - radius, y), ("Z",)]


def mark(m, full=True, samples=96):
    """The mark's shapes: the ring layer, plus the inlay when full."""
    shapes = [ring_path(m, **RING),
              stroke_path(m, CURL, TERMINAL_WIDTH, samples),
              stroke_path(m, FLICK, TERMINAL_WIDTH, samples)]
    if full:
        shapes += [ring_path(m, **HAIRLINE), circle_path(m, **BEAD)]
    return shapes


def num(value, places):
    text = ("%." + str(places) + "f") % value
    text = text.rstrip("0").rstrip(".") if "." in text else text
    return "0" if text in ("-0", "") else text


def svg_d(path):
    out = []
    for c in path:
        if c[0] in "ML":
            out.append("%s%s %s" % (c[0], num(c[1], 2), num(c[2], 2)))
        elif c[0] == "A":
            out.append("A%s %s 0 %d %d %s %s" % (num(c[1], 2), num(c[1], 2), c[2], c[3], num(c[4], 2), num(c[5], 2)))
        else:
            out.append("Z")
    return "".join(out)


def svg(size, shapes, fill, defs=""):
    body = "\n".join('  <path fill="%s" d="%s"/>' % (fill, svg_d(s)) for s in shapes)
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d">\n%s%s\n</svg>\n'
            % (size, size, size, size, defs, body))


def gold_defs(m):
    """Vertical gold gradient spanning the ring's height under mapping m."""
    scale, _, ty = m
    return ('  <defs><linearGradient id="gold" gradientUnits="userSpaceOnUse" x1="0" y1="%s" x2="0" y2="%s">'
            '<stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient></defs>\n'
            % (num(ty + scale * (50 - RING_OUTER), 2), num(ty + scale * (50 + RING_OUTER), 2), GOLD_TOP, GOLD_BOTTOM))


def icon_file(sizes, coloured):
    """A Chromium .icon file with one representation per canvas size."""
    reps = []
    for size in sizes:
        # Below 32 px the hairline would be thinner than a pixel, so only the ring layer is drawn.
        shapes = mark(fitted(size, 0.92), full=size >= 32, samples=12 if size < 32 else 24)
        lines = ["CANVAS_DIMENSIONS, %d," % size]
        for i, shape in enumerate(shapes):
            if i:
                lines.append("NEW_PATH,")
            if coloured:
                lines.append("PATH_COLOR_ARGB, %s," % ", ".join("0x%02X" % v for v in GOLD_ARGB))
            lines.append("FILL_RULE_NONZERO,")
            for c in shape:
                if c[0] == "M":
                    lines.append("MOVE_TO, %s, %s," % (num(c[1], 3), num(c[2], 3)))
                elif c[0] == "L":
                    lines.append("LINE_TO, %s, %s," % (num(c[1], 3), num(c[2], 3)))
                elif c[0] == "A":
                    lines.append("ARC_TO, %s, %s, 0, %d, %d, %s, %s," % (
                        num(c[1], 3), num(c[1], 3), c[2], c[3], num(c[4], 3), num(c[5], 3)))
                else:
                    lines.append("CLOSE,")
        reps.append("\n".join(lines))
    header = ("// Clair product mark. Generated by resources/icon/make_layers.py; do not edit.\n"
              "// Replaces Chromium's file of the same path.\n\n")
    return header + "\n\n".join(reps) + "\n"


def icon_preview(text):
    """Turn a generated .icon file back into an SVG of its first representation."""
    size, paths, fill = None, [""], MONO
    for line in text.splitlines():
        parts = [p.strip() for p in line.rstrip(",").split(",")]
        cmd, args = parts[0], parts[1:]
        if cmd == "CANVAS_DIMENSIONS":
            if size is not None:
                break
            size = int(args[0])
        elif cmd == "PATH_COLOR_ARGB":
            fill = "#%02X%02X%02X" % tuple(int(a, 16) for a in args[1:])
        elif cmd == "NEW_PATH":
            paths.append("")
        elif cmd == "MOVE_TO":
            paths[-1] += "M%s %s" % tuple(args)
        elif cmd == "LINE_TO":
            paths[-1] += "L%s %s" % tuple(args)
        elif cmd == "ARC_TO":
            paths[-1] += "A%s %s %s %s %s %s %s" % tuple(args)
        elif cmd == "CLOSE":
            paths[-1] += "Z"
    body = "".join('<path fill="%s" d="%s"/>' % (fill, p) for p in paths)
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d">%s</svg>\n'
            % (size, size, size, size, body))


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)
    print("wrote", os.path.relpath(path, HERE))


def main(argv):
    preview = argv[argv.index("--preview") + 1] if "--preview" in argv else None

    assets = os.path.join(HERE, "AppIcon.icon", "Assets")
    ring, curl, flick, hairline, bead = mark(ICON_MAPPING)
    write(os.path.join(assets, "ring.svg"), svg(1024, [ring, curl, flick], "#000000"))
    write(os.path.join(assets, "inlay.svg"), svg(1024, [hairline, bead], "#000000"))

    logo = fitted(256, 0.94)
    write(os.path.join(HERE, "logo.svg"), svg(256, mark(logo), "url(#gold)", gold_defs(logo)))
    write(os.path.join(HERE, "logo-mono.svg"), svg(256, mark(logo, full=False), MONO))

    for rel, (sizes, coloured) in sorted(VECTOR_ICONS.items()):
        text = icon_file(sizes, coloured)
        write(os.path.join(HERE, "vector_icons", rel), text)
        if preview:
            name = rel.replace("/", "__").replace(".icon", ".svg")
            write(os.path.join(preview, name), icon_preview(text))


if __name__ == "__main__":
    main(sys.argv[1:])
