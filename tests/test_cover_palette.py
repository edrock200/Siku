# SPDX-License-Identifier: AGPL-3.0-or-later
"""CoverPalette.brs (Silo Android #975, Apple's AudioCoverPalette): the audio player's backdrop colours and
accent from the cover's thumbhash.

The reference below decodes a thumbhash with the reference thumbHashToRGBA algorithm (checked byte for byte
against the thumbhash-python package when the vectors were made) and samples it like Android's
AudioCoverPalette.samplePalette. The vectors are thumbhashes of small synthetic covers."""
import unittest

from brs import calls, check_cases

FILES = ["components/common/CoverPalette.brs"]
import math, base64

def ref_decode(hash_b64, w, h):
    s = hash_b64.strip().replace("-", "+").replace("_", "/")
    s += "=" * (-len(s) % 4)
    hb = base64.b64decode(s)
    if len(hb) < 5:
        return None
    h24 = hb[0] | hb[1] << 8 | hb[2] << 16
    h16 = hb[3] | hb[4] << 8
    l_dc = (h24 & 63) / 63
    p_dc = ((h24 >> 6) & 63) / 31.5 - 1
    q_dc = ((h24 >> 12) & 63) / 31.5 - 1
    l_scale = ((h24 >> 18) & 31) / 31
    has_alpha = h24 >> 23
    p_scale = ((h16 >> 3) & 63) / 63
    q_scale = ((h16 >> 9) & 63) / 63
    land = h16 >> 15
    lx = max(3, (5 if has_alpha else 7) if land else h16 & 7)
    ly = max(3, h16 & 7 if land else (5 if has_alpha else 7))
    start = 6 if has_alpha else 5
    idx = [0]
    def chan(nx, ny, scale):
        ac = []
        for cy in range(ny):
            cx = 0 if cy else 1
            while cx * ny < nx * (ny - cy):
                k = start + (idx[0] >> 1)
                if k >= len(hb):
                    raise ValueError("short")
                ac.append((((hb[k] >> ((idx[0] & 1) << 2)) & 15) / 7.5 - 1) * scale)
                idx[0] += 1
                cx += 1
        return ac
    try:
        l_ac = chan(lx, ly, l_scale); p_ac = chan(3, 3, p_scale * 1.25); q_ac = chan(3, 3, q_scale * 1.25)
    except ValueError:
        return None
    out = []
    for y in range(h):
        fy = [math.cos(math.pi / h * (y + 0.5) * c) for c in range(max(ly, 3))]
        for x in range(w):
            fx = [math.cos(math.pi / w * (x + 0.5) * c) for c in range(max(lx, 3))]
            l, p, q = l_dc, p_dc, q_dc
            j = 0
            for cy in range(ly):
                cx = 0 if cy else 1
                while cx * ly < lx * (ly - cy):
                    l += l_ac[j] * fx[cx] * fy[cy] * 2; j += 1; cx += 1
            j = 0
            for cy in range(3):
                cx = 0 if cy else 1
                while cx < 3 - cy:
                    f = fx[cx] * fy[cy] * 2
                    p += p_ac[j] * f; q += q_ac[j] * f; j += 1; cx += 1
            b = l - 2 / 3 * p
            r = (3 * l - b + q) / 2
            g = r - q
            out.append(tuple(max(0.0, min(1.0, v)) for v in (r, g, b)))
    return out


VECTORS = {
    "orange_blue": "0wYGPwYdcWe/RHdkmSilaYd31vFLHb8E",
    "grey": "JAgSBwCHh4iAiIeIiKiIiIiGCAAAAAAA",
    "red_corner": "SEgGHwyQapbQZ4h5iKeGaHiGCQmdkNAJ",
    "teal": "lRYFBwqHh4iAiIeIiHiIiIh3iAd4eH8I",
    "black": "AAgCBwAAAAAAAAAAAAAAAAAAAAAAAAAA",
}


def hexc(c):
    return "0x" + "".join("%02X" % max(0, min(255, int(v * 255 + 0.5))) for v in c) + "FF"


def avg(px, w, x0, y0, x1, y1):
    sel = [px[y * w + x] for y in range(y0, y1) for x in range(x0, x1)]
    return tuple(sum(c[k] for c in sel) / len(sel) for k in range(3))


def sat(c):
    mx = max(c)
    return 0.0 if mx <= 0 else (mx - min(c)) / mx


def dimmed(c):
    lum = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    if lum <= 0.001:
        return (0.05, 0.05, 0.07)
    scale = 0.16 / lum if lum > 0.16 else min(1.6, 0.16 / max(lum, 0.04))
    return tuple(min(1.0, v * scale) for v in c)


