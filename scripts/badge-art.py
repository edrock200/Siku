#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Write the card overlay badges' glyphs into images/badges/ (components/tasks/
OverlayDraw.brs; silo-server docs/architecture/card-overlays.md). Adapted from
Silo-Server/silo-roku, AGPL-3.0 (scripts/badge-art.py, commit e8244ee).

  <glyph>.png        the badges' 24-unit glyphs at 2 px per unit (48 px),
                     2-unit round-capped strokes, white for a tint:
                     monitor, volume, film, layout, languages, subtitles,
                     shield, users, clock, globe, building, tv; and
                     dolby_vision, a ring with the right half of its middle
                     filled, as the web's inline mark draws it

OverlayArtTask scales each into a card's overlay image; fills, borders, and
scrims it draws itself. Shapes are plain geometry, not brand
assets or a copied icon set. Edges are antialiased by supersampling. Uses
only the standard library, so the pixels are the same on every machine. Run
from anywhere: python3 scripts/badge-art.py
"""
import math
import pathlib
import struct
import zlib

WHITE = (0xFF, 0xFF, 0xFF)
GLYPH_UNITS = 24
GLYPH_SCALE = 2
STROKE = 2.0  # glyph units
SAMPLES = 8


def coverage(width, height, covered, scale=1):
    rows = []
    for py in range(height * scale):
        row = []
        for px in range(width * scale):
            hits = sum(
                covered((px + (sx + 0.5) / SAMPLES) / scale, (py + (sy + 0.5) / SAMPLES) / scale)
                for sy in range(SAMPLES) for sx in range(SAMPLES))
            row.append(round(255 * hits / SAMPLES ** 2))
        rows.append(row)
    return rows


def box_distance(x, y, left, top, right, bottom, radii):
    """Signed distance to a rectangle with per-corner radii (top left, top
    right, bottom right, bottom left), negative inside."""
    cx, cy = (left + right) / 2, (top + bottom) / 2
    if x < cx:
        radius = radii[0] if y < cy else radii[3]
    else:
        radius = radii[1] if y < cy else radii[2]
    qx = abs(x - cx) - ((right - left) / 2 - radius)
    qy = abs(y - cy) - ((bottom - top) / 2 - radius)
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - radius


# --- Glyphs, in 24 units ------------------------------------------------

def segment_distance(x, y, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    length = dx * dx + dy * dy
    t = 0.0 if length == 0 else max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / length))
    return math.hypot(x - ax - t * dx, y - ay - t * dy)


def polyline(*points):
    return [(a, b) for a, b in zip(points, points[1:])]


def rect(left, top, right, bottom, radius):
    return ("box", (left, top, right, bottom, radius))


def arc(cx, cy, r, start, end, steps=24):
    """Points along a circle from start to end degrees (0 at three o'clock,
    clockwise in screen coordinates)."""
    return [(cx + r * math.cos(math.radians(start + (end - start) * i / steps)),
             cy + r * math.sin(math.radians(start + (end - start) * i / steps))) for i in range(steps + 1)]


def stroked(parts):
    """A predicate over strokes: segments (pairs of points), ("box", ...)
    rounded rectangles, ("circle", (cx, cy, r)) and ("ellipse", (cx, cy, rx,
    ry)) outlines."""
    half = STROKE / 2

    def covered(x, y):
        for part in parts:
            if part[0] == "box":
                left, top, right, bottom, radius = part[1]
                if abs(box_distance(x, y, left, top, right, bottom, (radius,) * 4)) <= half:
                    return True
            elif part[0] == "circle":
                cx, cy, r = part[1]
                if abs(math.hypot(x - cx, y - cy) - r) <= half:
                    return True
            elif part[0] == "ellipse":
                cx, cy, rx, ry = part[1]
                # Distance to the ellipse, approximated by scaling to a circle.
                k = math.hypot((x - cx) / rx, (y - cy) / ry)
                gradient = math.hypot((x - cx) / rx ** 2, (y - cy) / ry ** 2)
                if gradient > 0 and abs(k - 1) * k / gradient <= half:
                    return True
            elif segment_distance(x, y, *part[0], *part[1]) <= half:
                return True
        return False
    return covered


def glyph(parts):
    size = GLYPH_UNITS
    alpha = coverage(size, size, stroked(parts), GLYPH_SCALE)
    return [[WHITE + (a,) for a in line] for line in alpha]


GLYPHS = {
    "monitor": [rect(2, 3, 22, 17, 2), ((12, 17), (12, 21)), ((8, 21), (16, 21))],
    "volume": polyline((11, 5), (6, 9), (2, 9), (2, 15), (6, 15), (11, 19), (11, 5))
    + polyline(*arc(11, 12, 4.5, -45, 45)) + polyline(*arc(11, 12, 8.5, -50, 50)),
    "film": [rect(3, 3, 21, 21, 2), ((7, 3), (7, 21)), ((17, 3), (17, 21)), ((3, 12), (21, 12)),
             ((3, 7.5), (7, 7.5)), ((3, 16.5), (7, 16.5)), ((17, 7.5), (21, 7.5)), ((17, 16.5), (21, 16.5))],
    "layout": [rect(3, 3, 21, 10, 1), rect(3, 14, 10, 21, 1), rect(14, 14, 21, 21, 1)],
    "languages": [((2, 5), (12, 5)), ((7, 2), (7, 5)), ((4, 9), (10, 15)), ((10, 5), (4, 14)),
                  ((12, 21), (17, 9)), ((17, 9), (22, 21)), ((14, 17), (20, 17))],
    "subtitles": [rect(2, 5, 22, 19, 2), ((6.5, 10), (10.5, 10)), ((13.5, 10), (17.5, 10)),
                  ((6.5, 14), (13.5, 14)), ((16.5, 14), (17.5, 14))],
    "shield": polyline((12, 22), (8.5, 20.2), (5.6, 17.2), (4, 13), (4, 5.5), (12, 2.5), (20, 5.5),
                       (20, 13), (18.4, 17.2), (15.5, 20.2), (12, 22)),
    "users": [("circle", (9, 7, 4))] + polyline((2, 21), (2, 19), *arc(6, 19, 4, 180, 270), (12, 15),
                                                *arc(12, 19, 4, 270, 360), (16, 21))
    + polyline(*arc(15, 7, 4, -80, 80)) + polyline(*arc(18, 19, 4, 290, 360), (22, 21)),
    "clock": [("circle", (12, 12, 10)), ((12, 6), (12, 12)), ((12, 12), (16, 14))],
    "globe": [("circle", (12, 12, 10)), ((2, 12), (22, 12)), ("ellipse", (12, 12, 4.2, 10))],
    "building": [rect(6, 2, 18, 22, 2), ((6, 12), (2, 12)), ((2, 12), (2, 22)), ((2, 22), (6, 22)),
                 ((18, 9), (22, 9)), ((22, 9), (22, 22)), ((22, 22), (18, 22)),
                 ((10, 6), (14, 6)), ((10, 10), (14, 10)), ((10, 14), (14, 14)), ((10, 18), (14, 18))],
    "tv": [rect(2, 7, 22, 20, 2), ((7, 2), (12, 7)), ((12, 7), (17, 2))],
}


def dolby_vision():
    """In 16 units: a ring from radius 4.5 to 6 and the right half of the
    middle disc."""
    scale = 3

    def covered(x, y):
        d = math.hypot(x - 8, y - 8)
        return 4.5 <= d <= 6 or (d <= 4.5 and x >= 8)
    alpha = coverage(16, 16, covered, scale)
    return [[WHITE + (a,) for a in line] for line in alpha]


def png(rows):
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))

    height, width = len(rows), len(rows[0])
    raw = b"".join(b"\x00" + bytes(channel for pixel in row for channel in pixel) for row in rows)
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


def images():
    for name, parts in GLYPHS.items():
        yield f"{name}.png", glyph(parts)
    yield "dolby_vision.png", dolby_vision()


def main():
    out = pathlib.Path(__file__).resolve().parent.parent / "images" / "badges"
    out.mkdir(parents=True, exist_ok=True)
    for name, rows in images():
        (out / name).write_bytes(png(rows))
        print(f"images/badges/{name}  {len(rows[0])}x{len(rows)}")


if __name__ == "__main__":
    main()
