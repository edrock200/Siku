# SPDX-License-Identifier: AGPL-3.0-or-later
"""The focused-card look (Silo Android TV #781, CardFocus.brs): a 5% lift by whole px on each side
about the card's top-left corner, so every edge lands on a whole pixel, and points over the card
(calendar badges) that follow it; and FocusText_size, a focused label's size rounded down
(Silo-Server/silo-roku 3fd96f1)."""
import unittest

from brs import check_cases

FILES = ["components/common/CardFocus.brs", "components/common/FocusText.brs"]


def near(expected, tol=0.01):
    def check(v):
        return len(v) == len(expected) and all(abs(a - b) <= tol for a, b in zip(v, expected))
    return check


def transform(scale, translation):
    def check(v):
        return near(scale, 0.0005)(v["scale"]) and near(translation)(v["translation"])
    return check


class CardFocus(unittest.TestCase):
    def test_lift(self):
        f = "CardFocus_lift"
        check_cases(self, FILES, [
            ("row poster 176x264", f, [176, 264], [4, 7]),
            ("landscape card 360x202", f, [360, 202], [9, 5]),
            ("person circle 200x200", f, [200, 200], [5, 5]),
            ("calendar poster 248x372", f, [248, 372], [6, 9]),
        ])

    def test_transform(self):
        f = "CardFocus_transform"
        check_cases(self, FILES, [
            ("at rest the card keeps its place", f, [176, 264, 0, [0, 32]], transform([1, 1], [0, 32])),
            ("focused: 184x278, moved back by the lift", f, [176, 264, 1, [0, 0]],
             transform([184 / 176, 278 / 264], [-4, -7])),
            ("half way", f, [176, 264, 0.5, [0, 20]], transform([180 / 176, 271 / 264], [-2, 16.5])),
            ("no size yet", f, [0, 0, 1, [3, 4]], transform([1, 1], [3, 4])),
        ])

    def test_edges_on_whole_pixels(self):
        # The lifted card's right and bottom edges: translation + size * scale is whole.
        def whole(w, h):
            def check(v):
                r = v["translation"][0] + w * v["scale"][0]
                b = v["translation"][1] + h * v["scale"][1]
                return abs(r - round(r)) < 0.01 and abs(b - round(b)) < 0.01
            return check
        f = "CardFocus_transform"
        check_cases(self, FILES, [
            ("poster", f, [176, 264, 1, [0, 32]], whole(176, 264)),
            ("landscape", f, [360, 202, 1, [0, 20]], whole(360, 202)),
            ("library poster", f, [220, 330, 1, [20, 30]], whole(220, 330)),
        ])

    def test_point(self):
        f = "CardFocus_point"
        check_cases(self, FILES, [
            ("top-left badge at rest", f, [12, 12, 248, 372, 0], near([12, 12])),
            ("top-left badge focused", f, [12, 12, 248, 372, 1], near([-6 + 12 * 260 / 248, -9 + 12 * 390 / 372])),
            ("bottom-right corner focused", f, [248, 372, 248, 372, 1], near([254, 381])),
        ])

    def test_font_size_rounds_down(self):
        f = "FocusText_size"
        check_cases(self, FILES, [
            ("29 px at 1.06 is 30, not 31", f, [29, 1.06], 30),
            ("18 px at 1.03 stays 18", f, [18, 1.03], 18),
            ("25 px at 1.04 is 26 despite single precision", f, [25, 1.04], 26),
            ("27 px at 1.05 is 28", f, [27, 1.05], 28),
            ("38 px at 1.08 is 41", f, [38, 1.08], 41),
        ])


if __name__ == "__main__":
    unittest.main()
