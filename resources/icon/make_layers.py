#!/usr/bin/env python3
"""Write the Icon Composer layer SVGs for the Clair mark.

Icon Composer layers are filled shapes, so this outlines the strokes of
geometry.svg: the ring and hairline as exact arcs with round caps, and the
curl and flick as densely sampled curves. Standard library only.

Usage: make_layers.py [ASSETS_DIR]   (default: AppIcon.icon/Assets next to this file)
"""

import math
import os
import sys

# Drawing space (100 x 100) to Icon Composer's 1024 px canvas, which is the
# icon tile itself; see geometry.svg.
SCALE = 10.4727
TX, TY = 9.36, -11.64

RING = dict(cx=50, cy=50, r=32, width=6.4, gap=40)
HAIRLINE = dict(cx=50, cy=50, r=23.5, width=2, gap=40)
CURL = ((74.51, 70.57), (80.43, 66.02), (81.08, 58.22), (75.88, 55.62),
        (71.97, 53.67), (68.07, 56.92), (70.02, 60.43))
CURL_WIDTH = 3.6
FLICK = ((74.51, 29.43), (77.31, 27.87), (79.13, 25.92), (79.39, 23.71))
FLICK_WIDTH = 3.6
BEAD = dict(cx=26.5, cy=50, r=2.6)

SAMPLES_PER_SEGMENT = 96


def canvas(x, y):
    return TX + SCALE * x, TY + SCALE * y


def fmt(point):
    return "%.2f %.2f" % point


def cap(start, end, centre, direction, radius):
    """Semicircle from start to end around centre, bulging along direction."""
    # In SVG's y-down space a sweep-flag of 1 turns clockwise; the clockwise
    # semicircle from start passes through centre + (-v.y, v.x).
    vx, vy = start[0] - centre[0], start[1] - centre[1]
    sweep = 1 if (-vy * direction[0] + vx * direction[1]) > 0 else 0
    return "A%.2f %.2f 0 0 %d %s" % (radius, radius, sweep, fmt(end))


def ring_path(cx, cy, r, width, gap):
    """Open ring from -gap to +gap degrees through the left, with round caps."""
    half = width / 2
    centre = canvas(cx, cy)
    outer, inner, half_c = (r + half) * SCALE, (r - half) * SCALE, half * SCALE
    top, bottom = math.radians(-gap), math.radians(gap)

    def at(radius, angle):
        return centre[0] + radius * math.cos(angle), centre[1] + radius * math.sin(angle)

    def mid(angle):
        return at(r * SCALE, angle)

    # Travel runs from the top end anticlockwise (decreasing angle) to the bottom end.
    end_dir = (math.sin(bottom), -math.cos(bottom))
    start_dir = (-math.sin(top), math.cos(top))
    return "".join([
        "M", fmt(at(outer, top)),
        "A%.2f %.2f 0 1 0 %s" % (outer, outer, fmt(at(outer, bottom))),
        cap(at(outer, bottom), at(inner, bottom), mid(bottom), end_dir, half_c),
        "A%.2f %.2f 0 1 1 %s" % (inner, inner, fmt(at(inner, top))),
        cap(at(inner, top), at(outer, top), mid(top), start_dir, half_c),
        "Z",
    ])


def bezier_points(controls):
    """Sample a chain of cubic segments given as p0 c1 c2 p1 c1 c2 p2 ..."""
    points = []
    for i in range(0, len(controls) - 1, 3):
        p0, p1, p2, p3 = controls[i:i + 4]
        for step in range(SAMPLES_PER_SEGMENT + 1):
            if points and step == 0:
                continue
            t = step / SAMPLES_PER_SEGMENT
            u = 1 - t
            points.append(tuple(
                u * u * u * p0[k] + 3 * u * u * t * p1[k] + 3 * u * t * t * p2[k] + t * t * t * p3[k]
                for k in (0, 1)))
    return points


def unit(dx, dy):
    length = math.hypot(dx, dy)
    return dx / length, dy / length


def stroke_path(controls, width):
    """Outline a sampled curve with round caps at both ends."""
    pts = [canvas(*p) for p in bezier_points(controls)]
    half = width / 2 * SCALE
    left, right = [], []
    for i, p in enumerate(pts):
        a, b = pts[max(i - 1, 0)], pts[min(i + 1, len(pts) - 1)]
        tx, ty = unit(b[0] - a[0], b[1] - a[1])
        nx, ny = -ty, tx
        left.append((p[0] + nx * half, p[1] + ny * half))
        right.append((p[0] - nx * half, p[1] - ny * half))
    end_dir = unit(pts[-1][0] - pts[-2][0], pts[-1][1] - pts[-2][1])
    start_dir = unit(pts[0][0] - pts[1][0], pts[0][1] - pts[1][1])
    return "".join(
        ["M", fmt(left[0])]
        + ["L" + fmt(p) for p in left[1:]]
        + [cap(left[-1], right[-1], pts[-1], end_dir, half)]
        + ["L" + fmt(p) for p in reversed(right[:-1])]
        + [cap(right[0], left[0], pts[0], start_dir, half), "Z"])


def circle_path(cx, cy, r):
    x, y = canvas(cx, cy)
    radius = r * SCALE
    return "M%.2f %.2fA%.2f %.2f 0 1 0 %.2f %.2fA%.2f %.2f 0 1 0 %.2f %.2fZ" % (
        x - radius, y, radius, radius, x + radius, y, radius, radius, x - radius, y)


def svg(paths):
    body = "\n".join('  <path fill="#000000" d="%s"/>' % d for d in paths)
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" '
            'width="1024" height="1024">\n%s\n</svg>\n' % body)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "AppIcon.icon", "Assets")
    os.makedirs(out, exist_ok=True)
    layers = {
        "ring.svg": [ring_path(**RING), stroke_path(CURL, CURL_WIDTH), stroke_path(FLICK, FLICK_WIDTH)],
        "inlay.svg": [ring_path(**HAIRLINE), circle_path(**BEAD)],
    }
    for name, paths in layers.items():
        with open(os.path.join(out, name), "w") as f:
            f.write(svg(paths))
        print("wrote", os.path.join(out, name))


if __name__ == "__main__":
    main()