def boosted(c):
    mx = max(c)
    if mx <= 0.02:  # Android: 0.001; below one thumbhash brightness step (1/63) is noise
        return None
    if sat(c) <= 0.12:
        return (0.93, 0.93, 0.93)
    out = []
    for v in c:
        b = min(1.0, v * 0.92 / mx)
        out.append(b + (1 - b) * 0.18)
    return tuple(out)


def ref_palette(hash_b64, fallback="0xEDEDEDFF", n=12):
    px = ref_decode(hash_b64, n, n)
    if px is None:
        return None
    hw = n // 2
    quads = [avg(px, n, 0, 0, hw, hw), avg(px, n, hw, 0, n, hw), avg(px, n, 0, hw, hw, n), avg(px, n, hw, hw, n, n)]
    whole = avg(px, n, 0, 0, n, n)
    best = max(quads, key=lambda q: sat(q) * (0.35 + 0.65 * max(q)))  # first of equals, like maxByOrNull
    acc = boosted(best)
    return {"ok": True, "corners": [hexc(dimmed(q)) for q in quads], "center": hexc(dimmed(whole)),
            "accent": hexc(acc) if acc else fallback}


def close_hex(a, b, tol=2):
    """Single-precision BrightScript may land one step off a channel."""
    return all(abs(int(a[i:i + 2], 16) - int(b[i:i + 2], 16)) <= tol for i in (2, 4, 6)) and a[8:] == b[8:]


class Decode(unittest.TestCase):
    def test_grid_matches_reference(self):
        names = list(VECTORS)
        rs = calls(FILES, [{"fn": "CoverPalette_decode", "args": [VECTORS[k], 12, 12]} for k in names])
        for k, r in zip(names, rs):
            with self.subTest(k):
                self.assertTrue(r["ok"], r.get("error"))
                exp = ref_decode(VECTORS[k], 12, 12)
                self.assertEqual(len(r["value"]), 144)
                worst = max(abs(a - b) for got, want in zip(r["value"], exp) for a, b in zip(got, want))
                self.assertLess(worst, 0.002, k)

    def test_unreadable(self):
        c = "CoverPalette_decode"
        check_cases(self, FILES, [
            ("missing", c, [None, 12, 12], None),
            ("not a string", c, [42, 12, 12], None),
            ("too short", c, ["AAgC", 12, 12], None),
            ("cut off before its coefficients", c, ["0wYGPwYdcWe/", 12, 12], None),
            ("base64url without padding decodes", c, ["0wYGPwYdcWe_RHdkmSilaYd31vFLHb8E", 2, 2], lambda v: isinstance(v, list) and len(v) == 4),
        ])


class Palette(unittest.TestCase):
    def test_matches_reference(self):
        names = list(VECTORS)
        rs = calls(FILES, [{"fn": "CoverPalette_fromThumbhash", "args": [VECTORS[k]]} for k in names])
        for k, r in zip(names, rs):
            with self.subTest(k):
                self.assertTrue(r["ok"], r.get("error"))
                got, exp = r["value"], ref_palette(VECTORS[k])
                self.assertTrue(got["ok"])
                self.assertTrue(close_hex(got["accent"], exp["accent"]), (got["accent"], exp["accent"]))
                self.assertTrue(close_hex(got["center"], exp["center"]), (got["center"], exp["center"]))
                for a, b in zip(got["corners"], exp["corners"]):
                    self.assertTrue(close_hex(a, b), (a, b))

    def test_expected_looks(self):
        rs = calls(FILES, [{"fn": "CoverPalette_fromThumbhash", "args": [VECTORS[k], "0x123456FF"]}
                           for k in ("red_corner", "grey", "black")])
        red, grey, black = (r["value"] for r in rs)
        # The vivid bottom-right quadrant gives a red accent.
        r_, g_, b_ = (int(red["accent"][i:i + 2], 16) for i in (2, 4, 6))
        self.assertGreater(r_, g_ + 60)
        self.assertGreater(r_, b_ + 60)
        # A black-and-white cover keeps a light neutral accent instead of inventing a hue.
        self.assertEqual(grey["accent"], "0xEDEDEDFF")
        # A black cover has no colour to take: the caller's accent stays.
        self.assertEqual(black["accent"], "0x123456FF")

    def test_fallback(self):
        c = "CoverPalette_fromThumbhash"
        check_cases(self, FILES, [
            ("no hash keeps the neutral palette", c, [None, "0xABCDEFFF"],
             {"ok": False, "corners": ["0x1A1C26FF", "0x12141FFF", "0x0F0F1AFF", "0x171721FF"], "center": "0x12141CFF",
              "accent": "0xABCDEFFF"}),
            ("an empty hash too", c, [""], lambda v: v["ok"] is False and v["accent"] == "0xEDEDEDFF"),
        ])


if __name__ == "__main__":
    unittest.main()
