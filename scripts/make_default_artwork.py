# SPDX-License-Identifier: AGPL-3.0-or-later
"""Renders the missing-artwork backgrounds (images/ui/art_default_*.png).

A title with no poster, cover or still shows a faint glow in Siku's own logo colours on a dark
base, with a small type mark drawn on top by the card (MediaCardItem / DetailEpisodeItem). Roku
has no blur or gradient brush, so the glow is pre-rendered once per aspect ratio and scaled.

Usage: python3 scripts/make_default_artwork.py   (needs Pillow and numpy)
"""
import os

import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "images", "ui")

BASE = (0x16, 0x17, 0x1C)
# Siku's logo: the blue tile and its orange and red dots (images/logo_mark.png).
SIKU_BLUE = (11, 85, 236)
SIKU_ORANGE = (255, 128, 16)
SIKU_RED = (232, 30, 76)

SIZES = {"poster": (240, 360), "landscape": (384, 216), "square": (256, 256)}


def glow(w, h, color, alpha, cx, cy, radius):
    """A radial gradient from `alpha` at (cx, cy) to 0 at `radius`, as (rgb, a) arrays."""
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt((xs + 0.5 - cx) ** 2 + (ys + 0.5 - cy) ** 2) / radius
    a = np.clip(1.0 - d, 0.0, 1.0) * alpha
    rgb = np.empty((h, w, 3), np.float32)
    rgb[:] = color
    return rgb, a


def render(w, h):
    side = max(w, h)
    img = np.empty((h, w, 3), np.float32)
    img[:] = BASE
    # Sized from the longer side so a poster and a still get the same glow, cropped differently.
    for color, alpha, cx, cy, r in [
        (SIKU_BLUE, 0.20, 0, 0, side * 0.75),
        (SIKU_ORANGE, 0.15, w, h, side * 0.6),
        (SIKU_RED, 0.11, w * 0.7, h * 0.3, side * 0.5),
    ]:
        rgb, a = glow(w, h, color, alpha, cx, cy, r)
        img = img * (1 - a[..., None]) + rgb * a[..., None]
    # A little noise keeps 8-bit gradients from banding on a TV.
    img += np.random.default_rng(7).uniform(-0.6, 0.6, img.shape)
    return Image.fromarray(np.clip(img + 0.5, 0, 255).astype(np.uint8), "RGB")


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, (w, h) in SIZES.items():
        path = os.path.join(OUT, "art_default_%s.png" % name)
        render(w, h).save(path, optimize=True)
        print("wrote", path)


if __name__ == "__main__":
    main()
