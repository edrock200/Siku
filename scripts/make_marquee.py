"""Renders the first-run "marquee" backdrops (server connect, sign-in, profiles).

Port of the Android TV `MarqueeBackdrop` brand light (android-shared
common/ui/marquee/MarqueeBackdrop.kt): a 3x3 mesh of dimmed brand blue, red and
orange over black, drawn at 48x32 and scaled up, then the screen's scrim on top.
Roku can't animate it cheaply, so each stage is pre-rendered at one phase.

  images/marquee_server.jpg    stage 0, cool blue pool, leading (left) scrim
  images/marquee_bg.jpg        stage 1, sign-in, all three colors, leading scrim
  images/marquee_profiles.jpg  stage 2, warmer and lower, ambient scrim

Run: python3 scripts/make_marquee.py
SPDX-License-Identifier: AGPL-3.0-or-later
"""
import math
import os
import random

from PIL import Image, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "images")
W, H = 48, 32
FULL_W, FULL_H = 1920, 1080

BLUE = (0x00 / 255, 0x34 / 255, 0xFB / 255)
RED = (0xF5 / 255, 0x0B / 255, 0x4F / 255)
ORANGE = (0xFD / 255, 0x74 / 255, 0x03 / 255)
BLACK = (0.0, 0.0, 0.0)


def dimmed(c, amount):
    return tuple(v * (1 - amount) for v in c)


# Row-major 3x3 mesh colors per stage (MarqueeBackdrop.PALETTES).
PALETTES = [
    [dimmed(BLUE, 0.46), dimmed(BLUE, 0.7), dimmed(RED, 0.8),
     dimmed(BLUE, 0.8), dimmed(BLUE, 0.86), dimmed(RED, 0.92),
     BLACK, BLACK, BLACK],
    [dimmed(BLUE, 0.5), dimmed(RED, 0.58), dimmed(ORANGE, 0.58),
     dimmed(BLUE, 0.76), dimmed(RED, 0.74), dimmed(ORANGE, 0.82),
     BLACK, BLACK, BLACK],
    [dimmed(RED, 0.56), dimmed(ORANGE, 0.52), dimmed(BLUE, 0.56),
     dimmed(ORANGE, 0.7), dimmed(RED, 0.66), dimmed(BLUE, 0.72),
     dimmed(BLUE, 0.9), dimmed(RED, 0.9), dimmed(ORANGE, 0.92)],
]
MIDDLE = [0.42, 0.5, 0.6]
CENTER_X = [0.3, 0.55, 0.5]


def lerp(a, b, t):
    return a + (b - a) * t


def smooth(t):
    return t * t * (3 - 2 * t)


def sample(mesh, u, v):
    gx = min(u * 2, 1.9999)
    gy = min(v * 2, 1.9999)
    cx, cy = int(gx), int(gy)
    fx, fy = smooth(gx - cx), smooth(gy - cy)
    out = []
    for ch in range(3):
        tl = mesh[cy * 3 + cx][ch]
        tr = mesh[cy * 3 + cx + 1][ch]
        bl = mesh[(cy + 1) * 3 + cx][ch]
        br = mesh[(cy + 1) * 3 + cx + 1][ch]
        out.append(lerp(lerp(tl, tr, fx), lerp(bl, br, fx), fy))
    return out


def brand_light(stage, phase=6.0):
    mesh = PALETTES[stage]
    a = math.sin(phase / 13)
    b = math.cos(phase / 19)
    middle = MIDDLE[stage]
    top_x = 0.5 + 0.12 * a
    bottom_x = 0.5 - 0.1 * b
    left_y = middle + 0.06 * b
    right_y = middle - 0.06 * a
    c_x = CENTER_X[stage] + 0.1 * b
    c_y = middle - 0.08 * a
    img = Image.new("RGB", (W, H))
    px = img.load()
    for py in range(H):
        y = (py + 0.5) / H
        for pxx in range(W):
            x = (pxx + 0.5) / W
            row_y = lerp(left_y, c_y, x / c_x) if x < c_x else lerp(c_y, right_y, (x - c_x) / (1 - c_x))
            col_x = lerp(top_x, c_x, y / row_y) if y < row_y else lerp(c_x, bottom_x, (y - row_y) / (1 - row_y))
            u = 0.5 * x / col_x if x < col_x else 0.5 + 0.5 * (x - col_x) / (1 - col_x)
            v = 0.5 * y / row_y if y < row_y else 0.5 + 0.5 * (y - row_y) / (1 - row_y)
            r, g, bb = sample(mesh, min(max(u, 0), 1), min(max(v, 0), 1))
            px[pxx, py] = (int(r * 255 + 0.5), int(g * 255 + 0.5), int(bb * 255 + 0.5))
    return img


def gradient_alpha(stops, t):
    for (t0, a0), (t1, a1) in zip(stops, stops[1:]):
        if t <= t1:
            if t1 == t0:
                return a1
            return lerp(a0, a1, (min(max(t, t0), t1) - t0) / (t1 - t0))
    return stops[-1][1]


LEADING_H = [(0.0, 0.8), (0.3, 0.55), (0.58, 0.2), (0.8, 0.1), (1.0, 0.3)]
LEADING_V = [(0.0, 0.0), (0.65, 0.0), (1.0, 0.5)]
AMBIENT_V = [(0.0, 0.35), (0.25, 0.2), (0.55, 0.75), (0.78, 1.0), (1.0, 1.0)]


def apply_scrim(img, style):
    # Built at 1/8 scale, then smoothly upscaled: the scrim is a pure gradient.
    sw, sh = FULL_W // 8, FULL_H // 8
    mask = Image.new("L", (sw, sh))
    mp = mask.load()
    for y in range(sh):
        ty = (y + 0.5) / sh
        for x in range(sw):
            tx = (x + 0.5) / sw
            if style == "leading":
                a1 = gradient_alpha(LEADING_H, tx)
                a2 = gradient_alpha(LEADING_V, ty)
                alpha = 1 - (1 - a1) * (1 - a2)
            else:
                alpha = gradient_alpha(AMBIENT_V, ty)
            mp[x, y] = int(alpha * 255 + 0.5)
    mask = mask.resize((FULL_W, FULL_H), Image.BICUBIC)
    black = Image.new("RGB", (FULL_W, FULL_H), (0, 0, 0))
    return Image.composite(black, img, mask)


def add_grain(img, amount=0.012, seed=7):
    # Light per-pixel film grain (Android: 4.5% white noise), mainly to stop banding.
    # Kept fainter than Android's so the JPEG stays small.
    rnd = random.Random(seed)
    noise = Image.new("L", (FULL_W, FULL_H))
    noise.putdata([rnd.randint(0, 255) for _ in range(FULL_W * FULL_H)])
    white = Image.new("RGB", (FULL_W, FULL_H), (255, 255, 255))
    mask = noise.point(lambda v: int(v * amount))
    return Image.composite(white, img, mask)


def render(stage, style, name):
    light = brand_light(stage).resize((FULL_W, FULL_H), Image.BICUBIC)
    light = light.filter(ImageFilter.GaussianBlur(24))
    out = apply_scrim(light, style)
    out = add_grain(out)
    path = os.path.join(OUT, name)
    out.save(path, "JPEG", quality=80, optimize=True, progressive=False)
    print(name, os.path.getsize(path) // 1024, "KB")


def main():
    render(0, "leading", "marquee_server.jpg")
    render(1, "leading", "marquee_bg.jpg")
    render(2, "ambient", "marquee_profiles.jpg")


if __name__ == "__main__":
    main()
