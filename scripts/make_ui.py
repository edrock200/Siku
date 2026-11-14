"""Generates white 9-patch shapes used to draw rounded UI in SceneGraph.

SceneGraph has no rounded-rectangle primitive, so components use Poster nodes
with these white 9-patch images and tint them with `blendColor`.
Names: images/ui/r{radius}.9.png (fill), images/ui/r{radius}_ring{w}.9.png (outline),
       images/ui/circle.png and images/ui/circle_ring.png (stretched, for round buttons and avatars),
       images/ui/gradient_*.png (scrims), images/ui/mask_*.png (MaskGroup masks).
Run: python3 scripts/make_ui.py
"""
import os
from PIL import Image, ImageDraw, ImageFilter

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


def card_shadow():
    """A focused card's drop shadow (Silo Android TV #781, tvOS TVCardOutline): white, tinted black
    by blendColor. A radius-16 card blurred 8 px, with 24 px around it for the blur; MediaCardItem
    draws it 48 px larger than the card and 10 px lower (images/ui/card_shadow.9.png). The round
    one, for people, is a 200 px circle in a 248 px image (images/ui/card_shadow_circle.png)."""
    pad, r, blur = 24, 16, 8
    # 24 px of flat middle keeps the blur off the stretched centre row and column.
    s = 2 * (pad + r) + 24
    big = Image.new("L", (s * SS, s * SS), 0)
    ImageDraw.Draw(big).rounded_rectangle([pad * SS, pad * SS, (s - pad) * SS - 1, (s - pad) * SS - 1],
                                          radius=r * SS, fill=255)
    a = big.resize((s, s), Image.LANCZOS).filter(ImageFilter.GaussianBlur(blur))
    img = Image.new("RGBA", (s, s), (255, 255, 255, 0))
    img.putalpha(a)
    ninepatch(img, "card_shadow")
    d = 200
    s = d + 2 * pad
    big = Image.new("L", (s * SS, s * SS), 0)
    ImageDraw.Draw(big).ellipse([pad * SS, pad * SS, (s - pad) * SS - 1, (s - pad) * SS - 1], fill=255)
    a = big.resize((s, s), Image.LANCZOS).filter(ImageFilter.GaussianBlur(blur))
    img = Image.new("RGBA", (s, s), (255, 255, 255, 0))
    img.putalpha(a)
    img.save(os.path.join(OUT, "card_shadow_circle.png"))
    # The focus outline of a 200 px person circle: 4 px, as r16_ring4 on the other cards.
    circle(200, ring=4).save(os.path.join(OUT, "card_ring_circle.png"))


def progress_bar():
    """The watch-progress keyline bar on card art (Silo Android #902 WatchProgressBar, the web's
    and Apple's bar), 8 px tall (Android TV's 4 dp), as two 9-patches drawn by
    components/common/WatchProgress.brs:
    - progress_track: the black 55% capsule with a 2 px black 35% keyline and a soft drop shadow
      (capsules 2/4/6 px out at 12/8/5%, 2 px lower) outside it, all black, so the alpha carries
      the shades; tinted 0x000000FF. PAD px of room on every side for the shadow.
    - progress_fill: the near-white (#EDEDED) fill with a 1 px black 40% hairline outside it,
      drawn in its own colours (blendColor white), 1 px of room on every side."""
    h, r, pad, mid = 8, 4, 8, 1
    w = 2 * r + mid
    W, H = w + 2 * pad, h + 2 * pad

    def capsule(x0, y0, x1, y1, rad):
        m = Image.new("L", (W * SS, H * SS), 0)
        ImageDraw.Draw(m).rounded_rectangle([x0 * SS, y0 * SS, x1 * SS - 1, y1 * SS - 1], radius=rad * SS, fill=255)
        return m.resize((W, H), Image.LANCZOS)

    track = capsule(pad, pad, pad + w, pad + h, r)
    alpha = [0.0] * (W * H)

    def over(mask, a, outside_only):
        tp, mp = track.load(), mask.load()
        for y in range(H):
            for x in range(W):
                cov = mp[x, y] / 255.0
                if outside_only:
                    cov *= 1 - tp[x, y] / 255.0
                src = a * cov
                i = y * W + x
                alpha[i] = src + alpha[i] * (1 - src)

    for spread, a in ((1, 0.12), (2, 0.08), (3, 0.05)):
        s2 = spread * 2
        over(capsule(pad - s2, pad - s2 + 2, pad + w + s2, pad + h + s2 + 2, r + s2), a, True)
    over(capsule(pad - 2, pad - 2, pad + w + 2, pad + h + 2, r + 2), 0.35, True)
    over(track, 0.55, False)
    img = Image.new("RGBA", (W, H), (255, 255, 255, 0))
    img.putalpha(Image.frombytes("L", (W, H), bytes(int(round(a * 255)) for a in alpha)))
    ninepatch(img, "progress_track")

    fw, fh = w + 2, h + 2
    big = Image.new("RGBA", (fw * SS, fh * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    d.rounded_rectangle([0, 0, fw * SS - 1, fh * SS - 1], radius=(r + 1) * SS, fill=(0, 0, 0, 102))
    d.rounded_rectangle([SS, SS, (fw - 1) * SS - 1, (fh - 1) * SS - 1], radius=r * SS, fill=(0xED, 0xED, 0xED, 255))
    ninepatch(big.resize((fw, fh), Image.LANCZOS), "progress_fill")


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
    card_shadow()
    progress_bar()


if __name__ == "__main__":
    main()
