"""Generates Siku's channel artwork (icons, splash, logo) with Pillow.

Siku uses its own mark — a rounded play tile with a three-color "speed" stripe —
in Silo's palette. It deliberately does not reproduce the Silo logo.
Run: python3 scripts/make_images.py
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "images")
FONT = "/usr/share/fonts/opentype/inter/Inter-Bold.otf"

BG_TOP = (6, 10, 40)
BG_BOTTOM = (2, 4, 18)
BLUE = (13, 99, 251)
DEEP = (1, 13, 159)
RED = (232, 30, 76)
ORANGE = (255, 128, 16)
WHITE = (245, 246, 250)


def gradient(size, top, bottom):
    w, h = size
    im = Image.new("RGB", size, top)
    d = ImageDraw.Draw(im)
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return im


def mark(size):
    """Square RGBA mark: rounded tile, play triangle, tri-color stripe."""
    s = size * 4  # supersample
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    tile = gradient((s, s), BLUE, DEEP).convert("RGBA")
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 0.24), fill=255)
    im.paste(tile, (0, 0), mask)
    d = ImageDraw.Draw(im)
    # play triangle, slightly right of centre
    cx, cy, r = s * 0.53, s * 0.44, s * 0.24
    d.polygon([(cx - r * 0.8, cy - r), (cx - r * 0.8, cy + r), (cx + r * 0.95, cy)], fill=WHITE)
    # three short stripes under it (motion lines)
    y = s * 0.76
    hgt = s * 0.07
    x0 = s * 0.22
    for i, c in enumerate((BLUE, RED, ORANGE)):
        w = s * (0.14 if i == 0 else 0.17)
        x1 = x0 + w
        col = (120, 170, 255) if i == 0 else c
        d.rounded_rectangle([x0, y, x1, y + hgt], radius=int(hgt / 2), fill=col)
        x0 = x1 + s * 0.04
    return im.resize((size, size), Image.LANCZOS)


def wordmark_width(font, text):
    return font.getbbox(text)[2]


def lockup(canvas, center, mark_size, font_size):
    """Draws mark + 'siku' wordmark centred at `center` on an RGB canvas."""
    font = ImageFont.truetype(FONT, font_size)
    text = "siku"
    gap = int(mark_size * 0.28)
    tw = wordmark_width(font, text)
    total = mark_size + gap + tw
    x = int(center[0] - total / 2)
    y = int(center[1] - mark_size / 2)
    m = mark(mark_size)
    # soft glow
    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle(
        [x - 8, y - 8, x + mark_size + 8, y + mark_size + 8], radius=int(mark_size * 0.3), fill=(13, 99, 251, 90))
    glow = glow.filter(ImageFilter.GaussianBlur(mark_size * 0.15))
    canvas.paste(glow, (0, 0), glow)
    canvas.paste(m, (x, y), m)
    d = ImageDraw.Draw(canvas)
    bbox = font.getbbox(text)
    ty = int(center[1] - (bbox[1] + bbox[3]) / 2)
    d.text((x + mark_size + gap, ty), text, font=font, fill=WHITE)


def poster(w, h, name):
    im = gradient((w, h), BG_TOP, BG_BOTTOM).convert("RGBA")
    lockup(im, (w / 2, h / 2), int(h * 0.32), int(h * 0.23))
    im.convert("RGB").save(os.path.join(OUT, name), optimize=True)


def splash(w, h, name):
    im = gradient((w, h), BG_TOP, BG_BOTTOM).convert("RGBA")
    lockup(im, (w / 2, h / 2), int(h * 0.15), int(h * 0.11))
    im.convert("RGB").save(os.path.join(OUT, name), optimize=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    # Channel poster sizes from the Roku manifest spec.
    poster(540, 405, "channel_poster_fhd.png")
    poster(290, 218, "channel_poster_hd.png")
    poster(246, 140, "channel_poster_sd.png")
    splash(1920, 1080, "splash_fhd.png")
    splash(1280, 720, "splash_hd.png")
    splash(720, 480, "splash_sd.png")
    # In-app logo assets (transparent)
    mark(256).save(os.path.join(OUT, "logo_mark.png"))
    w = Image.new("RGBA", (520, 140), (0, 0, 0, 0))
    lockup(w, (260, 70), 110, 92)
    w.save(os.path.join(OUT, "logo_wordmark.png"))


if __name__ == "__main__":
    main()
