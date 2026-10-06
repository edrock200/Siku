"""Generates white 9-patch shapes used to draw rounded UI in SceneGraph.

SceneGraph has no rounded-rectangle primitive, so components use Poster nodes
with these white 9-patch images and tint them with `blendColor`.
Names: images/ui/r{radius}.9.png (fill), images/ui/r{radius}_ring{w}.9.png (outline),
       images/ui/circle.png and images/ui/circle_ring.png (stretched, for round buttons and avatars),
       images/ui/gradient_*.png (scrims), images/ui/mask_*.png (MaskGroup masks).
Run: python3 scripts/make_ui.py
"""
import os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "images", "ui")
SS = 4  # supersampling


def rounded(radius, ring=0, size=None):
    s = size or radius * 2 + 4
    big = Image.new("L", (s * SS, s * SS), 0)
    d = ImageDraw.Draw(big)
    d.rounded_rectangle([0, 0, s * SS - 1, s * SS - 1], radius=radius * SS, fill=255)
    if ring:
        d.rounded_rectangle([ring * SS, ring * SS, s * SS - 1 - ring * SS, s * SS - 1 - ring * SS],
                            radius=max(0, (radius - ring)) * SS, fill=0)
    a = big.resize((s, s), Image.LANCZOS)
    img = Image.new("RGBA", (s, s), (255, 255, 255, 0))
    img.putalpha(a)
    return img


def rounded_rect(w, h, radius):
    big = Image.new("L", (w * SS, h * SS), 0)
    ImageDraw.Draw(big).rounded_rectangle([0, 0, w * SS - 1, h * SS - 1], radius=radius * SS, fill=255)
    img = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    img.putalpha(big.resize((w, h), Image.LANCZOS))
    return img


def ninepatch(img, name):
    """Wraps img with Android 9-patch guides: stretch the single middle row/column."""
    w, h = img.size
    out = Image.new("RGBA", (w + 2, h + 2), (0, 0, 0, 0))
    out.paste(img, (1, 1))
    px = out.load()
    cx, cy = w // 2 + 1, h // 2 + 1
    px[cx, 0] = (0, 0, 0, 255)
    px[0, cy] = (0, 0, 0, 255)
    out.save(os.path.join(OUT, name + ".9.png"))


def circle(size, ring=0):
    big = Image.new("L", (size * SS, size * SS), 0)
    d = ImageDraw.Draw(big)
    d.ellipse([0, 0, size * SS - 1, size * SS - 1], fill=255)
    if ring:
        d.ellipse([ring * SS, ring * SS, size * SS - 1 - ring * SS, size * SS - 1 - ring * SS], fill=0)
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    img.putalpha(big.resize((size, size), Image.LANCZOS))
    return img


def vgradient(w, h, stops, name):
    """stops: list of (pos 0..1, alpha 0..255) for black; top to bottom."""
    img = Image.new("RGBA", (w, h))
    px = img.load()
    for y in range(h):
        t = y / max(1, h - 1)
        for i in range(len(stops) - 1):
            p0, a0 = stops[i]
            p1, a1 = stops[i + 1]
            if p0 <= t <= p1:
                a = a0 + (a1 - a0) * ((t - p0) / max(1e-6, p1 - p0))
                break
        else:
            a = stops[-1][1]
        for x in range(w):
            px[x, y] = (0, 0, 0, int(a))
    img.save(os.path.join(OUT, name))


def hgradient(w, h, stops, name):
    img = Image.new("RGBA", (w, h))
    px = img.load()
    for x in range(w):
        t = x / max(1, w - 1)
        for i in range(len(stops) - 1):
            p0, a0 = stops[i]
            p1, a1 = stops[i + 1]
            if p0 <= t <= p1:
                a = a0 + (a1 - a0) * ((t - p0) / max(1e-6, p1 - p0))
                break
        else:
            a = stops[-1][1]
        for y in range(h):
            px[x, y] = (0, 0, 0, int(a))
    img.save(os.path.join(OUT, name))


def main():
    os.makedirs(OUT, exist_ok=True)
    for r in (6, 8, 12, 14, 16, 20, 22, 26, 28, 30, 32, 38, 40, 42):
        ninepatch(rounded(r), "r%d" % r)
        ninepatch(rounded(r, ring=2), "r%d_ring2" % r)
        ninepatch(rounded(r, ring=4), "r%d_ring4" % r)
    circle(256).save(os.path.join(OUT, "circle.png"))
    circle(256, ring=4).save(os.path.join(OUT, "circle_ring.png"))
    # Mask for MaskGroup: white = visible.
    circle(256).save(os.path.join(OUT, "mask_circle.png"))
    rounded_rect(176, 264, 16).save(os.path.join(OUT, "mask_poster.png"))
    rounded_rect(360, 203, 16).save(os.path.join(OUT, "mask_landscape.png"))
    rounded_rect(300, 300, 16).save(os.path.join(OUT, "mask_square.png"))
    # Scrims (black with alpha), small and stretched by Poster.
    vgradient(4, 256, [(0, 0), (0.4, 77), (1, 140)], "scrim_bottom_player.png")
    vgradient(4, 256, [(0, 0), (0.5, 102), (0.8, 191), (1, 242)], "scrim_bottom.png")
    vgradient(4, 256, [(0, 242), (1, 0)], "scrim_top.png")
    hgradient(256, 4, [(0, 255), (0.3, 230), (0.55, 140), (0.75, 30), (1, 0)], "scrim_left.png")
    # Backdrop masks (white alpha) for the Skyline ambient backdrop.
    img = Image.new("RGBA", (256, 256))
    px = img.load()
    for y in range(256):
        ty = y / 255
        va = 1.0 if ty <= 0.58 else max(0.0, 1 - (ty - 0.58) / 0.42)
        for x in range(256):
            tx = x / 255
            ha = min(1.0, tx / 0.68)
            px[x, y] = (255, 255, 255, int(255 * ha * va))
    img.save(os.path.join(OUT, "mask_backdrop.png"))


if __name__ == "__main__":
    main()
