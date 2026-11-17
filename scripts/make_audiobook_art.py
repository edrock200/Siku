"""Generates the audiobook detail and player artwork (Silo Android #975 port).

  images/ui/ring/ring_01.png ... ring_36.png  the listening-state progress ring (112 px, an 8 px white
                                               arc from 12 o'clock, clockwise, round caps; ring_36 is the
                                               whole ring, also drawn tinted as the track)
  images/ui/glow.png                          a white radial glow (alpha 1, 0.55 at 55 %, 0 at the edge),
                                               tinted with blendColor for the player's cover colours
  images/ui/audiobook_hero_scrim.png           the detail hero's teal glow and dark gradient baked into one
                                               layer (tvOS TVAudiobookBackdrop), stretched to 1920x860
  images/ui/scrim_audio_player.png             the player's legibility scrim (black 20 % -> 5 % -> 55 %)
Roku cannot draw arcs or gradients, so they are pictures. Run: python3 scripts/make_audiobook_art.py
SPDX-License-Identifier: AGPL-3.0-or-later
"""
import math
import os
from PIL import Image, ImageDraw

UI = os.path.join(os.path.dirname(__file__), "..", "images", "ui")
SS = 4
RING_STEPS = 36
PAGE = (0x04, 0x0D, 0x0F)  # AudioDetailScreen's page surface


def ring(fraction, size=112, stroke=8):
    s = size * SS
    big = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(big)
    w = stroke * SS
    inset = w / 2
    box = [inset, inset, s - 1 - inset, s - 1 - inset]
    start = -90.0
    end = start + 360.0 * fraction
    if fraction >= 1.0:
        d.ellipse([0, 0, s - 1, s - 1], fill=255)
        d.ellipse([w, w, s - 1 - w, s - 1 - w], fill=0)
    else:
        d.arc([0, 0, s - 1, s - 1], start, end, fill=255, width=w)
        r = (s - w) / 2
        c = s / 2
        for ang in (start, end):
            x = c + r * math.cos(math.radians(ang))
            y = c + r * math.sin(math.radians(ang))
            d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=255)
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    img.putalpha(big.resize((size, size), Image.LANCZOS))
    return img


def glow(size=128):
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    px = img.load()
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            t = min(1.0, math.hypot(x - c, y - c) / c)
            a = 1.0 - t * (0.45 / 0.55) if t <= 0.55 else 0.55 * (1.0 - (t - 0.55) / 0.45)
            px[x, y] = (255, 255, 255, int(round(255 * max(0.0, a))))
    return img


def lerp(a, b, t):
    return a + (b - a) * t


def stops_at(stops, t):
    for i in range(len(stops) - 1):
        p0, c0 = stops[i]
        p1, c1 = stops[i + 1]
        if t <= p1:
            u = 0.0 if p1 == p0 else (t - p0) / (p1 - p0)
            return tuple(lerp(c0[k], c1[k], u) for k in range(4))
    return stops[-1][1]


def hero_scrim(w=192, h=86, full_w=1920, full_h=860):
    teal = (0.07, 0.25, 0.235)
    cx, cy, radius = 0.22 * full_w, 0.40 * full_h, 1200.0
    page = tuple(v / 255.0 for v in PAGE)
    grad = [(0.0, (0, 0, 0, 0.35)), (0.50, (0, 0, 0, 0.72)), (0.86, (0, 0, 0, 0.90)), (1.0, page + (1.0,))]
    img = Image.new("RGBA", (w, h))
    px = img.load()
    for y in range(h):
        fy = (y + 0.5) / h
        gr, gg, gb, ga = stops_at(grad, fy)
        for x in range(w):
            fx = (x + 0.5) / w
            t = min(1.0, math.hypot(fx * full_w - cx, fy * full_h - cy) / radius)
            # Compose interpolates the glow toward Color.Transparent (black, alpha 0) unpremultiplied.
            cr, cg, cb = (teal[k] * (1 - t) for k in range(3))
            ca = 0.9 * (1 - t)
            a = ga + ca * (1 - ga)
            if a <= 0:
                px[x, y] = (0, 0, 0, 0)
                continue
            r = (gr * ga + cr * ca * (1 - ga)) / a
            g = (gg * ga + cg * ca * (1 - ga)) / a
            b = (gb * ga + cb * ca * (1 - ga)) / a
            px[x, y] = tuple(int(round(255 * min(1.0, max(0.0, v)))) for v in (r, g, b, a))
    return img


def player_scrim(h=128):
    stops = [(0.0, (0, 0, 0, 0.20)), (0.35, (0, 0, 0, 0.05)), (1.0, (0, 0, 0, 0.55))]
    img = Image.new("RGBA", (4, h))
    px = img.load()
    for y in range(h):
        a = stops_at(stops, (y + 0.5) / h)[3]
        for x in range(4):
            px[x, y] = (0, 0, 0, int(round(255 * a)))
    return img


def main():
    os.makedirs(os.path.join(UI, "ring"), exist_ok=True)
    for i in range(1, RING_STEPS + 1):
        ring(i / RING_STEPS).save(os.path.join(UI, "ring", "ring_%02d.png" % i), optimize=True)
    glow().save(os.path.join(UI, "glow.png"), optimize=True)
    hero_scrim().save(os.path.join(UI, "audiobook_hero_scrim.png"), optimize=True)
    player_scrim().save(os.path.join(UI, "scrim_audio_player.png"), optimize=True)
    print("wrote %d ring steps, glow, hero scrim, player scrim" % RING_STEPS)


if __name__ == "__main__":
    main()
